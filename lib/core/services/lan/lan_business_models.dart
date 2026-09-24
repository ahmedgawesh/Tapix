import '../../promotions/promotion_sale_snapshot.dart';
import 'lan_models.dart';

class LanCatalogVariant {
  final int id;
  final int productId;
  final String? sku;
  final String? barcode;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final int priceCents;
  final int? wholesalePriceCents;
  final int? costCents;
  final int? lastPurchasePriceCents;
  final int stockQuantity;

  const LanCatalogVariant({
    required this.id,
    required this.productId,
    this.sku,
    this.barcode,
    this.colorName,
    this.colorHex,
    this.sizeName,
    required this.priceCents,
    this.wholesalePriceCents,
    this.costCents,
    this.lastPurchasePriceCents,
    required this.stockQuantity,
  });

  String get label {
    final dimensions = [
      colorName,
      sizeName,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' / ');
    if (dimensions.isNotEmpty) return dimensions;
    return sku?.trim().isNotEmpty == true ? sku!.trim() : 'Default';
  }

  Map<String, dynamic> toJson({bool includeCost = false}) => {
    'id': id,
    'productId': productId,
    'sku': sku,
    'barcode': barcode,
    'colorName': colorName,
    'colorHex': colorHex,
    'sizeName': sizeName,
    'priceCents': priceCents,
    'wholesalePriceCents': wholesalePriceCents,
    if (includeCost) 'costCents': costCents,
    if (includeCost) 'lastPurchasePriceCents': lastPurchasePriceCents,
    'stockQuantity': stockQuantity,
  };

  factory LanCatalogVariant.fromJson(Map<String, dynamic> json) {
    return LanCatalogVariant(
      id: (json['id'] as num).toInt(),
      productId: (json['productId'] as num).toInt(),
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      colorName: json['colorName']?.toString(),
      colorHex: json['colorHex']?.toString(),
      sizeName: json['sizeName']?.toString(),
      priceCents: (json['priceCents'] as num).toInt(),
      wholesalePriceCents: (json['wholesalePriceCents'] as num?)?.toInt(),
      costCents: (json['costCents'] as num?)?.toInt(),
      lastPurchasePriceCents: (json['lastPurchasePriceCents'] as num?)?.toInt(),
      stockQuantity: (json['stockQuantity'] as num).toInt(),
    );
  }
}

class LanMedicineIngredient {
  final int ingredientId;
  final String canonicalName;
  final String? nameAr;
  final String? nameFr;
  final int strengthValueMicros;
  final String strengthUnit;
  final int? basisValueMicros;
  final String? basisUnit;

  const LanMedicineIngredient({
    required this.ingredientId,
    required this.canonicalName,
    this.nameAr,
    this.nameFr,
    required this.strengthValueMicros,
    required this.strengthUnit,
    this.basisValueMicros,
    this.basisUnit,
  });

  Map<String, dynamic> toJson() => {
    'ingredientId': ingredientId,
    'canonicalName': canonicalName,
    'nameAr': nameAr,
    'nameFr': nameFr,
    'strengthValueMicros': strengthValueMicros,
    'strengthUnit': strengthUnit,
    'basisValueMicros': basisValueMicros,
    'basisUnit': basisUnit,
  };

  factory LanMedicineIngredient.fromJson(Map<String, dynamic> json) {
    return LanMedicineIngredient(
      ingredientId: (json['ingredientId'] as num).toInt(),
      canonicalName: json['canonicalName']?.toString() ?? '',
      nameAr: json['nameAr']?.toString(),
      nameFr: json['nameFr']?.toString(),
      strengthValueMicros: (json['strengthValueMicros'] as num).toInt(),
      strengthUnit: json['strengthUnit']?.toString() ?? '',
      basisValueMicros: (json['basisValueMicros'] as num?)?.toInt(),
      basisUnit: json['basisUnit']?.toString(),
    );
  }
}

class LanMedicineProfile {
  final String dosageForm;
  final String? administrationRoute;
  final bool substitutionEligible;
  final List<LanMedicineIngredient> ingredients;

  const LanMedicineProfile({
    required this.dosageForm,
    this.administrationRoute,
    required this.substitutionEligible,
    required this.ingredients,
  });

  Map<String, dynamic> toJson() => {
    'dosageForm': dosageForm,
    'administrationRoute': administrationRoute,
    'substitutionEligible': substitutionEligible,
    'ingredients': ingredients.map((row) => row.toJson()).toList(),
  };

  factory LanMedicineProfile.fromJson(Map<String, dynamic> json) {
    return LanMedicineProfile(
      dosageForm: json['dosageForm']?.toString() ?? '',
      administrationRoute: json['administrationRoute']?.toString(),
      substitutionEligible: json['substitutionEligible'] == true,
      ingredients: (json['ingredients'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanMedicineIngredient.fromJson)
          .toList(growable: false),
    );
  }
}

class LanCatalogProduct {
  final int id;
  final String name;
  final String? sku;
  final String? barcode;
  final int priceCents;
  final int? wholesalePriceCents;
  final int stockQuantity;
  final bool hasVariants;
  final bool isTaxable;
  final int salesTaxRateBps;
  final bool trackInventory;
  final String measurementType;
  final int quantityScale;
  final bool hasImage;
  final List<LanCatalogVariant> variants;
  final LanMedicineProfile? medicine;

  /// Present only when the catalog query exactly matched a saved supplier
  /// source code. Old clients ignore these optional fields.
  final int? matchedSupplierIdentityId;
  final int? matchedCanonicalVariantId;
  final String? matchedSupplierSourceSku;
  final String? matchedSupplierName;
  final String? matchedConsignmentLayerId;
  final String? matchedConsignmentSourceCode;

  // Management-only fields. The ordinary sales catalog never serializes
  // these, and cost is exposed only with the dedicated permission.
  final String? nameAr;
  final String? nameFr;
  final String? description;
  final int? costCents;
  final int? lastPurchasePriceCents;
  final int minQuantity;
  final int? categoryId;
  final int? supplierId;
  final int? currencyId;
  final int purchaseTaxRateBps;
  final bool isActive;
  final String costingMethod;
  final String inventoryTrackingType;

  const LanCatalogProduct({
    required this.id,
    required this.name,
    this.sku,
    this.barcode,
    required this.priceCents,
    this.wholesalePriceCents,
    required this.stockQuantity,
    required this.hasVariants,
    required this.isTaxable,
    required this.salesTaxRateBps,
    required this.trackInventory,
    required this.measurementType,
    required this.quantityScale,
    this.hasImage = false,
    this.variants = const [],
    this.medicine,
    this.matchedSupplierIdentityId,
    this.matchedCanonicalVariantId,
    this.matchedSupplierSourceSku,
    this.matchedSupplierName,
    this.matchedConsignmentLayerId,
    this.matchedConsignmentSourceCode,
    this.nameAr,
    this.nameFr,
    this.description,
    this.costCents,
    this.lastPurchasePriceCents,
    this.minQuantity = 0,
    this.categoryId,
    this.supplierId,
    this.currencyId,
    this.purchaseTaxRateBps = 0,
    this.isActive = true,
    this.costingMethod = 'wac',
    this.inventoryTrackingType = 'standard',
  });

  Map<String, dynamic> toJson({
    bool includeManagement = false,
    bool includeCost = false,
  }) => {
    'id': id,
    'name': name,
    'sku': sku,
    'barcode': barcode,
    'priceCents': priceCents,
    'wholesalePriceCents': wholesalePriceCents,
    'stockQuantity': stockQuantity,
    'hasVariants': hasVariants,
    'isTaxable': isTaxable,
    'salesTaxRateBps': salesTaxRateBps,
    'trackInventory': trackInventory,
    'measurementType': measurementType,
    'quantityScale': quantityScale,
    'hasImage': hasImage,
    'variants': variants
        .map((value) => value.toJson(includeCost: includeCost))
        .toList(),
    'medicine': medicine?.toJson(),
    if (matchedSupplierIdentityId != null)
      'matchedSupplierIdentityId': matchedSupplierIdentityId,
    if (matchedCanonicalVariantId != null)
      'matchedCanonicalVariantId': matchedCanonicalVariantId,
    if (matchedSupplierSourceSku != null)
      'matchedSupplierSourceSku': matchedSupplierSourceSku,
    if (matchedSupplierName != null) 'matchedSupplierName': matchedSupplierName,
    if (matchedConsignmentLayerId != null)
      'matchedConsignmentLayerId': matchedConsignmentLayerId,
    if (matchedConsignmentSourceCode != null)
      'matchedConsignmentSourceCode': matchedConsignmentSourceCode,
    if (includeManagement) ...{
      'nameAr': nameAr,
      'nameFr': nameFr,
      'description': description,
      if (includeCost) 'costCents': costCents,
      if (includeCost) 'lastPurchasePriceCents': lastPurchasePriceCents,
      'minQuantity': minQuantity,
      'categoryId': categoryId,
      'supplierId': supplierId,
      'currencyId': currencyId,
      'purchaseTaxRateBps': purchaseTaxRateBps,
      'isActive': isActive,
      'costingMethod': costingMethod,
      'inventoryTrackingType': inventoryTrackingType,
    },
  };

