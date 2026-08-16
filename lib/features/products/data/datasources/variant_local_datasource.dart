import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/product_variant_dao.dart';
import '../../../../core/database/daos/product_color_dao.dart';
import '../../../../core/database/daos/size_dao.dart';
import '../../../../core/services/price_history_service.dart';
import '../models/product_variant_model.dart';
import '../models/product_color_model.dart';
import '../models/size_model.dart';

abstract class VariantLocalDatasource {
  // Variants
  Stream<List<ProductVariantModel>> watchAllVariants();
  Stream<List<ProductVariantModel>> watchVariantsByProduct(int productId);
  Future<List<ProductVariantModel>> getVariantsByProduct(int productId);
  Future<ProductVariantModel?> getVariantById(int id);
  Future<ProductVariantModel?> getVariantByBarcode(String barcode);
  Future<ProductVariantModel?> getVariantBySku(String sku);
  Future<ProductVariantModel?> getDefaultVariantByProduct(int productId);
  Future<ProductVariantModel?> getAnonymousDefaultVariantByProduct(
    int productId, {
    bool activeOnly = true,
  });
  Future<void> reactivateVariant(int variantId);
  Future<int> createVariant(ProductVariantsCompanion variant);
  Future<void> updateVariantBarcode({
    required int variantId,
    required String barcode,
  });
  Future<bool> updateVariant(ProductVariantModel variant);
  Future<int> deleteVariant(int id);

  /// Count historical references to a single variant. Drives the smart-delete
  /// dialog: any non-zero count means the variant must be deactivated rather
  /// than hard-deleted to preserve audit trail and accounting integrity.
  Future<int> countVariantReferences(int variantId);

  /// QuickBooks/Xero/Odoo-style smart delete for a single variant: hard
  /// deletes when there are no references, otherwise deactivates and reports
  /// the reference count for surfacing in the UI.
  Future<({bool wasDeleted, int referenceCount})> smartDeleteVariant(
    int variantId,
  );

  /// Dimension-bearing variants (color or size != null) for [productId] that
  /// are still active. Drives the "disable variants" confirmation count.
  Future<int> countActiveDimensionalVariants(int productId);
  Future<int> countActiveDimensionalVariantsWithStock(int productId);

  /// Deactivate every dimension-bearing variant of [productId] (soft-delete).
  Future<int> deactivateDimensionalVariants(int productId);

  // Variant summaries (count + total stock per product)
  Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries();
  Stream<Map<int, ({String? sizeName, String? colorHex})>>
  watchVariantPreviews();
  Future<({int count, int totalStock})?> getVariantSummaryByProduct(
    int productId,
  );

  // Colors
  Stream<List<ProductColorModel>> watchAllColors();
  Future<List<ProductColorModel>> getAllColors();
  Future<ProductColorModel?> getColorById(int id);
  Future<int> createColor(ProductColorsCompanion color);
  Future<bool> updateColor(ProductColorModel color);
  Future<int> deleteColor(int id);

  // Sizes
  Stream<List<SizeModel>> watchAllSizes();
  Future<List<SizeModel>> getAllSizes();
  Future<SizeModel?> getSizeById(int id);
  Future<int> createSize(SizesCompanion size);
  Future<bool> updateSize(SizeModel size);
  Future<int> deleteSize(int id);
}

class VariantLocalDatasourceImpl implements VariantLocalDatasource {
  final ProductVariantDao _variantDao;
  final ProductColorDao _colorDao;
  final SizeDao _sizeDao;

  VariantLocalDatasourceImpl(this._variantDao, this._colorDao, this._sizeDao);

  // Variants
  @override
  Stream<List<ProductVariantModel>> watchAllVariants() {
    return _variantDao.watchAllVariants().map(
      (variants) =>
          variants.map((v) => ProductVariantModel.fromDrift(v)).toList(),
    );
  }

  @override
  Stream<List<ProductVariantModel>> watchVariantsByProduct(int productId) {
    return _variantDao
        .watchVariantsByProduct(productId)
        .map(
          (variants) =>
              variants.map((v) => ProductVariantModel.fromDrift(v)).toList(),
        );
  }

  @override
  Future<List<ProductVariantModel>> getVariantsByProduct(int productId) async {
    final variants = await _variantDao.getVariantsByProduct(productId);
    return variants.map((v) => ProductVariantModel.fromDrift(v)).toList();
  }

  @override
  Future<ProductVariantModel?> getVariantById(int id) async {
    final variant = await _variantDao.getVariantById(id);
    return variant == null ? null : ProductVariantModel.fromDrift(variant);
  }

