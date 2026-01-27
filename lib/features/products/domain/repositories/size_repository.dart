import '../entities/size_entity.dart';

abstract class SizeRepository {
  Stream<List<Size>> watchAllSizes();
  Stream<List<Size>> watchSizesBySearch(String query);
  Future<List<Size>> getAllSizes();
  Future<Size?> getSizeById(int id);
  Future<int> createSize(Size size);
  Future<bool> updateSize(Size size);
  Future<int> deleteSize(int id);
  Future<bool> hasProducts(int sizeId);
  Future<int> getProductCountBySize(int sizeId);
}
