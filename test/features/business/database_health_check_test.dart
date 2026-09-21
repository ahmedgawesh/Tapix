import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/database_health_check_service.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late DatabaseHealthCheckService service;
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    service = DatabaseHealthCheckService(db);
  });
  tearDown(() => db.close());
  Future<Map<String, Object>> snapshot() async {
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        )
        .get();
    return {
      for (final t in tables)
        t.read<String>(
          'name',
        ): (await db
                .customSelect(
                  'SELECT * FROM "${t.read<String>('name')}" ORDER BY rowid',
                )
                .get())
            .map((r) => r.data)
            .toList(),
    };
  }

  test('successful probe leaves every table and sequence unchanged', () async {
    final before = await snapshot();
    expect(await service.checkNullableVariantSku(), isTrue);
    expect(await snapshot(), before);
  });
  test('repeated checks do not consume identifiers or retain stock', () async {
    final before = await snapshot();
    for (var i = 0; i < 3; i++) {
      expect(await service.checkNullableVariantSku(), isTrue);
    }
    expect(await snapshot(), before);
  });
  test(
    'variant insertion failure rolls back the product and trigger effects',
    () async {
      await db.customStatement(
        "CREATE TRIGGER fail_health_variant BEFORE INSERT ON product_variants BEGIN SELECT RAISE(ABORT,'probe failure'); END",
      );
      final before = await snapshot();
      await expectLater(
        service.checkNullableVariantSku(),
        throwsA(isA<Exception>()),
      );
      expect(await snapshot(), before);
    },
  );
  test('failed SKU assertion also rolls back everything', () async {
    await db.customStatement(
      "CREATE TRIGGER change_health_sku AFTER INSERT ON product_variants BEGIN UPDATE product_variants SET sku='unexpected-probe-sku' WHERE id=NEW.id; END",
    );
    final before = await snapshot();
    expect(await service.checkNullableVariantSku(), isFalse);
    expect(await snapshot(), before);
  });
  test(
    'nested diagnostic rollback does not discard enclosing transaction',
    () async {
      await db.transaction(() async {
        await db.customStatement(
          "INSERT INTO product_categories(name) VALUES ('Existing transaction')",
        );
        final before = await snapshot();
        expect(await service.checkNullableVariantSku(), isTrue);
        expect(await snapshot(), before);
      });
      final row = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM product_categories WHERE name='Existing transaction'",
          )
          .getSingle();
      expect(row.read<int>('n'), 1);
    },
  );
}
