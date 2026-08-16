import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/free_quota_service.dart';
import '../../../../core/services/inventory/inventory_adjustment_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/price_history_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/product_local_datasource.dart';
import '../datasources/variant_local_datasource.dart';
import '../models/product_model.dart';

export '../../domain/repositories/product_repository.dart' show BulkProductData;

class ProductRepositoryImpl implements ProductRepository {
  final ProductLocalDatasource _datasource;
  final AuditLogService _audit;
  final SessionService _sessionService;
  final VariantLocalDatasource? _variantDatasource;
  final InventoryAdjustmentService? _adjustmentService;

  /// Phase B4 — free-tier cumulative quota guard. Optional so existing tests
  /// that construct the repository without DI keep working. When provided,
  /// `createProduct` calls `guardProductCreation()` (may throw
  /// [FreeQuotaExceededException]) and `incrementProductsCreated()` after a
  /// successful insert.
  final FreeQuotaService? _freeQuotaService;

  ProductRepositoryImpl(
    this._datasource,
    this._audit,
    this._sessionService, {
    VariantLocalDatasource? variantDatasource,
    InventoryAdjustmentService? adjustmentService,
    FreeQuotaService? freeQuotaService,
  }) : _variantDatasource = variantDatasource,
       _adjustmentService = adjustmentService,
       _freeQuotaService = freeQuotaService;

  Future<int?> _currentUserId() => _sessionService.getCurrentUserId();

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
  Future<Product?> findByName(String name) {
    return _datasource.findByName(name);
  }

  @override
  Future<Product?> getProductById(int id) {
    return _datasource.getProductById(id);
  }

