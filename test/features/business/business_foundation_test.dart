import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/business_foundation.dart';
import 'package:tapix/core/database/migrations/business_document_locations.dart';
import 'package:tapix/core/database/migrations/business_warehouse_stock.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';

const businessTables = [
  'business_warehouse_stocks',
  'business_document_locations',
  'business_contexts',
  'business_warehouses',
  'business_branches',
  'business_organizations',
];

AppDatabase memoryDb() =>
    AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));

Future<Map<String, List<Map<String, Object?>>>> legacySnapshot(
  AppDatabase db,
) async {
  final names = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'business_%' ORDER BY name",
      )
      .get();
  final result = <String, List<Map<String, Object?>>>{};
  for (final row in names) {
    final name = row.read<String>('name');
    result[name] =
        (await db.customSelect('SELECT * FROM "$name" ORDER BY rowid').get())
            .map((r) => r.data)
            .toList();
  }
  return result;
}

Future<void> seedLegacyData(AppDatabase db) async {
  final currency = await (db.select(
    db.currencies,
  )..where((c) => c.code.equals('USD'))).getSingle();
  final customer = await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          name: 'Existing customer',
          currencyId: currency.id,
          balanceCents: Value(Decimal.fromInt(17501)),
        ),
      );
  final supplier = await db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          name: 'Existing supplier',
          currencyId: currency.id,
          balanceCents: Value(Decimal.fromInt(-2403)),
        ),
      );
  for (final method in ['wac', 'fifo']) {
    final product = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Existing $method',
            sku: Value('OLD-$method'),
            currencyId: Value(currency.id),
            measurementType: const Value('weight'),
            costingMethod: Value(method),
            stockQuantity: const Value(1234),
            costCents: Decimal.fromInt(701),
            priceCents: Decimal.fromInt(1003),
          ),
        );
    final variant = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: product,
            stockQuantity: const Value(1234),
            costCents: Decimal.fromInt(701),
            priceCents: Decimal.fromInt(1003),
          ),
        );
    // Batch creation is deliberately real storage, so migration must preserve
    // exact FIFO/expiry data as well as aggregate quantity and cost.
    if (method == 'fifo') {
      await db
          .into(db.productBatches)
          .insert(
            ProductBatchesCompanion.insert(
              productId: product,
              variantId: Value(variant),
              batchNumber: 'OLD-BATCH',
              source: const Value('opening'),
              receivedQuantity: 1234,
              remainingQuantity: 1234,
              unitCostCents: Decimal.fromInt(701),
              receivedDate: Value(DateTime(2026, 1, 1)),
              expiryDate: Value(DateTime(2028, 1, 1)),
            ),
          );
    }
  }
  await db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          invoiceNumber: 'OLD-SALE-001',
          customerId: Value(customer),
          subtotalCents: Decimal.fromInt(17501),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(17501),
          currencyId: currency.id,
          paymentMethod: 'credit',
          idempotencyKey: const Value('existing-retry-key'),
        ),
      );
  await db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          purchaseNumber: 'OLD-PO-001',
          supplierId: supplier,
          subtotalCents: Decimal.fromInt(9503),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(9503),
          currencyId: currency.id,
        ),
      );
  final cash = await (db.select(
    db.accounts,
  )..where((a) => a.accountCode.equals('1000'))).getSingle();
  final revenue = await (db.select(
    db.accounts,
  )..where((a) => a.accountCode.equals('4000'))).getSingle();
  await AccountingRepository(db).createJournalEntry(
    entryData: JournalEntryData.simple(
      description: 'Existing posting',
      debitAccountId: cash.id,
      creditAccountId: revenue.id,
      amountCents: 55555,
      currencyId: currency.id,
    ),
    userId: null,
  );
  await db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: 'existing_customer_license_marker',
          value: 'must-not-change',
        ),
      );
}

