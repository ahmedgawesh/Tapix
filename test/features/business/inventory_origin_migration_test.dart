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
      await db.customStatement('DROP TRIGGER inventory_origin_stock_changed');
      await db.customStatement('DROP TRIGGER inventory_origin_stock_deleted');
      for (final table in [
        'inventory_origin_events',
        'inventory_origin_states',
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
      await db.customStatement('PRAGMA user_version=10092');
      return before;
    } finally {
      await db.close();
    }
  }

  test(
    '10092 file upgrades additively without changing identities or financial data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tapix-origin-upgrade-',
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
      expect(await db.select(db.inventoryOriginStates).get(), isEmpty);
      expect(await db.select(db.inventoryOriginEvents).get(), isEmpty);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'inventory_origin_%'",
                )
                .get())
            .length,
        greaterThanOrEqualTo(5),
      );
    },
  );
  test(
    'failed additive migration rolls back tables and version, then retries cleanly',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tapix-origin-retry-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/legacy.sqlite');
      final before = await seedOld(file);
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('CREATE VIEW inventory_origin_events AS SELECT 1 AS id');
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
        10092,
      );
      expect(
        inspect.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('inventory_origin_states','inventory_origin_events')",
        ),
        isEmpty,
      );
      inspect.execute('DROP VIEW inventory_origin_events');
      inspect.close();
      final recovered = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      addTearDown(recovered.close);
      expect(
        await recovered.select(recovered.inventoryOriginStates).get(),
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
