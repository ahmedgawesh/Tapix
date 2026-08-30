import 'package:drift/drift.dart';

import '../../services/pharmacy/medicine_normalization_service.dart';
import '../app_database.dart';

class MedicineIngredientDraft {
  const MedicineIngredientDraft({
    required this.ingredientId,
    required this.value,
    required this.unit,
    this.displayName,
    this.basisValue,
    this.basisUnit,
  });

  final int ingredientId;
  final String value;
  final String unit;
  final String? displayName;
  final String? basisValue;
  final String? basisUnit;
}

class MedicineProfileDraft {
  const MedicineProfileDraft({
    required this.productId,
    required this.dosageForm,
    required this.ingredients,
    this.administrationRoute,
    this.substitutionEligible = true,
    this.notes,
  });

  final int productId;
  final String dosageForm;
  final String? administrationRoute;
  final bool substitutionEligible;
  final String? notes;
  final List<MedicineIngredientDraft> ingredients;
}

class MedicineIngredientDetails {
  const MedicineIngredientDetails({
    required this.ingredient,
    required this.strength,
  });

  final ActiveIngredient ingredient;
  final MedicineActiveIngredient strength;
}

class MedicineProfileDetails {
  const MedicineProfileDetails({
    required this.product,
    required this.profile,
    required this.ingredients,
  });

  final Product product;
  final MedicineProfile profile;
  final List<MedicineIngredientDetails> ingredients;
}

/// Owns the pharmacy catalogue and exact-substitution rules. It deliberately
/// uses the master's product rows as the source of availability and identity;
/// no pharmacy-only stock or price copy is created.
class PharmacyDao {
  PharmacyDao(
    this.db, {
    MedicineNormalizationService normalization =
        const MedicineNormalizationService(),
  }) : _normalization = normalization;

  final AppDatabase db;
  final MedicineNormalizationService _normalization;

  Future<ActiveIngredient> saveActiveIngredient({
    required String canonicalName,
    String? nameAr,
    String? nameFr,
    String? description,
  }) async {
    final normalized = _normalization.normalizeIngredientName(canonicalName);
    final aliasCollision =
        await (db.select(db.activeIngredientAliases)
              ..where((row) => row.normalizedAlias.equals(normalized)))
            .getSingleOrNull();
    if (aliasCollision != null) {
      throw const PharmacyValidationException('ingredient_name_conflict');
    }

    final existing = await (db.select(
      db.activeIngredients,
    )..where((row) => row.normalizedName.equals(normalized))).getSingleOrNull();
    final now = DateTime.now();
    if (existing == null) {
      final id = await db
          .into(db.activeIngredients)
          .insert(
            ActiveIngredientsCompanion.insert(
              canonicalName: canonicalName.trim(),
              normalizedName: normalized,
              nameAr: Value(_nullableText(nameAr)),
              nameFr: Value(_nullableText(nameFr)),
              description: Value(_nullableText(description)),
              updatedAt: Value(now),
            ),
          );
      return (db.select(
        db.activeIngredients,
      )..where((row) => row.id.equals(id))).getSingle();
    }

    await (db.update(
      db.activeIngredients,
    )..where((row) => row.id.equals(existing.id))).write(
      ActiveIngredientsCompanion(
        canonicalName: Value(canonicalName.trim()),
        nameAr: Value(_nullableText(nameAr)),
        nameFr: Value(_nullableText(nameFr)),
        description: Value(_nullableText(description)),
        isActive: const Value(true),
        updatedAt: Value(now),
      ),
    );
    return (db.select(
      db.activeIngredients,
    )..where((row) => row.id.equals(existing.id))).getSingle();
  }

