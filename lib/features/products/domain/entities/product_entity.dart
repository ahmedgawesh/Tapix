import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/measurement/measurement.dart';

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

  /// Supplier reference price (gross of trade discounts). Decoupled from
  /// [costCents] which carries the IAS-2 net cost basis used for COGS and
  /// inventory valuation. UI displays this with fallback to [costCents]
  /// for legacy products predating migration 10055.
  final Decimal? lastPurchasePriceCents;

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
  final String measurementType;

  /// Inventory costing method used for COGS computation.
  /// One of `'wac'` (Weighted Average — default) or `'fifo'` (First-In, First-Out).
  /// Locked once any stock movement or batch consumption exists for this product.
  ///
  /// **Deprecation path (Phase F)**: this field is now derived from
  /// [inventoryTrackingType] — `standard` ⇒ `wac`, otherwise `fifo`. It is
  /// kept on the entity during the expand → migrate → contract migration
  /// window so existing readers (DAOs, reports) keep working.
  final String costingMethod;

  /// Per-product inventory tracking type — Layer 2 of the two-layer
  /// inventory architecture (see `docs/INVENTORY_ARCHITECTURE_PLAN.md`).
  /// One of:
  ///   - `'standard'`     — single pool of stock, no batches (default).
  ///   - `'batch'`        — every purchase creates a batch (lot); FIFO consumption.
  ///   - `'batch_expiry'` — batch + expiry date; FEFO consumption + alerts.
  ///
  /// Locked under the same rules as [costingMethod] (stock or consumptions
  /// exist) — flipping it after movements would leave batches in an
  /// inconsistent state.
  final String inventoryTrackingType;

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
    this.lastPurchasePriceCents,
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
    this.measurementType = 'piece',
    this.costingMethod = 'wac',
    this.inventoryTrackingType = 'standard',
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
    Decimal? lastPurchasePriceCents,
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
    String? measurementType,
    String? costingMethod,
    String? inventoryTrackingType,
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
      previousWholesalePriceCents:
          previousWholesalePriceCents ?? this.previousWholesalePriceCents,
      lastPurchasePriceCents:
          lastPurchasePriceCents ?? this.lastPurchasePriceCents,
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
      measurementType: measurementType ?? this.measurementType,
      costingMethod: costingMethod ?? this.costingMethod,
      inventoryTrackingType:
          inventoryTrackingType ?? this.inventoryTrackingType,
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
    lastPurchasePriceCents,
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
    measurementType,
    costingMethod,
    inventoryTrackingType,
  ];

  MeasurementType get measurement => MeasurementType.fromDb(measurementType);

  int get quantityScale => measurement.quantityScale;
}
