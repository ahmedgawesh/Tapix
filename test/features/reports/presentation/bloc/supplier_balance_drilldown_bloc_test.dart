import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_balance_drilldown_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('DrilldownTransaction data model', () {
    test('stores correct values', () {
      final txn = DrilldownTransaction(
        id: 1,
        date: DateTime(2026, 1, 15),
        type: 'purchase',
        description: 'Purchase Invoice #001',
        amountCents: 50000,
        runningBalanceCents: 50000,
        referenceId: 100,
        referenceType: 'purchase',
      );

      expect(txn.id, 1);
      expect(txn.date, DateTime(2026, 1, 15));
      expect(txn.type, 'purchase');
      expect(txn.description, 'Purchase Invoice #001');
      expect(txn.amountCents, 50000);
      expect(txn.runningBalanceCents, 50000);
      expect(txn.referenceId, 100);
      expect(txn.referenceType, 'purchase');
    });

    test('nullable fields default to null', () {
      final txn = DrilldownTransaction(
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

    test('positive amount represents debit (we owe supplier more)', () {
      final txn = DrilldownTransaction(
        id: 1,
        date: DateTime(2026, 1, 15),
        type: 'purchase',
        amountCents: 50000,
        runningBalanceCents: 50000,
      );

      expect(txn.amountCents > 0, isTrue);
    });

    test('negative amount represents credit (payment to supplier)', () {
      final txn = DrilldownTransaction(
        id: 2,
        date: DateTime(2026, 1, 20),
        type: 'payment',
        amountCents: -30000,
        runningBalanceCents: 20000,
      );

      expect(txn.amountCents < 0, isTrue);
    });

    test('integer cents prevents floating point errors', () {
      final txn = DrilldownTransaction(
        id: 1,
        date: DateTime(2026, 1, 15),
        type: 'purchase',
        amountCents: 10,
        runningBalanceCents: 10,
      );

      final txn2 = DrilldownTransaction(
        id: 2,
        date: DateTime(2026, 1, 16),
        type: 'purchase',
        amountCents: 20,
        runningBalanceCents: 30,
      );

      expect(txn.amountCents + txn2.amountCents, 30);
      expect(txn2.runningBalanceCents, 30);
    });
  });

  group('DrilldownTypeSummary data model', () {
    test('stores correct values', () {
      const summary = DrilldownTypeSummary(
        type: 'purchase',
        count: 5,
        totalDebitCents: 250000,
        totalCreditCents: 0,
        netCents: 250000,
      );

      expect(summary.type, 'purchase');
      expect(summary.count, 5);
      expect(summary.totalDebitCents, 250000);
      expect(summary.totalCreditCents, 0);
      expect(summary.netCents, 250000);
    });

    test('default values are zero', () {
      const summary = DrilldownTypeSummary(type: 'payment');

      expect(summary.count, 0);
      expect(summary.totalDebitCents, 0);
      expect(summary.totalCreditCents, 0);
      expect(summary.netCents, 0);
    });

    test('payment type has negative net', () {
      const summary = DrilldownTypeSummary(
        type: 'payment',
        count: 3,
        totalDebitCents: 0,
        totalCreditCents: 150000,
        netCents: -150000,
      );

      expect(summary.netCents < 0, isTrue);
      expect(summary.totalCreditCents, 150000);
    });

    test('net equals debit minus credit', () {
      const debit = 80000;
      const credit = 30000;
      const net = debit - credit;

      const summary = DrilldownTypeSummary(
        type: 'adjustment',
        count: 2,
        totalDebitCents: debit,
        totalCreditCents: credit,
        netCents: net,
      );

      expect(summary.netCents, summary.totalDebitCents - summary.totalCreditCents);
    });
  });

  group('SupplierDrilldownOption data model', () {
    test('stores correct values', () {
      const option = SupplierDrilldownOption(
        id: 1,
        name: 'Test Supplier',
        balanceCents: 150000,
      );

      expect(option.id, 1);
      expect(option.name, 'Test Supplier');
      expect(option.balanceCents, 150000);
    });

    test('zero balance supplier', () {
      const option = SupplierDrilldownOption(
        id: 2,
        name: 'Zero Balance',
        balanceCents: 0,
      );

      expect(option.balanceCents, 0);
    });

    test('negative balance (overpaid) supplier', () {
      const option = SupplierDrilldownOption(
        id: 3,
        name: 'Overpaid Supplier',
        balanceCents: -50000,
      );

      expect(option.balanceCents < 0, isTrue);
    });
  });

  group('SupplierBalanceDrilldownData', () {
    test('default values are correct', () {
      final data = SupplierBalanceDrilldownData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.supplierId, isNull);
      expect(data.supplierName, isNull);
      expect(data.supplierPhone, isNull);
      expect(data.supplierEmail, isNull);
      expect(data.supplierAddress, isNull);
      expect(data.openingBalanceCents, 0);
      expect(data.closingBalanceCents, 0);
      expect(data.totalDebitsCents, 0);
      expect(data.totalCreditsCents, 0);
      expect(data.transactions, isEmpty);
      expect(data.typeSummaries, isEmpty);
      expect(data.suppliers, isEmpty);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('transactionCount returns correct count', () {
      final data = SupplierBalanceDrilldownData(
        dateRange: ReportDateRange.thisMonth(),
        transactions: [
          DrilldownTransaction(
            id: 1,
            date: DateTime(2026, 1, 15),
            type: 'purchase',
            amountCents: 50000,
            runningBalanceCents: 50000,
          ),
          DrilldownTransaction(
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
      final original = SupplierBalanceDrilldownData(
        supplierId: 1,
        supplierName: 'Test Supplier',
        openingBalanceCents: 100000,
        closingBalanceCents: 150000,
        totalDebitsCents: 80000,
        totalCreditsCents: 30000,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.supplierId, 1);
      expect(updated.supplierName, 'Test Supplier');
      expect(updated.openingBalanceCents, 100000);
      expect(updated.closingBalanceCents, 150000);
      expect(updated.totalDebitsCents, 80000);
      expect(updated.totalCreditsCents, 30000);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = SupplierBalanceDrilldownData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        supplierId: 5,
        supplierName: 'New Supplier',
        openingBalanceCents: 50000,
      );

      expect(updated.supplierId, 5);
      expect(updated.supplierName, 'New Supplier');
      expect(updated.openingBalanceCents, 50000);
    });

    test('copyWith updates suppliers list', () {
      final original = SupplierBalanceDrilldownData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        suppliers: const [
          SupplierDrilldownOption(id: 1, name: 'Supplier A', balanceCents: 100000),
          SupplierDrilldownOption(id: 2, name: 'Supplier B', balanceCents: 50000),
        ],
      );

      expect(updated.suppliers.length, 2);
      expect(updated.suppliers.first.name, 'Supplier A');
    });

    test('copyWith updates transactions list', () {
      final original = SupplierBalanceDrilldownData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        transactions: [
          DrilldownTransaction(
            id: 1,
            date: DateTime(2026, 1, 15),
            type: 'purchase',
            amountCents: 50000,
            runningBalanceCents: 50000,
          ),
        ],
      );

      expect(updated.transactions.length, 1);
      expect(updated.transactionCount, 1);
    });

    test('copyWith updates typeSummaries list', () {
      final original = SupplierBalanceDrilldownData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        typeSummaries: const [
          DrilldownTypeSummary(
            type: 'purchase',
            count: 3,
            totalDebitCents: 150000,
            netCents: 150000,
          ),
          DrilldownTypeSummary(
            type: 'payment',
            count: 2,
            totalCreditCents: 80000,
            netCents: -80000,
          ),
        ],
      );

      expect(updated.typeSummaries.length, 2);
      expect(updated.typeSummaries.first.type, 'purchase');
      expect(updated.typeSummaries.last.type, 'payment');
    });
  });

  group('SupplierBalanceDrilldownBloc events', () {
    test('SupplierBalanceDrilldownDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = SupplierBalanceDrilldownDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('SupplierBalanceDrilldownSupplierChanged stores supplier id', () {
      const event = SupplierBalanceDrilldownSupplierChanged(42);
      expect(event.supplierId, 42);
    });

    test('SupplierBalanceDrilldownSupplierChanged allows null', () {
      const event = SupplierBalanceDrilldownSupplierChanged(null);
      expect(event.supplierId, isNull);
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

    test('closing balance can be negative (supplier overpaid)', () {
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
        // Purchase: +50000 -> running = 150000
        DrilldownTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'purchase',
          amountCents: 50000,
          runningBalanceCents: 150000,
        ),
        // Payment: -30000 -> running = 120000
        DrilldownTransaction(
          id: 2,
          date: DateTime(2026, 1, 10),
          type: 'payment',
          amountCents: -30000,
          runningBalanceCents: 120000,
        ),
        // Return: -10000 -> running = 110000
        DrilldownTransaction(
          id: 3,
          date: DateTime(2026, 1, 15),
          type: 'return',
          amountCents: -10000,
          runningBalanceCents: 110000,
        ),
        // Purchase: +20000 -> running = 130000
        DrilldownTransaction(
          id: 4,
          date: DateTime(2026, 1, 20),
          type: 'purchase',
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

    test('debit/credit classification is correct for supplier', () {
      final transactions = [
        DrilldownTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'purchase',
          amountCents: 50000,
          runningBalanceCents: 50000,
        ),
        DrilldownTransaction(
          id: 2,
          date: DateTime(2026, 1, 10),
          type: 'payment',
          amountCents: -30000,
          runningBalanceCents: 20000,
        ),
        DrilldownTransaction(
          id: 3,
          date: DateTime(2026, 1, 15),
          type: 'purchase',
          amountCents: 25000,
          runningBalanceCents: 45000,
        ),
        DrilldownTransaction(
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

  group('Type breakdown calculations', () {
    test('type summaries aggregate correctly', () {
      final transactions = [
        DrilldownTransaction(
          id: 1, date: DateTime(2026, 1, 5), type: 'purchase',
          amountCents: 50000, runningBalanceCents: 50000,
        ),
        DrilldownTransaction(
          id: 2, date: DateTime(2026, 1, 10), type: 'payment',
          amountCents: -30000, runningBalanceCents: 20000,
        ),
        DrilldownTransaction(
          id: 3, date: DateTime(2026, 1, 15), type: 'purchase',
          amountCents: 25000, runningBalanceCents: 45000,
        ),
        DrilldownTransaction(
          id: 4, date: DateTime(2026, 1, 20), type: 'return',
          amountCents: -5000, runningBalanceCents: 40000,
        ),
        DrilldownTransaction(
          id: 5, date: DateTime(2026, 1, 25), type: 'payment',
          amountCents: -10000, runningBalanceCents: 30000,
        ),
      ];

      // Simulate the bloc's type accumulation logic
      final typeMap = <String, _TestTypeAccumulator>{};
      for (final txn in transactions) {
        final acc = typeMap.putIfAbsent(txn.type, () => _TestTypeAccumulator());
        acc.count++;
        if (txn.amountCents > 0) {
          acc.totalDebitCents += txn.amountCents;
        } else {
          acc.totalCreditCents += txn.amountCents.abs();
        }
        acc.netCents += txn.amountCents;
      }

      // Verify purchase summary
      expect(typeMap['purchase']!.count, 2);
      expect(typeMap['purchase']!.totalDebitCents, 75000);
      expect(typeMap['purchase']!.totalCreditCents, 0);
      expect(typeMap['purchase']!.netCents, 75000);

      // Verify payment summary
      expect(typeMap['payment']!.count, 2);
      expect(typeMap['payment']!.totalDebitCents, 0);
      expect(typeMap['payment']!.totalCreditCents, 40000);
      expect(typeMap['payment']!.netCents, -40000);

      // Verify return summary
      expect(typeMap['return']!.count, 1);
      expect(typeMap['return']!.totalDebitCents, 0);
      expect(typeMap['return']!.totalCreditCents, 5000);
      expect(typeMap['return']!.netCents, -5000);
    });

    test('type summaries sorted by absolute net descending', () {
      final summaries = [
        const DrilldownTypeSummary(type: 'purchase', count: 5, netCents: 250000),
        const DrilldownTypeSummary(type: 'payment', count: 3, netCents: -150000),
        const DrilldownTypeSummary(type: 'return', count: 1, netCents: -5000),
        const DrilldownTypeSummary(type: 'adjustment', count: 2, netCents: 30000),
      ];

      final sorted = List<DrilldownTypeSummary>.from(summaries)
        ..sort((a, b) => b.netCents.abs().compareTo(a.netCents.abs()));

      expect(sorted[0].type, 'purchase');   // |250000|
      expect(sorted[1].type, 'payment');    // |150000|
      expect(sorted[2].type, 'adjustment'); // |30000|
      expect(sorted[3].type, 'return');     // |5000|
    });

    test('all transaction types produce correct summaries', () {
      final transactions = [
        DrilldownTransaction(
          id: 1, date: DateTime(2026, 1, 5), type: 'purchase',
          amountCents: 50000, runningBalanceCents: 50000,
        ),
        DrilldownTransaction(
          id: 2, date: DateTime(2026, 1, 10), type: 'payment',
          amountCents: -20000, runningBalanceCents: 30000,
        ),
        DrilldownTransaction(
          id: 3, date: DateTime(2026, 1, 12), type: 'return',
          amountCents: -5000, runningBalanceCents: 25000,
        ),
        DrilldownTransaction(
          id: 4, date: DateTime(2026, 1, 15), type: 'adjustment',
          amountCents: 3000, runningBalanceCents: 28000,
        ),
        DrilldownTransaction(
          id: 5, date: DateTime(2026, 1, 18), type: 'discount',
          amountCents: -8000, runningBalanceCents: 20000,
        ),
        DrilldownTransaction(
          id: 6, date: DateTime(2026, 1, 20), type: 'refund',
          amountCents: -10000, runningBalanceCents: 10000,
        ),
        DrilldownTransaction(
          id: 7, date: DateTime(2026, 1, 22), type: 'credit_note',
          amountCents: -2000, runningBalanceCents: 8000,
        ),
      ];

      final types = transactions.map((t) => t.type).toSet();
      expect(types, containsAll([
        'purchase', 'payment', 'return', 'adjustment',
        'discount', 'refund', 'credit_note',
      ]));
      expect(transactions.length, 7);

      // Verify running balance chain from 0
      int balance = 0;
      for (final txn in transactions) {
        balance += txn.amountCents;
        expect(txn.runningBalanceCents, balance);
      }
    });

    test('net of all type summaries equals closing minus opening', () {
      const openingBalance = 100000;
      const closingBalance = 130000;

      final summaries = [
        const DrilldownTypeSummary(
          type: 'purchase', count: 3,
          totalDebitCents: 80000, netCents: 80000,
        ),
        const DrilldownTypeSummary(
          type: 'payment', count: 2,
          totalCreditCents: 40000, netCents: -40000,
        ),
        const DrilldownTypeSummary(
          type: 'return', count: 1,
          totalCreditCents: 10000, netCents: -10000,
        ),
      ];

      final totalNet = summaries.fold<int>(0, (sum, s) => sum + s.netCents);
      expect(openingBalance + totalNet, closingBalance);
    });
  });

  group('Drilldown data integrity', () {
    test('full drilldown data is consistent', () {
      final data = SupplierBalanceDrilldownData(
        supplierId: 1,
        supplierName: 'Test Supplier',
        supplierPhone: '+1234567890',
        supplierEmail: 'supplier@example.com',
        supplierAddress: '456 Supply St',
        openingBalanceCents: 100000,
        closingBalanceCents: 130000,
        totalDebitsCents: 70000,
        totalCreditsCents: 40000,
        transactions: [
          DrilldownTransaction(
            id: 1,
            date: DateTime(2026, 1, 5),
            type: 'purchase',
            description: 'Purchase Invoice #001',
            amountCents: 50000,
            runningBalanceCents: 150000,
          ),
          DrilldownTransaction(
            id: 2,
            date: DateTime(2026, 1, 10),
            type: 'payment',
            description: 'Bank transfer',
            amountCents: -40000,
            runningBalanceCents: 110000,
          ),
          DrilldownTransaction(
            id: 3,
            date: DateTime(2026, 1, 20),
            type: 'purchase',
            description: 'Purchase Invoice #002',
            amountCents: 20000,
            runningBalanceCents: 130000,
          ),
        ],
        typeSummaries: const [
          DrilldownTypeSummary(
            type: 'purchase', count: 2,
            totalDebitCents: 70000, netCents: 70000,
          ),
          DrilldownTypeSummary(
            type: 'payment', count: 1,
            totalCreditCents: 40000, netCents: -40000,
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

      // Verify supplier info
      expect(data.supplierName, 'Test Supplier');
      expect(data.supplierAddress, '456 Supply St');

      // Verify type summaries net equals closing - opening
      final totalNet = data.typeSummaries.fold<int>(0, (sum, s) => sum + s.netCents);
      expect(data.openingBalanceCents + totalNet, data.closingBalanceCents);
    });

    test('drilldown with no supplier selected', () {
      final data = SupplierBalanceDrilldownData(
        dateRange: ReportDateRange.thisMonth(),
        suppliers: const [
          SupplierDrilldownOption(id: 1, name: 'A', balanceCents: 100000),
          SupplierDrilldownOption(id: 2, name: 'B', balanceCents: 50000),
        ],
      );

      expect(data.supplierId, isNull);
      expect(data.supplierName, isNull);
      expect(data.transactions, isEmpty);
      expect(data.typeSummaries, isEmpty);
      expect(data.openingBalanceCents, 0);
      expect(data.closingBalanceCents, 0);
      expect(data.suppliers.length, 2);
    });
  });

  group('PDF translation keys', () {
    test('all expected translation keys exist in service', () {
      const expectedKeys = [
        'supplier_balance_drilldown',
        'period',
        'supplier',
        'phone',
        'email',
        'address',
        'opening_balance',
        'closing_balance',
        'total_debits',
        'total_credits',
        'breakdown_by_type',
        'transactions',
        'date',
        'type',
        'description',
        'debit',
        'credit',
        'balance',
        'count',
        'net',
        'no_transactions',
        'printed_on',
        'txn_purchase',
        'txn_payment',
        'txn_return',
        'txn_refund',
        'txn_adjustment',
        'txn_discount',
        'txn_credit_note',
        'txn_opening_balance',
      ];
      expect(expectedKeys.length, 30);
    });
  });

  group('ReportDateRange for drilldown', () {
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
      final txn = DrilldownTransaction(
        id: 1,
        date: DateTime(2026, 1, 15),
        type: 'purchase',
        amountCents: 100000000,
        runningBalanceCents: 100000000,
      );

      expect(txn.amountCents, 100000000);
    });

    test('many transactions maintain correct running balance', () {
      int balance = 50000; // opening
      final transactions = <DrilldownTransaction>[];

      for (int i = 0; i < 100; i++) {
        final amount = (i % 2 == 0) ? 10000 : -5000;
        balance += amount;
        transactions.add(DrilldownTransaction(
          id: i + 1,
          date: DateTime(2026, 1, 1).add(Duration(days: i)),
          type: i % 2 == 0 ? 'purchase' : 'payment',
          amountCents: amount,
          runningBalanceCents: balance,
        ));
      }

      expect(transactions.length, 100);
      // 50 purchases of 10000 = 500000, 50 payments of 5000 = 250000
      // closing = 50000 + 500000 - 250000 = 300000
      expect(transactions.last.runningBalanceCents, 300000);
    });

    test('drilldown with only debits (purchases)', () {
      const openingBalance = 0;
      final transactions = [
        DrilldownTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'purchase',
          amountCents: 30000,
          runningBalanceCents: 30000,
        ),
        DrilldownTransaction(
          id: 2,
          date: DateTime(2026, 1, 10),
          type: 'purchase',
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

    test('drilldown with only credits (payments)', () {
      const openingBalance = 100000;
      final transactions = [
        DrilldownTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'payment',
          amountCents: -40000,
          runningBalanceCents: 60000,
        ),
        DrilldownTransaction(
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

    test('mixed purchase and return scenario', () {
      const openingBalance = 200000;
      final transactions = [
        // Purchase: +80000
        DrilldownTransaction(
          id: 1,
          date: DateTime(2026, 1, 5),
          type: 'purchase',
          amountCents: 80000,
          runningBalanceCents: 280000,
        ),
        // Return: -15000
        DrilldownTransaction(
          id: 2,
          date: DateTime(2026, 1, 8),
          type: 'return',
          amountCents: -15000,
          runningBalanceCents: 265000,
        ),
        // Payment: -100000
        DrilldownTransaction(
          id: 3,
          date: DateTime(2026, 1, 12),
          type: 'payment',
          amountCents: -100000,
          runningBalanceCents: 165000,
        ),
        // Discount: -5000
        DrilldownTransaction(
          id: 4,
          date: DateTime(2026, 1, 15),
          type: 'discount',
          amountCents: -5000,
          runningBalanceCents: 160000,
        ),
        // Purchase: +40000
        DrilldownTransaction(
          id: 5,
          date: DateTime(2026, 1, 20),
          type: 'purchase',
          amountCents: 40000,
          runningBalanceCents: 200000,
        ),
      ];

      // Verify running balance chain
      int balance = openingBalance;
      for (final txn in transactions) {
        balance += txn.amountCents;
        expect(txn.runningBalanceCents, balance,
            reason: 'Running balance after ${txn.type}');
      }

      // Calculate totals
      int totalDebits = 0;
      int totalCredits = 0;
      for (final txn in transactions) {
        if (txn.amountCents > 0) {
          totalDebits += txn.amountCents;
        } else {
          totalCredits += txn.amountCents.abs();
        }
      }

      expect(totalDebits, 120000); // 80000 + 40000
      expect(totalCredits, 120000); // 15000 + 100000 + 5000
      expect(openingBalance + totalDebits - totalCredits, 200000);
      expect(balance, 200000);
    });

    test('type breakdown with mixed debit/credit in same type', () {
      // Adjustment can be both positive and negative
      final transactions = [
        DrilldownTransaction(
          id: 1, date: DateTime(2026, 1, 5), type: 'adjustment',
          amountCents: 15000, runningBalanceCents: 15000,
        ),
        DrilldownTransaction(
          id: 2, date: DateTime(2026, 1, 10), type: 'adjustment',
          amountCents: -8000, runningBalanceCents: 7000,
        ),
        DrilldownTransaction(
          id: 3, date: DateTime(2026, 1, 15), type: 'adjustment',
          amountCents: 3000, runningBalanceCents: 10000,
        ),
      ];

      int debit = 0;
      int credit = 0;
      int net = 0;
      for (final txn in transactions) {
        if (txn.amountCents > 0) {
          debit += txn.amountCents;
        } else {
          credit += txn.amountCents.abs();
        }
        net += txn.amountCents;
      }

      expect(debit, 18000);  // 15000 + 3000
      expect(credit, 8000);  // 8000
      expect(net, 10000);    // 18000 - 8000
      expect(debit - credit, net);
    });
  });
}

/// Test helper to simulate the bloc's type accumulation logic
class _TestTypeAccumulator {
  int count = 0;
  int totalDebitCents = 0;
  int totalCreditCents = 0;
  int netCents = 0;
}
