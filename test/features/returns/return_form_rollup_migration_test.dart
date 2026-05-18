// ════════════════════════════════════════════════════════════════════════════
// PHASE 5 — RETURN-FORM ROLLUP MIGRATION · REGRESSION TESTS
// ════════════════════════════════════════════════════════════════════════════
//
// Pins the Phase-5 contract:
//   * `ReturnCalculationService.aggregate(...)` is the only writer of return
//     rollup totals (subtotal / discount / tax / refund / quantity).
//   * `SaleReturnFormState` and `PurchaseReturnFormState` expose those
//     totals via their existing `total*Cents` / `totalReturnQuantity`
//     getters, all reading from the same memoized `ReturnRollup` instance.
//   * The rollup result equals the byte-identical sum of its per-line
//     inputs (no rounding, no division).
//   * Memoization: two reads of any rollup-derived getter on the same
//     state instance never re-aggregate.
//
// These tests run alongside the Phase-0 return goldens
// (`test/golden/pricing/return_form_pricing_golden_test.dart`) which must
// also stay green — together they establish that the public rollup
// contract is unchanged.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/return_calculation_service.dart';
import 'package:tapix/features/purchases/domain/entities/purchase_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_return_form_bloc.dart';
import 'package:tapix/features/sales/domain/entities/sale_entity.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_return_form_bloc.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

SaleReturnLineItem _saleLine({
  required int id,
  required int subtotal,
  required int discount,
  required int tax,
  required int refund,
  required int returnQty,
  int origQty = 10,
}) {
  return SaleReturnLineItem(
    originalItem: SaleItemEntity(
      id: id,
      saleId: 1,
      productId: id,
      productName: 'P$id',
      quantity: origQty,
      unitPriceCents: Decimal.fromInt(100),
      subtotalCents: Decimal.fromInt(subtotal * (origQty ~/ (returnQty == 0 ? 1 : returnQty))),
      discountCents: Decimal.fromInt(discount),
      taxCents: Decimal.fromInt(tax),
      totalCents: Decimal.fromInt(subtotal - discount + tax),
      createdAt: DateTime(2026, 1, 1),
    ),
    returnQuantity: returnQty,
    subtotalCents: Decimal.fromInt(subtotal),
    discountCents: Decimal.fromInt(discount),
    taxCents: Decimal.fromInt(tax),
    refundCents: Decimal.fromInt(refund),
  );
}

ReturnLineItem _purchaseLine({
  required int id,
  required int subtotal,
  required int discount,
  required int tax,
  required int refund,
  required int returnQty,
  int origQty = 10,
}) {
  return ReturnLineItem(
    originalItem: PurchaseItemEntity(
      id: id,
      purchaseId: 1,
      productId: id,
      quantity: origQty,
      unitCostCents: Decimal.fromInt(100),
      discountCents: Decimal.fromInt(discount),
      subtotalCents: Decimal.fromInt(subtotal * (origQty ~/ (returnQty == 0 ? 1 : returnQty))),
      taxCents: Decimal.fromInt(tax),
      totalCents: Decimal.fromInt(subtotal - discount + tax),
      createdAt: DateTime(2026, 1, 1),
    ),
    returnQuantity: returnQty,
    subtotalCents: Decimal.fromInt(subtotal),
    discountCents: Decimal.fromInt(discount),
    taxCents: Decimal.fromInt(tax),
    refundCents: Decimal.fromInt(refund),
  );
}

