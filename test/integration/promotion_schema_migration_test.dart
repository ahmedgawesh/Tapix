import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

const _promotionTables = <String>[
  'promotions',
  'promotion_conditions',
  'promotion_scopes',
  'promotion_rewards',
  'promotion_schedules',
  'sale_promotion_applications',
  'sale_item_promotion_allocations',
];

Future<Set<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void main() {
  test('fresh database contains the normalized promotion schema', () async {
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);

    final tables = await _tableNames(db);

    expect(db.schemaVersion, 10115);
    expect(tables, containsAll(_promotionTables));
    expect(
      (await (db.select(
            db.appSettings,
          )..where((row) => row.key.equals('promotions_enabled'))).getSingle())
          .value,
      '0',
    );
  });

  test(
    'promotion children cascade while sale snapshots remain normalized',
    () async {
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(db.close);

      await db.customStatement('''INSERT INTO promotions
           (code, name, promotion_type, status, application_mode,
            concurrency_mode, priority, price_mode, version)
           VALUES ('PROMO-1', 'Test', 'quantity', 'draft', 'automatic',
                   'best_price', 0, 'retail', 1)''');
      await db.customStatement('''INSERT INTO promotion_conditions
           (promotion_id, condition_type, condition_group,
            minimum_quantity, quantity_scale)
           VALUES (1, 'minimum_quantity', 'default', 3, 1)''');
      await db.customStatement('''INSERT INTO promotion_rewards
           (promotion_id, reward_type, apply_to, percent_bps, quantity_scale)
           VALUES (1, 'percentage_off', 'qualifying_lines', 1000, 1)''');

      await db.customStatement('DELETE FROM promotions WHERE id = 1');

      final conditionCount = await db
          .customSelect('SELECT COUNT(*) AS c FROM promotion_conditions')
          .getSingle();
      final rewardCount = await db
          .customSelect('SELECT COUNT(*) AS c FROM promotion_rewards')
          .getSingle();
      expect(conditionCount.read<int>('c'), 0);
      expect(rewardCount.read<int>('c'), 0);
    },
  );

  test('database at 10070 upgrades by creating all promotion tables', () async {
    final temp = await Directory.systemTemp.createTemp(
      'tapix_promotion_migration_',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final file = File('${temp.path}/tapix.db');

    var db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    await db.customSelect('SELECT 1').get();
    for (final table in _promotionTables.reversed) {
      await db.customStatement('DROP TABLE IF EXISTS $table');
    }
    await db.customStatement('PRAGMA user_version = 10070');
    await db.close();

    db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    addTearDown(db.close);
    final tables = await _tableNames(db);

    expect(db.schemaVersion, 10115);
    expect(tables, containsAll(_promotionTables));
  });
}