  @override
  Future<ProductVariantModel?> getVariantByBarcode(String barcode) async {
    final variant = await _variantDao.getVariantByBarcode(barcode);
    return variant == null ? null : ProductVariantModel.fromDrift(variant);
  }

  @override
  Future<ProductVariantModel?> getVariantBySku(String sku) async {
    final variant = await _variantDao.getVariantBySku(sku);
    return variant == null ? null : ProductVariantModel.fromDrift(variant);
  }

  @override
  Future<ProductVariantModel?> getDefaultVariantByProduct(int productId) async {
    final variant = await _variantDao.getDefaultVariantByProduct(productId);
    return variant == null ? null : ProductVariantModel.fromDrift(variant);
  }

  @override
  Future<ProductVariantModel?> getAnonymousDefaultVariantByProduct(
    int productId, {
    bool activeOnly = true,
  }) async {
    final variant = await _variantDao.getAnonymousDefaultVariantByProduct(
      productId,
      activeOnly: activeOnly,
    );
    return variant == null ? null : ProductVariantModel.fromDrift(variant);
  }

  @override
  Future<void> reactivateVariant(int variantId) {
    return _variantDao.reactivateVariant(variantId);
  }

  @override
  Future<int> createVariant(ProductVariantsCompanion variant) {
    return _variantDao.createVariant(variant);
  }

  @override
  Future<void> updateVariantBarcode({
    required int variantId,
    required String barcode,
  }) {
    return _variantDao.updateVariantBarcode(
      variantId: variantId,
      barcode: barcode,
    );
  }

