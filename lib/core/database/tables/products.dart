import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';
import 'parties.dart';

@DataClassName('ProductCategory')
class ProductCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get parentId => integer().nullable().references(ProductCategories, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ProductColor')
class ProductColors extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get hexCode => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Size')
class Sizes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Product')
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sku => text().nullable().unique()();
  TextColumn get barcode => text().nullable().unique()();
  TextColumn get name => text()();
  TextColumn get nameAr => text().nullable()();
  TextColumn get nameFr => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get categoryId => integer().nullable().references(ProductCategories, #id, onDelete: KeyAction.restrict)();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  IntColumn get costCents => integer().map(const MoneyConverter())();
  IntColumn get priceCents => integer().map(const MoneyConverter())();
  IntColumn get wholesalePriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousCostCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousPriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousWholesalePriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get currencyId => integer().nullable().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get trackInventory => boolean().withDefault(const Constant(true))();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))(); // quantity in requirements
  IntColumn get minQuantity => integer().withDefault(const Constant(0))(); // reorderLevel in requirements
  BoolColumn get hasVariants => boolean().withDefault(const Constant(false))();
  BoolColumn get isTaxable => boolean().withDefault(const Constant(false))();
  IntColumn get taxRateBps => integer().withDefault(const Constant(0))();
  TextColumn get imagePath => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ProductVariant')
class ProductVariants extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.cascade)();
  TextColumn get sku => text().nullable().unique()();
  TextColumn get barcode => text().nullable().unique()();
  IntColumn get colorId => integer().nullable().references(ProductColors, #id, onDelete: KeyAction.restrict)();
  IntColumn get sizeId => integer().nullable().references(Sizes, #id, onDelete: KeyAction.restrict)();
  IntColumn get costCents => integer().map(const MoneyConverter())();
  IntColumn get priceCents => integer().map(const MoneyConverter())();
  IntColumn get wholesalePriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousCostCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousPriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousWholesalePriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get priceAdjustmentCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))(); // quantity in requirements
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ProductBatch')
class ProductBatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get variantId => integer().nullable().references(ProductVariants, #id, onDelete: KeyAction.cascade)();
  TextColumn get batchNumber => text()();
  IntColumn get quantity => integer()();
  IntColumn get costCents => integer().map(const MoneyConverter())();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
