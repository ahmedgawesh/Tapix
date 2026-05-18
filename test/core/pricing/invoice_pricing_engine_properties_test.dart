// ════════════════════════════════════════════════════════════════════════════
// PHASE 0 — PROPERTY-BASED TESTS · InvoicePricingEngine + Money.allocate
// ════════════════════════════════════════════════════════════════════════════
//
// Purpose
// -------
// Lock the two structural invariants that make the migration safe:
//
//   (I1)  Money.allocate sum invariant:
//         for every (total, weights), Σ allocate(weights) == total exactly.
//
//   (I2)  InvoicePricingEngine "no escaped cents":
//         for every invoice, Σ line.total == invoice.total.
//
// These invariants are the mathematical guarantees that make largest-
// remainder distribution safe — if ever broken, the engine is silently
// losing/creating cents (which is the exact failure mode Phase-0 must
// prevent through the whole migration).
//
// Pseudo-random: a deterministic seeded generator (via `Random(seed)`)
// keeps every run reproducible while still covering a wide input space.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/money/money.dart';
import 'package:tapix/core/pricing/discount.dart';
import 'package:tapix/core/pricing/invoice_pricing_engine.dart';
import 'package:tapix/core/pricing/line_item_pricing_engine.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────
  // I1 — Money.allocate: Σ allocate == total, exactly.
  // ──────────────────────────────────────────────────────────────────────
  group('Property I1 — Money.allocate sum invariant', () {
    test('1000 random (total, weights) cases: Σ == total exactly', () {
      final rng = Random(20260512); // seeded for reproducibility
      const cases = 1000;

      for (var i = 0; i < cases; i++) {
        // total in [-100_000_000, 100_000_000] cents; covers negatives
        // because downstream services sometimes allocate negatives (e.g.
        // refund proration). Allocation must be sign-agnostic.
        final total = rng.nextInt(200000000) - 100000000;
        final len = 1 + rng.nextInt(12); // 1..12 lines
        final weights = List<int>.generate(len, (_) => rng.nextInt(10000));
        // keep it realistic: ensure at least one non-zero weight most of
        // the time, but also exercise the all-zero degenerate path.
        if (weights.every((w) => w == 0) && rng.nextBool()) {
          weights[0] = 1 + rng.nextInt(1000);
        }

        final alloc = Money.fromCents(total).allocate(weights);
        expect(alloc.length, weights.length);
        final sum = alloc.fold<int>(0, (a, b) => a + b.cents);
        expect(sum, total,
            reason: 'seed-case #$i: total=$total weights=$weights → $alloc');
      }
    });

    test('all-zero weights → all cents go to slot 0 deterministically', () {
      final rng = Random(42);
      for (var i = 0; i < 50; i++) {
        final total = rng.nextInt(10000) + 1;
        final len = 2 + rng.nextInt(8);
        final weights = List<int>.filled(len, 0);
        final alloc = Money.fromCents(total).allocate(weights);
        expect(alloc[0].cents, total);
        for (var j = 1; j < len; j++) {
          expect(alloc[j].cents, 0);
        }
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // I2 — InvoicePricingEngine no-escaped-cents invariant.
  // ──────────────────────────────────────────────────────────────────────
  group('Property I2 — InvoicePricingEngine: Σ line.total == invoice.total',
      () {
    test('500 random invoices with overall % discount & mixed tax', () {
      final rng = Random(20260513);
      const cases = 500;

      for (var i = 0; i < cases; i++) {
        final lineCount = 1 + rng.nextInt(8);
        final lines = List<LineItemPricingInput>.generate(lineCount, (_) {
          final isTaxable = rng.nextBool();
          final taxRate = isTaxable ? (rng.nextInt(20) + 1) * 100 : 0;
          final unit = 50 + rng.nextInt(50000); // 0.50 .. 500.00
          final qty = 1 + rng.nextInt(10);
          // per-line discount: 40% chance of having one
          final Discount disc;
          final roll = rng.nextInt(10);
          if (roll < 4) {
            if (rng.nextBool()) {
              // fixed, <= subtotal
              final subtotal = unit * qty;
              final d = subtotal == 0 ? 0 : rng.nextInt(subtotal);
              disc = Discount.fixed(Money.fromCents(d));
            } else {
              // percent 1..50%
              final bps = (rng.nextInt(50) + 1) * 100;
              disc = Discount.percent(bps);
            }
          } else {
            disc = Discount.none;
          }
          return LineItemPricingInput(
            unitPrice: Money.fromCents(unit),
            quantity: qty,
            discount: disc,
            isTaxable: isTaxable,
            productTaxRateBps: taxRate,
          );
        });

        // 50% chance of an overall discount
        final Discount overall;
        if (rng.nextBool()) {
          if (rng.nextBool()) {
            overall = Discount.percent((rng.nextInt(30) + 1) * 100);
          } else {
            // Fixed overall: cap at Σ line.net to avoid over-discount
            // guard errors which are out of scope for this invariant.
            final netGuess = lines.fold<int>(
                0, (sum, l) => sum + (l.unitPrice.cents * l.quantity));
            final cap = netGuess > 0 ? rng.nextInt(netGuess + 1) : 0;
            overall = Discount.fixed(Money.fromCents(cap));
          }
        } else {
          overall = Discount.none;
        }

        final result = InvoicePricingEngine.compute(InvoicePricingInput(
          lines: lines,
          overallDiscount: overall,
          enableTaxCalculations: true,
          defaultTaxRateBps: 0,
          taxInclusivePricing: false,
        ));

        // Invariant I2a: Σ line.total == invoice.total
        final sumLineTotals = result.lines
            .fold<int>(0, (s, l) => s + l.total.cents);
        expect(sumLineTotals, result.total.cents,
            reason: 'seed-case #$i: lines=$lines overall=$overall');

        // Invariant I2b: Σ line.shareOfOverallDiscount == overallDiscount
        final sumShares = result.lines
            .fold<int>(0, (s, l) => s + l.shareOfOverallDiscount.cents);
        expect(sumShares, result.overallDiscount.cents,
            reason: 'overall discount allocation must sum exactly');

        // Invariant I2c: subtotal − itemDiscount − overallDiscount + tax == total
        final reconstructed = result.subtotal.cents -
            result.itemDiscountTotal.cents -
            result.overallDiscount.cents +
            result.tax.cents;
        final expected = reconstructed < 0 ? 0 : reconstructed;
        expect(result.total.cents, expected,
            reason: 'invoice total reconstruction invariant');
      }
    });

    test(
        'percent near-parity: |overall.total − perItem.total| is bounded by '
        'rounding error ≤ lineCount', () {
      // The "1% overall ≡ 1% per-item" hero invariant holds EXACTLY only on
      // friendly numbers (equal-weight, clean ratios — see the 2-line jacket/
      // skirt case in adj_return_discount_parity_test.dart). On arbitrary
      // weights, per-line and overall paths each round independently and may
      // drift by up to 1 cent per line (largest-remainder allocation + per-
      // line tax rounding). This is mathematically expected; the bug the
      // engine closes is "base includes tax" (ΔΔ cents), NOT "identical
      // result on every input".
      final rng = Random(101);
      for (var i = 0; i < 200; i++) {
        final lineCount = 1 + rng.nextInt(5);
        final lines = List<LineItemPricingInput>.generate(lineCount, (_) {
          final unit = 100 + rng.nextInt(50000);
          final qty = 1 + rng.nextInt(8);
          return LineItemPricingInput(
            unitPrice: Money.fromCents(unit),
            quantity: qty,
            discount: Discount.none,
            isTaxable: true,
            productTaxRateBps: 100, // uniform 1% tax
          );
        });

        final perItemLines = lines
            .map((l) => LineItemPricingInput(
                  unitPrice: l.unitPrice,
                  quantity: l.quantity,
                  discount: Discount.percent(100), // 1% per item
                  isTaxable: l.isTaxable,
                  productTaxRateBps: l.productTaxRateBps,
                ))
            .toList();

        final perItem = InvoicePricingEngine.compute(InvoicePricingInput(
          lines: perItemLines,
          overallDiscount: Discount.none,
          enableTaxCalculations: true,
          defaultTaxRateBps: 0,
          taxInclusivePricing: false,
        ));
        final overall = InvoicePricingEngine.compute(InvoicePricingInput(
          lines: lines,
          overallDiscount: Discount.percent(100), // 1% overall
          enableTaxCalculations: true,
          defaultTaxRateBps: 0,
          taxInclusivePricing: false,
        ));

        final delta = (overall.total.cents - perItem.total.cents).abs();
        expect(delta, lessThanOrEqualTo(lineCount),
            reason: 'case #$i: drift exceeded per-line rounding budget. '
                'lines=$lineCount perItem=${perItem.total.cents} '
                'overall=${overall.total.cents}');
      }
    });

    test('percent exact parity on friendly equal-weight 2-line case', () {
      // The hero documented case: jacket 30×10 + skirt 50×10, all at 1% tax.
      // With these clean ratios, the 1-cent drift vanishes. This pins the
      // "799.92" guarantee called out in docs/PRICING_ENGINE.md.
      final jacket = LineItemPricingInput(
        unitPrice: Money.fromCents(3000),
        quantity: 10,
        discount: Discount.none,
        isTaxable: true,
        productTaxRateBps: 100,
      );
      final skirt = LineItemPricingInput(
        unitPrice: Money.fromCents(5000),
        quantity: 10,
        discount: Discount.none,
        isTaxable: true,
        productTaxRateBps: 100,
      );

      final perItem = InvoicePricingEngine.compute(InvoicePricingInput(
        lines: [
          LineItemPricingInput(
              unitPrice: jacket.unitPrice,
              quantity: jacket.quantity,
              discount: Discount.percent(100),
              isTaxable: true,
              productTaxRateBps: 100),
          LineItemPricingInput(
              unitPrice: skirt.unitPrice,
              quantity: skirt.quantity,
              discount: Discount.percent(100),
              isTaxable: true,
              productTaxRateBps: 100),
        ],
        overallDiscount: Discount.none,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      ));
      final overall = InvoicePricingEngine.compute(InvoicePricingInput(
        lines: [jacket, skirt],
        overallDiscount: Discount.percent(100),
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      ));

      expect(perItem.total.cents, 79992);
      expect(overall.total.cents, 79992);
    });
  });
}
