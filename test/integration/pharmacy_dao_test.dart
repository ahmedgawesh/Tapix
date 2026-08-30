import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/pharmacy_dao.dart';
import 'package:tapix/core/services/pharmacy/medicine_normalization_service.dart';

void main() {
  late AppDatabase db;
  late PharmacyDao dao;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    dao = PharmacyDao(db);
  });

  tearDown(() => db.close());

  Future<int> product(String name) {
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

  MedicineIngredientDraft strength(
    int ingredientId,
    String value,
    String unit, {
    String? per,
    String? perUnit,
  }) {
    return MedicineIngredientDraft(
      ingredientId: ingredientId,
      value: value,
      unit: unit,
      basisValue: per,
      basisUnit: perUnit,
    );
  }

  Future<void> profile(
    int productId,
    List<MedicineIngredientDraft> ingredients, {
    String form = 'suspension',
    String? route = 'oral',
    bool eligible = true,
  }) {
    return dao.saveMedicineProfile(
      MedicineProfileDraft(
        productId: productId,
        dosageForm: form,
        administrationRoute: route,
        substitutionEligible: eligible,
        ingredients: ingredients,
      ),
    );
  }

  test(
    'ingredient names and aliases resolve without ambiguous collisions',
    () async {
      final ibuprofen = await dao.saveActiveIngredient(
        canonicalName: 'Ibuprofen',
        nameAr: 'إيبوبروفين',
      );
      final paracetamol = await dao.saveActiveIngredient(
        canonicalName: 'Paracetamol',
        nameAr: 'باراسيتامول',
      );
      await dao.addIngredientAlias(
        ingredientId: ibuprofen.id,
        alias: 'إِيبُوبْرُوفِين',
        languageCode: 'ar',
      );

      final results = await dao.searchActiveIngredients('ايبوبروفين');
      expect(results.map((row) => row.id), [ibuprofen.id]);
      await expectLater(
        () => dao.addIngredientAlias(
          ingredientId: ibuprofen.id,
          alias: paracetamol.canonicalName,
        ),
        throwsA(
          isA<PharmacyValidationException>().having(
            (error) => error.code,
            'code',
            'ingredient_name_conflict',
          ),
        ),
      );
    },
  );

  test(
    'exact alternatives require equal concentration, form and route',
    () async {
      final ibuprofen = await dao.saveActiveIngredient(
        canonicalName: 'Ibuprofen',
      );
      final paracetamol = await dao.saveActiveIngredient(
        canonicalName: 'Paracetamol',
      );
      final source = await product('Original 100mg/5ml');
      final equivalent = await product('Equivalent 20mg/ml');
      final wrongStrength = await product('Wrong strength');
      final wrongForm = await product('Wrong form');
      final wrongRoute = await product('Wrong route');
      final extraIngredient = await product('Extra ingredient');
      final disabled = await product('Not substitutable');
      final inactive = await product('Inactive product');

      final perFive = strength(
        ibuprofen.id,
        '100',
        'mg',
        per: '5',
        perUnit: 'ml',
      );
      final perOneEquivalent = strength(
        ibuprofen.id,
        '0.02',
        'g',
        per: '0.001',
        perUnit: 'l',
      );
      await profile(source, [perFive]);
      await profile(equivalent, [perOneEquivalent]);
      await profile(wrongStrength, [
        strength(ibuprofen.id, '25', 'mg', per: '1', perUnit: 'ml'),
      ]);
      await profile(wrongForm, [perFive], form: 'tablet');
      await profile(wrongRoute, [perFive], route: 'topical');
      await profile(extraIngredient, [
        perFive,
        strength(paracetamol.id, '10', 'mg', per: '1', perUnit: 'ml'),
      ]);
      await profile(disabled, [perFive], eligible: false);
      await profile(inactive, [perFive]);
      await (db.update(db.products)..where((row) => row.id.equals(inactive)))
          .write(const ProductsCompanion(isActive: Value(false)));

      final alternatives = await dao.findExactAlternatives(source);
      expect(alternatives.map((row) => row.product.id), [equivalent]);
    },
  );

  test(
    'multi-ingredient alternatives match regardless of input order',
    () async {
      final ingredientA = await dao.saveActiveIngredient(canonicalName: 'A');
      final ingredientB = await dao.saveActiveIngredient(canonicalName: 'B');
      final source = await product('Combination original');
      final exact = await product('Combination exact');
      final missingOne = await product('Single ingredient only');

      await profile(source, [
        strength(ingredientA.id, '200', 'mg'),
        strength(ingredientB.id, '500', 'mg'),
      ], form: 'tablet');
      await profile(exact, [
        strength(ingredientB.id, '0.5', 'g'),
        strength(ingredientA.id, '0.2', 'g'),
      ], form: 'tablet');
      await profile(missingOne, [
        strength(ingredientA.id, '200', 'mg'),
      ], form: 'tablet');

      final alternatives = await dao.findExactAlternatives(source);
      expect(alternatives.map((row) => row.product.id), [exact]);
    },
  );

  test(
    'invalid profile update leaves the previous formula untouched',
    () async {
      final ingredient = await dao.saveActiveIngredient(canonicalName: 'Safe');
      final productId = await product('Atomic profile');
      await profile(productId, [strength(ingredient.id, '100', 'mg')]);

      await expectLater(
        () => profile(productId, [
          strength(ingredient.id, '200', 'mg'),
          strength(ingredient.id, '300', 'mg'),
        ]),
        throwsA(
          isA<PharmacyValidationException>().having(
            (error) => error.code,
            'code',
            'medicine_ingredient_duplicated',
          ),
        ),
      );

      final saved = await dao.getMedicineProfile(productId);
      expect(saved, isNotNull);
      expect(saved!.ingredients, hasLength(1));
      expect(
        saved.ingredients.single.strength.normalizedStrengthValueMicros,
        100000000,
      );
    },
  );

  test('missing route disables automatic substitution for safety', () async {
    final ingredient = await dao.saveActiveIngredient(canonicalName: 'Safe');
    final source = await product('No route source');
    final candidate = await product('No route candidate');
    await profile(source, [strength(ingredient.id, '100', 'mg')], route: null);
    await profile(candidate, [
      strength(ingredient.id, '100', 'mg'),
    ], route: null);

    expect(await dao.findExactAlternatives(source), isEmpty);
  });
}
