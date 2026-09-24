import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

import '../../generated_migrations/consignment_schema/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test(
    '10112 to 10115 preserves data and installs receipt and recall provenance',
    () async {
      final schema = await verifier.schemaAt(10112);
      addTearDown(schema.close);
      const organization = '11111111-1111-4111-8111-111111111111';
      const branch = '22222222-2222-4222-8222-222222222222';
      const warehouse = '33333333-3333-4333-8333-333333333333';
      const database = '44444444-4444-4444-8444-444444444444';
      schema.rawDatabase.execute('''
        INSERT INTO business_organizations(id,name)
        VALUES('$organization','Migration organization')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO business_branches(id,organization_id,code,name)
        VALUES('$branch','$organization','MAIN','Main branch')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO business_warehouses(id,organization_id,branch_id,code,name)
        VALUES('$warehouse','$organization','$branch','MAIN','Main warehouse')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO business_contexts(
          id,organization_id,branch_id,warehouse_id,database_id
        ) VALUES(1,'$organization','$branch','$warehouse','$database')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO app_settings(key,value,description,created_at,updated_at)
        VALUES('transfer.dispatch.migration','kept','test',
        '2026-09-24T00:00:00.000Z','2026-09-24T00:00:00.000Z')
      ''');

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);
      addTearDown(db.close);

      expect(
        (await (db.select(db.appSettings)..where(
                  (row) => row.key.equals('transfer.dispatch.migration'),
                ))
                .getSingle())
            .value,
        'kept',
      );
      final inTransit = await (db.select(
        db.accounts,
      )..where((account) => account.accountCode.equals('1210'))).getSingle();
      expect(inTransit.accountType, 'asset');
      expect(inTransit.isSystemAccount, isTrue);
      expect(inTransit.isActive, isTrue);

      final journalTrigger = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type='trigger' "
            "AND name='business_location_journal_entries_insert'",
          )
          .getSingle();
      final triggerSql = journalTrigger.read<String>('sql');
      expect(triggerSql, contains('warehouse_transfer_dispatches'));
      expect(triggerSql, contains('source_warehouse_id'));
      expect(triggerSql, contains('warehouse_transfer_receipts'));
      expect(triggerSql, contains('destination_warehouse_id'));
      final batchColumns = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('product_batches') "
            "WHERE name IN ('origin_batch_id','transfer_allocation_id') "
            'ORDER BY name',
          )
          .get();
      expect(batchColumns.map((row) => row.read<String>('name')).toList(), [
        'origin_batch_id',
        'transfer_allocation_id',
      ]);
      final consumptionColumns = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('batch_consumptions') "
            "WHERE name='transfer_allocation_id'",
          )
          .get();
      expect(consumptionColumns, hasLength(1));
      final recallTables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name IN ('warehouse_transfer_recalls',"
            "'warehouse_transfer_recall_items') ORDER BY name",
          )
          .get();
      expect(recallTables.map((row) => row.read<String>('name')).toList(), [
        'warehouse_transfer_recall_items',
        'warehouse_transfer_recalls',
      ]);
      expect(triggerSql, contains('warehouse_transfer_recalls'));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        10115,
      );
    },
  );
}
