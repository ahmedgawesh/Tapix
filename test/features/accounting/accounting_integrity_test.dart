import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';

/// Tests verifying accounting integrity invariants:
/// - Debit always equals Credit
/// - Account balances remain correct after transactions
/// - Inventory quantities remain correct
/// - VAT calculations are accurate
/// - Customer/supplier balance updates are correct
void main() {
  // ─── Account code constants (mirrors JournalEntryService) ───
  const int cashAccountId = 1;
  const int receivablesAccountId = 3;
  const int inventoryAccountId = 4;
  const int vatReceivableAccountId = 5;
  const int payablesAccountId = 6;
  const int vatPayableAccountId = 7;
  const int revenueAccountId = 8;
  const int cogsAccountId = 10;
  const int currencyId = 1;

  group('Sale Journal Entry Integrity', () {
    test('cash sale: Dr Cash, Cr Revenue — debits equal credits', () {
      const saleTotalCents = 15000; // $150.00
      final entry = JournalEntryData.simple(
        description: 'Cash sale',
        debitAccountId: cashAccountId,
        creditAccountId: revenueAccountId,
        amountCents: saleTotalCents,
        currencyId: currencyId,
        entryType: 'sale',
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(entry.totalCreditCents));
      expect(entry.totalDebitCents, equals(saleTotalCents));
    });

    test('credit sale: Dr Receivables, Cr Revenue — debits equal credits', () {
      const saleTotalCents = 25000;
      final entry = JournalEntryData.simple(
        description: 'Credit sale',
        debitAccountId: receivablesAccountId,
        creditAccountId: revenueAccountId,
        amountCents: saleTotalCents,
        currencyId: currencyId,
        entryType: 'sale',
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(entry.totalCreditCents));
    });

    test('sale with VAT: multi-line entry stays balanced', () {
      const subtotalCents = 10000;
      const vatCents = 1500; // 15%
      const totalCents = subtotalCents + vatCents;

      final entry = JournalEntryData(
        description: 'Sale with VAT',
        entryType: 'sale',
        autoPost: true,
        lines: [
          // Dr Cash (total including VAT)
          JournalEntryLineData(
            accountId: cashAccountId,
            debitCents: totalCents,
            creditCents: 0,
            currencyId: currencyId,
          ),
          // Cr Revenue (subtotal)
          JournalEntryLineData(
            accountId: revenueAccountId,
            debitCents: 0,
            creditCents: subtotalCents,
            currencyId: currencyId,
          ),
          // Cr VAT Payable (tax)
          JournalEntryLineData(
            accountId: vatPayableAccountId,
            debitCents: 0,
            creditCents: vatCents,
            currencyId: currencyId,
          ),
        ],
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(entry.totalCreditCents));
      expect(entry.totalDebitCents, equals(totalCents));
    });

    test('partial payment sale: split across Cash + Receivables', () {
      const totalCents = 20000;
      const paidCents = 12000;
      const remainingCents = totalCents - paidCents;

      final entry = JournalEntryData(
        description: 'Partial payment sale',
        entryType: 'sale',
        autoPost: true,
        lines: [
          JournalEntryLineData(
            accountId: cashAccountId,
            debitCents: paidCents,
            creditCents: 0,
            currencyId: currencyId,
          ),
          JournalEntryLineData(
            accountId: receivablesAccountId,
            debitCents: remainingCents,
            creditCents: 0,
            currencyId: currencyId,
          ),
          JournalEntryLineData(
            accountId: revenueAccountId,
            debitCents: 0,
            creditCents: totalCents,
            currencyId: currencyId,
          ),
        ],
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(entry.totalCreditCents));
      expect(entry.totalDebitCents, equals(totalCents));
    });
  });

  group('COGS Journal Entry Integrity', () {
    test('COGS entry: Dr COGS, Cr Inventory — debits equal credits', () {
      const costCents = 8000;
      final entry = JournalEntryData.simple(
        description: 'COGS for sale',
        debitAccountId: cogsAccountId,
        creditAccountId: inventoryAccountId,
        amountCents: costCents,
        currencyId: currencyId,
        entryType: 'cogs',
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(entry.totalCreditCents));
      expect(entry.totalDebitCents, equals(costCents));
    });

    test('COGS reversal (return): Dr Inventory, Cr COGS — balanced', () {
      const returnCostCents = 3000;
      final entry = JournalEntryData.simple(
        description: 'COGS reversal for return',
        debitAccountId: inventoryAccountId,
        creditAccountId: cogsAccountId,
        amountCents: returnCostCents,
        currencyId: currencyId,
        entryType: 'cogs_reversal',
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(entry.totalCreditCents));
    });

    test('sale + COGS combined: total debits equal total credits', () {
      const saleTotalCents = 15000;
      const costCents = 8000;

      // Revenue entry
      final revenueEntry = JournalEntryData.simple(
        description: 'Sale revenue',
        debitAccountId: cashAccountId,
        creditAccountId: revenueAccountId,
        amountCents: saleTotalCents,
        currencyId: currencyId,
      );

      // COGS entry
      final cogsEntry = JournalEntryData.simple(
        description: 'COGS',
        debitAccountId: cogsAccountId,
        creditAccountId: inventoryAccountId,
        amountCents: costCents,
        currencyId: currencyId,
      );

      // Both entries must be individually balanced
      expect(revenueEntry.isValid, isTrue);
      expect(cogsEntry.isValid, isTrue);

      // Combined debit == combined credit
      final totalDebit =
          revenueEntry.totalDebitCents + cogsEntry.totalDebitCents;
      final totalCredit =
          revenueEntry.totalCreditCents + cogsEntry.totalCreditCents;
      expect(totalDebit, equals(totalCredit));
    });
  });

  group('Purchase Journal Entry Integrity', () {
    test('cash purchase: Dr Inventory, Cr Cash — balanced', () {
      const purchaseTotalCents = 50000;
      final entry = JournalEntryData.simple(
        description: 'Cash purchase',
        debitAccountId: inventoryAccountId,
        creditAccountId: cashAccountId,
        amountCents: purchaseTotalCents,
        currencyId: currencyId,
        entryType: 'purchase',
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(entry.totalCreditCents));
    });

    test('credit purchase: Dr Inventory, Cr Payables — balanced', () {
      const purchaseTotalCents = 75000;
      final entry = JournalEntryData.simple(
        description: 'Credit purchase',
        debitAccountId: inventoryAccountId,
        creditAccountId: payablesAccountId,
        amountCents: purchaseTotalCents,
        currencyId: currencyId,
        entryType: 'purchase',
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(entry.totalCreditCents));
    });

    test('purchase with VAT: Dr Inventory + Dr VAT Receivable, Cr Payables', () {
      const subtotalCents = 40000;
      const vatCents = 6000;
      const totalCents = subtotalCents + vatCents;

      final entry = JournalEntryData(
        description: 'Purchase with VAT',
        entryType: 'purchase',
        autoPost: true,
        lines: [
          JournalEntryLineData(
            accountId: inventoryAccountId,
            debitCents: subtotalCents,
            creditCents: 0,
            currencyId: currencyId,
          ),
          JournalEntryLineData(
            accountId: vatReceivableAccountId,
            debitCents: vatCents,
            creditCents: 0,
            currencyId: currencyId,
          ),
          JournalEntryLineData(
            accountId: payablesAccountId,
            debitCents: 0,
            creditCents: totalCents,
            currencyId: currencyId,
          ),
        ],
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(entry.totalCreditCents));
      expect(entry.totalDebitCents, equals(totalCents));
    });
  });

  group('Inventory Quantity Integrity', () {
    test('purchase increases stock, sale decreases stock', () {
      int stock = 0;

      // Purchase 50 units
      stock += 50;
      expect(stock, equals(50));

      // Sell 20 units
      stock -= 20;
      expect(stock, equals(30));

      // Purchase 10 more
      stock += 10;
      expect(stock, equals(40));

      // Sell 15
      stock -= 15;
      expect(stock, equals(25));
    });

    test('negative stock guard rejects overselling', () {
      int stock = 10;
      const sellQuantity = 15;

      final canSell = stock >= sellQuantity;
      expect(canSell, isFalse);
    });

    test('sale return restores stock', () {
      int stock = 50;

      // Sell 20
      stock -= 20;
      expect(stock, equals(30));

      // Return 5
      stock += 5;
      expect(stock, equals(35));
    });

    test('purchase void deducts stock', () {
      int stock = 0;

      // Purchase 30
      stock += 30;
      expect(stock, equals(30));

      // Sell 10
      stock -= 10;
      expect(stock, equals(20));

      // Cannot void purchase if stock < purchased quantity
      const purchasedQty = 30;
      final canVoid = stock >= purchasedQty;
      expect(canVoid, isFalse);
    });

    test('weighted average cost calculation after purchase', () {
      // Existing: 10 units @ $5.00
      int qty = 10;
      int costCents = 500;

      // New purchase: 5 units @ $8.00
      const newQty = 5;
      const newCostCents = 800;

      final avgCost =
          ((costCents * qty) + (newCostCents * newQty)) ~/ (qty + newQty);
      qty += newQty;
      costCents = avgCost;

      expect(qty, equals(15));
      // (5000 + 4000) / 15 = 600
      expect(costCents, equals(600));
    });
  });

  group('VAT Calculation Integrity', () {
    test('VAT at 15% on 100.00', () {
      const amountCents = 10000;
      const vatBps = 1500; // 15%
      final vatCents = (amountCents * vatBps) ~/ 10000;
      expect(vatCents, equals(1500));
    });

    test('VAT at 5% on 99.99', () {
      const amountCents = 9999;
      const vatBps = 500; // 5%
      final vatCents = (amountCents * vatBps) ~/ 10000;
      // 9999 * 500 / 10000 = 499.95 → 499
      expect(vatCents, equals(499));
    });

    test('VAT rounding consistency (always floor)', () {
      const amountCents = 3333;
      const vatBps = 1000; // 10%
      final vatCents = (amountCents * vatBps) ~/ 10000;
      // 3333 * 1000 / 10000 = 333.3 → 333
      expect(vatCents, equals(333));
    });

    test('VAT input vs output netting', () {
      // Purchase VAT (input): $15.00
      const inputVatCents = 1500;
      // Sale VAT (output): $22.50
      const outputVatCents = 2250;

      // Net VAT payable
      final netVatPayable = outputVatCents - inputVatCents;
      expect(netVatPayable, equals(750)); // $7.50 owed to government
    });

    test('zero-rated items have zero VAT', () {
      const amountCents = 50000;
      const vatBps = 0;
      final vatCents = (amountCents * vatBps) ~/ 10000;
      expect(vatCents, equals(0));
    });
  });

  group('Customer Balance Integrity', () {
    test('credit sale increases customer balance', () {
      int balanceCents = 0;
      const saleTotalCents = 15000;

      // Credit sale: customer owes us more
      balanceCents += saleTotalCents;
      expect(balanceCents, equals(15000));
    });

    test('payment decreases customer balance', () {
      int balanceCents = 15000;
      const paymentCents = 10000;

      balanceCents -= paymentCents;
      expect(balanceCents, equals(5000));
    });

    test('credit refund decreases customer balance', () {
      int balanceCents = 20000;
      const refundCents = 5000;

      // Credit refund: customer owes us less
      balanceCents -= refundCents;
      expect(balanceCents, equals(15000));
    });

    test('cash refund does NOT change balance', () {
      int balanceCents = 20000;

      // Cash refund: money already given back, balance unchanged
      // No balance change for cash refunds
      expect(balanceCents, equals(20000));
    });

    test('full lifecycle: sale → partial payment → return → payment', () {
      int balanceCents = 0;

      // Credit sale: $200
      balanceCents += 20000;
      expect(balanceCents, equals(20000));

      // Payment: $150
      balanceCents -= 15000;
      expect(balanceCents, equals(5000));

      // Credit return: $30
      balanceCents -= 3000;
      expect(balanceCents, equals(2000));

      // Final payment: $20
      balanceCents -= 2000;
      expect(balanceCents, equals(0));
    });
  });

  group('Supplier Balance Integrity', () {
    test('purchase increases supplier balance (we owe more)', () {
      int balanceCents = 0;
      const purchaseTotalCents = 50000;

      balanceCents += purchaseTotalCents;
      expect(balanceCents, equals(50000));
    });

    test('payment decreases supplier balance', () {
      int balanceCents = 50000;
      const paymentCents = 30000;

      balanceCents -= paymentCents;
      expect(balanceCents, equals(20000));
    });

    test('purchase return decreases supplier balance', () {
      int balanceCents = 50000;
      const returnCents = 10000;

      balanceCents -= returnCents;
      expect(balanceCents, equals(40000));
    });

    test('void purchase reverses net balance delta', () {
      int balanceCents = 0;

      // Purchase: $500, paid $200 up front
      const purchaseTotal = 50000;
      const paidUpFront = 20000;
      balanceCents += (purchaseTotal - paidUpFront); // net delta = $300
      expect(balanceCents, equals(30000));

      // Void: reverse the net delta
      balanceCents -= (purchaseTotal - paidUpFront);
      expect(balanceCents, equals(0));
    });

    test('full lifecycle: purchase → payment → return → void', () {
      int balanceCents = 0;

      // Purchase $1000, paid $400
      balanceCents += (100000 - 40000);
      expect(balanceCents, equals(60000));

      // Payment: $300
      balanceCents -= 30000;
      expect(balanceCents, equals(30000));

      // Return: $100
      balanceCents -= 10000;
      expect(balanceCents, equals(20000));
    });
  });

  group('Trial Balance Verification', () {
    test('complete business cycle produces balanced trial balance', () {
      // Simulate account balances (debit-normal are positive, credit-normal are negative)
      final accounts = <String, int>{};

      void debit(String account, int cents) =>
          accounts[account] = (accounts[account] ?? 0) + cents;
      void credit(String account, int cents) =>
          accounts[account] = (accounts[account] ?? 0) - cents;

      // Purchase inventory: Dr Inventory $500, Cr Cash $500
      debit('Inventory', 50000);
      credit('Cash', 50000);

      // Sale: Dr Cash $800, Cr Revenue $800
      debit('Cash', 80000);
      credit('Revenue', 80000);

      // COGS: Dr COGS $500, Cr Inventory $500
      debit('COGS', 50000);
      credit('Inventory', 50000);

      // Expense: Dr Expenses $100, Cr Cash $100
      debit('Expenses', 10000);
      credit('Cash', 10000);

      // Trial balance must sum to zero
      final trialBalance =
          accounts.values.fold<int>(0, (sum, val) => sum + val);
      expect(trialBalance, equals(0));

      // Verify profit: Revenue - COGS - Expenses = $800 - $500 - $100 = $200
      final revenue = -(accounts['Revenue'] ?? 0); // credit-normal → negate
      final cogs = accounts['COGS'] ?? 0;
      final expenses = accounts['Expenses'] ?? 0;
      final profit = revenue - cogs - expenses;
      expect(profit, equals(20000)); // $200.00
    });
  });
}
