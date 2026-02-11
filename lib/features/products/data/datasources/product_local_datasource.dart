import 'package:decimal/decimal.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/product_dao.dart';
import '../../domain/entities/price_history_entity.dart';
import '../models/product_model.dart';

abstract class ProductLocalDatasource {
  Stream<List<ProductModel>> watchAllProducts({bool? isActive = true});
  Stream<ProductModel?> watchProduct(int id);
  Future<List<ProductModel>> searchProducts(String query, {bool? isActive = true});
  Future<ProductModel?> findBySku(String sku);
  Future<ProductModel?> findByBarcode(String barcode);
  
  Future<List<ProductModel>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
    bool? isActive = true,
  });

  Stream<List<ProductModel>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
    bool? isActive = true,
  });

  Stream<List<ProductModel>> watchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
  });

  Future<List<ProductModel>> fetchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
    int limit = 1000,
    int offset = 0,
  });

  Future<int> createProduct(db.ProductsCompanion product);
  Future<bool> updateProduct(ProductModel product);
  Future<int> deleteProduct(int id);
  Future<int> bulkDeleteProducts(List<int> ids);

  Future<int> deactivateProduct(int id);
  Future<int> bulkDeactivateProducts(List<int> ids);

  Future<List<int>> findProductIdsReferencedByOpenPurchases(
    List<int> productIds, {
    Set<String> closedPurchaseStatuses,
  });

  /// Bulk create products in a single transaction
  Future<Map<int, int>> bulkCreateProducts(List<db.ProductsCompanion> products);

  /// Bulk update prices with history tracking in a single transaction
  Future<void> bulkUpdatePricesWithHistory({
    required List<ProductModel> products,
    required Map<int, Map<String, Decimal>> priceChanges,
    required List<PriceHistory> historyRecords,
  });

  /// Get price history for a product
  Future<List<PriceHistory>> getPriceHistory(int productId);

  /// Create a price history record
  Future<void> createPriceHistory(PriceHistory history);
}

class ProductLocalDatasourceImpl implements ProductLocalDatasource {
  final ProductDao _productDao;

  ProductLocalDatasourceImpl(this._productDao);

  @override
  Stream<List<ProductModel>> watchAllProducts({bool? isActive = true}) {
    return _productDao.watchAllProducts(isActive: isActive).map(
          (products) => products.map((p) => ProductModel.fromDrift(p)).toList(),
        );
  }

  @override
  Stream<ProductModel?> watchProduct(int id) {
    return _productDao.watchProduct(id).map(
          (p) => p == null ? null : ProductModel.fromDrift(p),
        );
  }

  @override
  Future<List<ProductModel>> searchProducts(String query, {bool? isActive = true}) async {
    final products = await _productDao.searchProducts(query, isActive: isActive);
    return products.map((p) => ProductModel.fromDrift(p)).toList();
  }

  @override
  Future<ProductModel?> findBySku(String sku) async {
    final product = await _productDao.findBySku(sku);
    return product == null ? null : ProductModel.fromDrift(product);
  }

  @override
  Future<ProductModel?> findByBarcode(String barcode) async {
    final product = await _productDao.findByBarcode(barcode);
    return product == null ? null : ProductModel.fromDrift(product);
  }

