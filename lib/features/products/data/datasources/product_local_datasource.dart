import 'package:decimal/decimal.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/product_dao.dart';
import '../../../../core/services/price_history_service.dart';
import '../../domain/entities/price_history_entity.dart';
import '../models/product_model.dart';

abstract class ProductLocalDatasource {
  Stream<List<ProductModel>> watchAllProducts({bool? isActive = true});
  Stream<ProductModel?> watchProduct(int id);
  Future<List<ProductModel>> searchProducts(
    String query, {
    bool? isActive = true,
  });
  Future<ProductModel?> findBySku(String sku);
  Future<ProductModel?> findByBarcode(String barcode);
  Future<ProductModel?> findByName(String name);
  Future<ProductModel?> getProductById(int id);

  Future<List<ProductModel>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
    bool? isActive = true,
    int lowStockThreshold = 5,
  });

  Stream<List<ProductModel>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
    bool? isActive = true,
    int lowStockThreshold = 5,
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

  /// See [ProductDao.getCostingMethodLockReason].
  Future<String?> getCostingMethodLockReason(int productId);

  /// See [ProductDao.setCostingMethod]. Returns `null` on success or a
  /// non-null lock-reason string on refusal.
  Future<String?> setCostingMethod({
    required int productId,
    required String method,
  });

  /// See [ProductDao.getInventoryTrackingType].
  Future<String> getInventoryTrackingType(int productId);

  /// See [ProductDao.setInventoryTrackingType]. Returns `null` on success or
  /// a non-null lock-reason string on refusal.
  Future<String?> setInventoryTrackingType({
    required int productId,
    required String trackingType,
  });
  Future<String?> setMeasurementType({
    required int productId,
    required String measurementType,
  });
  Future<String?> setTrackInventory({
    required int productId,
    required bool trackInventory,
  });
  Future<int> deleteProduct(int id);
  Future<int> bulkDeleteProducts(List<int> ids);

  Future<int> countProductReferences(int productId);
  Future<({bool wasDeleted, int referenceCount})> smartDeleteProduct(
    int productId,
  );

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

  /// See [ProductDao.watchExpirySummaries]. Streams per-product expiry
  /// status (expired qty + next non-expired date) for products tracked as
  /// `batch_expiry` only. Drives the product list near-expiry badges and
  /// will be re-used by the Phase E expiry alert dashboard.
  Stream<Map<int, ({int expiredQty, DateTime? nextExpiry})>>
  watchExpirySummaries();

  /// Runs [action] inside a single Drift transaction.
  Future<T> runInTransaction<T>(Future<T> Function() action);
}

class ProductLocalDatasourceImpl implements ProductLocalDatasource {
  final ProductDao _productDao;

  ProductLocalDatasourceImpl(this._productDao);

  @override
  Stream<List<ProductModel>> watchAllProducts({bool? isActive = true}) {
    return _productDao
        .watchAllProducts(isActive: isActive)
        .map(
          (products) => products.map((p) => ProductModel.fromDrift(p)).toList(),
        );
  }

  @override
  Stream<ProductModel?> watchProduct(int id) {
    return _productDao
        .watchProduct(id)
        .map((p) => p == null ? null : ProductModel.fromDrift(p));
  }

