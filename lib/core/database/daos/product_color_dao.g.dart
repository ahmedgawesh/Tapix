// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_color_dao.dart';

// ignore_for_file: type=lint
mixin _$ProductColorDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductColorsTable get productColors => attachedDatabase.productColors;
  ProductColorDaoManager get managers => ProductColorDaoManager(this);
}

class ProductColorDaoManager {
  final _$ProductColorDaoMixin _db;
  ProductColorDaoManager(this._db);
  $$ProductColorsTableTableManager get productColors =>
      $$ProductColorsTableTableManager(_db.attachedDatabase, _db.productColors);
}
