import 'package:decimal/decimal.dart';
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

  /// Adjust stock quantity for a variant with accounting journal entry.
  /// [quantityDelta] is positive for increase, negative for decrease.
  /// [reason] is required for audit trail.
  /// [currencyId] and [userId] are needed for journal entry posting.
  Future<void> adjustStock({
    required int variantId,
    required int quantityDelta,
    required String reason,
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
