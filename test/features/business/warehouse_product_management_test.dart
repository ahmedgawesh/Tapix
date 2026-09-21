import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/product_dao.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:tapix/features/products/data/datasources/product_local_datasource.dart';
import 'package:tapix/features/products/data/datasources/variant_local_datasource.dart';
import 'package:tapix/features/products/data/repositories/product_repository_impl.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

class _Session extends Mock implements SessionService {}

void main() {
  late AppDatabase db;
  late int product, variant, emptyProduct;
  late String other;
  setUp(() async {
    db = fixtures.memoryDb();
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      "INSERT INTO users (id, username, password_hash, role, is_active, created_at, updated_at) VALUES (0, 'system', 'no-pin', 'owner', 1, 0, 0)",
    );
    product = await db.customInsert(
      "INSERT INTO products (name, cost_cents, price_cents) VALUES ('Stocked', 500, 1000)",
    );
    emptyProduct = await db.customInsert(
      "INSERT INTO products (name, cost_cents, price_cents) VALUES ('Empty', 0, 1000)",
    );
    variant = await db.customInsert(
      'INSERT INTO product_variants (product_id, cost_cents, price_cents) VALUES (?, 500, 1000)',
      variables: [Variable.withInt(product)],
    );
    final scope = await BusinessFoundationRepository(db).getScope();
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
  Future<void> remote(int quantity) async {
    await (db.update(db.businessWarehouseStocks)
          ..where((s) => s.warehouseId.equals(other)))
        .write(BusinessWarehouseStocksCompanion(quantity: Value(quantity)));
  }

  Future<void> attempt(String action) async {
    switch (action) {
      case 'update':
        final row = await (db.select(
          db.products,
        )..where((p) => p.id.equals(product))).getSingle();
        await db.productDao.updateProduct(
          row.copyWith(isActive: false, stockQuantity: 0),
        );
      case 'delete':
        await db.productDao.deleteProduct(product);
      case 'smart':
        await db.productDao.smartDeleteProduct(product);
      case 'deactivate':
        await db.productDao.deactivateProduct(product);
      case 'bulkDelete':
        await db.productDao.bulkDeleteProducts([emptyProduct, product]);
      case 'bulkDeactivate':
        await db.productDao.bulkDeactivateProducts([emptyProduct, product]);
    }
  }

  for (final quantity in [5, -5]) {
    for (final action in [
      'update',
      'delete',
      'smart',
      'deactivate',
      'bulkDelete',
      'bulkDeactivate',
    ]) {
      test('$action rejects remote stock $quantity atomically', () async {
        await remote(quantity);
        final before = await fixtures.legacySnapshot(db);
        await expectLater(
          attempt(action),
          throwsA(isA<ProductStockNotZeroException>()),
        );
        expect(await fixtures.legacySnapshot(db), before);
      });
    }
  }
  test(
    'disabled remote warehouse and inactive variant still block deletion',
    () async {
      await db.customStatement(
        'UPDATE business_warehouses SET is_active = 0 WHERE id = ?',
        [other],
      );
      await db.customStatement(
        'UPDATE product_variants SET is_active = 0 WHERE id = ?',
        [variant],
      );
      await expectLater(
        attempt('smart'),
        throwsA(isA<ProductStockNotZeroException>()),
      );
    },
  );
  test('legacy product stock without any variant blocks hiding', () async {
    await db.customStatement(
      'UPDATE products SET stock_quantity = 3 WHERE id = ?',
      [emptyProduct],
    );
    await expectLater(
      db.productDao.deactivateProduct(emptyProduct),
      throwsA(isA<ProductStockNotZeroException>()),
    );
  });
  test('local stock blocks direct deletion until settled', () async {
    await remote(0);
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = 3 WHERE id = ?',
      [variant],
    );
    await expectLater(
      attempt('delete'),
      throwsA(isA<ProductStockNotZeroException>()),
    );
  });
  test('all-zero bulk deletion remains supported', () async {
    await remote(0);
    expect(await db.productDao.bulkDeleteProducts([emptyProduct, product]), 2);
    expect(await db.select(db.products).get(), isEmpty);
  });
  test('empty bulk requests remain no-ops', () async {
    expect(await db.productDao.bulkDeleteProducts([]), 0);
    expect(await db.productDao.bulkDeactivateProducts([]), 0);
  });

  ProductRepositoryImpl repository() {
    final session = _Session();
    when(() => session.getCurrentUserId()).thenAnswer((_) async => 0);
    return ProductRepositoryImpl(
      ProductLocalDatasourceImpl(db.productDao),
      AuditLogService(db),
      session,
      variantDatasource: VariantLocalDatasourceImpl(
        db.productVariantDao,
        db.productColorDao,
        db.sizeDao,
      ),
      adjustmentService: InventoryAdjustmentService(
        db: db,
        dao: InventoryAdjustmentDao(db),
        journal: JournalEntryService(AccountingRepository(db)),
      ),
    );
  }

  test(
    'remote stock rejection rolls back local writeoff and its journal',
    () async {
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = 3 WHERE id = ?',
        [variant],
      );
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        repository().writeOffAndDeleteProduct(
          productId: product,
          reason: 'Test writeoff',
        ),
        throwsA(isA<ProductStockNotZeroException>()),
      );
      expect(await fixtures.legacySnapshot(db), before);
      expect(await db.select(db.inventoryAdjustments).get(), isEmpty);
      expect(await db.select(db.journalEntries).get(), isEmpty);
    },
  );
  test('settled local stock allows atomic writeoff and soft deletion', () async {
    await remote(0);
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = 3 WHERE id = ?',
      [variant],
    );
    final result = await repository().writeOffAndDeleteProduct(
      productId: product,
      reason: 'Test writeoff',
    );
    expect(result.wasDeleted, isFalse);
    final row = await (db.select(
      db.products,
    )..where((p) => p.id.equals(product))).getSingle();
    expect(row.isActive, isFalse);
    expect(row.stockQuantity, 0);
    expect(await db.select(db.inventoryAdjustments).get(), hasLength(1));
    final journal = await db
        .customSelect(
          'SELECT SUM(debit_cents) AS dr, SUM(credit_cents) AS cr FROM journal_entry_lines',
        )
        .getSingle();
    expect(journal.read<int>('dr'), 1500);
    expect(journal.read<int>('cr'), 1500);
  });

  test('audit failure rolls back writeoff and product deactivation', () async {
    await remote(0);
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = 3 WHERE id = ?',
      [variant],
    );
    final before = await fixtures.legacySnapshot(db);
    await db.customStatement(
      "CREATE TRIGGER fail_product_audit BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END",
    );
    await expectLater(
      repository().writeOffAndDeleteProduct(
        productId: product,
        reason: 'Test writeoff',
      ),
      throwsA(anything),
    );
    expect(await fixtures.legacySnapshot(db), before);
    expect(await db.select(db.inventoryAdjustments).get(), isEmpty);
    expect(await db.select(db.journalEntries).get(), isEmpty);
  });

  test('smart deletion and its audit also roll back together', () async {
    final before = await fixtures.legacySnapshot(db);
    await db.customStatement(
      "CREATE TRIGGER fail_product_audit BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END",
    );
    await expectLater(
      repository().smartDeleteProduct(emptyProduct),
      throwsA(anything),
    );
    expect(await fixtures.legacySnapshot(db), before);
  });
}
