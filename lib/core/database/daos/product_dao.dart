import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';

part 'product_dao.g.dart';

@DriftAccessor(tables: [Products, ProductVariants, ProductCategories, ProductColors, Sizes, ProductBatches])
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  Stream<List<Product>> watchAllProducts() {
    return (select(products)
          ..where((p) => p.isActive.equals(true))
          ..orderBy([(p) => OrderingTerm(expression: p.name)]))
        .watch();
  }

  Stream<Product?> watchProduct(int id) {
    return (select(products)..where((p) => p.id.equals(id))).watchSingleOrNull();
  }

  Future<List<Product>> searchProducts(String query) {
    return (select(products)
          ..where((p) => p.name.like('%$query%') | p.sku.like('%$query%'))
          ..where((p) => p.isActive.equals(true)))
        .get();
  }

  Future<Product?> findBySku(String sku) {
    return (select(products)..where((p) => p.sku.equals(sku))).getSingleOrNull();
  }

  Future<int> createProduct(ProductsCompanion product) {
    return into(products).insert(product);
  }

  Future<bool> updateProduct(Product product) {
    return update(products).replace(product);
  }

  Future<int> deleteProduct(int id) {
    return (delete(products)..where((p) => p.id.equals(id))).go();
  }

  Stream<List<ProductVariant>> watchProductVariants(int productId) {
    return (select(productVariants)
          ..where((v) => v.productId.equals(productId))
          ..where((v) => v.isActive.equals(true)))
        .watch();
  }

  Future<int> createVariant(ProductVariantsCompanion variant) {
    return into(productVariants).insert(variant);
  }

  Stream<List<ProductCategory>> watchCategories() {
    return (select(productCategories)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .watch();
  }
}
