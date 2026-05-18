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
  /// Each component = original × (returnQty / origQty) using truncating
  /// integer division (matching existing behaviour).
  ///
  /// Returns zeroes when [originalQuantity] <= 0.
  static ProportionalReturnResult computeProportionalReturn({
    required int originalQuantity,
    required int returnQuantity,
    required int originalSubtotalCents,
    required int originalDiscountCents,
    required int originalTaxCents,
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

    final subtotal =
        (originalSubtotalCents * returnQuantity) ~/ originalQuantity;
    final discount =
        (originalDiscountCents * returnQuantity) ~/ originalQuantity;
    final tax = (originalTaxCents * returnQuantity) ~/ originalQuantity;
    // refund = subtotal - discount + tax  (net value + tax)
    final refund = subtotal - discount + tax;

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
