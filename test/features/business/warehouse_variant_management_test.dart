import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/product_variant_dao.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int product, variant;
  late String primary, other;
  setUp(() async {
    db = fixtures.memoryDb();
    await db.customSelect('SELECT 1').get();
    product = await db.customInsert(
      "INSERT INTO products (name, has_variants, cost_cents, price_cents) VALUES ('Warehouse variant', 1, 0, 1000)",
    );
    final size = await db.customInsert(
      "INSERT INTO sizes (name) VALUES ('Size')",
    );
    variant = await db.customInsert(
      'INSERT INTO product_variants (product_id, size_id, cost_cents, price_cents) VALUES (?, ?, 0, 1000)',
      variables: [Variable.withInt(product), Variable.withInt(size)],
    );
    final scope = await BusinessFoundationRepository(db).getScope();
    primary = scope.warehouseId;
    other = const Uuid().v4();
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
            quantity: const Value(5),
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> remoteQuantity(int value) =>
      (db.update(db.businessWarehouseStocks)
            ..where((s) => s.warehouseId.equals(other)))
          .write(BusinessWarehouseStocksCompanion(quantity: Value(value)));
  Future<void> attempt(String action) async {
    switch (action) {
      case 'update':
        final row = (await db.productVariantDao.getVariantById(variant))!;
        await db.productVariantDao.updateVariant(row.copyWith(isActive: false));
      case 'delete':
        await db.productVariantDao.deleteVariant(variant);
      case 'smart':
        await db.productVariantDao.smartDeleteVariant(variant);
      case 'bulk':
        await db.productVariantDao.deactivateDimensionalVariants(product);
    }
  }

  for (final quantity in [5, -5]) {
    for (final action in ['update', 'delete', 'smart', 'bulk']) {
      test('$action refuses nonzero remote quantity $quantity', () async {
        await remoteQuantity(quantity);
        final before = await fixtures.legacySnapshot(db);
        expect(
          await db.productVariantDao.countActiveDimensionalVariantsWithStock(
            product,
          ),
          1,
        );
        await expectLater(
          attempt(action),
          throwsA(isA<VariantStockNotZeroException>()),
        );
        expect(await fixtures.legacySnapshot(db), before);
        expect(
          (await db.productVariantDao.getVariantById(variant))!.isActive,
          isTrue,
        );
      });
    }
  }

  test(
    'stock in a disabled warehouse still prevents hiding a shared variant',
    () async {
      await (db.update(db.businessWarehouses)..where((w) => w.id.equals(other)))
          .write(const BusinessWarehousesCompanion(isActive: Value(false)));
      await expectLater(
        attempt('update'),
        throwsA(isA<VariantStockNotZeroException>()),
      );
      expect(
        await db.productDao.getCostingMethodLockReason(product),
        'has_stock',
      );
    },
  );

  test(
    'remote stock locks costing, measurement and inventory tracking',
    () async {
      expect(
        await db.productDao.setCostingMethod(
          productId: product,
          method: 'fifo',
        ),
        'has_stock',
      );
      expect(
        await db.productDao.setMeasurementType(
          productId: product,
          measurementType: 'weight',
        ),
        'has_stock',
      );
      expect(
        await db.productDao.setTrackInventory(
          productId: product,
          trackInventory: false,
        ),
        'has_stock',
      );
      expect(
        await db.productDao.setInventoryTrackingType(
          productId: product,
          trackingType: 'batch_expiry',
        ),
        'has_stock',
      );
      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(product))).getSingle();
      expect(row.costingMethod, 'wac');
      expect(row.measurementType, 'piece');
      expect(row.trackInventory, isTrue);
    },
  );

  test(
    'all-zero locations retain normal deactivation and lock behavior',
    () async {
      await remoteQuantity(0);
      expect(await db.productDao.getCostingMethodLockReason(product), isNull);
      await attempt('update');
      expect(
        (await db.productVariantDao.getVariantById(variant))!.isActive,
        isFalse,
      );
    },
  );

  test(
    'local summary excludes remote stock and updates on warehouse-only writes',
    () async {
      final events = StreamIterator(
        db.productVariantDao.watchVariantSummaries(),
      );
      // Test only: disconnect the legacy mirror to prove the read authority.
      await db.customStatement('DROP TRIGGER business_stock_primary_update');
      try {
        expect(await events.moveNext(), isTrue);
        expect(events.current[product], (count: 1, totalStock: 0));
        await (db.update(db.businessWarehouseStocks)
              ..where((s) => s.warehouseId.equals(primary)))
            .write(const BusinessWarehouseStocksCompanion(quantity: Value(7)));
        do {
          expect(
            await events.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
        } while (events.current[product]?.totalStock != 7);
        expect(await db.productVariantDao.getVariantSummaryByProduct(product), (
          count: 1,
          totalStock: 7,
        ));
        expect(
          (await db.productVariantDao.getVariantById(variant))!.stockQuantity,
          0,
        );
      } finally {
        await events.cancel();
      }
    },
  );

  test(
    'missing primary balance is not represented as an empty local stock',
    () async {
      await db.customStatement('DROP TRIGGER business_stock_retain');
      await db.customStatement(
        'DELETE FROM business_warehouse_stocks WHERE warehouse_id = ?',
        [primary],
      );
      await expectLater(
        db.productVariantDao.getVariantSummaryByProduct(product),
        throwsStateError,
      );
      await expectLater(
        db.productVariantDao.watchVariantSummaries().first,
        throwsStateError,
      );
    },
  );

  test(
    'equal opposite warehouse balances do not cancel the protection',
    () async {
      final scope = await BusinessFoundationRepository(db).getScope();
      final third = const Uuid().v4();
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: third,
              organizationId: scope.organizationId,
              branchId: scope.branchId,
              code: 'THIRD',
            ),
          );
      await db
          .into(db.businessWarehouseStocks)
          .insert(
            BusinessWarehouseStocksCompanion.insert(
              warehouseId: third,
              variantId: variant,
              quantity: const Value(-5),
            ),
          );
      await expectLater(
        attempt('smart'),
        throwsA(isA<VariantStockNotZeroException>()),
      );
      expect(
        await db.productDao.getCostingMethodLockReason(product),
        'has_stock',
      );
    },
  );
}
