import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../models/category_model.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  final AppDatabase _database;

  CategoryRepositoryImpl(this._database);

  @override
  Stream<List<Category>> watchAllCategories() {
    return _database.categoryDao.watchAllCategories().map(
      (categories) =>
          categories.map((cat) => CategoryModel.fromDrift(cat)).toList(),
    );
  }

  @override
  Stream<List<Category>> watchCategoriesBySearch(String query) {
    return _database.categoryDao
        .watchCategoriesBySearch(query)
        .map(
          (categories) =>
              categories.map((cat) => CategoryModel.fromDrift(cat)).toList(),
        );
  }

  @override
  Future<List<Category>> getAllCategories() async {
    final categories = await _database.categoryDao.getAllCategories();
    return categories.map((cat) => CategoryModel.fromDrift(cat)).toList();
  }

  @override
  Future<Category?> getCategoryById(int id) async {
    final category = await _database.categoryDao.getCategoryById(id);
    return category != null ? CategoryModel.fromDrift(category) : null;
  }

  @override
  Future<List<Category>> getSubcategories(int parentId) async {
    final categories = await _database.categoryDao.getSubcategories(parentId);
    return categories.map((cat) => CategoryModel.fromDrift(cat)).toList();
  }

  @override
  Stream<List<Category>> watchSubcategories(int parentId) {
    return _database.categoryDao
        .watchSubcategories(parentId)
        .map(
          (categories) =>
              categories.map((cat) => CategoryModel.fromDrift(cat)).toList(),
        );
  }

  @override
  Future<int> createCategory(Category category) async {
    final model = category as CategoryModel;
    return await _database.categoryDao.createCategory(
      model.toInsertCompanion(),
    );
  }

  @override
  Future<bool> updateCategory(Category category) async {
    final driftCategory = await _database.categoryDao.getCategoryById(
      category.id,
    );
    if (driftCategory == null) return false;

    final updatedCategory = driftCategory.copyWith(
      name: category.name,
      description: Value(category.description),
      parentId: Value(category.parentId),
      isActive: category.isActive,
      updatedAt: DateTime.now(),
    );

    return await _database.categoryDao.updateCategory(updatedCategory);
  }

  @override
  Future<void> deleteCategory(int id) async {
    await _database.categoryDao.deleteCategory(id);
  }

  @override
  Future<int> getProductCountByCategory(int categoryId) {
    return _database.categoryDao.getProductCountByCategory(categoryId);
  }

  @override
  Future<bool> hasProducts(int categoryId) {
    return _database.categoryDao.hasProducts(categoryId);
  }

  @override
  Future<bool> hasCircularReference(int categoryId, int? parentId) {
    return _database.categoryDao.hasCircularReference(categoryId, parentId);
  }
}
