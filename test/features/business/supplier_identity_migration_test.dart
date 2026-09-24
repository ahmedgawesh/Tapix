import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/app_database.dart';
import 'business_foundation_test.dart' as fixtures;
import 'support/purchase_supplier_source_fixture.dart';

void main() {
  Future<Map<String, List<Map<String, Object?>>>> seed10093(File file) async {
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    try {
      await fixtures.seedLegacyData(db);
      await removePurchaseSupplierSourceSchema(db);
      final guards = await db
          .customSelect(
            'SELECT name,type FROM sqlite_master WHERE '
            "(type='trigger' AND (name LIKE 'suppliers_product_code_%' "
            "OR name LIKE 'supplier_identity_%' OR name LIKE '%_supplier_identity_%' "
            "OR name LIKE 'supplier_code_lock_%')) "
            "OR (type='index' AND name LIKE 'idx_suppliers_product_code_%')",
          )
          .get();
      for (final guard in guards) {
        final type = guard.read<String>('type').toUpperCase();
        final name = guard.read<String>('name');
        await db.customStatement('DROP $type "$name"');
      }
      await db.customStatement('DROP TABLE supplier_product_code_locks');
      await db.customStatement('DROP TABLE supplier_product_identities');
      await db.customStatement(
        'ALTER TABLE suppliers DROP COLUMN product_code',
      );
      await db.customStatement('PRAGMA user_version=10093');
      return await fixtures.legacySnapshot(db);
    } finally {
      await db.close();
    }
  }

  test(
    '10093 -> 10099 adds NULL prefixes and no identities, preserving history',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'supplier-identity-migration-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/old.sqlite');
      final before = await seed10093(file);
      final db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      addTearDown(db.close);
      final after = await fixtures.legacySnapshot(db);
      expect(after.remove('supplier_product_identities'), isEmpty);
      expect(after.remove('supplier_product_code_locks'), isEmpty);
      for (final row in after['suppliers']!) {
        expect(row.remove('product_code'), isNull);
      }
      for (final row in after['purchase_items']!) {
        expect(row.remove('supplier_identity_requested'), 0);
        expect(row.remove('supplier_identity_id'), isNull);
      }
      expect(after, before);
      expect(db.schemaVersion, 10115);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test('a failed migration rolls back prefix and version then retries', () async {
    final dir = await Directory.systemTemp.createTemp(
      'supplier-identity-retry-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/old.sqlite');
    await seed10093(file);
    var raw = sqlite.sqlite3.open(file.path);
    raw.execute(
      'CREATE VIEW supplier_product_identities AS SELECT 1 AS incompatible',
    );
    raw.close();
    var db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
    await db.close();
    raw = sqlite.sqlite3.open(file.path);
    expect(raw.userVersion, 10093);
    expect(
      raw.select(
        "SELECT name FROM pragma_table_info('suppliers') WHERE name='product_code'",
      ),
      isEmpty,
    );
    raw.execute('DROP VIEW supplier_product_identities');
    raw.close();
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    addTearDown(db.close);
    expect(await db.select(db.supplierProductIdentities).get(), isEmpty);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      10115,
    );
  });

  test(
    'fresh and upgraded identity table have the same columns and FKs',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'supplier-identity-schema-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/old.sqlite');
      await seed10093(file);
      const queries = [
        "PRAGMA table_info('supplier_product_identities')",
        "PRAGMA foreign_key_list('supplier_product_identities')",
        "PRAGMA index_list('supplier_product_identities')",
      ];
      final upgradedSchema = <String, List<Map<String, Object?>>>{};
      // Read and close the upgraded database before constructing the fresh one.
      // The schemas are compared as copied data, not as two live AppDatabases.
      final upgraded = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      try {
        for (final query in queries) {
          upgradedSchema[query] = (await upgraded.customSelect(query).get())
              .map((row) => Map<String, Object?>.from(row.data))
              .toList();
        }
      } finally {
        await upgraded.close();
      }
      final fresh = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      try {
        for (final query in queries) {
          final freshSchema = (await fresh.customSelect(query).get())
              .map((row) => Map<String, Object?>.from(row.data))
              .toList();
          expect(upgradedSchema[query], freshSchema, reason: query);
        }
      } finally {
        await fresh.close();
      }
    },
  );
}
