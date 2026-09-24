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
    '10111 to 10112 preserves data and installs ownership conversion guards',
    () async {
      final schema = await verifier.schemaAt(10111);
      addTearDown(schema.close);
      schema.rawDatabase.execute('''
        INSERT INTO app_settings(key,value,description,created_at,updated_at)
        VALUES('consignment.conversion.migration','kept','test',
        '2026-09-24T00:00:00.000Z','2026-09-24T00:00:00.000Z')
      ''');

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);
      addTearDown(db.close);

      expect(
        (await (db.select(db.appSettings)..where(
                  (row) => row.key.equals('consignment.conversion.migration'),
                ))
                .getSingle())
            .value,
        'kept',
      );
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ("
            "'consignment_ownership_conversions',"
            "'consignment_ownership_conversion_items') ORDER BY name",
          )
          .get();
      expect(tables.map((row) => row.read<String>('name')).toList(), [
        'consignment_ownership_conversion_items',
        'consignment_ownership_conversions',
      ]);
      final triggers = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='trigger' AND name IN ("
            "'consignment_conversion_insert_guard',"
            "'consignment_conversion_status_guard',"
            "'consignment_conversion_items_insert_guard') ORDER BY name",
          )
          .get();
      expect(triggers, hasLength(3));
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
}
