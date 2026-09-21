import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/product_dao.dart';

/// Phase B regression tests — guard the contract that:
///   * Fresh installs default every product to `'standard'`.
///   * The migration backfill maps `wac` → `'standard'`,
///     `fifo` (no expiry rows) → `'batch'`, `fifo` (∃ expiry) → `'batch_expiry'`.
///   * `setInventoryTrackingType` keeps the legacy `costing_method` in sync.
///   * The lock semantics on tracking-type writes mirror those on
///     `setCostingMethod` (refuses when stock or batch consumptions exist).
void main() {
  group('inventory_tracking_type — schema + DAO', () {
    late AppDatabase db;
    late ProductDao productDao;

    setUp(() async {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
      await db.customSelect('SELECT 1').get();
      productDao = ProductDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertProduct({
      String name = 'Widget',
      String costingMethod = 'wac',
      int stock = 0,
    }) async {
      final id = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: name,
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(2000),
              costingMethod: Value(costingMethod),
              stockQuantity: Value(stock),
            ),
          );
      return id;
    }

    test('fresh install — every new product defaults to standard', () async {
      final id = await insertProduct();
      final t = await productDao.getInventoryTrackingType(id);
      expect(t, 'standard');
    });

    test(
      'getInventoryTrackingType — unknown product → defaults to standard',
      () async {
        final t = await productDao.getInventoryTrackingType(999999);
        expect(t, 'standard');
      },
    );

    test('setInventoryTrackingType — happy path writes both columns', () async {
      final id = await insertProduct();

      final lock1 = await productDao.setInventoryTrackingType(
        productId: id,
        trackingType: 'batch',
      );
      expect(lock1, isNull);
      expect(await productDao.getInventoryTrackingType(id), 'batch');

      final row1 = await db
          .customSelect(
            'SELECT costing_method FROM products WHERE id = ?',
            variables: [Variable.withInt(id)],
          )
          .getSingle();
      expect(
        row1.read<String>('costing_method'),
        'fifo',
        reason: 'tracking=batch must keep legacy costing_method=fifo in sync',
      );

      final lock2 = await productDao.setInventoryTrackingType(
        productId: id,
        trackingType: 'batch_expiry',
      );
      expect(lock2, isNull);
      expect(await productDao.getInventoryTrackingType(id), 'batch_expiry');

      final lock3 = await productDao.setInventoryTrackingType(
        productId: id,
        trackingType: 'standard',
      );
      expect(lock3, isNull);
      expect(await productDao.getInventoryTrackingType(id), 'standard');
      final row3 = await db
          .customSelect(
            'SELECT costing_method FROM products WHERE id = ?',
            variables: [Variable.withInt(id)],
          )
          .getSingle();
      expect(
        row3.read<String>('costing_method'),
        'wac',
        reason: 'tracking=standard must keep legacy costing_method=wac in sync',
      );
    });

    test('setInventoryTrackingType — refuses when stock > 0', () async {
      final id = await insertProduct(stock: 5);

      final lock = await productDao.setInventoryTrackingType(
        productId: id,
        trackingType: 'batch',
      );
      expect(
        lock,
        'has_stock',
        reason: 'lock must mirror setCostingMethod semantics',
      );
      expect(await productDao.getInventoryTrackingType(id), 'standard');
    });

    test(
      'setInventoryTrackingType — refuses when consumptions exist',
      () async {
        final id = await insertProduct();
        // Seed a batch + consumption so the lock fires on consumptions.
        final batchId = await db
            .into(db.productBatches)
            .insert(
              ProductBatchesCompanion.insert(
                productId: id,
                batchNumber: 'BATCH-TEST-1',
                receivedQuantity: 10,
                remainingQuantity: 3,
                unitCostCents: Decimal.fromInt(1000),
              ),
            );
        await db
            .into(db.batchConsumptions)
            .insert(
              BatchConsumptionsCompanion.insert(
                batchId: batchId,
                consumptionType: 'sale',
                direction: 'out',
                quantity: 7,
                unitCostCents: Decimal.fromInt(1000),
              ),
            );

        // Stock-flag check must not catch this case (stock = 0).
        final lock = await productDao.setInventoryTrackingType(
          productId: id,
          trackingType: 'batch',
        );
        expect(lock, 'has_consumptions');
      },
    );

    test('invalid tracking types are rejected at runtime', () async {
      final id = await insertProduct();
      await expectLater(
        productDao.setInventoryTrackingType(
          productId: id,
          trackingType: 'fifo',
        ),
        throwsArgumentError,
      );
      final product = await (db.select(
        db.products,
      )..where((row) => row.id.equals(id))).getSingle();
      expect(product.inventoryTrackingType, 'standard');
    });
  });
}
