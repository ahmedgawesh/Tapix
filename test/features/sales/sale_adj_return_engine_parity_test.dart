// ════════════════════════════════════════════════════════════════════════════
// sale_adj_return_engine_parity_test.dart
//
// Sale-side mirror of `purchases/adj_return_discount_parity_test.dart`.
// Locks the bug-fix invariants on `SaleAdjReturnFormState` so the engine
// migration can never silently regress.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/features/purchases/presentation/bloc/purchase_adj_return_form_bloc.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_adj_return_form_bloc.dart';

void main() {
  AdjReturnLineItem line({
    int qty = 1,
    int price = 80000,
    int discountCents = 0,
    int discountPercentBps = 0,
    int taxRateBps = 0,
  }) {
    return AdjReturnLineItem(
      productId: 1,
      productName: 'Widget',
      quantity: qty,
      unitPriceCents: price,
      discountCents: discountCents,
      discountPercentBps: discountPercentBps,
      taxRateBps: taxRateBps,
    );
  }

  group('Sale adj-return — engine parity', () {
    test('1 % per-item == 1 % overall on the same line (closes bug #1)', () {
      final perItem = SaleAdjReturnFormState(
        items: [line(price: 80000, taxRateBps: 100, discountPercentBps: 100)],
      );
      final overall = SaleAdjReturnFormState(
        items: [line(price: 80000, taxRateBps: 100)],
        overallDiscountCents: 100,
        overallDiscountIsPercent: true,
      );

      expect(perItem.totalCents, 79992);
      expect(
        overall.totalCents,
        perItem.totalCents,
        reason: 'overall % must equal per-item % when same rate',
      );
    });

    test('overall % base must NOT include tax', () {
      final s = SaleAdjReturnFormState(
        items: [line(price: 80000, taxRateBps: 100)],
        overallDiscountCents: 100, // 1 %
        overallDiscountIsPercent: true,
      );
      // Bug regression: 8.08 (= 1 % of 800+8) is the *wrong* answer.
      expect(s.effectiveOverallDiscountCents, isNot(808));
      expect(s.effectiveOverallDiscountCents, 800);
    });

    test('changing quantity re-applies the saved percent (closes bug #2)', () {
      final qty1 = SaleAdjReturnFormState(
        items: [line(qty: 1, price: 50000, discountPercentBps: 100)],
      );
      final qty2 = SaleAdjReturnFormState(
        items: [line(qty: 2, price: 50000, discountPercentBps: 100)],
      );
      expect(qty1.totalItemDiscountCents, 500); // 1 % of 500.00
      expect(qty2.totalItemDiscountCents, 1000); // 1 % of 1000.00
    });

    test('absolute discount stays absolute on quantity change', () {
      final qty1 = SaleAdjReturnFormState(
        items: [line(qty: 1, price: 50000, discountCents: 500)],
      );
      final qty5 = SaleAdjReturnFormState(
        items: [line(qty: 5, price: 50000, discountCents: 500)],
      );
      expect(qty1.totalItemDiscountCents, 500);
      expect(qty5.totalItemDiscountCents, 500);
    });

    test('engine.lines length and totals match state aggregates', () {
      final s = SaleAdjReturnFormState(
        items: [
          line(qty: 2, price: 30000, taxRateBps: 1500), // 600.00 + 15 %
          line(qty: 1, price: 12000, discountPercentBps: 1000), // 10 %
        ],
        overallDiscountCents: 250, // 2.5 %
        overallDiscountIsPercent: true,
      );
      expect(s.pricing.lines.length, 2);
      expect(s.pricing.subtotal.cents, s.totalSubtotalCents);
      expect(s.pricing.tax.cents, s.totalAdjustedTaxCents);
      expect(s.pricing.total.cents, s.totalCents);
      // Σ line.total == invoice.total (no escaped cents)
      final sumLineTotals = s.pricing.lines
          .map((l) => l.total.cents)
          .fold<int>(0, (a, b) => a + b);
      expect(sumLineTotals, s.pricing.total.cents);
    });
  });
}
