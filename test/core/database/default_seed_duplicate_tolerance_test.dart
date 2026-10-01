import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

void main() {
  test('startup tolerates legacy duplicate default colors and sizes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tapix-seed-duplicates-',
    );
    final file = File.fromUri(directory.uri.resolve('tapix.db'));

    var db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      'INSERT INTO product_colors (name, hex_code, is_active, created_at) '
      'VALUES (\'Red\', \'#FF0000\', 1, CURRENT_TIMESTAMP)',
    );
    await db.customStatement(
      'INSERT INTO sizes '
      '(name, description, sort_order, is_active, created_at) '
      'VALUES (\'Small\', \'S\', 2, 1, CURRENT_TIMESTAMP)',
    );
    await db.close();

    db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    addTearDown(() async {
      await db.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    expect(await db.customSelect('SELECT 1').get(), hasLength(1));
    final redCount = await db
        .customSelect(
          "SELECT COUNT(*) AS count FROM product_colors WHERE name = 'Red'",
        )
        .getSingle();
    final smallCount = await db
        .customSelect(
          "SELECT COUNT(*) AS count FROM sizes WHERE name = 'Small'",
        )
        .getSingle();
    expect(redCount.read<int>('count'), 2);
    expect(smallCount.read<int>('count'), 2);
  });
}
