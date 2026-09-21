import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/business_document_locations.dart';
import 'package:tapix/core/database/migrations/business_warehouse_stock.dart';
import 'package:tapix/features/business/data/business_document_repository.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:tapix/features/business/domain/business_document_type.dart';

import 'business_foundation_test.dart' as fixtures;

Future<int> insertSale(AppDatabase db, String number) async {
  final currency = await (db.select(
    db.currencies,
  )..where((c) => c.code.equals('USD'))).getSingle();
  return db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          invoiceNumber: number,
          subtotalCents: Decimal.zero,
          taxCents: Decimal.zero,
          totalCents: Decimal.zero,
          currencyId: currency.id,
          paymentMethod: 'cash',
        ),
      );
}

Future<void> seedAllLocatedTypes(AppDatabase db) async {
  await fixtures.seedLegacyData(db);
  final sale = (await db.select(db.sales).get()).single;
  final purchase = (await db.select(db.purchases).get()).single;
  final product = (await db.select(db.products).get()).first;
  await db
      .into(db.saleReturns)
      .insert(
        SaleReturnsCompanion.insert(
          saleId: sale.id,
          returnNumber: 'SR-LOC',
          totalCents: Decimal.zero,
          currencyId: sale.currencyId,
        ),
      );
  await db
      .into(db.purchaseReturns)
      .insert(
        PurchaseReturnsCompanion.insert(
          purchaseId: purchase.id,
          returnNumber: 'PR-LOC',
          totalCents: Decimal.zero,
          currencyId: purchase.currencyId,
        ),
      );
  await db
      .into(db.saleReturnAdjustments)
      .insert(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SRA-LOC',
          totalCents: Decimal.zero,
          currencyId: sale.currencyId,
        ),
      );
  await db
      .into(db.purchaseReturnAdjustments)
      .insert(
        PurchaseReturnAdjustmentsCompanion.insert(
          supplierId: purchase.supplierId,
          returnNumber: 'PRA-LOC',
          totalCents: Decimal.zero,
          currencyId: purchase.currencyId,
        ),
      );
  await db
      .into(db.inventoryAdjustments)
      .insert(
        InventoryAdjustmentsCompanion.insert(
          adjustmentNumber: 'IA-LOC',
          productId: product.id,
          adjustmentType: 'gain',
          quantityDelta: 1,
          unitCostCents: Decimal.fromInt(701),
          totalValueCents: Decimal.fromInt(701),
          reason: 'Location fixture',
          currencyId: sale.currencyId,
        ),
      );
}

