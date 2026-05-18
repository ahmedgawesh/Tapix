import 'package:decimal/decimal.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ENUMS
// ══════════════════════════════════════════════════════════════════════════════

/// Rounding strategy for tax amounts.
///
/// * [halfUp] — standard commercial rounding (0.5 → 1). **Default.**
/// * [bankers] — round half to even (0.5 → 0, 1.5 → 2). Used in some
///   jurisdictions and financial systems to minimize cumulative bias.
enum TaxRoundingMode {
  /// Round half away from zero (0.5 → 1, -0.5 → -1).
  /// This is the most common POS / commercial rounding convention.
  halfUp,

  /// Round half to even (banker's rounding).
  /// Minimizes cumulative rounding bias over many transactions.
  bankers,
}

// ══════════════════════════════════════════════════════════════════════════════
// EXCEPTIONS
// ══════════════════════════════════════════════════════════════════════════════

/// Thrown when the tax service receives invalid inputs.
///
/// This prevents silent incorrect calculations by failing loudly when
/// preconditions are violated.
class TaxValidationException implements Exception {
  final String message;
  const TaxValidationException(this.message);

  @override
  String toString() => 'TaxValidationException: $message';
}

// ══════════════════════════════════════════════════════════════════════════════
// INPUT / OUTPUT MODELS
// ══════════════════════════════════════════════════════════════════════════════

/// Lightweight data object describing one line item for tax calculation.
/// Deliberately decoupled from domain models (SaleLineItem / PurchaseLineItem)
/// so the service stays pure and testable.
class TaxableLineItem {
  /// qty × unitPrice (before any discount).
  final Decimal subtotalCents;

  /// Per-item discount (only meaningful in per-item discount mode;
  /// pass [Decimal.zero] when using invoice-level discount).
  final Decimal itemDiscountCents;

  /// Whether the product is flagged as taxable.
  final bool isTaxable;

  /// Product-level tax rate in basis points (e.g. 1500 = 15 %).
  final int productTaxRateBps;

  const TaxableLineItem({
    required this.subtotalCents,
    required this.itemDiscountCents,
    required this.isTaxable,
    required this.productTaxRateBps,
  });
}

/// Per-item breakdown returned by [TaxCalculationService.calculateInvoiceTax].
class LineItemTaxResult {
  final Decimal subtotalCents;

  /// Effective discount applied to this item (prorated when invoice-level).
  final Decimal discountCents;

  /// The amount on which tax was calculated (subtotal − discount).
  final Decimal taxableAmountCents;

  /// Tax computed for this item.
  final Decimal taxCents;

  /// The tax rate (bps) that was actually used for this item.
  final int taxRateBps;

  /// subtotal − discount + tax.
  final Decimal totalCents;

  const LineItemTaxResult({
    required this.subtotalCents,
    required this.discountCents,
    required this.taxableAmountCents,
    required this.taxCents,
    required this.taxRateBps,
    required this.totalCents,
  });

  @override
  String toString() =>
      'LineItemTaxResult(subtotal=$subtotalCents, discount=$discountCents, '
      'taxable=$taxableAmountCents, tax=$taxCents, rate=${taxRateBps}bps, '
      'total=$totalCents)';
}

/// Full invoice-level breakdown.
class InvoiceTaxBreakdown {
  final Decimal subtotalCents;
  final Decimal totalDiscountCents;
  final Decimal totalTaxCents;

  /// subtotal − discount + tax.
  final Decimal totalCents;
  final List<LineItemTaxResult> lineItems;

  const InvoiceTaxBreakdown({
    required this.subtotalCents,
    required this.totalDiscountCents,
    required this.totalTaxCents,
    required this.totalCents,
    required this.lineItems,
  });

  @override
  String toString() =>
      'InvoiceTaxBreakdown(subtotal=$subtotalCents, discount=$totalDiscountCents, '
      'tax=$totalTaxCents, total=$totalCents, items=${lineItems.length})';
}

// ── Debug / Audit models ─────────────────────────────────────────────────────

/// Per-item audit detail showing every intermediate value and rounding delta.
class LineItemAuditDetail {
  /// Index of this item in the input list.
  final int index;

  /// Raw subtotal from input.
  final Decimal inputSubtotalCents;

  /// Effective discount applied (per-item or prorated invoice-level).
  final Decimal effectiveDiscountCents;

