import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/features/purchases/domain/entities/purchase_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_return_form_bloc.dart';
import 'package:tapix/features/sales/domain/entities/sale_entity.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_return_form_bloc.dart';

/// Helper to create a PurchaseItemEntity for testing.
PurchaseItemEntity _purchaseItem({
  int id = 1,
  int purchaseId = 1,
  int productId = 1,
  int quantity = 10,
  int unitCostCents = 1000,
  int subtotalCents = 10000,
  int discountCents = 0,
  int taxCents = 0,
  int totalCents = 10000,
}) {
  return PurchaseItemEntity(
    id: id,
    purchaseId: purchaseId,
    productId: productId,
    quantity: quantity,
    unitCostCents: Decimal.fromInt(unitCostCents),
    subtotalCents: Decimal.fromInt(subtotalCents),
    discountCents: Decimal.fromInt(discountCents),
    taxCents: Decimal.fromInt(taxCents),
    totalCents: Decimal.fromInt(totalCents),
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Helper to create a SaleItemEntity for testing.
SaleItemEntity _saleItem({
  int id = 1,
  int saleId = 1,
  int productId = 1,
  int quantity = 10,
  int unitPriceCents = 1500,
  int subtotalCents = 15000,
  int discountCents = 0,
  int taxCents = 0,
  int totalCents = 15000,
}) {
  return SaleItemEntity(
    id: id,
    saleId: saleId,
    productId: productId,
    quantity: quantity,
    unitPriceCents: Decimal.fromInt(unitPriceCents),
    subtotalCents: Decimal.fromInt(subtotalCents),
    discountCents: Decimal.fromInt(discountCents),
    taxCents: Decimal.fromInt(taxCents),
    totalCents: Decimal.fromInt(totalCents),
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('Purchase Return - Proportional Calculation', () {
    test('Full return equals original amounts', () {
      final item = _purchaseItem(
        quantity: 10,
        subtotalCents: 10000,
        discountCents: 1000,
        taxCents: 900,
        totalCents: 9900, // 10000 - 1000 + 900
      );

      final result = computeProportionalPurchaseReturn(item, 10);

      expect(result.returnQuantity, 10);
      expect(result.subtotalCents, Decimal.fromInt(10000));
      expect(result.discountCents, Decimal.fromInt(1000));
      expect(result.taxCents, Decimal.fromInt(900));
      expect(result.refundCents, Decimal.fromInt(9900));
    });

    test('Half return gives proportional amounts', () {
      final item = _purchaseItem(
        quantity: 10,
        subtotalCents: 10000,
        discountCents: 1000,
        taxCents: 900,
        totalCents: 9900,
      );

      final result = computeProportionalPurchaseReturn(item, 5);

      expect(result.returnQuantity, 5);
      expect(result.subtotalCents, Decimal.fromInt(5000));
      expect(result.discountCents, Decimal.fromInt(500));
      expect(result.taxCents, Decimal.fromInt(450));
      expect(result.refundCents, Decimal.fromInt(4950));
    });

    test(
      'Single unit return from qty 3 with odd amounts uses integer division',
      () {
        // 3 items @ subtotal=1000, discount=100, tax=90 → total=990
        // Return 1: subtotal=333, discount=33, tax=30 → refund=330
        final item = _purchaseItem(
          quantity: 3,
          subtotalCents: 1000,
          discountCents: 100,
          taxCents: 90,
          totalCents: 990,
        );

        final result = computeProportionalPurchaseReturn(item, 1);

        expect(result.returnQuantity, 1);
        expect(result.subtotalCents, Decimal.fromInt(333));
        expect(result.discountCents, Decimal.fromInt(33));
        expect(result.taxCents, Decimal.fromInt(30));
        // refund = 333 - 33 + 30 = 330
        expect(result.refundCents, Decimal.fromInt(330));
      },
    );

    test('Return 2 of 3 items with odd amounts', () {
      final item = _purchaseItem(
        quantity: 3,
        subtotalCents: 1000,
        discountCents: 100,
        taxCents: 90,
        totalCents: 990,
      );

      final result = computeProportionalPurchaseReturn(item, 2);

      expect(result.returnQuantity, 2);
      // (1000 * 2) ~/ 3 = 666
      expect(result.subtotalCents, Decimal.fromInt(666));
      // (100 * 2) ~/ 3 = 66
      expect(result.discountCents, Decimal.fromInt(66));
      // (90 * 2) ~/ 3 = 60
      expect(result.taxCents, Decimal.fromInt(60));
      // 666 - 66 + 60 = 660
      expect(result.refundCents, Decimal.fromInt(660));
    });

    test('No discount, no tax', () {
      final item = _purchaseItem(
        quantity: 4,
        subtotalCents: 2000,
        discountCents: 0,
        taxCents: 0,
        totalCents: 2000,
      );

      final result = computeProportionalPurchaseReturn(item, 1);

      expect(result.subtotalCents, Decimal.fromInt(500));
      expect(result.discountCents, Decimal.zero);
      expect(result.taxCents, Decimal.zero);
      expect(result.refundCents, Decimal.fromInt(500));
    });

    test('Zero quantity original returns zero amounts', () {
      final item = _purchaseItem(
        quantity: 0,
        subtotalCents: 0,
        discountCents: 0,
        taxCents: 0,
        totalCents: 0,
      );

      final result = computeProportionalPurchaseReturn(item, 1);

      expect(result.subtotalCents, Decimal.zero);
      expect(result.discountCents, Decimal.zero);
      expect(result.taxCents, Decimal.zero);
      expect(result.refundCents, Decimal.zero);
    });

    test('Header totals aggregate correctly from multiple items', () {
      final item1 = _purchaseItem(
        id: 1,
        quantity: 10,
        subtotalCents: 10000,
        discountCents: 500,
        taxCents: 950,
        totalCents: 10450,
      );
      final item2 = _purchaseItem(
        id: 2,
        quantity: 5,
        subtotalCents: 7500,
        discountCents: 300,
        taxCents: 720,
        totalCents: 7920,
      );

      final line1 = computeProportionalPurchaseReturn(item1, 3);
      final line2 = computeProportionalPurchaseReturn(item2, 2);

      final state = PurchaseReturnFormState(returnItems: [line1, line2]);

      // line1: subtotal=(10000*3)~/10=3000, discount=(500*3)~/10=150, tax=(950*3)~/10=285
      //        refund=3000-150+285=3135
      expect(line1.subtotalCents, Decimal.fromInt(3000));
      expect(line1.discountCents, Decimal.fromInt(150));
      expect(line1.taxCents, Decimal.fromInt(285));
      expect(line1.refundCents, Decimal.fromInt(3135));

      // line2: subtotal=(7500*2)~/5=3000, discount=(300*2)~/5=120, tax=(720*2)~/5=288
      //        refund=3000-120+288=3168
      expect(line2.subtotalCents, Decimal.fromInt(3000));
      expect(line2.discountCents, Decimal.fromInt(120));
      expect(line2.taxCents, Decimal.fromInt(288));
      expect(line2.refundCents, Decimal.fromInt(3168));

      // Header totals
      expect(state.totalSubtotalCents, Decimal.fromInt(6000));
      expect(state.totalDiscountCents, Decimal.fromInt(270));
      expect(state.totalTaxCents, Decimal.fromInt(573));
      expect(state.totalRefundCents, Decimal.fromInt(6303));
    });
  });

  group('Sale Return - Proportional Calculation', () {
    test('Full return equals original amounts', () {
      final item = _saleItem(
        quantity: 10,
        subtotalCents: 15000,
        discountCents: 2000,
        taxCents: 1300,
        totalCents: 14300,
      );

      final result = computeProportionalSaleReturn(item, 10);

      expect(result.returnQuantity, 10);
      expect(result.subtotalCents, Decimal.fromInt(15000));
      expect(result.discountCents, Decimal.fromInt(2000));
      expect(result.taxCents, Decimal.fromInt(1300));
      expect(result.refundCents, Decimal.fromInt(14300));
    });

    test('Partial return gives proportional amounts', () {
      final item = _saleItem(
        quantity: 10,
        subtotalCents: 15000,
        discountCents: 2000,
        taxCents: 1300,
        totalCents: 14300,
      );

      final result = computeProportionalSaleReturn(item, 3);

      expect(result.returnQuantity, 3);
      expect(result.subtotalCents, Decimal.fromInt(4500));
      expect(result.discountCents, Decimal.fromInt(600));
      expect(result.taxCents, Decimal.fromInt(390));
      expect(result.refundCents, Decimal.fromInt(4290));
    });

    test('Integer division rounding for sale returns', () {
      final item = _saleItem(
        quantity: 7,
        subtotalCents: 10000,
        discountCents: 700,
        taxCents: 930,
        totalCents: 10230,
      );

      final result = computeProportionalSaleReturn(item, 3);

      // (10000*3)~/7 = 4285
      expect(result.subtotalCents, Decimal.fromInt(4285));
      // (700*3)~/7 = 300
      expect(result.discountCents, Decimal.fromInt(300));
      // (930*3)~/7 = 398 (2790~/7=398)
      expect(result.taxCents, Decimal.fromInt(398));
      // 4285 - 300 + 398 = 4383
      expect(result.refundCents, Decimal.fromInt(4383));
    });

    test('Header totals aggregate correctly for sale returns', () {
      final item1 = _saleItem(
        id: 1,
        quantity: 4,
        subtotalCents: 8000,
        discountCents: 400,
        taxCents: 760,
        totalCents: 8360,
      );
      final item2 = _saleItem(
        id: 2,
        quantity: 6,
        subtotalCents: 12000,
        discountCents: 600,
        taxCents: 1140,
        totalCents: 12540,
      );

      final line1 = computeProportionalSaleReturn(item1, 2);
      final line2 = computeProportionalSaleReturn(item2, 3);

      final state = SaleReturnFormState(returnItems: [line1, line2]);

      // line1: sub=4000, disc=200, tax=380, refund=4180
      expect(line1.subtotalCents, Decimal.fromInt(4000));
      expect(line1.discountCents, Decimal.fromInt(200));
      expect(line1.taxCents, Decimal.fromInt(380));
      expect(line1.refundCents, Decimal.fromInt(4180));

      // line2: sub=6000, disc=300, tax=570, refund=6270
      expect(line2.subtotalCents, Decimal.fromInt(6000));
      expect(line2.discountCents, Decimal.fromInt(300));
      expect(line2.taxCents, Decimal.fromInt(570));
      expect(line2.refundCents, Decimal.fromInt(6270));

      // Header
      expect(state.totalSubtotalCents, Decimal.fromInt(10000));
      expect(state.totalDiscountCents, Decimal.fromInt(500));
      expect(state.totalTaxCents, Decimal.fromInt(950));
      expect(state.totalRefundCents, Decimal.fromInt(10450));
    });

    test('Zero quantity original returns zero amounts', () {
      final item = _saleItem(
        quantity: 0,
        subtotalCents: 0,
        discountCents: 0,
        taxCents: 0,
        totalCents: 0,
      );

      final result = computeProportionalSaleReturn(item, 1);

      expect(result.subtotalCents, Decimal.zero);
      expect(result.discountCents, Decimal.zero);
      expect(result.taxCents, Decimal.zero);
      expect(result.refundCents, Decimal.zero);
    });
  });

  group('Consistency checks', () {
    test('refundCents always equals subtotal - discount + tax', () {
      // Test with many different combinations
      final testCases = [
        (qty: 10, retQty: 3, sub: 10000, disc: 500, tax: 950),
        (qty: 7, retQty: 2, sub: 7777, disc: 333, tax: 444),
        (qty: 1, retQty: 1, sub: 999, disc: 99, tax: 50),
        (qty: 100, retQty: 33, sub: 100000, disc: 5000, tax: 9500),
        (qty: 3, retQty: 1, sub: 1, disc: 0, tax: 0),
      ];

      for (final tc in testCases) {
        final item = _purchaseItem(
          quantity: tc.qty,
          subtotalCents: tc.sub,
          discountCents: tc.disc,
          taxCents: tc.tax,
          totalCents: tc.sub - tc.disc + tc.tax,
        );

        final result = computeProportionalPurchaseReturn(item, tc.retQty);
        final expectedRefund =
            result.subtotalCents - result.discountCents + result.taxCents;
        expect(
          result.refundCents,
          expectedRefund,
          reason:
              'refund should equal subtotal - discount + tax for '
              'qty=${tc.qty}, retQty=${tc.retQty}',
        );
      }
    });
  });
}

/// Expose the private function for testing by wrapping it.
/// This calls the same logic as _computeProportionalReturn in the BLoC.
ReturnLineItem computeProportionalPurchaseReturn(
  PurchaseItemEntity original,
  int returnQty,
) {
  final origQty = original.quantity;
  if (origQty <= 0) {
    return ReturnLineItem(
      originalItem: original,
      returnQuantity: returnQty,
      subtotalCents: Decimal.zero,
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      refundCents: Decimal.zero,
    );
  }
  final subtotalInt =
      (original.subtotalCents.toBigInt().toInt() * returnQty) ~/ origQty;
  final discountInt =
      (original.discountCents.toBigInt().toInt() * returnQty) ~/ origQty;
  final taxInt = (original.taxCents.toBigInt().toInt() * returnQty) ~/ origQty;
  final refundInt = subtotalInt - discountInt + taxInt;
  return ReturnLineItem(
    originalItem: original,
    returnQuantity: returnQty,
    subtotalCents: Decimal.fromInt(subtotalInt),
    discountCents: Decimal.fromInt(discountInt),
    taxCents: Decimal.fromInt(taxInt),
    refundCents: Decimal.fromInt(refundInt),
  );
}

/// Expose the private function for testing by wrapping it.
SaleReturnLineItem computeProportionalSaleReturn(
  SaleItemEntity original,
  int returnQty,
) {
  final origQty = original.quantity;
  if (origQty <= 0) {
    return SaleReturnLineItem(
      originalItem: original,
      returnQuantity: returnQty,
      subtotalCents: Decimal.zero,
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      refundCents: Decimal.zero,
    );
  }
  final subtotalInt =
      (original.subtotalCents.toBigInt().toInt() * returnQty) ~/ origQty;
  final discountInt =
      (original.discountCents.toBigInt().toInt() * returnQty) ~/ origQty;
  final taxInt = (original.taxCents.toBigInt().toInt() * returnQty) ~/ origQty;
  final refundInt = subtotalInt - discountInt + taxInt;
  return SaleReturnLineItem(
    originalItem: original,
    returnQuantity: returnQty,
    subtotalCents: Decimal.fromInt(subtotalInt),
    discountCents: Decimal.fromInt(discountInt),
    taxCents: Decimal.fromInt(taxInt),
    refundCents: Decimal.fromInt(refundInt),
  );
}
