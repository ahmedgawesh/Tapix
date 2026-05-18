import 'package:decimal/decimal.dart';
import '../../../../core/services/inventory/inventory_adjustment_service.dart';
import '../entities/product_variant_entity.dart';
import '../entities/product_color_entity.dart';
import '../entities/size_entity.dart';

abstract class ProductVariantRepository {
  Stream<List<ProductVariant>> watchAllVariants();
  Stream<List<ProductVariant>> watchVariantsByProduct(int productId);
  Future<List<ProductVariant>> getVariantsByProduct(int productId);
  Future<ProductVariant?> getVariantById(int id);
  Future<ProductVariant?> getVariantByBarcode(String barcode);
  Future<ProductVariant?> getVariantBySku(String sku);
  Future<ProductVariant?> getDefaultVariantByProduct(int productId);
  Future<int> ensureDefaultVariantForProduct({
    required int productId,
    required Decimal costCents,
    required Decimal priceCents,
    required int stockQuantity,
  });
  
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
  });

  Future<bool> updateVariant(ProductVariant variant);
  Future<int> deleteVariant(int id);

  /// Count historical references (sale/purchase items, return adjustments,
  /// inventory adjustments, batches, price history) for [variantId]. Drives
  /// the smart-delete confirmation dialog so the user understands whether
  /// the variant will be hard-deleted or deactivated.
  Future<int> countVariantReferences(int variantId);

  /// QuickBooks/Xero/Odoo-style smart delete for a single variant:
  ///   - no references  -> hard delete (`DELETE FROM product_variants`)
  ///   - any references -> soft delete (`is_active = 0`) so audit trail,
  ///     COGS history and journal entries remain intact.
  /// Returns the result so the UI can surface the right snackbar.
  Future<VariantDeletionResult> smartDeleteVariant(int variantId);

  /// Atomic "write-off-and-delete" used when the operator deletes a variant
  /// that still carries on-hand stock. The previous flow allowed a hard
  /// delete to silently strand the corresponding 1200 Inventory balance
  /// (GL ≠ Σ stock × cost). The international-standard fix:
  ///
  ///   1. Post a Shrinkage adjustment for the FULL on-hand quantity:
  ///        Dr 5800 Inventory Shrinkage   value
  ///        Cr 1200 Inventory             value
  ///      so the GL is brought down to zero against the variant.
  ///   2. Run [smartDeleteVariant] which then either hard-deletes or
  ///      deactivates depending on historical references.
  ///
  /// [reason] is forwarded to the inventory adjustment audit row so the
  /// shrinkage entry is traceable. The two writes are sequential — but if
  /// the shrinkage succeeds and the delete fails, the GL is still in sync
  /// (stock=0, 1200 unchanged), which is the only constraint we care about.
  Future<VariantDeletionResult> writeOffAndDeleteVariant({
    required int variantId,
    required String reason,
  });

  /// Active dimension-bearing (color/size) variants for [productId]. Used by
  /// the product form to confirm the exact number before disabling variants.
  Future<int> countActiveDimensionalVariants(int productId);

  /// Deactivate (soft-delete) every dimension-bearing variant so the product
  /// reverts to a single default variant behaviour. History is preserved.
  Future<int> deactivateDimensionalVariants(int productId);

  /// Adjust stock quantity for a variant with an auditable journal entry.
  ///
  /// Routes through [InventoryAdjustmentService] which enforces:
  ///   - Non-empty [reason] (never blank or whitespace).
  ///   - Matching sign between [quantityDelta] and [type].
  ///   - Atomic stock + GL update in a single DB transaction.
  ///   - A persisted `inventory_adjustments` row linked to the journal entry.
  ///
  /// [quantityDelta] is positive for a gain, negative for shrinkage.
  /// For cost-only changes (no quantity movement) callers should use the
  /// service directly with [InventoryAdjustmentType.revaluation].
  Future<InventoryAdjustmentResult> adjustStock({
    required int variantId,
    required InventoryAdjustmentType type,
    required int quantityDelta,
    required String reason,
    String? notes,
    required int currencyId,
    int? userId,
  });
  
  // Validation helpers
  Future<bool> isSkuTaken(String sku, {int? excludeVariantId});
  Future<bool> isBarcodeTaken(String barcode, {int? excludeVariantId});
  Future<bool> variantExists({
    required int productId,
    int? colorId,
    int? sizeId,
    int? excludeVariantId,
  });
  
  // Variant summaries
  Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries();
  Stream<Map<int, ({String? sizeName, String? colorHex})>> watchVariantPreviews();
  Future<({int count, int totalStock})?> getVariantSummaryByProduct(int productId);

  // Colors
  Stream<List<ProductColor>> watchAllColors();
  Future<List<ProductColor>> getAllColors();
  Future<int> createColor(String name, String? hexCode);
  Future<bool> updateColor(ProductColor color);
  Future<int> deleteColor(int id);

  // Sizes
  Stream<List<Size>> watchAllSizes();
  Future<List<Size>> getAllSizes();
  Future<int> createSize(String name, int sortOrder, String? description);
  Future<bool> updateSize(Size size);
  Future<int> deleteSize(int id);
}

/// Result of a smart-delete attempt on a single variant. Either the row was
/// hard-deleted (no historical references) or it was deactivated because it
/// is referenced by invoices / returns / adjustments / batches and must be
/// kept for audit & accounting integrity. Mirrors `ProductDeletionResult`.
class VariantDeletionResult {
  final bool wasDeleted;
  final int referenceCount;
  const VariantDeletionResult({
    required this.wasDeleted,
    required this.referenceCount,
  });
}
