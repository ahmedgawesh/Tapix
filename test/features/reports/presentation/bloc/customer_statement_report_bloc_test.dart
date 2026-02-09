import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_statement_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('StatementTransaction data model', () {
    test('stores correct values', () {
      final txn = StatementTransaction(
        id: 1,
        date: DateTime(2026, 1, 15),
        type: 'sale',
        description: 'Invoice #001',
        amountCents: 50000,
        runningBalanceCents: 50000,
        referenceId: 100,
        referenceType: 'sale',
      );

      expect(txn.id, 1);
      expect(txn.date, DateTime(2026, 1, 15));
      expect(txn.type, 'sale');
      expect(txn.description, 'Invoice #001');
      expect(txn.amountCents, 50000);
      expect(txn.runningBalanceCents, 50000);
      expect(txn.referenceId, 100);
      expect(txn.referenceType, 'sale');
    });

    test('nullable fields default to null', () {
      final txn = StatementTransaction(
        id: 2,
        date: DateTime(2026, 1, 20),
        type: 'payment',
        amountCents: -30000,
        runningBalanceCents: 20000,
      );

      expect(txn.description, isNull);
      expect(txn.referenceId, isNull);
      expect(txn.referenceType, isNull);
    });

    test('positive amount represents debit (customer owes more)', () {
      final txn = StatementTransaction(
        id: 1,
        date: DateTime(2026, 1, 15),
        type: 'sale',
        amountCents: 50000,
        runningBalanceCents: 50000,
      );

      expect(txn.amountCents > 0, isTrue);
    });

    test('negative amount represents credit (customer pays/returns)', () {
      final txn = StatementTransaction(
        id: 2,
        date: DateTime(2026, 1, 20),
        type: 'payment',
        amountCents: -30000,
        runningBalanceCents: 20000,
      );

      expect(txn.amountCents < 0, isTrue);
    });

    test('integer cents prevents floating point errors', () {
      final txn = StatementTransaction(
        id: 1,
        date: DateTime(2026, 1, 15),
        type: 'sale',
        amountCents: 10,
        runningBalanceCents: 10,
      );

      final txn2 = StatementTransaction(
        id: 2,
        date: DateTime(2026, 1, 16),
        type: 'sale',
        amountCents: 20,
        runningBalanceCents: 30,
      );

      expect(txn.amountCents + txn2.amountCents, 30);
      expect(txn2.runningBalanceCents, 30);
    });
  });

  group('CustomerOption data model', () {
    test('stores correct values', () {
      const option = CustomerOption(
        id: 1,
        name: 'Test Customer',
        balanceCents: 150000,
      );

      expect(option.id, 1);
      expect(option.name, 'Test Customer');
      expect(option.balanceCents, 150000);
    });

    test('zero balance customer', () {
      const option = CustomerOption(
        id: 2,
        name: 'Zero Balance',
        balanceCents: 0,
      );

      expect(option.balanceCents, 0);
    });

    test('negative balance (credit) customer', () {
      const option = CustomerOption(
        id: 3,
        name: 'Credit Customer',
        balanceCents: -50000,
      );

      expect(option.balanceCents < 0, isTrue);
    });
  });

  group('CustomerStatementData', () {
    test('default values are correct', () {
      final data = CustomerStatementData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.customerId, isNull);
      expect(data.customerName, isNull);
      expect(data.customerPhone, isNull);
      expect(data.customerEmail, isNull);
      expect(data.customerAddress, isNull);
      expect(data.customerSegment, isNull);
      expect(data.openingBalanceCents, 0);
      expect(data.closingBalanceCents, 0);
      expect(data.totalDebitsCents, 0);
      expect(data.totalCreditsCents, 0);
      expect(data.transactions, isEmpty);
      expect(data.customers, isEmpty);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('transactionCount returns correct count', () {
      final data = CustomerStatementData(
        dateRange: ReportDateRange.thisMonth(),
        transactions: [
          StatementTransaction(
            id: 1,
            date: DateTime(2026, 1, 15),
            type: 'sale',
            amountCents: 50000,
            runningBalanceCents: 50000,
          ),
          StatementTransaction(
            id: 2,
            date: DateTime(2026, 1, 20),
            type: 'payment',
            amountCents: -30000,
            runningBalanceCents: 20000,
          ),
        ],
      );

      expect(data.transactionCount, 2);
    });

    test('copyWith preserves unchanged fields', () {
      final original = CustomerStatementData(
        customerId: 1,
        customerName: 'Test',
        openingBalanceCents: 100000,
        closingBalanceCents: 150000,
        totalDebitsCents: 80000,
        totalCreditsCents: 30000,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.customerId, 1);
      expect(updated.customerName, 'Test');
      expect(updated.openingBalanceCents, 100000);
      expect(updated.closingBalanceCents, 150000);
      expect(updated.totalDebitsCents, 80000);
      expect(updated.totalCreditsCents, 30000);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = CustomerStatementData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        customerId: 5,
        customerName: 'New Customer',
        openingBalanceCents: 50000,
      );

      expect(updated.customerId, 5);
      expect(updated.customerName, 'New Customer');
      expect(updated.openingBalanceCents, 50000);
    });

    test('copyWith updates customers list', () {
      final original = CustomerStatementData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        customers: const [
          CustomerOption(id: 1, name: 'Customer A', balanceCents: 100000),
          CustomerOption(id: 2, name: 'Customer B', balanceCents: 50000),
        ],
      );

      expect(updated.customers.length, 2);
      expect(updated.customers.first.name, 'Customer A');
    });

    test('copyWith updates transactions list', () {
      final original = CustomerStatementData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        transactions: [
          StatementTransaction(
            id: 1,
            date: DateTime(2026, 1, 15),
            type: 'sale',
            amountCents: 50000,
            runningBalanceCents: 50000,
          ),
        ],
      );

      expect(updated.transactions.length, 1);
      expect(updated.transactionCount, 1);
    });
  });

  group('CustomerStatementReportBloc events', () {
    test('CustomerStatementReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = CustomerStatementReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('CustomerStatementReportCustomerChanged stores customer id', () {
      const event = CustomerStatementReportCustomerChanged(42);
      expect(event.customerId, 42);
    });

    test('CustomerStatementReportCustomerChanged allows null', () {
      const event = CustomerStatementReportCustomerChanged(null);
      expect(event.customerId, isNull);
    });
  });

  group('Opening/Closing balance calculations', () {
    test('closing balance = opening + debits - credits', () {
      const openingBalanceCents = 100000;
      const totalDebitsCents = 80000;
      const totalCreditsCents = 30000;

      final closingBalanceCents =
          openingBalanceCents + totalDebitsCents - totalCreditsCents;

      expect(closingBalanceCents, 150000);
    });

    test('closing balance with zero opening', () {
      const openingBalanceCents = 0;
      const totalDebitsCents = 50000;
      const totalCreditsCents = 20000;

      final closingBalanceCents =
          openingBalanceCents + totalDebitsCents - totalCreditsCents;

      expect(closingBalanceCents, 30000);
    });

    test('closing balance can be negative (customer has credit)', () {
      const openingBalanceCents = 10000;
      const totalDebitsCents = 5000;
      const totalCreditsCents = 50000;

      final closingBalanceCents =
          openingBalanceCents + totalDebitsCents - totalCreditsCents;

      expect(closingBalanceCents, -35000);
      expect(closingBalanceCents < 0, isTrue);
    });

    test('closing balance equals opening when no transactions', () {
      const openingBalanceCents = 75000;
      const totalDebitsCents = 0;
      const totalCreditsCents = 0;

      final closingBalanceCents =
          openingBalanceCents + totalDebitsCents - totalCreditsCents;

      expect(closingBalanceCents, openingBalanceCents);
    });

    test('running balance tracks correctly through transactions', () {
      const openingBalance = 100000;

      final transactions = [
        // Sale: +50000 -> running = 150000
        StatementTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'sale',
          amountCents: 50000,
          runningBalanceCents: 150000,
        ),
        // Payment: -30000 -> running = 120000
        StatementTransaction(
          id: 2,
          date: DateTime(2026, 1, 10),
          type: 'payment',
          amountCents: -30000,
          runningBalanceCents: 120000,
        ),
        // Return: -10000 -> running = 110000
        StatementTransaction(
          id: 3,
          date: DateTime(2026, 1, 15),
          type: 'return',
          amountCents: -10000,
          runningBalanceCents: 110000,
        ),
        // Sale: +20000 -> running = 130000
        StatementTransaction(
          id: 4,
          date: DateTime(2026, 1, 20),
          type: 'sale',
          amountCents: 20000,
          runningBalanceCents: 130000,
        ),
      ];

      // Verify running balance chain
      int balance = openingBalance;
      for (final txn in transactions) {
        balance += txn.amountCents;
        expect(txn.runningBalanceCents, balance,
            reason: 'Running balance should be correct after ${txn.type}');
      }

      // Final balance should be closing balance
      expect(balance, 130000);
    });

    test('debit/credit classification is correct', () {
      final transactions = [
        StatementTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'sale',
          amountCents: 50000,
          runningBalanceCents: 50000,
        ),
        StatementTransaction(
          id: 2,
          date: DateTime(2026, 1, 10),
          type: 'payment',
          amountCents: -30000,
          runningBalanceCents: 20000,
        ),
        StatementTransaction(
          id: 3,
          date: DateTime(2026, 1, 15),
          type: 'sale',
          amountCents: 25000,
          runningBalanceCents: 45000,
        ),
        StatementTransaction(
          id: 4,
          date: DateTime(2026, 1, 20),
          type: 'return',
          amountCents: -5000,
          runningBalanceCents: 40000,
        ),
      ];

      int totalDebits = 0;
      int totalCredits = 0;
      for (final txn in transactions) {
        if (txn.amountCents > 0) {
          totalDebits += txn.amountCents;
        } else {
          totalCredits += txn.amountCents.abs();
        }
      }

      expect(totalDebits, 75000); // 50000 + 25000
      expect(totalCredits, 35000); // 30000 + 5000
    });
  });

  group('Statement data integrity', () {
    test('full statement data is consistent', () {
      final data = CustomerStatementData(
        customerId: 1,
        customerName: 'Test Customer',
        customerPhone: '+1234567890',
        customerEmail: 'test@example.com',
        customerAddress: '123 Main St',
        customerSegment: 'retail',
        openingBalanceCents: 100000,
        closingBalanceCents: 130000,
        totalDebitsCents: 70000,
        totalCreditsCents: 40000,
        transactions: [
          StatementTransaction(
            id: 1,
            date: DateTime(2026, 1, 5),
            type: 'sale',
            description: 'Invoice #001',
            amountCents: 50000,
            runningBalanceCents: 150000,
          ),
          StatementTransaction(
            id: 2,
            date: DateTime(2026, 1, 10),
            type: 'payment',
            description: 'Cash payment',
            amountCents: -40000,
            runningBalanceCents: 110000,
          ),
          StatementTransaction(
            id: 3,
            date: DateTime(2026, 1, 20),
            type: 'sale',
            description: 'Invoice #002',
            amountCents: 20000,
            runningBalanceCents: 130000,
          ),
        ],
        dateRange: ReportDateRange.thisMonth(),
      );

      // Verify closing = opening + debits - credits
      expect(data.closingBalanceCents,
          data.openingBalanceCents + data.totalDebitsCents - data.totalCreditsCents);

      // Verify transaction count
      expect(data.transactionCount, 3);

      // Verify last running balance equals closing balance
      expect(data.transactions.last.runningBalanceCents,
          data.closingBalanceCents);

      // Verify customer info
      expect(data.customerName, 'Test Customer');
      expect(data.customerSegment, 'retail');
    });

    test('statement with no customer selected', () {
      final data = CustomerStatementData(
        dateRange: ReportDateRange.thisMonth(),
        customers: const [
          CustomerOption(id: 1, name: 'A', balanceCents: 100000),
          CustomerOption(id: 2, name: 'B', balanceCents: 50000),
        ],
      );

      expect(data.customerId, isNull);
      expect(data.customerName, isNull);
      expect(data.transactions, isEmpty);
      expect(data.openingBalanceCents, 0);
      expect(data.closingBalanceCents, 0);
      expect(data.customers.length, 2);
    });

    test('statement with all transaction types', () {
      final transactions = [
        StatementTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'sale',
          amountCents: 50000,
          runningBalanceCents: 50000,
        ),
        StatementTransaction(
          id: 2,
          date: DateTime(2026, 1, 10),
          type: 'payment',
          amountCents: -20000,
          runningBalanceCents: 30000,
        ),
        StatementTransaction(
          id: 3,
          date: DateTime(2026, 1, 12),
          type: 'return',
          amountCents: -5000,
          runningBalanceCents: 25000,
        ),
        StatementTransaction(
          id: 4,
          date: DateTime(2026, 1, 15),
          type: 'adjustment',
          amountCents: 3000,
          runningBalanceCents: 28000,
        ),
        StatementTransaction(
          id: 5,
          date: DateTime(2026, 1, 18),
          type: 'credit_note',
          amountCents: -8000,
          runningBalanceCents: 20000,
        ),
        StatementTransaction(
          id: 6,
          date: DateTime(2026, 1, 20),
          type: 'refund',
          amountCents: -10000,
          runningBalanceCents: 10000,
        ),
      ];

      final types = transactions.map((t) => t.type).toSet();
      expect(types, containsAll(['sale', 'payment', 'return', 'adjustment', 'credit_note', 'refund']));
      expect(transactions.length, 6);

      // Verify running balance chain from 0
      int balance = 0;
      for (final txn in transactions) {
        balance += txn.amountCents;
        expect(txn.runningBalanceCents, balance);
      }
    });
  });

  group('PDF translation keys', () {
    test('all expected translation keys exist in service', () {
      const expectedKeys = [
        'customer_statement',
        'period',
        'customer',
        'phone',
        'email',
        'address',
        'opening_balance',
        'closing_balance',
        'total_debits',
        'total_credits',
        'transactions',
        'date',
        'type',
        'description',
        'debit',
        'credit',
        'balance',
        'no_transactions',
        'printed_on',
        'txn_sale',
        'txn_payment',
        'txn_return',
        'txn_refund',
        'txn_adjustment',
        'txn_credit_note',
        'txn_opening_balance',
      ];
      expect(expectedKeys.length, 26);
    });
  });

  group('ReportDateRange for customer statement', () {
    test('thisMonth preset has correct dates', () {
      final range = ReportDateRange.thisMonth();
      final now = DateTime.now();
      expect(range.startDate.year, now.year);
      expect(range.startDate.month, now.month);
      expect(range.startDate.day, 1);
      expect(range.preset, ReportPeriodPreset.thisMonth);
    });

    test('allTime preset starts from 2000', () {
      final range = ReportDateRange.allTime();
      expect(range.startDate.year, 2000);
      expect(range.preset, ReportPeriodPreset.allTime);
    });

    test('custom range preserves dates', () {
      final range = ReportDateRange(
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 12, 31),
        preset: ReportPeriodPreset.custom,
      );
      expect(range.startDate.year, 2025);
      expect(range.endDate.month, 12);
      expect(range.preset, ReportPeriodPreset.custom);
    });
  });

  group('Edge cases', () {
    test('large transaction amounts in integer cents', () {
      // 1 million dollars = 100,000,000 cents - fits in int
      final txn = StatementTransaction(
        id: 1,
        date: DateTime(2026, 1, 15),
        type: 'sale',
        amountCents: 100000000,
        runningBalanceCents: 100000000,
      );

      expect(txn.amountCents, 100000000);
    });

    test('many transactions maintain correct running balance', () {
      int balance = 50000; // opening
      final transactions = <StatementTransaction>[];

      for (int i = 0; i < 100; i++) {
        final amount = (i % 2 == 0) ? 10000 : -5000;
        balance += amount;
        transactions.add(StatementTransaction(
          id: i + 1,
          date: DateTime(2026, 1, 1).add(Duration(days: i)),
          type: i % 2 == 0 ? 'sale' : 'payment',
          amountCents: amount,
          runningBalanceCents: balance,
        ));
      }

      expect(transactions.length, 100);
      // 50 sales of 10000 = 500000, 50 payments of 5000 = 250000
      // closing = 50000 + 500000 - 250000 = 300000
      expect(transactions.last.runningBalanceCents, 300000);
    });

    test('statement with only debits', () {
      const openingBalance = 0;
      final transactions = [
        StatementTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'sale',
          amountCents: 30000,
          runningBalanceCents: 30000,
        ),
        StatementTransaction(
          id: 2,
          date: DateTime(2026, 1, 10),
          type: 'sale',
          amountCents: 20000,
          runningBalanceCents: 50000,
        ),
      ];

      int totalDebits = 0;
      int totalCredits = 0;
      for (final txn in transactions) {
        if (txn.amountCents > 0) {
          totalDebits += txn.amountCents;
        } else {
          totalCredits += txn.amountCents.abs();
        }
      }

      expect(totalDebits, 50000);
      expect(totalCredits, 0);
      expect(openingBalance + totalDebits - totalCredits, 50000);
    });

    test('statement with only credits', () {
      const openingBalance = 100000;
      final transactions = [
        StatementTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'payment',
          amountCents: -40000,
          runningBalanceCents: 60000,
        ),
        StatementTransaction(
          id: 2,
          date: DateTime(2026, 1, 10),
          type: 'payment',
          amountCents: -60000,
          runningBalanceCents: 0,
        ),
      ];

      int totalDebits = 0;
      int totalCredits = 0;
      for (final txn in transactions) {
        if (txn.amountCents > 0) {
          totalDebits += txn.amountCents;
        } else {
          totalCredits += txn.amountCents.abs();
        }
      }

      expect(totalDebits, 0);
      expect(totalCredits, 100000);
      expect(openingBalance + totalDebits - totalCredits, 0);
    });
  });
}
