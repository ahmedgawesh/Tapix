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
  $BusinessOrganizationsTable get businessOrganizations =>
      attachedDatabase.businessOrganizations;
  $BusinessBranchesTable get businessBranches =>
      attachedDatabase.businessBranches;
  $BusinessWarehousesTable get businessWarehouses =>
      attachedDatabase.businessWarehouses;
  $PurchasesTable get purchases => attachedDatabase.purchases;
  $SupplierProductIdentitiesTable get supplierProductIdentities =>
      attachedDatabase.supplierProductIdentities;
  $PurchaseItemsTable get purchaseItems => attachedDatabase.purchaseItems;
  $ProductBatchesTable get productBatches => attachedDatabase.productBatches;
  $LoyaltyTiersTable get loyaltyTiers => attachedDatabase.loyaltyTiers;
  $CustomersTable get customers => attachedDatabase.customers;
  $UsersTable get users => attachedDatabase.users;
  $RolesTable get roles => attachedDatabase.roles;
  $EmployeesTable get employees => attachedDatabase.employees;
  $CashierShiftsTable get cashierShifts => attachedDatabase.cashierShifts;
  $SalesTable get sales => attachedDatabase.sales;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  $ReturnReasonCodesTable get returnReasonCodes =>
      attachedDatabase.returnReasonCodes;
  $SaleReturnsTable get saleReturns => attachedDatabase.saleReturns;
  $SaleReturnItemsTable get saleReturnItems => attachedDatabase.saleReturnItems;
  $PurchaseReturnsTable get purchaseReturns => attachedDatabase.purchaseReturns;
  $PurchaseReturnItemsTable get purchaseReturnItems =>
      attachedDatabase.purchaseReturnItems;
  $InventoryAdjustmentsTable get inventoryAdjustments =>
      attachedDatabase.inventoryAdjustments;
  $PurchaseReturnAdjustmentsTable get purchaseReturnAdjustments =>
      attachedDatabase.purchaseReturnAdjustments;
  $PurchaseReturnAdjustmentItemsTable get purchaseReturnAdjustmentItems =>
      attachedDatabase.purchaseReturnAdjustmentItems;
  $SaleReturnAdjustmentsTable get saleReturnAdjustments =>
      attachedDatabase.saleReturnAdjustments;
  $SaleReturnAdjustmentItemsTable get saleReturnAdjustmentItems =>
      attachedDatabase.saleReturnAdjustmentItems;
  $BatchConsumptionsTable get batchConsumptions =>
      attachedDatabase.batchConsumptions;
  $ProductPriceHistoriesTable get productPriceHistories =>
      attachedDatabase.productPriceHistories;
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
  $$PurchasesTableTableManager get purchases =>
      $$PurchasesTableTableManager(_db.attachedDatabase, _db.purchases);
  $$SupplierProductIdentitiesTableTableManager get supplierProductIdentities =>
      $$SupplierProductIdentitiesTableTableManager(
        _db.attachedDatabase,
        _db.supplierProductIdentities,
      );
  $$PurchaseItemsTableTableManager get purchaseItems =>
      $$PurchaseItemsTableTableManager(_db.attachedDatabase, _db.purchaseItems);
  $$ProductBatchesTableTableManager get productBatches =>
      $$ProductBatchesTableTableManager(
        _db.attachedDatabase,
        _db.productBatches,
      );
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
  $$CashierShiftsTableTableManager get cashierShifts =>
      $$CashierShiftsTableTableManager(_db.attachedDatabase, _db.cashierShifts);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
  $$ReturnReasonCodesTableTableManager get returnReasonCodes =>
      $$ReturnReasonCodesTableTableManager(
        _db.attachedDatabase,
        _db.returnReasonCodes,
      );
  $$SaleReturnsTableTableManager get saleReturns =>
      $$SaleReturnsTableTableManager(_db.attachedDatabase, _db.saleReturns);
  $$SaleReturnItemsTableTableManager get saleReturnItems =>
      $$SaleReturnItemsTableTableManager(
        _db.attachedDatabase,
        _db.saleReturnItems,
      );
  $$PurchaseReturnsTableTableManager get purchaseReturns =>
      $$PurchaseReturnsTableTableManager(
        _db.attachedDatabase,
        _db.purchaseReturns,
      );
  $$PurchaseReturnItemsTableTableManager get purchaseReturnItems =>
      $$PurchaseReturnItemsTableTableManager(
        _db.attachedDatabase,
        _db.purchaseReturnItems,
      );
  $$InventoryAdjustmentsTableTableManager get inventoryAdjustments =>
      $$InventoryAdjustmentsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryAdjustments,
      );
  $$PurchaseReturnAdjustmentsTableTableManager get purchaseReturnAdjustments =>
      $$PurchaseReturnAdjustmentsTableTableManager(
        _db.attachedDatabase,
        _db.purchaseReturnAdjustments,
      );
  $$PurchaseReturnAdjustmentItemsTableTableManager
  get purchaseReturnAdjustmentItems =>
      $$PurchaseReturnAdjustmentItemsTableTableManager(
        _db.attachedDatabase,
        _db.purchaseReturnAdjustmentItems,
      );
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
  $$BatchConsumptionsTableTableManager get batchConsumptions =>
      $$BatchConsumptionsTableTableManager(
        _db.attachedDatabase,
        _db.batchConsumptions,
      );
  $$ProductPriceHistoriesTableTableManager get productPriceHistories =>
      $$ProductPriceHistoriesTableTableManager(
        _db.attachedDatabase,
        _db.productPriceHistories,
      );
}
