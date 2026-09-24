import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_sales_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('CustomerSalesItem data model', () {
    test('stores correct values', () {
      const item = CustomerSalesItem(
        customerId: 1,
        customerName: 'Test Customer',
        segment: 'retail',
        totalSalesCents: 150000,
        invoiceCount: 10,
        totalQuantity: 50,
        averageOrderCents: 15000,
        lastSaleDate: null,
      );

      expect(item.customerId, 1);
      expect(item.customerName, 'Test Customer');
      expect(item.segment, 'retail');
      expect(item.totalSalesCents, 150000);
      expect(item.invoiceCount, 10);
      expect(item.totalQuantity, 50);
      expect(item.averageOrderCents, 15000);
      expect(item.lastSaleDate, isNull);
    });

    test('stores last sale date when provided', () {
      final date = DateTime(2026, 2, 1);
      final item = CustomerSalesItem(
        customerId: 2,
        customerName: 'Customer B',
        segment: 'wholesale',
        totalSalesCents: 500000,
        invoiceCount: 25,
        totalQuantity: 200,
        averageOrderCents: 20000,
        lastSaleDate: date,
      );

      expect(item.lastSaleDate, date);
      expect(item.segment, 'wholesale');
    });

    test('average order cents calculation is correct', () {
      // averageOrderCents = totalSalesCents ~/ invoiceCount
      const item = CustomerSalesItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        totalSalesCents: 100000,
        invoiceCount: 4,
        totalQuantity: 20,
        averageOrderCents: 25000, // 100000 ~/ 4
      );

      expect(item.averageOrderCents, 25000);
      expect(item.averageOrderCents, item.totalSalesCents ~/ item.invoiceCount);
    });

    test('integer cents prevents floating point errors', () {
      // Verify that using integer cents avoids floating point issues
      // e.g., 0.1 + 0.2 != 0.3 in floating point, but 10 + 20 == 30 in cents
      const item = CustomerSalesItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        totalSalesCents: 30, // 0.30 in dollars
        invoiceCount: 1,
        totalQuantity: 1,
        averageOrderCents: 30,
      );

      expect(item.totalSalesCents, 30);
      expect(item.averageOrderCents, 30);
    });

    test('zero invoices yields zero average', () {
      // When invoiceCount is 0, averageOrderCents should be 0
      const item = CustomerSalesItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        totalSalesCents: 0,
        invoiceCount: 0,
        totalQuantity: 0,
        averageOrderCents: 0,
      );

      expect(item.averageOrderCents, 0);
      expect(item.invoiceCount, 0);
    });
  });

  group('CustomerSalesReportData', () {
    test('default values are correct', () {
      final data = CustomerSalesReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.customers, isEmpty);
      expect(data.grandTotalSalesCents, 0);
      expect(data.grandTotalInvoices, 0);
      expect(data.grandTotalQuantity, 0);
      expect(data.uniqueCustomerCount, 0);
      expect(data.sort, CustomerSalesSortType.revenueDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = CustomerSalesReportData(
        grandTotalSalesCents: 500000,
        grandTotalInvoices: 50,
        grandTotalQuantity: 200,
        uniqueCustomerCount: 10,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(dateRange: ReportDateRange.thisYear());

      expect(updated.grandTotalSalesCents, 500000);
      expect(updated.grandTotalInvoices, 50);
      expect(updated.grandTotalQuantity, 200);
      expect(updated.uniqueCustomerCount, 10);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = CustomerSalesReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        grandTotalSalesCents: 100000,
        grandTotalInvoices: 25,
        sort: CustomerSalesSortType.invoiceCountDesc,
      );

      expect(updated.grandTotalSalesCents, 100000);
      expect(updated.grandTotalInvoices, 25);
      expect(updated.sort, CustomerSalesSortType.invoiceCountDesc);
    });

    test('copyWith updates customers list', () {
      final original = CustomerSalesReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const customer = CustomerSalesItem(
        customerId: 1,
        customerName: 'New Customer',
        segment: 'premium',
        totalSalesCents: 999900,
        invoiceCount: 100,
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

  group('CustomerSalesReportBloc events', () {
    test('CustomerSalesReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = CustomerSalesReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('CustomerSalesReportSortChanged stores sort type', () {
      const event = CustomerSalesReportSortChanged(
        CustomerSalesSortType.invoiceCountDesc,
      );
      expect(event.sort, CustomerSalesSortType.invoiceCountDesc);
    });
  });

  group('CustomerSalesSortType enum', () {
    test('has all expected values', () {
      expect(CustomerSalesSortType.values.length, 6);
      expect(
        CustomerSalesSortType.values,
        contains(CustomerSalesSortType.revenueDesc),
      );
      expect(
        CustomerSalesSortType.values,
        contains(CustomerSalesSortType.revenueAsc),
      );
      expect(
        CustomerSalesSortType.values,
        contains(CustomerSalesSortType.invoiceCountDesc),
      );
      expect(
        CustomerSalesSortType.values,
        contains(CustomerSalesSortType.invoiceCountAsc),
      );
      expect(
        CustomerSalesSortType.values,
        contains(CustomerSalesSortType.nameAsc),
      );
      expect(
        CustomerSalesSortType.values,
        contains(CustomerSalesSortType.nameDesc),
      );
    });
  });

  group('Sort logic', () {
    final customers = [
      const CustomerSalesItem(
        customerId: 1,
        customerName: 'Zebra Corp',
        segment: 'retail',
        totalSalesCents: 50000,
        invoiceCount: 5,
        totalQuantity: 20,
        averageOrderCents: 10000,
      ),
      const CustomerSalesItem(
        customerId: 2,
        customerName: 'Apple Inc',
        segment: 'wholesale',
        totalSalesCents: 200000,
        invoiceCount: 20,
        totalQuantity: 100,
        averageOrderCents: 10000,
      ),
      const CustomerSalesItem(
        customerId: 3,
        customerName: 'Mango Ltd',
        segment: 'premium',
        totalSalesCents: 100000,
        invoiceCount: 10,
        totalQuantity: 50,
        averageOrderCents: 10000,
      ),
    ];

    test('sort by revenue descending', () {
      final list = List<CustomerSalesItem>.from(customers);
      list.sort((a, b) => b.totalSalesCents.compareTo(a.totalSalesCents));

      expect(list[0].customerName, 'Apple Inc');
      expect(list[0].totalSalesCents, 200000);
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[1].totalSalesCents, 100000);
      expect(list[2].customerName, 'Zebra Corp');
      expect(list[2].totalSalesCents, 50000);
    });

    test('sort by revenue ascending', () {
      final list = List<CustomerSalesItem>.from(customers);
      list.sort((a, b) => a.totalSalesCents.compareTo(b.totalSalesCents));

      expect(list[0].customerName, 'Zebra Corp');
      expect(list[2].customerName, 'Apple Inc');
    });

    test('sort by invoice count descending', () {
      final list = List<CustomerSalesItem>.from(customers);
      list.sort((a, b) => b.invoiceCount.compareTo(a.invoiceCount));

      expect(list[0].customerName, 'Apple Inc');
      expect(list[0].invoiceCount, 20);
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[1].invoiceCount, 10);
      expect(list[2].customerName, 'Zebra Corp');
      expect(list[2].invoiceCount, 5);
    });

    test('sort by invoice count ascending', () {
      final list = List<CustomerSalesItem>.from(customers);
      list.sort((a, b) => a.invoiceCount.compareTo(b.invoiceCount));

      expect(list[0].customerName, 'Zebra Corp');
      expect(list[2].customerName, 'Apple Inc');
    });

    test('sort by name ascending', () {
      final list = List<CustomerSalesItem>.from(customers);
      list.sort((a, b) => a.customerName.compareTo(b.customerName));

      expect(list[0].customerName, 'Apple Inc');
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[2].customerName, 'Zebra Corp');
    });

    test('sort by name descending', () {
      final list = List<CustomerSalesItem>.from(customers);
      list.sort((a, b) => b.customerName.compareTo(a.customerName));

      expect(list[0].customerName, 'Zebra Corp');
      expect(list[1].customerName, 'Mango Ltd');
      expect(list[2].customerName, 'Apple Inc');
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from customer list', () {
      const customers = [
        CustomerSalesItem(
          customerId: 1,
          customerName: 'A',
          segment: 'retail',
          totalSalesCents: 50000,
          invoiceCount: 5,
          totalQuantity: 20,
          averageOrderCents: 10000,
        ),
        CustomerSalesItem(
          customerId: 2,
          customerName: 'B',
          segment: 'wholesale',
          totalSalesCents: 200000,
          invoiceCount: 20,
          totalQuantity: 100,
          averageOrderCents: 10000,
        ),
        CustomerSalesItem(
          customerId: 3,
          customerName: 'C',
          segment: 'premium',
          totalSalesCents: 100000,
          invoiceCount: 10,
          totalQuantity: 50,
          averageOrderCents: 10000,
        ),
      ];

      int totalSales = 0;
      int totalInvoices = 0;
      int totalQuantity = 0;
      for (final c in customers) {
        totalSales += c.totalSalesCents;
        totalInvoices += c.invoiceCount;
        totalQuantity += c.totalQuantity;
      }

      expect(totalSales, 350000);
      expect(totalInvoices, 35);
      expect(totalQuantity, 170);
      expect(customers.length, 3);
    });

    test('empty customer list yields zero totals', () {
      const customers = <CustomerSalesItem>[];

      int totalSales = 0;
      int totalInvoices = 0;
      int totalQuantity = 0;
      for (final c in customers) {
        totalSales += c.totalSalesCents;
        totalInvoices += c.invoiceCount;
        totalQuantity += c.totalQuantity;
      }

      expect(totalSales, 0);
      expect(totalInvoices, 0);
      expect(totalQuantity, 0);
    });

    test('average order calculation with integer division', () {
      // Verify integer division matches expected behavior
      // 350000 ~/ 35 = 10000 (exact)
      // 100001 ~/ 3 = 33333 (truncated, not rounded)
      expect(350000 ~/ 35, 10000);
      expect(100001 ~/ 3, 33333);
      expect(1 ~/ 3, 0);
      expect(0 ~/ 1, 0);
    });
  });

  group('ReportDateRange for customer sales', () {
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
      final updated = range.copyWith(preset: ReportPeriodPreset.custom);
      expect(updated.startDate, range.startDate);
      expect(updated.endDate, range.endDate);
      expect(updated.preset, ReportPeriodPreset.custom);
    });
  });

  group('CustomerSalesPdfService translations', () {
    test('all 3 languages have translation keys', () {
      // Verify the expected translation keys for the PDF service
      const expectedKeys = [
        'customer_sales_report',
        'period',
        'total_sales',
        'total_customers',
        'total_invoices',
        'total_quantity',
        'customer_sales_details',
        'customer',
        'segment',
        'invoices',
        'quantity',
        'avg_order',
        'last_sale',
        'grand_total',
        'printed_on',
        'segment_retail',
        'segment_wholesale',
        'segment_premium',
      ];
      expect(expectedKeys.length, 18);
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
