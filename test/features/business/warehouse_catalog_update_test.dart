import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late Product product;
  late ProductVariant variant;
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    variant = (await db.select(db.productVariants).get()).first;
    product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(variant.productId))).getSingle();
    for (final table in ['products', 'product_variants']) {
      final id = table == 'products' ? product.id : variant.id;
      await db.customStatement(
        'UPDATE $table SET previous_cost_cents = 601, previous_price_cents = 901, previous_wholesale_price_cents = 801, last_purchase_price_cents = 751 WHERE id = ?',
        [id],
      );
    }
    product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(product.id))).getSingle();
    variant = (await db.productVariantDao.getVariantById(variant.id))!;
  });
  tearDown(() => db.close());
  Future<Map<String, Object?>> protected(String table, int id) async =>
      (await db
              .customSelect(
                'SELECT stock_quantity, cost_cents, previous_cost_cents, previous_price_cents, previous_wholesale_price_cents, last_purchase_price_cents, created_at FROM $table WHERE id = $id',
              )
              .getSingle())
          .data;
  Future<void> rejectFinancialWrites(String table) => db.customStatement(
    "CREATE TRIGGER forbid_${table}_financial_update BEFORE UPDATE OF stock_quantity, cost_cents ON $table BEGIN SELECT RAISE(ABORT, 'catalog touched financial fields'); END",
  );

  test(
    'variant catalog update omits financial columns even with stale input',
    () async {
      final before = await protected('product_variants', variant.id);
      final balances = await db.select(db.businessWarehouseStocks).get();
      await rejectFinancialWrites('product_variants');
      final stale = variant.copyWith(
        stockQuantity: 0,
        costCents: Decimal.fromInt(9999),
        previousCostCents: const Value(null),
        previousPriceCents: const Value(null),
        previousWholesalePriceCents: const Value(null),
        lastPurchasePriceCents: const Value(null),
        createdAt: DateTime(2000),
        sku: const Value('NEW-SKU'),
        priceCents: Decimal.fromInt(1500),
      );
      expect(await db.productVariantDao.updateVariant(stale), isTrue);
      expect(await protected('product_variants', variant.id), before);
      expect(await db.select(db.businessWarehouseStocks).get(), balances);
      final actual = (await db.productVariantDao.getVariantById(variant.id))!;
      expect(actual.sku, 'NEW-SKU');
      expect(actual.priceCents, Decimal.fromInt(1500));
    },
  );

  test(
    'product catalog update preserves financial fields and inventory policy',
    () async {
      final before = await protected('products', product.id);
      await rejectFinancialWrites('products');
      final stale = product.copyWith(
        name: 'Renamed',
        stockQuantity: 0,
        costCents: Decimal.fromInt(9999),
        previousCostCents: const Value(null),
        previousPriceCents: const Value(null),
        previousWholesalePriceCents: const Value(null),
        lastPurchasePriceCents: const Value(null),
        createdAt: DateTime(2000),
        trackInventory: false,
        measurementType: 'volume',
        costingMethod: 'last',
        inventoryTrackingType: 'batch_expiry',
        priceCents: Decimal.fromInt(1500),
      );
      expect(await db.productDao.updateProduct(stale), isTrue);
      expect(await protected('products', product.id), before);
      final actual = await (db.select(
        db.products,
      )..where((p) => p.id.equals(product.id))).getSingle();
      expect(actual.name, 'Renamed');
      expect(actual.priceCents, Decimal.fromInt(1500));
      expect(actual.trackInventory, product.trackInventory);
      expect(actual.measurementType, product.measurementType);
      expect(actual.costingMethod, product.costingMethod);
      expect(actual.inventoryTrackingType, product.inventoryTrackingType);
    },
  );

  test(
    'renaming an active product does not reactivate retired variants',
    () async {
      final size = await db.customInsert(
        "INSERT INTO sizes (name) VALUES ('Retired size')",
      );
      final retired = await db.customInsert(
        'INSERT INTO product_variants (product_id, size_id, cost_cents, price_cents, is_active) VALUES (?, ?, 0, 1000, 0)',
        variables: [Variable.withInt(product.id), Variable.withInt(size)],
      );
      await db.productDao.updateProduct(product.copyWith(name: 'Renamed'));
      expect(
        (await db.productVariantDao.getVariantById(retired))!.isActive,
        isFalse,
      );
      expect(
        (await db.productVariantDao.getVariantById(variant.id))!.isActive,
        isTrue,
      );
    },
  );

  test(
    'explicit activation changes still propagate to variants after settlement',
    () async {
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = 0 WHERE product_id = ?',
        [product.id],
      );
      await db.customStatement(
        'UPDATE products SET stock_quantity = 0 WHERE id = ?',
        [product.id],
      );
      await db.productDao.updateProduct(product.copyWith(isActive: false));
      expect(
        (await db.productVariantDao.getVariantById(variant.id))!.isActive,
        isFalse,
      );
      await db.productDao.updateProduct(product.copyWith(isActive: true));
      expect(
        (await db.productVariantDao.getVariantById(variant.id))!.isActive,
        isTrue,
      );
    },
  );

  test(
    'unknown variant update has no parent or warehouse side effects',
    () async {
      final before = await fixtures.legacySnapshot(db);
      expect(
        await db.productVariantDao.updateVariant(
          variant.copyWith(id: variant.id + 99999),
        ),
        isFalse,
      );
      expect(await fixtures.legacySnapshot(db), before);
    },
  );

  test('unknown product update remains a no-op', () async {
    final before = await fixtures.legacySnapshot(db);
    expect(
      await db.productDao.updateProduct(
        product.copyWith(id: product.id + 99999),
      ),
      isFalse,
    );
    expect(await fixtures.legacySnapshot(db), before);
  });

  test(
    'variant cannot be reassigned to another product by catalog edit',
    () async {
      final another = (await db.select(db.products).get()).firstWhere(
        (p) => p.id != product.id,
      );
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        db.productVariantDao.updateVariant(
          variant.copyWith(productId: another.id),
        ),
        throwsStateError,
      );
      expect(await fixtures.legacySnapshot(db), before);
    },
  );

  test('outer rollback also reverts catalog metadata changes', () async {
    final before = await fixtures.legacySnapshot(db);
    await expectLater(
      db.transaction(() async {
        await db.productVariantDao.updateVariant(
          variant.copyWith(sku: const Value('ROLLBACK')),
        );
        await db.productDao.updateProduct(product.copyWith(name: 'ROLLBACK'));
        throw StateError('injected failure');
      }),
      throwsStateError,
    );
    expect(await fixtures.legacySnapshot(db), before);
  });
}
