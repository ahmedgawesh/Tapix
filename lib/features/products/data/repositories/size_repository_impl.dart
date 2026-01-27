import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/size_entity.dart' as domain;
import '../../domain/repositories/size_repository.dart';
import '../models/size_model.dart';

class SizeRepositoryImpl implements SizeRepository {
  final db.AppDatabase _database;

  SizeRepositoryImpl(this._database);

  @override
  Stream<List<domain.Size>> watchAllSizes() {
    return _database.sizeDao.watchAllSizes().map(
      (sizes) => sizes.map((s) => SizeModel.fromDrift(s)).toList(),
    );
  }

  @override
  Stream<List<domain.Size>> watchSizesBySearch(String query) {
    return _database.sizeDao.watchAllSizes().map(
      (sizes) => sizes
          .where((s) => s.name.toLowerCase().contains(query.toLowerCase()))
          .map((s) => SizeModel.fromDrift(s))
          .toList(),
    );
  }

  @override
  Future<List<domain.Size>> getAllSizes() async {
    final sizes = await _database.sizeDao.getAllSizes();
    return sizes.map((s) => SizeModel.fromDrift(s)).toList();
  }

  @override
  Future<domain.Size?> getSizeById(int id) async {
    final size = await _database.sizeDao.getSizeById(id);
    return size != null ? SizeModel.fromDrift(size) : null;
  }

  @override
  Future<int> createSize(domain.Size size) async {
    final companion = db.SizesCompanion.insert(
      name: size.name,
      description: Value(size.description),
      sortOrder: Value(size.sortOrder),
      isActive: Value(size.isActive),
    );
    return await _database.sizeDao.createSize(companion);
  }

  @override
  Future<bool> updateSize(domain.Size size) async {
    final driftSize = await _database.sizeDao.getSizeById(size.id);
    if (driftSize == null) return false;

    final updated = driftSize.copyWith(
      name: size.name,
      description: Value(size.description),
      sortOrder: size.sortOrder,
      isActive: size.isActive,
    );

    return await _database.sizeDao.updateSize(updated);
  }

  @override
  Future<int> deleteSize(int id) async {
    return await _database.sizeDao.deleteSize(id);
  }

  @override
  Future<bool> hasProducts(int sizeId) async {
    final count = await getProductCountBySize(sizeId);
    return count > 0;
  }

  @override
  Future<int> getProductCountBySize(int sizeId) async {
    return _database.sizeDao.getProductCountBySize(sizeId);
  }
}
