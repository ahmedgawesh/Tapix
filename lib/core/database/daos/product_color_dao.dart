import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';

part 'product_color_dao.g.dart';

@DriftAccessor(tables: [ProductColors])
class ProductColorDao extends DatabaseAccessor<AppDatabase>
    with _$ProductColorDaoMixin {
  ProductColorDao(super.db);

  Stream<List<ProductColor>> watchAllColors() {
    return (select(
      productColors,
    )..orderBy([(c) => OrderingTerm(expression: c.name)])).watch();
  }

  Future<List<ProductColor>> getAllColors() {
    return (select(
      productColors,
    )..orderBy([(c) => OrderingTerm(expression: c.name)])).get();
  }

  Future<ProductColor?> getColorById(int id) {
    return (select(
      productColors,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<int> createColor(ProductColorsCompanion color) {
    return into(productColors).insert(color);
  }

  Future<bool> updateColor(ProductColor color) {
    return update(productColors).replace(color);
  }

  Future<int> deleteColor(int id) {
    return (delete(productColors)..where((c) => c.id.equals(id))).go();
  }
}
