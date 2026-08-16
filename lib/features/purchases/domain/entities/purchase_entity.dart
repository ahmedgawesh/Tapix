import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class PurchaseEntity extends Equatable {
  final int id;
  final String purchaseNumber;
  final int supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final Decimal paidAmountCents;
  final int currencyId;
  final String status;
  final String? paymentMethod;
  final String? supplierInvoiceRef;
  final String? notes;
  final DateTime purchaseDate;
  final DateTime? dueDate;
  final bool taxInclusiveAtPost;
  final DateTime createdAt;
  final DateTime updatedAt;

  PurchaseEntity({
    required this.id,
    required this.purchaseNumber,
    required this.supplierId,
    this.supplierName,
    this.supplierPhone,
    required this.subtotalCents,
    Decimal? discountCents,
    required this.taxCents,
    required this.totalCents,
    Decimal? paidAmountCents,
    required this.currencyId,
    required this.status,
    this.paymentMethod,
    this.supplierInvoiceRef,
    this.notes,
    required this.purchaseDate,
    this.dueDate,
    this.taxInclusiveAtPost = false,
    required this.createdAt,
    required this.updatedAt,
  }) : discountCents = discountCents ?? Decimal.zero,
       paidAmountCents = paidAmountCents ?? Decimal.zero;

  bool get isDraft => status == 'draft' || status == 'pending';
  bool get isPosted => status == 'posted';
  bool get isVoided => status == 'voided';

  Decimal get remainingCents {
    final r = totalCents - paidAmountCents;
    return r < Decimal.zero ? Decimal.zero : r;
  }

  bool get isFullyPaid => paidAmountCents >= totalCents;

  bool get isOverdue {
    if (dueDate == null || isFullyPaid || isVoided) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  @override
  List<Object?> get props => [
    id,
    purchaseNumber,
    supplierId,
    supplierName,
    supplierPhone,
    subtotalCents,
    discountCents,
    taxCents,
    totalCents,
    paidAmountCents,
    currencyId,
    status,
    paymentMethod,
    supplierInvoiceRef,
    notes,
    purchaseDate,
    dueDate,
    taxInclusiveAtPost,
    createdAt,
    updatedAt,
  ];
}

class PurchaseItemEntity extends Equatable {
  final int id;
  final int purchaseId;
  final int productId;
  final int? variantId;
  final String? productName;
  final String? variantSku;

  /// Per-variant attributes resolved at the DAO level. They MUST come from
  /// joins on `productColors`/`sizes` keyed by the line's own `variantId`
  /// — never from a productId-keyed lookup — so invoices that contain
  /// multiple variants of the same product render each line correctly.
  final String? colorName;
  final String? colorHex;
  final String? sizeName;

  /// Current on-hand stock for this product/variant when loaded with details.
  /// Purchase-return forms cap the invoice entitlement by this physical limit.
  final int? currentStockQuantity;
  final bool tracksInventory;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final Decimal unitCostCents;
  final Decimal discountCents;
  final Decimal subtotalCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final Decimal? originalCostCents;
  final Decimal? originalPriceCents;
  final Decimal? originalWholesalePriceCents;
  final Decimal? newSellPriceCents;
  final Decimal? newWholesalePriceCents;
  final DateTime? expiryDate;
  final DateTime createdAt;

  PurchaseItemEntity({
    required this.id,
    required this.purchaseId,
    required this.productId,
    this.variantId,
    this.productName,
    this.variantSku,
    this.colorName,
    this.colorHex,
    this.sizeName,
    this.currentStockQuantity,
    this.tracksInventory = true,
    required this.quantity,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.unitCostCents,
    Decimal? discountCents,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    this.originalCostCents,
    this.originalPriceCents,
    this.originalWholesalePriceCents,
    this.newSellPriceCents,
    this.newWholesalePriceCents,
    this.expiryDate,
    required this.createdAt,
  }) : discountCents = discountCents ?? Decimal.zero;

  @override
  List<Object?> get props => [
    id,
    purchaseId,
    productId,
    variantId,
    productName,
    variantSku,
    colorName,
    colorHex,
    sizeName,
    currentStockQuantity,
    tracksInventory,
    quantity,
    quantityScale,
    measurementType,
    unitCostCents,
    discountCents,
    subtotalCents,
    taxCents,
    totalCents,
    originalCostCents,
    originalPriceCents,
    originalWholesalePriceCents,
    newSellPriceCents,
    newWholesalePriceCents,
    expiryDate,
    createdAt,
  ];
}

class PurchaseReturnEntity extends Equatable {
  final int id;
  final int purchaseId;
  final String returnNumber;
  final String? supplierName;
  final String? supplierPhone;
  final int? supplierId;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final int currencyId;
  final String status;
  final String dispositionType;

  /// cash, credit, cheque
  final String refundMethod;
  final String? reason;
  final DateTime returnDate;
  final DateTime createdAt;

  /// True if this return is an adjustment (not linked to an invoice).
  final bool isAdjustment;

  /// Unique identifier across both linked and adjustment returns.
  /// Format: "PR-{id}" for linked, "PRA-{id}" for adjustment.
  final String unifiedId;

  PurchaseReturnEntity({
    required this.id,
    required this.purchaseId,
    required this.returnNumber,
    this.supplierName,
    this.supplierPhone,
    this.supplierId,
    Decimal? subtotalCents,
    Decimal? discountCents,
    Decimal? taxCents,
    required this.totalCents,
    required this.currencyId,
    this.status = 'draft',
    this.dispositionType = 'restock',
    this.refundMethod = 'credit',
    this.reason,
    required this.returnDate,
    required this.createdAt,
    this.isAdjustment = false,
    String? unifiedId,
  }) : subtotalCents = subtotalCents ?? Decimal.zero,
       discountCents = discountCents ?? Decimal.zero,
       taxCents = taxCents ?? Decimal.zero,
       unifiedId = unifiedId ?? (isAdjustment ? 'PRA-$id' : 'PR-$id');

  bool get isDraft => status == 'draft';
  bool get isPosted => status == 'posted';
  bool get isVoided => status == 'voided';

  @override
  List<Object?> get props => [
    id,
    purchaseId,
    returnNumber,
    supplierName,
    supplierId,
    subtotalCents,
    discountCents,
    taxCents,
    totalCents,
    currencyId,
    status,
    dispositionType,
    refundMethod,
    reason,
    returnDate,
    createdAt,
    isAdjustment,
    unifiedId,
  ];
}

class PurchaseReturnItemEntity extends Equatable {
  final int id;
  final int returnId;
  final int purchaseItemId;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal refundCents;
  final String? reason;
  final String? productName;
  final String? variantSku;
  final String? variantBarcode;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final DateTime createdAt;

  PurchaseReturnItemEntity({
    required this.id,
    required this.returnId,
    required this.purchaseItemId,
    required this.quantity,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    Decimal? subtotalCents,
    Decimal? discountCents,
    Decimal? taxCents,
    required this.refundCents,
    this.reason,
    this.productName,
    this.variantSku,
    this.variantBarcode,
    this.colorName,
    this.colorHex,
    this.sizeName,
    required this.createdAt,
  }) : subtotalCents = subtotalCents ?? Decimal.zero,
       discountCents = discountCents ?? Decimal.zero,
       taxCents = taxCents ?? Decimal.zero;

  @override
  List<Object?> get props => [
    id,
    returnId,
    purchaseItemId,
    quantity,
    quantityScale,
    measurementType,
    subtotalCents,
    discountCents,
    taxCents,
    refundCents,
    reason,
    productName,
    variantSku,
    variantBarcode,
    colorName,
    colorHex,
    sizeName,
    createdAt,
  ];
}

class PurchasePaymentEntity extends Equatable {
  final int id;
  final int purchaseId;
  final Decimal amountCents;
  final int currencyId;
  final String paymentMethod;
  final String? reference;
  final String? notes;
  final DateTime paymentDate;
  final DateTime createdAt;

  const PurchasePaymentEntity({
    required this.id,
    required this.purchaseId,
    required this.amountCents,
    required this.currencyId,
    required this.paymentMethod,
    this.reference,
    this.notes,
    required this.paymentDate,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
    id,
    purchaseId,
    amountCents,
    currencyId,
    paymentMethod,
    reference,
    notes,
    paymentDate,
    createdAt,
  ];
}