void main() {
  test(
    'fresh database has one default scope without business subscription',
    () async {
      final db = memoryDb();
      addTearDown(db.close);
      final scope = await BusinessFoundationRepository(db).getScope();
      expect(db.schemaVersion, 10091);
      expect(scope.organizationId, hasLength(36));
      expect({
        scope.organizationId,
        scope.branchId,
        scope.warehouseId,
        scope.databaseId,
      }, hasLength(4));
      expect(await db.select(db.businessBranches).get(), hasLength(1));
      expect(await db.select(db.businessWarehouses).get(), hasLength(1));
      await initializeBusinessFoundation(db);
      expect(
        (await BusinessFoundationRepository(db).getScope()).databaseId,
        scope.databaseId,
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test(
    'independent databases never share branch or organization identities',
    () async {
      final a = memoryDb();
      final b = memoryDb();
      addTearDown(a.close);
      addTearDown(b.close);
      final first = await BusinessFoundationRepository(a).getScope();
      final second = await BusinessFoundationRepository(b).getScope();
      expect(first.organizationId, isNot(second.organizationId));
      expect(first.branchId, isNot(second.branchId));
      expect(first.databaseId, isNot(second.databaseId));
    },
  );

  test(
    'bootstrap failure rolls back every identity and can retry safely',
    () async {
      final db = memoryDb();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      for (final table in businessTables) {
        await db.customStatement('DELETE FROM $table');
      }
      await db.customStatement(
        """CREATE TRIGGER fail_business_seed BEFORE INSERT ON business_branches
      BEGIN SELECT RAISE(ABORT, 'injected metadata failure'); END""",
      );
      await expectLater(initializeBusinessFoundation(db), throwsA(anything));
      for (final table in businessTables) {
        expect(await db.customSelect('SELECT * FROM $table').get(), isEmpty);
      }
      await db.customStatement('DROP TRIGGER fail_business_seed');
      await initializeBusinessFoundation(db);
      expect(await db.select(db.businessContexts).get(), hasLength(1));
    },
  );

  test('missing context is not silently replaced with a new company', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final old = await BusinessFoundationRepository(db).getScope();
    await db.delete(db.businessContexts).go();
    await expectLater(initializeBusinessFoundation(db), throwsStateError);
    expect(
      (await db.select(db.businessOrganizations).get()).single.id,
      old.organizationId,
    );
    await expectLater(
      BusinessFoundationRepository(db).getScope(),
      throwsStateError,
    );
  });

  test(
    'cross-company warehouses and deleting the active scope are rejected',
    () async {
      final db = memoryDb();
      addTearDown(db.close);
      final scope = await BusinessFoundationRepository(db).getScope();
      final other = const Uuid().v4();
      await db
          .into(db.businessOrganizations)
          .insert(BusinessOrganizationsCompanion.insert(id: other));
      await expectLater(
        db
            .into(db.businessWarehouses)
            .insert(
              BusinessWarehousesCompanion.insert(
                id: const Uuid().v4(),
                organizationId: other,
                branchId: scope.branchId,
                code: 'OTHER',
              ),
            ),
        throwsA(anything),
      );
      await expectLater(
        (db.delete(
          db.businessWarehouses,
        )..where((w) => w.id.equals(scope.warehouseId))).go(),
        throwsA(anything),
      );
      await expectLater(
        (db.delete(
          db.businessBranches,
        )..where((b) => b.id.equals(scope.branchId))).go(),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('UPDATE business_contexts SET id = 2'),
        throwsA(anything),
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test(
    'primary warehouse reads exact live stock through the compatibility bridge',
    () async {
      final db = memoryDb();
      addTearDown(db.close);
      final repo = BusinessFoundationRepository(db);
      final scope = await repo.getScope();
      final product = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Measured stock',
              measurementType: const Value('length'),
              costCents: Decimal.fromInt(137),
              priceCents: Decimal.fromInt(211),
            ),
          );
      final variant = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: product,
              stockQuantity: const Value(1234),
              costCents: Decimal.fromInt(137),
              priceCents: Decimal.fromInt(211),
            ),
          );
      final first = (await repo.getPrimaryWarehouseStock(
        scope.warehouseId,
      )).single;
      expect(first.quantity, 1234);
      expect(first.quantityScale, 1000);
      expect(first.unitCostCents, 137);
      await (db.update(db.productVariants)..where((v) => v.id.equals(variant)))
          .write(const ProductVariantsCompanion(stockQuantity: Value(-250)));
      expect(
        (await repo.getPrimaryWarehouseStock(
          scope.warehouseId,
        )).single.quantity,
        -250,
      );
      await expectLater(
        repo.getPrimaryWarehouseStock(const Uuid().v4()),
        throwsStateError,
      );
    },
  );

  test(
    'failed schema upgrade rolls back new tables and succeeds after repair',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'business_failed_migration_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/legacy.db');
      var db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      await removeBusinessWarehouseStockTriggers(db);
      await removeBusinessDocumentLocationTriggers(db);
      for (final table in businessTables) {
        await db.customStatement('DROP TABLE $table');
      }
      await db.customStatement('PRAGMA user_version = 10082');
      // A conflicting view causes a deterministic failure after earlier tables
      // in the new migration have already been created.
      await db.customStatement(
        'CREATE VIEW business_contexts AS SELECT 1 AS incompatible',
      );
      await db.close();
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      await db.close();
      final raw = sqlite.sqlite3.open(file.path);
      expect(raw.userVersion, 10082);
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'business_%'",
        ),
        isEmpty,
      );
      raw.execute('DROP VIEW business_contexts');
      raw.close();
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      addTearDown(db.close);
      expect(
        (await BusinessFoundationRepository(db).getScope()).warehouseId,
        isNotEmpty,
      );
      expect((await db.select(db.businessOrganizations).get()), hasLength(1));
    },
  );

  test(
    '10082 migration preserves every legacy row and survives reopen and backup restore',
    () async {
      final dir = await Directory.systemTemp.createTemp('business_migration_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/legacy.db');
      var db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await seedLegacyData(db);
      final before = await legacySnapshot(db);
      await removeBusinessWarehouseStockTriggers(db);
      await removeBusinessDocumentLocationTriggers(db);
      for (final table in businessTables) {
        await db.customStatement('DROP TABLE $table');
      }
      await db.customStatement('PRAGMA user_version = 10082');
      await db.close();
      // Verify the fixture really has the old schema and no future metadata.
      final raw = sqlite.sqlite3.open(file.path);
      expect(raw.userVersion, 10082);
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE name LIKE 'business_%'",
        ),
        isEmpty,
      );
      raw.close();
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      final scope = await BusinessFoundationRepository(db).getScope();
      expect(await legacySnapshot(db), before);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
        (await db.customSelect('PRAGMA integrity_check').getSingle())
            .data
            .values
            .single,
        'ok',
      );
      await db.close();
      // Closed SQLite file copy models a restored backup, not shared-file LAN.
      final restored = await file.copy('${dir.path}/restored.db');
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(restored)));
      addTearDown(db.close);
      final reopened = await BusinessFoundationRepository(db).getScope();
      expect(reopened.databaseId, scope.databaseId);
      expect(reopened.organizationId, scope.organizationId);
      expect(reopened.branchId, scope.branchId);
      expect(reopened.warehouseId, scope.warehouseId);
      expect(await legacySnapshot(db), before);
    },
  );
}
