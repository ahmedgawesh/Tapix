import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/return_calculation_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // computeProportionalReturn
  // ═══════════════════════════════════════════════════════════════════════════

  group('computeProportionalReturn', () {
    test('full return equals original amounts', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 10,
        returnQuantity: 10,
        originalSubtotalCents: 10000,
        originalDiscountCents: 1000,
        originalTaxCents: 1350,
      );
      expect(result.subtotalCents, 10000);
      expect(result.discountCents, 1000);
      expect(result.taxCents, 1350);
      // refund = subtotal - discount + tax = 10000 - 1000 + 1350 = 10350
      expect(result.refundCents, 10350);
    });

    test('half return gives half amounts (even division)', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 10,
        returnQuantity: 5,
        originalSubtotalCents: 10000,
        originalDiscountCents: 1000,
        originalTaxCents: 1350,
      );
      expect(result.subtotalCents, 5000);
      expect(result.discountCents, 500);
      expect(result.taxCents, 675);
      expect(result.refundCents, 5000 - 500 + 675);
    });

    test('single unit return from multi-unit uses truncating integer division', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 3,
        returnQuantity: 1,
        originalSubtotalCents: 100,
        originalDiscountCents: 10,
        originalTaxCents: 15,
      );
      // 100 * 1 ~/ 3 = 33
      expect(result.subtotalCents, 33);
      // 10 * 1 ~/ 3 = 3
      expect(result.discountCents, 3);
      // 15 * 1 ~/ 3 = 5
      expect(result.taxCents, 5);
      // refund = 33 - 3 + 5 = 35
      expect(result.refundCents, 35);
    });

    test('return qty of 0 yields all zeroes', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 5,
        returnQuantity: 0,
        originalSubtotalCents: 10000,
        originalDiscountCents: 500,
        originalTaxCents: 1500,
      );
      expect(result.subtotalCents, 0);
      expect(result.discountCents, 0);
      expect(result.taxCents, 0);
      expect(result.refundCents, 0);
    });

    test('original qty <= 0 yields all zeroes', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 0,
        returnQuantity: 5,
        originalSubtotalCents: 10000,
        originalDiscountCents: 500,
        originalTaxCents: 1500,
      );
      expect(result.subtotalCents, 0);
      expect(result.discountCents, 0);
      expect(result.taxCents, 0);
      expect(result.refundCents, 0);
    });

    test('negative original qty yields all zeroes', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: -1,
        returnQuantity: 1,
        originalSubtotalCents: 10000,
        originalDiscountCents: 500,
        originalTaxCents: 1500,
      );
      expect(result.subtotalCents, 0);
      expect(result.discountCents, 0);
      expect(result.taxCents, 0);
      expect(result.refundCents, 0);
    });

    test('no discount, no tax', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 4,
        returnQuantity: 2,
        originalSubtotalCents: 2000,
        originalDiscountCents: 0,
        originalTaxCents: 0,
      );
      expect(result.subtotalCents, 1000);
      expect(result.discountCents, 0);
      expect(result.taxCents, 0);
      expect(result.refundCents, 1000);
    });

    test('large values do not overflow with standard int (< 2^53)', () {
      // 99999999 cents = $999,999.99
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 100,
        returnQuantity: 37,
        originalSubtotalCents: 99999999,
        originalDiscountCents: 5000000,
        originalTaxCents: 14250000,
      );
      // 99999999 * 37 ~/ 100 = 36999999
      expect(result.subtotalCents, 36999999);
      // 5000000 * 37 ~/ 100 = 1850000
      expect(result.discountCents, 1850000);
      // 14250000 * 37 ~/ 100 = 5272500
      expect(result.taxCents, 5272500);
      // refund = 36999999 - 1850000 + 5272500 = 40422499
      expect(result.refundCents, 40422499);
    });

    test('refund formula: subtotal - discount + tax', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 1,
        returnQuantity: 1,
        originalSubtotalCents: 500,
        originalDiscountCents: 100,
        originalTaxCents: 60,
      );
      expect(result.refundCents, 500 - 100 + 60);
    });
  });
}
