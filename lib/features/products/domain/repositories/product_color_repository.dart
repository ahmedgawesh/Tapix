import '../entities/product_color_entity.dart';

abstract class ProductColorRepository {
  Stream<List<ProductColor>> watchAllColors();
  Stream<List<ProductColor>> watchColorsBySearch(String query);
  Future<List<ProductColor>> getAllColors();
  Future<ProductColor?> getColorById(int id);
  Future<int> createColor(ProductColor color);
  Future<bool> updateColor(ProductColor color);
  Future<void> deleteColor(int id);
  Future<int> getProductCountByColor(int colorId);
  Future<bool> hasProducts(int colorId);
}
