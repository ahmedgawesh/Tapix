import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class ProductVariant extends Equatable {
  final int id;
  final int productId;
  final String? sku;
  final String? barcode;
  final int? colorId;
  final int? sizeId;
  final Decimal costCents;
  final Decimal priceCents;
  final Decimal? wholesalePriceCents;
  final Decimal? previousCostCents;
  final Decimal? previousPriceCents;
  final Decimal? previousWholesalePriceCents;
  final Decimal priceAdjustmentCents;
  final int stockQuantity;
  final bool isActive;

  const ProductVariant({
    required this.id,
    required this.productId,
    this.sku,
    this.barcode,
    this.colorId,
    this.sizeId,
    required this.costCents,
    required this.priceCents,
    this.wholesalePriceCents,
    this.previousCostCents,
    this.previousPriceCents,
    this.previousWholesalePriceCents,
    required this.priceAdjustmentCents,
    required this.stockQuantity,
    required this.isActive,
  });

  ProductVariant copyWith({
    int? id,
    int? productId,
    String? sku,
    String? barcode,
    int? colorId,
    int? sizeId,
    Decimal? costCents,
    Decimal? priceCents,
    Decimal? wholesalePriceCents,
    Decimal? previousCostCents,
    Decimal? previousPriceCents,
    Decimal? previousWholesalePriceCents,
    Decimal? priceAdjustmentCents,
    int? stockQuantity,
    bool? isActive,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      colorId: colorId ?? this.colorId,
      sizeId: sizeId ?? this.sizeId,
      costCents: costCents ?? this.costCents,
      priceCents: priceCents ?? this.priceCents,
      wholesalePriceCents: wholesalePriceCents ?? this.wholesalePriceCents,
      previousCostCents: previousCostCents ?? this.previousCostCents,
      previousPriceCents: previousPriceCents ?? this.previousPriceCents,
      previousWholesalePriceCents: previousWholesalePriceCents ?? this.previousWholesalePriceCents,
      priceAdjustmentCents: priceAdjustmentCents ?? this.priceAdjustmentCents,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  List<Object?> get props => [
        id,
        productId,
        sku,
        barcode,
        colorId,
        sizeId,
        costCents,
        priceCents,
        wholesalePriceCents,
        previousCostCents,
        previousPriceCents,
        previousWholesalePriceCents,
        priceAdjustmentCents,
        stockQuantity,
        isActive,
      ];
}
