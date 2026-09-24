import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_adj_return_form_bloc.dart';

/// Regression tests for two unlinked-return discount bugs surfaced by the
/// dual-return rollout (FIFO/WAC product split was the trigger; the maths
/// bug existed independently in the form state):
///
///   1. Invoice-level percent discount produced a different total than the
///      same percent applied per-item, because the percent base was the
///      *taxed* total instead of net before tax.
///   2. A per-item percent discount entered in the bottom sheet was frozen
///      to absolute cents, so changing the quantity from outside the sheet
///      did not re-apply the percent.
///
/// Numbers below mirror the screenshots that revealed the bug:
/// jacket 30 SAR x10 + skirt 50 SAR x10, all lines @ 1% tax, 1% discount.
void main() {
  // Two lines, each with 1% tax (taxRateBps = 100).
  AdjReturnLineItem jacket({
    int qty = 10,
    int discountCents = 0,
    int discountPercentBps = 0,
  }) => AdjReturnLineItem(
    productId: 1,
    productName: 'Jacket',
    quantity: qty,
    unitPriceCents: 3000, // 30.00
    taxRateBps: 100, // 1%
    discountCents: discountCents,
    discountPercentBps: discountPercentBps,
  );

  AdjReturnLineItem skirt({
    int qty = 10,
    int discountCents = 0,
    int discountPercentBps = 0,
  }) => AdjReturnLineItem(
    productId: 2,
    productName: 'Skirt',
    quantity: qty,
    unitPriceCents: 5000, // 50.00
    taxRateBps: 100, // 1%
    discountCents: discountCents,
    discountPercentBps: discountPercentBps,
  );

  group('Bug #1 — overall % discount equals per-item %', () {
    test('1% per-item discount matches 1% invoice-level discount', () {
      // Per-item: each line carries its own 1% discount via discountPercentBps.
      final perItem = PurchaseAdjReturnFormState(
        items: [
          jacket(discountPercentBps: 100),
          skirt(discountPercentBps: 100),
        ],
        discountPerItem: true,
      );

      // Invoice-level: lines are clean, overall discount = 1% (100 bps)
      // applied via the percent-cents conversion the UI layer performs against
      // the *net before tax* base — see _CheckoutSheet._syncDiscountFromPercent.
      final overallNet = PurchaseAdjReturnFormState(
        items: [jacket(), skirt()],
      ).totalNetBeforeOverallDiscountCents;
      final overallPercentCents = (overallNet * 100 / 10000).round(); // 1%
      final overall = PurchaseAdjReturnFormState(
        items: [jacket(), skirt()],
        discountPerItem: false,
        overallDiscountCents: overallPercentCents,
        overallDiscountIsPercent: false, // UI converts % -> fixed cents
      );

      // Both paths land on the same final total (799.92 SAR = 79992 cents).
      expect(perItem.totalCents, 79992);
      expect(overall.totalCents, perItem.totalCents);
    });

    test('regression — base must NOT include tax', () {
      // If the percent base were `subtotal + tax` (the old, buggy behaviour)
      // the overall discount would be 808 cents, dropping the total to 79984
      // (799.84 SAR). Pin the *correct* base to net before tax = 80000 cents.
      final s = PurchaseAdjReturnFormState(items: [jacket(), skirt()]);
      expect(s.totalNetBeforeOverallDiscountCents, 80000);
      expect(s.totalBeforeOverallDiscount, 80000 + 800); // includes 1% tax
    });
  });

  group('Bug #2 — per-item % survives external quantity changes', () {
    test('changing quantity re-applies the saved percent', () {
      final original = jacket(
        qty: 10,
        discountPercentBps: 100,
      ); // 1% of 300 = 3.00
      expect(original.effectiveDiscountCents, 300);
      expect(original.netCents, 30000 - 300);

      // Quantity stepper outside the sheet bumps qty 10 -> 20.
      final updated = original.copyWith(quantity: 20);

      // Discount must be re-evaluated against the new subtotal (60000),
      // NOT frozen at the previous 300 cents.
      expect(updated.effectiveDiscountCents, 600);
      expect(updated.netCents, 60000 - 600);
    });

    test('absolute discount stays absolute on quantity change', () {
      // Sanity check the inverse: when the user typed cents, the value
      // must not silently scale with quantity.
      final fixed = jacket(qty: 10, discountCents: 250); // 2.50 fixed
      expect(fixed.effectiveDiscountCents, 250);

      final updated = fixed.copyWith(quantity: 20);
      expect(updated.effectiveDiscountCents, 250);
    });

    test('percent never exceeds subtotal (clamp)', () {
      // 200% (20000 bps) is nonsensical but must not produce a negative net.
      final clamped = jacket(qty: 1, discountPercentBps: 20000);
      expect(clamped.effectiveDiscountCents, clamped.subtotalCents);
      expect(clamped.netCents, 0);
    });
  });
}
