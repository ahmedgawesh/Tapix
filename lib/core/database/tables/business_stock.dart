import 'package:drift/drift.dart';

import 'business.dart';
import 'products.dart';

/// One quantity/cost record per concrete variant and warehouse. Primary stock
/// retains an atomic compatibility projection in product_variants while the
/// legacy single-warehouse writers are migrated to this table.
@DataClassName('BusinessWarehouseStock')
class BusinessWarehouseStocks extends Table {
  TextColumn get warehouseId => text().references(
    BusinessWarehouses,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get variantId =>
      integer().references(ProductVariants, #id, onDelete: KeyAction.cascade)();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  IntColumn get unitCostCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {warehouseId, variantId};

  @override
  List<String> get customConstraints => [
    "CHECK (typeof(quantity) = 'integer')",
    "CHECK (typeof(unit_cost_cents) = 'integer')",
  ];
}
