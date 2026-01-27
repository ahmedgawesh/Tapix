// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'barcode_template_dao.dart';

// ignore_for_file: type=lint
mixin _$BarcodeTemplateDaoMixin on DatabaseAccessor<AppDatabase> {
  $BarcodeTemplatesTable get barcodeTemplates =>
      attachedDatabase.barcodeTemplates;
  $ProductCategoriesTable get productCategories =>
      attachedDatabase.productCategories;
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  $ProductColorsTable get productColors => attachedDatabase.productColors;
  $SizesTable get sizes => attachedDatabase.sizes;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $PrintHistoriesTable get printHistories => attachedDatabase.printHistories;
  BarcodeTemplateDaoManager get managers => BarcodeTemplateDaoManager(this);
}

class BarcodeTemplateDaoManager {
  final _$BarcodeTemplateDaoMixin _db;
  BarcodeTemplateDaoManager(this._db);
  $$BarcodeTemplatesTableTableManager get barcodeTemplates =>
      $$BarcodeTemplatesTableTableManager(
        _db.attachedDatabase,
        _db.barcodeTemplates,
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
  $$PrintHistoriesTableTableManager get printHistories =>
      $$PrintHistoriesTableTableManager(
        _db.attachedDatabase,
        _db.printHistories,
      );
}
