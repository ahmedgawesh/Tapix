import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'business_foundation_test.dart' as fixtures;
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/variant_nullability.dart';

class LegacyDb extends AppDatabase {
  LegacyDb() : super.connect(DatabaseConnection(NativeDatabase.memory()));
  String? failAt;
  @override
  Future<void> customStatement(String statement, [List<Object?>? args]) {
    if (failAt != null && statement.startsWith(failAt!)) {
      throw StateError('Injected migration failure');
    }
    return super.customStatement(statement, args);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('CREATE TABLE products(id INTEGER PRIMARY KEY)');
      await customStatement('INSERT INTO products VALUES (1)');
      await customStatement('''CREATE TABLE "product_variants" (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id),
        "sku" TEXT NOT NULL UNIQUE,
        barcode TEXT NOT NULL UNIQUE,
        cost_cents INTEGER NOT NULL,
        stock_quantity INTEGER NOT NULL,
        wholesale_price_cents INTEGER,
        previous_cost_cents INTEGER,
        last_purchase_price_cents INTEGER,
        custom_note TEXT DEFAULT 'retained'
      )''');
      await customStatement('''INSERT INTO product_variants
        (id, product_id, sku, barcode, cost_cents, stock_quantity,
         wholesale_price_cents, previous_cost_cents, last_purchase_price_cents)
        VALUES (1, 1, '', '', 701, 1234, 801, 601, 751),
               (900, 1, 'deleted', 'deleted', 100, 0, NULL, NULL, NULL)''');
      await customStatement('DELETE FROM product_variants WHERE id = 900');
      await customStatement(
        'CREATE TABLE linked_lines(id INTEGER PRIMARY KEY, variant_id INTEGER REFERENCES product_variants(id) ON DELETE CASCADE)',
      );
      await customStatement('INSERT INTO linked_lines VALUES (1, 1)');
      await customStatement('CREATE TABLE repair_audit(value INTEGER)');
      await customStatement(
        'CREATE INDEX variant_stock_index ON product_variants(stock_quantity) WHERE stock_quantity > 0',
      );
      await customStatement(
        'CREATE TRIGGER variant_audit AFTER UPDATE OF stock_quantity ON product_variants BEGIN INSERT INTO repair_audit VALUES (NEW.stock_quantity); END',
      );
      await customStatement(
        'CREATE VIEW variant_view AS SELECT id, custom_note FROM product_variants',
      );
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

class FailingUpgradeDb extends AppDatabase {
  FailingUpgradeDb(File file)
    : super.connect(DatabaseConnection(NativeDatabase(file)));
  @override
  Future<void> customStatement(String statement, [List<Object?>? args]) {
    if (statement.startsWith('ALTER TABLE product_variants__repair')) {
      throw StateError('Injected failure after dropping the original table');
    }
    return super.customStatement(statement, args);
  }
}

void main() {
  late LegacyDb db;
  setUp(() async {
    db = LegacyDb();
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() => db.close());
  Future<Map<String, Object>> snapshot() async {
    final schema = await db
        .customSelect(
          'SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name',
        )
        .get();
    final result = <String, Object>{
      'schema': schema.map((r) => r.data).toList(),
    };
    for (final row in schema.where((r) => r.read<String>('type') == 'table')) {
      final name = row.read<String>('name');
      result[name] =
          (await db.customSelect('SELECT * FROM "$name" ORDER BY rowid').get())
              .map((r) => r.data)
              .toList();
    }
    return result;
  }

  Future<void> checkPragmas() async {
    expect(
      (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
        'foreign_keys',
      ),
      1,
    );
    expect(
      (await db.customSelect('PRAGMA legacy_alter_table').getSingle())
          .read<int>('legacy_alter_table'),
      0,
    );
  }

  test(
    'preserves every column, dependent row, index, trigger, view and sequence',
    () async {
      final before =
          (await db.customSelect('SELECT * FROM product_variants').getSingle())
              .data;
      await repairVariantNullability(db);
      expect(
        (await db.customSelect('SELECT * FROM product_variants').getSingle())
            .data,
        before,
      );
      expect(
        (await db.customSelect('SELECT * FROM linked_lines').get()).length,
        1,
      );
      expect(
        (await db.customSelect('SELECT * FROM variant_view').getSingle())
            .read<String>('custom_note'),
        'retained',
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      expect(
        (await db
                .customSelect('PRAGMA foreign_key_list(linked_lines)')
                .getSingle())
            .read<String>('table'),
        'product_variants',
      );
      await checkPragmas();
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = 1235 WHERE id = 1',
      );
      expect(
        (await db.customSelect('SELECT value FROM repair_audit').getSingle())
            .read<int>('value'),
        1235,
      );
      await db.customStatement(
        'INSERT INTO product_variants(product_id, sku, barcode, cost_cents, stock_quantity) VALUES (1, NULL, NULL, 701, 0)',
      );
      expect(
        (await db
                .customSelect('SELECT MAX(id) AS id FROM product_variants')
                .getSingle())
            .read<int>('id'),
        901,
      );
      expect(
        (await db
                .customSelect(
                  "SELECT 1 FROM sqlite_master WHERE name = 'variant_stock_index'",
                )
                .get())
            .length,
        1,
      );
      final once = await snapshot();
      await repairVariantNullability(db);
      expect(await snapshot(), once);
    },
  );

  for (final step in [
    'INSERT INTO product_variants__repair',
    'DROP TABLE product_variants',
    'ALTER TABLE product_variants__repair',
    'CREATE INDEX variant_stock_index',
    'CREATE TRIGGER variant_audit',
    'UPDATE sqlite_sequence',
  ]) {
    test(
      'failure at $step rolls back schema and rows; retry succeeds',
      () async {
        final before = await snapshot();
        db.failAt = step;
        await expectLater(repairVariantNullability(db), throwsStateError);
        db.failAt = null;
        expect(await snapshot(), before);
        await checkPragmas();
        await repairVariantNullability(db);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  }

  test(
    'existing transaction with foreign keys enabled is refused before changes',
    () async {
      final before = await snapshot();
      await db.transaction(() async {
        await expectLater(repairVariantNullability(db), throwsStateError);
      });
      expect(await snapshot(), before);
      await checkPragmas();
    },
  );
  test('post-warehouse malformed schema is refused without changes', () async {
    await db.customStatement(
      'CREATE TABLE business_warehouse_stocks(id INTEGER PRIMARY KEY)',
    );
    final before = await snapshot();
    await expectLater(repairVariantNullability(db), throwsStateError);
    expect(await snapshot(), before);
    await checkPragmas();
  });
  test('orphaned references stop repair without dropping data', () async {
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('INSERT INTO linked_lines VALUES (2, 999)');
    await db.customStatement('PRAGMA foreign_keys = ON');
    final before = await snapshot();
    await expectLater(repairVariantNullability(db), throwsStateError);
    expect(await snapshot(), before);
    await checkPragmas();
  });
  test(
    'leftover table from a historic interrupted repair is retained and refused',
    () async {
      await db.customStatement(
        'CREATE TABLE product_variants__old(id INTEGER, cost_cents INTEGER)',
      );
      await db.customStatement(
        'INSERT INTO product_variants__old VALUES (5, 1200)',
      );
      final before = await snapshot();
      await expectLater(repairVariantNullability(db), throwsStateError);
      expect(await snapshot(), before);
    },
  );
  for (final injectFailure in [false, true]) {
    test(
      'real 10085 file upgrades before warehouse setup; failure=$injectFailure',
      () async {
        final source = fixtures.memoryDb();
        final temp = await Directory.systemTemp.createTemp(
          'tapix-variant-repair-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final file = File('${temp.path}/legacy.sqlite');
        late Map<String, List<Map<String, Object?>>> before;
        try {
          await fixtures.seedLegacyData(source);
          await source.customStatement(
            "UPDATE product_variants SET sku = 'legacy-sku-' || id, barcode = 'legacy-barcode-' || id",
          );
          before = await fixtures.legacySnapshot(source);
          await source.customStatement('VACUUM INTO ?', [file.path]);
        } finally {
          await source.close();
        }
        final raw = sqlite.sqlite3.open(file.path);
        try {
          for (final trigger in raw.select(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' AND (name GLOB 'business_stock_*' OR name GLOB 'commission_return_source_*' OR name GLOB 'business_location_*' OR name GLOB 'consignment_*')",
          )) {
            raw.execute('DROP TRIGGER "${trigger['name']}"');
          }
          raw.execute('DROP TABLE business_warehouse_stocks');
          raw.execute('DROP INDEX commissions_by_sale_return');
          raw.execute('ALTER TABLE commissions DROP COLUMN sale_return_id');
          final ddl =
              raw
                      .select(
                        "SELECT sql FROM sqlite_master WHERE name = 'product_variants'",
                      )
                      .single['sql']
                  as String;
          final legacyDdl = ddl
              .replaceAll('"sku" TEXT NULL', '"sku" TEXT NOT NULL')
              .replaceAll('"barcode" TEXT NULL', '"barcode" TEXT NOT NULL');
          expect(legacyDdl, isNot(ddl));
          // Test fixture only: emulate the historical NOT NULL declaration.
          raw.execute('PRAGMA writable_schema = ON');
          raw.execute(
            "UPDATE sqlite_master SET sql = ? WHERE name = 'product_variants'",
            [legacyDdl],
          );
          raw.execute('PRAGMA writable_schema = OFF');
          raw.execute('PRAGMA user_version = 10085');
        } finally {
          raw.close();
        }
        if (injectFailure) {
          final failing = FailingUpgradeDb(file);
          try {
            await expectLater(
              failing.customSelect('SELECT 1').get(),
              throwsStateError,
            );
          } finally {
            await failing.close();
          }
          final inspect = sqlite.sqlite3.open(file.path);
          try {
            expect(
              inspect.select('PRAGMA user_version').single['user_version'],
              10085,
            );
            expect(
              inspect.select(
                "SELECT 1 FROM sqlite_master WHERE name = 'product_variants__repair'",
              ),
              isEmpty,
            );
            expect(
              inspect
                  .select('SELECT * FROM product_variants ORDER BY id')
                  .map((r) => Map<String, Object?>.from(r))
                  .toList(),
              before['product_variants'],
            );
            expect(inspect.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            inspect.close();
          }
        }
        final upgraded = AppDatabase.connect(
          DatabaseConnection(NativeDatabase(file)),
        );
        try {
          expect(await fixtures.legacySnapshot(upgraded), before);
          expect(
            await upgraded.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
          final mismatches = await upgraded.customSelect(
            '''SELECT v.id FROM product_variants v
          JOIN business_warehouse_stocks s ON s.variant_id = v.id
          WHERE s.quantity != v.stock_quantity OR s.unit_cost_cents != v.cost_cents''',
          ).get();
          expect(mismatches, isEmpty);
          expect(
            (await upgraded.select(upgraded.businessWarehouseStocks).get())
                .length,
            before['product_variants']!.length,
          );
          expect(
            (await upgraded.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            10115,
          );
        } finally {
          await upgraded.close();
        }
      },
    );
  }
}
