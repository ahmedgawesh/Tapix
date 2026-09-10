import 'package:equatable/equatable.dart';

/// One real settlement leg captured while an invoice is created.
///
/// Credit is deliberately not represented as a payment: any difference
/// between the invoice total and [CheckoutSettlement.totalAllocatedCents]
/// remains in accounts receivable/payable. A cheque allocation reserves part
/// of the checkout total for a physical instrument, but it is not a payment
/// and does not settle the party obligation until bank clearance is confirmed.
class CheckoutPaymentAllocation extends Equatable {
  final String method;
  final int amountCents;
  final String? reference;
  final String? bankName;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final String? note;

  const CheckoutPaymentAllocation({
    required this.method,
    required this.amountCents,
    this.reference,
    this.bankName,
    this.issueDate,
    this.dueDate,
    this.note,
  });

  bool get isCheque {
    final normalized = method.trim().toLowerCase();
    return normalized == 'cheque' || normalized == 'check';
  }

  @override
  List<Object?> get props => [
    method,
    amountCents,
    reference,
    bankName,
    issueDate,
    dueDate,
    note,
  ];
}

class CheckoutSettlement extends Equatable {
  final List<CheckoutPaymentAllocation> payments;

  const CheckoutSettlement(this.payments);

  /// Total tender allocated at checkout, including open cheques.
  int get totalAllocatedCents =>
      payments.fold(0, (sum, payment) => sum + payment.amountCents);

  /// Amount that settles an invoice's AR/AP immediately.
  ///
  /// Open cheques are deliberately excluded. They remain pending instruments
  /// and only become payments when bank clearance is explicitly confirmed.
  int get totalSettledCents => payments
      .where((payment) => !payment.isCheque)
      .fold(0, (sum, payment) => sum + payment.amountCents);

  /// Backwards-compatible alias for the amount actually paid now.
  int get totalPaidCents => totalSettledCents;

  String get headerPaymentMethod {
    if (payments.isEmpty) return 'credit';
    final methods = payments.map((payment) => payment.method).toSet();
    return methods.length == 1 ? methods.single : 'mixed';
  }

  void validate({required int invoiceTotalCents}) {
    if (invoiceTotalCents <= 0) {
      throw ArgumentError.value(invoiceTotalCents, 'invoiceTotalCents');
    }
    if (payments.isEmpty) {
      throw ArgumentError('settlement_requires_payment');
    }
    for (final payment in payments) {
      if (payment.amountCents <= 0) {
        throw ArgumentError('settlement_amount_invalid');
      }
      if (payment.isCheque) {
        if (payment.reference?.trim().isEmpty ?? true) {
          throw ArgumentError('cheque_number_required');
        }
        if (payment.dueDate == null) {
          throw ArgumentError('cheque_due_date_required');
        }
        if (payment.issueDate != null &&
            payment.dueDate!.isBefore(payment.issueDate!)) {
          throw ArgumentError('cheque_due_before_issue');
        }
      }
    }
    if (totalAllocatedCents > invoiceTotalCents) {
      throw ArgumentError('settlement_exceeds_invoice_total');
    }
  }

  @override
  List<Object?> get props => [payments];
}
