import '../entities/category_entity.dart';

abstract class CategoryRepository {
  Stream<List<Category>> watchAllCategories();
  Stream<List<Category>> watchCategoriesBySearch(String query);
  Future<List<Category>> getAllCategories();
  Future<Category?> getCategoryById(int id);
  Future<List<Category>> getSubcategories(int parentId);
  Stream<List<Category>> watchSubcategories(int parentId);
  Future<int> createCategory(Category category);
  Future<bool> updateCategory(Category category);
  Future<void> deleteCategory(int id);
  Future<int> getProductCountByCategory(int categoryId);
  Future<bool> hasProducts(int categoryId);
  Future<bool> hasCircularReference(int categoryId, int? parentId);
}
