import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../../../core/services/inventory/inventory_adjustment_service.dart';
import '../../../barcode/services/barcode_generation_service.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../../domain/repositories/product_variant_repository.dart';
import '../datasources/variant_local_datasource.dart';
import '../models/product_variant_model.dart';
import '../models/product_color_model.dart';
import '../models/size_model.dart';

class ProductVariantRepositoryImpl implements ProductVariantRepository {
  final VariantLocalDatasource _datasource;
  final InventoryAdjustmentService _adjustmentService;
  final BarcodeGenerationService _barcodeGen;

  ProductVariantRepositoryImpl(
    this._datasource,
    this._adjustmentService, {
    BarcodeGenerationService? barcodeGen,
  }) : _barcodeGen = barcodeGen ?? BarcodeGenerationService();

  /// Produces a deterministic, **valid** EAN-13 for a variant. The previous
  /// implementation returned `'29' + padded(variantId, 11)` which was 13 chars
  /// but had no checksum — scanners rejecting invalid EAN-13 codes would
  /// refuse to read store-printed labels. We now compute the proper checksum
  /// via [BarcodeGenerationService].
  String _buildAutoBarcode(int variantId) {
    return _barcodeGen.generateDeterministicEan13(variantId);
  }

  // Variants
  @override
  Stream<List<ProductVariant>> watchAllVariants() {
    return _datasource.watchAllVariants();
  }

  @override
  Stream<List<ProductVariant>> watchVariantsByProduct(int productId) {
    return _datasource.watchVariantsByProduct(productId);
  }

  @override
  Future<List<ProductVariant>> getVariantsByProduct(int productId) {
    return _datasource.getVariantsByProduct(productId);
  }

  @override
  Future<ProductVariant?> getVariantById(int id) {
    return _datasource.getVariantById(id);
  }

  @override
  Future<ProductVariant?> getVariantByBarcode(String barcode) {
    return _datasource.getVariantByBarcode(barcode);
  }

  @override
  Future<ProductVariant?> getVariantBySku(String sku) {
    return _datasource.getVariantBySku(sku);
  }

  @override
  Future<ProductVariant?> getDefaultVariantByProduct(int productId) {
    return _datasource.getDefaultVariantByProduct(productId);
  }

  @override
  Future<int> ensureDefaultVariantForProduct({
    required int productId,
    required Decimal costCents,
    required Decimal priceCents,
    required int stockQuantity,
  }) async {
    final existing = await _datasource.getDefaultVariantByProduct(productId);
    if (existing != null) {
      return existing.id;
    }

    final id = await createVariant(
      productId: productId,
      costCents: costCents,
      priceCents: priceCents,
      stockQuantity: stockQuantity,
    );
    return id;
  }

  @override
  Future<int> createVariant({
    required int productId,
    String? sku,
    String? barcode,
    int? colorId,
    int? sizeId,
    required Decimal costCents,
    required Decimal priceCents,
    Decimal? wholesalePriceCents,
    required int stockQuantity,
    bool isActive = true,
  }) async {
    // ── Phase 4 accounting invariant ─────────────────────────────────────
    // A newly-created variant with a non-zero starting quantity must post
    // an "Opening Balance" journal entry so that:
    //   value on hand (stock × cost) ≡ balance of account 1200 Inventory.
    //
    // To make that possible we insert the row with stock_quantity = 0 and
    // then call InventoryAdjustmentService.recordOpeningBalance, which:
    //   1. writes an inventory_adjustments audit row (type = opening_balance),
    //   2. increments stock_quantity to the requested value via StockService,
    //   3. posts the matching JE: Dr 1200 Inventory / Cr 3100 Opening
    //      Balance Equity for quantity × cost.
    //
    // Creating with stock = 0 (the default flow) skips the service call
    // entirely and behaves as before.
    final int id = await _datasource.createVariant(
      db.ProductVariantsCompanion(
        productId: Value(productId),
        sku: Value(sku),
        barcode: Value(barcode),
        colorId: Value(colorId),
        sizeId: Value(sizeId),
        costCents: Value(costCents),
        priceCents: Value(priceCents),
        wholesalePriceCents: Value(wholesalePriceCents),
        priceAdjustmentCents: Value(Decimal.zero),
        // Start at zero; opening balance will bring it up via the service.
        stockQuantity: const Value(0),
        isActive: Value(isActive),
      ),
    );

    final shouldAutoGenerate = barcode == null || barcode.trim().isEmpty;
    if (shouldAutoGenerate) {
      final autoBarcode = _buildAutoBarcode(id);
      await _datasource.updateVariantBarcode(variantId: id, barcode: autoBarcode);
    }

    if (stockQuantity > 0) {
      await _adjustmentService.recordOpeningBalance(
        productId: productId,
        variantId: id,
        quantity: stockQuantity,
      );
    }

    return id;
  }

