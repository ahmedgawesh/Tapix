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
    required int stockQuantity,
    bool isActive = true,
  });

  Future<bool> updateVariant(ProductVariant variant);
  Future<int> deleteVariant(int id);

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
