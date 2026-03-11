import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('CustomerBalanceItem data model', () {
    test('stores correct values', () {
      const item = CustomerBalanceItem(
        customerId: 1,
        customerName: 'Ahmed',
        segment: 'retail',
        openingBalanceCents: 10000,
        totalSalesCents: 50000,
        totalPaymentsCents: 30000,
        totalDiscountsCents: 2000,
        totalReturnsCents: 3000,
        currentBalanceCents: 25000,
      );

      expect(item.customerId, 1);
      expect(item.customerName, 'Ahmed');
      expect(item.segment, 'retail');
      expect(item.openingBalanceCents, 10000);
      expect(item.totalSalesCents, 50000);
      expect(item.totalPaymentsCents, 30000);
      expect(item.totalDiscountsCents, 2000);
      expect(item.totalReturnsCents, 3000);
      expect(item.currentBalanceCents, 25000);
    });

    test('negative balance indicates payable', () {
      const item = CustomerBalanceItem(
        customerId: 2,
        customerName: 'Test',
        segment: 'wholesale',
        openingBalanceCents: -5000,
        totalSalesCents: 0,
        totalPaymentsCents: 0,
        totalDiscountsCents: 0,
        totalReturnsCents: 0,
        currentBalanceCents: -5000,
      );

      expect(item.currentBalanceCents, lessThan(0));
      expect(item.openingBalanceCents, lessThan(0));
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

      expect(data.customers, isEmpty);
      expect(data.agingItems, isEmpty);
      expect(data.analyticsItems, isEmpty);
      expect(data.totalReceivablesCents, 0);
      expect(data.totalPayablesCents, 0);
      expect(data.totalOpeningDebitCents, 0);
      expect(data.totalOpeningCreditCents, 0);
      expect(data.totalDiscountsCents, 0);
      expect(data.totalPaymentsCents, 0);
      expect(data.activeCustomerCount, 0);
      expect(data.searchQuery, isEmpty);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = CustomerReportsData(
        totalReceivablesCents: 100000,
        totalPayablesCents: 5000,
        activeCustomerCount: 15,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.totalReceivablesCents, 100000);
      expect(updated.totalPayablesCents, 5000);
      expect(updated.activeCustomerCount, 15);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = CustomerReportsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        totalReceivablesCents: 50000,
        activeCustomerCount: 10,
      );

      expect(updated.totalReceivablesCents, 50000);
      expect(updated.activeCustomerCount, 10);
    });

    test('copyWith with customers list', () {
      final original = CustomerReportsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        customers: const [
          CustomerBalanceItem(
            customerId: 1,
            customerName: 'Test',
            segment: 'retail',
            openingBalanceCents: 0,
            totalSalesCents: 5000,
            totalPaymentsCents: 0,
            totalDiscountsCents: 0,
            totalReturnsCents: 0,
            currentBalanceCents: 5000,
          ),
        ],
      );

      expect(updated.customers.length, 1);
      expect(updated.customers[0].customerName, 'Test');
    });

    test('filteredCustomers filters by search query', () {
      final data = CustomerReportsData(
        dateRange: ReportDateRange.thisMonth(),
        customers: const [
          CustomerBalanceItem(
            customerId: 1,
            customerName: 'Ahmed Store',
            segment: 'retail',
            openingBalanceCents: 0,
            totalSalesCents: 5000,
            totalPaymentsCents: 0,
            totalDiscountsCents: 0,
            totalReturnsCents: 0,
            currentBalanceCents: 5000,
          ),
          CustomerBalanceItem(
            customerId: 2,
            customerName: 'Omar Shop',
            segment: 'wholesale',
            openingBalanceCents: 0,
            totalSalesCents: 3000,
            totalPaymentsCents: 0,
            totalDiscountsCents: 0,
            totalReturnsCents: 0,
            currentBalanceCents: 3000,
          ),
        ],
        searchQuery: 'ahmed',
      );

      expect(data.filteredCustomers.length, 1);
      expect(data.filteredCustomers[0].customerName, 'Ahmed Store');
    });

    test('filteredCustomers returns all when query is empty', () {
      final data = CustomerReportsData(
        dateRange: ReportDateRange.thisMonth(),
        customers: const [
          CustomerBalanceItem(
            customerId: 1,
            customerName: 'Ahmed',
            segment: 'retail',
            openingBalanceCents: 0,
            totalSalesCents: 0,
            totalPaymentsCents: 0,
            totalDiscountsCents: 0,
            totalReturnsCents: 0,
            currentBalanceCents: 0,
          ),
          CustomerBalanceItem(
            customerId: 2,
            customerName: 'Omar',
            segment: 'retail',
            openingBalanceCents: 0,
            totalSalesCents: 0,
            totalPaymentsCents: 0,
            totalDiscountsCents: 0,
            totalReturnsCents: 0,
            currentBalanceCents: 0,
          ),
        ],
      );

      expect(data.filteredCustomers.length, 2);
    });
  });

  group('CustomerReportsEvent', () {
    test('CustomerReportsDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = CustomerReportsDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('CustomerReportsSearchChanged stores query', () {
      const event = CustomerReportsSearchChanged('test');
      expect(event.query, 'test');
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

    test('balance classification (receivable vs payable)', () {
      const customers = [
        CustomerBalanceItem(
          customerId: 1,
          customerName: 'A',
          segment: 'retail',
          openingBalanceCents: 5000,
          totalSalesCents: 10000,
          totalPaymentsCents: 5000,
          totalDiscountsCents: 0,
          totalReturnsCents: 0,
          currentBalanceCents: 10000, // positive = receivable
        ),
        CustomerBalanceItem(
          customerId: 2,
          customerName: 'B',
          segment: 'retail',
          openingBalanceCents: -3000,
          totalSalesCents: 0,
          totalPaymentsCents: 0,
          totalDiscountsCents: 0,
          totalReturnsCents: 0,
          currentBalanceCents: -3000, // negative = payable
        ),
      ];

      int totalReceivables = 0;
      int totalPayables = 0;
      for (final c in customers) {
        if (c.currentBalanceCents > 0) {
          totalReceivables += c.currentBalanceCents;
        } else if (c.currentBalanceCents < 0) {
          totalPayables += c.currentBalanceCents.abs();
        }
      }

      expect(totalReceivables, 10000);
      expect(totalPayables, 3000);
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
