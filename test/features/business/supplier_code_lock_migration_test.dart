import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/app_database.dart';
import 'business_foundation_test.dart' as fixtures;
import 'support/purchase_supplier_source_fixture.dart';

void main() {
  Future<Map<String, List<Map<String, Object?>>>> seed10095(File file) async {
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    try {
      await fixtures.seedLegacyData(db);
      await removePurchaseSupplierSourceSchema(db);
      final supplier = (await db.select(db.suppliers).get()).single;
      // First assignment is allowed for an old supplier with invoices.
      await db.customStatement(
        'UPDATE suppliers SET product_code=?,is_active=0 WHERE id=?',
        ['007', supplier.id],
      );
      final guards = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='trigger' "
            "AND name LIKE 'supplier_code_lock_%'",
          )
          .get();
      for (final guard in guards) {
        await db.customStatement(
          'DROP TRIGGER "${guard.read<String>('name')}"',
        );
      }
      await db.customStatement('DROP TABLE supplier_product_code_locks');
      await db.customStatement('PRAGMA user_version=10095');
      return await fixtures.legacySnapshot(db);
    } finally {
      await db.close();
    }
  }

  test(
    '10095 -> 10099 locks existing prefix without changing old rows',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'supplier-lock-upgrade-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/old.sqlite');
      final before = await seed10095(file);
      final db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      addTearDown(db.close);
      final after = await fixtures.legacySnapshot(db);
      final locks = after.remove('supplier_product_code_locks')!;
      expect(locks, hasLength(1));
      expect(locks.single['product_code'], '007');
      for (final row in after['purchase_items']!) {
        expect(row.remove('supplier_identity_requested'), 0);
        expect(row.remove('supplier_identity_id'), isNull);
      }
      expect(after, before);
      expect(db.schemaVersion, 10115);
      final supplier = (await db.select(db.suppliers).get()).single;
      expect(supplier.isActive, isFalse);
      expect(await db.supplierDao.isProductCodeLocked(supplier.id), isTrue);
      await expectLater(
        db.customStatement('UPDATE suppliers SET product_code=? WHERE id=?', [
          'OTHER9',
          supplier.id,
        ]),
        throwsA(anything),
      );
      await db.supplierDao.setSupplierActive(supplier.id, true);
      expect(
        (await db.supplierDao.getSupplier(supplier.id))!.productCode,
        '007',
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test('failed v10099 upgrade preserves data/version and can retry', () async {
    final dir = await Directory.systemTemp.createTemp('supplier-lock-retry-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/old.sqlite');
    await seed10095(file);
    var raw = sqlite.sqlite3.open(file.path);
    raw.execute(
      'CREATE VIEW supplier_product_code_locks AS SELECT 1 AS incompatible',
    );
    raw.close();
    var db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
    await db.close();
    raw = sqlite.sqlite3.open(file.path);
    expect(raw.userVersion, 10095);
    expect(
      raw.select('SELECT product_code FROM suppliers').single['product_code'],
      '007',
    );
    raw.execute('DROP VIEW supplier_product_code_locks');
    raw.close();
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    addTearDown(db.close);
    expect(await db.select(db.supplierProductCodeLocks).get(), hasLength(1));
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      10115,
    );
  });

  test(
    'fresh and upgraded lock tables have equal schema and foreign keys',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'supplier-lock-schema-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/old.sqlite');
      await seed10095(file);
      const queries = [
        "PRAGMA table_info('supplier_product_code_locks')",
        "PRAGMA foreign_key_list('supplier_product_code_locks')",
        "PRAGMA index_list('supplier_product_code_locks')",
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
