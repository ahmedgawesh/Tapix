import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/product_variant_entity.dart';

class ProductVariantModel extends ProductVariant {
  const ProductVariantModel({
    required super.id,
    required super.productId,
    super.sku,
    super.barcode,
    super.colorId,
    super.sizeId,
    required super.costCents,
    required super.priceCents,
    super.wholesalePriceCents,
    super.previousCostCents,
    super.previousPriceCents,
    super.previousWholesalePriceCents,
    super.lastPurchasePriceCents,
    required super.priceAdjustmentCents,
    required super.stockQuantity,
    required super.isActive,
  });

  factory ProductVariantModel.fromDrift(db.ProductVariant variant) {
    return ProductVariantModel(
      id: variant.id,
      productId: variant.productId,
      sku: variant.sku,
      barcode: variant.barcode,
      colorId: variant.colorId,
      sizeId: variant.sizeId,
      costCents: variant.costCents,
      priceCents: variant.priceCents,
      wholesalePriceCents: variant.wholesalePriceCents,
      previousCostCents: variant.previousCostCents,
      previousPriceCents: variant.previousPriceCents,
      previousWholesalePriceCents: variant.previousWholesalePriceCents,
      lastPurchasePriceCents: variant.lastPurchasePriceCents,
      priceAdjustmentCents: variant.priceAdjustmentCents,
      stockQuantity: variant.stockQuantity,
      isActive: variant.isActive,
    );
  }

  db.ProductVariantsCompanion toCompanion() {
    return db.ProductVariantsCompanion(
      id: Value(id),
      productId: Value(productId),
      sku: Value(sku),
      barcode: Value(barcode),
      colorId: Value(colorId),
      sizeId: Value(sizeId),
      costCents: Value(costCents),
      priceCents: Value(priceCents),
      wholesalePriceCents: Value(wholesalePriceCents),
      lastPurchasePriceCents: Value(lastPurchasePriceCents),
      priceAdjustmentCents: Value(priceAdjustmentCents),
      stockQuantity: Value(stockQuantity),
      isActive: Value(isActive),
    );
  }
}
