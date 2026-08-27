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

  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'sku': sku,
    'barcode': barcode,
    'colorName': colorName,
    'colorHex': colorHex,
    'sizeName': sizeName,
    'priceCents': priceCents,
    'wholesalePriceCents': wholesalePriceCents,
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
      stockQuantity: (json['stockQuantity'] as num).toInt(),
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
    'variants': variants.map((value) => value.toJson()).toList(),
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'segment': segment,
    'balanceCents': balanceCents,
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
  final bool enableTaxCalculations;
  final int defaultSalesTaxRateBps;
  final bool taxInclusivePricing;
  final bool allowNegativeStock;
  final bool allowPartialPayments;
  final bool requireCustomerForSales;
  final bool allowDiscounts;
  final double maxDiscountPercent;

  const LanCatalogPage({
    required this.products,
    required this.offset,
    required this.limit,
    required this.hasMore,
    required this.currencyId,
    required this.currencyCode,
    required this.currencySymbol,
    required this.enableTaxCalculations,
    required this.defaultSalesTaxRateBps,
    required this.taxInclusivePricing,
    required this.allowNegativeStock,
    required this.allowPartialPayments,
    required this.requireCustomerForSales,
    this.allowDiscounts = true,
    this.maxDiscountPercent = 100,
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
    'enableTaxCalculations': enableTaxCalculations,
    'defaultSalesTaxRateBps': defaultSalesTaxRateBps,
    'taxInclusivePricing': taxInclusivePricing,
    'allowNegativeStock': allowNegativeStock,
    'allowPartialPayments': allowPartialPayments,
    'requireCustomerForSales': requireCustomerForSales,
    'allowDiscounts': allowDiscounts,
    'maxDiscountPercent': maxDiscountPercent,
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
      enableTaxCalculations: json['enableTaxCalculations'] != false,
      defaultSalesTaxRateBps:
          (json['defaultSalesTaxRateBps'] as num?)?.toInt() ?? 0,
      taxInclusivePricing: json['taxInclusivePricing'] == true,
      allowNegativeStock: json['allowNegativeStock'] == true,
      allowPartialPayments: json['allowPartialPayments'] == true,
      requireCustomerForSales: json['requireCustomerForSales'] == true,
      allowDiscounts: json['allowDiscounts'] != false,
      maxDiscountPercent:
          (json['maxDiscountPercent'] as num?)?.toDouble() ?? 100,
    );
  }
}

class LanReturnableSaleSummary {
  final int saleId;
  final String invoiceNumber;
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

  const LanReturnableSaleDetails({required this.sale, required this.lines});

  Map<String, dynamic> toJson() => {
    'sale': sale.toJson(),
    'lines': lines.map((value) => value.toJson()).toList(),
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

  const LanSaleReturnRequest({
    required this.idempotencyKey,
    required this.saleId,
    required this.dispositionType,
    required this.refundMethod,
    this.reason,
    this.dueDate,
    required this.lines,
  });

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'saleId': saleId,
    'dispositionType': dispositionType,
    'refundMethod': refundMethod,
    'reason': reason,
    'dueDate': dueDate?.toUtc().toIso8601String(),
    'lines': lines.map((value) => value.toJson()).toList(),
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

class LanSaleAdjustmentReturnLineRequest {
  final int productId;
  final int? variantId;
  final int quantity;
  final int unitPriceCents;
  final int discountCents;
  final int discountPercentBps;
  final String dispositionType;
  final String? reason;

  const LanSaleAdjustmentReturnLineRequest({
    required this.productId,
    this.variantId,
    required this.quantity,
    required this.unitPriceCents,
    this.discountCents = 0,
    this.discountPercentBps = 0,
    this.dispositionType = 'restock',
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
    reason: json['reason']?.toString(),
  );
}

class LanSaleAdjustmentReturnRequest {
  final String idempotencyKey;
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

  const LanSaleAdjustmentReturnRequest({
    required this.idempotencyKey,
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
  });

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
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
  };

  factory LanSaleAdjustmentReturnRequest.fromJson(Map<String, dynamic> json) =>
      LanSaleAdjustmentReturnRequest(
        idempotencyKey: json['idempotencyKey']?.toString() ?? '',
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
        overallDiscountCents:
            (json['overallDiscountCents'] as num?)?.toInt() ?? 0,
        overallDiscountIsPercent: json['overallDiscountIsPercent'] == true,
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(LanSaleAdjustmentReturnLineRequest.fromJson)
            .toList(growable: false),
      );
}

class LanSaleLineRequest {
  final int productId;
  final int? variantId;
  final int quantity;
  final String priceTier;
  final int? salespersonId;
  final String discountType;
  final int discountValue;

  const LanSaleLineRequest({
    required this.productId,
    this.variantId,
    required this.quantity,
    this.priceTier = 'retail',
    this.salespersonId,
    this.discountType = 'none',
    this.discountValue = 0,
  });

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'variantId': variantId,
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
      quantity: (json['quantity'] as num).toInt(),
      priceTier: json['priceTier']?.toString() ?? 'retail',
      salespersonId: (json['salespersonId'] as num?)?.toInt(),
      discountType: json['discountType']?.toString() ?? 'none',
      discountValue: (json['discountValue'] as num?)?.toInt() ?? 0,
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
  final List<LanSaleLineRequest> lines;

  const LanSaleRequest({
    required this.idempotencyKey,
    this.customerId,
    this.salespersonId,
    required this.paymentMethod,
    this.paidAmountCents,
    this.notes,
    required this.lines,
  });

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'customerId': customerId,
    'salespersonId': salespersonId,
    'paymentMethod': paymentMethod,
    'paidAmountCents': paidAmountCents,
    'notes': notes,
    'lines': lines.map((value) => value.toJson()).toList(),
  };

  factory LanSaleRequest.fromJson(Map<String, dynamic> json) {
    return LanSaleRequest(
      idempotencyKey: json['idempotencyKey']?.toString() ?? '',
      customerId: (json['customerId'] as num?)?.toInt(),
      salespersonId: (json['salespersonId'] as num?)?.toInt(),
      paymentMethod: json['paymentMethod']?.toString() ?? 'cash',
      paidAmountCents: (json['paidAmountCents'] as num?)?.toInt(),
      notes: json['notes']?.toString(),
      lines: (json['lines'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LanSaleLineRequest.fromJson)
          .toList(growable: false),
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
  final bool duplicate;

  const LanSaleResult({
    required this.saleId,
    required this.invoiceNumber,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidAmountCents,
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
      duplicate: json['duplicate'] == true,
    );
  }
}

class LanBusinessException implements Exception {
  final String code;
  final String message;
  final int statusCode;

  const LanBusinessException(this.code, this.message, {this.statusCode = 400});

  @override
  String toString() => message;
}

abstract interface class LanMasterBusinessGateway {
  Future<LanCatalogPage> fetchCatalog({
    required String query,
    required int offset,
    required int limit,
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

  Future<LanSaleReturnResult> createSaleReturn({
    required LanRemoteUser actor,
    required LanSaleReturnRequest request,
  });

  Future<LanSaleReturnResult> createSaleAdjustmentReturn({
    required LanRemoteUser actor,
    required LanSaleAdjustmentReturnRequest request,
  });

  Future<LanSaleResult> createSale({
    required LanRemoteUser actor,
    required LanSaleRequest request,
  });
}
