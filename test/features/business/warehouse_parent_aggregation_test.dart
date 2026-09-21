import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/inventory/product_cost_service.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int product, first, second;
  late String warehouse;
  setUp(() async {
    db = fixtures.memoryDb();
    await db.customSelect('SELECT 1').get();
    product = await db.customInsert(
      "INSERT INTO products (name, has_variants, stock_quantity, cost_cents, price_cents) VALUES ('Aggregate', 1, 77, 777, 888)",
    );
    final size1 = await db.customInsert(
      "INSERT INTO sizes (name) VALUES ('First')",
    );
    final size2 = await db.customInsert(
      "INSERT INTO sizes (name) VALUES ('Second')",
    );
    first = await db.customInsert(
      'INSERT INTO product_variants (product_id, size_id, stock_quantity, cost_cents, price_cents) VALUES (?, ?, 2, 101, 1000)',
      variables: [Variable.withInt(product), Variable.withInt(size1)],
    );
    second = await db.customInsert(
      'INSERT INTO product_variants (product_id, size_id, stock_quantity, cost_cents, price_cents) VALUES (?, ?, 3, 201, 1200)',
      variables: [Variable.withInt(product), Variable.withInt(size2)],
    );
    warehouse = (await BusinessFoundationRepository(db).getScope()).warehouseId;
    // Test only: stale display fields must not become the aggregation source.
    await db.customStatement('DROP TRIGGER business_stock_variant_update');
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = 100, cost_cents = 9999 WHERE product_id = ?',
      [product],
    );
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> parent() async =>
      (await db
              .customSelect(
                'SELECT stock_quantity, cost_cents, price_cents FROM products WHERE id = $product',
              )
              .getSingle())
          .data;
  Future<void> sync({bool stock = true, bool cost = true, bool price = true}) =>
      ProductCostService.syncProductFromVariants(
        db.productDao,
        productId: product,
        syncStock: stock,
        syncCost: cost,
        syncPrice: price,
      );
  Future<void> syncStock() => StockService.syncProductStockFromVariants(
    db.productDao,
    productId: product,
  );

  for (final stock in [false, true]) {
    for (final cost in [false, true]) {
      for (final price in [false, true]) {
        test(
          'warehouse aggregation flags stock=$stock cost=$cost price=$price',
          () async {
            await sync(stock: stock, cost: cost, price: price);
            expect(await parent(), {
              'stock_quantity': stock ? 5 : 77,
              'cost_cents': cost ? 161 : 777,
              'price_cents': price ? 1200 : 888,
            });
          },
        );
      }
    }
  }

  test(
    'stock-only service uses warehouse quantity and leaves prices unchanged',
    () async {
      await syncStock();
      expect(await parent(), {
        'stock_quantity': 5,
        'cost_cents': 777,
        'price_cents': 888,
      });
    },
  );

  test(
    'secondary stock cannot change parent quantity or weighted cost',
    () async {
      final scope = await BusinessFoundationRepository(db).getScope();
      final other = const Uuid().v4();
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: other,
              organizationId: scope.organizationId,
              branchId: scope.branchId,
              code: 'OTHER',
            ),
          );
      await db
          .into(db.businessWarehouseStocks)
          .insert(
            BusinessWarehouseStocksCompanion.insert(
              warehouseId: other,
              variantId: first,
              quantity: const Value(999),
              unitCostCents: const Value(9000),
            ),
          );
      await sync();
      expect((await parent())['cost_cents'], 161);
      await syncStock();
      expect((await parent())['stock_quantity'], 5);
    },
  );

  test('zero stock retains average warehouse cost fallback', () async {
    await db.customStatement(
      'UPDATE business_warehouse_stocks SET quantity = 0',
    );
    await sync();
    expect((await parent())['stock_quantity'], 0);
    expect((await parent())['cost_cents'], 151);
  });

  test('inactive variant remains excluded from aggregation', () async {
    await db.customStatement(
      'UPDATE product_variants SET is_active = 0 WHERE id = ?',
      [second],
    );
    await sync();
    expect((await parent())['stock_quantity'], 2);
    expect((await parent())['cost_cents'], 101);
  });

  test('missing primary balance fails without saving partial totals', () async {
    await db.customStatement('DROP TRIGGER business_stock_retain');
    await db.customStatement(
      'DELETE FROM business_warehouse_stocks WHERE warehouse_id = ? AND variant_id = ?',
      [warehouse, second],
    );
    final before = await parent();
    await expectLater(sync(), throwsStateError);
    expect(await parent(), before);
    await expectLater(syncStock(), throwsStateError);
    expect(await parent(), before);
  });

  for (final table in ['business_warehouses', 'business_branches']) {
    test('inactive $table prevents parent writes', () async {
      await db.customStatement('UPDATE $table SET is_active = 0');
      final before = await parent();
      await expectLater(sync(), throwsStateError);
      await expectLater(syncStock(), throwsStateError);
      expect(await parent(), before);
    });
  }

  test('parent stream receives warehouse-derived aggregation', () async {
    final events = StreamIterator(
      (db.select(
        db.products,
      )..where((p) => p.id.equals(product))).watchSingle(),
    );
    try {
      expect(await events.moveNext(), isTrue);
      expect(events.current.stockQuantity, 77);
      await sync();
      expect(
        await events.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      expect(events.current.stockQuantity, 5);
    } finally {
      await events.cancel();
    }
  });

  test('outer transaction rollback restores parent aggregate', () async {
    final before = await parent();
    await expectLater(
      db.transaction(() async {
        await sync();
        throw StateError('posting failure');
      }),
      throwsStateError,
    );
    expect(await parent(), before);
  });

  test(
    'no active variants preserves legacy no-op cost and zero stock contracts',
    () async {
      await db.customStatement(
        'UPDATE product_variants SET is_active = 0 WHERE product_id = ?',
        [product],
      );
      final before = await parent();
      await sync();
      expect(await parent(), before);
      await syncStock();
      expect((await parent())['stock_quantity'], 0);
    },
  );
}
