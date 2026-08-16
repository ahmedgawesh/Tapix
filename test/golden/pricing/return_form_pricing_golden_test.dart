// ════════════════════════════════════════════════════════════════════════════
// PHASE 0 — RETURN FORMS PRICING · GOLDEN CHARACTERISATION TESTS
// ════════════════════════════════════════════════════════════════════════════
//
// Purpose
// -------
// Pin the CURRENT outputs of:
//   1. ReturnCalculationService.computeProportionalReturn (per-line math)
//   2. SaleReturnFormState + PurchaseReturnFormState rollup folds
// across 6 canonical return scenarios.
//
// Phase-5 of the migration (see docs/adr/0001-pricing-engines-as-sot.md) will
// collapse the four parallel folds in each return bloc into one rollup helper
// over ReturnCalculationService. These tests must stay green through that
// refactor.
//
// Rounding note: the first partial allocation uses integer division. Later
// linked returns pass their financial history, so the final return receives
// every residual cent and the cumulative total reconstructs the invoice.
//
// Coverage:
//   R1  full return of single-line invoice
//   R2  partial return (3 of 5 units), no discount, no tax
//   R3  partial return of discounted line (proportional discount)
//   R4  partial return of taxable line (proportional tax)
//   R5  partial return of discounted + taxable line (all three components)
//   R6  originalQuantity == 0 guard → zero result
//   R7  multi-line return rollup aggregation
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/return_calculation_service.dart';
import 'package:tapix/features/purchases/domain/entities/purchase_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_return_form_bloc.dart';
import 'package:tapix/features/sales/domain/entities/sale_entity.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_return_form_bloc.dart';

// ─── Helpers to build per-line return items from service output ─────────────

SaleReturnLineItem _saleReturnLine({
  required int saleItemId,
  required int productId,
  required int origQty,
  required int returnQty,
  required int origSubtotalCents,
  required int origDiscountCents,
  required int origTaxCents,
}) {
  final r = ReturnCalculationService.computeProportionalReturn(
    originalQuantity: origQty,
    returnQuantity: returnQty,
    originalSubtotalCents: origSubtotalCents,
    originalDiscountCents: origDiscountCents,
    originalTaxCents: origTaxCents,
  );
  final now = DateTime(2026, 1, 15);
  final origTotal = origSubtotalCents - origDiscountCents + origTaxCents;
  return SaleReturnLineItem(
    originalItem: SaleItemEntity(
      id: saleItemId,
      saleId: 1,
      productId: productId,
      productName: 'P$productId',
      quantity: origQty,
      unitPriceCents: Decimal.fromInt(origSubtotalCents ~/ origQty),
      subtotalCents: Decimal.fromInt(origSubtotalCents),
      discountCents: Decimal.fromInt(origDiscountCents),
      taxCents: Decimal.fromInt(origTaxCents),
      totalCents: Decimal.fromInt(origTotal),
      createdAt: now,
    ),
    returnQuantity: returnQty,
    subtotalCents: Decimal.fromInt(r.subtotalCents),
    discountCents: Decimal.fromInt(r.discountCents),
    taxCents: Decimal.fromInt(r.taxCents),
    refundCents: Decimal.fromInt(r.refundCents),
  );
}

ReturnLineItem _purchaseReturnLine({
  required int purchaseItemId,
  required int productId,
  required int origQty,
  required int returnQty,
  required int origSubtotalCents,
  required int origDiscountCents,
  required int origTaxCents,
}) {
  final r = ReturnCalculationService.computeProportionalReturn(
    originalQuantity: origQty,
    returnQuantity: returnQty,
    originalSubtotalCents: origSubtotalCents,
    originalDiscountCents: origDiscountCents,
    originalTaxCents: origTaxCents,
  );
  final origTotal = origSubtotalCents - origDiscountCents + origTaxCents;
  return ReturnLineItem(
    originalItem: PurchaseItemEntity(
      id: purchaseItemId,
      purchaseId: 1,
      productId: productId,
      quantity: origQty,
      unitCostCents: Decimal.fromInt(origSubtotalCents ~/ origQty),
      discountCents: Decimal.fromInt(origDiscountCents),
      subtotalCents: Decimal.fromInt(origSubtotalCents),
      taxCents: Decimal.fromInt(origTaxCents),
      totalCents: Decimal.fromInt(origTotal),
      createdAt: DateTime(2026, 1, 15),
    ),
    returnQuantity: returnQty,
    subtotalCents: Decimal.fromInt(r.subtotalCents),
    discountCents: Decimal.fromInt(r.discountCents),
    taxCents: Decimal.fromInt(r.taxCents),
    refundCents: Decimal.fromInt(r.refundCents),
  );
}

