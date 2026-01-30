// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_dao.dart';

// ignore_for_file: type=lint
mixin _$CustomerDaoMixin on DatabaseAccessor<AppDatabase> {
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $LoyaltyTiersTable get loyaltyTiers => attachedDatabase.loyaltyTiers;
  $CustomersTable get customers => attachedDatabase.customers;
  $CustomerTransactionsTable get customerTransactions =>
      attachedDatabase.customerTransactions;
  CustomerDaoManager get managers => CustomerDaoManager(this);
}

class CustomerDaoManager {
  final _$CustomerDaoMixin _db;
  CustomerDaoManager(this._db);
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$LoyaltyTiersTableTableManager get loyaltyTiers =>
      $$LoyaltyTiersTableTableManager(_db.attachedDatabase, _db.loyaltyTiers);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$CustomerTransactionsTableTableManager get customerTransactions =>
      $$CustomerTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.customerTransactions,
      );
}
