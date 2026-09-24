import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [ProductCategories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Stream<List<ProductCategory>> watchAllCategories() {
    return (select(productCategories)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .watch();
  }

  Stream<List<ProductCategory>> watchCategoriesBySearch(String query) {
    return (select(productCategories)
          ..where((c) => c.isActive.equals(true) & c.name.like('%$query%'))
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .watch();
  }

  Future<List<ProductCategory>> getAllCategories() {
    return (select(productCategories)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .get();
  }

  Future<ProductCategory?> getCategoryById(int id) {
    return (select(
      productCategories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<List<ProductCategory>> getSubcategories(int parentId) {
    return (select(productCategories)
          ..where((c) => c.parentId.equals(parentId) & c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .get();
  }

  Stream<List<ProductCategory>> watchSubcategories(int parentId) {
    return (select(productCategories)
          ..where((c) => c.parentId.equals(parentId) & c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .watch();
  }

  Future<int> createCategory(ProductCategoriesCompanion category) {
    return into(productCategories).insert(category);
  }

  Future<bool> updateCategory(ProductCategory category) {
    return update(productCategories).replace(category);
  }

  Future<int> deleteCategory(int id) {
    return (update(productCategories)..where((c) => c.id.equals(id))).write(
      const ProductCategoriesCompanion(isActive: Value(false)),
    );
  }

  Future<int> getProductCountByCategory(int categoryId) async {
    final query = selectOnly(db.products)
      ..addColumns([db.products.id.count()])
      ..where(
        db.products.categoryId.equals(categoryId) &
            db.products.isActive.equals(true),
      );

    final result = await query.getSingleOrNull();
    return result?.read(db.products.id.count()) ?? 0;
  }

  Future<bool> hasProducts(int categoryId) async {
    final count = await getProductCountByCategory(categoryId);
    return count > 0;
  }

  Future<bool> hasCircularReference(int categoryId, int? parentId) async {
    if (parentId == null) return false;
    if (categoryId == parentId) return true;

    int? currentParentId = parentId;
    final visited = <int>{categoryId};

    while (currentParentId != null) {
      if (visited.contains(currentParentId)) {
        return true;
      }
      visited.add(currentParentId);

      final parent = await getCategoryById(currentParentId);
      currentParentId = parent?.parentId;
    }

    return false;
  }
}
