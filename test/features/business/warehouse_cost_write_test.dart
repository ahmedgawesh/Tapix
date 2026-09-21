import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/inventory/product_cost_service.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int variant, product;
  late String warehouse;
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
    warehouse = (await BusinessFoundationRepository(db).getScope()).warehouseId;
  });
  tearDown(() => db.close());

  Future<int> cost() async =>
      (await db
              .customSelect(
                'SELECT unit_cost_cents FROM business_warehouse_stocks WHERE warehouse_id = ? AND variant_id = ?',
                variables: [
                  Variable.withString(warehouse),
                  Variable.withInt(variant),
                ],
              )
              .getSingle())
          .read<int>('unit_cost_cents');
  Future<void> setCost(int value) => ProductCostService.setVariantCost(
    db.productDao,
    variantId: variant,
    newCostCents: value,
  );
  Future<int> previous() async =>
      (await db
              .customSelect(
                'SELECT previous_cost_cents FROM product_variants WHERE id = $variant',
              )
              .getSingle())
          .read<int>('previous_cost_cents');
  Future<void> failCost() => db.customStatement(
    "CREATE TRIGGER injected_cost_failure BEFORE UPDATE OF unit_cost_cents ON business_warehouse_stocks BEGIN SELECT RAISE(ABORT, 'injected cost failure'); END",
  );

  test(
    'cost write changes only primary balance and retains previous cost',
    () async {
      final scope = await BusinessFoundationRepository(db).getScope();
      final second = const Uuid().v4();
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: second,
              organizationId: scope.organizationId,
              branchId: scope.branchId,
              code: 'OTHER',
            ),
          );
      await db
          .into(db.businessWarehouseStocks)
          .insert(
            BusinessWarehouseStocksCompanion.insert(
              warehouseId: second,
              variantId: variant,
              quantity: const Value(99),
              unitCostCents: const Value(999),
            ),
          );
      await setCost(801);
      expect(await cost(), 801);
      expect(await previous(), 701);
      final other = await (db.select(
        db.businessWarehouseStocks,
      )..where((s) => s.warehouseId.equals(second))).getSingle();
      expect(other.unitCostCents, 999);
      expect(other.quantity, 99);
      final projection = await db
          .customSelect(
            'SELECT cost_cents, stock_quantity FROM product_variants WHERE id = $variant',
          )
          .getSingle();
      expect(projection.read<int>('cost_cents'), 801);
      expect(projection.read<int>('stock_quantity'), 1234);
    },
  );

  test(
    'purchase blending preserves previous-cost contract and WAC formula',
    () async {
      await setCost(800);
      final oldPrevious = await previous();
      final blended = await ProductCostService.applyPurchaseCostToVariant(
        db.purchaseDao,
        variantId: variant,
        beforeQty: 10,
        beforeCostCents: 800,
        addedQty: 10,
        newPaidCostCents: 1000,
        costingMethod: 'wac',
      );
      expect(blended, 900);
      expect(await cost(), 900);
      expect(await previous(), oldPrevious);
    },
  );

  test('inverse inbound cost restores original WAC', () async {
    await setCost(900);
    final restored = await ProductCostService.applyRemovalCostToVariant(
      db.saleDao,
      variantId: variant,
      beforeQty: 20,
      beforeCostCents: 900,
      removedQty: 10,
      removedUnitCostCents: 1000,
      costingMethod: 'wac',
    );
    expect(restored, 800);
    expect(await cost(), 800);
    expect(await previous(), 900);
  });

  test(
    'failure rolls back previous-cost metadata without outer transaction',
    () async {
      final before = await fixtures.legacySnapshot(db);
      await failCost();
      await expectLater(setCost(801), throwsA(anything));
      expect(await cost(), 701);
      expect(await fixtures.legacySnapshot(db), before);
    },
  );

  test('parent and operational cost roll back together', () async {
    final before = await fixtures.legacySnapshot(db);
    await failCost();
    await expectLater(
      ProductCostService.setProductCost(
        db.productDao,
        productId: product,
        newCostCents: 801,
      ),
      throwsA(anything),
    );
    expect(await cost(), 701);
    expect(await fixtures.legacySnapshot(db), before);
  });

  for (final table in ['business_warehouses', 'business_branches']) {
    test(
      'disabled $table blocks quantity and cost with no side effects',
      () async {
        await db.customStatement('UPDATE $table SET is_active = 0');
        final before = await fixtures.legacySnapshot(db);
        await expectLater(setCost(801), throwsStateError);
        await expectLater(
          ProductCostService.setProductCost(
            db.productDao,
            productId: product,
            newCostCents: 801,
          ),
          throwsStateError,
        );
        for (final id in [null, variant]) {
          await expectLater(
            StockService.adjustStock(
              db.productDao,
              productId: product,
              variantId: id,
              quantity: 1,
              direction: StockDirection.increase,
            ),
            throwsStateError,
          );
        }
        expect(await cost(), 701);
        expect(await fixtures.legacySnapshot(db), before);
      },
    );
  }

  test('unknown variant cannot silently succeed', () async {
    await expectLater(
      ProductCostService.setVariantCost(
        db.productDao,
        variantId: variant + 99999,
        newCostCents: 801,
      ),
      throwsStateError,
    );
    expect(await cost(), 701);
  });

  test('warehouse watcher receives direct service cost updates', () async {
    final events = StreamIterator(
      (db.select(db.businessWarehouseStocks)..where(
            (s) =>
                s.variantId.equals(variant) & s.warehouseId.equals(warehouse),
          ))
          .watchSingle(),
    );
    try {
      expect(await events.moveNext(), isTrue);
      expect(events.current.unitCostCents, 701);
      await setCost(801);
      expect(
        await events.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      expect(events.current.unitCostCents, 801);
    } finally {
      await events.cancel();
    }
  });

  test(
    'outer posting rollback includes warehouse and cost projection',
    () async {
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        db.transaction(() async {
          await setCost(801);
          throw StateError('posting failure');
        }),
        throwsStateError,
      );
      expect(await cost(), 701);
      expect(await fixtures.legacySnapshot(db), before);
    },
  );

  test(
    'simple product with optional size mirrors cost to its operational row',
    () async {
      final size = await db.customInsert(
        "INSERT INTO sizes (name) VALUES ('Optional size')",
      );
      await db.customStatement(
        'UPDATE product_variants SET size_id = ? WHERE id = ?',
        [size, variant],
      );
      await ProductCostService.setProductCost(
        db.productDao,
        productId: product,
        newCostCents: 801,
      );
      expect(await cost(), 801);
      expect(await previous(), 701);
      final parent = await db
          .customSelect(
            'SELECT cost_cents, previous_cost_cents FROM products WHERE id = $product',
          )
          .getSingle();
      expect(parent.read<int>('cost_cents'), 801);
      expect(parent.read<int>('previous_cost_cents'), 701);
    },
  );

  test('ambiguous simple-product mirror rejects and rolls back parent', () async {
    final size = await db.customInsert(
      "INSERT INTO sizes (name) VALUES ('Second size')",
    );
    await db.customStatement(
      'INSERT INTO product_variants (product_id, size_id, cost_cents, price_cents) VALUES (?, ?, 999, 1200)',
      [product, size],
    );
    final before = await fixtures.legacySnapshot(db);
    await expectLater(
      ProductCostService.setProductCost(
        db.productDao,
        productId: product,
        newCostCents: 801,
      ),
      throwsStateError,
    );
    expect(await cost(), 701);
    expect(await fixtures.legacySnapshot(db), before);
  });
}
