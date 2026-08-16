// ══════════════════════════════════════════════════════════════════════════════
// RETURN CALCULATION SERVICE
// ══════════════════════════════════════════════════════════════════════════════

/// Result of a proportional return computation.
class ProportionalReturnResult {
  final int subtotalCents;
  final int discountCents;
  final int taxCents;

  /// subtotal - discount + tax
  final int refundCents;

  const ProportionalReturnResult({
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.refundCents,
  });
}

/// Financial history of non-voided returns that are linked to one invoice
/// line. Adjustment returns are deliberately excluded: they have their own
/// price and journal policy and only participate in the quantity cap.
class LinkedReturnHistory {
  final int quantity;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int refundCents;

  const LinkedReturnHistory({
    required this.quantity,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.refundCents,
  });

  static const zero = LinkedReturnHistory(
    quantity: 0,
    subtotalCents: 0,
    discountCents: 0,
    taxCents: 0,
    refundCents: 0,
  );

  LinkedReturnHistory add(ProportionalReturnResult value, int addedQuantity) {
    return LinkedReturnHistory(
      quantity: quantity + addedQuantity,
      subtotalCents: subtotalCents + value.subtotalCents,
      discountCents: discountCents + value.discountCents,
      taxCents: taxCents + value.taxCents,
      refundCents: refundCents + value.refundCents,
    );
  }
}

/// Shape of one line's contribution to a return rollup. Mirrors the four
/// integer-cent components produced by [ReturnCalculationService.computeProportionalReturn]
/// plus the return quantity, expressed as a Dart record so callers can build
/// the iterable inline without a wrapper class.
typedef ReturnLineAmounts = ({
  int subtotalCents,
  int discountCents,
  int taxCents,
  int refundCents,
  int quantity,
});

/// Aggregated rollup over a list of per-line return amounts.
///
/// Phase-5 of the scattered-calculation migration (see
/// `docs/adr/0001-pricing-engines-as-sot.md`) collapses the four parallel
/// `fold(Decimal.zero, +)` loops that lived in `SaleReturnFormState` and
/// `PurchaseReturnFormState` into a single call to
/// [ReturnCalculationService.aggregate], so every return-side total has
/// exactly one arithmetic path.
class ReturnRollup {
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int refundCents;
  final int totalQuantity;

  const ReturnRollup({
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.refundCents,
    required this.totalQuantity,
  });

  static const ReturnRollup empty = ReturnRollup(
    subtotalCents: 0,
    discountCents: 0,
    taxCents: 0,
    refundCents: 0,
    totalQuantity: 0,
  );
}

/// Static-only service for proportional return computation.
///
/// ERP Golden Rule: each component of the original transaction is reversed
/// proportionally using integer math.
///
/// Same pattern as `TaxCalculationService`.
class ReturnCalculationService {
  ReturnCalculationService._();

  /// Compute proportional reversal amounts.
  ///
  /// Each component is the difference between the cumulative proportional
  /// target and the amounts already reversed by earlier *linked* returns.
  /// This preserves integer-cent rounding across sequential partial returns:
  /// the last linked return receives the remaining cents.
  ///
  /// Adjustment returns must never be included in [previousLinkedHistory].
  /// They are independent transactions and do not reverse this invoice line
  /// frozen discount/tax amounts.
  ///
  /// Returns zeroes when [originalQuantity] <= 0.
  static ProportionalReturnResult computeProportionalReturn({
    required int originalQuantity,
    required int returnQuantity,
    required int originalSubtotalCents,
    required int originalDiscountCents,
    required int originalTaxCents,
    LinkedReturnHistory previousLinkedHistory = LinkedReturnHistory.zero,
    bool taxInclusivePricing = false,
  }) {
    assert(returnQuantity >= 0, 'returnQuantity must be non-negative');

    if (originalQuantity <= 0) {
      return const ProportionalReturnResult(
        subtotalCents: 0,
        discountCents: 0,
        taxCents: 0,
        refundCents: 0,
      );
    }

    final cumulativeQuantity = previousLinkedHistory.quantity + returnQuantity;
    if (cumulativeQuantity > originalQuantity) {
      throw ArgumentError.value(
        cumulativeQuantity,
        'cumulativeReturnQuantity',
        'Linked returns cannot exceed the original invoice quantity',
      );
    }

    int remainingAllocation(int originalCents, int previouslyReturnedCents) {
      final cumulativeTarget =
          (originalCents * cumulativeQuantity) ~/ originalQuantity;
      return cumulativeTarget - previouslyReturnedCents;
    }

    final subtotal = remainingAllocation(
      originalSubtotalCents,
      previousLinkedHistory.subtotalCents,
    );
    final discount = remainingAllocation(
      originalDiscountCents,
      previousLinkedHistory.discountCents,
    );
    final tax = remainingAllocation(
      originalTaxCents,
      previousLinkedHistory.taxCents,
    );
    // Exclusive prices add tax; inclusive prices already contain it.
    final refund = subtotal - discount + (taxInclusivePricing ? 0 : tax);

    return ProportionalReturnResult(
      subtotalCents: subtotal,
      discountCents: discount,
      taxCents: tax,
      refundCents: refund,
    );
  }

  /// Aggregate a list of per-line return amounts into a single [ReturnRollup].
  ///
  /// Sole rollup writer used by both `SaleReturnFormState` and
  /// `PurchaseReturnFormState`. Pure-additive integer math — no rounding,
  /// no division — so the rollup is exactly Σ of its inputs.
  static ReturnRollup aggregate(Iterable<ReturnLineAmounts> lines) {
    var subtotal = 0;
    var discount = 0;
    var tax = 0;
    var refund = 0;
    var quantity = 0;
    for (final line in lines) {
      subtotal += line.subtotalCents;
      discount += line.discountCents;
      tax += line.taxCents;
      refund += line.refundCents;
      quantity += line.quantity;
    }
    return ReturnRollup(
      subtotalCents: subtotal,
      discountCents: discount,
      taxCents: tax,
      refundCents: refund,
      totalQuantity: quantity,
    );
  }
}
