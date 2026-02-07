import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

class SaleEntity extends Equatable {
  final int id;
  final String invoiceNumber;
  final int? customerId;
  final String? customerName;
  final int? employeeId;
  final Decimal subtotalCents;
  final Decimal taxCents;
  final Decimal discountCents;
  final Decimal totalCents;
  final Decimal paidAmountCents;
  final int currencyId;
  final String paymentMethod;
  final String status;
  final String? notes;
  final DateTime saleDate;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  SaleEntity({
    required this.id,
    required this.invoiceNumber,
    this.customerId,
    this.customerName,
    this.employeeId,
    required this.subtotalCents,
    required this.taxCents,
    required this.discountCents,
    required this.totalCents,
    Decimal? paidAmountCents,
    required this.currencyId,
    required this.paymentMethod,
    required this.status,
    this.notes,
    required this.saleDate,
    this.dueDate,
    required this.createdAt,
    required this.updatedAt,
  }) : paidAmountCents = paidAmountCents ?? Decimal.zero;

  bool get isCompleted => status == 'completed';
  bool get isVoided => status == 'voided';
  bool get isDraft => status == 'draft';
  bool get isPending => status == 'pending';

  Decimal get remainingCents => totalCents - paidAmountCents;
  bool get isFullyPaid => paidAmountCents >= totalCents;
  bool get isOverdue => dueDate != null && !isFullyPaid && DateTime.now().isAfter(dueDate!);

  @override
  List<Object?> get props => [
        id, invoiceNumber, customerId, customerName, employeeId,
        subtotalCents, taxCents, discountCents, totalCents, paidAmountCents,
        currencyId, paymentMethod, status, notes, saleDate, dueDate,
        createdAt, updatedAt,
      ];
}

class SaleItemEntity extends Equatable {
  final int id;
  final int saleId;
  final int productId;
  final String? productName;
  final int? variantId;
  final String? variantSku;
  final int quantity;
  final Decimal unitPriceCents;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final DateTime createdAt;

  const SaleItemEntity({
    required this.id,
    required this.saleId,
    required this.productId,
    this.productName,
    this.variantId,
    this.variantSku,
    required this.quantity,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [
        id, saleId, productId, productName, variantId, variantSku,
        quantity, unitPriceCents, subtotalCents, discountCents,
        taxCents, totalCents, createdAt,
      ];
}

class SaleReturnEntity extends Equatable {
  final int id;
  final int saleId;
  final String? saleInvoiceNumber;
  final String? customerName;
  final String returnNumber;
  final Decimal totalCents;
  final int currencyId;
  final String status;
  final String dispositionType;
  final String? reason;
  final DateTime returnDate;
  final DateTime createdAt;

  const SaleReturnEntity({
    required this.id,
    required this.saleId,
    this.saleInvoiceNumber,
    this.customerName,
    required this.returnNumber,
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
        id, saleId, saleInvoiceNumber, customerName, returnNumber,
        totalCents, currencyId, status, dispositionType, reason,
        returnDate, createdAt,
      ];
}

class SaleReturnItemEntity extends Equatable {
  final int id;
  final int returnId;
  final int saleItemId;
  final int quantity;
  final Decimal refundCents;
  final String? reason;
  final DateTime createdAt;

  const SaleReturnItemEntity({
    required this.id,
    required this.returnId,
    required this.saleItemId,
    required this.quantity,
    required this.refundCents,
    this.reason,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, returnId, saleItemId, quantity, refundCents, reason, createdAt];
}

class SalePaymentEntity extends Equatable {
  final int id;
  final int saleId;
  final Decimal amountCents;
  final int currencyId;
  final String paymentMethod;
  final String? reference;
  final String? notes;
  final DateTime paymentDate;
  final DateTime createdAt;

  const SalePaymentEntity({
    required this.id,
    required this.saleId,
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
        id, saleId, amountCents, currencyId, paymentMethod,
        reference, notes, paymentDate, createdAt,
      ];
}

class SaleDashboardStats extends Equatable {
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

  const SaleDashboardStats({
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

  @override
  List<Object?> get props => [
        totalCount, completedCount, voidedCount, totalSalesCents,
        totalPaidCents, overdueCount,
        returnsCount, totalReturnsCents, todaySalesCents, todayCount,
      ];
}