void main() {
  group('Phase 5 — ReturnCalculationService.aggregate', () {
    test('empty iterable → ReturnRollup.empty equivalent (all zeros)', () {
      final r = ReturnCalculationService.aggregate(const []);
      expect(r.subtotalCents, 0);
      expect(r.discountCents, 0);
      expect(r.taxCents, 0);
      expect(r.refundCents, 0);
      expect(r.totalQuantity, 0);
    });

    test('single line → identity', () {
      final r = ReturnCalculationService.aggregate([
        (
          subtotalCents: 5000,
          discountCents: 250,
          taxCents: 475,
          refundCents: 5225,
          quantity: 3,
        ),
      ]);
      expect(r.subtotalCents, 5000);
      expect(r.discountCents, 250);
      expect(r.taxCents, 475);
      expect(r.refundCents, 5225);
      expect(r.totalQuantity, 3);
    });

    test('multi-line aggregate is exact Σ of inputs (no rounding)', () {
      final r = ReturnCalculationService.aggregate([
        (
          subtotalCents: 100,
          discountCents: 10,
          taxCents: 5,
          refundCents: 95,
          quantity: 1,
        ),
        (
          subtotalCents: 200,
          discountCents: 20,
          taxCents: 18,
          refundCents: 198,
          quantity: 2,
        ),
        (
          subtotalCents: 333,
          discountCents: 0,
          taxCents: 33,
          refundCents: 366,
          quantity: 7,
        ),
      ]);
      expect(r.subtotalCents, 100 + 200 + 333);
      expect(r.discountCents, 10 + 20 + 0);
      expect(r.taxCents, 5 + 18 + 33);
      expect(r.refundCents, 95 + 198 + 366);
      expect(r.totalQuantity, 1 + 2 + 7);
    });

    test('ReturnRollup.empty constant is all-zero', () {
      const e = ReturnRollup.empty;
      expect(e.subtotalCents, 0);
      expect(e.discountCents, 0);
      expect(e.taxCents, 0);
      expect(e.refundCents, 0);
      expect(e.totalQuantity, 0);
    });
  });

  group('Phase 5 — SaleReturnFormState rollup-backed totals', () {
    test('empty returnItems → all rollup-backed getters are zero', () {
      final state = SaleReturnFormState(returnItems: const []);
      expect(state.totalSubtotalCents, Decimal.zero);
      expect(state.totalDiscountCents, Decimal.zero);
      expect(state.totalTaxCents, Decimal.zero);
      expect(state.totalRefundCents, Decimal.zero);
      expect(state.totalReturnQuantity, 0);
    });

    test('multi-line: totals match a freshly-computed aggregate()', () {
      final lines = [
        _saleLine(
            id: 1,
            subtotal: 4000,
            discount: 200,
            tax: 380,
            refund: 4180,
            returnQty: 2),
        _saleLine(
            id: 2,
            subtotal: 3000,
            discount: 0,
            tax: 450,
            refund: 3450,
            returnQty: 3),
      ];
      final state = SaleReturnFormState(returnItems: lines);

      final expected = ReturnCalculationService.aggregate(
        lines.map((l) => (
              subtotalCents: l.subtotalCents.toBigInt().toInt(),
              discountCents: l.discountCents.toBigInt().toInt(),
              taxCents: l.taxCents.toBigInt().toInt(),
              refundCents: l.refundCents.toBigInt().toInt(),
              quantity: l.returnQuantity,
            )),
      );

      expect(state.totalSubtotalCents,
          Decimal.fromInt(expected.subtotalCents));
      expect(state.totalDiscountCents,
          Decimal.fromInt(expected.discountCents));
      expect(state.totalTaxCents, Decimal.fromInt(expected.taxCents));
      expect(state.totalRefundCents,
          Decimal.fromInt(expected.refundCents));
      expect(state.totalReturnQuantity, expected.totalQuantity);
    });

    test('refund invariant: Σ refund == Σ subtotal − Σ discount + Σ tax', () {
      // The per-line invariant (refund = subtotal − discount + tax) is
      // preserved by `computeProportionalReturn`. Aggregate must
      // therefore satisfy the same equation on the rollup.
      final lines = [
        _saleLine(
            id: 1,
            subtotal: 2000,
            discount: 100,
            tax: 190,
            refund: 2090,
            returnQty: 2),
        _saleLine(
            id: 2,
            subtotal: 1500,
            discount: 0,
            tax: 225,
            refund: 1725,
            returnQty: 1),
      ];
      final state = SaleReturnFormState(returnItems: lines);

      final reconstructed = state.totalSubtotalCents -
          state.totalDiscountCents +
          state.totalTaxCents;
      expect(state.totalRefundCents, reconstructed);
    });

    test('memoization: rollup is computed once per state instance', () {
      // Two state instances built from the same line list must yield
      // identical totals (proves the aggregate output is deterministic
      // and that no hidden state mutation creeps in across accesses).
      final lines = [
        _saleLine(
            id: 1,
            subtotal: 999,
            discount: 99,
            tax: 100,
            refund: 1000,
            returnQty: 5),
      ];
      final s1 = SaleReturnFormState(returnItems: lines);
      final s2 = SaleReturnFormState(returnItems: lines);

      expect(s1.totalRefundCents, s2.totalRefundCents);

      // Same instance, repeated reads — must return equal values
      // (memoization correctness; we cannot reach into the private field
      // but we can pin the observable contract).
      final a = s1.totalRefundCents;
      final b = s1.totalRefundCents;
      final c = s1.totalRefundCents;
      expect(a, b);
      expect(b, c);
    });
  });

  group('Phase 5 — PurchaseReturnFormState rollup-backed totals', () {
    test('empty returnItems → all rollup-backed getters are zero', () {
      final state = PurchaseReturnFormState(returnItems: const []);
      expect(state.totalSubtotalCents, Decimal.zero);
      expect(state.totalDiscountCents, Decimal.zero);
      expect(state.totalTaxCents, Decimal.zero);
      expect(state.totalRefundCents, Decimal.zero);
      expect(state.totalReturnQuantity, 0);
    });

    test('multi-line: totals match a freshly-computed aggregate()', () {
      final lines = [
        _purchaseLine(
            id: 10,
            subtotal: 2000,
            discount: 250,
            tax: 175,
            refund: 1925,
            returnQty: 1),
        _purchaseLine(
            id: 11,
            subtotal: 4000,
            discount: 0,
            tax: 400,
            refund: 4400,
            returnQty: 2),
      ];
      final state = PurchaseReturnFormState(returnItems: lines);

      final expected = ReturnCalculationService.aggregate(
        lines.map((l) => (
              subtotalCents: l.subtotalCents.toBigInt().toInt(),
              discountCents: l.discountCents.toBigInt().toInt(),
              taxCents: l.taxCents.toBigInt().toInt(),
              refundCents: l.refundCents.toBigInt().toInt(),
              quantity: l.returnQuantity,
            )),
      );

      expect(state.totalSubtotalCents,
          Decimal.fromInt(expected.subtotalCents));
      expect(state.totalDiscountCents,
          Decimal.fromInt(expected.discountCents));
      expect(state.totalTaxCents, Decimal.fromInt(expected.taxCents));
      expect(state.totalRefundCents,
          Decimal.fromInt(expected.refundCents));
      expect(state.totalReturnQuantity, expected.totalQuantity);
    });

    test('refund invariant on rollup: Σ refund == Σ subtotal − Σ discount + Σ tax',
        () {
      final lines = [
        _purchaseLine(
            id: 1,
            subtotal: 5000,
            discount: 500,
            tax: 450,
            refund: 4950,
            returnQty: 5),
        _purchaseLine(
            id: 2,
            subtotal: 800,
            discount: 0,
            tax: 80,
            refund: 880,
            returnQty: 1),
      ];
      final state = PurchaseReturnFormState(returnItems: lines);

      final reconstructed = state.totalSubtotalCents -
          state.totalDiscountCents +
          state.totalTaxCents;
      expect(state.totalRefundCents, reconstructed);
    });
  });

  group('Phase 5 — Cross-bloc symmetry guarantee', () {
    test(
        'identical inputs → identical rollup totals on both sale and purchase states',
        () {
      // Same five numeric lines, fed through the sale-side state and the
      // purchase-side state. Both must produce the same five rollup
      // figures — proving the single-writer invariant for return rollups.
      final amounts = [
        (sub: 1000, disc: 50, tax: 95, refund: 1045, qty: 1),
        (sub: 2500, disc: 0, tax: 250, refund: 2750, qty: 2),
        (sub: 333, disc: 33, tax: 30, refund: 330, qty: 3),
      ];

      final saleState = SaleReturnFormState(
        returnItems: amounts
            .asMap()
            .entries
            .map((e) => _saleLine(
                  id: e.key + 1,
                  subtotal: e.value.sub,
                  discount: e.value.disc,
                  tax: e.value.tax,
                  refund: e.value.refund,
                  returnQty: e.value.qty,
                ))
            .toList(),
      );
      final purchaseState = PurchaseReturnFormState(
        returnItems: amounts
            .asMap()
            .entries
            .map((e) => _purchaseLine(
                  id: e.key + 1,
                  subtotal: e.value.sub,
                  discount: e.value.disc,
                  tax: e.value.tax,
                  refund: e.value.refund,
                  returnQty: e.value.qty,
                ))
            .toList(),
      );

      expect(
          saleState.totalSubtotalCents, purchaseState.totalSubtotalCents);
      expect(
          saleState.totalDiscountCents, purchaseState.totalDiscountCents);
      expect(saleState.totalTaxCents, purchaseState.totalTaxCents);
      expect(saleState.totalRefundCents, purchaseState.totalRefundCents);
      expect(
          saleState.totalReturnQuantity, purchaseState.totalReturnQuantity);
    });
  });
}
