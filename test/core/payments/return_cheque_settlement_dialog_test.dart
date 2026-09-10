import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/payments/checkout_settlement.dart';
import 'package:tapix/core/payments/return_cheque_settlement_dialog.dart';

void main() {
  group('return cheque settlement validation', () {
    final dueDate = DateTime(2026, 9, 30);

    test('accepts a cheque with an immediate partial remainder', () {
      final allocations = [
        CheckoutPaymentAllocation(
          method: 'cheque',
          amountCents: 6000,
          reference: 'CHK-1',
          dueDate: dueDate,
        ),
        const CheckoutPaymentAllocation(method: 'cash', amountCents: 2000),
      ];

      expect(
        isReturnChequeSettlementValid(allocations, totalCents: 10000),
        isTrue,
      );
      expect(returnChequePrimaryDueDate(allocations), dueDate);
    });

    test('accepts an unallocated credit remainder', () {
      final allocations = [
        CheckoutPaymentAllocation(
          method: 'cheque',
          amountCents: 6000,
          reference: 'CHK-2',
          dueDate: dueDate,
        ),
      ];

      expect(
        isReturnChequeSettlementValid(allocations, totalCents: 10000),
        isTrue,
      );
    });

    test('rejects stale allocations after the return total decreases', () {
      final allocations = [
        CheckoutPaymentAllocation(
          method: 'cheque',
          amountCents: 6000,
          reference: 'CHK-3',
          dueDate: dueDate,
        ),
      ];

      expect(
        isReturnChequeSettlementValid(allocations, totalCents: 5000),
        isFalse,
      );
    });

    test('rejects a settlement without a cheque', () {
      const allocations = [
        CheckoutPaymentAllocation(method: 'cash', amountCents: 5000),
      ];

      expect(
        isReturnChequeSettlementValid(allocations, totalCents: 5000),
        isFalse,
      );
    });
  });
}
