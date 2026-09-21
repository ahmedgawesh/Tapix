import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/feature_gate_service.dart';
import 'package:tapix/core/services/free_quota_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/products/data/datasources/product_local_datasource.dart';
import 'package:tapix/features/products/data/datasources/variant_local_datasource.dart';
import 'package:tapix/features/products/data/repositories/category_repository_impl.dart';
import 'package:tapix/features/products/data/repositories/product_repository_impl.dart';
import 'package:tapix/features/products/data/repositories/product_variant_repository_impl.dart';
import 'package:tapix/features/products/domain/entities/import_file_data.dart';
import 'package:tapix/features/products/services/product_import_service.dart';

import 'business_foundation_test.dart' as fixtures;

class _Session extends Mock implements SessionService {}

class _Gate extends Mock implements FeatureGateService {}

void main() {
  late AppDatabase db;
  late ProductRepositoryImpl repo;
  late ProductImportService importer;
  late ProductVariantRepositoryImpl variants;
  late FreeQuotaService quota;
  setUp(() async {
    db = fixtures.memoryDb();
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      "INSERT INTO users (id, username, password_hash, role, is_active, created_at, updated_at) VALUES (0, 'system', 'no-pin', 'owner', 1, 0, 0)",
    );
    final session = _Session();
    when(() => session.getCurrentUserId()).thenAnswer((_) async => 0);
    final gate = _Gate();
    when(() => gate.isPro).thenReturn(false);
    SharedPreferences.setMockInitialValues({});
    quota = FreeQuotaService(
      prefs: await SharedPreferences.getInstance(),
      featureGateService: gate,
    );
    repo = ProductRepositoryImpl(
      ProductLocalDatasourceImpl(db.productDao),
      AuditLogService(db),
      session,
      freeQuotaService: quota,
    );
    variants = ProductVariantRepositoryImpl(
      VariantLocalDatasourceImpl(
        db.productVariantDao,
        db.productColorDao,
        db.sizeDao,
      ),
      InventoryAdjustmentService(
        db: db,
        dao: InventoryAdjustmentDao(db),
        journal: JournalEntryService(AccountingRepository(db)),
      ),
    );
    importer = ProductImportService(repo, variants, CategoryRepositoryImpl(db));
  });
  tearDown(() => db.close());
  Future<int> create() => repo.createProduct(
    name: 'Direct',
    costCents: Decimal.fromInt(500),
    priceCents: Decimal.fromInt(1000),
    stockQuantity: 0,
    minQuantity: 0,
  );
  BulkProductData row(int index, String name) => BulkProductData(
    rowIndex: index,
    name: name,
    costCents: Decimal.fromInt(500),
    priceCents: Decimal.fromInt(1000),
  );
  Future<void> failAudit({bool secondOnly = false}) => db.customStatement(
    "CREATE TRIGGER reject_audit BEFORE INSERT ON audit_logs ${secondOnly ? 'WHEN (SELECT COUNT(*) FROM audit_logs) > 0' : ''} BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END",
  );

  for (final quantity in [-2, 2]) {
    for (final kind in ['simple', 'variants', 'service']) {
      test('direct $kind creation rejects unposted stock $quantity', () async {
        final before = await fixtures.legacySnapshot(db);
        await expectLater(
          repo.createProduct(
            name: 'Direct',
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            stockQuantity: quantity,
            minQuantity: 0,
            hasVariants: kind == 'variants',
            trackInventory: kind != 'service',
          ),
          throwsArgumentError,
        );
        expect(await fixtures.legacySnapshot(db), before);
        expect(quota.productsCreatedLifetime, 0);
      });
    }
  }

  for (final policy in ['measurement', 'costing', 'tracking']) {
    test(
      'creation rejects invalid $policy without data or quota changes',
      () async {
        final before = await fixtures.legacySnapshot(db);
        for (final invalid in ['', 'unknown']) {
          await expectLater(
            repo.createProduct(
              name: 'Invalid policy',
              costCents: Decimal.fromInt(500),
              priceCents: Decimal.fromInt(1000),
              stockQuantity: 0,
              minQuantity: 0,
              measurementType: policy == 'measurement' ? invalid : 'piece',
              costingMethod: policy == 'costing' ? invalid : 'wac',
              inventoryTrackingType: policy == 'tracking'
                  ? invalid
                  : 'standard',
            ),
            throwsArgumentError,
          );
          expect(await fixtures.legacySnapshot(db), before);
          expect(quota.productsCreatedLifetime, 0);
        }
      },
    );
  }

  test('bulk rejects a nonzero parent balance atomically', () async {
    final before = await fixtures.legacySnapshot(db);
    await expectLater(
      repo.bulkCreateProducts([
        row(4, 'Valid'),
        BulkProductData(
          rowIndex: 9,
          name: 'Invalid',
          costCents: Decimal.fromInt(500),
          priceCents: Decimal.fromInt(1000),
          stockQuantity: 3,
        ),
      ]),
      throwsArgumentError,
    );
    expect(await fixtures.legacySnapshot(db), before);
    expect(quota.productsCreatedLifetime, 0);
  });

  test('direct supported aggregate posts opening stock exactly once', () async {
    final id = await repo.runInTransaction(() async {
      final id = await create();
      await variants.ensureDefaultVariantForProduct(
        productId: id,
        costCents: Decimal.fromInt(500),
        priceCents: Decimal.fromInt(1000),
        stockQuantity: 3,
      );
      await variants.ensureDefaultVariantForProduct(
        productId: id,
        costCents: Decimal.fromInt(500),
        priceCents: Decimal.fromInt(1000),
        stockQuantity: 3,
      );
      return id;
    });
    expect((await repo.getProductById(id))!.stockQuantity, 3);
    expect(await db.select(db.inventoryAdjustments).get(), hasLength(1));
    final stock = await db.select(db.businessWarehouseStocks).getSingle();
    expect(stock.quantity, 3);
    expect(quota.productsCreatedLifetime, 1);
  });

  test(
    'variant import starts parent at zero and aggregates every opening',
    () async {
      final result = await importer(
        fileData: const ImportFileData(
          fileName: 'variants.csv',
          fileType: ImportFileType.csv,
          headers: ['name', 'price', 'cost', 'stock_quantity', 'size'],
          rows: [
            ['Shared', '10', '5', '2', 'Small'],
            ['Shared', '10', '5', '3', 'Large'],
          ],
          totalRows: 2,
        ),
        columnMapping: const ColumnMapping({
          'name': 0,
          'price': 1,
          'cost': 2,
          'stock_quantity': 3,
          'size': 4,
        }),
      );
      expect(result.successfulRows, 2);
      final product = await db.select(db.products).getSingle();
      expect(product.hasVariants, isTrue);
      expect(product.stockQuantity, 5);
      expect(await db.select(db.productVariants).get(), hasLength(2));
      expect(await db.select(db.inventoryAdjustments).get(), hasLength(2));
      expect(quota.productsCreatedLifetime, 1);
      final journal = await db
          .customSelect(
            'SELECT SUM(debit_cents) AS dr, SUM(credit_cents) AS cr FROM journal_entry_lines',
          )
          .getSingle();
      expect(journal.read<int>('dr'), 2500);
      expect(journal.read<int>('cr'), 2500);
    },
  );

  test('direct create rolls back product on audit failure', () async {
    final before = await fixtures.legacySnapshot(db);
    await failAudit();
    await expectLater(create(), throwsA(anything));
    expect(await fixtures.legacySnapshot(db), before);
    expect(quota.productsCreatedLifetime, 0);
  });
  test(
    'bulk audit failure rolls back all products and earlier audit rows',
    () async {
      final before = await fixtures.legacySnapshot(db);
      await failAudit(secondOnly: true);
      await expectLater(
        repo.bulkCreateProducts([row(7, 'First'), row(42, 'Second')]),
        throwsA(anything),
      );
      expect(await fixtures.legacySnapshot(db), before);
      expect(quota.productsCreatedLifetime, 0);
    },
  );
  test(
    'sparse row indexes retain correct product and audit association',
    () async {
      final result = await repo.bulkCreateProducts([
        row(42, 'First'),
        row(7, 'Second'),
      ]);
      expect(result.keys.toList(), [42, 7]);
      expect((await repo.getProductById(result[42]!))!.name, 'First');
      expect((await repo.getProductById(result[7]!))!.name, 'Second');
      expect(await db.select(db.auditLogs).get(), hasLength(2));
      expect(quota.productsCreatedLifetime, 2);
    },
  );
  test('duplicate row indexes are rejected without writes', () async {
    final before = await fixtures.legacySnapshot(db);
    await expectLater(
      repo.bulkCreateProducts([row(7, 'First'), row(7, 'Second')]),
      throwsArgumentError,
    );
    expect(await fixtures.legacySnapshot(db), before);
    expect(quota.productsCreatedLifetime, 0);
  });
  test('outer failure restores direct and bulk creation and quota', () async {
    final before = await fixtures.legacySnapshot(db);
    await expectLater(
      repo.runInTransaction(() async {
        await create();
        await repo.bulkCreateProducts([row(9, 'Bulk')]);
        expect(quota.productsCreatedLifetime, 2);
        throw StateError('outer failure');
      }),
      throwsStateError,
    );
    expect(await fixtures.legacySnapshot(db), before);
    expect(quota.productsCreatedLifetime, 0);
  });
  test(
    'queued failure cannot erase quota of preceding successful create',
    () async {
      await failAudit(secondOnly: true);
      final first = create();
      final second = create();
      await expectLater(second, throwsA(anything));
      await first;
      expect(await db.select(db.products).get(), hasLength(1));
      expect(quota.productsCreatedLifetime, 1);
    },
  );
  test('successful direct creation increments quota once', () async {
    final id = await create();
    expect((await repo.getProductById(id))!.name, 'Direct');
    expect(await db.select(db.auditLogs).get(), hasLength(1));
    expect(quota.productsCreatedLifetime, 1);
  });

  for (final fail in [false, true]) {
    test('actual import atomicity with opening stock, fail=$fail', () async {
      final before = await fixtures.legacySnapshot(db);
      if (fail) {
        await db.customStatement(
          "CREATE TRIGGER reject_second_opening BEFORE INSERT ON journal_entries WHEN (SELECT COUNT(*) FROM journal_entries) > 0 BEGIN SELECT RAISE(ABORT, 'injected second opening failure'); END",
        );
      }
      final result = await importer(
        fileData: const ImportFileData(
          fileName: 'stock.csv',
          fileType: ImportFileType.csv,
          headers: ['name', 'price', 'cost', 'stock_quantity', 'category'],
          rows: [
            ['First', '10', '5', '2', 'Imported'],
            ['Second', '10', '5', '3', 'Imported'],
          ],
          totalRows: 2,
        ),
        columnMapping: const ColumnMapping({
          'name': 0,
          'price': 1,
          'cost': 2,
          'stock_quantity': 3,
          'category': 4,
        }),
      );
      if (fail) {
        expect(result.successfulRows, 0);
        expect(result.rowToProductId, isEmpty);
        expect(await fixtures.legacySnapshot(db), before);
        expect(await db.select(db.businessWarehouseStocks).get(), isEmpty);
        expect(await db.select(db.businessDocumentLocations).get(), isEmpty);
        expect(quota.productsCreatedLifetime, 0);
      } else {
        expect(result.successfulRows, 2);
        expect(quota.productsCreatedLifetime, 2);
        expect(await db.select(db.inventoryAdjustments).get(), hasLength(2));
        final totals = await db
            .customSelect(
              'SELECT SUM(quantity) AS qty FROM business_warehouse_stocks',
            )
            .getSingle();
        expect(totals.read<int>('qty'), 5);
        final journal = await db
            .customSelect(
              'SELECT SUM(debit_cents) AS dr, SUM(credit_cents) AS cr FROM journal_entry_lines',
            )
            .getSingle();
        expect(journal.read<int>('dr'), 2500);
        expect(journal.read<int>('cr'), 2500);
      }
    });
  }
}
