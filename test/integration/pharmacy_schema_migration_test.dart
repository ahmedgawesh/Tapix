import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async => db.close());

  Future<int> insertProduct(String name) {
    return db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: name,
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
          ),
        );
  }

  test(
    'fresh schema stores multi-ingredient medicine strengths exactly',
    () async {
      expect(db.schemaVersion, 10070);
      final flag =
          await (db.select(db.appSettings)
                ..where((row) => row.key.equals('pharmacy_features_enabled')))
              .getSingle();
      expect(flag.value, '0');

      final productId = await insertProduct('Combination medicine');
      final ibuprofenId = await db
          .into(db.activeIngredients)
          .insert(
            ActiveIngredientsCompanion.insert(
              canonicalName: 'Ibuprofen',
              normalizedName: 'ibuprofen',
              nameAr: const Value('إيبوبروفين'),
            ),
          );
      final paracetamolId = await db
          .into(db.activeIngredients)
          .insert(
            ActiveIngredientsCompanion.insert(
              canonicalName: 'Paracetamol',
              normalizedName: 'paracetamol',
            ),
          );
      await db
          .into(db.activeIngredientAliases)
          .insert(
            ActiveIngredientAliasesCompanion.insert(
              ingredientId: ibuprofenId,
              alias: 'بروفين',
              normalizedAlias: 'بروفين',
              languageCode: const Value('ar'),
            ),
          );
      await db
          .into(db.medicineProfiles)
          .insert(
            MedicineProfilesCompanion.insert(
              productId: Value(productId),
              dosageForm: 'tablet',
              administrationRoute: const Value('oral'),
            ),
          );
      await db
          .into(db.medicineActiveIngredients)
          .insert(
            MedicineActiveIngredientsCompanion.insert(
              productId: productId,
              ingredientId: ibuprofenId,
              normalizedStrengthValueMicros: 400000000,
              normalizedStrengthUnit: 'mg',
              sortOrder: const Value(0),
            ),
          );
      await db
          .into(db.medicineActiveIngredients)
          .insert(
            MedicineActiveIngredientsCompanion.insert(
              productId: productId,
              ingredientId: paracetamolId,
              normalizedStrengthValueMicros: 500000000,
              normalizedStrengthUnit: 'mg',
              sortOrder: const Value(1),
            ),
          );

      final ingredients = await (db.select(
        db.medicineActiveIngredients,
      )..where((row) => row.productId.equals(productId))).get();
      expect(ingredients, hasLength(2));
      expect(ingredients.first.normalizedStrengthValueMicros, 400000000);
    },
  );

  test(
    'database constraints reject ambiguous or duplicate medicine data',
    () async {
      final productId = await insertProduct('Ibuprofen 100mg/5ml');
      final ingredientId = await db
          .into(db.activeIngredients)
          .insert(
            ActiveIngredientsCompanion.insert(
              canonicalName: 'Ibuprofen',
              normalizedName: 'ibuprofen',
            ),
          );
      await db
          .into(db.medicineProfiles)
          .insert(
            MedicineProfilesCompanion.insert(
              productId: Value(productId),
              dosageForm: 'suspension',
              administrationRoute: const Value('oral'),
            ),
          );

      await expectLater(
        () => db.customStatement(
          'INSERT INTO medicine_active_ingredients '
          '(product_id, ingredient_id, normalized_strength_value_micros, '
          'normalized_strength_unit, normalized_basis_value_micros) '
          'VALUES (?, ?, ?, ?, ?)',
          [productId, ingredientId, 100000000, 'mg', 5000000],
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => db.customStatement(
          'INSERT INTO medicine_active_ingredients '
          '(product_id, ingredient_id, normalized_strength_value_micros, '
          'normalized_strength_unit) VALUES (?, ?, 0, ?)',
          [productId, ingredientId, 'mg'],
        ),
        throwsA(isA<Exception>()),
      );

      await db
          .into(db.medicineActiveIngredients)
          .insert(
            MedicineActiveIngredientsCompanion.insert(
              productId: productId,
              ingredientId: ingredientId,
              normalizedStrengthValueMicros: 100000000,
              normalizedStrengthUnit: 'mg',
              normalizedBasisValueMicros: const Value(5000000),
              normalizedBasisUnit: const Value('ml'),
            ),
          );
      await expectLater(
        () => db
            .into(db.medicineActiveIngredients)
            .insert(
              MedicineActiveIngredientsCompanion.insert(
                productId: productId,
                ingredientId: ingredientId,
                normalizedStrengthValueMicros: 100000000,
                normalizedStrengthUnit: 'mg',
              ),
            ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        () => db
            .into(db.activeIngredients)
            .insert(
              ActiveIngredientsCompanion.insert(
                canonicalName: 'IBUPROFEN duplicate',
                normalizedName: 'ibuprofen',
              ),
            ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('product deletion cascades only its pharmacy profile', () async {
    final productId = await insertProduct('Cascade medicine');
    final ingredientId = await db
        .into(db.activeIngredients)
        .insert(
          ActiveIngredientsCompanion.insert(
            canonicalName: 'Test active',
            normalizedName: 'test active',
          ),
        );
    await db
        .into(db.medicineProfiles)
        .insert(
          MedicineProfilesCompanion.insert(
            productId: Value(productId),
            dosageForm: 'tablet',
          ),
        );
    await db
        .into(db.medicineActiveIngredients)
        .insert(
          MedicineActiveIngredientsCompanion.insert(
            productId: productId,
            ingredientId: ingredientId,
            normalizedStrengthValueMicros: 1000000,
            normalizedStrengthUnit: 'mg',
          ),
        );

    await (db.delete(
      db.products,
    )..where((row) => row.id.equals(productId))).go();
    expect(await db.select(db.medicineProfiles).get(), isEmpty);
    expect(await db.select(db.medicineActiveIngredients).get(), isEmpty);
    expect(await db.select(db.activeIngredients).get(), hasLength(1));
  });

  test('pharmacy feature seed never overwrites the owner choice', () async {
    await (db.update(db.appSettings)
          ..where((row) => row.key.equals('pharmacy_features_enabled')))
        .write(const AppSettingsCompanion(value: Value('1')));
    await db.seedInitialDataForTest();
    final flag = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals('pharmacy_features_enabled'))).getSingle();
    expect(flag.value, '1');
  });

  test('10069 database migrates additively to pharmacy schema 10070', () async {
    final temp = await Directory.systemTemp.createTemp(
      'tapix-pharmacy-migration-',
    );
    final file = File('${temp.path}/tapix.db');
    AppDatabase? fileDb;
    try {
      fileDb = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await fileDb.customSelect('SELECT 1').get();
      final productId = await fileDb
          .into(fileDb.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Existing non-pharmacy product',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
            ),
          );
      await fileDb.customStatement('DELETE FROM app_settings WHERE key = ?', [
        'pharmacy_features_enabled',
      ]);
      await fileDb.customStatement('DROP TABLE medicine_active_ingredients');
      await fileDb.customStatement('DROP TABLE medicine_profiles');
      await fileDb.customStatement('DROP TABLE active_ingredient_aliases');
      await fileDb.customStatement('DROP TABLE active_ingredients');
      await fileDb.customStatement('PRAGMA user_version = 10069');
      await fileDb.close();
      fileDb = null;

      fileDb = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await fileDb.customSelect('SELECT 1').get();
      expect(fileDb.schemaVersion, 10070);
      final existing = await (fileDb.select(
        fileDb.products,
      )..where((row) => row.id.equals(productId))).getSingle();
      expect(existing.name, 'Existing non-pharmacy product');
      for (final table in [
        'active_ingredients',
        'active_ingredient_aliases',
        'medicine_profiles',
        'medicine_active_ingredients',
      ]) {
        final found = await fileDb
            .customSelect(
              'SELECT COUNT(*) AS count FROM sqlite_master '
              'WHERE type = ? AND name = ?',
              variables: [
                Variable.withString('table'),
                Variable.withString(table),
              ],
            )
            .getSingle();
        expect(found.read<int>('count'), 1, reason: '$table was not migrated');
      }
      final flag =
          await (fileDb.select(fileDb.appSettings)
                ..where((row) => row.key.equals('pharmacy_features_enabled')))
              .getSingle();
      expect(flag.value, '0');
    } finally {
      await fileDb?.close();
      await temp.delete(recursive: true);
    }
  });
}