  @override
  Future<List<Product>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
    bool? isActive = true,
    int lowStockThreshold = 5,
  }) {
    return _datasource.filterProducts(
      categoryId: categoryId,
      stockStatus: stockStatus,
      limit: limit,
      offset: offset,
      isActive: isActive,
      lowStockThreshold: lowStockThreshold,
    );
  }

  @override
  Stream<List<Product>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
    bool? isActive = true,
    int lowStockThreshold = 5,
  }) {
    return _datasource.watchFilteredProducts(
      categoryId: categoryId,
      stockStatus: stockStatus,
      isActive: isActive,
      lowStockThreshold: lowStockThreshold,
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
    String measurementType = 'piece',
    String costingMethod = 'wac',
    String inventoryTrackingType = 'standard',
  }) async {
    assert(
      inventoryTrackingType == 'standard' ||
          inventoryTrackingType == 'batch' ||
          inventoryTrackingType == 'batch_expiry',
      'inventoryTrackingType must be standard | batch | batch_expiry',
    );
    // Phase B4 — enforce free-tier cumulative cap BEFORE the insert.
    // Pro users bypass; free users at or past the cap get
    // [FreeQuotaExceededException].
    _freeQuotaService?.guardProductCreation();
    final productId = await _datasource.createProduct(
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
        measurementType: Value(measurementType),
        costingMethod: Value(costingMethod),
        inventoryTrackingType: Value(inventoryTrackingType),
      ),
    );

    // Audit: log product creation
    await _audit.logProductCreated(
      productId: productId,
      productName: name,
      userId: await _currentUserId(),
    );

    // Phase B4 — bump the cumulative counter ONLY after a successful insert.
    // Pro users still increment so that, if their subscription lapses, the
    // free-tier counter accurately reflects lifetime usage.
    await _freeQuotaService?.incrementProductsCreated();

    return productId;
  }

  @override
  Future<bool> updateProduct(Product product) async {
    // Audit: log product update
    _audit.logProductUpdated(
      productId: product.id,
      productName: product.name,
      userId: await _currentUserId(),
    );

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
          measurementType: product.measurementType,
          costingMethod: product.costingMethod,
        ),
      );
    }
  }

  @override
  Future<String?> getCostingMethodLockReason(int productId) {
    return _datasource.getCostingMethodLockReason(productId);
  }

  @override
  Future<String?> setCostingMethod({
    required int productId,
    required String method,
  }) {
    return _datasource.setCostingMethod(productId: productId, method: method);
  }

  @override
  Future<String> getInventoryTrackingType(int productId) {
    return _datasource.getInventoryTrackingType(productId);
  }

  @override
  Future<String?> setInventoryTrackingType({
    required int productId,
    required String trackingType,
  }) {
    return _datasource.setInventoryTrackingType(
      productId: productId,
      trackingType: trackingType,
    );
  }

  @override
  Future<String?> setMeasurementType({
    required int productId,
    required String measurementType,
  }) {
    return _datasource.setMeasurementType(
      productId: productId,
      measurementType: measurementType,
    );
  }

  @override
  Future<String?> setTrackInventory({
    required int productId,
    required bool trackInventory,
  }) {
    return _datasource.setTrackInventory(
      productId: productId,
      trackInventory: trackInventory,
    );
  }

  @override
  Future<int> deleteProduct(int id) async {
    // Audit: log product deletion (CRITICAL)
    _audit.logProductDeleted(
      productId: id,
      productName: 'Product #$id',
      userId: await _currentUserId(),
    );
    return _datasource.deleteProduct(id);
  }

  @override
  Future<int> countProductReferences(int productId) {
    return _datasource.countProductReferences(productId);
  }

  @override
  Future<ProductDeletionResult> smartDeleteProduct(int productId) async {
    final result = await _datasource.smartDeleteProduct(productId);
    if (result.wasDeleted) {
      _audit.logProductDeleted(
        productId: productId,
        productName: 'Product #$productId',
        userId: await _currentUserId(),
      );
    } else {
      // Deactivation is audit-relevant but less severe than hard delete.
      _audit.logProductUpdated(
        productId: productId,
        productName:
            'Product #$productId (deactivated, ${result.referenceCount} refs)',
        userId: await _currentUserId(),
      );
    }
    return ProductDeletionResult(
      wasDeleted: result.wasDeleted,
      referenceCount: result.referenceCount,
    );
  }

  @override
  Future<ProductDeletionResult> writeOffAndDeleteProduct({
    required int productId,
    required String reason,
  }) async {
    // The accounting-safe write-off step requires both the variant
    // datasource (to enumerate every variant carrying stock) and the
    // adjustment service (to post the shrinkage JE per variant). They
    // are optional in the constructor for backwards-compat; if either
    // is missing we fall back to the plain smart-delete (the old behaviour
    // — accepted only when the product carries no stock).
    final variantDs = _variantDatasource;
    final adjSvc = _adjustmentService;

    if (variantDs != null && adjSvc != null) {
      // Iterate active variants with stock>0 and shrink each to zero
      // before touching the products table. Inactive variants already
      // had their stock zeroed (or never had any) so we leave them be.
      final variants = await variantDs.getVariantsByProduct(productId);
      for (final v in variants) {
        if (v.stockQuantity > 0) {
          await adjSvc.adjustForProduct(
            productId: productId,
            variantId: v.id,
            type: InventoryAdjustmentType.shrinkage,
            quantityDelta: -v.stockQuantity,
            reason: reason,
          );
        }
      }
    }

    // Now delete (hard if no refs, soft if any).
    return smartDeleteProduct(productId);
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
    Set<String> closedPurchaseStatuses = const {
      'closed',
      'paid',
      'completed',
      'posted',
    },
  }) {
    return _datasource.findProductIdsReferencedByOpenPurchases(
      productIds,
      closedPurchaseStatuses: closedPurchaseStatuses,
    );
  }

  @override
  Future<Map<int, int>> bulkCreateProducts(
    List<BulkProductData> products,
  ) async {
    _freeQuotaService?.guardProductCreations(products.length);
    final companions = products
        .map(
          (p) => db.ProductsCompanion(
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
          ),
        )
        .toList();

    final created = await _datasource.bulkCreateProducts(companions);

    final userId = await _currentUserId();
    final productByRow = {
      for (final product in products) product.rowIndex: product,
    };
    for (final entry in created.entries) {
      final product = productByRow[entry.key];
      if (product == null) continue;
      await _audit.logProductCreated(
        productId: entry.value,
        productName: product.name,
        userId: userId,
      );
    }

    await _freeQuotaService?.incrementProductsCreatedBy(created.length);
    return created;
  }

  @override
  Future<void> bulkUpdatePricesWithHistory({
    required List<Product> products,
    required Map<int, Map<String, Decimal>> priceChanges,
    required List<PriceHistory> historyRecords,
  }) async {
    // Convert Product entities to ProductModel for datasource
    final productModels = products
        .map((p) => ProductModel.fromEntity(p))
        .toList();

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

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    final quotaSnapshot = _freeQuotaService?.productsCreatedLifetime;
    try {
      return await _datasource.runInTransaction(action);
    } catch (_) {
      if (quotaSnapshot != null) {
        await _freeQuotaService!.restoreProductsCreatedAfterRollback(
          quotaSnapshot,
        );
      }
      rethrow;
    }
  }

  @override
  Stream<Map<int, ({int expiredQty, DateTime? nextExpiry})>>
  watchExpirySummaries() {
    return _datasource.watchExpirySummaries();
  }
}
