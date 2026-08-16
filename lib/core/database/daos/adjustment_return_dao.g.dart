// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'adjustment_return_dao.dart';

// ignore_for_file: type=lint
mixin _$AdjustmentReturnDaoMixin on DatabaseAccessor<AppDatabase> {
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $UsersTable get users => attachedDatabase.users;
  $ReturnReasonCodesTable get returnReasonCodes =>
      attachedDatabase.returnReasonCodes;
  $PurchaseReturnAdjustmentsTable get purchaseReturnAdjustments =>
      attachedDatabase.purchaseReturnAdjustments;
  $ProductCategoriesTable get productCategories =>
      attachedDatabase.productCategories;
  $ProductsTable get products => attachedDatabase.products;
  $ProductColorsTable get productColors => attachedDatabase.productColors;
  $SizesTable get sizes => attachedDatabase.sizes;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $PurchaseReturnAdjustmentItemsTable get purchaseReturnAdjustmentItems =>
      attachedDatabase.purchaseReturnAdjustmentItems;
  $LoyaltyTiersTable get loyaltyTiers => attachedDatabase.loyaltyTiers;
  $CustomersTable get customers => attachedDatabase.customers;
  $RolesTable get roles => attachedDatabase.roles;
  $EmployeesTable get employees => attachedDatabase.employees;
  $CashierShiftsTable get cashierShifts => attachedDatabase.cashierShifts;
  $SaleReturnAdjustmentsTable get saleReturnAdjustments =>
      attachedDatabase.saleReturnAdjustments;
  $SaleReturnAdjustmentItemsTable get saleReturnAdjustmentItems =>
      attachedDatabase.saleReturnAdjustmentItems;
  $SupplierTransactionsTable get supplierTransactions =>
      attachedDatabase.supplierTransactions;
  $CustomerTransactionsTable get customerTransactions =>
      attachedDatabase.customerTransactions;
  $SalesTable get sales => attachedDatabase.sales;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  $PurchasesTable get purchases => attachedDatabase.purchases;
  $PurchaseItemsTable get purchaseItems => attachedDatabase.purchaseItems;
  AdjustmentReturnDaoManager get managers => AdjustmentReturnDaoManager(this);
}

class AdjustmentReturnDaoManager {
  final _$AdjustmentReturnDaoMixin _db;
  AdjustmentReturnDaoManager(this._db);
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$ReturnReasonCodesTableTableManager get returnReasonCodes =>
      $$ReturnReasonCodesTableTableManager(
        _db.attachedDatabase,
        _db.returnReasonCodes,
      );
  $$PurchaseReturnAdjustmentsTableTableManager get purchaseReturnAdjustments =>
      $$PurchaseReturnAdjustmentsTableTableManager(
        _db.attachedDatabase,
        _db.purchaseReturnAdjustments,
      );
  $$ProductCategoriesTableTableManager get productCategories =>
      $$ProductCategoriesTableTableManager(
        _db.attachedDatabase,
        _db.productCategories,
      );
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
  $$PurchaseReturnAdjustmentItemsTableTableManager
  get purchaseReturnAdjustmentItems =>
      $$PurchaseReturnAdjustmentItemsTableTableManager(
        _db.attachedDatabase,
        _db.purchaseReturnAdjustmentItems,
      );
  $$LoyaltyTiersTableTableManager get loyaltyTiers =>
      $$LoyaltyTiersTableTableManager(_db.attachedDatabase, _db.loyaltyTiers);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$RolesTableTableManager get roles =>
      $$RolesTableTableManager(_db.attachedDatabase, _db.roles);
  $$EmployeesTableTableManager get employees =>
      $$EmployeesTableTableManager(_db.attachedDatabase, _db.employees);
  $$CashierShiftsTableTableManager get cashierShifts =>
      $$CashierShiftsTableTableManager(_db.attachedDatabase, _db.cashierShifts);
  $$SaleReturnAdjustmentsTableTableManager get saleReturnAdjustments =>
      $$SaleReturnAdjustmentsTableTableManager(
        _db.attachedDatabase,
        _db.saleReturnAdjustments,
      );
  $$SaleReturnAdjustmentItemsTableTableManager get saleReturnAdjustmentItems =>
      $$SaleReturnAdjustmentItemsTableTableManager(
        _db.attachedDatabase,
        _db.saleReturnAdjustmentItems,
      );
  $$SupplierTransactionsTableTableManager get supplierTransactions =>
      $$SupplierTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.supplierTransactions,
      );
  $$CustomerTransactionsTableTableManager get customerTransactions =>
      $$CustomerTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.customerTransactions,
      );
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
  $$PurchasesTableTableManager get purchases =>
      $$PurchasesTableTableManager(_db.attachedDatabase, _db.purchases);
  $$PurchaseItemsTableTableManager get purchaseItems =>
      $$PurchaseItemsTableTableManager(_db.attachedDatabase, _db.purchaseItems);
}
