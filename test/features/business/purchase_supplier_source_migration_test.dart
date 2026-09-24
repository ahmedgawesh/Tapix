import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/app_database.dart';

import 'business_foundation_test.dart' as fixtures;
import 'support/purchase_supplier_source_fixture.dart';

void main() {
  Future<Map<String, List<Map<String, Object?>>>> seed10096(File file) async {
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    try {
      await fixtures.seedLegacyData(db);
      // Ensure the fixture contains an actual old purchase LINE, not headers only.
      await db.customStatement('''INSERT INTO purchase_items
        (purchase_id,product_id,variant_id,quantity,quantity_scale,measurement_type,
         unit_cost_cents,subtotal_cents,total_cents)
        SELECT p.id,pr.id,v.id,1250,1000,'weight',701,876,876
        FROM purchases p JOIN products pr ON pr.costing_method='wac'
        JOIN product_variants v ON v.product_id=pr.id LIMIT 1''');
      final supplier = (await db.select(db.suppliers).get()).single;
      await db.customStatement(
        'UPDATE suppliers SET product_code=? WHERE id=?',
        ['007', supplier.id],
      );
      await removePurchaseSupplierSourceSchema(db);
      // Match the actual user-exported v10096 purchase columns, rather than
      // merely changing user_version on a future-schema database.
      final schema =
          jsonDecode(
                File(
                  'drift_schemas/app_database/drift_schema_v10096.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final entities = schema['entities'] as List<dynamic>;
      final table =
          entities.cast<Map<String, dynamic>>().singleWhere(
                (e) =>
                    e['type'] == 'table' &&
                    (e['data'] as Map<String, dynamic>)['name'] ==
                        'purchase_items',
              )['data']
              as Map<String, dynamic>;
      final expected = (table['columns'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((c) => c['name'])
          .toList();
      final actual =
          (await db.customSelect("PRAGMA table_info('purchase_items')").get())
              .map((r) => r.read<String>('name'))
              .toList();
      expect(actual, expected);
      await db.customStatement('PRAGMA user_version=10096');
      return await fixtures.legacySnapshot(db);
    } finally {
      await db.close();
    }
  }

  test(
    '10096 -> 10099 preserves old invoices, stock, codes and locks',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'purchase-source-upgrade-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/old.sqlite');
      final before = await seed10096(file);
      final db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      addTearDown(db.close);
      final after = await fixtures.legacySnapshot(db);
      expect(after['purchase_items'], isNotEmpty);
      for (final row in after['purchase_items']!) {
        expect(row.remove('supplier_identity_requested'), 0);
        expect(row.remove('supplier_identity_id'), isNull);
      }
      expect(after, before);
      expect(db.schemaVersion, 10115);
      expect(await db.select(db.supplierProductIdentities).get(), isEmpty);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
        (await db.customSelect('PRAGMA integrity_check').getSingle())
            .data
            .values
            .single,
        'ok',
      );
    },
  );

  test(
    'migration failure rolls back columns and version, then retries',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'purchase-source-retry-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/old.sqlite');
      await seed10096(file);
      var raw = sqlite.sqlite3.open(file.path);
      raw.execute(
        'CREATE VIEW idx_purchase_items_supplier_identity AS SELECT 1 AS blocker',
      );
      raw.close();
      var db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      await db.close();
      raw = sqlite.sqlite3.open(file.path);
      expect(raw.userVersion, 10096);
      expect(
        raw.select(
          "SELECT name FROM pragma_table_info('purchase_items') "
          "WHERE name='supplier_identity_id'",
        ),
        isEmpty,
      );
      expect(
        raw.select('SELECT product_code FROM suppliers').single['product_code'],
        '007',
      );
      raw.execute('DROP VIEW idx_purchase_items_supplier_identity');
      raw.close();
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      addTearDown(db.close);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        10115,
      );
      expect(
        (await db.select(db.purchaseItems).get()).single.supplierIdentityId,
        isNull,
      );
    },
  );

  test('fresh and upgraded purchase source columns and guards agree', () async {
    final dir = await Directory.systemTemp.createTemp(
      'purchase-source-schema-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/old.sqlite');
    await seed10096(file);
    const queries = [
      "PRAGMA table_info('purchase_items')",
      "PRAGMA foreign_key_list('purchase_items')",
      "SELECT name,sql FROM sqlite_master WHERE name LIKE 'purchase_supplier_source_%' OR name='idx_purchase_items_supplier_identity' ORDER BY name",
    ];
    Future<Map<String, List<Map<String, Object?>>>> readAndClose(
      AppDatabase db,
    ) async {
      try {
        final result = <String, List<Map<String, Object?>>>{};
        for (final q in queries) {
          result[q] = (await db.customSelect(q).get())
              .map((r) => Map<String, Object?>.from(r.data))
              .toList();
        }
        return result;
      } finally {
        await db.close();
      }
    }

    final upgraded = await readAndClose(
      AppDatabase.connect(DatabaseConnection(NativeDatabase(file))),
    );
    final fresh = await readAndClose(
      AppDatabase.connect(DatabaseConnection(NativeDatabase.memory())),
    );
    expect(upgraded, fresh);
  });
}
