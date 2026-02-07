import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class PurchaseEntity extends Equatable {
  final int id;
  final String purchaseNumber;
  final int supplierId;
  final String? supplierName;
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
  final DateTime createdAt;
  final DateTime updatedAt;

  PurchaseEntity({
    required this.id,
    required this.purchaseNumber,
    required this.supplierId,
    this.supplierName,
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
        id, purchaseNumber, supplierId, supplierName,
        subtotalCents, discountCents, taxCents, totalCents,
        paidAmountCents, currencyId, status, paymentMethod,
        supplierInvoiceRef, notes, purchaseDate, dueDate,
        createdAt, updatedAt,
      ];
}

class PurchaseItemEntity extends Equatable {
  final int id;
  final int purchaseId;
  final int productId;
  final int? variantId;
  final String? productName;
  final String? variantSku;
  final int quantity;
  final Decimal unitCostCents;
  final Decimal discountCents;
  final Decimal subtotalCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final DateTime? expiryDate;
  final DateTime createdAt;

  PurchaseItemEntity({
    required this.id,
    required this.purchaseId,
    required this.productId,
    this.variantId,
    this.productName,
    this.variantSku,
    required this.quantity,
    required this.unitCostCents,
    Decimal? discountCents,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    this.expiryDate,
    required this.createdAt,
  }) : discountCents = discountCents ?? Decimal.zero;

  @override
  List<Object?> get props => [
        id, purchaseId, productId, variantId, productName, variantSku,
        quantity, unitCostCents, discountCents, subtotalCents, taxCents,
        totalCents, expiryDate, createdAt,
      ];
}

class PurchaseReturnEntity extends Equatable {
  final int id;
  final int purchaseId;
  final String returnNumber;
  final String? supplierName;
  final Decimal totalCents;
  final int currencyId;
  final String status;
  final String dispositionType;
  final String? reason;
  final DateTime returnDate;
  final DateTime createdAt;

  const PurchaseReturnEntity({
    required this.id,
    required this.purchaseId,
    required this.returnNumber,
    this.supplierName,
    required this.totalCents,
    required this.currencyId,
    this.status = 'draft',
    this.dispositionType = 'restock',
    this.reason,
    required this.returnDate,
    required this.createdAt,
  });

  bool get isDraft => status == 'draft';
  bool get isPosted => status == 'posted';
  bool get isVoided => status == 'voided';

  @override
  List<Object?> get props => [
        id, purchaseId, returnNumber, supplierName,
        totalCents, currencyId, status, dispositionType,
        reason, returnDate, createdAt,
      ];
}

class PurchaseReturnItemEntity extends Equatable {
  final int id;
  final int returnId;
  final int purchaseItemId;
  final int quantity;
  final Decimal refundCents;
  final String? reason;
  final String? productName;
  final String? variantSku;
  final DateTime createdAt;

  const PurchaseReturnItemEntity({
    required this.id,
    required this.returnId,
    required this.purchaseItemId,
    required this.quantity,
    required this.refundCents,
    this.reason,
    this.productName,
    this.variantSku,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id, returnId, purchaseItemId, quantity,
        refundCents, reason, productName, variantSku, createdAt,
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
        id, purchaseId, amountCents, currencyId,
        paymentMethod, reference, notes, paymentDate, createdAt,
      ];
}
