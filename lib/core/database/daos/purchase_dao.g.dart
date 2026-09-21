// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_dao.dart';

// ignore_for_file: type=lint
mixin _$PurchaseDaoMixin on DatabaseAccessor<AppDatabase> {
  $BusinessOrganizationsTable get businessOrganizations =>
      attachedDatabase.businessOrganizations;
  $BusinessBranchesTable get businessBranches =>
      attachedDatabase.businessBranches;
  $BusinessWarehousesTable get businessWarehouses =>
      attachedDatabase.businessWarehouses;
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $PurchasesTable get purchases => attachedDatabase.purchases;
  $ProductCategoriesTable get productCategories =>
      attachedDatabase.productCategories;
  $ProductsTable get products => attachedDatabase.products;
  $ProductColorsTable get productColors => attachedDatabase.productColors;
  $SizesTable get sizes => attachedDatabase.sizes;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $PurchaseItemsTable get purchaseItems => attachedDatabase.purchaseItems;
  $UsersTable get users => attachedDatabase.users;
  $ReturnReasonCodesTable get returnReasonCodes =>
      attachedDatabase.returnReasonCodes;
  $PurchaseReturnsTable get purchaseReturns => attachedDatabase.purchaseReturns;
  $PurchaseReturnItemsTable get purchaseReturnItems =>
      attachedDatabase.purchaseReturnItems;
  $PurchasePaymentsTable get purchasePayments =>
      attachedDatabase.purchasePayments;
  $SupplierTransactionsTable get supplierTransactions =>
      attachedDatabase.supplierTransactions;
  $ProductBatchesTable get productBatches => attachedDatabase.productBatches;
  PurchaseDaoManager get managers => PurchaseDaoManager(this);
}

class PurchaseDaoManager {
  final _$PurchaseDaoMixin _db;
  PurchaseDaoManager(this._db);
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
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$PurchasesTableTableManager get purchases =>
      $$PurchasesTableTableManager(_db.attachedDatabase, _db.purchases);
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
  $$PurchaseItemsTableTableManager get purchaseItems =>
      $$PurchaseItemsTableTableManager(_db.attachedDatabase, _db.purchaseItems);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$ReturnReasonCodesTableTableManager get returnReasonCodes =>
      $$ReturnReasonCodesTableTableManager(
        _db.attachedDatabase,
        _db.returnReasonCodes,
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
  $$PurchasePaymentsTableTableManager get purchasePayments =>
      $$PurchasePaymentsTableTableManager(
        _db.attachedDatabase,
        _db.purchasePayments,
      );
  $$SupplierTransactionsTableTableManager get supplierTransactions =>
      $$SupplierTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.supplierTransactions,
      );
  $$ProductBatchesTableTableManager get productBatches =>
      $$ProductBatchesTableTableManager(
        _db.attachedDatabase,
        _db.productBatches,
      );
}