Future<void> verifyEveryLocation(AppDatabase db) async {
  final scope = await BusinessFoundationRepository(db).getScope();
  final repo = BusinessDocumentRepository(db);
  final all = await db.select(db.businessDocumentLocations).get();
  var expectedCount = 0;
  final ids = <String>{};
  for (final type in BusinessDocumentType.values) {
    final sources = await db
        .customSelect('SELECT id FROM ${type.sourceTable}')
        .get();
    expectedCount += sources.length;
    for (final row in sources) {
      final location = await repo.getLocation(type, row.read<int>('id'));
      expect(location.sourceTable, type.sourceTable);
      expect(location.organizationId, scope.organizationId);
      expect(location.branchId, scope.branchId);
      expect(location.warehouseId, scope.warehouseId);
      expect(location.originDatabaseId, scope.databaseId);
      expect(
        location.documentId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(ids.add(location.documentId), isTrue);
    }
  }
  expect(all.length, expectedCount);
  expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
}

void main() {
  test(
    'every supported header and batch gets one atomic primary location',
    () async {
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      await seedAllLocatedTypes(db);
      expect(
        locatedBusinessTables.toSet(),
        BusinessDocumentType.values.map((v) => v.sourceTable).toSet(),
      );
      for (final type in BusinessDocumentType.values) {
        expect(
          await db.customSelect('SELECT id FROM ${type.sourceTable}').get(),
          isNotEmpty,
        );
      }
      await verifyEveryLocation(db);
      final before = await db.select(db.businessDocumentLocations).get();
      await installBusinessDocumentLocations(db);
      expect(await db.select(db.businessDocumentLocations).get(), before);
    },
  );

  test(
    'same local invoice IDs in independent databases have different global identities',
    () async {
      final first = fixtures.memoryDb();
      final second = fixtures.memoryDb();
      addTearDown(first.close);
      addTearDown(second.close);
      final a = await insertSale(first, 'SALE-1');
      final b = await insertSale(second, 'SALE-1');
      expect(a, b);
      final one = await BusinessDocumentRepository(
        first,
      ).getLocation(BusinessDocumentType.sale, a);
      final two = await BusinessDocumentRepository(
        second,
      ).getLocation(BusinessDocumentType.sale, b);
      expect(one.documentId, isNot(two.documentId));
      expect(one.originDatabaseId, isNot(two.originDatabaseId));
    },
  );

  test(
    'metadata failure rolls back the source insert and outer transaction',
    () async {
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await db.customStatement(
        """CREATE TRIGGER fail_location BEFORE INSERT ON business_document_locations
      WHEN NEW.source_table = 'sales' BEGIN SELECT RAISE(ABORT, 'injected location failure'); END""",
      );
      await expectLater(
        db.transaction(() async {
          await db
              .into(db.appSettings)
              .insert(
                AppSettingsCompanion.insert(key: 'must_rollback', value: 'yes'),
              );
          await insertSale(db, 'FAIL-LOC');
        }),
        throwsA(anything),
      );
      expect(await db.select(db.sales).get(), isEmpty);
      expect(await db.select(db.businessDocumentLocations).get(), isEmpty);
      expect(
        await (db.select(
          db.appSettings,
        )..where((s) => s.key.equals('must_rollback'))).get(),
        isEmpty,
      );
      await db.customStatement('DROP TRIGGER fail_location');
      await insertSale(db, 'FAIL-LOC');
      await verifyEveryLocation(db);
    },
  );

  test(
    'missing context rejects a new document instead of saving it unscoped',
    () async {
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await db.delete(db.businessContexts).go();
      await expectLater(insertSale(db, 'NO-CONTEXT'), throwsA(anything));
      expect(await db.select(db.sales).get(), isEmpty);
      await expectLater(installBusinessDocumentLocations(db), throwsStateError);
    },
  );

  test(
    'update, direct deletion and REPLACE cannot reassign document identity',
    () async {
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      final id = await insertSale(db, 'IMMUTABLE');
      final repo = BusinessDocumentRepository(db);
      final location = await repo.getLocation(BusinessDocumentType.sale, id);
      await (db.update(db.sales)..where((s) => s.id.equals(id))).write(
        const SalesCompanion(notes: Value('edited draft')),
      );
      expect(await repo.getLocation(BusinessDocumentType.sale, id), location);
      await expectLater(
        db.customStatement(
          'UPDATE business_document_locations SET document_id = ?',
          [const Uuid().v4()],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.delete(db.businessDocumentLocations).go(),
        throwsA(anything),
      );
      await expectLater(
        db
            .into(db.businessDocumentLocations)
            .insert(
              location.toCompanion(true),
              mode: InsertMode.insertOrReplace,
            ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('UPDATE sales SET id = ? WHERE id = ?', [
          id + 100,
          id,
        ]),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('UPDATE business_contexts SET database_id = ?', [
          const Uuid().v4(),
        ]),
        throwsA(anything),
      );
      final context = await db.select(db.businessContexts).getSingle();
      await expectLater(
        db
            .into(db.businessContexts)
            .insert(
              context
                  .toCompanion(true)
                  .copyWith(databaseId: Value(const Uuid().v4())),
              mode: InsertMode.insertOrReplace,
            ),
        throwsA(anything),
      );
      await expectLater(db.delete(db.businessContexts).go(), throwsA(anything));
      expect(await repo.getLocation(BusinessDocumentType.sale, id), location);
    },
  );

  test(
    'unknown sources and secondary warehouse assignments are rejected',
    () async {
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      final id = await insertSale(db, 'PRIMARY');
      final original = await BusinessDocumentRepository(
        db,
      ).getLocation(BusinessDocumentType.sale, id);
      final secondary = const Uuid().v4();
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: secondary,
              organizationId: original.organizationId,
              branchId: original.branchId,
              code: 'SECONDARY',
            ),
          );
      await expectLater(
        db
            .into(db.businessDocumentLocations)
            .insert(
              original
                  .toCompanion(true)
                  .copyWith(
                    documentId: Value(const Uuid().v4()),
                    sourceId: const Value(99999),
                  ),
            ),
        throwsA(anything),
      );
      // Remove insert automation to test a direct assignment of a real source;
      // production never exposes this operation.
      await db.customStatement('DROP TRIGGER business_location_sales_insert');
      final secondId = await insertSale(db, 'SECONDARY');
      await expectLater(
        db
            .into(db.businessDocumentLocations)
            .insert(
              original
                  .toCompanion(true)
                  .copyWith(
                    documentId: Value(const Uuid().v4()),
                    sourceId: Value(secondId),
                    warehouseId: Value(secondary),
                  ),
            ),
        throwsA(anything),
      );
      await installBusinessDocumentLocations(db);
      expect(
        (await BusinessDocumentRepository(
          db,
        ).getLocation(BusinessDocumentType.sale, secondId)).warehouseId,
        original.warehouseId,
      );
    },
  );

  test(
    'draft deletion removes its location and ID reuse gets a new global ID',
    () async {
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      final id = await insertSale(db, 'DRAFT-DELETE');
      final repo = BusinessDocumentRepository(db);
      final old = await repo.getLocation(BusinessDocumentType.sale, id);
      final sale = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(id))).getSingle();
      await (db.delete(db.sales)..where((s) => s.id.equals(id))).go();
      await expectLater(
        repo.getLocation(BusinessDocumentType.sale, id),
        throwsStateError,
      );
      await db.into(db.sales).insert(sale.toCompanion(true));
      expect(
        (await repo.getLocation(BusinessDocumentType.sale, id)).documentId,
        isNot(old.documentId),
      );
      await verifyEveryLocation(db);
    },
  );

  test(
    'location stream follows source inserts and deletes made through Drift',
    () async {
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      final repo = BusinessDocumentRepository(db);
      final initial = repo.watchLocations(BusinessDocumentType.sale).first;
      expect(await initial, isEmpty);
      final inserted = repo
          .watchLocations(BusinessDocumentType.sale)
          .firstWhere((rows) => rows.length == 1)
          .timeout(const Duration(seconds: 5));
      final id = await insertSale(db, 'STREAM');
      expect((await inserted).single.sourceId, id);
      final removed = repo
          .watchLocations(BusinessDocumentType.sale)
          .firstWhere((rows) => rows.isEmpty)
          .timeout(const Duration(seconds: 5));
      await (db.delete(db.sales)..where((s) => s.id.equals(id))).go();
      expect(await removed, isEmpty);
    },
  );

  test(
    'sale posting, linked return and void preserve location and measured stock',
    () async {
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      await fixtures.seedLegacyData(db);
      final product = await (db.select(
        db.products,
      )..where((p) => p.costingMethod.equals('wac'))).getSingle();
      final variant = await (db.select(
        db.productVariants,
      )..where((v) => v.productId.equals(product.id))).getSingle();
      final currency = await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle();
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'LIFECYCLE',
              subtotalCents: Decimal.fromInt(100),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(100),
              paidAmountCents: Value(Decimal.fromInt(100)),
              currencyId: currency.id,
              paymentMethod: 'cash',
              status: const Value('draft'),
            ),
          );
      final itemId = await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: product.id,
              variantId: Value(variant.id),
              quantity: 100,
              quantityScale: const Value(1000),
              measurementType: const Value('weight'),
              unitPriceCents: Decimal.fromInt(1003),
              subtotalCents: Decimal.fromInt(100),
              totalCents: Decimal.fromInt(100),
            ),
          );
      final repo = BusinessDocumentRepository(db);
      final original = await repo.getLocation(
        BusinessDocumentType.sale,
        saleId,
      );
      Future<int> stock() async => (await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variant.id))).getSingle()).stockQuantity;
      await db.saleDao.postSale(saleId);
      expect(await stock(), 1134);
      expect(
        await repo.getLocation(BusinessDocumentType.sale, saleId),
        original,
      );
      final returnId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          saleId: saleId,
          returnNumber: 'LIFECYCLE-SR',
          totalCents: Decimal.fromInt(50),
          subtotalCents: Value(Decimal.fromInt(50)),
          currencyId: currency.id,
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: itemId,
            quantity: 50,
            quantityScale: const Value(1000),
            measurementType: const Value('weight'),
            subtotalCents: Value(Decimal.fromInt(50)),
            refundCents: Decimal.fromInt(50),
          ),
        ],
      );
      final returnLocation = await repo.getLocation(
        BusinessDocumentType.saleReturn,
        returnId,
      );
      expect(returnLocation.warehouseId, original.warehouseId);
      await db.saleDao.postSaleReturn(returnId);
      expect(await stock(), 1184);
      await db.saleDao.voidSaleReturn(returnId);
      expect(await stock(), 1134);
      await db.saleDao.voidSale(saleId);
      expect(await stock(), 1234);
      expect(
        await repo.getLocation(BusinessDocumentType.sale, saleId),
        original,
      );
      expect(
        await repo.getLocation(BusinessDocumentType.saleReturn, returnId),
        returnLocation,
      );
      await verifyEveryLocation(db);
    },
  );

  test(
    'unchanged reason seeds keep their audit timestamp during reseeding',
    () async {
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      await db.customStatement(
        "UPDATE return_reason_codes SET updated_at = '2001-01-01 00:00:00'",
      );
      final before = await db
          .customSelect('SELECT * FROM return_reason_codes ORDER BY id')
          .get();
      await db.seedInitialDataForTest();
      final after = await db
          .customSelect('SELECT * FROM return_reason_codes ORDER BY id')
          .get();
      expect(
        after.map((r) => r.data).toList(),
        before.map((r) => r.data).toList(),
      );
    },
  );

  test(
    '10083 migration preserves all financial rows and identities survive restore',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'document_location_migration_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/legacy.db');
      var db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await seedAllLocatedTypes(db);
      final before = await fixtures.legacySnapshot(db);
      final scope = await BusinessFoundationRepository(db).getScope();
      await removeBusinessWarehouseStockTriggers(db);
      await removeBusinessDocumentLocationTriggers(db);
      await db.customStatement('DROP TABLE business_warehouse_stocks');
      await db.customStatement('DROP TABLE business_document_locations');
      await db.customStatement('PRAGMA user_version = 10083');
      await db.close();
      final raw = sqlite.sqlite3.open(file.path);
      expect(raw.userVersion, 10083);
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE name = 'business_document_locations'",
        ),
        isEmpty,
      );
      raw.close();
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      expect(db.schemaVersion, 10091);
      await verifyEveryLocation(db);
      expect(await fixtures.legacySnapshot(db), before);
      expect(
        (await BusinessFoundationRepository(db).getScope()).databaseId,
        scope.databaseId,
      );
      final identities = await db.select(db.businessDocumentLocations).get();
      await db.close();
      final copy = await file.copy('${dir.path}/restored.db');
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(copy)));
      addTearDown(db.close);
      expect(await db.select(db.businessDocumentLocations).get(), identities);
      expect(await fixtures.legacySnapshot(db), before);
      await verifyEveryLocation(db);
    },
  );

  test(
    'failure midway through metadata backfill rolls back migration completely',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'document_location_failure_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/legacy.db');
      var db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await seedAllLocatedTypes(db);
      final scope = await BusinessFoundationRepository(db).getScope();
      await removeBusinessWarehouseStockTriggers(db);
      await removeBusinessDocumentLocationTriggers(db);
      await db.customStatement('DROP TABLE business_warehouse_stocks');
      await db.customStatement('DROP TABLE business_document_locations');
      // Invalid source identity forces failure in the last backfill table, after
      // earlier documents have already received their provisional locations.
      await db.customStatement(
        "INSERT INTO journal_entries (id, entry_number, description) VALUES (0, 'INJECTED', 'migration failure')",
      );
      await db.customStatement('PRAGMA user_version = 10083');
      await db.close();
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      await db.close();
      final raw = sqlite.sqlite3.open(file.path);
      expect(raw.userVersion, 10083);
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE name = 'business_document_locations'",
        ),
        isEmpty,
      );
      expect(
        raw
            .select('SELECT database_id FROM business_contexts')
            .single['database_id'],
        scope.databaseId,
      );
      raw.execute('DELETE FROM journal_entries WHERE id = 0');
      raw.close();
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      addTearDown(db.close);
      await verifyEveryLocation(db);
    },
  );
}
