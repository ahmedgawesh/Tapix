import 'package:drift/drift.dart';

import 'products.dart';

/// Canonical active-ingredient dictionary. [normalizedName] is a stable,
/// case-folded search key (for example `ibuprofen`) while the display names
/// preserve the pharmacist-facing spelling in each supported language.
@DataClassName('ActiveIngredient')
class ActiveIngredients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get canonicalName => text().withLength(min: 1, max: 200)();
  TextColumn get normalizedName =>
      text().withLength(min: 1, max: 200).unique()();
  TextColumn get nameAr => text().nullable()();
  TextColumn get nameFr => text().nullable()();
  TextColumn get description => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Alternative spellings, trade-neutral synonyms and localized search names.
/// A normalized alias belongs to exactly one canonical ingredient so a search
/// can never silently resolve to two different substances.
@DataClassName('ActiveIngredientAlias')
class ActiveIngredientAliases extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get ingredientId => integer().references(
    ActiveIngredients,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get alias => text().withLength(min: 1, max: 200)();
  TextColumn get normalizedAlias =>
      text().withLength(min: 1, max: 200).unique()();
  TextColumn get languageCode => text().nullable().withLength(max: 10)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Pharmacy-only attributes belonging to a product, not to its inventory
/// variant. Different strengths must be separate products; variants remain
/// available for package/barcode/price/stock differences.
@DataClassName('MedicineProfile')
class MedicineProfiles extends Table {
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();

  /// Canonical extensible code such as tablet, capsule, syrup, cream or vial.
  TextColumn get dosageForm => text().withLength(min: 1, max: 80)();

  /// Canonical administration route (oral, topical, intravenous, ...).
  /// Nullable for legacy/imported rows; safe exact-alternative matching will
  /// require a populated, equal route before suggesting a substitution.
  TextColumn get administrationRoute => text().nullable().withLength(max: 80)();

  /// Lets the pharmacist exclude a product from automatic alternative lists
  /// even when ingredient, strength, form and route are identical.
  BoolColumn get substitutionEligible =>
      boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {productId};
}

/// Exact normalized strength for each active ingredient in a medicine.
/// Values are fixed-point integers with six decimal places after unit
/// normalization. Example: 400 mg is stored as 400000000 + unit `mg`; 0.4 g
/// is normalized to the same representation before insertion.
@DataClassName('MedicineActiveIngredient')
class MedicineActiveIngredients extends Table {
  IntColumn get productId => integer().references(
    MedicineProfiles,
    #productId,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get ingredientId => integer().references(
    ActiveIngredients,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get normalizedStrengthValueMicros => integer()();

  /// Normalized numerator unit family, for example mg, iu, unit, mmol, meq.
  TextColumn get normalizedStrengthUnit => text().withLength(min: 1, max: 24)();

  /// Optional denominator for concentrations (e.g. 100 mg / 5 ml).
  IntColumn get normalizedBasisValueMicros => integer().nullable()();
  TextColumn get normalizedBasisUnit => text().nullable().withLength(max: 24)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {productId, ingredientId};

  @override
  List<String> get customConstraints => const [
    'CHECK (normalized_strength_value_micros > 0)',
    'CHECK (normalized_basis_value_micros IS NULL OR normalized_basis_value_micros > 0)',
    'CHECK ((normalized_basis_value_micros IS NULL AND normalized_basis_unit IS NULL) OR (normalized_basis_value_micros IS NOT NULL AND normalized_basis_unit IS NOT NULL))',
  ];
}
