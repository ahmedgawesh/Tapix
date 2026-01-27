import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/product_color_entity.dart';
import '../../domain/repositories/product_color_repository.dart';
import '../models/product_color_model.dart';

class ProductColorRepositoryImpl implements ProductColorRepository {
  final db.AppDatabase _database;

  ProductColorRepositoryImpl(this._database);

  @override
  Stream<List<ProductColor>> watchAllColors() {
    return _database.productColorDao.watchAllColors().map(
          (colors) => colors
              .map((color) => ProductColorModel.fromDrift(color))
              .toList(),
        );
  }

  @override
  Stream<List<ProductColor>> watchColorsBySearch(String query) {
    if (query.isEmpty) {
      return watchAllColors();
    }
    
    return _database.productColorDao.watchAllColors().map(
      (colors) => colors
          .where((color) => color.name.toLowerCase().contains(query.toLowerCase()))
          .map((color) => ProductColorModel.fromDrift(color))
          .toList(),
    );
  }

  @override
  Future<List<ProductColor>> getAllColors() async {
    final colors = await _database.productColorDao.getAllColors();
    return colors.map((color) => ProductColorModel.fromDrift(color)).toList();
  }

  @override
  Future<ProductColor?> getColorById(int id) async {
    final color = await _database.productColorDao.getColorById(id);
    return color != null ? ProductColorModel.fromDrift(color) : null;
  }

  @override
  Future<int> createColor(ProductColor color) async {
    final model = color as ProductColorModel;
    return await _database.productColorDao.createColor(model.toCompanion());
  }

  @override
  Future<bool> updateColor(ProductColor color) async {
    final driftColor = await _database.productColorDao.getColorById(color.id);
    if (driftColor == null) return false;
    
    final updatedColor = driftColor.copyWith(
      name: color.name,
      hexCode: Value(color.hexCode),
      isActive: color.isActive,
    );
    
    return await _database.productColorDao.updateColor(updatedColor);
  }

  @override
  Future<void> deleteColor(int id) async {
    await _database.productColorDao.deleteColor(id);
  }

  @override
  Future<int> getProductCountByColor(int colorId) async {
    final count = await (_database.select(_database.productVariants)
          ..where((v) => v.colorId.equals(colorId)))
        .get();
    return count.length;
  }

  @override
  Future<bool> hasProducts(int colorId) async {
    final count = await getProductCountByColor(colorId);
    return count > 0;
  }
}