  @override
  Future<bool> updateVariant(ProductVariantModel variant) async {
    return _variantDao.runInTransaction(() async {
      // Preserve original createdAt — updating the variant should never
      // rewrite its creation timestamp (required for aging reports & SKU lifecycle).
      final existing = await _variantDao.getVariantById(variant.id);

      // ── DEFENSE IN DEPTH (Phase 4) ─────────────────────────────────────
      // Manual edits to `stock_quantity` or `cost_cents` via this path are
      // FORBIDDEN: they bypass the InventoryAdjustmentService and leave the
      // general ledger out of sync with physical stock. Any such change
      // must go through `ProductVariantRepository.adjustStock(...)` which
      // posts a proper journal entry.
      //
      // We silently force those two fields back to their persisted values
      // instead of throwing, because legacy UI code paths pass a full
      // ProductVariant instance including stock/cost even when the user
      // only edited name/price/SKU. Throwing here would regress those
      // flows. The forced overwrite guarantees the invariant:
      //   stock_quantity × cost_cents ≡ Σ(1200 inventory ledger postings)
      final int safeStock = existing?.stockQuantity ?? variant.stockQuantity;
      final Decimal safeCost = existing?.costCents ?? variant.costCents;

      // Surface (debug only) when a caller passed values that diverge from the
      // persisted ones. Silently ignoring these used to make follow-up bugs
      // hard to locate; a developer-log entry preserves the safe behaviour
      // while leaving a breadcrumb for whoever wrote the offending update path.
      if (existing != null) {
        if (existing.stockQuantity != variant.stockQuantity) {
          developer.log(
            'updateVariant called with divergent stock_quantity '
            '(existing=${existing.stockQuantity}, attempted=${variant.stockQuantity}, '
            'variantId=${variant.id}). Value forced back to existing. '
            'Use ProductVariantRepository.adjustStock(...) to change stock through the GL.',
            name: 'VariantLocalDatasource',
            level: 900, // WARNING
          );
        }
        if (existing.costCents != variant.costCents) {
          developer.log(
            'updateVariant called with divergent cost_cents '
            '(existing=${existing.costCents}, attempted=${variant.costCents}, '
            'variantId=${variant.id}). Value forced back to existing. '
            'Use InventoryAdjustmentService.revaluation(...) to change cost through the GL.',
            name: 'VariantLocalDatasource',
            level: 900, // WARNING
          );
        }
      }

      final updated = ProductVariant(
        id: variant.id,
        productId: variant.productId,
        sku: variant.sku,
        barcode: variant.barcode,
        colorId: variant.colorId,
        sizeId: variant.sizeId,
        costCents: safeCost,
        priceCents: variant.priceCents,
        wholesalePriceCents: variant.wholesalePriceCents,
        // Supplier reference price (gross of trade discounts) — managed by
        // purchase posting via `purchase_dao.postPurchase`. Preserved on
        // generic variant edits (SKU, barcode, color/size, status) so the
        // product detail screen keeps showing the most recent supplier
        // list price after the user renames or re-categorises a variant.
        lastPurchasePriceCents: existing?.lastPurchasePriceCents,
        priceAdjustmentCents: variant.priceAdjustmentCents,
        stockQuantity: safeStock,
        isActive: variant.isActive,
        // Preserve existing createdAt; only falls through to now() for the
        // theoretically-impossible case where the row vanished between fetch
        // and update (guarded by the earlier select).
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final ok = await _variantDao.updateVariant(updated);
      final isDimensional =
          existing?.colorId != null || existing?.sizeId != null;
      if (ok && existing != null && isDimensional) {
        await PriceHistoryService.recordIfChanged(
          _variantDao,
          productId: updated.productId,
          variantId: updated.id,
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
          changeReason: 'variant_update',
        );
      }
      return ok;
    });
  }

  @override
  Future<int> deleteVariant(int id) {
    return _variantDao.deleteVariant(id);
  }

  @override
  Future<int> countVariantReferences(int variantId) {
    return _variantDao.countVariantReferences(variantId);
  }

  @override
  Future<({bool wasDeleted, int referenceCount})> smartDeleteVariant(
    int variantId,
  ) {
    return _variantDao.smartDeleteVariant(variantId);
  }

  @override
  Future<int> countActiveDimensionalVariants(int productId) {
    return _variantDao.countActiveDimensionalVariants(productId);
  }

  @override
  Future<int> countActiveDimensionalVariantsWithStock(int productId) {
    return _variantDao.countActiveDimensionalVariantsWithStock(productId);
  }

  @override
  Future<int> deactivateDimensionalVariants(int productId) {
    return _variantDao.deactivateDimensionalVariants(productId);
  }

  @override
  Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries() {
    return _variantDao.watchVariantSummaries();
  }

  @override
  Stream<Map<int, ({String? sizeName, String? colorHex})>>
  watchVariantPreviews() {
    return _variantDao.watchVariantPreviews();
  }

  @override
  Future<({int count, int totalStock})?> getVariantSummaryByProduct(
    int productId,
  ) {
    return _variantDao.getVariantSummaryByProduct(productId);
  }

  // Colors
  @override
  Stream<List<ProductColorModel>> watchAllColors() {
    return _colorDao.watchAllColors().map(
      (colors) => colors.map((c) => ProductColorModel.fromDrift(c)).toList(),
    );
  }

  @override
  Future<List<ProductColorModel>> getAllColors() async {
    final colors = await _colorDao.getAllColors();
    return colors.map((c) => ProductColorModel.fromDrift(c)).toList();
  }

  @override
  Future<ProductColorModel?> getColorById(int id) async {
    final color = await _colorDao.getColorById(id);
    return color == null ? null : ProductColorModel.fromDrift(color);
  }

  @override
  Future<int> createColor(ProductColorsCompanion color) {
    return _colorDao.createColor(color);
  }

  @override
  Future<bool> updateColor(ProductColorModel color) async {
    final existing = await _colorDao.getColorById(color.id);
    return _colorDao.updateColor(
      ProductColor(
        id: color.id,
        name: color.name,
        hexCode: color.hexCode,
        isActive: color.isActive,
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Future<int> deleteColor(int id) {
    return _colorDao.deleteColor(id);
  }

  // Sizes
  @override
  Stream<List<SizeModel>> watchAllSizes() {
    return _sizeDao.watchAllSizes().map(
      (sizes) => sizes.map((s) => SizeModel.fromDrift(s)).toList(),
    );
  }

  @override
  Future<List<SizeModel>> getAllSizes() async {
    final sizes = await _sizeDao.getAllSizes();
    return sizes.map((s) => SizeModel.fromDrift(s)).toList();
  }

  @override
  Future<SizeModel?> getSizeById(int id) async {
    final size = await _sizeDao.getSizeById(id);
    return size == null ? null : SizeModel.fromDrift(size);
  }

  @override
  Future<int> createSize(SizesCompanion size) {
    return _sizeDao.createSize(size);
  }

  @override
  Future<bool> updateSize(SizeModel size) async {
    final existing = await _sizeDao.getSizeById(size.id);
    return _sizeDao.updateSize(
      Size(
        id: size.id,
        name: size.name,
        description: size.description,
        sortOrder: size.sortOrder,
        isActive: size.isActive,
        createdAt: existing?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Future<int> deleteSize(int id) {
    return _sizeDao.deleteSize(id);
  }
}
