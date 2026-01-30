import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/product_variant_dao.dart';
import '../../../../core/database/daos/product_color_dao.dart';
import '../../../../core/database/daos/size_dao.dart';
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
  Future<int> createVariant(ProductVariantsCompanion variant);
  Future<void> updateVariantBarcode({required int variantId, required String barcode});
  Future<bool> updateVariant(ProductVariantModel variant);
  Future<int> deleteVariant(int id);
  
  // Variant summaries (count + total stock per product)
  Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries();
  Stream<Map<int, ({String? sizeName, String? colorHex})>> watchVariantPreviews();
  Future<({int count, int totalStock})?> getVariantSummaryByProduct(int productId);

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

  VariantLocalDatasourceImpl(
    this._variantDao,
    this._colorDao,
    this._sizeDao,
  );

  // Variants
  @override
  Stream<List<ProductVariantModel>> watchAllVariants() {
    return _variantDao.watchAllVariants().map(
          (variants) => variants.map((v) => ProductVariantModel.fromDrift(v)).toList(),
        );
  }

  @override
  Stream<List<ProductVariantModel>> watchVariantsByProduct(int productId) {
    return _variantDao.watchVariantsByProduct(productId).map(
          (variants) => variants.map((v) => ProductVariantModel.fromDrift(v)).toList(),
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
  Future<int> createVariant(ProductVariantsCompanion variant) {
    return _variantDao.createVariant(variant);
  }

  @override
  Future<void> updateVariantBarcode({required int variantId, required String barcode}) {
    return _variantDao.updateVariantBarcode(variantId: variantId, barcode: barcode);
  }

  @override
  Future<bool> updateVariant(ProductVariantModel variant) {
    return _variantDao.updateVariant(
      ProductVariant(
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
        createdAt: DateTime.now(), // Should preserve
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<int> deleteVariant(int id) {
    return _variantDao.deleteVariant(id);
  }

  @override
  Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries() {
    return _variantDao.watchVariantSummaries();
  }

  @override
  Stream<Map<int, ({String? sizeName, String? colorHex})>> watchVariantPreviews() {
    return _variantDao.watchVariantPreviews();
  }

  @override
  Future<({int count, int totalStock})?> getVariantSummaryByProduct(int productId) {
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
  Future<bool> updateColor(ProductColorModel color) {
    return _colorDao.updateColor(
      ProductColor(
        id: color.id,
        name: color.name,
        hexCode: color.hexCode,
        isActive: color.isActive,
        createdAt: DateTime.now(),
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
  Future<bool> updateSize(SizeModel size) {
    return _sizeDao.updateSize(
      Size(
        id: size.id,
        name: size.name,
        description: size.description,
        sortOrder: size.sortOrder,
        isActive: size.isActive,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<int> deleteSize(int id) {
    return _sizeDao.deleteSize(id);
  }
}
