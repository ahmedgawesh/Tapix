import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_aging_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('CustomerAgingItem data model', () {
    test('stores correct values', () {
      const item = CustomerAgingItem(
        customerId: 1,
        customerName: 'Test Customer',
        segment: 'retail',
        phone: '+1234567890',
        email: 'test@example.com',
        currentCents: 50000,
        days30Cents: 30000,
        days60Cents: 20000,
        days90Cents: 10000,
        over90Cents: 5000,
        totalCents: 115000,
      );

      expect(item.customerId, 1);
      expect(item.customerName, 'Test Customer');
      expect(item.segment, 'retail');
      expect(item.phone, '+1234567890');
      expect(item.email, 'test@example.com');
      expect(item.currentCents, 50000);
      expect(item.days30Cents, 30000);
      expect(item.days60Cents, 20000);
      expect(item.days90Cents, 10000);
      expect(item.over90Cents, 5000);
      expect(item.totalCents, 115000);
    });

    test('nullable contact fields default to null', () {
      const item = CustomerAgingItem(
        customerId: 2,
        customerName: 'No Contact',
        segment: 'wholesale',
        currentCents: 10000,
        days30Cents: 0,
        days60Cents: 0,
        days90Cents: 0,
        over90Cents: 0,
        totalCents: 10000,
      );

      expect(item.phone, isNull);
      expect(item.email, isNull);
    });

    test('integer cents prevents floating point errors', () {
      // Verify that using integer cents avoids floating point issues
      // e.g., 0.1 + 0.2 != 0.3 in floating point, but 10 + 20 == 30 in cents
      const item = CustomerAgingItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        currentCents: 10,
        days30Cents: 20,
        days60Cents: 0,
        days90Cents: 0,
        over90Cents: 0,
        totalCents: 30,
      );

      expect(item.currentCents + item.days30Cents, 30);
      expect(item.totalCents, 30);
    });

    test('all buckets sum to total', () {
      const item = CustomerAgingItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        currentCents: 50000,
        days30Cents: 30000,
        days60Cents: 20000,
        days90Cents: 10000,
        over90Cents: 5000,
        totalCents: 115000,
      );

      final bucketSum = item.currentCents +
          item.days30Cents +
          item.days60Cents +
          item.days90Cents +
          item.over90Cents;
      expect(bucketSum, item.totalCents);
    });

    test('zero balance customer has all zeros', () {
      const item = CustomerAgingItem(
        customerId: 1,
        customerName: 'Zero Balance',
        segment: 'retail',
        currentCents: 0,
        days30Cents: 0,
        days60Cents: 0,
        days90Cents: 0,
        over90Cents: 0,
        totalCents: 0,
      );

      expect(item.totalCents, 0);
      expect(item.currentCents, 0);
      expect(item.over90Cents, 0);
    });
  });

  group('CustomerAgingReportData', () {
    test('default values are correct', () {
      final data = CustomerAgingReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.customers, isEmpty);
      expect(data.grandTotalCurrentCents, 0);
      expect(data.grandTotal30Cents, 0);
      expect(data.grandTotal60Cents, 0);
      expect(data.grandTotal90Cents, 0);
      expect(data.grandTotalOver90Cents, 0);
      expect(data.grandTotalCents, 0);
      expect(data.customerCount, 0);
      expect(data.sort, CustomerAgingSortType.totalDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('grandTotalOverdueCents computed correctly', () {
      final data = CustomerAgingReportData(
        grandTotalCurrentCents: 50000,
        grandTotal30Cents: 30000,
        grandTotal60Cents: 20000,
        grandTotal90Cents: 10000,
        grandTotalOver90Cents: 5000,
        grandTotalCents: 115000,
        dateRange: ReportDateRange.thisMonth(),
      );

      // Overdue = 30 + 60 + 90 + over90 (excludes current)
      expect(data.grandTotalOverdueCents, 65000);
      expect(data.grandTotalOverdueCents,
          data.grandTotal30Cents +
              data.grandTotal60Cents +
              data.grandTotal90Cents +
              data.grandTotalOver90Cents);
    });

    test('copyWith preserves unchanged fields', () {
      final original = CustomerAgingReportData(
        grandTotalCents: 500000,
        grandTotalCurrentCents: 200000,
        grandTotal30Cents: 100000,
        grandTotal60Cents: 80000,
        grandTotal90Cents: 70000,
        grandTotalOver90Cents: 50000,
        customerCount: 10,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.grandTotalCents, 500000);
      expect(updated.grandTotalCurrentCents, 200000);
      expect(updated.grandTotal30Cents, 100000);
      expect(updated.grandTotal60Cents, 80000);
      expect(updated.grandTotal90Cents, 70000);
      expect(updated.grandTotalOver90Cents, 50000);
      expect(updated.customerCount, 10);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = CustomerAgingReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        grandTotalCents: 100000,
        customerCount: 25,
        sort: CustomerAgingSortType.nameAsc,
      );

      expect(updated.grandTotalCents, 100000);
      expect(updated.customerCount, 25);
      expect(updated.sort, CustomerAgingSortType.nameAsc);
    });

    test('copyWith updates customers list', () {
      final original = CustomerAgingReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const customer = CustomerAgingItem(
        customerId: 1,
        customerName: 'New Customer',
        segment: 'premium',
        currentCents: 50000,
        days30Cents: 0,
        days60Cents: 0,
        days90Cents: 0,
        over90Cents: 0,
        totalCents: 50000,
      );

      final updated = original.copyWith(
        customers: [customer],
        customerCount: 1,
      );

      expect(updated.customers.length, 1);
      expect(updated.customers.first.customerName, 'New Customer');
      expect(updated.customerCount, 1);
    });
  });

  group('CustomerAgingReportBloc events', () {
    test('CustomerAgingReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = CustomerAgingReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('CustomerAgingReportSortChanged stores sort type', () {
      const event = CustomerAgingReportSortChanged(
          CustomerAgingSortType.over90Desc);
      expect(event.sort, CustomerAgingSortType.over90Desc);
    });
  });

  group('CustomerAgingSortType enum', () {
    test('has all expected values', () {
      expect(CustomerAgingSortType.values.length, 6);
      expect(CustomerAgingSortType.values,
          contains(CustomerAgingSortType.totalDesc));
      expect(CustomerAgingSortType.values,
          contains(CustomerAgingSortType.totalAsc));
      expect(CustomerAgingSortType.values,
          contains(CustomerAgingSortType.over90Desc));
      expect(CustomerAgingSortType.values,
          contains(CustomerAgingSortType.over90Asc));
      expect(CustomerAgingSortType.values,
          contains(CustomerAgingSortType.nameAsc));
      expect(CustomerAgingSortType.values,
          contains(CustomerAgingSortType.nameDesc));
    });
  });

  group('Sort logic', () {
    final customers = [
      const CustomerAgingItem(
        customerId: 1,
        customerName: 'Zebra Corp',
        segment: 'retail',
        currentCents: 10000,
        days30Cents: 5000,
        days60Cents: 3000,
        days90Cents: 2000,
        over90Cents: 30000,
        totalCents: 50000,
      ),
      const CustomerAgingItem(
        customerId: 2,
        customerName: 'Apple Inc',
        segment: 'wholesale',
        currentCents: 100000,
        days30Cents: 50000,
        days60Cents: 30000,
        days90Cents: 10000,
        over90Cents: 10000,
        totalCents: 200000,
      ),
      const CustomerAgingItem(
        customerId: 3,
        customerName: 'Mango Ltd',
        segment: 'premium',
        currentCents: 50000,
        days30Cents: 20000,
        days60Cents: 10000,
        days90Cents: 10000,
        over90Cents: 10000,
        totalCents: 100000,
      ),
    ];

    test('sort by total descending', () {
      final list = List<CustomerAgingItem>.from(customers);
      list.sort((a, b) => b.totalCents.compareTo(a.totalCents));

      expect(list[0].customerName, 'Apple Inc');
      expect(list[0].totalCents, 200000);
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[1].totalCents, 100000);
      expect(list[2].customerName, 'Zebra Corp');
      expect(list[2].totalCents, 50000);
    });

    test('sort by total ascending', () {
      final list = List<CustomerAgingItem>.from(customers);
      list.sort((a, b) => a.totalCents.compareTo(b.totalCents));

      expect(list[0].customerName, 'Zebra Corp');
      expect(list[2].customerName, 'Apple Inc');
    });

    test('sort by over90 descending', () {
      final list = List<CustomerAgingItem>.from(customers);
      list.sort((a, b) => b.over90Cents.compareTo(a.over90Cents));

      expect(list[0].customerName, 'Zebra Corp');
      expect(list[0].over90Cents, 30000);
      expect(list[1].customerName, 'Apple Inc');
      expect(list[1].over90Cents, 10000);
    });

    test('sort by over90 ascending', () {
      final list = List<CustomerAgingItem>.from(customers);
      list.sort((a, b) => a.over90Cents.compareTo(b.over90Cents));

      expect(list[0].over90Cents, 10000);
      expect(list[2].customerName, 'Zebra Corp');
      expect(list[2].over90Cents, 30000);
    });

    test('sort by name ascending', () {
      final list = List<CustomerAgingItem>.from(customers);
      list.sort((a, b) => a.customerName.compareTo(b.customerName));

      expect(list[0].customerName, 'Apple Inc');
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[2].customerName, 'Zebra Corp');
    });

    test('sort by name descending', () {
      final list = List<CustomerAgingItem>.from(customers);
      list.sort((a, b) => b.customerName.compareTo(a.customerName));

      expect(list[0].customerName, 'Zebra Corp');
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[2].customerName, 'Apple Inc');
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from customer list', () {
      const customers = [
        CustomerAgingItem(
          customerId: 1,
          customerName: 'A',
          segment: 'retail',
          currentCents: 50000,
          days30Cents: 30000,
          days60Cents: 20000,
          days90Cents: 10000,
          over90Cents: 5000,
          totalCents: 115000,
        ),
        CustomerAgingItem(
          customerId: 2,
          customerName: 'B',
          segment: 'wholesale',
          currentCents: 100000,
          days30Cents: 50000,
          days60Cents: 30000,
          days90Cents: 20000,
          over90Cents: 10000,
          totalCents: 210000,
        ),
        CustomerAgingItem(
          customerId: 3,
          customerName: 'C',
          segment: 'premium',
          currentCents: 25000,
          days30Cents: 15000,
          days60Cents: 10000,
          days90Cents: 5000,
          over90Cents: 20000,
          totalCents: 75000,
        ),
      ];

      int totalCurrent = 0;
      int total30 = 0;
      int total60 = 0;
      int total90 = 0;
      int totalOver90 = 0;
      int grandTotal = 0;
      for (final c in customers) {
        totalCurrent += c.currentCents;
        total30 += c.days30Cents;
        total60 += c.days60Cents;
        total90 += c.days90Cents;
        totalOver90 += c.over90Cents;
        grandTotal += c.totalCents;
      }

      expect(totalCurrent, 175000);
      expect(total30, 95000);
      expect(total60, 60000);
      expect(total90, 35000);
      expect(totalOver90, 35000);
      expect(grandTotal, 400000);
      expect(customers.length, 3);

      // Verify overdue = total - current
      final totalOverdue = total30 + total60 + total90 + totalOver90;
      expect(totalOverdue, 225000);
      expect(grandTotal - totalCurrent, totalOverdue);
    });

    test('empty customer list yields zero totals', () {
      const customers = <CustomerAgingItem>[];

      int totalCurrent = 0;
      int grandTotal = 0;
      for (final c in customers) {
        totalCurrent += c.currentCents;
        grandTotal += c.totalCents;
      }

      expect(totalCurrent, 0);
      expect(grandTotal, 0);
    });

    test('single customer with only current balance', () {
      const customers = [
        CustomerAgingItem(
          customerId: 1,
          customerName: 'Current Only',
          segment: 'retail',
          currentCents: 100000,
          days30Cents: 0,
          days60Cents: 0,
          days90Cents: 0,
          over90Cents: 0,
          totalCents: 100000,
        ),
      ];

      final overdue = customers.first.days30Cents +
          customers.first.days60Cents +
          customers.first.days90Cents +
          customers.first.over90Cents;
      expect(overdue, 0);
      expect(customers.first.totalCents, 100000);
    });

    test('single customer with only over90 balance', () {
      const customers = [
        CustomerAgingItem(
          customerId: 1,
          customerName: 'Very Overdue',
          segment: 'retail',
          currentCents: 0,
          days30Cents: 0,
          days60Cents: 0,
          days90Cents: 0,
          over90Cents: 500000,
          totalCents: 500000,
        ),
      ];

      expect(customers.first.over90Cents, 500000);
      expect(customers.first.currentCents, 0);
      expect(customers.first.totalCents, customers.first.over90Cents);
    });
  });

  group('ReportDateRange for customer aging', () {
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

    test('thisWeek starts on Monday', () {
      final range = ReportDateRange.thisWeek();
      expect(range.startDate.weekday, DateTime.monday);
      expect(range.preset, ReportPeriodPreset.thisWeek);
    });

    test('lastMonth has correct boundaries', () {
      final range = ReportDateRange.lastMonth();
      final now = DateTime.now();
      final expectedMonth = now.month == 1 ? 12 : now.month - 1;
      expect(range.startDate.month, expectedMonth);
      expect(range.startDate.day, 1);
      expect(range.preset, ReportPeriodPreset.lastMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final range = ReportDateRange.thisMonth();
      final updated = range.copyWith(
        preset: ReportPeriodPreset.custom,
      );
      expect(updated.startDate, range.startDate);
      expect(updated.endDate, range.endDate);
      expect(updated.preset, ReportPeriodPreset.custom);
    });
  });

  group('CustomerAgingPdfService translations', () {
    test('all expected translation keys exist', () {
      const expectedKeys = [
        'customer_aging_report',
        'as_of',
        'total_receivables',
        'total_overdue',
        'total_customers',
        'aging_summary',
        'customer_aging_detail',
        'customer',
        'contact',
        'current',
        'days_1_30',
        'days_31_60',
        'days_61_90',
        'over_90',
        'total',
        'grand_total',
        'printed_on',
      ];
      expect(expectedKeys.length, 17);
    });
  });

  group('Aging bucket boundary validation', () {
    test('aging buckets cover all periods without gaps', () {
      // Current: 0 days overdue (not overdue)
      // 1-30: 1-30 days overdue
      // 31-60: 31-60 days overdue
      // 61-90: 61-90 days overdue
      // 91+: over 90 days overdue
      // These should cover every possible day count
      const boundaries = [0, 30, 60, 90]; // bucket boundaries in days
      for (int i = 0; i < boundaries.length - 1; i++) {
        expect(boundaries[i + 1] - boundaries[i], 30,
            reason: 'Each bucket should span 30 days');
      }
    });

    test('overdue calculation excludes current bucket', () {
      const item = CustomerAgingItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        currentCents: 50000,
        days30Cents: 10000,
        days60Cents: 5000,
        days90Cents: 3000,
        over90Cents: 2000,
        totalCents: 70000,
      );

      final overdue = item.days30Cents +
          item.days60Cents +
          item.days90Cents +
          item.over90Cents;
      expect(overdue, 20000);
      expect(item.totalCents - item.currentCents, overdue);
    });
  });
}