  Future<ActiveIngredientAlias?> addIngredientAlias({
    required int ingredientId,
    required String alias,
    String? languageCode,
  }) async {
    final ingredient = await (db.select(
      db.activeIngredients,
    )..where((row) => row.id.equals(ingredientId))).getSingleOrNull();
    if (ingredient == null) {
      throw const PharmacyValidationException('ingredient_not_found');
    }
    final normalized = _normalization.normalizeIngredientName(alias);
    if (normalized == ingredient.normalizedName) return null;

    final canonicalCollision = await (db.select(
      db.activeIngredients,
    )..where((row) => row.normalizedName.equals(normalized))).getSingleOrNull();
    if (canonicalCollision != null) {
      throw const PharmacyValidationException('ingredient_name_conflict');
    }
    final existing =
        await (db.select(db.activeIngredientAliases)
              ..where((row) => row.normalizedAlias.equals(normalized)))
            .getSingleOrNull();
    if (existing != null) {
      if (existing.ingredientId == ingredientId) return existing;
      throw const PharmacyValidationException('ingredient_name_conflict');
    }

    final id = await db
        .into(db.activeIngredientAliases)
        .insert(
          ActiveIngredientAliasesCompanion.insert(
            ingredientId: ingredientId,
            alias: alias.trim(),
            normalizedAlias: normalized,
            languageCode: Value(_nullableText(languageCode)?.toLowerCase()),
          ),
        );
    return (db.select(
      db.activeIngredientAliases,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<List<ActiveIngredient>> searchActiveIngredients(String query) async {
    if (query.trim().isEmpty) {
      return (db.select(db.activeIngredients)
            ..where((row) => row.isActive.equals(true))
            ..orderBy([(row) => OrderingTerm.asc(row.canonicalName)]))
          .get();
    }
    final normalized = _normalization.normalizeIngredientName(query);
    final pattern = '%$normalized%';
    final aliases = await (db.select(
      db.activeIngredientAliases,
    )..where((row) => row.normalizedAlias.like(pattern))).get();
    final aliasIds = aliases.map((row) => row.ingredientId).toSet();
    final statement = db.select(db.activeIngredients)
      ..where(
        (row) =>
            row.isActive.equals(true) &
            (row.normalizedName.like(pattern) |
                row.nameAr.like(pattern) |
                row.nameFr.like(pattern) |
                (aliasIds.isEmpty
                    ? const Constant(false)
                    : row.id.isIn(aliasIds))),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.canonicalName)]);
    return statement.get();
  }

  Future<void> saveMedicineProfile(MedicineProfileDraft draft) async {
    if (draft.ingredients.isEmpty) {
      throw const PharmacyValidationException('medicine_ingredient_required');
    }
    final product = await (db.select(
      db.products,
    )..where((row) => row.id.equals(draft.productId))).getSingleOrNull();
    if (product == null) {
      throw const PharmacyValidationException('product_not_found');
    }

    final dosageForm = _normalization.normalizeCode(
      draft.dosageForm,
      field: 'dosage_form',
    );
    final routeText = _nullableText(draft.administrationRoute);
    final route = routeText == null
        ? null
        : _normalization.normalizeCode(
            routeText,
            field: 'administration_route',
          );

    final normalizedIngredients = <_NormalizedIngredientDraft>[];
    final ingredientIds = <int>{};
    for (final ingredient in draft.ingredients) {
      if (!ingredientIds.add(ingredient.ingredientId)) {
        throw const PharmacyValidationException(
          'medicine_ingredient_duplicated',
        );
      }
      normalizedIngredients.add(
        _NormalizedIngredientDraft(
          ingredient.ingredientId,
          _normalization.normalizeStrength(
            value: ingredient.value,
            unit: ingredient.unit,
            basisValue: ingredient.basisValue,
            basisUnit: ingredient.basisUnit,
          ),
        ),
      );
    }

    final ingredients =
        await (db.select(db.activeIngredients)..where(
              (row) => row.id.isIn(ingredientIds) & row.isActive.equals(true),
            ))
            .get();
    if (ingredients.length != ingredientIds.length) {
      throw const PharmacyValidationException('ingredient_not_found');
    }

    final now = DateTime.now();
    await db.transaction(() async {
      final existing =
          await (db.select(db.medicineProfiles)
                ..where((row) => row.productId.equals(draft.productId)))
              .getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.medicineProfiles)
            .insert(
              MedicineProfilesCompanion.insert(
                productId: Value(draft.productId),
                dosageForm: dosageForm,
                administrationRoute: Value(route),
                substitutionEligible: Value(draft.substitutionEligible),
                notes: Value(_nullableText(draft.notes)),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (db.update(
          db.medicineProfiles,
        )..where((row) => row.productId.equals(draft.productId))).write(
          MedicineProfilesCompanion(
            dosageForm: Value(dosageForm),
            administrationRoute: Value(route),
            substitutionEligible: Value(draft.substitutionEligible),
            notes: Value(_nullableText(draft.notes)),
            updatedAt: Value(now),
          ),
        );
      }

      await (db.delete(
        db.medicineActiveIngredients,
      )..where((row) => row.productId.equals(draft.productId))).go();
      for (var index = 0; index < normalizedIngredients.length; index++) {
        final ingredient = normalizedIngredients[index];
        await db
            .into(db.medicineActiveIngredients)
            .insert(
              MedicineActiveIngredientsCompanion.insert(
                productId: draft.productId,
                ingredientId: ingredient.ingredientId,
                normalizedStrengthValueMicros: ingredient.strength.valueMicros,
                normalizedStrengthUnit: ingredient.strength.unit,
                normalizedBasisValueMicros: Value(
                  ingredient.strength.basisValueMicros,
                ),
                normalizedBasisUnit: Value(ingredient.strength.basisUnit),
                sortOrder: Value(index),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  Future<void> deleteMedicineProfile(int productId) async {
    await (db.delete(
      db.medicineProfiles,
    )..where((row) => row.productId.equals(productId))).go();
  }

  Future<MedicineProfileDetails?> getMedicineProfile(int productId) async {
    final profile = await (db.select(
      db.medicineProfiles,
    )..where((row) => row.productId.equals(productId))).getSingleOrNull();
    if (profile == null) return null;
    final product = await (db.select(
      db.products,
    )..where((row) => row.id.equals(productId))).getSingle();
    final strengths = await _strengthsForProducts({productId});
    final ingredientIds = strengths.values
        .expand((rows) => rows)
        .map((row) => row.ingredientId)
        .toSet();
    final ingredientMap = await _ingredientMap(ingredientIds);
    return _details(
      product,
      profile,
      strengths[productId] ?? const [],
      ingredientMap,
    );
  }

  Future<Set<int>> getMedicineProductIds() async {
    final rows = await db.select(db.medicineProfiles).get();
    return rows.map((row) => row.productId).toSet();
  }

  Future<Set<int>> searchMedicineProductIds(String query) async {
    if (query.trim().isEmpty) return getMedicineProductIds();
    final ingredients = await searchActiveIngredients(query);
    if (ingredients.isEmpty) return const {};
    final ingredientIds = ingredients.map((row) => row.id).toSet();
    final rows = await (db.select(
      db.medicineActiveIngredients,
    )..where((row) => row.ingredientId.isIn(ingredientIds))).get();
    return rows.map((row) => row.productId).toSet();
  }

  Future<Map<int, MedicineProfileDetails>> getMedicineProfilesForProducts(
    Iterable<int> productIds,
  ) async {
    final ids = productIds.toSet();
    if (ids.isEmpty) return const {};
    final profiles = await (db.select(
      db.medicineProfiles,
    )..where((row) => row.productId.isIn(ids))).get();
    if (profiles.isEmpty) return const {};
    final profileIds = profiles.map((row) => row.productId).toSet();
    final products = await (db.select(
      db.products,
    )..where((row) => row.id.isIn(profileIds))).get();
    final strengths = await _strengthsForProducts(profileIds);
    final ingredientIds = strengths.values
        .expand((rows) => rows)
        .map((row) => row.ingredientId)
        .toSet();
    final ingredientMap = await _ingredientMap(ingredientIds);
    final profileMap = {for (final row in profiles) row.productId: row};
    return {
      for (final product in products)
        if (profileMap[product.id] case final profile?)
          product.id: _details(
            product,
            profile,
            strengths[product.id] ?? const [],
            ingredientMap,
          ),
    };
  }

  Future<List<MedicineProfileDetails>> findExactAlternatives(
    int productId,
  ) async {
    final source = await getMedicineProfile(productId);
    final route = source?.profile.administrationRoute;
    if (source == null ||
        !source.profile.substitutionEligible ||
        route == null ||
        route.isEmpty ||
        source.ingredients.any((row) => !row.ingredient.isActive)) {
      return const [];
    }

    final joined =
        db.select(db.medicineProfiles).join([
          innerJoin(
            db.products,
            db.products.id.equalsExp(db.medicineProfiles.productId),
          ),
        ])..where(
          db.medicineProfiles.productId.equals(productId).not() &
              db.medicineProfiles.substitutionEligible.equals(true) &
              db.medicineProfiles.dosageForm.equals(source.profile.dosageForm) &
              db.medicineProfiles.administrationRoute.equals(route) &
              db.products.isActive.equals(true),
        );
    final candidateRows = await joined.get();
    if (candidateRows.isEmpty) return const [];

    final productsById = <int, Product>{};
    final profilesById = <int, MedicineProfile>{};
    for (final row in candidateRows) {
      final profile = row.readTable(db.medicineProfiles);
      productsById[profile.productId] = row.readTable(db.products);
      profilesById[profile.productId] = profile;
    }

    final candidateIds = productsById.keys.toSet();
    final strengths = await _strengthsForProducts(candidateIds);
    final allIngredientIds = strengths.values
        .expand((rows) => rows)
        .map((row) => row.ingredientId)
        .toSet();
    final ingredientMap = await _ingredientMap(allIngredientIds);
    final sourceStrengths = source.ingredients
        .map((row) => row.strength)
        .toList();
    final alternatives = <MedicineProfileDetails>[];
    for (final candidateId in candidateIds) {
      final candidateStrengths = strengths[candidateId] ?? const [];
      if (!_sameFormula(sourceStrengths, candidateStrengths)) continue;
      if (candidateStrengths.any(
        (row) => ingredientMap[row.ingredientId]?.isActive != true,
      )) {
        continue;
      }
      alternatives.add(
        _details(
          productsById[candidateId]!,
          profilesById[candidateId]!,
          candidateStrengths,
          ingredientMap,
        ),
      );
    }
    alternatives.sort(
      (left, right) => left.product.name.compareTo(right.product.name),
    );
    return alternatives;
  }

  Future<Map<int, List<MedicineActiveIngredient>>> _strengthsForProducts(
    Set<int> productIds,
  ) async {
    if (productIds.isEmpty) return const {};
    final rows =
        await (db.select(db.medicineActiveIngredients)
              ..where((row) => row.productId.isIn(productIds))
              ..orderBy([
                (row) => OrderingTerm.asc(row.productId),
                (row) => OrderingTerm.asc(row.sortOrder),
              ]))
            .get();
    final result = <int, List<MedicineActiveIngredient>>{};
    for (final row in rows) {
      result.putIfAbsent(row.productId, () => []).add(row);
    }
    return result;
  }

  Future<Map<int, ActiveIngredient>> _ingredientMap(Set<int> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (db.select(
      db.activeIngredients,
    )..where((row) => row.id.isIn(ids))).get();
    return {for (final row in rows) row.id: row};
  }

  MedicineProfileDetails _details(
    Product product,
    MedicineProfile profile,
    List<MedicineActiveIngredient> strengths,
    Map<int, ActiveIngredient> ingredientMap,
  ) {
    return MedicineProfileDetails(
      product: product,
      profile: profile,
      ingredients: [
        for (final strength in strengths)
          if (ingredientMap[strength.ingredientId] case final ingredient?)
            MedicineIngredientDetails(
              ingredient: ingredient,
              strength: strength,
            ),
      ],
    );
  }

  bool _sameFormula(
    List<MedicineActiveIngredient> left,
    List<MedicineActiveIngredient> right,
  ) {
    if (left.length != right.length) return false;
    final rightByIngredient = {for (final row in right) row.ingredientId: row};
    for (final row in left) {
      final candidate = rightByIngredient[row.ingredientId];
      if (candidate == null ||
          !_asNormalizedStrength(
            row,
          ).equivalentTo(_asNormalizedStrength(candidate))) {
        return false;
      }
    }
    return true;
  }

  NormalizedMedicineStrength _asNormalizedStrength(
    MedicineActiveIngredient row,
  ) {
    return NormalizedMedicineStrength(
      valueMicros: row.normalizedStrengthValueMicros,
      unit: row.normalizedStrengthUnit,
      basisValueMicros: row.normalizedBasisValueMicros,
      basisUnit: row.normalizedBasisUnit,
    );
  }

  String? _nullableText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _NormalizedIngredientDraft {
  const _NormalizedIngredientDraft(this.ingredientId, this.strength);

  final int ingredientId;
  final NormalizedMedicineStrength strength;
}
