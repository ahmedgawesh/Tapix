import 'package:drift/drift.dart';
import 'business.dart';
import 'products.dart';

class InventoryOriginStates extends Table {
  TextColumn get warehouseId => text().references(BusinessWarehouses, #id)();
  IntColumn get variantId => integer().references(ProductVariants, #id)();
  IntColumn get quantity => integer()();
  TextColumn get measurementType => text()();
  IntColumn get dirty => integer().withDefault(const Constant(0))();
  TextColumn get layers => text()();
  @override
  Set<Column> get primaryKey => {warehouseId, variantId};
  @override
  List<String> get customConstraints => ['CHECK(dirty IN (0,1))'];
}

class InventoryOriginEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get warehouseId => text().references(BusinessWarehouses, #id)();
  IntColumn get variantId => integer().references(ProductVariants, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get measurementType => text()();
  TextColumn get eventKey => text()();
  TextColumn get claimKey => text().nullable()();
  IntColumn get delta => integer()();
  TextColumn get allocations => text()();
  TextColumn get createdAt => text().withDefault(
    const CustomExpression("(strftime('%Y-%m-%dT%H:%M:%fZ','now'))"),
  )();
  @override
  List<Set<Column>> get uniqueKeys => [
    {warehouseId, eventKey},
  ];
  @override
  List<String> get customConstraints => ['CHECK(delta != 0)'];
}