  factory LanCatalogProduct.fromJson(Map<String, dynamic> json) {
    return LanCatalogProduct(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      priceCents: (json['priceCents'] as num).toInt(),
      wholesalePriceCents: (json['wholesalePriceCents'] as num?)?.toInt(),
      stockQuantity: (json['stockQuantity'] as num).toInt(),
      hasVariants: json['hasVariants'] == true,
      isTaxable: json['isTaxable'] == true,
      salesTaxRateBps: (json['salesTaxRateBps'] as num?)?.toInt() ?? 0,
      trackInventory: json['trackInventory'] != false,
      measurementType: json['measurementType']?.toString() ?? 'piece',
      quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
      hasImage: json['hasImage'] == true,
      variants: (json['variants'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanCatalogVariant.fromJson)
          .toList(growable: false),
      medicine: json['medicine'] is Map<String, dynamic>
          ? LanMedicineProfile.fromJson(
              json['medicine'] as Map<String, dynamic>,
            )
          : null,
      matchedSupplierIdentityId: (json['matchedSupplierIdentityId'] as num?)
          ?.toInt(),
      matchedCanonicalVariantId: (json['matchedCanonicalVariantId'] as num?)
          ?.toInt(),
      matchedSupplierSourceSku: json['matchedSupplierSourceSku']?.toString(),
      matchedSupplierName: json['matchedSupplierName']?.toString(),
      matchedConsignmentLayerId: json['matchedConsignmentLayerId']?.toString(),
      matchedConsignmentSourceCode: json['matchedConsignmentSourceCode']
          ?.toString(),
      nameAr: json['nameAr']?.toString(),
      nameFr: json['nameFr']?.toString(),
      description: json['description']?.toString(),
      costCents: (json['costCents'] as num?)?.toInt(),
      lastPurchasePriceCents: (json['lastPurchasePriceCents'] as num?)?.toInt(),
      minQuantity: (json['minQuantity'] as num?)?.toInt() ?? 0,
      categoryId: (json['categoryId'] as num?)?.toInt(),
      supplierId: (json['supplierId'] as num?)?.toInt(),
      currencyId: (json['currencyId'] as num?)?.toInt(),
      purchaseTaxRateBps: (json['purchaseTaxRateBps'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] != false,
      costingMethod: json['costingMethod']?.toString() ?? 'wac',
      inventoryTrackingType:
          json['inventoryTrackingType']?.toString() ?? 'standard',
    );
  }
}

/// Read-only, freshly loaded checkout information from the branch master.
class LanCustomerCheckout {
  final int customerId;
  final int currencyId;
  final String currencyCode;
  final int balanceCents;
  final int pointsBalance;
  const LanCustomerCheckout({
    required this.customerId,
    required this.currencyId,
    required this.currencyCode,
    required this.balanceCents,
    required this.pointsBalance,
  });
  Map<String, dynamic> toJson() => {
    'customerId': customerId,
    'currencyId': currencyId,
    'currencyCode': currencyCode,
    'balanceCents': balanceCents,
    'pointsBalance': pointsBalance,
  };
  factory LanCustomerCheckout.fromJson(Map<String, dynamic> json) =>
      LanCustomerCheckout(
        customerId: (json['customerId'] as num).toInt(),
        currencyId: (json['currencyId'] as num).toInt(),
        currencyCode: json['currencyCode'] as String,
        balanceCents: (json['balanceCents'] as num).toInt(),
        pointsBalance: (json['pointsBalance'] as num).toInt(),
      );
}

class LanCustomerSummary {
  final int id;
  final String name;
  final String? phone;
  final String segment;
  final int balanceCents;

  const LanCustomerSummary({
    required this.id,
    required this.name,
    this.phone,
    required this.segment,
    required this.balanceCents,
  });

  /// Directory responses intentionally omit financial balances. The live
  /// checkout endpoint is the only LAN sales API allowed to disclose them.
  Map<String, dynamic> toJson({bool includeBalance = false}) => {
    'id': id,
    'name': name,
    'phone': phone,
    'segment': segment,
    if (includeBalance) 'balanceCents': balanceCents,
  };

  factory LanCustomerSummary.fromJson(Map<String, dynamic> json) {
    return LanCustomerSummary(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString(),
      segment: json['segment']?.toString() ?? 'retail',
      balanceCents: (json['balanceCents'] as num?)?.toInt() ?? 0,
    );
  }
}

class LanEmployeeSummary {
  final int id;
  final String name;
  final String? position;

  const LanEmployeeSummary({
    required this.id,
    required this.name,
    this.position,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'position': position,
  };

  factory LanEmployeeSummary.fromJson(Map<String, dynamic> json) {
    return LanEmployeeSummary(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      position: json['position']?.toString(),
    );
  }
}

class LanCashierShiftSnapshot {
  final int id;
  final String shiftNumber;
  final String status;
  final int cashierUserId;
  final int? employeeId;
  final String cashierName;
  final String currencyCode;
  final String currencySymbol;
  final int currencyDecimalDigits;
  final bool currencySymbolAfter;
  final int openingCashCents;
  final int expectedCashCents;
  final int salesCount;
  final int returnsCount;
  final DateTime openedAt;
  final DateTime? closedAt;

  const LanCashierShiftSnapshot({
    required this.id,
    required this.shiftNumber,
    required this.status,
    required this.cashierUserId,
    this.employeeId,
    required this.cashierName,
    required this.currencyCode,
    required this.currencySymbol,
    this.currencyDecimalDigits = 2,
    this.currencySymbolAfter = false,
    required this.openingCashCents,
    required this.expectedCashCents,
    required this.salesCount,
    required this.returnsCount,
    required this.openedAt,
    this.closedAt,
  });

  bool get isOpen => status == 'open';

  Map<String, dynamic> toJson() => {
    'id': id,
    'shiftNumber': shiftNumber,
    'status': status,
    'cashierUserId': cashierUserId,
    'employeeId': employeeId,
    'cashierName': cashierName,
    'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
    'currencyDecimalDigits': currencyDecimalDigits,
    'currencySymbolAfter': currencySymbolAfter,
    'openingCashCents': openingCashCents,
    'expectedCashCents': expectedCashCents,
    'salesCount': salesCount,
    'returnsCount': returnsCount,
    'openedAt': openedAt.toUtc().toIso8601String(),
    'closedAt': closedAt?.toUtc().toIso8601String(),
  };

  factory LanCashierShiftSnapshot.fromJson(Map<String, dynamic> json) {
    return LanCashierShiftSnapshot(
      id: (json['id'] as num).toInt(),
      shiftNumber: json['shiftNumber']?.toString() ?? '',
      status: json['status']?.toString() ?? 'closed',
      cashierUserId: (json['cashierUserId'] as num).toInt(),
      employeeId: (json['employeeId'] as num?)?.toInt(),
      cashierName: json['cashierName']?.toString() ?? '',
      currencyCode: json['currencyCode']?.toString() ?? '',
      currencySymbol: json['currencySymbol']?.toString() ?? '',
      currencyDecimalDigits:
          (json['currencyDecimalDigits'] as num?)?.toInt() ?? 2,
      currencySymbolAfter: json['currencySymbolAfter'] == true,
      openingCashCents: (json['openingCashCents'] as num?)?.toInt() ?? 0,
      expectedCashCents: (json['expectedCashCents'] as num?)?.toInt() ?? 0,
      salesCount: (json['salesCount'] as num?)?.toInt() ?? 0,
      returnsCount: (json['returnsCount'] as num?)?.toInt() ?? 0,
      openedAt: DateTime.parse(json['openedAt'].toString()),
      closedAt: json['closedAt'] == null
          ? null
          : DateTime.tryParse(json['closedAt'].toString()),
    );
  }
}

class LanCatalogPage {
  final List<LanCatalogProduct> products;
  final int offset;
  final int limit;
  final bool hasMore;
  final int currencyId;
  final String currencyCode;
  final String currencySymbol;
  final int currencyDecimalDigits;
  final bool currencySymbolAfter;
  final bool enableTaxCalculations;
  final int defaultSalesTaxRateBps;
  final int? defaultPurchaseTaxRateBps;
  final bool taxInclusivePricing;
  final bool allowNegativeStock;
  final bool allowPartialPayments;
  final bool requireCustomerForSales;
  final bool allowDiscounts;
  final double maxDiscountPercent;
  final bool allowBelowCostSales;
  final String? receiptHeaderText;
  final String? receiptFooterText;
  final bool enablePharmacyFeatures;
  final bool enablePromotions;
  final List<Map<String, dynamic>> promotionRules;
  final List<LanCatalogProduct> promotionProducts;

  const LanCatalogPage({
    required this.products,
    required this.offset,
    required this.limit,
    required this.hasMore,
    required this.currencyId,
    required this.currencyCode,
    required this.currencySymbol,
    this.currencyDecimalDigits = 2,
    this.currencySymbolAfter = false,
    required this.enableTaxCalculations,
    required this.defaultSalesTaxRateBps,
    this.defaultPurchaseTaxRateBps,
    required this.taxInclusivePricing,
    required this.allowNegativeStock,
    required this.allowPartialPayments,
    required this.requireCustomerForSales,
    this.allowDiscounts = true,
    this.maxDiscountPercent = 100,
    this.allowBelowCostSales = false,
    this.receiptHeaderText,
    this.receiptFooterText,
    this.enablePharmacyFeatures = false,
    this.enablePromotions = false,
    this.promotionRules = const [],
    this.promotionProducts = const [],
  });

  Map<String, dynamic> toJson({
    bool includeManagement = false,
    bool includeCost = false,
  }) => {
    'products': products
        .map(
          (value) => value.toJson(
            includeManagement: includeManagement,
            includeCost: includeCost,
          ),
        )
        .toList(),
    'offset': offset,
    'limit': limit,
    'hasMore': hasMore,
    'currencyId': currencyId,
    'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
    'currencyDecimalDigits': currencyDecimalDigits,
    'currencySymbolAfter': currencySymbolAfter,
    'enableTaxCalculations': enableTaxCalculations,
    'defaultSalesTaxRateBps': defaultSalesTaxRateBps,
    'defaultPurchaseTaxRateBps': defaultPurchaseTaxRateBps,
    'taxInclusivePricing': taxInclusivePricing,
    'allowNegativeStock': allowNegativeStock,
    'allowPartialPayments': allowPartialPayments,
    'requireCustomerForSales': requireCustomerForSales,
    'allowDiscounts': allowDiscounts,
    'maxDiscountPercent': maxDiscountPercent,
    'allowBelowCostSales': allowBelowCostSales,
    'receiptHeaderText': receiptHeaderText,
    'receiptFooterText': receiptFooterText,
    'enablePharmacyFeatures': enablePharmacyFeatures,
    'enablePromotions': enablePromotions,
    'promotionRules': promotionRules,
    'promotionProducts': promotionProducts
        .map(
          (value) => value.toJson(
            includeManagement: includeManagement,
            includeCost: includeCost,
          ),
        )
        .toList(growable: false),
  };

  factory LanCatalogPage.fromJson(Map<String, dynamic> json) {
    return LanCatalogPage(
      products: (json['products'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanCatalogProduct.fromJson)
          .toList(growable: false),
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 100,
      hasMore: json['hasMore'] == true,
      currencyId: (json['currencyId'] as num?)?.toInt() ?? 1,
      currencyCode: json['currencyCode']?.toString() ?? 'USD',
      currencySymbol: json['currencySymbol']?.toString() ?? r'$',
      currencyDecimalDigits:
          (json['currencyDecimalDigits'] as num?)?.toInt() ?? 2,
      currencySymbolAfter: json['currencySymbolAfter'] == true,
      enableTaxCalculations: json['enableTaxCalculations'] != false,
      defaultPurchaseTaxRateBps: (json['defaultPurchaseTaxRateBps'] as num?)
          ?.toInt(),
      defaultSalesTaxRateBps:
          (json['defaultSalesTaxRateBps'] as num?)?.toInt() ?? 0,
      taxInclusivePricing: json['taxInclusivePricing'] == true,
      allowNegativeStock: json['allowNegativeStock'] == true,
      allowPartialPayments: json['allowPartialPayments'] == true,
      requireCustomerForSales: json['requireCustomerForSales'] == true,
      allowDiscounts: json['allowDiscounts'] != false,
      maxDiscountPercent:
          (json['maxDiscountPercent'] as num?)?.toDouble() ?? 100,
      allowBelowCostSales: json['allowBelowCostSales'] == true,
      receiptHeaderText: json.containsKey('receiptHeaderText')
          ? json['receiptHeaderText']?.toString() ?? ''
          : null,
      receiptFooterText: json.containsKey('receiptFooterText')
          ? json['receiptFooterText']?.toString() ?? ''
          : null,
      enablePharmacyFeatures: json['enablePharmacyFeatures'] == true,
      enablePromotions: json['enablePromotions'] == true,
      promotionRules: (json['promotionRules'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
      promotionProducts:
          (json['promotionProducts'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(LanCatalogProduct.fromJson)
              .toList(growable: false),
    );
  }
}

class LanMedicineAlternativesResult {
  final int sourceProductId;
  final List<LanCatalogProduct> alternatives;

  const LanMedicineAlternativesResult({
    required this.sourceProductId,
    required this.alternatives,
  });

  Map<String, dynamic> toJson() => {
    'sourceProductId': sourceProductId,
    'alternatives': alternatives.map((row) => row.toJson()).toList(),
  };

  factory LanMedicineAlternativesResult.fromJson(Map<String, dynamic> json) {
    return LanMedicineAlternativesResult(
      sourceProductId: (json['sourceProductId'] as num).toInt(),
      alternatives: (json['alternatives'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanCatalogProduct.fromJson)
          .toList(growable: false),
    );
  }
}

class LanReturnableSaleSummary {
  final int saleId;
  final String invoiceNumber;
  final int? customerId;
  final String? customerName;
  final DateTime saleDate;
  final int totalCents;
  final String paymentMethod;
  final String currencyCode;
  final String currencySymbol;
  final int currencyId;
  final bool taxInclusiveAtPost;
  final int returnableLineCount;

  const LanReturnableSaleSummary({
    required this.saleId,
    required this.invoiceNumber,
    this.customerId,
    this.customerName,
    required this.saleDate,
    required this.totalCents,
    required this.paymentMethod,
    required this.currencyCode,
    required this.currencySymbol,
    this.currencyId = 1,
    this.taxInclusiveAtPost = false,
    required this.returnableLineCount,
  });

  Map<String, dynamic> toJson() => {
    'saleId': saleId,
    'invoiceNumber': invoiceNumber,
    'customerId': customerId,
    'customerName': customerName,
    'saleDate': saleDate.toUtc().toIso8601String(),
    'totalCents': totalCents,
    'paymentMethod': paymentMethod,
    'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
    'currencyId': currencyId,
    'taxInclusiveAtPost': taxInclusiveAtPost,
    'returnableLineCount': returnableLineCount,
  };

  factory LanReturnableSaleSummary.fromJson(Map<String, dynamic> json) {
    return LanReturnableSaleSummary(
      saleId: (json['saleId'] as num).toInt(),
      invoiceNumber: json['invoiceNumber']?.toString() ?? '',
      customerId: (json['customerId'] as num?)?.toInt(),
      customerName: json['customerName']?.toString(),
      saleDate: DateTime.parse(json['saleDate'].toString()),
      totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
      paymentMethod: json['paymentMethod']?.toString() ?? 'cash',
      currencyCode: json['currencyCode']?.toString() ?? '',
      currencySymbol: json['currencySymbol']?.toString() ?? '',
      currencyId: (json['currencyId'] as num?)?.toInt() ?? 1,
      taxInclusiveAtPost: json['taxInclusiveAtPost'] == true,
      returnableLineCount: (json['returnableLineCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class LanReturnableSalesPage {
  final List<LanReturnableSaleSummary> sales;
  final int offset;
  final int limit;
  final bool hasMore;

  const LanReturnableSalesPage({
    required this.sales,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  Map<String, dynamic> toJson() => {
    'sales': sales.map((value) => value.toJson()).toList(),
    'offset': offset,
    'limit': limit,
    'hasMore': hasMore,
  };

  factory LanReturnableSalesPage.fromJson(Map<String, dynamic> json) {
    return LanReturnableSalesPage(
      sales: (json['sales'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanReturnableSaleSummary.fromJson)
          .toList(growable: false),
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      limit: (json['limit'] as num?)?.toInt() ?? 50,
      hasMore: json['hasMore'] == true,
    );
  }
}

class LanReturnableSaleLine {
  final int saleItemId;
  final int productId;
  final int? variantId;
  final String productName;
  final String? variantSku;
  final String? colorName;
  final String? sizeName;
  final int originalQuantity;
  final int returnedQuantity;
  final int availableQuantity;
  final int quantityScale;
  final String measurementType;
  final int unitPriceCents;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int linkedReturnedQuantity;
  final int linkedReturnedSubtotalCents;
  final int linkedReturnedDiscountCents;
  final int linkedReturnedTaxCents;
  final int linkedReturnedRefundCents;

  const LanReturnableSaleLine({
    required this.saleItemId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantSku,
    this.colorName,
    this.sizeName,
    required this.originalQuantity,
    required this.returnedQuantity,
    required this.availableQuantity,
    required this.quantityScale,
    required this.measurementType,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    this.linkedReturnedQuantity = 0,
    this.linkedReturnedSubtotalCents = 0,
    this.linkedReturnedDiscountCents = 0,
    this.linkedReturnedTaxCents = 0,
    this.linkedReturnedRefundCents = 0,
  });

  Map<String, dynamic> toJson() => {
    'saleItemId': saleItemId,
    'productId': productId,
    'variantId': variantId,
    'productName': productName,
    'variantSku': variantSku,
    'colorName': colorName,
    'sizeName': sizeName,
    'originalQuantity': originalQuantity,
    'returnedQuantity': returnedQuantity,
    'availableQuantity': availableQuantity,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
    'unitPriceCents': unitPriceCents,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'linkedReturnedQuantity': linkedReturnedQuantity,
    'linkedReturnedSubtotalCents': linkedReturnedSubtotalCents,
    'linkedReturnedDiscountCents': linkedReturnedDiscountCents,
    'linkedReturnedTaxCents': linkedReturnedTaxCents,
    'linkedReturnedRefundCents': linkedReturnedRefundCents,
  };

  factory LanReturnableSaleLine.fromJson(Map<String, dynamic> json) {
    return LanReturnableSaleLine(
      saleItemId: (json['saleItemId'] as num).toInt(),
      productId: (json['productId'] as num).toInt(),
      variantId: (json['variantId'] as num?)?.toInt(),
      productName: json['productName']?.toString() ?? '',
      variantSku: json['variantSku']?.toString(),
      colorName: json['colorName']?.toString(),
      sizeName: json['sizeName']?.toString(),
      originalQuantity: (json['originalQuantity'] as num?)?.toInt() ?? 0,
      returnedQuantity: (json['returnedQuantity'] as num?)?.toInt() ?? 0,
      availableQuantity: (json['availableQuantity'] as num?)?.toInt() ?? 0,
      quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
      measurementType: json['measurementType']?.toString() ?? 'piece',
      unitPriceCents: (json['unitPriceCents'] as num?)?.toInt() ?? 0,
      subtotalCents: (json['subtotalCents'] as num?)?.toInt() ?? 0,
      discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
      taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
      totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
      linkedReturnedQuantity:
          (json['linkedReturnedQuantity'] as num?)?.toInt() ?? 0,
      linkedReturnedSubtotalCents:
          (json['linkedReturnedSubtotalCents'] as num?)?.toInt() ?? 0,
      linkedReturnedDiscountCents:
          (json['linkedReturnedDiscountCents'] as num?)?.toInt() ?? 0,
      linkedReturnedTaxCents:
          (json['linkedReturnedTaxCents'] as num?)?.toInt() ?? 0,
      linkedReturnedRefundCents:
          (json['linkedReturnedRefundCents'] as num?)?.toInt() ?? 0,
    );
  }
}

class LanReturnableSaleDetails {
  final LanReturnableSaleSummary sale;
  final List<LanReturnableSaleLine> lines;
  final List<SalePromotionSnapshot> promotionApplications;

  const LanReturnableSaleDetails({
    required this.sale,
    required this.lines,
    this.promotionApplications = const [],
  });

  Map<String, dynamic> toJson() => {
    'sale': sale.toJson(),
    'lines': lines.map((value) => value.toJson()).toList(),
    'promotionApplications': promotionApplications
        .map((value) => value.toTransportMap())
        .toList(growable: false),
  };

  factory LanReturnableSaleDetails.fromJson(Map<String, dynamic> json) {
    return LanReturnableSaleDetails(
      sale: LanReturnableSaleSummary.fromJson(
        json['sale'] as Map<String, dynamic>,
      ),
      lines: (json['lines'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanReturnableSaleLine.fromJson)
          .toList(growable: false),
      promotionApplications:
          (json['promotionApplications'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(SalePromotionSnapshot.fromTransportMap)
              .toList(growable: false),
    );
  }
}

class LanSaleReturnSummary {
  final int id;
  final int saleId;
  final String? saleInvoiceNumber;
  final String? customerName;
  final String? customerPhone;
  final int? customerId;
  final String returnNumber;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int currencyId;
  final String status;
  final String dispositionType;
  final String refundMethod;
  final String? reason;
  final DateTime returnDate;
  final DateTime createdAt;
  final bool isAdjustment;
  final String unifiedId;

  const LanSaleReturnSummary({
    required this.id,
    required this.saleId,
    this.saleInvoiceNumber,
    this.customerName,
    this.customerPhone,
    this.customerId,
    required this.returnNumber,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.currencyId,
    required this.status,
    required this.dispositionType,
    required this.refundMethod,
    this.reason,
    required this.returnDate,
    required this.createdAt,
    required this.isAdjustment,
    required this.unifiedId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'saleId': saleId,
    'saleInvoiceNumber': saleInvoiceNumber,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'customerId': customerId,
    'returnNumber': returnNumber,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'currencyId': currencyId,
    'status': status,
    'dispositionType': dispositionType,
    'refundMethod': refundMethod,
    'reason': reason,
    'returnDate': returnDate.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'isAdjustment': isAdjustment,
    'unifiedId': unifiedId,
  };

  factory LanSaleReturnSummary.fromJson(Map<String, dynamic> json) =>
      LanSaleReturnSummary(
        id: (json['id'] as num).toInt(),
        saleId: (json['saleId'] as num?)?.toInt() ?? 0,
        saleInvoiceNumber: json['saleInvoiceNumber']?.toString(),
        customerName: json['customerName']?.toString(),
        customerPhone: json['customerPhone']?.toString(),
        customerId: (json['customerId'] as num?)?.toInt(),
        returnNumber: json['returnNumber']?.toString() ?? '',
        subtotalCents: (json['subtotalCents'] as num?)?.toInt() ?? 0,
        discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
        taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
        currencyId: (json['currencyId'] as num?)?.toInt() ?? 1,
        status: json['status']?.toString() ?? 'posted',
        dispositionType: json['dispositionType']?.toString() ?? 'restock',
        refundMethod: json['refundMethod']?.toString() ?? 'cash',
        reason: json['reason']?.toString(),
        returnDate: DateTime.parse(json['returnDate'].toString()),
        createdAt: DateTime.parse(json['createdAt'].toString()),
        isAdjustment: json['isAdjustment'] == true,
        unifiedId: json['unifiedId']?.toString() ?? '',
      );
}

class LanSaleReturnsPage {
  final List<LanSaleReturnSummary> returns;
  final int offset;
  final int limit;
  final bool hasMore;

  const LanSaleReturnsPage({
    required this.returns,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  Map<String, dynamic> toJson() => {
    'returns': returns.map((value) => value.toJson()).toList(),
    'offset': offset,
    'limit': limit,
    'hasMore': hasMore,
  };

  factory LanSaleReturnsPage.fromJson(Map<String, dynamic> json) =>
      LanSaleReturnsPage(
        returns: (json['returns'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanSaleReturnSummary.fromJson)
            .toList(growable: false),
        offset: (json['offset'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 100,
        hasMore: json['hasMore'] == true,
      );
}

class LanSaleReturnDetailLine {
  final int id;
  final int returnId;
  final int? saleItemId;
  final int productId;
  final int? variantId;
  final String productName;
  final String? productSku;
  final String? variantSku;
  final String? variantBarcode;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final int? unitPriceCents;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final String? reason;
  final String dispositionType;
  final DateTime createdAt;

  const LanSaleReturnDetailLine({
    required this.id,
    required this.returnId,
    this.saleItemId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.productSku,
    this.variantSku,
    this.variantBarcode,
    this.colorName,
    this.colorHex,
    this.sizeName,
    required this.quantity,
    required this.quantityScale,
    required this.measurementType,
    this.unitPriceCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    this.reason,
    required this.dispositionType,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'returnId': returnId,
    'saleItemId': saleItemId,
    'productId': productId,
    'variantId': variantId,
    'productName': productName,
    'productSku': productSku,
    'variantSku': variantSku,
    'variantBarcode': variantBarcode,
    'colorName': colorName,
    'colorHex': colorHex,
    'sizeName': sizeName,
    'quantity': quantity,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
    'unitPriceCents': unitPriceCents,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'reason': reason,
    'dispositionType': dispositionType,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory LanSaleReturnDetailLine.fromJson(Map<String, dynamic> json) =>
      LanSaleReturnDetailLine(
        id: (json['id'] as num).toInt(),
        returnId: (json['returnId'] as num).toInt(),
        saleItemId: (json['saleItemId'] as num?)?.toInt(),
        productId: (json['productId'] as num?)?.toInt() ?? 0,
        variantId: (json['variantId'] as num?)?.toInt(),
        productName: json['productName']?.toString() ?? '',
        productSku: json['productSku']?.toString(),
        variantSku: json['variantSku']?.toString(),
        variantBarcode: json['variantBarcode']?.toString(),
        colorName: json['colorName']?.toString(),
        colorHex: json['colorHex']?.toString(),
        sizeName: json['sizeName']?.toString(),
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
        measurementType: json['measurementType']?.toString() ?? 'piece',
        unitPriceCents: (json['unitPriceCents'] as num?)?.toInt(),
        subtotalCents: (json['subtotalCents'] as num?)?.toInt() ?? 0,
        discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
        taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
        reason: json['reason']?.toString(),
        dispositionType: json['dispositionType']?.toString() ?? 'restock',
        createdAt: DateTime.parse(json['createdAt'].toString()),
      );
}

class LanSaleReturnDetails {
  final LanSaleReturnSummary summary;
  final List<LanSaleReturnDetailLine> lines;
  final String currencyCode;
  final String currencySymbol;
  final int currencyDecimalDigits;
  final bool currencySymbolAfter;
  final String? employeeName;
  final String? returnMode;
  final String? notes;
  final List<SalePromotionSnapshot> promotionApplications;

  const LanSaleReturnDetails({
    required this.summary,
    required this.lines,
    required this.currencyCode,
    required this.currencySymbol,
    required this.currencyDecimalDigits,
    required this.currencySymbolAfter,
    this.employeeName,
    this.returnMode,
    this.notes,
    this.promotionApplications = const [],
  });

  Map<String, dynamic> toJson() => {
    'summary': summary.toJson(),
    'lines': lines.map((value) => value.toJson()).toList(),
    'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
    'currencyDecimalDigits': currencyDecimalDigits,
    'currencySymbolAfter': currencySymbolAfter,
    'employeeName': employeeName,
    'returnMode': returnMode,
    'notes': notes,
    'promotionApplications': promotionApplications
        .map((value) => value.toTransportMap())
        .toList(growable: false),
  };

  factory LanSaleReturnDetails.fromJson(Map<String, dynamic> json) =>
      LanSaleReturnDetails(
        summary: LanSaleReturnSummary.fromJson(
          json['summary'] as Map<String, dynamic>,
        ),
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanSaleReturnDetailLine.fromJson)
            .toList(growable: false),
        currencyCode: json['currencyCode']?.toString() ?? '',
        currencySymbol: json['currencySymbol']?.toString() ?? '',
        currencyDecimalDigits:
            (json['currencyDecimalDigits'] as num?)?.toInt() ?? 2,
        currencySymbolAfter: json['currencySymbolAfter'] == true,
        employeeName: json['employeeName']?.toString(),
        returnMode: json['returnMode']?.toString(),
        notes: json['notes']?.toString(),
        promotionApplications:
            (json['promotionApplications'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(SalePromotionSnapshot.fromTransportMap)
                .toList(growable: false),
      );
}

class LanSaleReturnLineRequest {
  final int saleItemId;
  final int quantity;
  final String? reason;

  const LanSaleReturnLineRequest({
    required this.saleItemId,
    required this.quantity,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    'saleItemId': saleItemId,
    'quantity': quantity,
    'reason': reason,
  };

  factory LanSaleReturnLineRequest.fromJson(Map<String, dynamic> json) =>
      LanSaleReturnLineRequest(
        saleItemId: (json['saleItemId'] as num).toInt(),
        quantity: (json['quantity'] as num).toInt(),
        reason: json['reason']?.toString(),
      );
}

class LanSaleReturnRequest {
  final String idempotencyKey;
  final int saleId;
  final String dispositionType;
  final String refundMethod;
  final String? reason;
  final DateTime? dueDate;
  final List<LanSaleReturnLineRequest> lines;
  final List<LanCheckoutPaymentRequest> payments;

  const LanSaleReturnRequest({
    required this.idempotencyKey,
    required this.saleId,
    required this.dispositionType,
    required this.refundMethod,
    this.reason,
    this.dueDate,
    required this.lines,
    this.payments = const [],
  });

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'saleId': saleId,
    'dispositionType': dispositionType,
    'refundMethod': refundMethod,
    'reason': reason,
    'dueDate': dueDate?.toUtc().toIso8601String(),
    'lines': lines.map((value) => value.toJson()).toList(),
    'payments': payments.map((value) => value.toJson()).toList(),
  };

  factory LanSaleReturnRequest.fromJson(Map<String, dynamic> json) =>
      LanSaleReturnRequest(
        idempotencyKey: json['idempotencyKey']?.toString() ?? '',
        saleId: (json['saleId'] as num).toInt(),
        dispositionType: json['dispositionType']?.toString() ?? 'restock',
        refundMethod: json['refundMethod']?.toString() ?? 'cash',
        reason: json['reason']?.toString(),
        dueDate: json['dueDate'] == null
            ? null
            : DateTime.tryParse(json['dueDate'].toString()),
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanSaleReturnLineRequest.fromJson)
            .toList(growable: false),
        payments: (json['payments'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanCheckoutPaymentRequest.fromJson)
            .toList(growable: false),
      );
}

class LanSaleReturnResult {
  final int returnId;
  final String returnNumber;
  final int totalCents;
  final bool duplicate;

  const LanSaleReturnResult({
    required this.returnId,
    required this.returnNumber,
    required this.totalCents,
    this.duplicate = false,
  });

  Map<String, dynamic> toJson() => {
    'returnId': returnId,
    'returnNumber': returnNumber,
    'totalCents': totalCents,
    'duplicate': duplicate,
  };

  factory LanSaleReturnResult.fromJson(Map<String, dynamic> json) =>
      LanSaleReturnResult(
        returnId: (json['returnId'] as num).toInt(),
        returnNumber: json['returnNumber']?.toString() ?? '',
        totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
        duplicate: json['duplicate'] == true,
      );
}

/// A single, proven stock balance on the branch master.
///
/// Ownership is enterprise, consignment, or unverified. An unverified source
/// is deliberately kept separate and cannot be assigned to a supplier by
/// inference.
class LanInventoryStockSource {
  const LanInventoryStockSource({
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.quantityScale,
    required this.measurementType,
    required this.ownership,
    required this.variantLabel,
    this.supplierId,
    this.supplierName,
    this.supplierIdentityId,
    this.consignmentLayerId,
    this.sourceCode,
    this.receiptNumber,
    this.batchNumber,
  });

  final int productId;
  final int variantId;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final String ownership;
  final String variantLabel;
  final int? supplierId;
  final String? supplierName;
  final int? supplierIdentityId;
  final String? consignmentLayerId;
  final String? sourceCode;
  final String? receiptNumber;
  final String? batchNumber;

  bool get isConsignment => ownership == 'consignment';
  bool get isVerified =>
      supplierIdentityId != null || consignmentLayerId != null;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variantId': variantId,
    'quantity': quantity,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
    'ownership': ownership,
    'variantLabel': variantLabel,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'supplierIdentityId': supplierIdentityId,
    'consignmentLayerId': consignmentLayerId,
    'sourceCode': sourceCode,
    'receiptNumber': receiptNumber,
    'batchNumber': batchNumber,
  };

  factory LanInventoryStockSource.fromJson(Map<String, dynamic> json) =>
      LanInventoryStockSource(
        productId: (json['productId'] as num).toInt(),
        variantId: (json['variantId'] as num).toInt(),
        quantity: (json['quantity'] as num).toInt(),
        quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
        measurementType: json['measurementType']?.toString() ?? 'piece',
        ownership: json['ownership']?.toString() ?? 'unverified',
        variantLabel: json['variantLabel']?.toString() ?? '',
        supplierId: (json['supplierId'] as num?)?.toInt(),
        supplierName: json['supplierName']?.toString(),
        supplierIdentityId: (json['supplierIdentityId'] as num?)?.toInt(),
        consignmentLayerId: json['consignmentLayerId']?.toString(),
        sourceCode: json['sourceCode']?.toString(),
        receiptNumber: json['receiptNumber']?.toString(),
        batchNumber: json['batchNumber']?.toString(),
      );
}

class LanProductStockSourceSnapshot {
  const LanProductStockSourceSnapshot({
    required this.productId,
    required this.warehouseId,
    required this.physicalQuantity,
    required this.enterpriseQuantity,
    required this.consignmentQuantity,
    required this.quantityScale,
    required this.measurementType,
    required this.sources,
    required this.reconciled,
  });

  final int productId;
  final String warehouseId;
  final int physicalQuantity;
  final int enterpriseQuantity;
  final int consignmentQuantity;
  final int quantityScale;
  final String measurementType;
  final List<LanInventoryStockSource> sources;
  final bool reconciled;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'warehouseId': warehouseId,
    'physicalQuantity': physicalQuantity,
    'enterpriseQuantity': enterpriseQuantity,
    'consignmentQuantity': consignmentQuantity,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
    'sources': sources.map((source) => source.toJson()).toList(),
    'reconciled': reconciled,
  };

  factory LanProductStockSourceSnapshot.fromJson(Map<String, dynamic> json) =>
      LanProductStockSourceSnapshot(
        productId: (json['productId'] as num).toInt(),
        warehouseId: json['warehouseId']?.toString() ?? '',
        physicalQuantity: (json['physicalQuantity'] as num?)?.toInt() ?? 0,
        enterpriseQuantity: (json['enterpriseQuantity'] as num?)?.toInt() ?? 0,
        consignmentQuantity:
            (json['consignmentQuantity'] as num?)?.toInt() ?? 0,
        quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
        measurementType: json['measurementType']?.toString() ?? 'piece',
        sources: (json['sources'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanInventoryStockSource.fromJson)
            .toList(growable: false),
        reconciled: json['reconciled'] == true,
      );
}

class LanConsignmentReturnSource {
  const LanConsignmentReturnSource({
    required this.layerId,
    required this.supplierId,
    required this.supplierName,
    required this.receiptNumber,
    required this.receivedAt,
    required this.maximumReturnQuantity,
    required this.quantityScale,
    required this.measurementType,
    this.batchNumber,
    this.manufacturerLotNumber,
  });

  final String layerId;
  final int supplierId;
  final String supplierName;
  final String receiptNumber;
  final DateTime receivedAt;
  final int maximumReturnQuantity;
  final int quantityScale;
  final String measurementType;
  final String? batchNumber;
  final String? manufacturerLotNumber;

  Map<String, dynamic> toJson() => {
    'layerId': layerId,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'receiptNumber': receiptNumber,
    'receivedAt': receivedAt.toUtc().toIso8601String(),
    'maximumReturnQuantity': maximumReturnQuantity,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
    'batchNumber': batchNumber,
    'manufacturerLotNumber': manufacturerLotNumber,
  };

  factory LanConsignmentReturnSource.fromJson(Map<String, dynamic> json) =>
      LanConsignmentReturnSource(
        layerId: json['layerId']?.toString() ?? '',
        supplierId: (json['supplierId'] as num).toInt(),
        supplierName: json['supplierName']?.toString() ?? '',
        receiptNumber: json['receiptNumber']?.toString() ?? '',
        receivedAt: DateTime.parse(json['receivedAt'].toString()),
        maximumReturnQuantity:
            (json['maximumReturnQuantity'] as num?)?.toInt() ?? 0,
        quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
        measurementType: json['measurementType']?.toString() ?? 'piece',
        batchNumber: json['batchNumber']?.toString(),
        manufacturerLotNumber: json['manufacturerLotNumber']?.toString(),
      );
}

class LanSaleAdjustmentReturnLineRequest {
  final int productId;
  final int? variantId;
  final int quantity;
  final int unitPriceCents;
  final int discountCents;
  final int discountPercentBps;
  final String dispositionType;
  final String? consignmentLayerId;
  final int? supplierIdentityId;
  final String sourceResolution;
  final String? sourceResolutionReason;
  final String? reason;

  const LanSaleAdjustmentReturnLineRequest({
    required this.productId,
    this.variantId,
    required this.quantity,
    required this.unitPriceCents,
    this.discountCents = 0,
    this.discountPercentBps = 0,
    this.dispositionType = 'restock',
    this.consignmentLayerId,
    this.supplierIdentityId,
    this.sourceResolution = 'pending',
    this.sourceResolutionReason,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variantId': variantId,
    'quantity': quantity,
    'unitPriceCents': unitPriceCents,
    'discountCents': discountCents,
    'discountPercentBps': discountPercentBps,
    'dispositionType': dispositionType,
    if (consignmentLayerId != null) 'consignmentLayerId': consignmentLayerId,
    if (supplierIdentityId != null) 'supplierIdentityId': supplierIdentityId,
    'sourceResolution': sourceResolution,
    if (sourceResolutionReason != null)
      'sourceResolutionReason': sourceResolutionReason,
    'reason': reason,
  };

  factory LanSaleAdjustmentReturnLineRequest.fromJson(
    Map<String, dynamic> json,
  ) => LanSaleAdjustmentReturnLineRequest(
    productId: (json['productId'] as num).toInt(),
    variantId: (json['variantId'] as num?)?.toInt(),
    quantity: (json['quantity'] as num).toInt(),
    unitPriceCents: (json['unitPriceCents'] as num).toInt(),
    discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
    discountPercentBps: (json['discountPercentBps'] as num?)?.toInt() ?? 0,
    dispositionType: json['dispositionType']?.toString() ?? 'restock',
    consignmentLayerId: json['consignmentLayerId']?.toString(),
    supplierIdentityId: (json['supplierIdentityId'] as num?)?.toInt(),
    sourceResolution: json['sourceResolution']?.toString() ?? 'pending',
    sourceResolutionReason: json['sourceResolutionReason']?.toString(),
    reason: json['reason']?.toString(),
  );
}

class LanSaleAdjustmentReturnRequest {
  final String idempotencyKey;
  final String? expectedPricingFingerprint;
  final int? customerId;
  final int? employeeId;
  final String refundMethod;
  final DateTime? dueDate;
  final DateTime returnDate;
  final String reasonCode;
  final String? notes;
  final int overallDiscountCents;
  final bool overallDiscountIsPercent;
  final List<LanSaleAdjustmentReturnLineRequest> lines;
  final List<LanCheckoutPaymentRequest> payments;

  const LanSaleAdjustmentReturnRequest({
    required this.idempotencyKey,
    this.expectedPricingFingerprint,
    this.customerId,
    this.employeeId,
    required this.refundMethod,
    this.dueDate,
    required this.returnDate,
    required this.reasonCode,
    this.notes,
    this.overallDiscountCents = 0,
    this.overallDiscountIsPercent = false,
    required this.lines,
    this.payments = const [],
  });

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    if (expectedPricingFingerprint != null)
      'expectedPricingFingerprint': expectedPricingFingerprint,
    'customerId': customerId,
    'employeeId': employeeId,
    'refundMethod': refundMethod,
    'dueDate': dueDate?.toUtc().toIso8601String(),
    'returnDate': returnDate.toUtc().toIso8601String(),
    'reasonCode': reasonCode,
    'notes': notes,
    'overallDiscountCents': overallDiscountCents,
    'overallDiscountIsPercent': overallDiscountIsPercent,
    'lines': lines.map((value) => value.toJson()).toList(),
    'payments': payments.map((value) => value.toJson()).toList(),
  };

  factory LanSaleAdjustmentReturnRequest.fromJson(
    Map<String, dynamic> json,
  ) => LanSaleAdjustmentReturnRequest(
    idempotencyKey: json['idempotencyKey']?.toString() ?? '',
    expectedPricingFingerprint: json['expectedPricingFingerprint'] as String?,
    customerId: (json['customerId'] as num?)?.toInt(),
    employeeId: (json['employeeId'] as num?)?.toInt(),
    refundMethod: json['refundMethod']?.toString() ?? 'cash',
    dueDate: json['dueDate'] == null
        ? null
        : DateTime.tryParse(json['dueDate'].toString()),
    returnDate:
        DateTime.tryParse(json['returnDate']?.toString() ?? '') ??
        DateTime.now(),
    reasonCode: json['reasonCode']?.toString() ?? '',
    notes: json['notes']?.toString(),
    overallDiscountCents: (json['overallDiscountCents'] as num?)?.toInt() ?? 0,
    overallDiscountIsPercent: json['overallDiscountIsPercent'] == true,
    lines: (json['lines'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LanSaleAdjustmentReturnLineRequest.fromJson)
        .toList(growable: false),
    payments: (json['payments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LanCheckoutPaymentRequest.fromJson)
        .toList(growable: false),
  );
}

class LanSupplierSummary {
  final int id;
  final String name;
  final String? phone;
  final String? productCode;

  const LanSupplierSummary({
    required this.id,
    required this.name,
    this.phone,
    this.productCode,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    if (productCode != null) 'productCode': productCode,
  };

  factory LanSupplierSummary.fromJson(Map<String, dynamic> json) =>
      LanSupplierSummary(
        id: (json['id'] as num).toInt(),
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString(),
        productCode: json['productCode']?.toString(),
      );
}

class LanReturnablePurchaseSummary {
  final int purchaseId;
  final String purchaseNumber;
  final int supplierId;
  final String? supplierName;
  final DateTime purchaseDate;
  final int totalCents;
  final String paymentMethod;
  final int currencyId;
  final bool taxInclusiveAtPost;
  final int returnableLineCount;

  const LanReturnablePurchaseSummary({
    required this.purchaseId,
    required this.purchaseNumber,
    required this.supplierId,
    this.supplierName,
    required this.purchaseDate,
    required this.totalCents,
    required this.paymentMethod,
    required this.currencyId,
    required this.taxInclusiveAtPost,
    required this.returnableLineCount,
  });

  Map<String, dynamic> toJson() => {
    'purchaseId': purchaseId,
    'purchaseNumber': purchaseNumber,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'purchaseDate': purchaseDate.toUtc().toIso8601String(),
    'totalCents': totalCents,
    'paymentMethod': paymentMethod,
    'currencyId': currencyId,
    'taxInclusiveAtPost': taxInclusiveAtPost,
    'returnableLineCount': returnableLineCount,
  };

  factory LanReturnablePurchaseSummary.fromJson(Map<String, dynamic> json) =>
      LanReturnablePurchaseSummary(
        purchaseId: (json['purchaseId'] as num).toInt(),
        purchaseNumber: json['purchaseNumber']?.toString() ?? '',
        supplierId: (json['supplierId'] as num).toInt(),
        supplierName: json['supplierName']?.toString(),
        purchaseDate: DateTime.parse(json['purchaseDate'].toString()),
        totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
        paymentMethod: json['paymentMethod']?.toString() ?? 'credit',
        currencyId: (json['currencyId'] as num?)?.toInt() ?? 1,
        taxInclusiveAtPost: json['taxInclusiveAtPost'] == true,
        returnableLineCount:
            (json['returnableLineCount'] as num?)?.toInt() ?? 0,
      );
}

class LanReturnablePurchasesPage {
  final List<LanReturnablePurchaseSummary> purchases;
  final int offset;
  final int limit;
  final bool hasMore;

  const LanReturnablePurchasesPage({
    required this.purchases,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  Map<String, dynamic> toJson() => {
    'purchases': purchases.map((value) => value.toJson()).toList(),
    'offset': offset,
    'limit': limit,
    'hasMore': hasMore,
  };

  factory LanReturnablePurchasesPage.fromJson(Map<String, dynamic> json) =>
      LanReturnablePurchasesPage(
        purchases: (json['purchases'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanReturnablePurchaseSummary.fromJson)
            .toList(growable: false),
        offset: (json['offset'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 50,
        hasMore: json['hasMore'] == true,
      );
}

class LanReturnablePurchaseLine {
  final int purchaseItemId;
  final int productId;
  final int? variantId;
  final String productName;
  final String? variantSku;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final int originalQuantity;
  final int returnedQuantity;
  final int availableQuantity;
  final int? currentStockQuantity;
  final bool tracksInventory;
  final int quantityScale;
  final String measurementType;
  final int unitCostCents;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int linkedReturnedQuantity;
  final int linkedReturnedSubtotalCents;
  final int linkedReturnedDiscountCents;
  final int linkedReturnedTaxCents;
  final int linkedReturnedRefundCents;

  const LanReturnablePurchaseLine({
    required this.purchaseItemId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantSku,
    this.colorName,
    this.colorHex,
    this.sizeName,
    required this.originalQuantity,
    required this.returnedQuantity,
    required this.availableQuantity,
    this.currentStockQuantity,
    required this.tracksInventory,
    required this.quantityScale,
    required this.measurementType,
    required this.unitCostCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    this.linkedReturnedQuantity = 0,
    this.linkedReturnedSubtotalCents = 0,
    this.linkedReturnedDiscountCents = 0,
    this.linkedReturnedTaxCents = 0,
    this.linkedReturnedRefundCents = 0,
  });

  Map<String, dynamic> toJson() => {
    'purchaseItemId': purchaseItemId,
    'productId': productId,
    'variantId': variantId,
    'productName': productName,
    'variantSku': variantSku,
    'colorName': colorName,
    'colorHex': colorHex,
    'sizeName': sizeName,
    'originalQuantity': originalQuantity,
    'returnedQuantity': returnedQuantity,
    'availableQuantity': availableQuantity,
    'currentStockQuantity': currentStockQuantity,
    'tracksInventory': tracksInventory,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
    'unitCostCents': unitCostCents,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'linkedReturnedQuantity': linkedReturnedQuantity,
    'linkedReturnedSubtotalCents': linkedReturnedSubtotalCents,
    'linkedReturnedDiscountCents': linkedReturnedDiscountCents,
    'linkedReturnedTaxCents': linkedReturnedTaxCents,
    'linkedReturnedRefundCents': linkedReturnedRefundCents,
  };

  factory LanReturnablePurchaseLine.fromJson(Map<String, dynamic> json) =>
      LanReturnablePurchaseLine(
        purchaseItemId: (json['purchaseItemId'] as num).toInt(),
        productId: (json['productId'] as num).toInt(),
        variantId: (json['variantId'] as num?)?.toInt(),
        productName: json['productName']?.toString() ?? '',
        variantSku: json['variantSku']?.toString(),
        colorName: json['colorName']?.toString(),
        colorHex: json['colorHex']?.toString(),
        sizeName: json['sizeName']?.toString(),
        originalQuantity: (json['originalQuantity'] as num?)?.toInt() ?? 0,
        returnedQuantity: (json['returnedQuantity'] as num?)?.toInt() ?? 0,
        availableQuantity: (json['availableQuantity'] as num?)?.toInt() ?? 0,
        currentStockQuantity: (json['currentStockQuantity'] as num?)?.toInt(),
        tracksInventory: json['tracksInventory'] != false,
        quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
        measurementType: json['measurementType']?.toString() ?? 'piece',
        unitCostCents: (json['unitCostCents'] as num?)?.toInt() ?? 0,
        subtotalCents: (json['subtotalCents'] as num?)?.toInt() ?? 0,
        discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
        taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
        linkedReturnedQuantity:
            (json['linkedReturnedQuantity'] as num?)?.toInt() ?? 0,
        linkedReturnedSubtotalCents:
            (json['linkedReturnedSubtotalCents'] as num?)?.toInt() ?? 0,
        linkedReturnedDiscountCents:
            (json['linkedReturnedDiscountCents'] as num?)?.toInt() ?? 0,
        linkedReturnedTaxCents:
            (json['linkedReturnedTaxCents'] as num?)?.toInt() ?? 0,
        linkedReturnedRefundCents:
            (json['linkedReturnedRefundCents'] as num?)?.toInt() ?? 0,
      );
}

class LanReturnablePurchaseDetails {
  final LanReturnablePurchaseSummary purchase;
  final List<LanReturnablePurchaseLine> lines;

  const LanReturnablePurchaseDetails({
    required this.purchase,
    required this.lines,
  });

  Map<String, dynamic> toJson() => {
    'purchase': purchase.toJson(),
    'lines': lines.map((value) => value.toJson()).toList(),
  };

  factory LanReturnablePurchaseDetails.fromJson(Map<String, dynamic> json) =>
      LanReturnablePurchaseDetails(
        purchase: LanReturnablePurchaseSummary.fromJson(
          json['purchase'] as Map<String, dynamic>,
        ),
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanReturnablePurchaseLine.fromJson)
            .toList(growable: false),
      );
}

class LanPurchaseReturnSummary {
  final int id;
  final int purchaseId;
  final String? purchaseNumber;
  final int? supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final String returnNumber;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int currencyId;
  final String status;
  final String dispositionType;
  final String refundMethod;
  final String? reason;
  final DateTime returnDate;
  final DateTime createdAt;
  final bool isAdjustment;
  final String unifiedId;

  const LanPurchaseReturnSummary({
    required this.id,
    required this.purchaseId,
    this.purchaseNumber,
    this.supplierId,
    this.supplierName,
    this.supplierPhone,
    required this.returnNumber,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.currencyId,
    required this.status,
    required this.dispositionType,
    required this.refundMethod,
    this.reason,
    required this.returnDate,
    required this.createdAt,
    required this.isAdjustment,
    required this.unifiedId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'purchaseId': purchaseId,
    'purchaseNumber': purchaseNumber,
    'supplierId': supplierId,
    'supplierName': supplierName,
    'supplierPhone': supplierPhone,
    'returnNumber': returnNumber,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'currencyId': currencyId,
    'status': status,
    'dispositionType': dispositionType,
    'refundMethod': refundMethod,
    'reason': reason,
    'returnDate': returnDate.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'isAdjustment': isAdjustment,
    'unifiedId': unifiedId,
  };

  factory LanPurchaseReturnSummary.fromJson(Map<String, dynamic> json) =>
      LanPurchaseReturnSummary(
        id: (json['id'] as num).toInt(),
        purchaseId: (json['purchaseId'] as num?)?.toInt() ?? 0,
        purchaseNumber: json['purchaseNumber']?.toString(),
        supplierId: (json['supplierId'] as num?)?.toInt(),
        supplierName: json['supplierName']?.toString(),
        supplierPhone: json['supplierPhone']?.toString(),
        returnNumber: json['returnNumber']?.toString() ?? '',
        subtotalCents: (json['subtotalCents'] as num?)?.toInt() ?? 0,
        discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
        taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
        currencyId: (json['currencyId'] as num?)?.toInt() ?? 1,
        status: json['status']?.toString() ?? 'posted',
        dispositionType: json['dispositionType']?.toString() ?? 'restock',
        refundMethod: json['refundMethod']?.toString() ?? 'credit',
        reason: json['reason']?.toString(),
        returnDate: DateTime.parse(json['returnDate'].toString()),
        createdAt: DateTime.parse(json['createdAt'].toString()),
        isAdjustment: json['isAdjustment'] == true,
        unifiedId: json['unifiedId']?.toString() ?? '',
      );
}

class LanPurchaseReturnsPage {
  final List<LanPurchaseReturnSummary> returns;
  final int offset;
  final int limit;
  final bool hasMore;

  const LanPurchaseReturnsPage({
    required this.returns,
    required this.offset,
    required this.limit,
    required this.hasMore,
  });

  Map<String, dynamic> toJson() => {
    'returns': returns.map((value) => value.toJson()).toList(),
    'offset': offset,
    'limit': limit,
    'hasMore': hasMore,
  };

  factory LanPurchaseReturnsPage.fromJson(Map<String, dynamic> json) =>
      LanPurchaseReturnsPage(
        returns: (json['returns'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanPurchaseReturnSummary.fromJson)
            .toList(growable: false),
        offset: (json['offset'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 100,
        hasMore: json['hasMore'] == true,
      );
}

class LanPurchaseReturnDetailLine {
  final int id;
  final int returnId;
  final int? purchaseItemId;
  final int productId;
  final int? variantId;
  final String productName;
  final String? variantSku;
  final String? variantBarcode;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final int? unitPriceCents;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final String? reason;
  final String dispositionType;
  final DateTime createdAt;

  const LanPurchaseReturnDetailLine({
    required this.id,
    required this.returnId,
    this.purchaseItemId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantSku,
    this.variantBarcode,
    this.colorName,
    this.colorHex,
    this.sizeName,
    required this.quantity,
    required this.quantityScale,
    required this.measurementType,
    this.unitPriceCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    this.reason,
    required this.dispositionType,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'returnId': returnId,
    'purchaseItemId': purchaseItemId,
    'productId': productId,
    'variantId': variantId,
    'productName': productName,
    'variantSku': variantSku,
    'variantBarcode': variantBarcode,
    'colorName': colorName,
    'colorHex': colorHex,
    'sizeName': sizeName,
    'quantity': quantity,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
    'unitPriceCents': unitPriceCents,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'reason': reason,
    'dispositionType': dispositionType,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory LanPurchaseReturnDetailLine.fromJson(Map<String, dynamic> json) =>
      LanPurchaseReturnDetailLine(
        id: (json['id'] as num).toInt(),
        returnId: (json['returnId'] as num).toInt(),
        purchaseItemId: (json['purchaseItemId'] as num?)?.toInt(),
        productId: (json['productId'] as num?)?.toInt() ?? 0,
        variantId: (json['variantId'] as num?)?.toInt(),
        productName: json['productName']?.toString() ?? '',
        variantSku: json['variantSku']?.toString(),
        variantBarcode: json['variantBarcode']?.toString(),
        colorName: json['colorName']?.toString(),
        colorHex: json['colorHex']?.toString(),
        sizeName: json['sizeName']?.toString(),
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
        measurementType: json['measurementType']?.toString() ?? 'piece',
        unitPriceCents: (json['unitPriceCents'] as num?)?.toInt(),
        subtotalCents: (json['subtotalCents'] as num?)?.toInt() ?? 0,
        discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
        taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
        reason: json['reason']?.toString(),
        dispositionType: json['dispositionType']?.toString() ?? 'restock',
        createdAt: DateTime.parse(json['createdAt'].toString()),
      );
}

class LanPurchaseReturnDetails {
  final LanPurchaseReturnSummary summary;
  final List<LanPurchaseReturnDetailLine> lines;
  final LanReturnablePurchaseSummary? originalPurchase;

  const LanPurchaseReturnDetails({
    required this.summary,
    required this.lines,
    this.originalPurchase,
  });

  Map<String, dynamic> toJson() => {
    'summary': summary.toJson(),
    'lines': lines.map((value) => value.toJson()).toList(),
    'originalPurchase': originalPurchase?.toJson(),
  };

  factory LanPurchaseReturnDetails.fromJson(Map<String, dynamic> json) =>
      LanPurchaseReturnDetails(
        summary: LanPurchaseReturnSummary.fromJson(
          json['summary'] as Map<String, dynamic>,
        ),
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanPurchaseReturnDetailLine.fromJson)
            .toList(growable: false),
        originalPurchase: json['originalPurchase'] is Map<String, dynamic>
            ? LanReturnablePurchaseSummary.fromJson(
                json['originalPurchase'] as Map<String, dynamic>,
              )
            : null,
      );
}

class LanPurchaseReturnLineRequest {
  final int purchaseItemId;
  final int quantity;
  final String? reason;

  const LanPurchaseReturnLineRequest({
    required this.purchaseItemId,
    required this.quantity,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    'purchaseItemId': purchaseItemId,
    'quantity': quantity,
    'reason': reason,
  };

  factory LanPurchaseReturnLineRequest.fromJson(Map<String, dynamic> json) =>
      LanPurchaseReturnLineRequest(
        purchaseItemId: (json['purchaseItemId'] as num).toInt(),
        quantity: (json['quantity'] as num).toInt(),
        reason: json['reason']?.toString(),
      );
}

class LanPurchaseReturnRequest {
  final String idempotencyKey;
  final int purchaseId;
  final String dispositionType;
  final String refundMethod;
  final String? reason;
  final DateTime? dueDate;
  final List<LanPurchaseReturnLineRequest> lines;
  final List<LanCheckoutPaymentRequest> payments;

  const LanPurchaseReturnRequest({
    required this.idempotencyKey,
    required this.purchaseId,
    required this.dispositionType,
    required this.refundMethod,
    this.reason,
    this.dueDate,
    required this.lines,
    this.payments = const [],
  });

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'purchaseId': purchaseId,
    'dispositionType': dispositionType,
    'refundMethod': refundMethod,
    'reason': reason,
    'dueDate': dueDate?.toUtc().toIso8601String(),
    'lines': lines.map((value) => value.toJson()).toList(),
    'payments': payments.map((value) => value.toJson()).toList(),
  };

  factory LanPurchaseReturnRequest.fromJson(Map<String, dynamic> json) =>
      LanPurchaseReturnRequest(
        idempotencyKey: json['idempotencyKey']?.toString() ?? '',
        purchaseId: (json['purchaseId'] as num).toInt(),
        dispositionType: json['dispositionType']?.toString() ?? 'restock',
        refundMethod: json['refundMethod']?.toString() ?? 'credit',
        reason: json['reason']?.toString(),
        dueDate: json['dueDate'] == null
            ? null
            : DateTime.tryParse(json['dueDate'].toString()),
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanPurchaseReturnLineRequest.fromJson)
            .toList(growable: false),
        payments: (json['payments'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanCheckoutPaymentRequest.fromJson)
            .toList(growable: false),
      );
}

class LanPurchaseAdjustmentReturnLineRequest {
  final int productId;
  final int? variantId;
  final int quantity;
  final int unitPriceCents;
  final int discountCents;
  final int discountPercentBps;
  final String? reason;

  const LanPurchaseAdjustmentReturnLineRequest({
    required this.productId,
    this.variantId,
    required this.quantity,
    required this.unitPriceCents,
    this.discountCents = 0,
    this.discountPercentBps = 0,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variantId': variantId,
    'quantity': quantity,
    'unitPriceCents': unitPriceCents,
    'discountCents': discountCents,
    'discountPercentBps': discountPercentBps,
    'reason': reason,
  };

  factory LanPurchaseAdjustmentReturnLineRequest.fromJson(
    Map<String, dynamic> json,
  ) => LanPurchaseAdjustmentReturnLineRequest(
    productId: (json['productId'] as num).toInt(),
    variantId: (json['variantId'] as num?)?.toInt(),
    quantity: (json['quantity'] as num).toInt(),
    unitPriceCents: (json['unitPriceCents'] as num).toInt(),
    discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
    discountPercentBps: (json['discountPercentBps'] as num?)?.toInt() ?? 0,
    reason: json['reason']?.toString(),
  );
}

class LanPurchaseAdjustmentReturnRequest {
  final String idempotencyKey;
  final String? expectedPricingFingerprint;
  final int supplierId;
  final String refundMethod;
  final DateTime? dueDate;
  final DateTime returnDate;
  final String reasonCode;
  final String? notes;
  final int overallDiscountCents;
  final bool overallDiscountIsPercent;
  final List<LanPurchaseAdjustmentReturnLineRequest> lines;
  final List<LanCheckoutPaymentRequest> payments;

  const LanPurchaseAdjustmentReturnRequest({
    required this.idempotencyKey,
    this.expectedPricingFingerprint,
    required this.supplierId,
    required this.refundMethod,
    this.dueDate,
    required this.returnDate,
    required this.reasonCode,
    this.notes,
    this.overallDiscountCents = 0,
    this.overallDiscountIsPercent = false,
    required this.lines,
    this.payments = const [],
  });

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    if (expectedPricingFingerprint != null)
      'expectedPricingFingerprint': expectedPricingFingerprint,
    'supplierId': supplierId,
    'refundMethod': refundMethod,
    'dueDate': dueDate?.toUtc().toIso8601String(),
    'returnDate': returnDate.toUtc().toIso8601String(),
    'reasonCode': reasonCode,
    'notes': notes,
    'overallDiscountCents': overallDiscountCents,
    'overallDiscountIsPercent': overallDiscountIsPercent,
    'lines': lines.map((value) => value.toJson()).toList(),
    'payments': payments.map((value) => value.toJson()).toList(),
  };

  factory LanPurchaseAdjustmentReturnRequest.fromJson(
    Map<String, dynamic> json,
  ) => LanPurchaseAdjustmentReturnRequest(
    idempotencyKey: json['idempotencyKey']?.toString() ?? '',
    expectedPricingFingerprint: json['expectedPricingFingerprint'] as String?,
    supplierId: (json['supplierId'] as num).toInt(),
    refundMethod: json['refundMethod']?.toString() ?? 'credit',
    dueDate: json['dueDate'] == null
        ? null
        : DateTime.tryParse(json['dueDate'].toString()),
    returnDate:
        DateTime.tryParse(json['returnDate']?.toString() ?? '') ??
        DateTime.now(),
    reasonCode: json['reasonCode']?.toString() ?? '',
    notes: json['notes']?.toString(),
    overallDiscountCents: (json['overallDiscountCents'] as num?)?.toInt() ?? 0,
    overallDiscountIsPercent: json['overallDiscountIsPercent'] == true,
    lines: (json['lines'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LanPurchaseAdjustmentReturnLineRequest.fromJson)
        .toList(growable: false),
    payments: (json['payments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LanCheckoutPaymentRequest.fromJson)
        .toList(growable: false),
  );
}

class LanPurchaseReturnResult {
  final int returnId;
  final String returnNumber;
  final int totalCents;
  final bool duplicate;

  const LanPurchaseReturnResult({
    required this.returnId,
    required this.returnNumber,
    required this.totalCents,
    this.duplicate = false,
  });

  Map<String, dynamic> toJson() => {
    'returnId': returnId,
    'returnNumber': returnNumber,
    'totalCents': totalCents,
    'duplicate': duplicate,
  };

  factory LanPurchaseReturnResult.fromJson(Map<String, dynamic> json) =>
      LanPurchaseReturnResult(
        returnId: (json['returnId'] as num).toInt(),
        returnNumber: json['returnNumber']?.toString() ?? '',
        totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
        duplicate: json['duplicate'] == true,
      );
}

class LanSaleLineRequest {
  final int productId;
  final int? variantId;
  final int? supplierIdentityId;
  final String? consignmentLayerId;
  final int quantity;
  final String priceTier;
  final int? salespersonId;
  final String discountType;
  final int discountValue;

  const LanSaleLineRequest({
    required this.productId,
    this.variantId,
    this.supplierIdentityId,
    this.consignmentLayerId,
    required this.quantity,
    this.priceTier = 'retail',
    this.salespersonId,
    this.discountType = 'none',
    this.discountValue = 0,
  });

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variantId': variantId,
    if (supplierIdentityId != null) 'supplierIdentityId': supplierIdentityId,
    if (consignmentLayerId != null) 'consignmentLayerId': consignmentLayerId,
    'quantity': quantity,
    'priceTier': priceTier,
    'salespersonId': salespersonId,
    'discountType': discountType,
    'discountValue': discountValue,
  };

  factory LanSaleLineRequest.fromJson(Map<String, dynamic> json) {
    return LanSaleLineRequest(
      productId: (json['productId'] as num).toInt(),
      variantId: (json['variantId'] as num?)?.toInt(),
      supplierIdentityId: (json['supplierIdentityId'] as num?)?.toInt(),
      consignmentLayerId: json['consignmentLayerId']?.toString(),
      quantity: (json['quantity'] as num).toInt(),
      priceTier: json['priceTier']?.toString() ?? 'retail',
      salespersonId: (json['salespersonId'] as num?)?.toInt(),
      discountType: json['discountType']?.toString() ?? 'none',
      discountValue: (json['discountValue'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A real payment leg captured at checkout on a remote device.
///
/// Credit is not sent as a payment. Any uncovered invoice balance remains in
/// accounts receivable on the master. Cheque metadata is included so the
/// master can create the cheque instrument and its accounting entry in the
/// same transaction as the sale.
class LanCheckoutPaymentRequest {
  final String method;
  final int amountCents;
  final String? reference;
  final String? bankName;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final String? note;

  const LanCheckoutPaymentRequest({
    required this.method,
    required this.amountCents,
    this.reference,
    this.bankName,
    this.issueDate,
    this.dueDate,
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'method': method,
    'amountCents': amountCents,
    'reference': reference,
    'bankName': bankName,
    'issueDate': issueDate?.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
    'note': note,
  };

  factory LanCheckoutPaymentRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString());

    return LanCheckoutPaymentRequest(
      method: json['method']?.toString() ?? '',
      amountCents: (json['amountCents'] as num?)?.toInt() ?? 0,
      reference: json['reference']?.toString(),
      bankName: json['bankName']?.toString(),
      issueDate: parseDate(json['issueDate']),
      dueDate: parseDate(json['dueDate']),
      note: json['note']?.toString(),
    );
  }
}

class LanSaleRequest {
  final String idempotencyKey;
  final int? customerId;
  final int? salespersonId;
  final String paymentMethod;
  final int? paidAmountCents;
  final String? notes;
  final String? belowCostOverrideReason;
  final List<LanSaleLineRequest> lines;
  final List<LanCheckoutPaymentRequest> payments;

  const LanSaleRequest({
    required this.idempotencyKey,
    this.customerId,
    this.salespersonId,
    required this.paymentMethod,
    this.paidAmountCents,
    this.notes,
    this.belowCostOverrideReason,
    required this.lines,
    this.payments = const [],
  });

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'customerId': customerId,
    'salespersonId': salespersonId,
    'paymentMethod': paymentMethod,
    'paidAmountCents': paidAmountCents,
    'notes': notes,
    'belowCostOverrideReason': belowCostOverrideReason,
    'lines': lines.map((value) => value.toJson()).toList(),
    'payments': payments.map((value) => value.toJson()).toList(),
  };

  factory LanSaleRequest.fromJson(Map<String, dynamic> json) {
    return LanSaleRequest(
      idempotencyKey: json['idempotencyKey']?.toString() ?? '',
      customerId: (json['customerId'] as num?)?.toInt(),
      salespersonId: (json['salespersonId'] as num?)?.toInt(),
      paymentMethod: json['paymentMethod']?.toString() ?? 'cash',
      paidAmountCents: (json['paidAmountCents'] as num?)?.toInt(),
      notes: json['notes']?.toString(),
      belowCostOverrideReason: json['belowCostOverrideReason']?.toString(),
      lines: (json['lines'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanSaleLineRequest.fromJson)
          .toList(growable: false),
      payments: (json['payments'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanCheckoutPaymentRequest.fromJson)
          .toList(growable: false),
    );
  }

  LanSaleRequest copyWith({String? belowCostOverrideReason}) {
    return LanSaleRequest(
      idempotencyKey: idempotencyKey,
      customerId: customerId,
      salespersonId: salespersonId,
      paymentMethod: paymentMethod,
      paidAmountCents: paidAmountCents,
      notes: notes,
      belowCostOverrideReason:
          belowCostOverrideReason ?? this.belowCostOverrideReason,
      lines: lines,
      payments: payments,
    );
  }
}

class LanSaleResult {
  final int saleId;
  final String invoiceNumber;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int paidAmountCents;
  final String? receiptHeaderText;
  final String? receiptFooterText;
  final bool duplicate;

  const LanSaleResult({
    required this.saleId,
    required this.invoiceNumber,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidAmountCents,
    this.receiptHeaderText,
    this.receiptFooterText,
    this.duplicate = false,
  });

  Map<String, dynamic> toJson() => {
    'saleId': saleId,
    'invoiceNumber': invoiceNumber,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'paidAmountCents': paidAmountCents,
    'receiptHeaderText': receiptHeaderText,
    'receiptFooterText': receiptFooterText,
    'duplicate': duplicate,
  };

  factory LanSaleResult.fromJson(Map<String, dynamic> json) {
    return LanSaleResult(
      saleId: (json['saleId'] as num).toInt(),
      invoiceNumber: json['invoiceNumber']?.toString() ?? '',
      subtotalCents: (json['subtotalCents'] as num?)?.toInt() ?? 0,
      discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
      taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
      totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
      paidAmountCents: (json['paidAmountCents'] as num?)?.toInt() ?? 0,
      receiptHeaderText: json.containsKey('receiptHeaderText')
          ? json['receiptHeaderText']?.toString() ?? ''
          : null,
      receiptFooterText: json.containsKey('receiptFooterText')
          ? json['receiptFooterText']?.toString() ?? ''
          : null,
      duplicate: json['duplicate'] == true,
    );
  }
}

class LanSaleSummary {
  final int id;
  final String invoiceNumber;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final int? employeeId;
  final String? employeeName;
  final int subtotalCents;
  final int taxCents;
  final int discountCents;
  final int totalCents;
  final int paidAmountCents;
  final int currencyId;
  final String paymentMethod;
  final String status;
  final String? notes;
  final DateTime saleDate;
  final DateTime? dueDate;
  final bool taxInclusiveAtPost;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LanSaleSummary({
    required this.id,
    required this.invoiceNumber,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.employeeId,
    this.employeeName,
    required this.subtotalCents,
    required this.taxCents,
    required this.discountCents,
    required this.totalCents,
    required this.paidAmountCents,
    required this.currencyId,
    required this.paymentMethod,
    required this.status,
    this.notes,
    required this.saleDate,
    this.dueDate,
    required this.taxInclusiveAtPost,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'invoiceNumber': invoiceNumber,
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'employeeId': employeeId,
    'employeeName': employeeName,
    'subtotalCents': subtotalCents,
    'taxCents': taxCents,
    'discountCents': discountCents,
    'totalCents': totalCents,
    'paidAmountCents': paidAmountCents,
    'currencyId': currencyId,
    'paymentMethod': paymentMethod,
    'status': status,
    'notes': notes,
    'saleDate': saleDate.toUtc().toIso8601String(),
    'dueDate': dueDate?.toUtc().toIso8601String(),
    'taxInclusiveAtPost': taxInclusiveAtPost,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory LanSaleSummary.fromJson(Map<String, dynamic> json) => LanSaleSummary(
    id: (json['id'] as num).toInt(),
    invoiceNumber: json['invoiceNumber']?.toString() ?? '',
    customerId: (json['customerId'] as num?)?.toInt(),
    customerName: json['customerName']?.toString(),
    customerPhone: json['customerPhone']?.toString(),
    employeeId: (json['employeeId'] as num?)?.toInt(),
    employeeName: json['employeeName']?.toString(),
    subtotalCents: (json['subtotalCents'] as num?)?.toInt() ?? 0,
    taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
    discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
    totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
    paidAmountCents: (json['paidAmountCents'] as num?)?.toInt() ?? 0,
    currencyId: (json['currencyId'] as num?)?.toInt() ?? 1,
    paymentMethod: json['paymentMethod']?.toString() ?? 'cash',
    status: json['status']?.toString() ?? 'completed',
    notes: json['notes']?.toString(),
    saleDate: DateTime.parse(json['saleDate'].toString()),
    dueDate: json['dueDate'] == null
        ? null
        : DateTime.parse(json['dueDate'].toString()),
    taxInclusiveAtPost: json['taxInclusiveAtPost'] == true,
    createdAt: DateTime.parse(json['createdAt'].toString()),
    updatedAt: DateTime.parse(json['updatedAt'].toString()),
  );
}

/// Complete, read-only sale line returned by the master. Cost fields are
/// intentionally absent so a cashier device can never infer product cost.
class LanSaleDetailLine {
  final int id;
  final int saleId;
  final int productId;
  final String productName;
  final String? productSku;
  final int? variantId;
  final String? variantSku;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final int unitPriceCents;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int? employeeId;
  final String? employeeName;
  final DateTime createdAt;

  const LanSaleDetailLine({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.productName,
    this.productSku,
    this.variantId,
    this.variantSku,
    this.colorName,
    this.colorHex,
    this.sizeName,
    required this.quantity,
    required this.quantityScale,
    required this.measurementType,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    this.employeeId,
    this.employeeName,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'saleId': saleId,
    'productId': productId,
    'productName': productName,
    'productSku': productSku,
    'variantId': variantId,
    'variantSku': variantSku,
    'colorName': colorName,
    'colorHex': colorHex,
    'sizeName': sizeName,
    'quantity': quantity,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
    'unitPriceCents': unitPriceCents,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'totalCents': totalCents,
    'employeeId': employeeId,
    'employeeName': employeeName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory LanSaleDetailLine.fromJson(Map<String, dynamic> json) =>
      LanSaleDetailLine(
        id: (json['id'] as num).toInt(),
        saleId: (json['saleId'] as num).toInt(),
        productId: (json['productId'] as num).toInt(),
        productName: json['productName']?.toString() ?? '',
        productSku: json['productSku']?.toString(),
        variantId: (json['variantId'] as num?)?.toInt(),
        variantSku: json['variantSku']?.toString(),
        colorName: json['colorName']?.toString(),
        colorHex: json['colorHex']?.toString(),
        sizeName: json['sizeName']?.toString(),
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        quantityScale: (json['quantityScale'] as num?)?.toInt() ?? 1,
        measurementType: json['measurementType']?.toString() ?? 'piece',
        unitPriceCents: (json['unitPriceCents'] as num?)?.toInt() ?? 0,
        subtotalCents: (json['subtotalCents'] as num?)?.toInt() ?? 0,
        discountCents: (json['discountCents'] as num?)?.toInt() ?? 0,
        taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
        employeeId: (json['employeeId'] as num?)?.toInt(),
        employeeName: json['employeeName']?.toString(),
        createdAt: DateTime.parse(json['createdAt'].toString()),
      );
}

class LanSaleDetails {
  final LanSaleSummary sale;
  final List<LanSaleDetailLine> lines;
  final List<SalePromotionSnapshot> promotionApplications;
  final String currencyCode;
  final String currencySymbol;
  final int currencyDecimalDigits;
  final bool currencySymbolAfter;
  final String? cashierName;
  final String? cashierShiftNumber;
  final String? receiptHeaderText;
  final String? receiptFooterText;

  const LanSaleDetails({
    required this.sale,
    required this.lines,
    this.promotionApplications = const [],
    required this.currencyCode,
    required this.currencySymbol,
    required this.currencyDecimalDigits,
    required this.currencySymbolAfter,
    this.cashierName,
    this.cashierShiftNumber,
    this.receiptHeaderText,
    this.receiptFooterText,
  });

  Map<String, dynamic> toJson() => {
    'sale': sale.toJson(),
    'lines': lines.map((line) => line.toJson()).toList(),
    'promotionApplications': promotionApplications
        .map((application) => application.toTransportMap())
        .toList(growable: false),
    'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
    'currencyDecimalDigits': currencyDecimalDigits,
    'currencySymbolAfter': currencySymbolAfter,
    'cashierName': cashierName,
    'cashierShiftNumber': cashierShiftNumber,
    'receiptHeaderText': receiptHeaderText,
    'receiptFooterText': receiptFooterText,
  };

  factory LanSaleDetails.fromJson(Map<String, dynamic> json) => LanSaleDetails(
    sale: LanSaleSummary.fromJson(json['sale'] as Map<String, dynamic>),
    lines: (json['lines'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LanSaleDetailLine.fromJson)
        .toList(growable: false),
    promotionApplications:
        (json['promotionApplications'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SalePromotionSnapshot.fromTransportMap)
            .toList(growable: false),
    currencyCode: json['currencyCode']?.toString() ?? 'USD',
    currencySymbol: json['currencySymbol']?.toString() ?? r'$',
    currencyDecimalDigits:
        (json['currencyDecimalDigits'] as num?)?.toInt() ?? 2,
    currencySymbolAfter: json['currencySymbolAfter'] == true,
    cashierName: json['cashierName']?.toString(),
    cashierShiftNumber: json['cashierShiftNumber']?.toString(),
    receiptHeaderText: json.containsKey('receiptHeaderText')
        ? json['receiptHeaderText']?.toString() ?? ''
        : null,
    receiptFooterText: json.containsKey('receiptFooterText')
        ? json['receiptFooterText']?.toString() ?? ''
        : null,
  );
}

class LanSaleVoidResult {
  final int saleId;
  final String status;
  final bool duplicate;

  const LanSaleVoidResult({
    required this.saleId,
    required this.status,
    this.duplicate = false,
  });

  Map<String, dynamic> toJson() => {
    'saleId': saleId,
    'status': status,
    'duplicate': duplicate,
  };

  factory LanSaleVoidResult.fromJson(Map<String, dynamic> json) =>
      LanSaleVoidResult(
        saleId: (json['saleId'] as num).toInt(),
        status: json['status']?.toString() ?? 'voided',
        duplicate: json['duplicate'] == true,
      );
}

class LanSaleDashboardStats {
  final int totalCount;
  final int completedCount;
  final int voidedCount;
  final int totalSalesCents;
  final int totalPaidCents;
  final int overdueCount;
  final int returnsCount;
  final int totalReturnsCents;
  final int todaySalesCents;
  final int todayCount;

  const LanSaleDashboardStats({
    required this.totalCount,
    required this.completedCount,
    required this.voidedCount,
    required this.totalSalesCents,
    this.totalPaidCents = 0,
    this.overdueCount = 0,
    required this.returnsCount,
    required this.totalReturnsCents,
    required this.todaySalesCents,
    required this.todayCount,
  });

  Map<String, dynamic> toJson() => {
    'totalCount': totalCount,
    'completedCount': completedCount,
    'voidedCount': voidedCount,
    'totalSalesCents': totalSalesCents,
    'totalPaidCents': totalPaidCents,
    'overdueCount': overdueCount,
    'returnsCount': returnsCount,
    'totalReturnsCents': totalReturnsCents,
    'todaySalesCents': todaySalesCents,
    'todayCount': todayCount,
  };

  factory LanSaleDashboardStats.fromJson(Map<String, dynamic> json) =>
      LanSaleDashboardStats(
        totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
        completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
        voidedCount: (json['voidedCount'] as num?)?.toInt() ?? 0,
        totalSalesCents: (json['totalSalesCents'] as num?)?.toInt() ?? 0,
        totalPaidCents: (json['totalPaidCents'] as num?)?.toInt() ?? 0,
        overdueCount: (json['overdueCount'] as num?)?.toInt() ?? 0,
        returnsCount: (json['returnsCount'] as num?)?.toInt() ?? 0,
        totalReturnsCents: (json['totalReturnsCents'] as num?)?.toInt() ?? 0,
        todaySalesCents: (json['todaySalesCents'] as num?)?.toInt() ?? 0,
        todayCount: (json['todayCount'] as num?)?.toInt() ?? 0,
      );
}

class LanSalesPage {
  final List<LanSaleSummary> sales;
  final LanSaleDashboardStats stats;
  final Set<int> saleIdsWithReturns;
  final Map<int, List<String>> productSearchTerms;
  final String currencyCode;
  final String currencySymbol;
  final int currencyDecimalDigits;
  final bool currencySymbolAfter;

  const LanSalesPage({
    required this.sales,
    required this.stats,
    this.saleIdsWithReturns = const {},
    this.productSearchTerms = const {},
    required this.currencyCode,
    required this.currencySymbol,
    required this.currencyDecimalDigits,
    required this.currencySymbolAfter,
  });

  Map<String, dynamic> toJson() => {
    'sales': sales.map((value) => value.toJson()).toList(),
    'stats': stats.toJson(),
    'currencyCode': currencyCode,
    'currencySymbol': currencySymbol,
    'currencyDecimalDigits': currencyDecimalDigits,
    'currencySymbolAfter': currencySymbolAfter,
    'saleIdsWithReturns': saleIdsWithReturns.toList(),
    'productSearchTerms': productSearchTerms.map(
      (key, value) => MapEntry(key.toString(), value),
    ),
  };

  factory LanSalesPage.fromJson(Map<String, dynamic> json) {
    final rawTerms = json['productSearchTerms'];
    return LanSalesPage(
      sales: (json['sales'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanSaleSummary.fromJson)
          .toList(growable: false),
      stats: LanSaleDashboardStats.fromJson(
        json['stats'] as Map<String, dynamic>? ?? const {},
      ),
      currencyCode: json['currencyCode']?.toString() ?? 'USD',
      currencySymbol: json['currencySymbol']?.toString() ?? r'$',
      currencyDecimalDigits:
          (json['currencyDecimalDigits'] as num?)?.toInt() ?? 2,
      currencySymbolAfter: json['currencySymbolAfter'] == true,
      saleIdsWithReturns:
          (json['saleIdsWithReturns'] as List<dynamic>? ?? const [])
              .whereType<num>()
              .map((value) => value.toInt())
              .toSet(),
      productSearchTerms: rawTerms is Map<String, dynamic>
          ? rawTerms.map(
              (key, value) => MapEntry(
                int.parse(key),
                (value as List<dynamic>? ?? const [])
                    .map((term) => term.toString())
                    .toList(growable: false),
              ),
            )
          : const {},
    );
  }
}

class LanBusinessException implements Exception {
  final String code;
  final String message;
  final int statusCode;
  final Map<String, dynamic> details;

  const LanBusinessException(
    this.code,
    this.message, {
    this.statusCode = 400,
    this.details = const {},
  });

  @override
  String toString() => message;
}

abstract interface class LanMasterBusinessGateway {
  Future<LanCustomerCheckout> fetchCustomerCheckout(int customerId);

  Future<LanSalesPage> fetchSales({required int limit});

  Future<LanSaleDetails?> fetchSaleDetails({required int saleId});

  Future<LanSaleVoidResult> voidSale({
    required LanRemoteUser actor,
    required int saleId,
  });

  Future<LanCatalogPage> fetchCatalog({
    required String query,
    required int offset,
    required int limit,
  });

  Future<LanMedicineAlternativesResult> fetchMedicineAlternatives({
    required int productId,
  });

  Future<String?> resolveProductImagePath({required int productId});

  Future<List<LanCustomerSummary>> fetchCustomers({
    required String query,
    required int limit,
  });

  Future<List<LanEmployeeSummary>> fetchSalespeople({
    required String query,
    required int limit,
  });

  Future<LanCashierShiftSnapshot?> getOwnShift({required LanRemoteUser actor});

  Future<LanCashierShiftSnapshot> openOwnShift({
    required LanRemoteUser actor,
    required int openingCashCents,
    String? notes,
  });

  Future<LanCashierShiftSnapshot> closeOwnShift({
    required LanRemoteUser actor,
    int? shiftId,
    required int countedCashCents,
    String? notes,
  });

  Future<LanReturnableSalesPage> fetchReturnableSales({
    required String query,
    required int offset,
    required int limit,
  });

  Future<LanReturnableSaleDetails?> fetchReturnableSale({required int saleId});

  Future<LanSaleReturnsPage> fetchSaleReturns({
    required String query,
    required int offset,
    required int limit,
  });

  Future<LanSaleReturnDetails?> fetchSaleReturnDetails({
    required int returnId,
    required bool adjustment,
  });

  Future<LanSaleReturnResult> createSaleReturn({
    required LanRemoteUser actor,
    required LanSaleReturnRequest request,
  });

  Future<LanSaleReturnResult> createSaleAdjustmentReturn({
    required LanRemoteUser actor,
    required LanSaleAdjustmentReturnRequest request,
  });

  Future<List<LanConsignmentReturnSource>>
  fetchConsignmentAdjustmentReturnSources({
    required int productId,
    int? variantId,
  });

  Future<LanProductStockSourceSnapshot> fetchInventoryStockSources({
    required int productId,
    int? variantId,
  });

  Future<List<LanSupplierSummary>> fetchSuppliers({
    required String query,
    required int limit,
  });

  Future<LanReturnablePurchasesPage> fetchReturnablePurchases({
    required String query,
    required int offset,
    required int limit,
  });

  Future<LanReturnablePurchaseDetails?> fetchReturnablePurchase({
    required int purchaseId,
  });

  Future<LanPurchaseReturnsPage> fetchPurchaseReturns({
    required String query,
    required int offset,
    required int limit,
  });

  Future<LanPurchaseReturnDetails?> fetchPurchaseReturnDetails({
    required int returnId,
    required bool adjustment,
  });

  Future<LanPurchaseReturnResult> createPurchaseReturn({
    required LanRemoteUser actor,
    required LanPurchaseReturnRequest request,
  });

  Future<LanPurchaseReturnResult> createPurchaseAdjustmentReturn({
    required LanRemoteUser actor,
    required LanPurchaseAdjustmentReturnRequest request,
  });

  Future<void> voidPurchaseReturn({
    required LanRemoteUser actor,
    required int returnId,
    required bool adjustment,
  });

  Future<LanSaleResult> createSale({
    required LanRemoteUser actor,
    required LanSaleRequest request,
  });
}

/// Versioned LAN contract for same-branch warehouse transfers.
///
/// It is deliberately separate from [LanMasterBusinessGateway] so older test
/// and integration gateways remain valid. The server advertises the matching
/// capability only when this contract is installed.
abstract interface class LanWarehouseTransferGateway {
  Future<List<LanWarehouseTransferWarehouse>> fetchTransferWarehouses({
    required LanRemoteUser actor,
  });

  Future<List<LanWarehouseTransferDocument>> fetchWarehouseTransfers({
    required LanRemoteUser actor,
    required Set<String> statuses,
    required int limit,
  });

  Future<List<LanWarehouseTransferCatalogItem>> fetchWarehouseTransferCatalog({
    required LanRemoteUser actor,
    required String warehouseId,
    required String query,
    required int offset,
  });

  Future<LanWarehouseTransferDocument> createWarehouseTransfer({
    required LanRemoteUser actor,
    required LanWarehouseTransferCreateRequest request,
  });

  Future<LanWarehouseTransferDocument> cancelWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required LanWarehouseTransferReasonRequest request,
  });

  Future<LanWarehouseTransferDocument> dispatchWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required String requestKey,
  });

  Future<List<LanWarehouseTransferPendingAllocation>>
  fetchWarehouseTransferPending({
    required LanRemoteUser actor,
    required String transferId,
  });

  Future<LanWarehouseTransferDocument> receiveWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required LanWarehouseTransferReceiptRequest request,
  });

  Future<LanWarehouseTransferDocument> recallWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required LanWarehouseTransferReasonRequest request,
  });
}

class LanWarehouseTransferWarehouse {
  const LanWarehouseTransferWarehouse({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name};

  factory LanWarehouseTransferWarehouse.fromJson(Map<String, dynamic> json) =>
      LanWarehouseTransferWarehouse(
        id: json['id']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

class LanWarehouseTransferCatalogItem {
  const LanWarehouseTransferCatalogItem({
    required this.productId,
    required this.variantId,
    required this.name,
    required this.code,
    required this.quantity,
    required this.supplierOwnedQuantity,
    required this.quantityScale,
    required this.measurementType,
  });

  final int productId;
  final int variantId;
  final String name;
  final String code;
  final int quantity;
  final int supplierOwnedQuantity;
  final int quantityScale;
  final String measurementType;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variantId': variantId,
    'name': name,
    'code': code,
    'quantity': quantity,
    'supplierOwnedQuantity': supplierOwnedQuantity,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
  };

  factory LanWarehouseTransferCatalogItem.fromJson(Map<String, dynamic> json) =>
      LanWarehouseTransferCatalogItem(
        productId: (json['productId'] as num).toInt(),
        variantId: (json['variantId'] as num).toInt(),
        name: json['name']?.toString() ?? '',
        code: json['code']?.toString() ?? '',
        quantity: (json['quantity'] as num).toInt(),
        supplierOwnedQuantity: (json['supplierOwnedQuantity'] as num).toInt(),
        quantityScale: (json['quantityScale'] as num).toInt(),
        measurementType: json['measurementType']?.toString() ?? 'piece',
      );
}

class LanWarehouseTransferDocument {
  const LanWarehouseTransferDocument({
    required this.id,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required this.status,
    required this.lineCount,
    required this.notes,
    required this.recalled,
  });

  final String id;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final String status;
  final int lineCount;
  final String notes;
  final bool recalled;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceWarehouseId': sourceWarehouseId,
    'destinationWarehouseId': destinationWarehouseId,
    'status': status,
    'lineCount': lineCount,
    'notes': notes,
    'recalled': recalled,
  };

  factory LanWarehouseTransferDocument.fromJson(Map<String, dynamic> json) =>
      LanWarehouseTransferDocument(
        id: json['id']?.toString() ?? '',
        sourceWarehouseId: json['sourceWarehouseId']?.toString() ?? '',
        destinationWarehouseId:
            json['destinationWarehouseId']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        lineCount: (json['lineCount'] as num).toInt(),
        notes: json['notes']?.toString() ?? '',
        recalled: json['recalled'] == true,
      );
}

class LanWarehouseTransferLineRequest {
  const LanWarehouseTransferLineRequest({
    required this.productId,
    required this.variantId,
    required this.quantity,
  });

  final int productId;
  final int variantId;
  final int quantity;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variantId': variantId,
    'quantity': quantity,
  };

  factory LanWarehouseTransferLineRequest.fromJson(Map<String, dynamic> json) =>
      LanWarehouseTransferLineRequest(
        productId: (json['productId'] as num).toInt(),
        variantId: (json['variantId'] as num).toInt(),
        quantity: (json['quantity'] as num).toInt(),
      );
}

class LanWarehouseTransferCreateRequest {
  LanWarehouseTransferCreateRequest({
    required this.requestKey,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required List<LanWarehouseTransferLineRequest> lines,
    this.notes = '',
  }) : lines = List.unmodifiable(lines);

  final String requestKey;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final List<LanWarehouseTransferLineRequest> lines;
  final String notes;

  Map<String, dynamic> toJson() => {
    'requestKey': requestKey,
    'sourceWarehouseId': sourceWarehouseId,
    'destinationWarehouseId': destinationWarehouseId,
    'lines': lines.map((line) => line.toJson()).toList(growable: false),
    'notes': notes,
  };

  factory LanWarehouseTransferCreateRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawLines = json['lines'];
    if (rawLines is! List || rawLines.isEmpty || rawLines.length > 500) {
      throw const FormatException('Transfer requires 1 to 500 lines.');
    }
    final lines = rawLines
        .whereType<Map<String, dynamic>>()
        .map(LanWarehouseTransferLineRequest.fromJson)
        .toList(growable: false);
    if (lines.length != rawLines.length) {
      throw const FormatException('Transfer lines are invalid.');
    }
    return LanWarehouseTransferCreateRequest(
      requestKey: json['requestKey']?.toString() ?? '',
      sourceWarehouseId: json['sourceWarehouseId']?.toString() ?? '',
      destinationWarehouseId: json['destinationWarehouseId']?.toString() ?? '',
      lines: lines,
      notes: json['notes']?.toString() ?? '',
    );
  }
}

class LanWarehouseTransferPendingAllocation {
  const LanWarehouseTransferPendingAllocation({
    required this.allocationId,
    required this.remainingQuantity,
    required this.quantityScale,
    required this.productName,
    required this.code,
    required this.ownerType,
  });

  final String allocationId;
  final int remainingQuantity;
  final int quantityScale;
  final String productName;
  final String code;
  final String ownerType;

  Map<String, dynamic> toJson() => {
    'allocationId': allocationId,
    'remainingQuantity': remainingQuantity,
    'quantityScale': quantityScale,
    'productName': productName,
    'code': code,
    'ownerType': ownerType,
  };

  factory LanWarehouseTransferPendingAllocation.fromJson(
    Map<String, dynamic> json,
  ) => LanWarehouseTransferPendingAllocation(
    allocationId: json['allocationId']?.toString() ?? '',
    remainingQuantity: (json['remainingQuantity'] as num).toInt(),
    quantityScale: (json['quantityScale'] as num).toInt(),
    productName: json['productName']?.toString() ?? '',
    code: json['code']?.toString() ?? '',
    ownerType: json['ownerType']?.toString() ?? 'owned',
  );
}

class LanWarehouseTransferReceiptItemRequest {
  const LanWarehouseTransferReceiptItemRequest({
    required this.allocationId,
    this.acceptedQuantity = 0,
    this.damagedQuantity = 0,
    this.lostQuantity = 0,
  });

  final String allocationId;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int lostQuantity;

  Map<String, dynamic> toJson() => {
    'allocationId': allocationId,
    'acceptedQuantity': acceptedQuantity,
    'damagedQuantity': damagedQuantity,
    'lostQuantity': lostQuantity,
  };

  factory LanWarehouseTransferReceiptItemRequest.fromJson(
    Map<String, dynamic> json,
  ) => LanWarehouseTransferReceiptItemRequest(
    allocationId: json['allocationId']?.toString() ?? '',
    acceptedQuantity: (json['acceptedQuantity'] as num? ?? 0).toInt(),
    damagedQuantity: (json['damagedQuantity'] as num? ?? 0).toInt(),
    lostQuantity: (json['lostQuantity'] as num? ?? 0).toInt(),
  );
}

class LanWarehouseTransferReceiptRequest {
  LanWarehouseTransferReceiptRequest({
    required this.requestKey,
    required List<LanWarehouseTransferReceiptItemRequest> items,
    this.notes = '',
  }) : items = List.unmodifiable(items);

  final String requestKey;
  final List<LanWarehouseTransferReceiptItemRequest> items;
  final String notes;

  Map<String, dynamic> toJson() => {
    'requestKey': requestKey,
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'notes': notes,
  };

  factory LanWarehouseTransferReceiptRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawItems = json['items'];
    if (rawItems is! List || rawItems.isEmpty || rawItems.length > 5000) {
      throw const FormatException('Transfer receipt requires items.');
    }
    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map(LanWarehouseTransferReceiptItemRequest.fromJson)
        .toList(growable: false);
    if (items.length != rawItems.length) {
      throw const FormatException('Transfer receipt items are invalid.');
    }
    return LanWarehouseTransferReceiptRequest(
      requestKey: json['requestKey']?.toString() ?? '',
      items: items,
      notes: json['notes']?.toString() ?? '',
    );
  }
}

class LanWarehouseTransferReasonRequest {
  const LanWarehouseTransferReasonRequest({
    required this.requestKey,
    required this.reason,
  });

  final String requestKey;
  final String reason;

  Map<String, dynamic> toJson() => {'requestKey': requestKey, 'reason': reason};

  factory LanWarehouseTransferReasonRequest.fromJson(
    Map<String, dynamic> json,
  ) => LanWarehouseTransferReasonRequest(
    requestKey: json['requestKey']?.toString() ?? '',
    reason: json['reason']?.toString() ?? '',
  );
}
