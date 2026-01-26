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
          ..where((p) => p.name.like('%$query%') | p.sku.like('%$query%') | p.sku.equals(query))
          ..where((p) => p.isActive.equals(true)))
        .get();
  }

  Future<Product?> findBySkuOrBarcode(String code) {
    return (select(products)
          ..where((p) => p.sku.equals(code) | p.barcode.equals(code))
          ..where((p) => p.isActive.equals(true)))
        .getSingleOrNull();
  }

  Future<List<Product>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
  }) {
    final query = select(products)..where((p) => p.isActive.equals(true));

    if (categoryId != null) {
      query.where((p) => p.categoryId.equals(categoryId));
    }

    if (stockStatus != null) {
      if (stockStatus == 'out_of_stock') {
        query.where((p) => p.stockQuantity.equals(0));
      } else if (stockStatus == 'low_stock') {
        query.where((p) => p.stockQuantity.isBiggerThanValue(0) & p.stockQuantity.isSmallerOrEqual(p.minQuantity));
      }
    }

    query
      ..orderBy([(p) => OrderingTerm(expression: p.name)])
      ..limit(limit, offset: offset);

    return query.get();
  }

  Stream<List<Product>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
  }) {
    final query = select(products)..where((p) => p.isActive.equals(true));

    if (categoryId != null) {
      query.where((p) => p.categoryId.equals(categoryId));
    }

    if (stockStatus != null) {
      if (stockStatus == 'out_of_stock') {
        query.where((p) => p.stockQuantity.equals(0));
      } else if (stockStatus == 'low_stock') {
        query.where((p) => p.stockQuantity.isBiggerThanValue(0) & p.stockQuantity.isSmallerOrEqual(p.minQuantity));
      }
    }

    query.orderBy([(p) => OrderingTerm(expression: p.name)]);

    return query.watch();
  }

  Stream<List<Product>> watchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
  }) {
    final query = select(products);

    if (activeOnly) {
      query.where((p) => p.isActive.equals(true));
    }
    if (categoryId != null) {
      query.where((p) => p.categoryId.equals(categoryId));
    }
    if (supplierId != null) {
      query.where((p) => p.supplierId.equals(supplierId));
    }

    query.orderBy([(p) => OrderingTerm(expression: p.name)]);
    return query.watch();
  }

  Future<List<Product>> fetchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
    int limit = 1000,
    int offset = 0,
  }) {
    final query = select(products);

    if (activeOnly) {
      query.where((p) => p.isActive.equals(true));
    }
    if (categoryId != null) {
      query.where((p) => p.categoryId.equals(categoryId));
    }
    if (supplierId != null) {
      query.where((p) => p.supplierId.equals(supplierId));
    }

    query
      ..orderBy([(p) => OrderingTerm(expression: p.name)])
      ..limit(limit, offset: offset);

    return query.get();
  }

  Future<Product?> findBySku(String sku) {
    return (select(products)..where((p) => p.sku.equals(sku))).getSingleOrNull();
  }

  Future<Product?> findByBarcode(String barcode) {
    return (select(products)..where((p) => p.barcode.equals(barcode))).getSingleOrNull();
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

  /// Bulk create products in a single transaction for performance
  /// Returns a map of index to product ID
  Future<Map<int, int>> bulkCreateProducts(List<ProductsCompanion> productList) async {
    final results = <int, int>{};
    
    await db.transaction(() async {
      for (int i = 0; i < productList.length; i++) {
        final id = await into(products).insert(productList[i]);
        results[i] = id;
      }
    });
    
    return results;
  }
}
