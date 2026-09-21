import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/data_integrity_service.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int product, variant;
  late String warehouse;
  late DataIntegrityService integrity;
  setUp(() async {
    db = fixtures.memoryDb();
    product = await db.customInsert(
      "INSERT INTO products (name, cost_cents, price_cents, stock_quantity) VALUES ('Local', 500, 1000, 99)",
    );
    variant = await db.customInsert(
      'INSERT INTO product_variants (product_id, cost_cents, price_cents, stock_quantity) VALUES (?, 500, 1000, 99)',
      variables: [Variable.withInt(product)],
    );
    warehouse = (await BusinessFoundationRepository(db).getScope()).warehouseId;
    integrity = DataIntegrityService(db);
    // Test-only divergence proves reads use the ledger rather than mirrors.
    await db.customStatement('DROP TRIGGER business_stock_primary_update');
  });
  tearDown(() => db.close());
  Future<void> quantity(int value) async {
    await (db.update(db.businessWarehouseStocks)..where(
          (s) => s.warehouseId.equals(warehouse) & s.variantId.equals(variant),
        ))
        .write(BusinessWarehouseStocksCompanion(quantity: Value(value)));
  }

  Future<List<Product>> filter(String status) =>
      db.productDao.filterProducts(stockStatus: status);

  for (final hasVariants in [false, true]) {
    for (final qty in [0, 3, 8]) {
      test(
        'stock filters use local balance=$qty variants=$hasVariants',
        () async {
          await db.customStatement(
            'UPDATE products SET has_variants = ? WHERE id = ?',
            [hasVariants ? 1 : 0, product],
          );
          final size = await db.customInsert(
            "INSERT INTO sizes (name) VALUES ('Optional')",
          );
          await db.customStatement(
            'UPDATE product_variants SET size_id = ? WHERE id = ?',
            [size, variant],
          );
          await quantity(qty);
          final out = await filter('out_of_stock');
          final low = await filter('low_stock');
          expect(out.map((p) => p.id), qty == 0 ? [product] : isEmpty);
          expect(low.map((p) => p.id), qty == 3 ? [product] : isEmpty);
          if (out.isNotEmpty) expect(out.single.stockQuantity, 0);
          if (low.isNotEmpty) expect(low.single.stockQuantity, 3);
        },
      );
    }
  }
  test('product minimum overrides default threshold', () async {
    await quantity(8);
    await db.customStatement(
      'UPDATE products SET min_quantity = 10 WHERE id = ?',
      [product],
    );
    expect(await filter('low_stock'), hasLength(1));
  });
  test('remote quantity cannot hide local shortage', () async {
    await quantity(0);
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
            variantId: variant,
            quantity: const Value(1000),
          ),
        );
    expect(await filter('out_of_stock'), hasLength(1));
    expect(
      await integrity.validateStockDeduction(variantId: variant, quantity: 1),
      isFalse,
    );
  });
  test('warehouse-only update refreshes stock filter stream', () async {
    await quantity(8);
    final stream = StreamIterator(
      db.productDao.watchFilteredProducts(stockStatus: 'low_stock'),
    );
    try {
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, isEmpty);
      await quantity(2);
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      expect(stream.current.single.stockQuantity, 2);
    } finally {
      await stream.cancel();
    }
  });
  test('legacy product without variant retains stored balance', () async {
    final legacy = await db.customInsert(
      "INSERT INTO products (name, cost_cents, price_cents, stock_quantity) VALUES ('Legacy', 500, 1000, 2)",
    );
    expect((await filter('low_stock')).single.id, legacy);
  });
  test('deduction uses local quantity and rejects negative requests', () async {
    await quantity(3);
    expect(
      await integrity.validateStockDeduction(variantId: variant, quantity: 3),
      isTrue,
    );
    expect(
      await integrity.validateStockDeduction(variantId: variant, quantity: 4),
      isFalse,
    );
    expect(
      await integrity.validateStockDeduction(variantId: variant, quantity: -1),
      isFalse,
    );
  });
  test(
    'negative balance visible when warehouse disabled but deduction denied',
    () async {
      await quantity(-2);
      await db.customStatement(
        'UPDATE business_warehouses SET is_active = 0 WHERE id = ?',
        [warehouse],
      );
      final bad = await integrity.findNegativeStockVariants();
      expect(bad.single.variantId, variant);
      expect(bad.single.stockQuantity, -2);
      await quantity(3);
      expect(
        await integrity.validateStockDeduction(variantId: variant, quantity: 1),
        isFalse,
      );
      expect(await filter('low_stock'), hasLength(1));
    },
  );
  test('missing primary balance cannot authorize deduction', () async {
    await db.customStatement('DROP TRIGGER business_stock_retain');
    await db.customStatement(
      'DELETE FROM business_warehouse_stocks WHERE variant_id = ?',
      [variant],
    );
    expect(
      await integrity.validateStockDeduction(variantId: variant, quantity: 1),
      isFalse,
    );
  });
}
