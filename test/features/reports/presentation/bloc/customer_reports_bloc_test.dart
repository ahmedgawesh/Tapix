import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('CustomerStatementItem data model', () {
    test('stores correct values', () {
      final item = CustomerStatementItem(
        transactionId: 1,
        date: DateTime(2026, 1, 15),
        type: 'sale',
        description: 'Sale invoice #100',
        amountCents: 50000,
        runningBalanceCents: 75000,
      );

      expect(item.transactionId, 1);
      expect(item.date, DateTime(2026, 1, 15));
      expect(item.type, 'sale');
      expect(item.description, 'Sale invoice #100');
      expect(item.amountCents, 50000);
      expect(item.runningBalanceCents, 75000);
    });

    test('nullable description defaults to null', () {
      final item = CustomerStatementItem(
        transactionId: 1,
        date: DateTime(2026, 1, 1),
        type: 'payment',
        amountCents: -10000,
        runningBalanceCents: 40000,
      );

      expect(item.description, isNull);
    });
  });

  group('CustomerStatementData data model', () {
    test('stores correct values', () {
      const data = CustomerStatementData(
        customerId: 1,
        customerName: 'Ahmed',
        openingBalanceCents: 10000,
        closingBalanceCents: 25000,
        totalDebitCents: 20000,
        totalCreditCents: 5000,
        items: [],
      );

      expect(data.customerId, 1);
      expect(data.customerName, 'Ahmed');
      expect(data.openingBalanceCents, 10000);
      expect(data.closingBalanceCents, 25000);
      expect(data.totalDebitCents, 20000);
      expect(data.totalCreditCents, 5000);
      expect(data.items, isEmpty);
    });

    test('items list holds statement items', () {
      final items = [
        CustomerStatementItem(
          transactionId: 1,
          date: DateTime(2026, 1, 5),
          type: 'sale',
          amountCents: 15000,
          runningBalanceCents: 25000,
        ),
        CustomerStatementItem(
          transactionId: 2,
          date: DateTime(2026, 1, 10),
          type: 'payment',
          amountCents: -5000,
          runningBalanceCents: 20000,
        ),
      ];

      final data = CustomerStatementData(
        customerId: 1,
        customerName: 'Test',
        openingBalanceCents: 10000,
        closingBalanceCents: 20000,
        totalDebitCents: 15000,
        totalCreditCents: 5000,
        items: items,
      );

      expect(data.items.length, 2);
      expect(data.items[0].type, 'sale');
      expect(data.items[1].type, 'payment');
    });
  });

  group('CustomerAgingItem data model', () {
    test('stores correct values', () {
      const item = CustomerAgingItem(
        customerId: 1,
        customerName: 'Test Customer',
        segment: 'retail',
        currentCents: 5000,
        days30Cents: 3000,
        days60Cents: 2000,
        days90Cents: 1000,
        over90Cents: 500,
        totalCents: 11500,
      );

      expect(item.customerId, 1);
      expect(item.customerName, 'Test Customer');
      expect(item.segment, 'retail');
      expect(item.currentCents, 5000);
      expect(item.days30Cents, 3000);
      expect(item.days60Cents, 2000);
      expect(item.days90Cents, 1000);
      expect(item.over90Cents, 500);
      expect(item.totalCents, 11500);
    });

    test('aging buckets sum to total', () {
      const item = CustomerAgingItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'wholesale',
        currentCents: 10000,
        days30Cents: 5000,
        days60Cents: 3000,
        days90Cents: 2000,
        over90Cents: 1000,
        totalCents: 21000,
      );

      final sum = item.currentCents +
          item.days30Cents +
          item.days60Cents +
          item.days90Cents +
          item.over90Cents;
      expect(sum, item.totalCents);
    });
  });

  group('CustomerAnalyticsItem data model', () {
    test('stores correct values', () {
      final item = CustomerAnalyticsItem(
        customerId: 1,
        customerName: 'Premium Customer',
        segment: 'premium',
        totalSpentCents: 500000,
        totalTransactions: 25,
        averageOrderCents: 20000,
        balanceCents: 15000,
        lastTransactionAt: DateTime(2026, 2, 1),
      );

      expect(item.customerId, 1);
      expect(item.customerName, 'Premium Customer');
      expect(item.segment, 'premium');
      expect(item.totalSpentCents, 500000);
      expect(item.totalTransactions, 25);
      expect(item.averageOrderCents, 20000);
      expect(item.balanceCents, 15000);
      expect(item.lastTransactionAt, DateTime(2026, 2, 1));
    });

    test('nullable lastTransactionAt defaults to null', () {
      const item = CustomerAnalyticsItem(
        customerId: 1,
        customerName: 'New Customer',
        segment: 'retail',
        totalSpentCents: 0,
        totalTransactions: 0,
        averageOrderCents: 0,
        balanceCents: 0,
      );

      expect(item.lastTransactionAt, isNull);
    });
  });

  group('CustomerReportsData', () {
    test('default values are correct', () {
      final data = CustomerReportsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.statements, isEmpty);
      expect(data.agingItems, isEmpty);
      expect(data.analyticsItems, isEmpty);
      expect(data.totalReceivablesCents, 0);
      expect(data.totalCustomers, 0);
      expect(data.totalOverdueCents, 0);
      expect(data.activeTab, 0);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = CustomerReportsData(
        totalReceivablesCents: 100000,
        totalCustomers: 15,
        totalOverdueCents: 30000,
        dateRange: ReportDateRange.thisMonth(),
        activeTab: 1,
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.totalReceivablesCents, 100000);
      expect(updated.totalCustomers, 15);
      expect(updated.totalOverdueCents, 30000);
      expect(updated.activeTab, 1);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = CustomerReportsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        totalReceivablesCents: 50000,
        totalCustomers: 10,
        activeTab: 2,
      );

      expect(updated.totalReceivablesCents, 50000);
      expect(updated.totalCustomers, 10);
      expect(updated.activeTab, 2);
    });

    test('copyWith with statements list', () {
      final original = CustomerReportsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        statements: [
          const CustomerStatementData(
            customerId: 1,
            customerName: 'Test',
            openingBalanceCents: 0,
            closingBalanceCents: 5000,
            totalDebitCents: 5000,
            totalCreditCents: 0,
            items: [],
          ),
        ],
      );

      expect(updated.statements.length, 1);
      expect(updated.statements[0].customerName, 'Test');
    });
  });

  group('CustomerReportsEvent', () {
    test('CustomerReportsDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = CustomerReportsDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('CustomerReportsTabChanged stores tab index', () {
      const event = CustomerReportsTabChanged(2);
      expect(event.tabIndex, 2);
    });
  });

  group('Money calculations verification (integer cents)', () {
    test('aging totals use integer cents', () {
      const items = [
        CustomerAgingItem(
          customerId: 1,
          customerName: 'A',
          segment: 'retail',
          currentCents: 15050,
          days30Cents: 7525,
          days60Cents: 3000,
          days90Cents: 1500,
          over90Cents: 999,
          totalCents: 28074,
        ),
        CustomerAgingItem(
          customerId: 2,
          customerName: 'B',
          segment: 'wholesale',
          currentCents: 25075,
          days30Cents: 10000,
          days60Cents: 5000,
          days90Cents: 2500,
          over90Cents: 1001,
          totalCents: 43576,
        ),
      ];

      int totalReceivables = 0;
      int totalOverdue = 0;
      for (final item in items) {
        totalReceivables += item.totalCents;
        totalOverdue += item.days30Cents +
            item.days60Cents +
            item.days90Cents +
            item.over90Cents;
      }

      expect(totalReceivables, 71650); // 28074 + 43576
      expect(totalOverdue, 31525); // 7525+3000+1500+999 + 10000+5000+2500+1001
    });

    test('statement running balance tracks correctly', () {
      int openingBalance = 10000;
      final amounts = [5000, -3000, 8000, -2000];
      int running = openingBalance;

      for (final amount in amounts) {
        running += amount;
      }

      // 10000 + 5000 - 3000 + 8000 - 2000 = 18000
      expect(running, 18000);
    });

    test('analytics average order uses integer division', () {
      const totalSpent = 10000;
      const totalTx = 3;
      final avgOrder = totalTx > 0 ? totalSpent ~/ totalTx : 0;

      // 10000 ~/ 3 = 3333 (integer division)
      expect(avgOrder, 3333);
      expect(avgOrder, isA<int>());
    });
  });

  group('ReportDateRange for customer reports', () {
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
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 6, 30),
        preset: ReportPeriodPreset.custom,
      );
      expect(range.startDate, DateTime(2026, 1, 1));
      expect(range.endDate, DateTime(2026, 6, 30));
      expect(range.preset, ReportPeriodPreset.custom);
    });
  });
}