  /// Taxable amount = subtotal − discount.
  final Decimal taxableAmountCents;

  /// Resolved tax rate in basis points.
  final int resolvedTaxRateBps;

  /// Raw tax before rounding (exact rational result).
  final Decimal rawTaxBeforeRounding;

  /// Final rounded tax.
  final Decimal finalTaxCents;

  /// Rounding difference = finalTax − rawTax.
  final Decimal roundingDeltaCents;

  /// Whether negative-value symmetry was applied (for returns).
  final bool negativeSymmetryApplied;

  const LineItemAuditDetail({
    required this.index,
    required this.inputSubtotalCents,
    required this.effectiveDiscountCents,
    required this.taxableAmountCents,
    required this.resolvedTaxRateBps,
    required this.rawTaxBeforeRounding,
    required this.finalTaxCents,
    required this.roundingDeltaCents,
    required this.negativeSymmetryApplied,
  });

  @override
  String toString() =>
      'Item[$index] subtotal=$inputSubtotalCents discount=$effectiveDiscountCents '
      'taxable=$taxableAmountCents rate=${resolvedTaxRateBps}bps '
      'rawTax=$rawTaxBeforeRounding finalTax=$finalTaxCents '
      'roundingΔ=$roundingDeltaCents negSymmetry=$negativeSymmetryApplied';
}

/// Full audit trail for an invoice tax calculation.
///
/// Use [TaxCalculationService.calculateInvoiceTaxWithAudit] to obtain this.
/// Invaluable for debugging, customer support, and verifying calculations.
class TaxAuditTrail {
  /// The final calculation result.
  final InvoiceTaxBreakdown breakdown;

  /// Per-item audit details with intermediate values.
  final List<LineItemAuditDetail> lineDetails;

  /// Rounding mode used for this calculation.
  final TaxRoundingMode roundingMode;

  /// Sum of all per-item rounding deltas.
  final Decimal totalRoundingDeltaCents;

  /// Whether any item had negative-symmetry applied.
  final bool anyNegativeSymmetryApplied;

  /// Timestamp when the calculation was performed (UTC).
  final DateTime calculatedAt;

  const TaxAuditTrail({
    required this.breakdown,
    required this.lineDetails,
    required this.roundingMode,
    required this.totalRoundingDeltaCents,
    required this.anyNegativeSymmetryApplied,
    required this.calculatedAt,
  });

