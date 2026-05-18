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
  /// One-shot fetch of a product by primary key. Used by guards that need a
  /// synchronous server-authoritative snapshot (e.g. preserving ledger-
  /// controlled fields like `stockQuantity` and `costCents` across edits).
  Future<Product?> getProductById(int id);
  
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
    String costingMethod = 'wac',
    // Layer 2 of the two-layer inventory architecture. Must be one of
    // 'standard' | 'batch' | 'batch_expiry'. Threaded through create so the
    // user-selected tracking type lands in the initial INSERT rather than
    // falling back to the DB default — the previous omission caused the
    // first-save-loses-selection bug. Layer 1 (`costingMethod`) is kept in
    // sync by the caller for the expand-migrate-contract window.
    String inventoryTrackingType = 'standard',
  });

  Future<bool> updateProduct(Product product);

  /// Returns a non-null reason ('has_stock' or 'has_consumptions') when the
  /// product's costing method is locked, or `null` when it is editable.
  /// See `ProductDao.getCostingMethodLockReason` for full semantics.
  Future<String?> getCostingMethodLockReason(int productId);

  /// Persists a new costing method ('wac' or 'fifo') for [productId].
  /// Refuses the change when the product is locked, returning the lock
  /// reason so the UI can surface a precise message. Returns `null` on
  /// success.
  Future<String?> setCostingMethod({
    required int productId,
    required String method,
  });

  /// Returns the per-product inventory tracking type — Layer 2 of the
  /// two-layer inventory architecture. One of `'standard'` | `'batch'` |
  /// `'batch_expiry'`. Defaults to `'standard'` when the row is missing.
  Future<String> getInventoryTrackingType(int productId);

  /// Persists a new inventory tracking type ('standard' | 'batch' |
  /// 'batch_expiry') for [productId]. Re-uses the same lock semantics as
  /// [setCostingMethod] (locked once stock or batch consumptions exist).
  /// Returns `null` on success or a non-null lock-reason string on refusal.
  Future<String?> setInventoryTrackingType({
    required int productId,
    required String trackingType,
  });
  Future<int> deleteProduct(int id);
  Future<int> bulkDeleteProducts(List<int> ids);

  /// Count how many historical references exist for [productId] across
  /// sale_items / purchase_items / adjustment-return items. Used to drive
  /// the smart-delete decision in the UI before confirming.
  Future<int> countProductReferences(int productId);

  /// Deletes the product if there are no historical references (invoices,
  /// returns, etc.); otherwise deactivates it (soft-delete) — preserving
  /// audit trail in line with QuickBooks/Xero/Odoo behaviour.
  /// Returns whether the row was hard-deleted and the reference count.
  Future<ProductDeletionResult> smartDeleteProduct(int productId);

  /// Atomic "write-off-and-delete" for a product that still carries on-hand
  /// stock. Posts one Shrinkage adjustment per variant with stock>0
  /// (Dr 5800 / Cr 1200), then runs [smartDeleteProduct]. Mirrors the
  /// variant-level helper and keeps Σ(stock×cost) ≡ balance of 1200 in the
  /// general ledger after the row is removed/deactivated.
  Future<ProductDeletionResult> writeOffAndDeleteProduct({
    required int productId,
    required String reason,
  });

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

  /// Runs [action] inside a single DB transaction. Used by the product form
  /// bloc to atomically perform the sequence (update product → ensure default
  /// variant → update variant → optionally deactivate dimensional variants)
  /// so a partial failure never leaves the product and its variants out of
  /// sync — which would corrupt stock totals and journal references.
  Future<T> runInTransaction<T>(Future<T> Function() action);

  /// Per-product batch-expiry health summary. Emits a map keyed by
  /// `productId` covering only products that are tracked as `batch_expiry`
  /// **and** carry on-hand stock with at least one dated batch. Each value
  /// reports the quantity already past expiry and the nearest upcoming
  /// expiry date (or `null` when every remaining batch is expired).
  ///
  /// Drives the product list near-expiry / expired badges (Phase C) and
  /// will be re-used by the Phase E expiry alert dashboard.
  Stream<Map<int, ({int expiredQty, DateTime? nextExpiry})>>
      watchExpirySummaries();
}

/// Result of a smart-delete attempt: either the product was hard-deleted
/// (no historical references) or it was deactivated because it is referenced
/// by invoices / returns and must be kept for audit / accounting integrity.
class ProductDeletionResult {
  final bool wasDeleted;
  final int referenceCount;
  const ProductDeletionResult({
    required this.wasDeleted,
    required this.referenceCount,
  });
  bool get wasDeactivated => !wasDeleted;
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