// ─── Scenarios ──────────────────────────────────────────────────────────────

void main() {
  group('ReturnCalculationService — Phase 0 golden per-line math', () {
    // ── R1 ─────────────────────────────────────────────────────────────
    test('R1 full return: returnQty == origQty → all original values', () {
      final r = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 3,
        returnQuantity: 3,
        originalSubtotalCents: 15000,
        originalDiscountCents: 1500,
        originalTaxCents: 1350,
      );
      expect(r.subtotalCents, 15000);
      expect(r.discountCents, 1500);
      expect(r.taxCents, 1350);
      expect(r.refundCents, 15000 - 1500 + 1350); // 14850
    });

    // ── R2 ─────────────────────────────────────────────────────────────
    test('R2 partial return 3 of 5, no discount, no tax', () {
      // 3/5 of 50000 = 30000 exact.
      final r = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 5,
        returnQuantity: 3,
        originalSubtotalCents: 50000,
        originalDiscountCents: 0,
        originalTaxCents: 0,
      );
      expect(r.subtotalCents, 30000);
      expect(r.discountCents, 0);
      expect(r.taxCents, 0);
      expect(r.refundCents, 30000);
    });

    // ── R3 ─────────────────────────────────────────────────────────────
    test('R3 partial return of discounted line (proportional discount)', () {
      // orig qty=4, subtotal=8000, discount=1000, no tax. Return qty=1.
      // subtotal = (8000 * 1) ~/ 4 = 2000
      // discount = (1000 * 1) ~/ 4 =  250
      // refund   = 2000 - 250 = 1750
      final r = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 4,
        returnQuantity: 1,
        originalSubtotalCents: 8000,
        originalDiscountCents: 1000,
        originalTaxCents: 0,
      );
      expect(r.subtotalCents, 2000);
      expect(r.discountCents, 250);
      expect(r.taxCents, 0);
      expect(r.refundCents, 1750);
    });

    // ── R4 ─────────────────────────────────────────────────────────────
    test('R4 partial return of taxable line (proportional tax)', () {
      // orig qty=10, subtotal=10000, no discount, tax=1500 (15%). Return 3.
      // subtotal = (10000 * 3) ~/ 10 = 3000
      // tax      = (1500 * 3) ~/ 10  =  450
      // refund   = 3000 + 450 = 3450
      final r = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 10,
        returnQuantity: 3,
        originalSubtotalCents: 10000,
        originalDiscountCents: 0,
        originalTaxCents: 1500,
      );
      expect(r.subtotalCents, 3000);
      expect(r.discountCents, 0);
      expect(r.taxCents, 450);
      expect(r.refundCents, 3450);
    });

    // ── R5 ─────────────────────────────────────────────────────────────
    test('R5 partial return with truncation (1-cent rounding error)', () {
      // orig qty=3, subtotal=100, discount=10, tax=5. Return qty=1.
      // subtotal = (100*1) ~/ 3 = 33  (not 33.33...)
      // discount = (10*1)  ~/ 3 =  3
      // tax      = (5*1)   ~/ 3 =  1
      // refund   = 33 - 3 + 1   = 31
      // This isolated first allocation truncates. Sequential linked returns
      // pass previousLinkedHistory, allowing the later rows to recover the
      // residual cents.
      final r = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 3,
        returnQuantity: 1,
        originalSubtotalCents: 100,
        originalDiscountCents: 10,
        originalTaxCents: 5,
      );
      expect(r.subtotalCents, 33);
      expect(r.discountCents, 3);
      expect(r.taxCents, 1);
      expect(r.refundCents, 31);
    });

    // ── R6 ─────────────────────────────────────────────────────────────
    test('R6 originalQuantity == 0 → all-zero guard', () {
      final r = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 0,
        returnQuantity: 0,
        originalSubtotalCents: 999,
        originalDiscountCents: 50,
        originalTaxCents: 25,
      );
      expect(r.subtotalCents, 0);
      expect(r.discountCents, 0);
      expect(r.taxCents, 0);
      expect(r.refundCents, 0);
    });
  });

  group('SaleReturnFormState — Phase 0 rollup aggregation', () {
    test('R7 multi-line rollup: Σ per-line == state totals', () {
      final line1 = _saleReturnLine(
        saleItemId: 101,
        productId: 1,
        origQty: 5,
        returnQty: 2,
        origSubtotalCents: 10000, // 2000 per unit
        origDiscountCents: 500,
        origTaxCents: 950, // 10% of 9500
      );
      final line2 = _saleReturnLine(
        saleItemId: 102,
        productId: 2,
        origQty: 3,
        returnQty: 3,
        origSubtotalCents: 3000,
        origDiscountCents: 0,
        origTaxCents: 450,
      );
      // Expected per-line (by hand):
      //  line1: subtotal=(10000*2)/5=4000, discount=(500*2)/5=200,
      //         tax=(950*2)/5=380, refund=4000-200+380=4180
      //  line2: subtotal=3000, discount=0, tax=450, refund=3450 (full)
      // Σ:     subtotal=7000, discount=200, tax=830, refund=7630
      final state = SaleReturnFormState(
        saleId: 1,
        currencyId: 1,
        returnItems: [line1, line2],
      );
      expect(state.totalSubtotalCents, Decimal.fromInt(7000));
      expect(state.totalDiscountCents, Decimal.fromInt(200));
      expect(state.totalTaxCents, Decimal.fromInt(830));
      expect(state.totalRefundCents, Decimal.fromInt(7630));
      expect(state.totalReturnQuantity, 5);

      // Invariant: every line's refund == subtotal - discount + tax.
      for (final l in state.returnItems) {
        final reconstructed = l.subtotalCents - l.discountCents + l.taxCents;
        expect(
          l.refundCents,
          reconstructed,
          reason: 'refund invariant for line ${l.originalItem.id}',
        );
      }
    });
  });

  group('PurchaseReturnFormState — Phase 0 rollup aggregation', () {
    test(
      'R7 multi-line rollup (purchase side): Σ per-line == state totals',
      () {
        final line1 = _purchaseReturnLine(
          purchaseItemId: 201,
          productId: 10,
          origQty: 4,
          returnQty: 1,
          origSubtotalCents: 8000,
          origDiscountCents: 1000,
          origTaxCents: 700,
        );
        final line2 = _purchaseReturnLine(
          purchaseItemId: 202,
          productId: 11,
          origQty: 2,
          returnQty: 2,
          origSubtotalCents: 4000,
          origDiscountCents: 0,
          origTaxCents: 400,
        );
        // line1: subtotal=2000, discount=250, tax=175, refund=1925
        // line2: subtotal=4000, discount=0,   tax=400, refund=4400
        // Σ:     subtotal=6000, discount=250, tax=575, refund=6325
        final state = PurchaseReturnFormState(
          purchaseId: 1,
          currencyId: 1,
          returnItems: [line1, line2],
        );
        expect(state.totalSubtotalCents, Decimal.fromInt(6000));
        expect(state.totalDiscountCents, Decimal.fromInt(250));
        expect(state.totalTaxCents, Decimal.fromInt(575));
        expect(state.totalRefundCents, Decimal.fromInt(6325));
        expect(state.totalReturnQuantity, 3);
      },
    );
  });
}
