// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cheque_confirmation_dao.dart';

// ignore_for_file: type=lint
mixin _$ChequeConfirmationDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $ChequeConfirmationsTable get chequeConfirmations =>
      attachedDatabase.chequeConfirmations;
  ChequeConfirmationDaoManager get managers =>
      ChequeConfirmationDaoManager(this);
}

class ChequeConfirmationDaoManager {
  final _$ChequeConfirmationDaoMixin _db;
  ChequeConfirmationDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$ChequeConfirmationsTableTableManager get chequeConfirmations =>
      $$ChequeConfirmationsTableTableManager(
        _db.attachedDatabase,
        _db.chequeConfirmations,
      );
}
