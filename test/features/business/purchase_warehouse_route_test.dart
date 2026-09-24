import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/business_document_locations.dart';
import 'package:tapix/core/database/migrations/sale_source_selection.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late Purchase source;
  late String other;
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    source = (await db.select(db.purchases).get()).single;
    final local = await BusinessFoundationRepository(db).getScope();
    other = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: other,
            organizationId: local.organizationId,
            branchId: local.branchId,
            code: 'PURCHASE-OTHER',
          ),
        );
  });
  tearDown(() => db.close());

  Future<int> purchase(String? warehouse) => db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          purchaseNumber: 'ROUTED',
          supplierId: source.supplierId,
          currencyId: source.currencyId,
          subtotalCents: Decimal.zero,
          taxCents: Decimal.zero,
          totalCents: Decimal.zero,
          warehouseId: Value(warehouse),
        ),
      );
  Future<String> location(String table, int id) async =>
      (await db
              .customSelect(
                'SELECT warehouse_id FROM business_document_locations WHERE source_table = ? AND source_id = ?',
                variables: [Variable.withString(table), Variable.withInt(id)],
              )
              .getSingle())
          .read<String>('warehouse_id');

  test('purchase route is inherited by return and both journals', () async {
    final id = await purchase(other);
    expect(await location('purchases', id), other);
    final ret = await db
        .into(db.purchaseReturns)
        .insert(
          PurchaseReturnsCompanion.insert(
            purchaseId: id,
            returnNumber: 'ROUTED-RETURN',
            totalCents: Decimal.zero,
            currencyId: source.currencyId,
          ),
        );
    expect(await location('purchase_returns', ret), other);
    for (final entry in {'purchases': id, 'purchase_returns': ret}.entries) {
      final journal = await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-${entry.key}',
              description: 'Route test',
              sourceTable: Value(entry.key),
              sourceId: Value(entry.value),
            ),
          );
      expect(await location('journal_entries', journal), other);
      await expectLater(
        db.customStatement(
          'UPDATE journal_entries SET source_id = ? WHERE id = ?',
          [999999, journal],
        ),
        throwsA(anything),
      );
    }
    await expectLater(
      db.customStatement(
        'UPDATE purchases SET warehouse_id = NULL WHERE id = ?',
        [id],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        'UPDATE purchase_returns SET purchase_id = ? WHERE id = ?',
        [source.id, ret],
      ),
      throwsA(anything),
    );
  });

  test(
    'payment and cheque journals inherit source and reversal location',
    () async {
      final id = await purchase(other);
      final payment = await db
          .into(db.purchasePayments)
          .insert(
            PurchasePaymentsCompanion.insert(
              purchaseId: id,
              amountCents: Decimal.fromInt(100),
              currencyId: source.currencyId,
              paymentMethod: 'cash',
            ),
          );
      final cheque = await db
          .into(db.chequeInstruments)
          .insert(
            ChequeInstrumentsCompanion.insert(
              direction: 'outgoing',
              sourceTable: 'purchases',
              sourceId: id,
              amountCents: Decimal.fromInt(100),
              currencyId: source.currencyId,
              dueDate: DateTime.now(),
              status: 'issued',
            ),
          );
      for (final entry in {
        'purchase_payments': payment,
        'cheque_instruments': cheque,
      }.entries) {
        final journal = await db
            .into(db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                entryNumber: 'DEPENDENT-${entry.key}',
                description: 'Dependent route',
                sourceTable: Value(entry.key),
                sourceId: Value(entry.value),
              ),
            );
        expect(await location('journal_entries', journal), other);
        final reverse = await db
            .into(db.journalEntries)
            .insert(
              JournalEntriesCompanion.insert(
                entryNumber: 'REVERSE-${entry.key}',
                description: 'Reversal route',
                reversedEntryId: Value(journal),
              ),
            );
        expect(await location('journal_entries', reverse), other);
        await expectLater(
          db.customStatement(
            'UPDATE journal_entries SET source_id = ? WHERE id = ?',
            [99999, journal],
          ),
          throwsA(anything),
        );
      }
    },
  );

  test(
    'omitted route preserves primary; inactive route rejects atomically',
    () async {
      final primary = (await BusinessFoundationRepository(
        db,
      ).getScope()).warehouseId;
      expect(await location('purchases', await purchase(null)), primary);
      await (db.update(db.businessWarehouses)..where((w) => w.id.equals(other)))
          .write(const BusinessWarehousesCompanion(isActive: Value(false)));
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                purchaseNumber: 'INACTIVE',
                supplierId: source.supplierId,
                currencyId: source.currencyId,
                subtotalCents: Decimal.zero,
                taxCents: Decimal.zero,
                totalCents: Decimal.zero,
                warehouseId: Value(other),
              ),
            ),
        throwsA(anything),
      );
      expect(await fixtures.legacySnapshot(db), before);
    },
  );

  test(
    '10090 migration creates empty layer audit and preserves accounting history',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'fifo_revaluation_upgrade_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/old.db');
      var legacy = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      await fixtures.seedLegacyData(legacy);
      final before = await fixtures.legacySnapshot(legacy);
      final identities = (await legacy.select(legacy.businessContexts).get())
          .map((r) => r.toJson())
          .toList();
      await legacy.customStatement('DROP TABLE inventory_revaluation_layers');
      await legacy.customStatement('PRAGMA user_version = 10090');
      await legacy.close();
      legacy = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      addTearDown(legacy.close);
      expect(await fixtures.legacySnapshot(legacy), before);
      expect(legacy.schemaVersion, 10115);
      expect(
        (await legacy.select(legacy.businessContexts).get())
            .map((r) => r.toJson())
            .toList(),
        identities,
      );
      expect(
        await legacy.select(legacy.inventoryRevaluationLayers).get(),
        isEmpty,
      );
    },
  );

  test(
    '10089 migration adds route without changing old values or identities',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'purchase_route_upgrade_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/old.db');
      var legacy = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      await fixtures.seedLegacyData(legacy);
      final before = await fixtures.legacySnapshot(legacy);
      final locations =
          (await legacy.select(legacy.businessDocumentLocations).get())
              .map((r) => r.toJson())
              .toList();
      await removeBusinessDocumentLocationTriggers(legacy);
      // The fixture is downgraded from the current schema. Remove guards that
      // did not exist in 10090 before removing the columns they reference.
      await removeSaleSourceSelectionGuards(legacy);
      // This fixture emulates schema 10089. Consignment triggers were added
      // later and can reference the route columns removed below.
      for (final trigger
          in await legacy
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='trigger' AND name GLOB 'consignment_*'",
              )
              .get()) {
        final name = trigger.read<String>('name');
        await legacy.customStatement('DROP TRIGGER "$name"');
      }
      for (final table in [
        'sales',
        'purchases',
        'sale_return_adjustments',
        'purchase_return_adjustments',
      ]) {
        await legacy.customStatement(
          'ALTER TABLE $table DROP COLUMN warehouse_id',
        );
      }
      await legacy.customStatement(
        'ALTER TABLE sale_return_adjustment_items DROP COLUMN return_batch_id',
      );
      await legacy.customStatement('PRAGMA user_version = 10089');
      await legacy.close();
      legacy = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      addTearDown(legacy.close);
      expect(await fixtures.legacySnapshot(legacy), before);
      expect(legacy.schemaVersion, 10115);
      expect(
        (await legacy.select(legacy.businessDocumentLocations).get())
            .map((r) => r.toJson())
            .toList(),
        locations,
      );
      expect(
        await legacy.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}
