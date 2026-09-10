class SalePromotionLineSnapshot {
  final int saleItemId;
  final int discountCents;
  final int appliedQuantity;
  final int quantityScale;
  final int originalUnitPriceCents;
  final String rewardType;

  const SalePromotionLineSnapshot({
    required this.saleItemId,
    required this.discountCents,
    required this.appliedQuantity,
    required this.quantityScale,
    required this.originalUnitPriceCents,
    required this.rewardType,
  });

  Map<String, dynamic> toTransportMap() => {
    'saleItemId': saleItemId,
    'discountCents': discountCents,
    'appliedQuantity': appliedQuantity,
    'quantityScale': quantityScale,
    'originalUnitPriceCents': originalUnitPriceCents,
    'rewardType': rewardType,
  };

  factory SalePromotionLineSnapshot.fromTransportMap(
    Map<String, dynamic> json,
  ) => SalePromotionLineSnapshot(
    saleItemId: (json['saleItemId'] as num?)?.toInt() ?? 0,
    discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
    appliedQuantity: (json['appliedQuantity'] as num?)?.toInt() ?? 0,
    quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
    originalUnitPriceCents:
        (json['originalUnitPriceCents'] as num?)?.toInt() ?? 0,
    rewardType: json['rewardType']?.toString() ?? '',
  );
}

/// Immutable, display-safe view of the exact promotion snapshot posted with a
/// sale. It deliberately contains no current promotion definition: invoices,
/// returns and audits must remain reproducible after a campaign is paused or
/// archived.
class SalePromotionSnapshot {
  final int applicationId;
  final int promotionId;
  final String code;
  final String name;
  final int version;
  final String type;
  final String concurrencyMode;
  final int applicationCount;
  final int discountCents;
  final String engineVersion;
  final List<SalePromotionLineSnapshot> allocations;

  const SalePromotionSnapshot({
    required this.applicationId,
    required this.promotionId,
    required this.code,
    required this.name,
    required this.version,
    required this.type,
    required this.concurrencyMode,
    required this.applicationCount,
    required this.discountCents,
    required this.engineVersion,
    this.allocations = const [],
  });

  Map<String, dynamic> toTransportMap() => {
    'applicationId': applicationId,
    'promotionId': promotionId,
    'code': code,
    'name': name,
    'version': version,
    'type': type,
    'concurrencyMode': concurrencyMode,
    'applicationCount': applicationCount,
    'discountCents': discountCents,
    'engineVersion': engineVersion,
    'allocations': allocations
        .map((allocation) => allocation.toTransportMap())
        .toList(growable: false),
  };

  factory SalePromotionSnapshot.fromTransportMap(Map<String, dynamic> json) =>
      SalePromotionSnapshot(
        applicationId: (json['applicationId'] as num?)?.toInt() ?? 0,
        promotionId: (json['promotionId'] as num?)?.toInt() ?? 0,
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        version: (json['version'] as num?)?.toInt() ?? 1,
        type: json['type']?.toString() ?? '',
        concurrencyMode: json['concurrencyMode']?.toString() ?? '',
        applicationCount: (json['applicationCount'] as num?)?.toInt() ?? 1,
        discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
        engineVersion: json['engineVersion']?.toString() ?? '',
        allocations: (json['allocations'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SalePromotionLineSnapshot.fromTransportMap)
            .toList(growable: false),
      );
}

class PromotionCurrencyPerformance {
  final int currencyId;
  final String currencyCode;
  final String currencySymbol;
  final int transactionCount;
  final int applicationCount;
  final int discountCents;
  final int netSalesCents;
  final int revenueCents;
  final int costCents;
  final int grossProfitCents;

  const PromotionCurrencyPerformance({
    required this.currencyId,
    required this.currencyCode,
    required this.currencySymbol,
    required this.transactionCount,
    required this.applicationCount,
    required this.discountCents,
    required this.netSalesCents,
    this.revenueCents = 0,
    this.costCents = 0,
    this.grossProfitCents = 0,
  });
}

/// One currency-specific row in the promotion usage report.
///
/// Monetary values are attributed only to the frozen promotion allocations
/// on sale lines. Return values are the proportional part of those same
/// allocations consumed by the authoritative returned-quantity counters.
class PromotionUsageReportRow {
  final int promotionId;
  final String promotionCode;
  final String promotionName;
  final int promotionVersion;
  final String status;
  final int currencyId;
  final String currencyCode;
  final String currencySymbol;
  final int transactionCount;
  final int applicationCount;
  final int grossSalesCents;
  final int returnedGrossSalesCents;
  final int discountCents;
  final int returnedDiscountCents;
  final int costCents;
  final int returnedCostCents;

  const PromotionUsageReportRow({
    required this.promotionId,
    required this.promotionCode,
    required this.promotionName,
    required this.promotionVersion,
    required this.status,
    required this.currencyId,
    required this.currencyCode,
    required this.currencySymbol,
    required this.transactionCount,
    required this.applicationCount,
    required this.grossSalesCents,
    required this.returnedGrossSalesCents,
    required this.discountCents,
    required this.returnedDiscountCents,
    required this.costCents,
    required this.returnedCostCents,
  });

  int get netGrossSalesCents => grossSalesCents - returnedGrossSalesCents;
  int get netDiscountCents => discountCents - returnedDiscountCents;
  int get netCostCents => costCents - returnedCostCents;
  int get netSalesCents => netGrossSalesCents - netDiscountCents;
  int get grossProfitCents => netSalesCents - netCostCents;
}

/// Invoice drill-down row for one promotion and one currency.
class PromotionUsageInvoiceRow {
  final int saleId;
  final String invoiceNumber;
  final DateTime saleDate;
  final int currencyId;
  final String currencyCode;
  final String currencySymbol;
  final int applicationCount;
  final int grossSalesCents;
  final int returnedGrossSalesCents;
  final int discountCents;
  final int returnedDiscountCents;
  final int costCents;
  final int returnedCostCents;

  const PromotionUsageInvoiceRow({
    required this.saleId,
    required this.invoiceNumber,
    required this.saleDate,
    required this.currencyId,
    required this.currencyCode,
    required this.currencySymbol,
    required this.applicationCount,
    required this.grossSalesCents,
    required this.returnedGrossSalesCents,
    required this.discountCents,
    required this.returnedDiscountCents,
    required this.costCents,
    required this.returnedCostCents,
  });

  int get netGrossSalesCents => grossSalesCents - returnedGrossSalesCents;
  int get netDiscountCents => discountCents - returnedDiscountCents;
  int get netCostCents => costCents - returnedCostCents;
  int get netSalesCents => netGrossSalesCents - netDiscountCents;
  int get grossProfitCents => netSalesCents - netCostCents;
}
