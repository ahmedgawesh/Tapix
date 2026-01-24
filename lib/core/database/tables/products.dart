import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';

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
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Product')
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sku => text().unique()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get categoryId => integer().nullable().references(ProductCategories, #id, onDelete: KeyAction.restrict)();
  IntColumn get costCents => integer().map(const MoneyConverter())();
  IntColumn get priceCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get trackInventory => boolean().withDefault(const Constant(true))();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))();
  IntColumn get reorderLevel => integer().nullable()();
  BoolColumn get hasVariants => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ProductVariant')
class ProductVariants extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.cascade)();
  TextColumn get sku => text().unique()();
  IntColumn get colorId => integer().nullable().references(ProductColors, #id, onDelete: KeyAction.restrict)();
  IntColumn get sizeId => integer().nullable().references(Sizes, #id, onDelete: KeyAction.restrict)();
  IntColumn get costCents => integer().map(const MoneyConverter())();
  IntColumn get priceCents => integer().map(const MoneyConverter())();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))();
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
