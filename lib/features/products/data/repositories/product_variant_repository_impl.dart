import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
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

  ProductVariantRepositoryImpl(this._datasource);

  String _buildAutoBarcode(int variantId) {
    final padded = variantId.toString().padLeft(11, '0');
    return '29$padded';
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
  }) {
    return _datasource.createVariant(
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
        stockQuantity: Value(stockQuantity),
        isActive: Value(isActive),
      ),
    ).then((id) async {
      final shouldAutoGenerate = barcode == null || barcode.trim().isEmpty;
      if (shouldAutoGenerate) {
        final autoBarcode = _buildAutoBarcode(id);
        await _datasource.updateVariantBarcode(variantId: id, barcode: autoBarcode);
      }
      return id;
    });
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
