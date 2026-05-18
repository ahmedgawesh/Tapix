// ════════════════════════════════════════════════════════════════════════════
// InvoicePricingEngine — single source of truth for invoice-level math
// ════════════════════════════════════════════════════════════════════════════
//
// PURPOSE
//   Compose [LineItemPricingEngine] + [TaxCalculationService] into one
//   call that produces the canonical invoice breakdown:
//       per-line subtotal/discount/net  →  overall discount  →
//       prorated overall discount per line  →  tax on adjusted net  →
//       totals
//
//   Used by every Form-State (PurchaseFormState, SaleFormState, AdjReturn
//   variants, etc.) so the math is computed in **exactly one place**.
//
// CONTRACTS
//   1. Each line's local breakdown follows [LineItemPricingEngine] rules:
//      `subtotal = qty × price`, `discount = on subtotal`, `net = subtotal − discount`.
//   2. Overall percent discount base = `Σ line.net` (i.e. net-after-line-
//      discounts, **before** tax). This is symmetric with the per-line
//      percent semantics, eliminating the "1% per-item ≠ 1% overall" bug.
//   3. Overall discount is distributed proportionally across line nets via
//      the largest-remainder method, so `Σ line.shareOfOverall == overall`.
//   4. Tax per line is computed on `line.net − line.shareOfOverall`
//      (matches QuickBooks / SAP / Xero behavior).
//   5. `total = subtotal − itemDiscount − overall + tax  ==  Σ line.total`.
//
// All arithmetic uses [Money] / [Decimal] internally; no `double` ever.
// ════════════════════════════════════════════════════════════════════════════

import '../money/money.dart';
import '../services/tax_calculation_service.dart';
import 'discount.dart';
import 'line_item_pricing_engine.dart';

/// Input to compute an invoice-level breakdown.
class InvoicePricingInput {
  /// Lines making up the invoice. May be empty (returns zeros).
  final List<LineItemPricingInput> lines;

  /// Optional invoice-level discount applied **after** per-line discounts.
  ///
  /// When [Discount.percent], the percent base is the sum of per-line nets
  /// (`Σ (subtotal − itemDiscount)`), **not** subtotal+tax — this is the
  /// invariant that closes the famous "799.84 vs 799.92" bug.
  final Discount overallDiscount;

  /// Global tax toggle.
  final bool enableTaxCalculations;

  /// Default tax rate in bps used when a line is taxable but the product
  /// has no rate of its own.
  final int defaultTaxRateBps;

  /// Whether prices are tax-inclusive.
  final bool taxInclusivePricing;

  /// Rounding mode for tax. Discount rounding follows [discountRounding].
  final TaxRoundingMode taxRounding;

  /// Rounding mode for discount and money operations.
  final MoneyRoundingMode discountRounding;

  const InvoicePricingInput({
    required this.lines,
    this.overallDiscount = Discount.none,
    required this.enableTaxCalculations,
    required this.defaultTaxRateBps,
    required this.taxInclusivePricing,
    this.taxRounding = TaxRoundingMode.halfUp,
    this.discountRounding = MoneyRoundingMode.halfUp,
  });
}

/// Per-line result inside the invoice breakdown. Extends the local line
/// result with the share of invoice-level discount allocated to it and
/// the net/total **after** that allocation.
class InvoiceLineResult {
  /// Pricing for this line **before** the invoice-level discount.
  /// `localResult.net` is the base used for proration and for the
  /// pre-overall percent base.
  final LineItemPricingResult local;

  /// Share of the overall discount allocated to this line (always
  /// `>= 0` and sums exactly to the overall discount across all lines).
  final Money shareOfOverallDiscount;

  /// Net after applying the share of overall discount: `local.net − share`,
  /// clamped to `>= 0`.
  final Money adjustedNet;

  /// Tax computed on [adjustedNet]. Replaces `local.tax` in the totals.
  final Money tax;

  /// `adjustedNet + tax` — the contribution of this line to the invoice total.
  final Money total;

  const InvoiceLineResult({
    required this.local,
    required this.shareOfOverallDiscount,
    required this.adjustedNet,
    required this.tax,
    required this.total,
  });

  /// Convenience: `local.subtotal`.
  Money get subtotal => local.subtotal;

  /// Convenience: `local.discount + shareOfOverallDiscount`.
  /// The total discount actually applied to this line.
  Money get totalLineDiscount => local.discount + shareOfOverallDiscount;

  /// The tax rate (bps) actually used.
  int get effectiveTaxRateBps => local.effectiveTaxRateBps;
}

/// Aggregate invoice breakdown.
class InvoicePricingResult {
  final List<InvoiceLineResult> lines;

  /// `Σ line.subtotal`.
  final Money subtotal;

  /// `Σ line.local.discount` — sum of per-line discounts.
  final Money itemDiscountTotal;

  /// Resolved overall discount (`overallDiscount.resolve(...)`).
  final Money overallDiscount;

  /// `itemDiscountTotal + overallDiscount`.
  final Money totalDiscount;

  /// Sum of per-line tax (after overall-discount distribution).
  final Money tax;

  /// `subtotal − totalDiscount + tax`, clamped to `>= 0`.
  final Money total;

