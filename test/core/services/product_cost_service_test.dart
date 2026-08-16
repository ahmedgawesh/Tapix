import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/purchase_dao.dart';
import 'package:tapix/core/services/inventory/product_cost_service.dart';

/// Tests for [ProductCostService].
///
/// Two layers:
///   1. **Pure math** — no database, exercises `resolvePurchaseCostForTest`
///      across every costing method and edge case.
///   2. **Integration** — uses an in-memory Drift DB to verify that the
///      parent `products.cost_cents` aggregation is a true weighted
///      average (and NOT the legacy `MAX(cost_cents)` that caused the
///      production bug the user reported).
void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // PURE MATH — resolvePurchaseCostForTest
  // ═══════════════════════════════════════════════════════════════════════════

  group('ProductCostService — WAC math', () {
    test('collapses to new paid cost when prior stock is zero', () {
      // User scenario: first-ever purchase of a brand-new variant. There is
      // no prior stock to blend into, so the WAC formula MUST return the
      // new paid cost exactly (no rounding drift).
      expect(
        ProductCostService.resolvePurchaseCostForTest(
          beforeQty: 0,
          beforeCostCents: 0,
          addedQty: 10,
          newPaidCostCents: 6500,
          costingMethod: ProductCostService.methodWac,
        ),
        6500,
      );
    });

    test('classic 2-lot blend: (50×3 + 60×1) / 4 = 52.50¢ rounds to 5250', () {
      // Textbook moving-average example. 3 units @ $50, add 1 unit @ $60:
      //   (5000×3 + 6000×1) / 4 = 21000/4 = 5250
      expect(
        ProductCostService.resolvePurchaseCostForTest(
          beforeQty: 3,
          beforeCostCents: 5000,
          addedQty: 1,
          newPaidCostCents: 6000,
          costingMethod: ProductCostService.methodWac,
        ),
        5250,
      );
    });

    test('user-reported regression: 60→65 blend stays inside [60, 65]', () {
      // The user complaint: after a 60 PO followed by a 65 PO the displayed
      // cost dropped to 55.63 — impossible if the math were correct. This
      // regression locks the invariant that WAC never produces a value
      // outside the range of its inputs.
      //
      // 1 unit @ 60, add 1 unit @ 65 → (6000 + 6500) / 2 = 6250 (= 62.50¢).
      final blended = ProductCostService.resolvePurchaseCostForTest(
        beforeQty: 1,
        beforeCostCents: 6000,
        addedQty: 1,
        newPaidCostCents: 6500,
        costingMethod: ProductCostService.methodWac,
      );
      expect(blended, 6250);
      expect(blended, inInclusiveRange(6000, 6500));
    });

    test('larger-lot dilution: 1 unit @ 65 added to 9 units @ 60 → 6050', () {
      //   (6000×9 + 6500×1) / 10 = 60500/10 = 6050 (= $60.50)
      expect(
        ProductCostService.resolvePurchaseCostForTest(
          beforeQty: 9,
          beforeCostCents: 6000,
          addedQty: 1,
          newPaidCostCents: 6500,
          costingMethod: ProductCostService.methodWac,
        ),
        6050,
      );
    });

    test('rounding: half-away-from-zero', () {
      // (1000×1 + 1001×1) / 2 = 1000.5 → rounds to 1001
      expect(
        ProductCostService.resolvePurchaseCostForTest(
          beforeQty: 1,
          beforeCostCents: 1000,
          addedQty: 1,
          newPaidCostCents: 1001,
          costingMethod: ProductCostService.methodWac,
        ),
        1001,
      );
    });

    test('adding same-cost stock is a no-op', () {
      expect(
        ProductCostService.resolvePurchaseCostForTest(
          beforeQty: 100,
          beforeCostCents: 5000,
          addedQty: 50,
          newPaidCostCents: 5000,
          costingMethod: ProductCostService.methodWac,
        ),
        5000,
      );
    });

    test('unknown method defaults to WAC', () {
      // Defensive behaviour: a caller passing a typo/stale string should
      // still get a deterministic answer, not a crash or NaN.
      expect(
        ProductCostService.resolvePurchaseCostForTest(
          beforeQty: 1,
          beforeCostCents: 6000,
          addedQty: 1,
          newPaidCostCents: 6500,
          costingMethod: 'unknown_method_xyz',
        ),
        6250,
      );
    });

    test(
      'voiding inbound return removes its frozen value from current WAC',
      () {
        // Current pool: 10 @ 150. Remove a previously returned unit whose
        // frozen cost was 100:
        //   (10×150 - 1×100) / 9 = 155.56 -> 156.
        expect(
          ProductCostService.resolveRemovalCostForTest(
            beforeQty: 10,
            beforeCostCents: 150,
            removedQty: 1,
            removedUnitCostCents: 100,
          ),
          156,
        );
      },
    );

    test('inbound return followed by immediate void restores prior WAC', () {
      final afterReturn = ProductCostService.resolvePurchaseCostForTest(
        beforeQty: 10,
        beforeCostCents: 150,
        addedQty: 2,
        newPaidCostCents: 100,
        costingMethod: ProductCostService.methodWac,
      );
      expect(afterReturn, 142);

      expect(
        ProductCostService.resolveRemovalCostForTest(
          beforeQty: 12,
          beforeCostCents: afterReturn,
          removedQty: 2,
          removedUnitCostCents: 100,
        ),
        150,
      );
    });

    test('removing all returned stock keeps last visible cost', () {
      expect(
        ProductCostService.resolveRemovalCostForTest(
          beforeQty: 2,
          beforeCostCents: 100,
          removedQty: 2,
          removedUnitCostCents: 100,
        ),
        100,
      );
    });
  });

  group('ProductCostService — FIFO / last-cost math', () {
    test('FIFO stores latest paid cost (display value)', () {
      // Per-layer costs live in product_batches. The cost_cents cell is
      // purely a display value and MUST equal the most recent paid price
      // so the product-edit screen matches the user's mental model.
      expect(
        ProductCostService.resolvePurchaseCostForTest(
          beforeQty: 100,
          beforeCostCents: 5000,
          addedQty: 1,
          newPaidCostCents: 6500,
          costingMethod: ProductCostService.methodFifo,
        ),
        6500,
      );
    });

    test('last-cost is identical to FIFO for the cost_cents cell', () {
      // The methods differ only in how COGS is computed at sale time
      // (FIFO consumes batches; last-cost reads cost_cents directly).
      // For the display cell both overwrite with the latest paid value.
      expect(
        ProductCostService.resolvePurchaseCostForTest(
          beforeQty: 100,
          beforeCostCents: 5000,
          addedQty: 1,
          newPaidCostCents: 6500,
          costingMethod: ProductCostService.methodLast,
        ),
        6500,
      );
    });

    test('FIFO ignores beforeQty/beforeCost entirely', () {
      // Confirms the method switch: no blending whatsoever for FIFO.
      for (final qty in [0, 1, 50, 1000]) {
        for (final prior in [0, 1000, 5000, 99999]) {
          expect(
            ProductCostService.resolvePurchaseCostForTest(
              beforeQty: qty,
              beforeCostCents: prior,
              addedQty: 7,
              newPaidCostCents: 4242,
              costingMethod: ProductCostService.methodFifo,
            ),
            4242,
            reason: 'FIFO with beforeQty=$qty beforeCost=$prior',
          );
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // INTEGRATION — syncProductFromVariants with real Drift DB
  // ═══════════════════════════════════════════════════════════════════════════

  group('ProductCostService — parent sync regression (user-reported bug)', () {
    late AppDatabase db;
    late PurchaseDao dao;
    late int currencyId;

    setUp(() async {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
      dao = PurchaseDao(db);
      await db.customSelect('SELECT 1').get(); // triggers beforeOpen seeds

      final usd = await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle();
      currencyId = usd.id;
    });

    tearDown(() async {
      await db.close();
    });

    /// Helper: create a product with [n] variants having the given
    /// (cost, stock) pairs. Returns the new product id.
    ///
    /// Each variant is given a distinct `color_id` so the composite-unique
    /// index `(product_id, color_id, size_id)` does not reject the second
    /// and later inserts — mirrors the constraint Drift enforces in
    /// production to block accidental duplicate variants.
    Future<int> createProductWithVariants(
      List<({int cost, int stock})> variants, {
      String costingMethod = 'wac',
    }) async {
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Test Product ${DateTime.now().microsecondsSinceEpoch}',
              costCents: Decimal.fromInt(0),
              priceCents: Decimal.fromInt(0),
              currencyId: Value(currencyId),
              hasVariants: const Value(true),
              costingMethod: Value(costingMethod),
            ),
          );
      for (var i = 0; i < variants.length; i++) {
        final colorId = await db
            .into(db.productColors)
            .insert(
              ProductColorsCompanion.insert(
                name: 'Color-$productId-$i',
                hexCode: const Value('#000000'),
              ),
            );
        await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: productId,
                sku: Value('V-$productId-$i'),
                colorId: Value(colorId),
                costCents: Decimal.fromInt(variants[i].cost),
                priceCents: Decimal.fromInt(0),
                stockQuantity: Value(variants[i].stock),
                isActive: const Value(true),
              ),
            );
      }
      return productId;
    }

    test(
      'parent cost_cents is TRUE weighted average across variants — NOT MAX',
      () async {
        // Build the exact shape from the user's bug report:
        //   variant A: 1 unit @ 6000  (Small)
        //   variant B: 1 unit @ 6250  (Medium)
        //   variant C: 1 unit @ 6500  (Medium)
        // Weighted avg = (6000 + 6250 + 6500) / 3 = 6250.
        // Legacy (buggy) MAX would give 6500 — this test pins the fix.
        final pid = await createProductWithVariants([
          (cost: 6000, stock: 1),
          (cost: 6250, stock: 1),
          (cost: 6500, stock: 1),
        ]);

        await ProductCostService.syncProductFromVariants(dao, productId: pid);

        final row = await (db.select(
          db.products,
        )..where((p) => p.id.equals(pid))).getSingle();

        expect(
          row.costCents.toBigInt().toInt(),
          6250,
          reason: 'Parent cost must be weighted average, not MAX(6500)',
        );
        expect(row.stockQuantity, 3);
      },
    );

    test(
      'weighted average weights by stock quantity (not count of variants)',
      () async {
        //   variant A: 10 units @ 5000
        //   variant B:  1 unit  @ 9999
        // Simple avg = 7499.5 (wrong — used by naive AVG(cost_cents)).
        // Weighted = (5000×10 + 9999×1) / 11 = 59999/11 ≈ 5454.45 → 5454.
        final pid = await createProductWithVariants([
          (cost: 5000, stock: 10),
          (cost: 9999, stock: 1),
        ]);

        await ProductCostService.syncProductFromVariants(dao, productId: pid);

        final row = await (db.select(
          db.products,
        )..where((p) => p.id.equals(pid))).getSingle();

        expect(row.costCents.toBigInt().toInt(), 5454);
        expect(row.stockQuantity, 11);
      },
    );

    test(
      'falls back to simple average when every variant is out of stock',
      () async {
        // Edge case: product fully depleted but user still wants to see a
        // meaningful cost value on the edit screen. Weighted average is
        // mathematically undefined (divide by zero), so we use the simple
        // mean of cost_cents across active variants.
        //   (5000 + 6000 + 7000) / 3 = 6000.
        final pid = await createProductWithVariants([
          (cost: 5000, stock: 0),
          (cost: 6000, stock: 0),
          (cost: 7000, stock: 0),
        ]);

        await ProductCostService.syncProductFromVariants(dao, productId: pid);

        final row = await (db.select(
          db.products,
        )..where((p) => p.id.equals(pid))).getSingle();

        expect(row.costCents.toBigInt().toInt(), 6000);
        expect(row.stockQuantity, 0);
      },
    );

    test('ignores inactive variants', () async {
      // Soft-deleted variants must not pollute the parent aggregate —
      // otherwise a deactivated-but-still-stocked SKU would keep skewing
      // the displayed cost long after the user "removed" it.
      final pid = await createProductWithVariants([
        (cost: 5000, stock: 10),
        (cost: 9999, stock: 10),
      ]);
      // Deactivate the second variant via raw SQL (cost_cents uses
      // MoneyConverter; equating a Decimal filter would pass a typed
      // value Drift cannot compare without the converter's coercion).
      await db.customUpdate(
        'UPDATE product_variants SET is_active = 0 '
        'WHERE product_id = ? AND cost_cents = 9999',
        variables: [Variable.withInt(pid)],
        updates: {db.productVariants},
        updateKind: UpdateKind.update,
      );

      await ProductCostService.syncProductFromVariants(dao, productId: pid);

      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(pid))).getSingle();

      expect(row.costCents.toBigInt().toInt(), 5000);
      expect(row.stockQuantity, 10);
    });

    test('syncCost=false leaves cost_cents untouched', () async {
      // Verifies the per-column opt-out flags on the sync method.
      final pid = await createProductWithVariants([
        (cost: 5000, stock: 1),
        (cost: 7000, stock: 1),
      ]);
      // Pre-set an arbitrary parent cost so we can detect whether it moves.
      await (db.update(db.products)..where((p) => p.id.equals(pid))).write(
        ProductsCompanion(costCents: Value(Decimal.fromInt(12345))),
      );

      await ProductCostService.syncProductFromVariants(
        dao,
        productId: pid,
        syncCost: false,
      );

      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(pid))).getSingle();

      expect(row.costCents.toBigInt().toInt(), 12345);
      // Stock WAS synced (default true), so this also serves as an
      // end-to-end confirmation that the column-level flags work.
      expect(row.stockQuantity, 2);
    });
  });
}
