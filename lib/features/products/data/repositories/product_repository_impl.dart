import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/price_history_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_local_datasource.dart';
import '../models/product_model.dart';

export '../../domain/repositories/product_repository.dart' show BulkProductData;

class ProductRepositoryImpl implements ProductRepository {
  final ProductLocalDatasource _datasource;

  ProductRepositoryImpl(this._datasource);

  @override
  Stream<List<Product>> watchAllProducts({bool? isActive = true}) {
    return _datasource.watchAllProducts(isActive: isActive);
  }

  @override
  Stream<Product?> watchProduct(int id) {
    return _datasource.watchProduct(id);
  }

  @override
  Future<List<Product>> searchProducts(String query, {bool? isActive = true}) {
    return _datasource.searchProducts(query, isActive: isActive);
  }

  @override
  Future<Product?> findBySku(String sku) {
    return _datasource.findBySku(sku);
  }

  @override
  Future<Product?> findByBarcode(String barcode) {
    return _datasource.findByBarcode(barcode);
  }

  @override
  Future<List<Product>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
    bool? isActive = true,
  }) {
    return _datasource.filterProducts(
      categoryId: categoryId,
      stockStatus: stockStatus,
      limit: limit,
      offset: offset,
      isActive: isActive,
    );
  }

  @override
  Stream<List<Product>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
    bool? isActive = true,
  }) {
    return _datasource.watchFilteredProducts(
      categoryId: categoryId,
      stockStatus: stockStatus,
      isActive: isActive,
    );
  }

  @override
  Stream<List<Product>> watchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
  }) {
    return _datasource.watchProductsForExport(
      categoryId: categoryId,
      supplierId: supplierId,
      activeOnly: activeOnly,
    );
  }

  @override
  Future<List<Product>> fetchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
    int limit = 1000,
    int offset = 0,
  }) {
    return _datasource.fetchProductsForExport(
      categoryId: categoryId,
      supplierId: supplierId,
      activeOnly: activeOnly,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> createProduct({
    required String name,
    String? nameAr,
    String? nameFr,
    String? description,
    String? sku,
    String? barcode,
    required Decimal costCents,
    required Decimal priceCents,
    Decimal? wholesalePriceCents,
    required int stockQuantity,
    required int minQuantity,
    int? categoryId,
    int? supplierId,
    int? currencyId,
    String? imagePath,
    bool hasVariants = false,
    bool isTaxable = false,
    int purchaseTaxRateBps = 0,
    int salesTaxRateBps = 0,
    bool isActive = true,
    bool trackInventory = true,
  }) {
    return _datasource.createProduct(
      db.ProductsCompanion(
        name: Value(name),
        nameAr: Value(nameAr),
        nameFr: Value(nameFr),
        description: Value(description),
        sku: Value(sku),
        barcode: Value(barcode),
        costCents: Value(costCents),
        priceCents: Value(priceCents),
        wholesalePriceCents: Value(wholesalePriceCents),
        stockQuantity: Value(stockQuantity),
        minQuantity: Value(minQuantity),
        categoryId: Value(categoryId),
        supplierId: Value(supplierId),
        currencyId: Value(currencyId ?? 1), 
        imagePath: Value(imagePath),
        hasVariants: Value(hasVariants),
        isTaxable: Value(isTaxable),
        purchaseTaxRateBps: Value(purchaseTaxRateBps),
        salesTaxRateBps: Value(salesTaxRateBps),
        isActive: Value(isActive),
        trackInventory: Value(trackInventory),
      ),
    );
  }

  @override
  Future<bool> updateProduct(Product product) {
    if (product is ProductModel) {
      return _datasource.updateProduct(product);
    } else {
      // Create a ProductModel from the Product entity to ensure we pass the correct type to datasource
      return _datasource.updateProduct(
        ProductModel(
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
          currencyId: product.currencyId,
          imagePath: product.imagePath,
          hasVariants: product.hasVariants,
          isTaxable: product.isTaxable,
          purchaseTaxRateBps: product.purchaseTaxRateBps,
          salesTaxRateBps: product.salesTaxRateBps,
          isActive: product.isActive,
          trackInventory: product.trackInventory,
        ),
      );
    }
  }

  @override
  Future<int> deleteProduct(int id) {
    return _datasource.deleteProduct(id);
  }

  @override
  Future<int> bulkDeleteProducts(List<int> ids) {
    return _datasource.bulkDeleteProducts(ids);
  }

  @override
  Future<int> deactivateProduct(int id) {
    return _datasource.deactivateProduct(id);
  }

  @override
  Future<int> bulkDeactivateProducts(List<int> ids) {
    return _datasource.bulkDeactivateProducts(ids);
  }

  @override
  Future<List<int>> findProductIdsReferencedByOpenPurchases(
    List<int> productIds, {
    Set<String> closedPurchaseStatuses = const {'closed', 'paid', 'completed', 'posted'},
  }) {
    return _datasource.findProductIdsReferencedByOpenPurchases(
      productIds,
      closedPurchaseStatuses: closedPurchaseStatuses,
    );
  }

  @override
  Future<Map<int, int>> bulkCreateProducts(List<BulkProductData> products) {
    final companions = products.map((p) => db.ProductsCompanion(
      name: Value(p.name),
      nameAr: Value(p.nameAr),
      nameFr: Value(p.nameFr),
      sku: Value(p.sku),
      barcode: Value(p.barcode),
      costCents: Value(p.costCents),
      priceCents: Value(p.priceCents),
      wholesalePriceCents: Value(p.wholesalePriceCents),
      stockQuantity: Value(p.stockQuantity),
      minQuantity: Value(p.minQuantity),
      categoryId: Value(p.categoryId),
      supplierId: Value(p.supplierId),
      currencyId: const Value(1),
      hasVariants: Value(p.hasVariants),
      isTaxable: Value(p.isTaxable),
      purchaseTaxRateBps: Value(p.purchaseTaxRateBps),
      salesTaxRateBps: Value(p.salesTaxRateBps),
      isActive: Value(p.isActive),
      trackInventory: Value(p.trackInventory),
    )).toList();

    return _datasource.bulkCreateProducts(companions);
  }

  @override
  Future<void> bulkUpdatePricesWithHistory({
    required List<Product> products,
    required Map<int, Map<String, Decimal>> priceChanges,
    required List<PriceHistory> historyRecords,
  }) async {
    // Convert Product entities to ProductModel for datasource
    final productModels = products.map((p) => ProductModel.fromEntity(p)).toList();
    
    await _datasource.bulkUpdatePricesWithHistory(
      products: productModels,
      priceChanges: priceChanges,
      historyRecords: historyRecords,
    );
  }

  @override
  Future<List<PriceHistory>> getPriceHistory(int productId) {
    return _datasource.getPriceHistory(productId);
  }

  @override
  Future<void> createPriceHistory(PriceHistory history) {
    return _datasource.createPriceHistory(history);
  }
}