  const InvoicePricingResult({
    required this.lines,
    required this.subtotal,
    required this.itemDiscountTotal,
    required this.overallDiscount,
    required this.totalDiscount,
    required this.tax,
    required this.total,
  });

  /// Empty breakdown (no lines).
  factory InvoicePricingResult.empty() => InvoicePricingResult(
        lines: const [],
        subtotal: Money.zero,
        itemDiscountTotal: Money.zero,
        overallDiscount: Money.zero,
        totalDiscount: Money.zero,
        tax: Money.zero,
        total: Money.zero,
      );

  @override
  String toString() =>
      'InvoicePricingResult(subtotal=$subtotal, itemDisc=$itemDiscountTotal, '
      'overallDisc=$overallDiscount, tax=$tax, total=$total, '
      'lines=${lines.length})';
}

/// Pure, stateless invoice pricing engine.
class InvoicePricingEngine {
  InvoicePricingEngine._();

  /// Compute the canonical invoice breakdown.
  ///
  /// **Steps:**
  /// 1. For each line, compute its local breakdown **without** tax (we
  ///    delay tax until after overall-discount allocation).
  /// 2. Resolve the overall discount against `Σ line.local.net`.
  /// 3. Allocate the overall discount across lines proportionally to
  ///    `line.local.net` using largest-remainder.
  /// 4. For each line, `adjustedNet = line.local.net − share`. Compute
  ///    tax on `adjustedNet`.
  /// 5. Aggregate.
  static InvoicePricingResult compute(InvoicePricingInput input) {
    if (input.lines.isEmpty) {
      return InvoicePricingResult.empty();
    }

    // ── Step 1: local breakdown (no tax yet) ──
    final locals = input.lines
        .map((l) => LineItemPricingEngine.compute(
              input: l,
              // Disable tax at this stage; we'll compute tax after the
              // overall-discount allocation so its base is correct.
              enableTaxCalculations: false,
              defaultTaxRateBps: input.defaultTaxRateBps,
              taxInclusivePricing: input.taxInclusivePricing,
              discountRounding: input.discountRounding,
              taxRounding: input.taxRounding,
            ))
        .toList(growable: false);

    // ── Step 2: overall discount base = Σ line.net ──
    final preOverallNet = locals.fold<Money>(
      Money.zero,
      (sum, l) => sum + l.net,
    );

    // Resolve overall discount against this base. Since base is pre-tax,
    // a 1 % overall discount equals 1 % per-line discount when all lines
    // share the same rate — closing the bug.
    final overallDiscount = input.overallDiscount
        .resolve(preOverallNet, mode: input.discountRounding);

    // ── Step 3: distribute overall discount proportionally to line nets ──
    List<Money> shares;
    if (overallDiscount.isZero) {
      shares = List<Money>.filled(locals.length, Money.zero);
    } else {
      final weights = locals.map((l) => l.net.cents).toList(growable: false);
      shares = overallDiscount.allocate(weights);
    }

    // ── Steps 4-5: per-line tax on adjusted net + aggregate ──
    final lineResults = <InvoiceLineResult>[];
    Money totalSubtotal = Money.zero;
    Money totalItemDiscount = Money.zero;
    Money totalTax = Money.zero;

    for (int i = 0; i < locals.length; i++) {
      final local = locals[i];
      final share = shares[i];
      final adjustedNet = (local.net - share).clampNonNegative();

      Money tax = Money.zero;
      int rateBps = 0;
      if (input.enableTaxCalculations && !adjustedNet.isZero) {
        rateBps = TaxCalculationService.resolveLineItemTaxRateBps(
          isTaxable: input.lines[i].isTaxable,
          productTaxRateBps: input.lines[i].productTaxRateBps,
          defaultTaxRateBps: input.defaultTaxRateBps,
        );
        if (rateBps > 0) {
          final taxDec = TaxCalculationService.calculateTax(
            taxableAmountCents: adjustedNet.decimalCents,
            taxRateBps: rateBps,
            taxInclusivePricing: input.taxInclusivePricing,
            roundingMode: input.taxRounding,
          );
          tax = Money.fromDecimalCents(taxDec);
        }
      }

      // Rebuild a local result that carries the resolved tax rate even
      // though tax was deferred at step 1.
      final localWithRate = LineItemPricingResult(
        subtotal: local.subtotal,
        discount: local.discount,
        net: local.net,
        tax: Money.zero, // tax lives on the InvoiceLineResult below
        total: local.net,
        effectiveTaxRateBps: rateBps,
      );

      lineResults.add(InvoiceLineResult(
        local: localWithRate,
        shareOfOverallDiscount: share,
        adjustedNet: adjustedNet,
        tax: tax,
        total: adjustedNet + tax,
      ));

      totalSubtotal = totalSubtotal + local.subtotal;
      totalItemDiscount = totalItemDiscount + local.discount;
      totalTax = totalTax + tax;
    }

    final totalDiscount = totalItemDiscount + overallDiscount;
    final total =
        (totalSubtotal - totalDiscount + totalTax).clampNonNegative();

    return InvoicePricingResult(
      lines: List.unmodifiable(lineResults),
      subtotal: totalSubtotal,
      itemDiscountTotal: totalItemDiscount,
      overallDiscount: overallDiscount,
      totalDiscount: totalDiscount,
      tax: totalTax,
      total: total,
    );
  }
}
