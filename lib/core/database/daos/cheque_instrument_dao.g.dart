// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cheque_instrument_dao.dart';

// ignore_for_file: type=lint
mixin _$ChequeInstrumentDaoMixin on DatabaseAccessor<AppDatabase> {
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $UsersTable get users => attachedDatabase.users;
  $ChequeInstrumentsTable get chequeInstruments =>
      attachedDatabase.chequeInstruments;
  ChequeInstrumentDaoManager get managers => ChequeInstrumentDaoManager(this);
}

class ChequeInstrumentDaoManager {
  final _$ChequeInstrumentDaoMixin _db;
  ChequeInstrumentDaoManager(this._db);
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$ChequeInstrumentsTableTableManager get chequeInstruments =>
      $$ChequeInstrumentsTableTableManager(
        _db.attachedDatabase,
        _db.chequeInstruments,
      );
}
