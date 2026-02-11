import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class Product extends Equatable {
  final int id;
  final String name;
  final String? nameAr;
  final String? nameFr;
  final String? description;
  final String? sku;
  final String? barcode;
  final Decimal costCents;
  final Decimal priceCents;
  final Decimal? wholesalePriceCents;
  final Decimal? previousCostCents;
  final Decimal? previousPriceCents;
  final Decimal? previousWholesalePriceCents;
  final int stockQuantity;
  final int minQuantity;
  final int? categoryId;
  final int? supplierId;
  final int? currencyId;
  final String? imagePath;
  final bool hasVariants;
  final bool isTaxable;
  final int purchaseTaxRateBps;
  final int salesTaxRateBps;
  final bool isActive;
  final bool trackInventory;

  const Product({
    required this.id,
    required this.name,
    this.nameAr,
    this.nameFr,
    this.description,
    this.sku,
    this.barcode,
    required this.costCents,
    required this.priceCents,
    this.wholesalePriceCents,
    this.previousCostCents,
    this.previousPriceCents,
    this.previousWholesalePriceCents,
    required this.stockQuantity,
    required this.minQuantity,
    this.categoryId,
    this.supplierId,
    this.currencyId,
    this.imagePath,
    required this.hasVariants,
    required this.isTaxable,
    required this.purchaseTaxRateBps,
    required this.salesTaxRateBps,
    required this.isActive,
    required this.trackInventory,
  });

  Product copyWith({
    int? id,
    String? name,
    String? nameAr,
    String? nameFr,
    String? description,
    String? sku,
    String? barcode,
    Decimal? costCents,
    Decimal? priceCents,
    Decimal? wholesalePriceCents,
    Decimal? previousCostCents,
    Decimal? previousPriceCents,
    Decimal? previousWholesalePriceCents,
    int? stockQuantity,
    int? minQuantity,
    int? categoryId,
    int? supplierId,
    int? currencyId,
    String? imagePath,
    bool? hasVariants,
    bool? isTaxable,
    int? purchaseTaxRateBps,
    int? salesTaxRateBps,
    bool? isActive,
    bool? trackInventory,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      nameFr: nameFr ?? this.nameFr,
      description: description ?? this.description,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      costCents: costCents ?? this.costCents,
      priceCents: priceCents ?? this.priceCents,
      wholesalePriceCents: wholesalePriceCents ?? this.wholesalePriceCents,
      previousCostCents: previousCostCents ?? this.previousCostCents,
      previousPriceCents: previousPriceCents ?? this.previousPriceCents,
      previousWholesalePriceCents: previousWholesalePriceCents ?? this.previousWholesalePriceCents,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      minQuantity: minQuantity ?? this.minQuantity,
      categoryId: categoryId ?? this.categoryId,
      supplierId: supplierId ?? this.supplierId,
      currencyId: currencyId ?? this.currencyId,
      imagePath: imagePath ?? this.imagePath,
      hasVariants: hasVariants ?? this.hasVariants,
      isTaxable: isTaxable ?? this.isTaxable,
      purchaseTaxRateBps: purchaseTaxRateBps ?? this.purchaseTaxRateBps,
      salesTaxRateBps: salesTaxRateBps ?? this.salesTaxRateBps,
      isActive: isActive ?? this.isActive,
      trackInventory: trackInventory ?? this.trackInventory,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        nameAr,
        nameFr,
        description,
        sku,
        barcode,
        costCents,
        priceCents,
        wholesalePriceCents,
        previousCostCents,
        previousPriceCents,
        previousWholesalePriceCents,
        stockQuantity,
        minQuantity,
        categoryId,
        supplierId,
        currencyId,
        imagePath,
        hasVariants,
        isTaxable,
        purchaseTaxRateBps,
        salesTaxRateBps,
        isActive,
        trackInventory,
      ];
}