  @override
  Future<bool> updateVariant(ProductVariant variant) {
    if (variant is ProductVariantModel) {
      return _datasource.updateVariant(variant);
    } else {
      return _datasource.updateVariant(
        ProductVariantModel(
          id: variant.id,
          productId: variant.productId,
          sku: variant.sku,
          barcode: variant.barcode,
          colorId: variant.colorId,
          sizeId: variant.sizeId,
          costCents: variant.costCents,
          priceCents: variant.priceCents,
          wholesalePriceCents: variant.wholesalePriceCents,
          priceAdjustmentCents: variant.priceAdjustmentCents,
          stockQuantity: variant.stockQuantity,
          isActive: variant.isActive,
        ),
      );
    }
  }

  @override
  Future<int> deleteVariant(int id) {
    return _datasource.deleteVariant(id);
  }

  @override
  Future<int> countVariantReferences(int variantId) {
    return _datasource.countVariantReferences(variantId);
  }

  @override
  Future<VariantDeletionResult> smartDeleteVariant(int variantId) async {
    final result = await _datasource.smartDeleteVariant(variantId);
    return VariantDeletionResult(
      wasDeleted: result.wasDeleted,
      referenceCount: result.referenceCount,
    );
  }

  @override
  Future<VariantDeletionResult> writeOffAndDeleteVariant({
    required int variantId,
    required String reason,
  }) async {
    final variant = await _datasource.getVariantById(variantId);
    if (variant == null) {
      // Mirror smart-delete contract for the not-found case so callers
      // can treat both methods uniformly.
      return const VariantDeletionResult(wasDeleted: false, referenceCount: 0);
    }

    // Step 1 — post a balanced shrinkage entry that drives stock to zero.
    // This guarantees the 1200 Inventory ledger stays aligned with Σ(stock
    // × cost) regardless of whether the row is hard- or soft-deleted next.
    if (variant.stockQuantity > 0) {
      await _adjustmentService.adjustForProduct(
        productId: variant.productId,
        variantId: variant.id,
        type: InventoryAdjustmentType.shrinkage,
        quantityDelta: -variant.stockQuantity,
        reason: reason,
      );
    }

    // Step 2 — smart delete (hard if no refs, soft if there are any).
    final result = await _datasource.smartDeleteVariant(variantId);
    return VariantDeletionResult(
      wasDeleted: result.wasDeleted,
      referenceCount: result.referenceCount,
    );
  }

  @override
  Future<int> countActiveDimensionalVariants(int productId) {
    return _datasource.countActiveDimensionalVariants(productId);
  }

  @override
  Future<int> deactivateDimensionalVariants(int productId) {
    return _datasource.deactivateDimensionalVariants(productId);
  }

