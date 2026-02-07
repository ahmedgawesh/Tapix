// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sale_dao.dart';

// ignore_for_file: type=lint
mixin _$SaleDaoMixin on DatabaseAccessor<AppDatabase> {
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $LoyaltyTiersTable get loyaltyTiers => attachedDatabase.loyaltyTiers;
  $CustomersTable get customers => attachedDatabase.customers;
  $UsersTable get users => attachedDatabase.users;
  $RolesTable get roles => attachedDatabase.roles;
  $EmployeesTable get employees => attachedDatabase.employees;
  $SalesTable get sales => attachedDatabase.sales;
  $ProductCategoriesTable get productCategories =>
      attachedDatabase.productCategories;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  $ProductColorsTable get productColors => attachedDatabase.productColors;
  $SizesTable get sizes => attachedDatabase.sizes;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  $SaleTaxBandsTable get saleTaxBands => attachedDatabase.saleTaxBands;
  $SaleReturnsTable get saleReturns => attachedDatabase.saleReturns;
  $SaleReturnItemsTable get saleReturnItems => attachedDatabase.saleReturnItems;
  $SalePaymentsTable get salePayments => attachedDatabase.salePayments;
  SaleDaoManager get managers => SaleDaoManager(this);
}

class SaleDaoManager {
  final _$SaleDaoMixin _db;
  SaleDaoManager(this._db);
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$LoyaltyTiersTableTableManager get loyaltyTiers =>
      $$LoyaltyTiersTableTableManager(_db.attachedDatabase, _db.loyaltyTiers);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$RolesTableTableManager get roles =>
      $$RolesTableTableManager(_db.attachedDatabase, _db.roles);
  $$EmployeesTableTableManager get employees =>
      $$EmployeesTableTableManager(_db.attachedDatabase, _db.employees);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$ProductCategoriesTableTableManager get productCategories =>
      $$ProductCategoriesTableTableManager(
        _db.attachedDatabase,
        _db.productCategories,
      );
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
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
  $$SaleTaxBandsTableTableManager get saleTaxBands =>
      $$SaleTaxBandsTableTableManager(_db.attachedDatabase, _db.saleTaxBands);
  $$SaleReturnsTableTableManager get saleReturns =>
      $$SaleReturnsTableTableManager(_db.attachedDatabase, _db.saleReturns);
  $$SaleReturnItemsTableTableManager get saleReturnItems =>
      $$SaleReturnItemsTableTableManager(
        _db.attachedDatabase,
        _db.saleReturnItems,
      );
  $$SalePaymentsTableTableManager get salePayments =>
      $$SalePaymentsTableTableManager(_db.attachedDatabase, _db.salePayments);
}