  @override
  Future<List<ProductModel>> searchProducts(
    String query, {
    bool? isActive = true,
  }) async {
    final products = await _productDao.searchProducts(
      query,
      isActive: isActive,
    );
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
  Future<ProductModel?> findByName(String name) async {
    final product = await _productDao.findByName(name);
    return product == null ? null : ProductModel.fromDrift(product);
  }

  @override
  Future<ProductModel?> getProductById(int id) async {
    final product = await _productDao.getProductById(id);
    return product == null ? null : ProductModel.fromDrift(product);
  }

  @override
  Future<List<ProductModel>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
    bool? isActive = true,
    int lowStockThreshold = 5,
  }) async {
    final products = await _productDao.filterProducts(
      categoryId: categoryId,
      stockStatus: stockStatus,
      limit: limit,
      offset: offset,
      isActive: isActive,
      lowStockThreshold: lowStockThreshold,
    );
    return products.map((p) => ProductModel.fromDrift(p)).toList();
  }

  @override
  Stream<List<ProductModel>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
    bool? isActive = true,
    int lowStockThreshold = 5,
  }) {
    return _productDao
        .watchFilteredProducts(
          categoryId: categoryId,
          stockStatus: stockStatus,
          isActive: isActive,
          lowStockThreshold: lowStockThreshold,
        )
        .map(
          (products) => products.map((p) => ProductModel.fromDrift(p)).toList(),
        );
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
        .map(
          (products) => products.map((p) => ProductModel.fromDrift(p)).toList(),
        );
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
  Future<bool> updateProduct(ProductModel product) async {
    return _productDao.runInTransaction(() async {
      // Preserve createdAt and — as in the variant path — forbid manual edits
      // to stock_quantity / cost_cents via this route. Those must go through
      // InventoryAdjustmentService so the general ledger stays reconciled.
      final existing = await _productDao.getProductById(product.id);
      final int safeStock = existing?.stockQuantity ?? product.stockQuantity;
      final Decimal safeCost = existing?.costCents ?? product.costCents;

      final updated = db.Product(
        id: product.id,
        name: product.name,
        nameAr: product.nameAr,
        nameFr: product.nameFr,
        description: product.description,
        sku: product.sku,
        barcode: product.barcode,
        costCents: safeCost,
        priceCents: product.priceCents,
        wholesalePriceCents: product.wholesalePriceCents,
        // Supplier reference price (gross of trade discounts) — managed by
        // purchase posting via `purchase_dao.postPurchase`. Preserved here
        // so a generic product update (rename, recategorise, taxability
        // toggle, etc.) cannot silently clobber it back to NULL.
        lastPurchasePriceCents: existing?.lastPurchasePriceCents,
        stockQuantity: safeStock,
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
        // These fields alter the meaning/existence of the stock ledger and
        // may only change through their lock-checked DAO setters below.
        trackInventory: existing?.trackInventory ?? product.trackInventory,
        measurementType: existing?.measurementType ?? product.measurementType,
        // costing_method is product-level configuration that should never
        // be silently flipped by a generic update path — preserve the
        // existing value (or fall back to the system default 'wac').
        costingMethod: existing?.costingMethod ?? 'wac',
        // inventory_tracking_type — same rule. Phase B (two-layer
        // architecture): preserve the existing value, default 'standard'
        // for fresh rows.
        inventoryTrackingType: existing?.inventoryTrackingType ?? 'standard',
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final ok = await _productDao.updateProduct(updated);
      if (ok && existing != null) {
        await PriceHistoryService.recordIfChanged(
          _productDao,
          productId: product.id,
          oldCostCents: existing.costCents.toBigInt().toInt(),
          newCostCents: safeCost.toBigInt().toInt(),
          oldPriceCents: existing.priceCents.toBigInt().toInt(),
          newPriceCents: updated.priceCents.toBigInt().toInt(),
          oldWholesalePriceCents: existing.wholesalePriceCents
              ?.toBigInt()
              .toInt(),
          newWholesalePriceCents: updated.wholesalePriceCents
              ?.toBigInt()
              .toInt(),
          changeReason: 'product_update',
        );
      }
      return ok;
    });
  }

  @override
  Future<String?> getCostingMethodLockReason(int productId) {
    return _productDao.getCostingMethodLockReason(productId);
  }

  @override
  Future<String?> setCostingMethod({
    required int productId,
    required String method,
  }) {
    return _productDao.setCostingMethod(productId: productId, method: method);
  }

  @override
  Future<String> getInventoryTrackingType(int productId) {
    return _productDao.getInventoryTrackingType(productId);
  }

  @override
  Future<String?> setInventoryTrackingType({
    required int productId,
    required String trackingType,
  }) {
    return _productDao.setInventoryTrackingType(
      productId: productId,
      trackingType: trackingType,
    );
  }

  @override
  Future<String?> setMeasurementType({
    required int productId,
    required String measurementType,
  }) {
    return _productDao.setMeasurementType(
      productId: productId,
      measurementType: measurementType,
    );
  }

  @override
  Future<String?> setTrackInventory({
    required int productId,
    required bool trackInventory,
  }) {
    return _productDao.setTrackInventory(
      productId: productId,
      trackInventory: trackInventory,
    );
  }

  @override
  Future<int> deleteProduct(int id) {
    return _productDao.deleteProduct(id);
  }

  @override
  Future<int> countProductReferences(int productId) {
    return _productDao.countProductReferences(productId);
  }

  @override
  Future<({bool wasDeleted, int referenceCount})> smartDeleteProduct(
    int productId,
  ) {
    return _productDao.smartDeleteProduct(productId);
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
    Set<String> closedPurchaseStatuses = const {
      'closed',
      'paid',
      'completed',
      'posted',
    },
  }) {
    return _productDao.findProductIdsReferencedByOpenPurchases(
      productIds,
      closedPurchaseStatuses: closedPurchaseStatuses,
    );
  }

  @override
  Future<Map<int, int>> bulkCreateProducts(
    List<db.ProductsCompanion> products,
  ) {
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
    final rows = await _productDao.getPriceHistoryForProduct(productId);
    return rows
        .map(
          (r) => PriceHistory(
            id: r.id,
            productId: r.productId,
            variantId: r.variantId,
            oldCostCents: r.oldCostCents.toBigInt().toInt(),
            newCostCents: r.newCostCents.toBigInt().toInt(),
            oldPriceCents: r.oldPriceCents.toBigInt().toInt(),
            newPriceCents: r.newPriceCents.toBigInt().toInt(),
            oldWholesalePriceCents: r.oldWholesalePriceCents
                ?.toBigInt()
                .toInt(),
            newWholesalePriceCents: r.newWholesalePriceCents
                ?.toBigInt()
                .toInt(),
            userId: r.userId ?? 0,
            changeReason: r.changeReason,
            createdAt: r.createdAt,
          ),
        )
        .toList();
  }

  @override
  Future<void> createPriceHistory(PriceHistory history) async {
    // Funnel through the single sanctioned writer so the manual product-form
    // edits, purchase-posting WAC/last-cost mutations, and inventory
    // revaluations all share one append path. This guarantees the in-app
    // "price history" surface stays the single source of truth — no scattered
    // writers, no parallel histories.
    await PriceHistoryService.recordIfChanged(
      _productDao,
      productId: history.productId,
      variantId: history.variantId,
      oldCostCents: history.oldCostCents,
      newCostCents: history.newCostCents,
      oldPriceCents: history.oldPriceCents,
      newPriceCents: history.newPriceCents,
      oldWholesalePriceCents: history.oldWholesalePriceCents,
      newWholesalePriceCents: history.newWholesalePriceCents,
      userId: history.userId == 0 ? null : history.userId,
      changeReason: history.changeReason,
    );
  }

  @override
  Stream<Map<int, ({int expiredQty, DateTime? nextExpiry})>>
  watchExpirySummaries() {
    return _productDao.watchExpirySummaries();
  }

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) {
    return _productDao.runInTransaction(action);
  }
}
