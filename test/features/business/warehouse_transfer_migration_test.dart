import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/app_database.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  Future<Map<String, Object>> seedOld(File file) async {
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    try {
      await fixtures.seedLegacyData(db);
      for (final table in [
        'warehouse_transfer_events',
        'warehouse_transfer_lines',
        'warehouse_transfers',
      ]) {
        await db.customStatement('DROP TABLE $table');
      }
      final before = <String, Object>{};
      for (final table in [
        'business_contexts',
        'business_warehouses',
        'business_warehouse_stocks',
        'products',
        'product_variants',
        'sales',
        'sale_items',
        'purchases',
        'purchase_items',
        'product_batches',
        'journal_entries',
        'journal_entry_lines',
      ]) {
        before[table] =
            (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
                .map((r) => r.data)
                .toList();
      }
      await db.customStatement('PRAGMA user_version=10091');
      return before;
    } finally {
      await db.close();
    }
  }

  test(
    '10091 file upgrades additively without changing identities or financial data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tapix-transfer-upgrade-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/legacy.sqlite');
      final before = await seedOld(file);
      final db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      addTearDown(db.close);
      for (final table in before.keys) {
        expect(
          (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
              .map((r) => r.data)
              .toList(),
          before[table],
          reason: table,
        );
      }
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        10115,
      );
      expect(await db.select(db.warehouseTransfers).get(), isEmpty);
      expect(await db.select(db.warehouseTransferLines).get(), isEmpty);
      expect(await db.select(db.warehouseTransferEvents).get(), isEmpty);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'warehouse_transfer%'",
                )
                .get())
            .length,
        greaterThanOrEqualTo(10),
      );
    },
  );
  test(
    'failed additive migration rolls back tables and version, then retries cleanly',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tapix-transfer-retry-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/legacy.sqlite');
      final before = await seedOld(file);
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('CREATE VIEW warehouse_transfer_events AS SELECT 1 AS id');
      raw.close();
      final broken = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      await expectLater(
        broken.customSelect('SELECT 1').get(),
        throwsA(anything),
      );
      await broken.close();
      final inspect = sqlite.sqlite3.open(file.path);
      expect(
        inspect.select('PRAGMA user_version').single['user_version'],
        10091,
      );
      expect(
        inspect.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('warehouse_transfers','warehouse_transfer_lines')",
        ),
        isEmpty,
      );
      inspect.execute('DROP VIEW warehouse_transfer_events');
      inspect.close();
      final recovered = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      addTearDown(recovered.close);
      expect(
        await recovered.select(recovered.warehouseTransfers).get(),
        isEmpty,
      );
      for (final table in before.keys) {
        expect(
          (await recovered
                  .customSelect('SELECT * FROM $table ORDER BY rowid')
                  .get())
              .map((r) => r.data)
              .toList(),
          before[table],
          reason: table,
        );
      }
      expect(
        (await recovered.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        10115,
      );
    },
  );
}
