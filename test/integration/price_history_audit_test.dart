import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/app_database.dart';

/// Regression tests guarding two bugs that surfaced after centralizing
/// `product_price_histories` writes:
///
///   Bug 2: post-WAC variant cost was being logged as the "new cost" in the
///          audit log. WAC blends old qty × old cost with new qty × new cost
///          (e.g. 50 × 3 + 60 × 1 / 4 = 52.50). Logging 52.50 when the user
///          paid 60 is misleading — the audit log is supposed to show the
///          PURCHASE PRICE the user typed. The variant's stored cost still
///          becomes the WAC value (correct accounting); only the audit log
///          changes.
///
///   Bug 1 (DAO surface): when a variant was purchased without explicitly
///          setting a wholesale price, the centralized writer must NOT log a
///          wholesale change just because a sibling variant pushed the
///          parent product's wholesale aggregate. Each variant carries its
///          own NULLable wholesale; non-null wholesale leaks were only ever
///          surfaced in the BLoC fallback chain (covered by widget tests),
///          so here we assert the post-condition: the per-variant wholesale
///          column stays NULL when nothing was supplied.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> setupCurrencyAndSupplier() async {
    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    final supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'WAC Audit Supplier',
            currencyId: usd.id,
            balanceCents: Value(Decimal.zero),
          ),
        );
    return supplierId;
  }

  Future<({int productId, int variantId, int currencyId})> setupVariantProduct({
    int initialCostCents = 5000,
    int initialPriceCents = 6000,
    int initialStock = 3,
  }) async {
    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    final productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value<String?>('WAC-AUDIT-001'),
            name: 'WAC Audit Product',
            costCents: Decimal.fromInt(initialCostCents),
            priceCents: Decimal.fromInt(initialPriceCents),
            currencyId: Value(usd.id),
            stockQuantity: Value(initialStock),
          ),
        );
    final variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: Value(initialStock),
            costCents: Decimal.fromInt(initialCostCents),
            priceCents: Decimal.fromInt(initialPriceCents),
          ),
        );
    return (productId: productId, variantId: variantId, currencyId: usd.id);
  }

  group('Bug 2: price_history records purchase price, not post-WAC cost', () {
    test(
      'WAC blends variant.cost to 52.50 but audit log shows 60.00',
      () async {
        // Variant pre-state: cost=50.00, stock=3
        final ctx = await setupVariantProduct(
          initialCostCents: 5000,
          initialPriceCents: 6000,
          initialStock: 3,
        );
        final supplierId = await setupCurrencyAndSupplier();

        // Post a purchase: 1 unit at cost 60.00 (WAC is the default strategy)
        final purchaseId = await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                purchaseNumber: 'PO-WAC-AUDIT-001',
                supplierId: supplierId,
                subtotalCents: Decimal.fromInt(6000),
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(6000),
                paidAmountCents: Value(Decimal.fromInt(6000)),
                currencyId: ctx.currencyId,
                status: const Value('draft'),
                paymentMethod: const Value('cash'),
              ),
            );
        await db
            .into(db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                purchaseId: purchaseId,
                productId: ctx.productId,
                variantId: Value(ctx.variantId),
                quantity: 1,
                unitCostCents: Decimal.fromInt(6000),
                subtotalCents: Decimal.fromInt(6000),
                totalCents: Decimal.fromInt(6000),
              ),
            );

        await db.purchaseDao.postPurchase(purchaseId);

        // Variant cost should be the WAC blend: (5000*3 + 6000*1) / 4 = 5250.
        final variant = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(ctx.variantId))).getSingle();
        expect(
          variant.costCents.toBigInt().toInt(),
          equals(5250),
          reason: 'WAC must blend old and new cost: (5000*3 + 6000*1)/4 = 5250',
        );

        // The audit log must show the PURCHASE PRICE (6000), not the WAC blend
        // (5250). This is the regression guard for Bug 2.
        //
        // Storage convention: every `*_cents` column stores integer cents
        // directly. This guards against the legacy divide/shift convention
        // which truncated values such as 11.88.
        final histories =
            await (db.select(db.productPriceHistories)
                  ..where(
                    (h) =>
                        h.productId.equals(ctx.productId) &
                        h.variantId.equals(ctx.variantId),
                  )
                  ..orderBy([(h) => OrderingTerm.desc(h.id)])
                  ..limit(1))
                .get();

        expect(
          histories.length,
          equals(1),
          reason: 'A single price-history row must be recorded per posted line',
        );
        final row = histories.first;
        expect(
          row.oldCostCents.toBigInt().toInt(),
          equals(5000),
          reason: 'Old cost must equal the variant.cost before WAC mutation',
        );
        expect(
          row.newCostCents.toBigInt().toInt(),
          equals(6000),
          reason:
              'New cost must equal the PURCHASE price the user typed (6000), '
              'not the post-WAC variant cost (5250). Audit logs answer '
              '"what did I pay" — WAC is internal valuation only.',
        );
        expect(
          row.changeReason,
          equals('purchase_post:#$purchaseId'),
          reason: 'Reason must identify the source purchase for traceability',
        );
      },
    );

    test(
      'per-line discount: audit log shows GROSS typed cost, not NET',
      () async {
        // Repro for the user-reported bug: "I typed 100 but Price Change
        // History shows 99".
        //
        // The purchase form lets the user enter a per-line discount. The
        // IAS-2 NET basis used for inventory valuation (cost_cents) is
        // (gross - discount/qty), which is correct for COGS / GL. But the
        // audit log is a USER-FACING "what did I pay" surface — it must
        // reflect the price the user actually typed, otherwise the
        // product edit screen (which now reads last_purchase_price_cents)
        // and the history row disagree.
        //
        // Scenario: variant starts pristine (cost=0, no prior purchase).
        // Post a purchase line: qty=1, unit_cost=100.00, discount=1.00.
        //   NET inventory basis  → (10000 - 100/1) = 9900
        //   GROSS audit value    → 10000
        // The history row must record 10000.
        final ctx = await setupVariantProduct(
          initialCostCents: 0,
          initialPriceCents: 0,
          initialStock: 0,
        );
        final supplierId = await setupCurrencyAndSupplier();

        final purchaseId = await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                purchaseNumber: 'PO-DISC-AUDIT-001',
                supplierId: supplierId,
                subtotalCents: Decimal.fromInt(10000),
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(9900),
                paidAmountCents: Value(Decimal.fromInt(9900)),
                currencyId: ctx.currencyId,
                status: const Value('draft'),
                paymentMethod: const Value('cash'),
              ),
            );
        await db
            .into(db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                purchaseId: purchaseId,
                productId: ctx.productId,
                variantId: Value(ctx.variantId),
                quantity: 1,
                unitCostCents: Decimal.fromInt(10000),
                discountCents: Value(Decimal.fromInt(100)),
                subtotalCents: Decimal.fromInt(10000),
                totalCents: Decimal.fromInt(9900),
              ),
            );

        await db.purchaseDao.postPurchase(purchaseId);

        // Inventory cost basis (cost_cents) MUST be the NET 9900 — that's
        // what drives COGS / GL and must remain net of trade discounts.
        final variant = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(ctx.variantId))).getSingle();
        expect(
          variant.costCents.toBigInt().toInt(),
          equals(9900),
          reason:
              'cost_cents must remain the NET (post-discount) basis for IAS-2',
        );

        // Supplier reference / last list price (last_purchase_price_cents)
        // MUST be the GROSS 10000 — that's the column the product edit
        // screen reads to answer "what did I pay last time".
        expect(
          variant.lastPurchasePriceCents?.toBigInt().toInt(),
          equals(10000),
          reason:
              'last_purchase_price_cents must be the GROSS unit cost the user typed',
        );

        // The Price Change History row must record the GROSS value (10000),
        // not the NET basis (9900). This is the user-facing regression.
        final histories =
            await (db.select(db.productPriceHistories)
                  ..where(
                    (h) =>
                        h.productId.equals(ctx.productId) &
                        h.variantId.equals(ctx.variantId),
                  )
                  ..orderBy([(h) => OrderingTerm.desc(h.id)])
                  ..limit(1))
                .get();
        expect(
          histories.length,
          equals(1),
          reason: 'Exactly one price-history row per posted line',
        );
        final row = histories.first;
        expect(
          row.newCostCents.toBigInt().toInt(),
          equals(10000),
          reason:
              'Audit log must record the GROSS typed cost (10000), not the '
              'post-discount NET basis (9900). The product edit screen and '
              'the history widget must agree.',
        );
      },
    );

    test(
      'consecutive purchases compare GROSS-to-GROSS in the audit log',
      () async {
        // After the discount fix, the "old cost" of the SECOND purchase must
        // be the GROSS value from the first purchase (not the WAC blend in
        // cost_cents). Otherwise the history widget shows mismatched
        // bookends: "0 → 100" then "99 → 120" (where did 99 come from?).
        final ctx = await setupVariantProduct(
          initialCostCents: 0,
          initialPriceCents: 0,
          initialStock: 0,
        );
        final supplierId = await setupCurrencyAndSupplier();

        // ── First purchase: typed 100, discount 1 ⇒ NET 99, GROSS 100.
        final po1 = await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                purchaseNumber: 'PO-CONS-001',
                supplierId: supplierId,
                subtotalCents: Decimal.fromInt(10000),
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(9900),
                paidAmountCents: Value(Decimal.fromInt(9900)),
                currencyId: ctx.currencyId,
                status: const Value('draft'),
                paymentMethod: const Value('cash'),
              ),
            );
        await db
            .into(db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                purchaseId: po1,
                productId: ctx.productId,
                variantId: Value(ctx.variantId),
                quantity: 1,
                unitCostCents: Decimal.fromInt(10000),
                discountCents: Value(Decimal.fromInt(100)),
                subtotalCents: Decimal.fromInt(10000),
                totalCents: Decimal.fromInt(9900),
              ),
            );
        await db.purchaseDao.postPurchase(po1);

        // ── Second purchase: typed 120, no discount ⇒ GROSS 120.
        final po2 = await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                purchaseNumber: 'PO-CONS-002',
                supplierId: supplierId,
                subtotalCents: Decimal.fromInt(12000),
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(12000),
                paidAmountCents: Value(Decimal.fromInt(12000)),
                currencyId: ctx.currencyId,
                status: const Value('draft'),
                paymentMethod: const Value('cash'),
              ),
            );
        await db
            .into(db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                purchaseId: po2,
                productId: ctx.productId,
                variantId: Value(ctx.variantId),
                quantity: 1,
                unitCostCents: Decimal.fromInt(12000),
                subtotalCents: Decimal.fromInt(12000),
                totalCents: Decimal.fromInt(12000),
              ),
            );
        await db.purchaseDao.postPurchase(po2);

        // Two history rows in insertion order: first row newCost=10000,
        // second row oldCost=10000 (GROSS-to-GROSS continuity), newCost=12000.
        final rows =
            await (db.select(db.productPriceHistories)
                  ..where(
                    (h) =>
                        h.productId.equals(ctx.productId) &
                        h.variantId.equals(ctx.variantId),
                  )
                  ..orderBy([(h) => OrderingTerm.asc(h.id)]))
                .get();
        expect(
          rows.length,
          equals(2),
          reason: 'One history row per posted purchase line',
        );
        expect(
          rows[0].newCostCents.toBigInt().toInt(),
          equals(10000),
          reason: 'First row records GROSS 10000 (the typed cost)',
        );
        expect(
          rows[1].oldCostCents.toBigInt().toInt(),
          equals(10000),
          reason:
              'Second row\'s old cost must be the FIRST row\'s new cost '
              '(10000), not the WAC NET basis in cost_cents (9900). '
              'Old and new are both expressed in GROSS terms so the '
              'history is internally consistent.',
        );
        expect(
          rows[1].newCostCents.toBigInt().toInt(),
          equals(12000),
          reason: 'Second row records GROSS 12000',
        );
      },
    );

    test(
      'WAC does NOT alter variant cost when product is non-tracked',
      () async {
        // Set up a non-tracked product (e.g. a service item).
        final usd = await (db.select(
          db.currencies,
        )..where((c) => c.code.equals('USD'))).getSingle();
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('SVC-AUDIT-001'),
                name: 'Service Product',
                costCents: Decimal.fromInt(5000),
                priceCents: Decimal.fromInt(6000),
                currencyId: Value(usd.id),
                trackInventory: const Value(false),
              ),
            );
        final variantId = await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: productId,
                stockQuantity: const Value(0),
                costCents: Decimal.fromInt(5000),
                priceCents: Decimal.fromInt(6000),
              ),
            );
        final supplierId = await setupCurrencyAndSupplier();

        final purchaseId = await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                purchaseNumber: 'PO-SVC-001',
                supplierId: supplierId,
                subtotalCents: Decimal.fromInt(6000),
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(6000),
                paidAmountCents: Value(Decimal.fromInt(6000)),
                currencyId: usd.id,
                status: const Value('draft'),
                paymentMethod: const Value('cash'),
              ),
            );
        await db
            .into(db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                purchaseId: purchaseId,
                productId: productId,
                variantId: Value(variantId),
                quantity: 1,
                unitCostCents: Decimal.fromInt(6000),
                subtotalCents: Decimal.fromInt(6000),
                totalCents: Decimal.fromInt(6000),
              ),
            );

        await db.purchaseDao.postPurchase(purchaseId);

        // Variant cost MUST stay at 5000 — non-tracked products carry no
        // inventory cost basis, so WAC does not run.
        final variant = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variantId))).getSingle();
        expect(
          variant.costCents.toBigInt().toInt(),
          equals(5000),
          reason:
              'Non-tracked products must not have their cost mutated by WAC',
        );

        // Stock must also stay at 0 — non-tracked products have no ledger.
        expect(
          variant.stockQuantity,
          equals(0),
          reason: 'Non-tracked products must not accumulate stock',
        );

        // No price-history row should exist for cost (the recorded new == old).
        final histories = await db
            .customSelect(
              'SELECT old_cost_cents, new_cost_cents '
              'FROM product_price_histories '
              'WHERE product_id = ? AND variant_id = ?',
              variables: [
                Variable.withInt(productId),
                Variable.withInt(variantId),
              ],
            )
            .get();
        // PriceHistoryService.recordIfChanged is a no-op when nothing changed,
        // so we expect zero rows here.
        expect(
          histories.length,
          equals(0),
          reason:
              'No price-history row should be written when nothing changed '
              '(non-tracked product, no sell/wholesale override)',
        );
      },
    );
  });

  group('Bug 1 (DAO surface): variant wholesale stays NULL when not set', () {
    test('posting a sibling variant does not write a wholesale value to '
        'another variant', () async {
      // Build a product with TWO variants. Variant A receives a wholesale
      // override on its purchase line; Variant B is a sibling that has never
      // been purchased.
      final usd = await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle();
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('SIB-WHS-001'),
              name: 'Sibling Wholesale Test',
              costCents: Decimal.zero,
              priceCents: Decimal.zero,
              currencyId: Value(usd.id),
              hasVariants: const Value(true),
            ),
          );
      // Distinct dimensional axes are required because the unique index
      // `idx_product_variants_product_color_size_unique` is defined as
      // `(product_id, IFNULL(color_id,-1), IFNULL(size_id,-1))` — two
      // variants under the same product cannot both be NULL/NULL.
      final colorRed = await db
          .into(db.productColors)
          .insert(ProductColorsCompanion.insert(name: 'Red'));
      final colorBlue = await db
          .into(db.productColors)
          .insert(ProductColorsCompanion.insert(name: 'Blue'));
      final variantA = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              sku: const Value('SIB-A'),
              colorId: Value(colorRed),
              stockQuantity: const Value(0),
              costCents: Decimal.zero,
              priceCents: Decimal.zero,
            ),
          );
      final variantB = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              sku: const Value('SIB-B'),
              colorId: Value(colorBlue),
              stockQuantity: const Value(0),
              costCents: Decimal.zero,
              priceCents: Decimal.zero,
            ),
          );
      final supplierId = await setupCurrencyAndSupplier();

      // Purchase variant A with newWholesalePriceCents = 7000.
      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'PO-SIB-001',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(5000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(5000),
              paidAmountCents: Value(Decimal.fromInt(5000)),
              currencyId: usd.id,
              status: const Value('draft'),
              paymentMethod: const Value('cash'),
            ),
          );
      await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: productId,
              variantId: Value(variantA),
              quantity: 1,
              unitCostCents: Decimal.fromInt(5000),
              subtotalCents: Decimal.fromInt(5000),
              totalCents: Decimal.fromInt(5000),
              newWholesalePriceCents: Value(Decimal.fromInt(7000)),
            ),
          );
      await db.purchaseDao.postPurchase(purchaseId);

      // Variant A must have wholesale = 7000.
      final rowA = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantA))).getSingle();
      expect(
        rowA.wholesalePriceCents?.toBigInt().toInt(),
        equals(7000),
        reason: 'Variant A should have its overridden wholesale persisted',
      );

      // Variant B's wholesale must remain NULL — the sibling write must not
      // contaminate it. This is the DB-level invariant that backs the BLoC
      // bug-1 fix (the BLoC fallback chain previously bled the products-table
      // aggregate onto sibling variants).
      final rowB = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantB))).getSingle();
      expect(
        rowB.wholesalePriceCents,
        isNull,
        reason:
            'Sibling variant B must NOT inherit Variant A\'s wholesale '
            'just because the parent product\'s aggregated wholesale is now '
            'non-null.',
      );

      // The audit log must contain a row only for Variant A's wholesale
      // change, not for Variant B.
      final histB = await db
          .customSelect(
            'SELECT id FROM product_price_histories '
            'WHERE product_id = ? AND variant_id = ?',
            variables: [
              Variable.withInt(productId),
              Variable.withInt(variantB),
            ],
          )
          .get();
      expect(
        histB.length,
        equals(0),
        reason: 'No price-history row should exist for Variant B (untouched)',
      );
    });
  });
}
