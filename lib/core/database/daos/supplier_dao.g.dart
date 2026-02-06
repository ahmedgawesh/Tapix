// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'supplier_dao.dart';

// ignore_for_file: type=lint
mixin _$SupplierDaoMixin on DatabaseAccessor<AppDatabase> {
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $SupplierTransactionsTable get supplierTransactions =>
      attachedDatabase.supplierTransactions;
  SupplierDaoManager get managers => SupplierDaoManager(this);
}

class SupplierDaoManager {
  final _$SupplierDaoMixin _db;
  SupplierDaoManager(this._db);
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$SupplierTransactionsTableTableManager get supplierTransactions =>
      $$SupplierTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.supplierTransactions,
      );
}