  @override
  Future<InventoryAdjustmentResult> adjustStock({
    required int variantId,
    required InventoryAdjustmentType type,
    required int quantityDelta,
    required String reason,
    String? notes,
    required int currencyId,
    int? userId,
  }) async {
    final variant = await _datasource.getVariantById(variantId);
    if (variant == null) {
      throw const InventoryAdjustmentException('Variant not found');
    }

    // Delegate to the single sanctioned entry point. The service owns:
    //   - reason validation (non-empty),
    //   - stock mutation via StockService,
    //   - journal entry posting, and
    //   - the inventory_adjustments audit row.
    // This repository must NOT touch stock_quantity directly anymore.
    return _adjustmentService.adjust(
      productId: variant.productId,
      variantId: variant.id,
      type: type,
      quantityDelta: quantityDelta,
      reason: reason,
      notes: notes,
      currencyId: currencyId,
      userId: userId,
    );
  }

  @override
  Future<bool> isSkuTaken(String sku, {int? excludeVariantId}) async {
    final variant = await _datasource.getVariantBySku(sku);
    if (variant == null) return false;
    if (excludeVariantId != null && variant.id == excludeVariantId) return false;
    return true;
  }

  @override
  Future<bool> isBarcodeTaken(String barcode, {int? excludeVariantId}) async {
    final variant = await _datasource.getVariantByBarcode(barcode);
    if (variant == null) return false;
    if (excludeVariantId != null && variant.id == excludeVariantId) return false;
    return true;
  }

  @override
  Future<bool> variantExists({
    required int productId,
    int? colorId,
    int? sizeId,
    int? excludeVariantId,
  }) async {
    final variants = await _datasource.getVariantsByProduct(productId);
    for (final v in variants) {
      if (excludeVariantId != null && v.id == excludeVariantId) continue;
      if (v.colorId == colorId && v.sizeId == sizeId) return true;
    }
    return false;
  }

  @override
  Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries() {
    return _datasource.watchVariantSummaries();
  }

  @override
  Stream<Map<int, ({String? sizeName, String? colorHex})>> watchVariantPreviews() {
    return _datasource.watchVariantPreviews();
  }

  @override
  Future<({int count, int totalStock})?> getVariantSummaryByProduct(int productId) {
    return _datasource.getVariantSummaryByProduct(productId);
  }

  // Colors
  @override
  Stream<List<ProductColor>> watchAllColors() {
    return _datasource.watchAllColors();
  }

  @override
  Future<List<ProductColor>> getAllColors() {
    return _datasource.getAllColors();
  }

  @override
  Future<int> createColor(String name, String? hexCode) {
    return _datasource.createColor(
      db.ProductColorsCompanion(
        name: Value(name),
        hexCode: Value(hexCode),
      ),
    );
  }

  @override
  Future<bool> updateColor(ProductColor color) {
    if (color is ProductColorModel) {
      return _datasource.updateColor(color);
    } else {
      return _datasource.updateColor(
        ProductColorModel(
          id: color.id,
          name: color.name,
          hexCode: color.hexCode,
          isActive: color.isActive,
        ),
      );
    }
  }

  @override
  Future<int> deleteColor(int id) {
    return _datasource.deleteColor(id);
  }

  // Sizes
  @override
  Stream<List<Size>> watchAllSizes() {
    return _datasource.watchAllSizes();
  }

  @override
  Future<List<Size>> getAllSizes() {
    return _datasource.getAllSizes();
  }

  @override
  Future<int> createSize(String name, int sortOrder, String? description) {
    return _datasource.createSize(
      db.SizesCompanion(
        name: Value(name),
        sortOrder: Value(sortOrder),
        description: Value(description),
      ),
    );
  }

  @override
  Future<bool> updateSize(Size size) {
    if (size is SizeModel) {
      return _datasource.updateSize(size);
    } else {
      return _datasource.updateSize(
        SizeModel(
          id: size.id,
          name: size.name,
          description: size.description,
          sortOrder: size.sortOrder,
          isActive: size.isActive,
        ),
      );
    }
  }

  @override
  Future<int> deleteSize(int id) {
    return _datasource.deleteSize(id);
  }
}
