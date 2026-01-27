// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'size_dao.dart';

// ignore_for_file: type=lint
mixin _$SizeDaoMixin on DatabaseAccessor<AppDatabase> {
  $SizesTable get sizes => attachedDatabase.sizes;
  SizeDaoManager get managers => SizeDaoManager(this);
}

class SizeDaoManager {
  final _$SizeDaoMixin _db;
  SizeDaoManager(this._db);
  $$SizesTableTableManager get sizes =>
      $$SizesTableTableManager(_db.attachedDatabase, _db.sizes);
}
