import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money Calculations - Integer Cents', () {
    test('basic addition is exact', () {
      const int price1Cents = 1999; // $19.99
      const int price2Cents = 2499; // $24.99
      const int total = price1Cents + price2Cents;
      
      expect(total, equals(4498)); // $44.98 exactly
    });

    test('multiplication is exact', () {
      const int priceInCents = 1999; // $19.99
      const int quantity = 3;
      const int total = priceInCents * quantity;
      
      expect(total, equals(5997)); // $59.97 exactly
    });

    test('percentage discount calculation', () {
      const int subtotalCents = 10000; // $100.00
      const int discountPercent = 15; // 15%
      
      // Integer division rounds down
      final discountCents = (subtotalCents * discountPercent) ~/ 100;
      
      expect(discountCents, equals(1500)); // $15.00
    });

    test('percentage discount with odd amounts', () {
      const int subtotalCents = 9999; // $99.99
      const int discountPercent = 10; // 10%
      
      final discountCents = (subtotalCents * discountPercent) ~/ 100;
      
      expect(discountCents, equals(999)); // $9.99 (rounds down from 999.9)
    });

    test('tax calculation with basis points', () {
      const int amountCents = 10000; // $100.00
      const int taxRateBasisPoints = 1500; // 15% = 1500 basis points
      
      final taxCents = (amountCents * taxRateBasisPoints) ~/ 10000;
      
      expect(taxCents, equals(1500)); // $15.00
    });

    test('tax calculation with odd amounts', () {
      const int amountCents = 9999; // $99.99
      const int taxRateBasisPoints = 1500; // 15%
      
      final taxCents = (amountCents * taxRateBasisPoints) ~/ 10000;
      
      expect(taxCents, equals(1499)); // $14.99 (rounds down from 1499.85)
    });

    test('complete sale calculation', () {
      const int item1Price = 1999; // $19.99
      const int item1Qty = 2;
      const int item2Price = 4999; // $49.99
      const int item2Qty = 1;
      
      final subtotal = (item1Price * item1Qty) + (item2Price * item2Qty);
      expect(subtotal, equals(8997)); // $89.97
      
      const int discountPercent = 10;
      final discount = (subtotal * discountPercent) ~/ 100;
      expect(discount, equals(899)); // $8.99
      
      final afterDiscount = subtotal - discount;
      expect(afterDiscount, equals(8098)); // $80.98
      
      const int taxRateBasisPoints = 1000; // 10%
      final tax = (afterDiscount * taxRateBasisPoints) ~/ 10000;
      expect(tax, equals(809)); // $8.09
      
      final total = afterDiscount + tax;
      expect(total, equals(8907)); // $89.07
    });

    test('split payment calculation', () {
      const int totalCents = 10000; // $100.00
      const int cashPayment = 6000; // $60.00
      final cardPayment = totalCents - cashPayment;
      
      expect(cardPayment, equals(4000)); // $40.00
      expect(cashPayment + cardPayment, equals(totalCents));
    });

    test('change calculation', () {
      const int totalCents = 8750; // $87.50
      const int cashReceived = 10000; // $100.00
      final change = cashReceived - totalCents;
      
      expect(change, equals(1250)); // $12.50
    });

    test('balance calculation', () {
      int balanceCents = 0;
      
      // Sale on credit
      balanceCents += 5000; // $50.00
      expect(balanceCents, equals(5000));
      
      // Another sale
      balanceCents += 3500; // $35.00
      expect(balanceCents, equals(8500));
      
      // Payment received
      balanceCents -= 4000; // $40.00
      expect(balanceCents, equals(4500));
      
      // Return processed
      balanceCents -= 1500; // $15.00
      expect(balanceCents, equals(3000)); // $30.00 remaining
    });

    test('weighted average cost calculation', () {
      // Current inventory: 10 units at $5.00 each
      const int currentQty = 10;
      const int currentCostCents = 500;
      
      // New purchase: 5 units at $6.00 each
      const int newQty = 5;
      const int newCostCents = 600;
      
      // Calculate weighted average
      final totalValue = (currentQty * currentCostCents) + (newQty * newCostCents);
      final totalQty = currentQty + newQty;
      final avgCostCents = totalValue ~/ totalQty;
      
      // (10 * 500 + 5 * 600) / 15 = 8000 / 15 = 533.33 -> 533
      expect(avgCostCents, equals(533));
    });

    test('profit margin calculation', () {
      const int sellingPriceCents = 2000; // $20.00
      const int costPriceCents = 1200; // $12.00
      
      final profitCents = sellingPriceCents - costPriceCents;
      expect(profitCents, equals(800)); // $8.00
      
      // Margin percentage (in basis points for precision)
      final marginBasisPoints = (profitCents * 10000) ~/ sellingPriceCents;
      expect(marginBasisPoints, equals(4000)); // 40%
    });

    test('commission calculation', () {
      const int saleTotalCents = 50000; // $500.00
      const int commissionRateBasisPoints = 500; // 5%
      
      final commissionCents = (saleTotalCents * commissionRateBasisPoints) ~/ 10000;
      
      expect(commissionCents, equals(2500)); // $25.00
    });

    test('currency conversion', () {
      const int amountUsdCents = 10000; // $100.00
      const int exchangeRateBasisPoints = 8500; // 0.85 EUR/USD
      
      final amountEurCents = (amountUsdCents * exchangeRateBasisPoints) ~/ 10000;
      
      expect(amountEurCents, equals(8500)); // €85.00
    });
  });

  group('Money Calculations - Edge Cases', () {
    test('handles very large amounts', () {
      const int largeAmount = 999999999; // $9,999,999.99
      const int quantity = 100;
      
      // Use BigInt for very large calculations
      final total = BigInt.from(largeAmount) * BigInt.from(quantity);
      
      expect(total, equals(BigInt.from(99999999900)));
    });

    test('handles zero amounts', () {
      const int amount = 0;
      const int taxRate = 1500;
      
      final tax = (amount * taxRate) ~/ 10000;
      
      expect(tax, equals(0));
    });

    test('handles single cent', () {
      const int amount = 1; // $0.01
      const int quantity = 100;
      
      final total = amount * quantity;
      
      expect(total, equals(100)); // $1.00
    });

    test('rounding consistency', () {
      // Test that rounding is always consistent (floor)
      const int amount = 333; // $3.33
      const int taxRate = 1000; // 10%
      
      final tax = (amount * taxRate) ~/ 10000;
      
      // 333 * 1000 / 10000 = 33.3 -> 33
      expect(tax, equals(33));
    });

    test('subtraction never goes negative unexpectedly', () {
      const int balance = 1000;
      const int payment = 1500;
      
      final newBalance = balance - payment;
      
      // Negative balance is valid (customer overpaid)
      expect(newBalance, equals(-500));
    });
  });

  group('Double-Entry Verification', () {
    test('debits equal credits in simple entry', () {
      const int debit = 1000;
      const int credit = 1000;
      
      expect(debit, equals(credit));
    });

    test('debits equal credits in multi-line entry', () {
      final debits = [500, 300, 200];
      final credits = [1000];
      
      final totalDebits = debits.fold<int>(0, (sum, d) => sum + d);
      final totalCredits = credits.fold<int>(0, (sum, c) => sum + c);
      
      expect(totalDebits, equals(totalCredits));
    });

    test('trial balance verification', () {
      // Simulate account balances
      final accounts = {
        'Cash': 50000,           // Asset (debit balance)
        'Receivables': 25000,   // Asset (debit balance)
        'Inventory': 30000,     // Asset (debit balance)
        'Payables': -15000,     // Liability (credit balance, stored as negative)
        'Equity': -40000,       // Equity (credit balance, stored as negative)
        'Revenue': -60000,      // Revenue (credit balance, stored as negative)
        'Expenses': 10000,      // Expense (debit balance)
      };
      
      // Sum should be zero (balanced)
      final sum = accounts.values.fold<int>(0, (sum, balance) => sum + balance);
      
      expect(sum, equals(0));
    });
  });
}
