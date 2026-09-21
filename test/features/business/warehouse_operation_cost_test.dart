import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/inventory/product_cost_service.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/core/services/inventory/wac_movement_service.dart';
import 'package:tapix/core/services/inventory/inventory_valuation_delta_service.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int variant, product;
  late WarehouseOperationScope scope;

  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    final row = await db
        .customSelect(
          'SELECT id, product_id FROM product_variants ORDER BY id LIMIT 1',
        )
        .getSingle();
    variant = row.read<int>('id');
    product = row.read<int>('product_id');
    final primary = await WarehouseOperationScope.resolve(db);
    final other = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: other,
            organizationId: primary.organizationId,
            branchId: primary.branchId,
            code: 'COST-SECOND',
          ),
        );
    await db
        .into(db.businessWarehouseStocks)
        .insert(
          BusinessWarehouseStocksCompanion.insert(
            warehouseId: other,
            variantId: variant,
            quantity: const Value(1000),
            unitCostCents: const Value(200),
          ),
        );
    scope = await WarehouseOperationScope.resolve(db, warehouseId: other);
  });
  tearDown(() => db.close());

  Future<BusinessWarehouseStock> balance() =>
      (db.select(db.businessWarehouseStocks)..where(
            (s) =>
                s.warehouseId.equals(scope.warehouseId) &
                s.variantId.equals(variant),
          ))
          .getSingle();

  Future<void> purchase(String method, bool simple) async {
    final before = await balance();
    await db.transaction(() async {
      await StockService.adjustStock(
        db.productDao,
        productId: product,
        variantId: simple ? null : variant,
        quantity: 1000,
        direction: StockDirection.increase,
        scope: scope,
      );
      if (simple) {
        await ProductCostService.applyPurchaseCostToProduct(
          db.productDao,
          productId: product,
          beforeQty: before.quantity,
          beforeCostCents: before.unitCostCents,
          addedQty: 1000,
          newPaidCostCents: 1000,
          costingMethod: method,
          scope: scope,
        );
      } else {
        await ProductCostService.applyPurchaseCostToVariant(
          db.productDao,
          variantId: variant,
          beforeQty: before.quantity,
          beforeCostCents: before.unitCostCents,
          addedQty: 1000,
          newPaidCostCents: 1000,
          costingMethod: method,
          scope: scope,
        );
      }
      await ProductCostService.syncProductFromVariants(
        db.productDao,
        productId: product,
        scope: scope,
      );
    });
  }

  group('frozen warehouse snapshots', () {
    test('ambiguous simple WAC refuses the first active variant', () async {
      final size = await db.customInsert(
        "INSERT INTO sizes (name) VALUES ('Extra WAC')",
      );
      await db.customStatement(
        'INSERT INTO product_variants (product_id, size_id, cost_cents, price_cents) VALUES (?, ?, 100, 200)',
        [product, size],
      );
      await expectLater(
        WacMovementService.capture(
          db.productDao,
          productId: product,
          scope: scope,
        ),
        throwsStateError,
      );
    });

    test(
      'optional size remains valid for a single simple operational variant',
      () async {
        final size = await db.customInsert(
          "INSERT INTO sizes (name) VALUES ('Optional WAC')",
        );
        await db.customStatement(
          'UPDATE product_variants SET size_id = ? WHERE id = ?',
          [size, variant],
        );
        expect(
          (await WacMovementService.capture(
            db.productDao,
            productId: product,
            scope: scope,
          ))!.variantId,
          variant,
        );
        expect(
          (await InventoryValuationDeltaService.capture(
            db.productDao,
            productId: product,
            scope: scope,
          ))!.variantId,
          variant,
        );
      },
    );

    test(
      'secondary valuation cannot reuse a legacy product-only balance',
      () async {
        final legacy = await db.customInsert(
          "INSERT INTO products (name, cost_cents, price_cents, stock_quantity) VALUES ('Legacy scope', 501, 1000, 3)",
        );
        await expectLater(
          InventoryValuationDeltaService.capture(
            db.productDao,
            productId: legacy,
            scope: scope,
          ),
          throwsStateError,
        );
        expect(
          (await InventoryValuationDeltaService.capture(
            db.productDao,
            productId: legacy,
          ))!.valueCents,
          1503,
        );
      },
    );

    test(
      'inbound WAC and inverse use the captured warehouse and exact value delta',
      () async {
        final old = await fixtures.legacySnapshot(db);
        await db.transaction(() async {
          final valuation = (await InventoryValuationDeltaService.capture(
            db.productDao,
            productId: product,
            scope: scope,
          ))!;
          final before = (await WacMovementService.capture(
            db.productDao,
            productId: product,
            scope: scope,
          ))!;
          expect(before.scope.warehouseId, scope.warehouseId);
          expect(before.quantity, 1000);
          expect(before.unitCostCents, 200);
          await StockService.adjustStock(
            db.productDao,
            productId: product,
            quantity: 1000,
            direction: StockDirection.increase,
            scope: scope,
          );
          await WacMovementService.applyInbound(
            db.productDao,
            snapshot: before,
            addedQty: 1000,
            inboundUnitCostCents: 1000,
          );
          expect((await balance()).unitCostCents, 600);
          expect(
            await InventoryValuationDeltaService.signedDeltaAfter(
              db.productDao,
              valuation,
            ),
            1000,
          );
          final reverseValue = (await InventoryValuationDeltaService.capture(
            db.productDao,
            productId: product,
            variantId: variant,
            scope: scope,
          ))!;
          final reverse = (await WacMovementService.capture(
            db.productDao,
            productId: product,
            variantId: variant,
            scope: scope,
          ))!;
          await StockService.adjustStock(
            db.productDao,
            productId: product,
            quantity: 1000,
            direction: StockDirection.decrease,
            scope: scope,
          );
          await WacMovementService.reverseInbound(
            db.productDao,
            snapshot: reverse,
            removedQty: 1000,
            removedUnitCostCents: 1000,
          );
          expect((await balance()).unitCostCents, 200);
          expect(
            await InventoryValuationDeltaService.signedDeltaAfter(
              db.productDao,
              reverseValue,
            ),
            -1000,
          );
        });
        expect(await fixtures.legacySnapshot(db), old);
      },
    );

    test('fractional rounding follows the selected warehouse pool', () async {
      await (db.update(db.businessWarehouseStocks)..where(
            (s) =>
                s.warehouseId.equals(scope.warehouseId) &
                s.variantId.equals(variant),
          ))
          .write(
            const BusinessWarehouseStocksCompanion(
              quantity: Value(3),
              unitCostCents: Value(500),
            ),
          );
      final original = (await InventoryValuationDeltaService.capture(
        db.productDao,
        productId: product,
        scope: scope,
      ))!;
      expect(original.valueCents, 2);
      final deltas = <int>[];
      for (var i = 0; i < 3; i++) {
        final before = (await InventoryValuationDeltaService.capture(
          db.productDao,
          productId: product,
          scope: scope,
        ))!;
        await StockService.adjustStock(
          db.productDao,
          productId: product,
          quantity: 1,
          direction: StockDirection.decrease,
          scope: scope,
        );
        deltas.add(
          await InventoryValuationDeltaService.signedDeltaAfter(
            db.productDao,
            before,
          ),
        );
      }
      expect(deltas, [-1, 0, -1]);
      expect(
        await InventoryValuationDeltaService.signedDeltaAfter(
          db.productDao,
          original,
        ),
        -2,
      );
    });

    test(
      'snapshots cannot be applied to a different database connection',
      () async {
        final before = (await WacMovementService.capture(
          db.productDao,
          productId: product,
          scope: scope,
        ))!;
        final valuation = (await InventoryValuationDeltaService.capture(
          db.productDao,
          productId: product,
          scope: scope,
        ))!;
        final other = fixtures.memoryDb();
        try {
          await expectLater(
            WacMovementService.applyInbound(
              other.productDao,
              snapshot: before,
              addedQty: 1,
              inboundUnitCostCents: 200,
            ),
            throwsStateError,
          );
          await expectLater(
            InventoryValuationDeltaService.signedDeltaAfter(
              other.productDao,
              valuation,
            ),
            throwsStateError,
          );
        } finally {
          await other.close();
        }
      },
    );

    test(
      'deactivation after capture rejects WAC and valuation reuse',
      () async {
        final before = (await WacMovementService.capture(
          db.productDao,
          productId: product,
          scope: scope,
        ))!;
        final valuation = (await InventoryValuationDeltaService.capture(
          db.productDao,
          productId: product,
          scope: scope,
        ))!;
        await (db.update(db.businessWarehouses)
              ..where((w) => w.id.equals(scope.warehouseId)))
            .write(const BusinessWarehousesCompanion(isActive: Value(false)));
        await expectLater(
          WacMovementService.applyInbound(
            db.productDao,
            snapshot: before,
            addedQty: 1,
            inboundUnitCostCents: 200,
          ),
          throwsStateError,
        );
        await expectLater(
          InventoryValuationDeltaService.signedDeltaAfter(
            db.productDao,
            valuation,
          ),
          throwsStateError,
        );
        expect((await balance()).unitCostCents, 200);
      },
    );

    test('multivariant WAC capture requires an explicit variant', () async {
      await (db.update(db.products)..where((p) => p.id.equals(product))).write(
        const ProductsCompanion(hasVariants: Value(true)),
      );
      await expectLater(
        WacMovementService.capture(
          db.productDao,
          productId: product,
          scope: scope,
        ),
        throwsStateError,
      );
      expect(
        (await WacMovementService.capture(
          db.productDao,
          productId: product,
          variantId: variant,
          scope: scope,
        ))!.unitCostCents,
        200,
      );
    });

    test(
      'WAC capture rejects a variant belonging to another product',
      () async {
        final other = await (db.select(
          db.products,
        )..where((p) => p.id.isNotValue(product))).getSingle();
        await (db.update(db.products)..where((p) => p.id.equals(other.id)))
            .write(const ProductsCompanion(costingMethod: Value('wac')));
        await expectLater(
          WacMovementService.capture(
            db.productDao,
            productId: other.id,
            variantId: variant,
            scope: scope,
          ),
          throwsStateError,
        );
      },
    );

    test(
      'valuation does not absorb changes made only in the primary warehouse',
      () async {
        final before = (await InventoryValuationDeltaService.capture(
          db.productDao,
          productId: product,
          scope: scope,
        ))!;
        await ProductCostService.setVariantCost(
          db.productDao,
          variantId: variant,
          newCostCents: 9999,
        );
        await StockService.adjustStock(
          db.productDao,
          productId: product,
          quantity: 123,
          direction: StockDirection.increase,
        );
        expect(
          await InventoryValuationDeltaService.signedDeltaAfter(
            db.productDao,
            before,
          ),
          0,
        );
      },
    );
  });

  for (final simple in [false, true]) {
    for (final method in ['wac', 'fifo', 'last']) {
      test('selected warehouse cost: $method simple=$simple', () async {
        if (!simple) {
          await (db.update(db.products)..where((p) => p.id.equals(product)))
              .write(const ProductsCompanion(hasVariants: Value(true)));
        }
        final old = await fixtures.legacySnapshot(db);
        await purchase(method, simple);
        final result = await balance();
        expect(result.quantity, 2000);
        expect(result.unitCostCents, method == 'wac' ? 600 : 1000);
        expect(await fixtures.legacySnapshot(db), old);
        final primary = await WarehouseOperationScope.resolve(db);
        final primaryStock =
            await (db.select(db.businessWarehouseStocks)..where(
                  (s) =>
                      s.warehouseId.equals(primary.warehouseId) &
                      s.variantId.equals(variant),
                ))
                .getSingle();
        expect(primaryStock.quantity, 1234);
        expect(primaryStock.unitCostCents, 701);
      });
    }
  }

  test(
    'inverse WAC removes only the selected warehouse inbound value',
    () async {
      final old = await fixtures.legacySnapshot(db);
      await purchase('wac', false);
      final before = await balance();
      await db.transaction(() async {
        await StockService.adjustStock(
          db.productDao,
          productId: product,
          variantId: variant,
          quantity: 1000,
          direction: StockDirection.decrease,
          scope: scope,
        );
        final resolved = await ProductCostService.applyRemovalCostToVariant(
          db.productDao,
          variantId: variant,
          beforeQty: before.quantity,
          beforeCostCents: before.unitCostCents,
          removedQty: 1000,
          removedUnitCostCents: 1000,
          costingMethod: 'wac',
          scope: scope,
        );
        expect(resolved, 200);
      });
      expect((await balance()).quantity, 1000);
      expect((await balance()).unitCostCents, 200);
      expect(await fixtures.legacySnapshot(db), old);
    },
  );

  for (final simple in [false, true]) {
    test(
      'direct cost write leaves global previous cost unchanged: simple=$simple',
      () async {
        final old = await fixtures.legacySnapshot(db);
        if (simple) {
          await ProductCostService.setProductCost(
            db.productDao,
            productId: product,
            newCostCents: 456,
            scope: scope,
          );
        } else {
          await ProductCostService.setVariantCost(
            db.productDao,
            variantId: variant,
            newCostCents: 456,
            scope: scope,
          );
        }
        expect((await balance()).unitCostCents, 456);
        expect((await balance()).quantity, 1000);
        expect(await fixtures.legacySnapshot(db), old);
      },
    );
  }

  test('secondary product-only projection is rejected', () async {
    await expectLater(
      ProductCostService.setProductCost(
        db.productDao,
        productId: product,
        newCostCents: 456,
        mirrorToDefaultVariant: false,
        scope: scope,
      ),
      throwsStateError,
    );
    expect((await balance()).unitCostCents, 200);
  });

  test('missing secondary cost row cannot fall back to global cost', () async {
    final empty = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: empty,
            organizationId: scope.organizationId,
            branchId: scope.branchId,
            code: 'EMPTY-COST',
          ),
        );
    scope = await WarehouseOperationScope.resolve(db, warehouseId: empty);
    final old = await fixtures.legacySnapshot(db);
    await expectLater(
      ProductCostService.setProductCost(
        db.productDao,
        productId: product,
        newCostCents: 456,
        scope: scope,
      ),
      throwsStateError,
    );
    expect(await fixtures.legacySnapshot(db), old);
  });

  test('deactivated selected warehouse rejects cost writes', () async {
    await (db.update(db.businessWarehouses)
          ..where((w) => w.id.equals(scope.warehouseId)))
        .write(const BusinessWarehousesCompanion(isActive: Value(false)));
    await expectLater(
      ProductCostService.setVariantCost(
        db.productDao,
        variantId: variant,
        newCostCents: 456,
        scope: scope,
      ),
      throwsStateError,
    );
    expect((await balance()).unitCostCents, 200);
  });

  test('failed cost write rolls back the preceding quantity movement', () async {
    final old = await fixtures.legacySnapshot(db);
    await db.customStatement(
      "CREATE TRIGGER fail_selected_cost BEFORE UPDATE OF unit_cost_cents ON business_warehouse_stocks BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    await expectLater(purchase('wac', true), throwsA(anything));
    expect((await balance()).quantity, 1000);
    expect((await balance()).unitCostCents, 200);
    expect(await fixtures.legacySnapshot(db), old);
  });

  test(
    'a multivariant product cannot route cost through the simple path',
    () async {
      await (db.update(db.products)..where((p) => p.id.equals(product))).write(
        const ProductsCompanion(hasVariants: Value(true)),
      );
      await expectLater(
        ProductCostService.setProductCost(
          db.productDao,
          productId: product,
          newCostCents: 456,
          scope: scope,
        ),
        throwsStateError,
      );
      expect((await balance()).unitCostCents, 200);
    },
  );
}