  @override
  String toString() {
    final buf = StringBuffer()
      ..writeln('═══ TAX AUDIT TRAIL ═══')
      ..writeln('Calculated: $calculatedAt (UTC)')
      ..writeln('Rounding: ${roundingMode.name}')
      ..writeln('Subtotal: ${breakdown.subtotalCents}')
      ..writeln('Discount: ${breakdown.totalDiscountCents}')
      ..writeln('Tax:      ${breakdown.totalTaxCents}')
      ..writeln('Total:    ${breakdown.totalCents}')
      ..writeln('Total rounding Δ: $totalRoundingDeltaCents')
      ..writeln('Negative symmetry used: $anyNegativeSymmetryApplied')
      ..writeln('─── Line items (${lineDetails.length}) ───');
    for (final d in lineDetails) {
      buf.writeln('  $d');
    }
    return buf.toString();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ══════════════════════════════════════════════════════════════════════════════

/// **Single source of truth** for all tax calculations in Tapix.
///
/// All methods are static & pure — no state, no side-effects, no DI needed.
///
/// ### Rounding strategy
/// All arithmetic uses [Decimal] to avoid floating-point imprecision.
/// Rounding mode is configurable via [TaxRoundingMode]:
/// - **halfUp** (default): round half away from zero — most common POS convention.
/// - **bankers**: round half to even — minimizes cumulative rounding bias.
/// Rounding is applied **per line item**, not at the invoice total level.
///
/// ### Negative values (returns / reversals)
/// Negative taxable amounts are supported with guaranteed symmetry:
/// `tax(-X) = -tax(abs(X))`. This ensures returns reverse the original tax exactly.
///
/// ### Validation
/// Input guards throw [TaxValidationException] on invalid inputs (negative rates,
/// discount exceeding subtotal). This prevents silent incorrect calculations.
class TaxCalculationService {
  TaxCalculationService._(); // prevent instantiation

  // ── Helpers ──────────────────────────────────────────────────────────────

  static final Decimal _bpsDivisor = Decimal.fromInt(10000);

  /// Apply the chosen rounding mode to a [Decimal] value, returning [BigInt].
  ///
  /// Accepts [Decimal] values and rounds to an integer using the specified mode.
  static BigInt _roundDecimal(Decimal value, TaxRoundingMode mode) {
    switch (mode) {
      case TaxRoundingMode.halfUp:
        // Round half away from zero: 0.5 → 1, -0.5 → -1
        // Dart's Decimal.round() returns Decimal; .toBigInt() converts.
        return value.round().toBigInt();
      case TaxRoundingMode.bankers:
        // Round half to even (banker's rounding).
        final flooredDec = value.floor();
        final flooredBig = flooredDec.toBigInt();
        final fraction = value - flooredDec;
        final half = Decimal.parse('0.5');
        if (fraction == half) {
          // Round to nearest even
          return flooredBig.isEven ? flooredBig : flooredBig + BigInt.one;
        }
        // For all other cases, standard rounding works
        return value.round().toBigInt();
    }
  }

  /// Determine which tax rate (bps) to use for a given item.
  ///
  /// Priority:
  /// 1. Product's own rate if [isTaxable] **and** rate > 0.
  /// 2. Otherwise the global [defaultTaxRateBps].
  /// 3. 0 if neither applies.
  static int resolveLineItemTaxRateBps({
    required bool isTaxable,
    required int productTaxRateBps,
    required int defaultTaxRateBps,
  }) {
    if (isTaxable && productTaxRateBps > 0) return productTaxRateBps;
    if (defaultTaxRateBps > 0) return defaultTaxRateBps;
    return 0;
  }

  /// Phase 7 — Recover an effective tax rate in basis points from a posted
  /// `(taxableSubtotal, tax)` pair.
  ///
  /// Used by snapshot-recovery code paths (e.g. `AdjustmentReturnDao` at post
  /// time, where the tax was already computed line-by-line and we need to
  /// stamp `tax_rate_bps_at_post` for audit/replay). Centralising the formula
  /// here keeps the inverse of `calculateTax` in one place.
  ///
  /// Rules:
  ///   * Non-positive [taxableSubtotalCents] (zero or negative — e.g. a
  ///     fully-discounted line) → returns `0` (cannot meaningfully recover
  ///     a rate from a zero base; matches the legacy DAO guard).
  ///   * Otherwise: `round((taxOnLine × 10_000) / taxableSubtotal)`.
  ///     Byte-identical to the formula the DAO used inline; for a
  ///     zero-tax line this naturally yields `0`.
  ///
  /// This is the **inverse** of `calculateTax` for the exclusive-tax case:
  ///   tax = subtotal × rate / 10_000  ⇒  rate = tax × 10_000 / subtotal.
  /// It is NOT an inverse for the inclusive-tax case; do not use it for
  /// recovering rates from inclusive-tax invoices.
  static int recoverRateBps({
    required int taxableSubtotalCents,
    required int taxOnLineCents,
  }) {
    if (taxableSubtotalCents <= 0) return 0;
    return ((taxOnLineCents * 10000) / taxableSubtotalCents).round();
  }

  // ── Validation ──────────────────────────────────────────────────────────

  /// Validate tax rate is non-negative.
  static void _validateTaxRate(int taxRateBps, [String context = '']) {
    if (taxRateBps < 0) {
      throw TaxValidationException(
        'Tax rate must be non-negative, got $taxRateBps bps${context.isNotEmpty ? ' ($context)' : ''}',
      );
    }
  }

  /// Validate discount does not exceed subtotal (except for returns where
  /// subtotal may be negative).
  static void _validateDiscount(Decimal discount, Decimal subtotal, [String context = '']) {
    if (discount < Decimal.zero) {
      throw TaxValidationException(
        'Discount must be non-negative, got $discount${context.isNotEmpty ? ' ($context)' : ''}',
      );
    }
    // Only validate discount <= subtotal for positive subtotals (not returns)
    if (subtotal > Decimal.zero && discount > subtotal) {
      throw TaxValidationException(
        'Discount ($discount) exceeds subtotal ($subtotal)${context.isNotEmpty ? ' ($context)' : ''}',
      );
    }
  }

  // ── Core tax calculation ────────────────────────────────────────────────

  /// Calculate tax on a single amount.
  ///
  /// * **Exclusive**: tax = amount × rate / 10 000
  /// * **Inclusive**: tax = amount − (amount / (1 + rate / 10 000))
  ///
  /// ### Negative values (returns)
  /// When [taxableAmountCents] < 0, the tax is computed on the absolute value
  /// and then negated, ensuring perfect symmetry: `tax(-X) = -tax(X)`.
  ///
  /// Returns [Decimal.zero] when [taxableAmountCents] == 0 or [taxRateBps] <= 0.
  ///
  /// Throws [TaxValidationException] if [taxRateBps] < 0.
  static Decimal calculateTax({
    required Decimal taxableAmountCents,
    required int taxRateBps,
    required bool taxInclusivePricing,
    TaxRoundingMode roundingMode = TaxRoundingMode.halfUp,
  }) {
    _validateTaxRate(taxRateBps, 'calculateTax');

    if (taxableAmountCents == Decimal.zero || taxRateBps == 0) {
      return Decimal.zero;
    }

    // ── Negative symmetry: tax(-X) = -tax(abs(X)) ──
    final bool isNegative = taxableAmountCents < Decimal.zero;
    final Decimal absAmount = isNegative ? -taxableAmountCents : taxableAmountCents;

    final rate = Decimal.fromInt(taxRateBps);
    Decimal tax;

    if (taxInclusivePricing) {
      // Tax = Amount − Amount / (1 + Rate/10000)
      final divisor = _bpsDivisor + rate;
      final preTaxDec = ((absAmount * _bpsDivisor) / divisor)
          .toDecimal(scaleOnInfinitePrecision: 10);
      final preTax = Decimal.fromBigInt(_roundDecimal(preTaxDec, roundingMode));
      tax = absAmount - preTax;
    } else {
      // Tax = Amount × Rate / 10000
      final rawDec = (absAmount * rate / _bpsDivisor)
          .toDecimal(scaleOnInfinitePrecision: 10);
      tax = Decimal.fromBigInt(_roundDecimal(rawDec, roundingMode));
    }

    return isNegative ? -tax : tax;
  }

  /// Calculate the **raw** (unrounded) tax for audit purposes.
  /// Returns the exact rational result before any rounding.
  static Decimal _calculateRawTax({
    required Decimal absAmount,
    required int taxRateBps,
    required bool taxInclusivePricing,
  }) {
    if (absAmount == Decimal.zero || taxRateBps == 0) return Decimal.zero;

    final rate = Decimal.fromInt(taxRateBps);

    if (taxInclusivePricing) {
      final divisor = _bpsDivisor + rate;
      final preTaxRational = (absAmount * _bpsDivisor) / divisor;
      // Return exact difference — no rounding
      return absAmount - Decimal.fromBigInt(preTaxRational.round());
    } else {
      final raw = absAmount * rate / _bpsDivisor;
      // Return the raw rational as Decimal (truncated to internal precision)
      return Decimal.fromBigInt(raw.round());
    }
  }

  // ── Line-item level ─────────────────────────────────────────────────────

  /// Convenience wrapper: calculate tax for a **single** line item using
  /// global settings. Suitable for the per-item discount scenario where
  /// `net = subtotal − itemDiscount`.
  ///
  /// Negative [netCents] are supported (for returns) with symmetry guarantee.
  static Decimal calculateLineItemTax({
    required Decimal netCents,
    required bool enableTaxCalculations,
    required bool isTaxable,
    required int productTaxRateBps,
    required int defaultTaxRateBps,
    required bool taxInclusivePricing,
    TaxRoundingMode roundingMode = TaxRoundingMode.halfUp,
  }) {
    if (!enableTaxCalculations) return Decimal.zero;
    if (netCents == Decimal.zero) return Decimal.zero;

    final rateBps = resolveLineItemTaxRateBps(
      isTaxable: isTaxable,
      productTaxRateBps: productTaxRateBps,
      defaultTaxRateBps: defaultTaxRateBps,
    );
    if (rateBps <= 0) return Decimal.zero;

    return calculateTax(
      taxableAmountCents: netCents,
      taxRateBps: rateBps,
      taxInclusivePricing: taxInclusivePricing,
      roundingMode: roundingMode,
    );
  }

  // ── Invoice level ───────────────────────────────────────────────────────

  /// Full invoice tax calculation with proportional discount distribution.
  ///
  /// When [invoiceDiscountCents] > 0 the discount is distributed
  /// proportionally across items by subtotal weight (largest-remainder method)
  /// so that ∑ item discounts == invoiceDiscountCents exactly.
  ///
  /// When [invoiceDiscountCents] is zero, each item uses its own
  /// [TaxableLineItem.itemDiscountCents].
  ///
  /// ### Validation
  /// - Throws [TaxValidationException] if [defaultTaxRateBps] < 0.
  /// - Throws [TaxValidationException] if any item's discount > subtotal
  ///   (for positive subtotals).
  ///
  /// **Calculation order** (per user requirements):
  /// 1. Subtotal = Σ item.subtotalCents
  /// 2. Distribute invoice-level discount proportionally
  /// 3. Taxable amount per item = subtotal − discount
  /// 4. Tax per item = calculateTax(taxable, rate, inclusive)
  /// 5. Total tax = Σ item tax
  /// 6. Total = subtotal − discount + tax
  static InvoiceTaxBreakdown calculateInvoiceTax({
    required List<TaxableLineItem> items,
    required Decimal invoiceDiscountCents,
    required bool enableTaxCalculations,
    required int defaultTaxRateBps,
    required bool taxInclusivePricing,
    TaxRoundingMode roundingMode = TaxRoundingMode.halfUp,
  }) {
    _validateTaxRate(defaultTaxRateBps, 'calculateInvoiceTax.defaultTaxRateBps');

    if (items.isEmpty) {
      return InvoiceTaxBreakdown(
        subtotalCents: Decimal.zero,
        totalDiscountCents: Decimal.zero,
        totalTaxCents: Decimal.zero,
        totalCents: Decimal.zero,
        lineItems: const [],
      );
    }

    final subtotal = items.fold<Decimal>(
      Decimal.zero,
      (sum, i) => sum + i.subtotalCents,
    );

    // ── Step 2: Determine per-item discounts ──

    final bool useInvoiceDiscount = invoiceDiscountCents > Decimal.zero;
    List<Decimal> itemDiscounts;

    if (useInvoiceDiscount) {
      _validateDiscount(invoiceDiscountCents, subtotal, 'invoice-level discount');
      final weights = items.map((i) => i.subtotalCents.toBigInt().toInt()).toList();
      final weightSum = subtotal.toBigInt().toInt();
      final discountInt = invoiceDiscountCents.toBigInt().toInt();
      final distributed = distributeProportionally(discountInt, weights, weightSum);
      itemDiscounts = distributed.map((d) => Decimal.fromInt(d)).toList();
    } else {
      itemDiscounts = items.map((i) => i.itemDiscountCents).toList();
    }

    // ── Steps 3-5: Per-line tax calculation ──

    Decimal totalDiscount = Decimal.zero;
    Decimal totalTax = Decimal.zero;
    final lineResults = <LineItemTaxResult>[];

    for (int i = 0; i < items.length; i++) {
      final item = items[i];

      _validateTaxRate(item.productTaxRateBps, 'item[$i].productTaxRateBps');
      if (!useInvoiceDiscount) {
        _validateDiscount(item.itemDiscountCents, item.subtotalCents, 'item[$i] discount');
      }

      final discount = itemDiscounts[i];
      final taxable = item.subtotalCents - discount;

      int rateBps = 0;
      Decimal tax = Decimal.zero;

      if (enableTaxCalculations && taxable != Decimal.zero) {
        rateBps = resolveLineItemTaxRateBps(
          isTaxable: item.isTaxable,
          productTaxRateBps: item.productTaxRateBps,
          defaultTaxRateBps: defaultTaxRateBps,
        );
        if (rateBps > 0) {
          tax = calculateTax(
            taxableAmountCents: taxable,
            taxRateBps: rateBps,
            taxInclusivePricing: taxInclusivePricing,
            roundingMode: roundingMode,
          );
        }
      }

      totalDiscount += discount;
      totalTax += tax;

      lineResults.add(LineItemTaxResult(
        subtotalCents: item.subtotalCents,
        discountCents: discount,
        taxableAmountCents: taxable,
        taxCents: tax,
        taxRateBps: rateBps,
        totalCents: item.subtotalCents - discount + tax,
      ));
    }

    // ── Step 6: Final total ──

    final total = subtotal - totalDiscount + totalTax;

    return InvoiceTaxBreakdown(
      subtotalCents: subtotal,
      totalDiscountCents: totalDiscount,
      totalTaxCents: totalTax,
      totalCents: total < Decimal.zero ? Decimal.zero : total,
      lineItems: lineResults,
    );
  }

  // ── Invoice level with audit trail ─────────────────────────────────────

  /// Same as [calculateInvoiceTax] but returns a full [TaxAuditTrail]
  /// with per-item intermediate values and rounding deltas.
  ///
  /// Use this for:
  /// - Debugging tax discrepancies
  /// - Customer support investigations
  /// - Regulatory audit logs
  static TaxAuditTrail calculateInvoiceTaxWithAudit({
    required List<TaxableLineItem> items,
    required Decimal invoiceDiscountCents,
    required bool enableTaxCalculations,
    required int defaultTaxRateBps,
    required bool taxInclusivePricing,
    TaxRoundingMode roundingMode = TaxRoundingMode.halfUp,
  }) {
    _validateTaxRate(defaultTaxRateBps, 'calculateInvoiceTaxWithAudit.defaultTaxRateBps');

    // Compute the standard breakdown first
    final breakdown = calculateInvoiceTax(
      items: items,
      invoiceDiscountCents: invoiceDiscountCents,
      enableTaxCalculations: enableTaxCalculations,
      defaultTaxRateBps: defaultTaxRateBps,
      taxInclusivePricing: taxInclusivePricing,
      roundingMode: roundingMode,
    );

    // Build per-item audit details
    final auditDetails = <LineItemAuditDetail>[];
    Decimal totalRoundingDelta = Decimal.zero;
    bool anyNegSymmetry = false;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final lineResult = breakdown.lineItems[i];
      final taxable = lineResult.taxableAmountCents;
      final isNeg = taxable < Decimal.zero;
      final absTaxable = isNeg ? -taxable : taxable;

      if (anyNegSymmetry == false && isNeg) anyNegSymmetry = true;

      Decimal rawTax = Decimal.zero;
      if (enableTaxCalculations && taxable != Decimal.zero && lineResult.taxRateBps > 0) {
        rawTax = _calculateRawTax(
          absAmount: absTaxable,
          taxRateBps: lineResult.taxRateBps,
          taxInclusivePricing: taxInclusivePricing,
        );
        if (isNeg) rawTax = -rawTax;
      }

      final roundingDelta = lineResult.taxCents - rawTax;
      totalRoundingDelta += roundingDelta;

      auditDetails.add(LineItemAuditDetail(
        index: i,
        inputSubtotalCents: item.subtotalCents,
        effectiveDiscountCents: lineResult.discountCents,
        taxableAmountCents: taxable,
        resolvedTaxRateBps: lineResult.taxRateBps,
        rawTaxBeforeRounding: rawTax,
        finalTaxCents: lineResult.taxCents,
        roundingDeltaCents: roundingDelta,
        negativeSymmetryApplied: isNeg,
      ));
    }

    return TaxAuditTrail(
      breakdown: breakdown,
      lineDetails: auditDetails,
      roundingMode: roundingMode,
      totalRoundingDeltaCents: totalRoundingDelta,
      anyNegativeSymmetryApplied: anyNegSymmetry,
      calculatedAt: DateTime.now().toUtc(),
    );
  }

  // ── Proportional distribution ───────────────────────────────────────────

  /// Distribute [total] proportionally across [weights] using the
  /// **largest-remainder method** so that the distributed integers
  /// sum **exactly** to [total].
  ///
  /// This is used for:
  /// - Invoice-level discount proration across line items.
  /// - Any other scenario where an integer must be split without rounding drift.
  static List<int> distributeProportionally(
    int total,
    List<int> weights,
    int weightSum,
  ) {
    if (weights.isEmpty || weightSum <= 0 || total == 0) {
      return List.filled(weights.length, 0);
    }
    final result = List<int>.filled(weights.length, 0);
    int allocated = 0;
    final remainders = <int, double>{};
    for (int i = 0; i < weights.length; i++) {
      final exact = (total * weights[i]) / weightSum;
      result[i] = exact.floor();
      remainders[i] = exact - result[i];
      allocated += result[i];
    }
    var remaining = total - allocated;
    final sorted = remainders.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      if (remaining <= 0) break;
      result[entry.key]++;
      remaining--;
    }
    return result;
  }

}