  @override
  Future<List<ProductModel>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
    bool? isActive = true,
  }) async {
    final products = await _productDao.filterProducts(
      categoryId: categoryId,
      stockStatus: stockStatus,
      limit: limit,
      offset: offset,
      isActive: isActive,
    );
    return products.map((p) => ProductModel.fromDrift(p)).toList();
  }

  @override
  Stream<List<ProductModel>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
    bool? isActive = true,
  }) {
    return _productDao
        .watchFilteredProducts(
          categoryId: categoryId,
          stockStatus: stockStatus,
          isActive: isActive,
        )
        .map((products) => products.map((p) => ProductModel.fromDrift(p)).toList());
  }

  @override
  Stream<List<ProductModel>> watchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
  }) {
    return _productDao
        .watchProductsForExport(
          categoryId: categoryId,
          supplierId: supplierId,
          activeOnly: activeOnly,
        )
        .map((products) => products.map((p) => ProductModel.fromDrift(p)).toList());
  }

  @override
  Future<List<ProductModel>> fetchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
    int limit = 1000,
    int offset = 0,
  }) async {
    final products = await _productDao.fetchProductsForExport(
      categoryId: categoryId,
      supplierId: supplierId,
      activeOnly: activeOnly,
      limit: limit,
      offset: offset,
    );
    return products.map((p) => ProductModel.fromDrift(p)).toList();
  }

  @override
  Future<int> createProduct(db.ProductsCompanion product) {
    return _productDao.createProduct(product);
  }

  @override
  Future<bool> updateProduct(ProductModel product) {
    return _productDao.updateProduct(
       db.Product(
         id: product.id,
         name: product.name,
         nameAr: product.nameAr,
         nameFr: product.nameFr,
         description: product.description,
         sku: product.sku,
         barcode: product.barcode,
         costCents: product.costCents,
         priceCents: product.priceCents,
         wholesalePriceCents: product.wholesalePriceCents,
         stockQuantity: product.stockQuantity,
         minQuantity: product.minQuantity,
         categoryId: product.categoryId,
         supplierId: product.supplierId,
         currencyId: product.currencyId ?? 1,
         imagePath: product.imagePath,
         hasVariants: product.hasVariants,
         isTaxable: product.isTaxable,
         purchaseTaxRateBps: product.purchaseTaxRateBps,
         salesTaxRateBps: product.salesTaxRateBps,
         isActive: product.isActive,
         trackInventory: product.trackInventory,
         createdAt: DateTime.now(),
         updatedAt: DateTime.now(),
       )
    );
  }

  @override
  Future<int> deleteProduct(int id) {
    return _productDao.deleteProduct(id);
  }

  @override
  Future<int> bulkDeleteProducts(List<int> ids) {
    return _productDao.bulkDeleteProducts(ids);
  }

  @override
  Future<int> deactivateProduct(int id) {
    return _productDao.deactivateProduct(id);
  }

  @override
  Future<int> bulkDeactivateProducts(List<int> ids) {
    return _productDao.bulkDeactivateProducts(ids);
  }

  @override
  Future<List<int>> findProductIdsReferencedByOpenPurchases(
    List<int> productIds, {
    Set<String> closedPurchaseStatuses = const {'closed', 'paid', 'completed', 'posted'},
  }) {
    return _productDao.findProductIdsReferencedByOpenPurchases(
      productIds,
      closedPurchaseStatuses: closedPurchaseStatuses,
    );
  }

  @override
  Future<Map<int, int>> bulkCreateProducts(List<db.ProductsCompanion> products) {
    return _productDao.bulkCreateProducts(products);
  }

  @override
  Future<void> bulkUpdatePricesWithHistory({
    required List<ProductModel> products,
    required Map<int, Map<String, Decimal>> priceChanges,
    required List<PriceHistory> historyRecords,
  }) async {
    // Note: This is a placeholder implementation
    // The actual implementation would require price_history table in database
    // For now, just update the products
    for (final entry in priceChanges.entries) {
      final productId = entry.key;
      final changes = entry.value;
      
      final product = products.firstWhere((p) => p.id == productId);
      ProductModel updatedProduct = product;
      
      if (changes.containsKey('priceCents')) {
        updatedProduct = ProductModel(
          id: updatedProduct.id,
          name: updatedProduct.name,
          nameAr: updatedProduct.nameAr,
          nameFr: updatedProduct.nameFr,
          description: updatedProduct.description,
          sku: updatedProduct.sku,
          barcode: updatedProduct.barcode,
          costCents: updatedProduct.costCents,
          priceCents: changes['priceCents']!,
          wholesalePriceCents: updatedProduct.wholesalePriceCents,
          stockQuantity: updatedProduct.stockQuantity,
          minQuantity: updatedProduct.minQuantity,
          categoryId: updatedProduct.categoryId,
          supplierId: updatedProduct.supplierId,
          currencyId: updatedProduct.currencyId,
          imagePath: updatedProduct.imagePath,
          hasVariants: updatedProduct.hasVariants,
          isTaxable: updatedProduct.isTaxable,
          purchaseTaxRateBps: updatedProduct.purchaseTaxRateBps,
          salesTaxRateBps: updatedProduct.salesTaxRateBps,
          isActive: updatedProduct.isActive,
          trackInventory: updatedProduct.trackInventory,
        );
      }
      if (changes.containsKey('wholesalePriceCents')) {
        updatedProduct = ProductModel(
          id: updatedProduct.id,
          name: updatedProduct.name,
          nameAr: updatedProduct.nameAr,
          nameFr: updatedProduct.nameFr,
          description: updatedProduct.description,
          sku: updatedProduct.sku,
          barcode: updatedProduct.barcode,
          costCents: updatedProduct.costCents,
          priceCents: updatedProduct.priceCents,
          wholesalePriceCents: changes['wholesalePriceCents']!,
          stockQuantity: updatedProduct.stockQuantity,
          minQuantity: updatedProduct.minQuantity,
          categoryId: updatedProduct.categoryId,
          supplierId: updatedProduct.supplierId,
          currencyId: updatedProduct.currencyId,
          imagePath: updatedProduct.imagePath,
          hasVariants: updatedProduct.hasVariants,
          isTaxable: updatedProduct.isTaxable,
          purchaseTaxRateBps: updatedProduct.purchaseTaxRateBps,
          salesTaxRateBps: updatedProduct.salesTaxRateBps,
          isActive: updatedProduct.isActive,
          trackInventory: updatedProduct.trackInventory,
        );
      }
      
      await updateProduct(updatedProduct);
    }
  }

  @override
  Future<List<PriceHistory>> getPriceHistory(int productId) async {
    // Placeholder: price_history table not yet implemented
    return [];
  }

  @override
  Future<void> createPriceHistory(PriceHistory history) async {
    // Placeholder: price_history table not yet implemented
  }
}
