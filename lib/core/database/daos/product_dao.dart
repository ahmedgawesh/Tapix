import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/transactions.dart';

part 'product_dao.g.dart';

@DriftAccessor(tables: [
  Products,
  ProductVariants,
  ProductCategories,
  ProductColors,
  Sizes,
  ProductBatches,
  Purchases,
  PurchaseItems,
])
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  Stream<List<Product>> watchAllProducts({bool? isActive = true}) {
    final query = select(products);
    if (isActive != null) {
      query.where((p) => p.isActive.equals(isActive));
    }
    query.orderBy([(p) => OrderingTerm(expression: p.name)]);
    return query.watch();
  }

  Stream<Product?> watchProduct(int id) {
    return (select(products)..where((p) => p.id.equals(id))).watchSingleOrNull();
  }

  Future<List<Product>> searchProducts(String query, {bool? isActive = true}) {
    final q = select(products)
      ..where((p) => p.name.like('%$query%') | p.sku.like('%$query%') | p.sku.equals(query));
    if (isActive != null) {
      q.where((p) => p.isActive.equals(isActive));
    }
    return q.get();
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
    bool? isActive = true,
    int lowStockThreshold = 5,
  }) {
    if (stockStatus == null) {
      final query = select(products);

      if (isActive != null) {
        query.where((p) => p.isActive.equals(isActive));
      }

      if (categoryId != null) {
        query.where((p) => p.categoryId.equals(categoryId));
      }

      query
        ..orderBy([(p) => OrderingTerm(expression: p.name)])
        ..limit(limit, offset: offset);

      return query.get();
    }

    final where = StringBuffer('WHERE 1=1');
    final vars = <Variable<Object>>[];

    if (isActive != null) {
      where.write(' AND p.is_active = ?');
      vars.add(Variable.withInt(isActive ? 1 : 0));
    }
    if (categoryId != null) {
      where.write(' AND p.category_id = ?');
      vars.add(Variable.withInt(categoryId));
    }

    if (stockStatus == 'out_of_stock') {
      where.write(
        ' AND ((p.has_variants = 0 AND p.stock_quantity = 0) OR (p.has_variants = 1 AND NOT EXISTS (SELECT 1 FROM product_variants v WHERE v.product_id = p.id AND v.is_active = 1 AND v.stock_quantity > 0)))',
      );
    } else if (stockStatus == 'low_stock') {
      where.write(
        ' AND ((p.has_variants = 0 AND p.stock_quantity > 0 AND p.stock_quantity <= CASE WHEN p.min_quantity > 0 THEN p.min_quantity ELSE ? END) OR (p.has_variants = 1 AND EXISTS (SELECT 1 FROM product_variants v WHERE v.product_id = p.id AND v.is_active = 1 AND v.stock_quantity > 0 AND v.stock_quantity <= CASE WHEN p.min_quantity > 0 THEN p.min_quantity ELSE ? END)))',
      );
      vars.add(Variable.withInt(lowStockThreshold));
      vars.add(Variable.withInt(lowStockThreshold));
    }

    where.write(' ORDER BY p.name LIMIT ? OFFSET ?');
    vars.add(Variable.withInt(limit));
    vars.add(Variable.withInt(offset));

    return customSelect(
      'SELECT p.* FROM products p ${where.toString()}',
      variables: vars,
      readsFrom: {products, productVariants},
    ).map((row) => products.map(row.data)).get();
  }

  Stream<List<Product>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
    bool? isActive = true,
    int lowStockThreshold = 5,
  }) {
    if (stockStatus == null) {
      final query = select(products);

      if (isActive != null) {
        query.where((p) => p.isActive.equals(isActive));
      }

      if (categoryId != null) {
        query.where((p) => p.categoryId.equals(categoryId));
      }

      query.orderBy([(p) => OrderingTerm(expression: p.name)]);

      return query.watch();
    }

    final where = StringBuffer('WHERE 1=1');
    final vars = <Variable<Object>>[];

    if (isActive != null) {
      where.write(' AND p.is_active = ?');
      vars.add(Variable.withInt(isActive ? 1 : 0));
    }
    if (categoryId != null) {
      where.write(' AND p.category_id = ?');
      vars.add(Variable.withInt(categoryId));
    }

    if (stockStatus == 'out_of_stock') {
      where.write(
        ' AND ((p.has_variants = 0 AND p.stock_quantity = 0) OR (p.has_variants = 1 AND NOT EXISTS (SELECT 1 FROM product_variants v WHERE v.product_id = p.id AND v.is_active = 1 AND v.stock_quantity > 0)))',
      );
    } else if (stockStatus == 'low_stock') {
      where.write(
        ' AND ((p.has_variants = 0 AND p.stock_quantity > 0 AND p.stock_quantity <= CASE WHEN p.min_quantity > 0 THEN p.min_quantity ELSE ? END) OR (p.has_variants = 1 AND EXISTS (SELECT 1 FROM product_variants v WHERE v.product_id = p.id AND v.is_active = 1 AND v.stock_quantity > 0 AND v.stock_quantity <= CASE WHEN p.min_quantity > 0 THEN p.min_quantity ELSE ? END)))',
      );
      vars.add(Variable.withInt(lowStockThreshold));
      vars.add(Variable.withInt(lowStockThreshold));
    }

    where.write(' ORDER BY p.name');

    return customSelect(
      'SELECT p.* FROM products p ${where.toString()}',
      variables: vars,
      readsFrom: {products, productVariants},
    ).map((row) => products.map(row.data)).watch();
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

  Future<Product?> findByName(String name) {
    return (select(products)..where((p) => p.name.equals(name))).getSingleOrNull();
  }

  Future<int> createProduct(ProductsCompanion product) {
    return into(products).insert(product);
  }

  Future<bool> updateProduct(Product product) {
    return transaction(() async {
      final ok = await update(products).replace(product);

      await customUpdate(
        'UPDATE product_variants SET is_active = ? WHERE product_id = ?',
        variables: [
          Variable.withInt(product.isActive ? 1 : 0),
          Variable.withInt(product.id),
        ],
        updates: {productVariants},
      );

      return ok;
    });
  }

  Future<int> deleteProduct(int id) {
    return (delete(products)..where((p) => p.id.equals(id))).go();
  }

  Future<int> bulkDeleteProducts(List<int> ids) {
    if (ids.isEmpty) return Future.value(0);
    return (delete(products)..where((p) => p.id.isIn(ids))).go();
  }

  Future<int> deactivateProduct(int id) {
    return (update(products)..where((p) => p.id.equals(id))).write(
      const ProductsCompanion(
        isActive: Value(false),
      ),
    );
  }

  Future<int> bulkDeactivateProducts(List<int> ids) {
    if (ids.isEmpty) return Future.value(0);
    return (update(products)..where((p) => p.id.isIn(ids))).write(
      const ProductsCompanion(
        isActive: Value(false),
      ),
    );
  }

  Future<List<int>> findProductIdsReferencedByOpenPurchases(
    List<int> productIds, {
    Set<String> closedPurchaseStatuses = const {'closed', 'paid', 'completed', 'posted'},
  }) async {
    if (productIds.isEmpty) return const [];

    final purchases = db.purchases;
    final purchaseItems = db.purchaseItems;

    final query = selectOnly(purchaseItems, distinct: true)
      ..addColumns([purchaseItems.productId])
      ..join([
        innerJoin(
          purchases,
          purchases.id.equalsExp(purchaseItems.purchaseId),
        ),
      ])
      ..where(purchaseItems.productId.isIn(productIds));
    query.where(purchases.status.isNotIn(closedPurchaseStatuses.toList()));

    final rows = await query.get();
    return rows
        .map((r) => r.read(purchaseItems.productId))
        .whereType<int>()
        .toList();
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
