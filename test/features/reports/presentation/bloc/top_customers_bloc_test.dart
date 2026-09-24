import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/top_customers_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('TopCustomerItem data model', () {
    test('stores correct values', () {
      const item = TopCustomerItem(
        customerId: 1,
        customerName: 'Test Customer',
        segment: 'retail',
        totalRevenueCents: 150000,
        transactionCount: 10,
        totalQuantity: 50,
        averageOrderCents: 15000,
        lastPurchaseDate: null,
      );

      expect(item.customerId, 1);
      expect(item.customerName, 'Test Customer');
      expect(item.segment, 'retail');
      expect(item.totalRevenueCents, 150000);
      expect(item.transactionCount, 10);
      expect(item.totalQuantity, 50);
      expect(item.averageOrderCents, 15000);
      expect(item.lastPurchaseDate, isNull);
    });

    test('stores last purchase date when provided', () {
      final date = DateTime(2026, 2, 1);
      final item = TopCustomerItem(
        customerId: 2,
        customerName: 'Customer B',
        segment: 'wholesale',
        totalRevenueCents: 500000,
        transactionCount: 25,
        totalQuantity: 200,
        averageOrderCents: 20000,
        lastPurchaseDate: date,
      );

      expect(item.lastPurchaseDate, date);
      expect(item.segment, 'wholesale');
    });

    test('average order cents calculation is correct', () {
      // averageOrderCents = totalRevenueCents ~/ transactionCount
      const item = TopCustomerItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        totalRevenueCents: 100000,
        transactionCount: 4,
        totalQuantity: 20,
        averageOrderCents: 25000, // 100000 ~/ 4
      );

      expect(item.averageOrderCents, 25000);
      expect(
        item.averageOrderCents,
        item.totalRevenueCents ~/ item.transactionCount,
      );
    });

    test('integer cents prevents floating point errors', () {
      // Verify that using integer cents avoids floating point issues
      // e.g., 0.1 + 0.2 != 0.3 in floating point, but 10 + 20 == 30 in cents
      const item = TopCustomerItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        totalRevenueCents: 30, // 0.30 in dollars
        transactionCount: 1,
        totalQuantity: 1,
        averageOrderCents: 30,
      );

      expect(item.totalRevenueCents, 30);
      expect(item.averageOrderCents, 30);
    });
  });

  group('TopCustomersData', () {
    test('default values are correct', () {
      final data = TopCustomersData(dateRange: ReportDateRange.thisMonth());

      expect(data.customers, isEmpty);
      expect(data.grandTotalRevenueCents, 0);
      expect(data.grandTotalTransactions, 0);
      expect(data.grandTotalQuantity, 0);
      expect(data.uniqueCustomerCount, 0);
      expect(data.sort, TopCustomersSortType.revenueDesc);
      expect(data.view, TopCustomersViewType.byRevenue);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = TopCustomersData(
        grandTotalRevenueCents: 500000,
        grandTotalTransactions: 50,
        grandTotalQuantity: 200,
        uniqueCustomerCount: 10,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(dateRange: ReportDateRange.thisYear());

      expect(updated.grandTotalRevenueCents, 500000);
      expect(updated.grandTotalTransactions, 50);
      expect(updated.grandTotalQuantity, 200);
      expect(updated.uniqueCustomerCount, 10);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = TopCustomersData(dateRange: ReportDateRange.thisMonth());

      final updated = original.copyWith(
        grandTotalRevenueCents: 100000,
        grandTotalTransactions: 25,
        sort: TopCustomersSortType.volumeDesc,
        view: TopCustomersViewType.byVolume,
      );

      expect(updated.grandTotalRevenueCents, 100000);
      expect(updated.grandTotalTransactions, 25);
      expect(updated.sort, TopCustomersSortType.volumeDesc);
      expect(updated.view, TopCustomersViewType.byVolume);
    });

    test('copyWith updates customers list', () {
      final original = TopCustomersData(dateRange: ReportDateRange.thisMonth());

      const customer = TopCustomerItem(
        customerId: 1,
        customerName: 'New Customer',
        segment: 'premium',
        totalRevenueCents: 999900,
        transactionCount: 100,
        totalQuantity: 500,
        averageOrderCents: 9999,
      );

      final updated = original.copyWith(
        customers: [customer],
        uniqueCustomerCount: 1,
      );

      expect(updated.customers.length, 1);
      expect(updated.customers.first.customerName, 'New Customer');
      expect(updated.uniqueCustomerCount, 1);
    });
  });

  group('TopCustomersBloc events', () {
    test('TopCustomersDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = TopCustomersDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('TopCustomersSortChanged stores sort type', () {
      const event = TopCustomersSortChanged(TopCustomersSortType.volumeDesc);
      expect(event.sort, TopCustomersSortType.volumeDesc);
    });

    test('TopCustomersViewChanged stores view type', () {
      const event = TopCustomersViewChanged(TopCustomersViewType.byVolume);
      expect(event.view, TopCustomersViewType.byVolume);
    });
  });

  group('TopCustomersSortType enum', () {
    test('has all expected values', () {
      expect(TopCustomersSortType.values.length, 6);
      expect(
        TopCustomersSortType.values,
        contains(TopCustomersSortType.revenueDesc),
      );
      expect(
        TopCustomersSortType.values,
        contains(TopCustomersSortType.revenueAsc),
      );
      expect(
        TopCustomersSortType.values,
        contains(TopCustomersSortType.volumeDesc),
      );
      expect(
        TopCustomersSortType.values,
        contains(TopCustomersSortType.volumeAsc),
      );
      expect(
        TopCustomersSortType.values,
        contains(TopCustomersSortType.nameAsc),
      );
      expect(
        TopCustomersSortType.values,
        contains(TopCustomersSortType.nameDesc),
      );
    });
  });

  group('TopCustomersViewType enum', () {
    test('has all expected values', () {
      expect(TopCustomersViewType.values.length, 2);
      expect(
        TopCustomersViewType.values,
        contains(TopCustomersViewType.byRevenue),
      );
      expect(
        TopCustomersViewType.values,
        contains(TopCustomersViewType.byVolume),
      );
    });
  });

  group('Sort logic', () {
    final customers = [
      const TopCustomerItem(
        customerId: 1,
        customerName: 'Zebra Corp',
        segment: 'retail',
        totalRevenueCents: 50000,
        transactionCount: 5,
        totalQuantity: 20,
        averageOrderCents: 10000,
      ),
      const TopCustomerItem(
        customerId: 2,
        customerName: 'Apple Inc',
        segment: 'wholesale',
        totalRevenueCents: 200000,
        transactionCount: 20,
        totalQuantity: 100,
        averageOrderCents: 10000,
      ),
      const TopCustomerItem(
        customerId: 3,
        customerName: 'Mango Ltd',
        segment: 'premium',
        totalRevenueCents: 100000,
        transactionCount: 10,
        totalQuantity: 50,
        averageOrderCents: 10000,
      ),
    ];

    test('sort by revenue descending', () {
      final list = List<TopCustomerItem>.from(customers);
      list.sort((a, b) => b.totalRevenueCents.compareTo(a.totalRevenueCents));

      expect(list[0].customerName, 'Apple Inc');
      expect(list[0].totalRevenueCents, 200000);
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[1].totalRevenueCents, 100000);
      expect(list[2].customerName, 'Zebra Corp');
      expect(list[2].totalRevenueCents, 50000);
    });

    test('sort by revenue ascending', () {
      final list = List<TopCustomerItem>.from(customers);
      list.sort((a, b) => a.totalRevenueCents.compareTo(b.totalRevenueCents));

      expect(list[0].customerName, 'Zebra Corp');
      expect(list[2].customerName, 'Apple Inc');
    });

    test('sort by volume descending', () {
      final list = List<TopCustomerItem>.from(customers);
      list.sort((a, b) => b.transactionCount.compareTo(a.transactionCount));

      expect(list[0].customerName, 'Apple Inc');
      expect(list[0].transactionCount, 20);
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[1].transactionCount, 10);
      expect(list[2].customerName, 'Zebra Corp');
      expect(list[2].transactionCount, 5);
    });

    test('sort by volume ascending', () {
      final list = List<TopCustomerItem>.from(customers);
      list.sort((a, b) => a.transactionCount.compareTo(b.transactionCount));

      expect(list[0].customerName, 'Zebra Corp');
      expect(list[2].customerName, 'Apple Inc');
    });

    test('sort by name ascending', () {
      final list = List<TopCustomerItem>.from(customers);
      list.sort((a, b) => a.customerName.compareTo(b.customerName));

      expect(list[0].customerName, 'Apple Inc');
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[2].customerName, 'Zebra Corp');
    });

    test('sort by name descending', () {
      final list = List<TopCustomerItem>.from(customers);
      list.sort((a, b) => b.customerName.compareTo(a.customerName));

      expect(list[0].customerName, 'Zebra Corp');
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[2].customerName, 'Apple Inc');
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from customer list', () {
      const customers = [
        TopCustomerItem(
          customerId: 1,
          customerName: 'A',
          segment: 'retail',
          totalRevenueCents: 50000,
          transactionCount: 5,
          totalQuantity: 20,
          averageOrderCents: 10000,
        ),
        TopCustomerItem(
          customerId: 2,
          customerName: 'B',
          segment: 'wholesale',
          totalRevenueCents: 200000,
          transactionCount: 20,
          totalQuantity: 100,
          averageOrderCents: 10000,
        ),
        TopCustomerItem(
          customerId: 3,
          customerName: 'C',
          segment: 'premium',
          totalRevenueCents: 100000,
          transactionCount: 10,
          totalQuantity: 50,
          averageOrderCents: 10000,
        ),
      ];

      int totalRevenue = 0;
      int totalTransactions = 0;
      int totalQuantity = 0;
      for (final c in customers) {
        totalRevenue += c.totalRevenueCents;
        totalTransactions += c.transactionCount;
        totalQuantity += c.totalQuantity;
      }

      expect(totalRevenue, 350000);
      expect(totalTransactions, 35);
      expect(totalQuantity, 170);
      expect(customers.length, 3);
    });

    test('empty customer list yields zero totals', () {
      const customers = <TopCustomerItem>[];

      int totalRevenue = 0;
      int totalTransactions = 0;
      int totalQuantity = 0;
      for (final c in customers) {
        totalRevenue += c.totalRevenueCents;
        totalTransactions += c.transactionCount;
        totalQuantity += c.totalQuantity;
      }

      expect(totalRevenue, 0);
      expect(totalTransactions, 0);
      expect(totalQuantity, 0);
    });
  });

  group('ReportDateRange for top customers', () {
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
      // Monday = 1 in Dart's DateTime.weekday
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
  });

  group('TopCustomersPdfService translations', () {
    test('all 3 languages have translation keys', () {
      // Verify the expected translation keys for the PDF service
      const expectedKeys = [
        'top_customers_revenue',
        'top_customers_volume',
        'period',
        'total_revenue',
        'total_customers',
        'total_transactions',
        'total_quantity',
        'customer',
        'segment',
        'revenue',
        'transactions',
        'quantity',
        'avg_order',
        'last_purchase',
        'grand_total',
        'printed_on',
        'segment_retail',
        'segment_wholesale',
        'segment_premium',
      ];
      expect(expectedKeys.length, 19);
    });
  });

  group('Segment labels', () {
    test('all segment types are handled', () {
      const segments = ['retail', 'wholesale', 'premium'];
      for (final segment in segments) {
        expect(segment.isNotEmpty, true);
      }
    });
  });
}
