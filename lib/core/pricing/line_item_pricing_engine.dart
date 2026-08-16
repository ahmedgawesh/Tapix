// ════════════════════════════════════════════════════════════════════════════
// LineItemPricingEngine — single source of truth for one-line math
// ════════════════════════════════════════════════════════════════════════════
//
// PURPOSE
//   Compute, for **one** invoice/return line, the canonical sequence:
//       subtotal → discount → net → tax → total
//   using a single rounded-once contract. Every form-state, DAO, and report
//   that needs line totals MUST go through this engine. Direct arithmetic
//   on cents elsewhere is now considered a bug.
//
//   Tax is delegated to the existing [TaxCalculationService] so we do not
//   duplicate the tax engine — we only own the discount + composition logic.
//
// CONTRACTS
//   - subtotal  =  unitPrice × quantity                  (exact)
//   - discount  =  Discount.resolve(base = subtotal)      (% base = subtotal)
//   - net       =  max(0, subtotal − discount)
//   - tax       =  TaxCalculationService.calculateTax(net, rate, inclusive)
//   - total     =  net + tax (exclusive), or net (inclusive)
//
//   ⚠ The percent-discount base is **always the subtotal (pre-tax)**, never
//   subtotal+tax. This is the documented invariant guarded by tests and is
//   the fix for the "799.84 vs 799.92" bug.
// ════════════════════════════════════════════════════════════════════════════

import '../money/money.dart';
import '../services/tax_calculation_service.dart';
import 'discount.dart';

/// Inputs to compute a single line.
class LineItemPricingInput {
  /// Unit price (e.g. 100.00 EGP → `Money.fromCents(10000)`).
  final Money unitPrice;

  /// Whole-unit quantity. Must be `>= 0`. Returns flow as positive
  /// quantities; negation happens at journal-posting time.
  final int quantity;

  /// Number of stored quantity units that make one priced unit. Count items
  /// use 1; measured products use 1000 (e.g. 250 g is quantity=250 while
  /// [unitPrice] remains the price per kilogram).
  final int quantityScale;

  /// Optional per-line discount.
  final Discount discount;

  /// Whether the underlying product is flagged taxable.
  final bool isTaxable;

  /// Product-level tax rate in basis points. 0 disables tax for this line
  /// when there is no global default.
  final int productTaxRateBps;

  const LineItemPricingInput({
    required this.unitPrice,
    required this.quantity,
    this.quantityScale = 1,
    this.discount = Discount.none,
    required this.isTaxable,
    required this.productTaxRateBps,
  });
}

/// Result of computing a single line.
class LineItemPricingResult {
  /// `unitPrice × quantity`.
  final Money subtotal;

  /// Effective discount applied to this line.
  final Money discount;

  /// `max(0, subtotal − discount)`. The taxable base for this line.
  final Money net;

  /// Tax computed by [TaxCalculationService.calculateTax] over [net].
  final Money tax;

  /// `net + tax` for exclusive pricing, or `net` for inclusive pricing.
  final Money total;

  /// Tax rate in bps actually used (may differ from product rate when
  /// falling back to global default).
  final int effectiveTaxRateBps;

  const LineItemPricingResult({
    required this.subtotal,
    required this.discount,
    required this.net,
    required this.tax,
    required this.total,
    required this.effectiveTaxRateBps,
  });

  @override
  String toString() =>
      'LineItemPricingResult(subtotal=$subtotal, discount=$discount, '
      'net=$net, tax=$tax, total=$total, rate=${effectiveTaxRateBps}bps)';
}

/// Pricing engine for a single line. Stateless, pure, deterministic.
class LineItemPricingEngine {
  LineItemPricingEngine._();

  /// Compute the canonical breakdown for one line.
  ///
  /// [enableTaxCalculations] toggles tax globally; when false, the result's
  /// `tax` field is always zero regardless of the product's rate.
  static LineItemPricingResult compute({
    required LineItemPricingInput input,
    required bool enableTaxCalculations,
    required int defaultTaxRateBps,
    required bool taxInclusivePricing,
    MoneyRoundingMode discountRounding = MoneyRoundingMode.halfUp,
    TaxRoundingMode taxRounding = TaxRoundingMode.halfUp,
  }) {
    if (input.quantity < 0) {
      throw ArgumentError(
        'LineItemPricingEngine: quantity must be >= 0, got ${input.quantity}',
      );
    }
    if (input.quantityScale <= 0) {
      throw ArgumentError(
        'LineItemPricingEngine: quantityScale must be > 0, got '
        '${input.quantityScale}',
      );
    }

    final subtotal = input.unitPrice
        .multiplyRatio(input.quantity, input.quantityScale)
        .round(discountRounding);
    final discount = input.discount.resolve(subtotal, mode: discountRounding);
    final net = (subtotal - discount).clampNonNegative();

    int rateBps = 0;
    Money tax = Money.zero;
    if (enableTaxCalculations && !net.isZero) {
      rateBps = TaxCalculationService.resolveLineItemTaxRateBps(
        isTaxable: input.isTaxable,
        productTaxRateBps: input.productTaxRateBps,
        defaultTaxRateBps: defaultTaxRateBps,
      );
      if (rateBps > 0) {
        final taxDec = TaxCalculationService.calculateTax(
          taxableAmountCents: net.decimalCents,
          taxRateBps: rateBps,
          taxInclusivePricing: taxInclusivePricing,
          roundingMode: taxRounding,
        );
        tax = Money.fromDecimalCents(taxDec);
      }
    }

    final total = Money.fromDecimalCents(
      TaxCalculationService.composeTotal(
        netCents: net.decimalCents,
        taxCents: tax.decimalCents,
        taxInclusivePricing: taxInclusivePricing,
      ),
    );

    return LineItemPricingResult(
      subtotal: subtotal,
      discount: discount,
      net: net,
      tax: tax,
      total: total,
      effectiveTaxRateBps: rateBps,
    );
  }

  /// Convenience: compute the discount only (without tax). Useful for
  /// UIs that need to display "you save X" before commit. Same contract
  /// as [compute]: the percent base is `unitPrice × quantity`.
  static Money resolveDiscount({
    required Money unitPrice,
    required int quantity,
    int quantityScale = 1,
    required Discount discount,
    MoneyRoundingMode mode = MoneyRoundingMode.halfUp,
  }) {
    if (quantityScale <= 0) {
      throw ArgumentError.value(quantityScale, 'quantityScale');
    }
    final subtotal = unitPrice
        .multiplyRatio(quantity, quantityScale)
        .round(mode);
    return discount.resolve(subtotal, mode: mode);
  }
}
