// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_adjustment_dao.dart';

// ignore_for_file: type=lint
mixin _$InventoryAdjustmentDaoMixin on DatabaseAccessor<AppDatabase> {
  $BusinessOrganizationsTable get businessOrganizations =>
      attachedDatabase.businessOrganizations;
  $BusinessBranchesTable get businessBranches =>
      attachedDatabase.businessBranches;
  $BusinessWarehousesTable get businessWarehouses =>
      attachedDatabase.businessWarehouses;
  $ProductCategoriesTable get productCategories =>
      attachedDatabase.productCategories;
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  $ProductColorsTable get productColors => attachedDatabase.productColors;
  $SizesTable get sizes => attachedDatabase.sizes;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $UsersTable get users => attachedDatabase.users;
  $InventoryAdjustmentsTable get inventoryAdjustments =>
      attachedDatabase.inventoryAdjustments;
  InventoryAdjustmentDaoManager get managers =>
      InventoryAdjustmentDaoManager(this);
}

class InventoryAdjustmentDaoManager {
  final _$InventoryAdjustmentDaoMixin _db;
  InventoryAdjustmentDaoManager(this._db);
  $$BusinessOrganizationsTableTableManager get businessOrganizations =>
      $$BusinessOrganizationsTableTableManager(
        _db.attachedDatabase,
        _db.businessOrganizations,
      );
  $$BusinessBranchesTableTableManager get businessBranches =>
      $$BusinessBranchesTableTableManager(
        _db.attachedDatabase,
        _db.businessBranches,
      );
  $$BusinessWarehousesTableTableManager get businessWarehouses =>
      $$BusinessWarehousesTableTableManager(
        _db.attachedDatabase,
        _db.businessWarehouses,
      );
  $$ProductCategoriesTableTableManager get productCategories =>
      $$ProductCategoriesTableTableManager(
        _db.attachedDatabase,
        _db.productCategories,
      );
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$ProductColorsTableTableManager get productColors =>
      $$ProductColorsTableTableManager(_db.attachedDatabase, _db.productColors);
  $$SizesTableTableManager get sizes =>
      $$SizesTableTableManager(_db.attachedDatabase, _db.sizes);
  $$ProductVariantsTableTableManager get productVariants =>
      $$ProductVariantsTableTableManager(
        _db.attachedDatabase,
        _db.productVariants,
      );
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$InventoryAdjustmentsTableTableManager get inventoryAdjustments =>
      $$InventoryAdjustmentsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryAdjustments,
      );
}
