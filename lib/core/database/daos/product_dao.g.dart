// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_dao.dart';

// ignore_for_file: type=lint
mixin _$ProductDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductCategoriesTable get productCategories =>
      attachedDatabase.productCategories;
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  $ProductColorsTable get productColors => attachedDatabase.productColors;
  $SizesTable get sizes => attachedDatabase.sizes;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $ProductBatchesTable get productBatches => attachedDatabase.productBatches;
  $BatchConsumptionsTable get batchConsumptions =>
      attachedDatabase.batchConsumptions;
  $UsersTable get users => attachedDatabase.users;
  $ProductPriceHistoriesTable get productPriceHistories =>
      attachedDatabase.productPriceHistories;
  $PurchasesTable get purchases => attachedDatabase.purchases;
  $PurchaseItemsTable get purchaseItems => attachedDatabase.purchaseItems;
  ProductDaoManager get managers => ProductDaoManager(this);
}

class ProductDaoManager {
  final _$ProductDaoMixin _db;
  ProductDaoManager(this._db);
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
  $$ProductBatchesTableTableManager get productBatches =>
      $$ProductBatchesTableTableManager(
        _db.attachedDatabase,
        _db.productBatches,
      );
  $$BatchConsumptionsTableTableManager get batchConsumptions =>
      $$BatchConsumptionsTableTableManager(
        _db.attachedDatabase,
        _db.batchConsumptions,
      );
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$ProductPriceHistoriesTableTableManager get productPriceHistories =>
      $$ProductPriceHistoriesTableTableManager(
        _db.attachedDatabase,
        _db.productPriceHistories,
      );
  $$PurchasesTableTableManager get purchases =>
      $$PurchasesTableTableManager(_db.attachedDatabase, _db.purchases);
  $$PurchaseItemsTableTableManager get purchaseItems =>
      $$PurchaseItemsTableTableManager(_db.attachedDatabase, _db.purchaseItems);
}
