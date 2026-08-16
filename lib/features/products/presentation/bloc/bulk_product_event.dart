part of 'bulk_product_bloc.dart';

abstract class BulkProductEvent extends Equatable {
  const BulkProductEvent();

  @override
  List<Object?> get props => [];
}

class BulkProductRowAdded extends BulkProductEvent {
  const BulkProductRowAdded();
}

class BulkProductRowRemoved extends BulkProductEvent {
  final int rowIndex;

  const BulkProductRowRemoved(this.rowIndex);

  @override
  List<Object?> get props => [rowIndex];
}

class BulkProductRowUpdated extends BulkProductEvent {
  final int rowIndex;
  final String? name;
  final String? nameAr;
  final String? nameFr;
  final String? sku;
  final String? barcode;
  final Decimal? costCents;
  final Decimal? priceCents;
  final Decimal? wholesalePriceCents;
  final int? stockQuantity;
  final int? minQuantity;
  final int? categoryId;
  final int? colorId;
  final int? sizeId;
  final bool? hasVariants;
  final bool? isTaxable;
  final int? purchaseTaxRateBps;
  final int? salesTaxRateBps;

  const BulkProductRowUpdated({
    required this.rowIndex,
    this.name,
    this.nameAr,
    this.nameFr,
    this.sku,
    this.barcode,
    this.costCents,
    this.priceCents,
    this.wholesalePriceCents,
    this.stockQuantity,
    this.minQuantity,
    this.categoryId,
    this.colorId,
    this.sizeId,
    this.hasVariants,
    this.isTaxable,
    this.purchaseTaxRateBps,
    this.salesTaxRateBps,
  });

  @override
  List<Object?> get props => [
    rowIndex,
    name,
    nameAr,
    nameFr,
    sku,
    barcode,
    costCents,
    priceCents,
    wholesalePriceCents,
    stockQuantity,
    minQuantity,
    categoryId,
    colorId,
    sizeId,
    hasVariants,
    isTaxable,
    purchaseTaxRateBps,
    salesTaxRateBps,
  ];
}

class BulkProductValidationRequested extends BulkProductEvent {
  const BulkProductValidationRequested();
}

class BulkProductSubmitRequested extends BulkProductEvent {
  const BulkProductSubmitRequested();
}

class BulkProductReset extends BulkProductEvent {
  const BulkProductReset();
}
