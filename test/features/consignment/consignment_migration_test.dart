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
    '10097 to current schema is additive and preserves a normal supplier',
    () async {
      final schema = await verifier.schemaAt(10097);
      addTearDown(schema.close);
      schema.rawDatabase.execute('''
      INSERT INTO currencies(
        id,code,name,symbol,exchange_rate,is_base,is_active,created_at,updated_at
      ) VALUES(77,'USD','US Dollar','USD',100,1,1,
        '2026-09-01T00:00:00.000Z','2026-09-01T00:00:00.000Z')
    ''');
      schema.rawDatabase.execute('''
      INSERT INTO suppliers(
        id,name,balance_cents,opening_balance_cents,currency_id,is_active,
        created_at,updated_at
      ) VALUES(42,'Existing normal supplier',12345,12345,77,1,
        '2026-09-01T00:00:00.000Z','2026-09-01T00:00:00.000Z')
    ''');

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);

      final supplier = await (db.select(
        db.suppliers,
      )..where((s) => s.id.equals(42))).getSingle();
      expect(supplier.name, 'Existing normal supplier');
      expect(supplier.balanceCents.toBigInt().toInt(), 12345);
      expect(supplier.openingBalanceCents.toBigInt().toInt(), 12345);
      expect(supplier.defaultSupplyMode, 'standard');
      expect(await db.select(db.consignmentAgreements).get(), isEmpty);
      expect(await db.select(db.consignmentAgreementItems).get(), isEmpty);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      await db.close();
    },
  );

  test(
    '10102 to current schema preserves data and installs settlement guards',
    () async {
      final schema = await verifier.schemaAt(10102);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        '''INSERT INTO app_settings(key,value,description,created_at,updated_at)
        VALUES('consignment.migration.sentinel','kept','test',
        '2026-09-23T00:00:00.000Z','2026-09-23T00:00:00.000Z')''',
      );

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);

      final sentinel =
          await (db.select(db.appSettings)..where(
                (row) => row.key.equals('consignment.migration.sentinel'),
              ))
              .getSingle();
      expect(sentinel.value, 'kept');
      final guards = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='trigger' "
            "AND name IN ('consignment_statement_transition_guard',"
            "'consignment_payment_reversal_guard') ORDER BY name",
          )
          .get();
      expect(guards.map((row) => row.read<String>('name')).toList(), [
        'consignment_payment_reversal_guard',
        'consignment_statement_transition_guard',
      ]);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      await db.close();
    },
  );

  test(
    '10098 to current schema adds zero supplier ownership and empty custody ledgers',
    () async {
      final schema = await verifier.schemaAt(10098);
      addTearDown(schema.close);
      final db = AppDatabase.connect(schema.newConnection());

      await verifier.migrateAndValidate(db, 10115);

      final column = await db
          .customSelect(
            "SELECT name, dflt_value FROM pragma_table_info('business_warehouse_stocks') "
            "WHERE name='supplier_owned_quantity'",
          )
          .getSingle();
      expect(column.read<String>('name'), 'supplier_owned_quantity');
      expect(column.read<String>('dflt_value'), '0');
      expect(await db.select(db.consignmentReceipts).get(), isEmpty);
      expect(await db.select(db.consignmentReceiptItems).get(), isEmpty);
      expect(await db.select(db.consignmentInventoryLayers).get(), isEmpty);
      expect(await db.select(db.consignmentReceiptEvents).get(), isEmpty);
      expect(await db.select(db.consignmentSaleAllocations).get(), isEmpty);
      expect(await db.select(db.consignmentObligationEvents).get(), isEmpty);
      expect(
        await db.select(db.consignmentAdjustmentReturnEvents).get(),
        isEmpty,
      );
      expect(
        await db.select(db.consignmentSettlementStatements).get(),
        isEmpty,
      );
      expect(await db.select(db.consignmentSettlementItems).get(), isEmpty);
      expect(await db.select(db.consignmentSettlementPayments).get(), isEmpty);
      final guards = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='trigger' "
            "AND name IN ('consignment_statement_transition_guard',"
            "'consignment_payment_reversal_guard') ORDER BY name",
          )
          .get();
      expect(guards.map((row) => row.read<String>('name')).toList(), [
        'consignment_payment_reversal_guard',
        'consignment_statement_transition_guard',
      ]);
      final agreementTaxColumns = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('consignment_agreements') "
            "WHERE name IN ('settlement_tax_rate_bps','settlement_tax_inclusive') "
            'ORDER BY name',
          )
          .get();
      expect(
        agreementTaxColumns.map((row) => row.read<String>('name')).toSet(),
        {'settlement_tax_inclusive', 'settlement_tax_rate_bps'},
      );
      final adjustmentColumns = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('sale_return_adjustment_items') "
            "WHERE name IN ('item_discount_at_post_cents',"
            "'invoice_discount_at_post_cents','consignment_layer_id') "
            'ORDER BY name',
          )
          .get();
      expect(adjustmentColumns.map((row) => row.read<String>('name')).toSet(), {
        'consignment_layer_id',
        'invoice_discount_at_post_cents',
        'item_discount_at_post_cents',
      });

      await db.close();
    },
  );
  test(
    '10103 to current schema adds safe return-disposition defaults and guards',
    () async {
      final schema = await verifier.schemaAt(10103);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        '''INSERT INTO app_settings(key,value,description,created_at,updated_at)
        VALUES('consignment.10104.sentinel','kept','test',
        '2026-09-23T00:00:00.000Z','2026-09-23T00:00:00.000Z')''',
      );

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);

      final sentinel =
          await (db.select(db.appSettings)
                ..where((row) => row.key.equals('consignment.10104.sentinel')))
              .getSingle();
      expect(sentinel.value, 'kept');
      for (final table in [
        'consignment_obligation_events',
        'consignment_adjustment_return_events',
      ]) {
        final column = await db.customSelect(
          '''SELECT name,dflt_value FROM pragma_table_info('$table')
              WHERE name='restores_stock' ''',
        ).getSingle();
        expect(column.read<String>('name'), 'restores_stock');
        expect(column.read<String>('dflt_value'), '1');
      }
      final guards = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type='trigger' AND name IN ("
            "'consignment_obligation_events_insert_guard',"
            "'consignment_adj_event_insert_guard') ORDER BY name",
          )
          .get();
      expect(guards, hasLength(2));
      expect(
        guards.every(
          (row) => row.read<String>('sql').contains('restores_stock'),
        ),
        isTrue,
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      await db.close();
    },
  );

  test(
    '10105 to current schema adds transfer custody documents exactly',
    () async {
      final schema = await verifier.schemaAt(10105);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        """INSERT INTO app_settings(key,value,description,created_at,updated_at)
      VALUES('station3.10109.sentinel','kept','test',
      '2026-09-24T00:00:00.000Z','2026-09-24T00:00:00.000Z')""",
      );

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);

      final sentinel = await (db.select(
        db.appSettings,
      )..where((row) => row.key.equals('station3.10109.sentinel'))).getSingle();
      expect(sentinel.value, 'kept');
      expect(await db.select(db.warehouseTransferDispatches).get(), isEmpty);
      expect(await db.select(db.warehouseTransferAllocations).get(), isEmpty);
      expect(await db.select(db.warehouseTransferReceipts).get(), isEmpty);
      expect(await db.select(db.warehouseTransferReceiptItems).get(), isEmpty);
      final layerColumns = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('consignment_inventory_layers') "
            "WHERE name IN ('origin_layer_id','transfer_allocation_id') ORDER BY name",
          )
          .get();
      expect(layerColumns.map((row) => row.read<String>('name')).toList(), [
        'origin_layer_id',
        'transfer_allocation_id',
      ]);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      await db.close();
    },
  );

  test(
    'malformed 10107 custody schema self-heals to current schema without data loss',
    () async {
      // A released device could be stamped 10107 while still carrying the
      // 10105 transfer/layer layout. Reproduce that exact hybrid shape.
      final schema = await verifier.schemaAt(10105);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        'ALTER TABLE sale_items ADD COLUMN supplier_identity_id INTEGER NULL '
        'REFERENCES supplier_product_identities(id) ON DELETE RESTRICT',
      );
      schema.rawDatabase.execute(
        'ALTER TABLE sale_return_adjustment_items '
        'ADD COLUMN supplier_identity_id INTEGER NULL '
        'REFERENCES supplier_product_identities(id) ON DELETE RESTRICT',
      );
      schema.rawDatabase.execute(
        """INSERT INTO app_settings(key,value,description,created_at,updated_at)
        VALUES('consignment.10109.repair.sentinel','kept','test',
        '2026-09-24T00:00:00.000Z','2026-09-24T00:00:00.000Z')""",
      );
      schema.rawDatabase.execute('PRAGMA user_version=10107');

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 10115);

      final sentinel =
          await (db.select(db.appSettings)..where(
                (row) => row.key.equals('consignment.10109.repair.sentinel'),
              ))
              .getSingle();
      expect(sentinel.value, 'kept');

      final layerColumns = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('consignment_inventory_layers') "
            "WHERE name IN ('origin_layer_id','transfer_allocation_id') "
            'ORDER BY name',
          )
          .get();
      expect(layerColumns.map((row) => row.read<String>('name')).toList(), [
        'origin_layer_id',
        'transfer_allocation_id',
      ]);

      final transferTables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ("
            "'warehouse_transfer_dispatches',"
            "'warehouse_transfer_allocations',"
            "'warehouse_transfer_receipts',"
            "'warehouse_transfer_receipt_items') ORDER BY name",
          )
          .get();
      expect(transferTables.map((row) => row.read<String>('name')).toSet(), {
        'warehouse_transfer_allocations',
        'warehouse_transfer_dispatches',
        'warehouse_transfer_receipt_items',
        'warehouse_transfer_receipts',
      });

      final transferDdl = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type='table' "
            "AND name='warehouse_transfers'",
          )
          .getSingle();
      expect(transferDdl.read<String>('sql'), contains('in_transit'));

      final layerDdl = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type='table' "
            "AND name='consignment_inventory_layers'",
          )
          .getSingle();
      expect(
        layerDdl.read<String>('sql'),
        isNot(contains('"receipt_item_id" TEXT NOT NULL UNIQUE')),
      );

      final guards = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='trigger' AND name IN ("
            "'consignment_layers_insert_guard',"
            "'consignment_layers_identity_guard',"
            "'warehouse_transfer_receipts_finalize') ORDER BY name",
          )
          .get();
      expect(guards, hasLength(3));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      await db.close();
    },
  );

  test(
    '10104 to current schema preserves data and requires zero-value sale provenance',
    () async {
      final schema = await verifier.schemaAt(10104);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        """INSERT INTO app_settings(key,value,description,created_at,updated_at)
        VALUES('consignment.10109.sentinel','kept','test',
        '2026-09-23T00:00:00.000Z','2026-09-23T00:00:00.000Z')""",
      );

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);

      final sentinel =
          await (db.select(db.appSettings)
                ..where((row) => row.key.equals('consignment.10109.sentinel')))
              .getSingle();
      expect(sentinel.value, 'kept');
      final guard = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type='trigger' "
            "AND name='consignment_sale_completion_guard'",
          )
          .getSingle();
      final sql = guard.read<String>('sql');
      expect(sql, contains("e.kind='sale_accrual'"));
      expect(sql, isNot(contains('a.obligation_cents>0')));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      await db.close();
    },
  );

  test(
    '10108 to current schema adds explicit sale source selection without data loss',
    () async {
      final schema = await verifier.schemaAt(10108);
      addTearDown(schema.close);
      schema.rawDatabase.execute(
        """INSERT INTO app_settings(key,value,description,created_at,updated_at)
        VALUES('sale.source.10109.sentinel','kept','test',
        '2026-09-24T00:00:00.000Z','2026-09-24T00:00:00.000Z')""",
      );

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);

      final sentinel =
          await (db.select(db.appSettings)
                ..where((row) => row.key.equals('sale.source.10109.sentinel')))
              .getSingle();
      expect(sentinel.value, 'kept');
      final column = await db
          .customSelect(
            "SELECT name FROM pragma_table_info('sale_items') "
            "WHERE name='consignment_layer_id'",
          )
          .getSingle();
      expect(column.read<String>('name'), 'consignment_layer_id');
      final guards = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='trigger' AND name IN ("
            "'sale_source_selection_insert_guard',"
            "'sale_source_selection_update_guard') ORDER BY name",
          )
          .get();
      expect(guards, hasLength(2));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      await db.close();
    },
  );
}
