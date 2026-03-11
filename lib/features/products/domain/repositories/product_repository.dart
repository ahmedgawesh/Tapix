import 'package:decimal/decimal.dart';
import '../entities/product_entity.dart';
import '../entities/price_history_entity.dart';

abstract class ProductRepository {
  Stream<List<Product>> watchAllProducts({bool? isActive = true});
  Stream<Product?> watchProduct(int id);
  Future<List<Product>> searchProducts(String query, {bool? isActive = true});
  Future<Product?> findBySku(String sku);
  Future<Product?> findByBarcode(String barcode);
  Future<Product?> findByName(String name);
  
  Future<List<Product>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
    bool? isActive = true,
    int lowStockThreshold = 5,
  });

  Stream<List<Product>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
    bool? isActive = true,
    int lowStockThreshold = 5,
  });

  Stream<List<Product>> watchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
  });

  Future<List<Product>> fetchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
    int limit = 1000,
    int offset = 0,
  });

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
  });

  Future<bool> updateProduct(Product product);
  Future<int> deleteProduct(int id);
  Future<int> bulkDeleteProducts(List<int> ids);

  Future<int> deactivateProduct(int id);
  Future<int> bulkDeactivateProducts(List<int> ids);

  Future<List<int>> findProductIdsReferencedByOpenPurchases(
    List<int> productIds, {
    Set<String> closedPurchaseStatuses,
  });

  /// Bulk create products in a single transaction for performance and consistency
  /// Returns a map of row index to product ID for successful inserts
  /// Throws exception on failure with rollback
  Future<Map<int, int>> bulkCreateProducts(List<BulkProductData> products);

  /// Bulk update prices with history tracking in a single transaction
  Future<void> bulkUpdatePricesWithHistory({
    required List<Product> products,
    required Map<int, Map<String, Decimal>> priceChanges,
    required List<PriceHistory> historyRecords,
  });

  /// Get price history for a product
  Future<List<PriceHistory>> getPriceHistory(int productId);

  /// Create a price history record
  Future<void> createPriceHistory(PriceHistory history);
}

/// Data class for bulk product creation
class BulkProductData {
  final int rowIndex;
  final String name;
  final String? nameAr;
  final String? nameFr;
  final String? sku;
  final String? barcode;
  final Decimal costCents;
  final Decimal priceCents;
  final Decimal? wholesalePriceCents;
  final int stockQuantity;
  final int minQuantity;
  final int? categoryId;
  final int? supplierId;
  final bool hasVariants;
  final bool isTaxable;
  final int purchaseTaxRateBps;
  final int salesTaxRateBps;
  final bool isActive;
  final bool trackInventory;

  const BulkProductData({
    required this.rowIndex,
    required this.name,
    this.nameAr,
    this.nameFr,
    this.sku,
    this.barcode,
    required this.costCents,
    required this.priceCents,
    this.wholesalePriceCents,
    this.stockQuantity = 0,
    this.minQuantity = 0,
    this.categoryId,
    this.supplierId,
    this.hasVariants = false,
    this.isTaxable = false,
    this.purchaseTaxRateBps = 0,
    this.salesTaxRateBps = 0,
    this.isActive = true,
    this.trackInventory = true,
  });
}
