part of 'bulk_product_bloc.dart';

abstract class BulkProductState extends Equatable {
  const BulkProductState();

  @override
  List<Object?> get props => [];
}

class BulkProductInitial extends BulkProductState {}

class BulkProductEditing extends BulkProductState {
  final List<BulkProductRowData> rows;
  final Map<int, List<String>> validationErrors;

  const BulkProductEditing({
    required this.rows,
    required this.validationErrors,
  });

  @override
  List<Object?> get props => [rows, validationErrors];

  bool get hasValidationErrors => validationErrors.isNotEmpty;

  List<String>? getErrorsForRow(int rowIndex) => validationErrors[rowIndex];
}

class BulkProductSubmitting extends BulkProductState {
  final int totalCount;
  final int currentIndex;
  final List<BulkProductRowData> rows;

  const BulkProductSubmitting({
    required this.totalCount,
    required this.currentIndex,
    required this.rows,
  });

  double get progress => totalCount > 0 ? currentIndex / totalCount : 0;

  @override
  List<Object?> get props => [totalCount, currentIndex, rows];
}

class BulkProductSuccess extends BulkProductState {
  final int successCount;
  final int totalCount;

  const BulkProductSuccess({
    required this.successCount,
    required this.totalCount,
  });

  @override
  List<Object?> get props => [successCount, totalCount];
}

class BulkProductError extends BulkProductState {
  final String message;
  final Map<int, String> failedRows;
  final int successCount;
  final int totalCount;

  const BulkProductError({
    required this.message,
    required this.failedRows,
    required this.successCount,
    required this.totalCount,
  });

  @override
  List<Object?> get props => [message, failedRows, successCount, totalCount];
}

class BulkProductRowData extends Equatable {
  final int rowIndex;
  final String name;
  final String? nameAr;
  final String? nameFr;
  final String? sku;
  final String? barcode;
  final Decimal costCents;
  final Decimal priceCents;
  final Decimal? wholesalePriceCents;
  final int stockQuantity;
  final int minQuantity;
  final int? categoryId;
  final int? colorId;
  final int? sizeId;
  final bool hasVariants;
  final bool isTaxable;
  final int purchaseTaxRateBps;
  final int salesTaxRateBps;

  const BulkProductRowData({
    required this.rowIndex,
    required this.name,
    this.nameAr,
    this.nameFr,
    this.sku,
    this.barcode,
    required this.costCents,
    required this.priceCents,
    this.wholesalePriceCents,
    this.stockQuantity = 0,
    this.minQuantity = 0,
    this.categoryId,
    this.colorId,
    this.sizeId,
    this.hasVariants = false,
    this.isTaxable = false,
    this.purchaseTaxRateBps = 0,
    this.salesTaxRateBps = 0,
  });

  factory BulkProductRowData.empty(int rowIndex) {
    return BulkProductRowData(
      rowIndex: rowIndex,
      name: '',
      costCents: Decimal.zero,
      priceCents: Decimal.zero,
      stockQuantity: 0,
      minQuantity: 0,
    );
  }

  BulkProductRowData copyWith({
    int? rowIndex,
    String? name,
    String? nameAr,
    String? nameFr,
    String? sku,
    String? barcode,
    Decimal? costCents,
    Decimal? priceCents,
    Decimal? wholesalePriceCents,
    int? stockQuantity,
    int? minQuantity,
    int? categoryId,
    int? colorId,
    int? sizeId,
    bool? hasVariants,
    bool? isTaxable,
    int? purchaseTaxRateBps,
    int? salesTaxRateBps,
  }) {
    return BulkProductRowData(
      rowIndex: rowIndex ?? this.rowIndex,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      nameFr: nameFr ?? this.nameFr,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      costCents: costCents ?? this.costCents,
      priceCents: priceCents ?? this.priceCents,
      wholesalePriceCents: wholesalePriceCents ?? this.wholesalePriceCents,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      minQuantity: minQuantity ?? this.minQuantity,
      categoryId: categoryId ?? this.categoryId,
      colorId: colorId ?? this.colorId,
      sizeId: sizeId ?? this.sizeId,
      hasVariants: hasVariants ?? this.hasVariants,
      isTaxable: isTaxable ?? this.isTaxable,
      purchaseTaxRateBps: purchaseTaxRateBps ?? this.purchaseTaxRateBps,
      salesTaxRateBps: salesTaxRateBps ?? this.salesTaxRateBps,
    );
  }

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
