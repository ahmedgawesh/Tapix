import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_sales_returns_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('CustomerReturnSummary data model', () {
    test('stores correct values', () {
      final item = CustomerReturnSummary(
        customerId: 1,
        customerName: 'John Doe',
        segment: 'retail',
        returnCount: 5,
        totalReturnedCents: 50000,
        totalItemsReturned: 12,
        lastReturnDate: DateTime(2026, 1, 15),
      );

      expect(item.customerId, 1);
      expect(item.customerName, 'John Doe');
      expect(item.segment, 'retail');
      expect(item.returnCount, 5);
      expect(item.totalReturnedCents, 50000);
      expect(item.totalItemsReturned, 12);
      expect(item.lastReturnDate, DateTime(2026, 1, 15));
    });

    test('averageReturnCents computes correctly', () {
      const item = CustomerReturnSummary(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        returnCount: 4,
        totalReturnedCents: 10000,
        totalItemsReturned: 8,
      );

      // 10000 ~/ 4 = 2500
      expect(item.averageReturnCents, 2500);
    });

    test('averageReturnCents returns 0 when no returns', () {
      const item = CustomerReturnSummary(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        returnCount: 0,
        totalReturnedCents: 0,
        totalItemsReturned: 0,
      );

      expect(item.averageReturnCents, 0);
    });

    test('averageReturnCents uses integer division', () {
      const item = CustomerReturnSummary(
        customerId: 1,
        customerName: 'Test',
        segment: 'wholesale',
        returnCount: 3,
        totalReturnedCents: 10000,
        totalItemsReturned: 6,
      );

      // 10000 ~/ 3 = 3333 (integer division)
      expect(item.averageReturnCents, 3333);
    });

    test('nullable lastReturnDate defaults to null', () {
      const item = CustomerReturnSummary(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        returnCount: 0,
        totalReturnedCents: 0,
        totalItemsReturned: 0,
      );

      expect(item.lastReturnDate, isNull);
    });
  });

  group('ReturnDetailItem data model', () {
    test('stores correct values', () {
      final item = ReturnDetailItem(
        returnId: 10,
        returnNumber: 'RET-001',
        returnDate: DateTime(2026, 2, 1),
        status: 'posted',
        dispositionType: 'restock',
        refundMethod: 'cash',
        reason: 'defective',
        totalCents: 15000,
        itemCount: 3,
        originalInvoiceNumber: 'INV-100',
      );

      expect(item.returnId, 10);
      expect(item.returnNumber, 'RET-001');
      expect(item.returnDate, DateTime(2026, 2, 1));
      expect(item.status, 'posted');
      expect(item.dispositionType, 'restock');
      expect(item.refundMethod, 'cash');
      expect(item.reason, 'defective');
      expect(item.totalCents, 15000);
      expect(item.itemCount, 3);
      expect(item.originalInvoiceNumber, 'INV-100');
    });

    test('nullable fields default to null', () {
      final item = ReturnDetailItem(
        returnId: 1,
        returnNumber: 'RET-002',
        returnDate: DateTime(2026, 1, 1),
        status: 'posted',
        dispositionType: 'refund',
        refundMethod: 'credit',
        totalCents: 5000,
        itemCount: 1,
      );

      expect(item.reason, isNull);
      expect(item.originalInvoiceNumber, isNull);
    });
  });

  group('ReturnReasonBreakdown data model', () {
    test('stores correct values', () {
      const item = ReturnReasonBreakdown(
        reason: 'defective',
        count: 10,
        totalCents: 25000,
      );

      expect(item.reason, 'defective');
      expect(item.count, 10);
      expect(item.totalCents, 25000);
    });
  });

  group('CustomerSalesReturnsData', () {
    test('default values are correct', () {
      final data = CustomerSalesReturnsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.customerSummaries, isEmpty);
      expect(data.returnDetails, isEmpty);
      expect(data.reasonBreakdown, isEmpty);
      expect(data.totalReturnsCents, 0);
      expect(data.totalReturnCount, 0);
      expect(data.totalItemsReturned, 0);
      expect(data.customersWithReturns, 0);
      expect(data.sort, ReturnsSortType.totalDesc);
      expect(data.selectedCustomerId, isNull);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = CustomerSalesReturnsData(
        totalReturnsCents: 50000,
        totalReturnCount: 10,
        totalItemsReturned: 25,
        customersWithReturns: 5,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(dateRange: ReportDateRange.thisYear());

      expect(updated.totalReturnsCents, 50000);
      expect(updated.totalReturnCount, 10);
      expect(updated.totalItemsReturned, 25);
      expect(updated.customersWithReturns, 5);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = CustomerSalesReturnsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        totalReturnsCents: 100000,
        totalReturnCount: 20,
        sort: ReturnsSortType.customerAsc,
      );

      expect(updated.totalReturnsCents, 100000);
      expect(updated.totalReturnCount, 20);
      expect(updated.sort, ReturnsSortType.customerAsc);
    });

    test('copyWith handles nullable selectedCustomerId', () {
      final original = CustomerSalesReturnsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      // Set to a value
      final withCustomer = original.copyWith(selectedCustomerId: () => 42);
      expect(withCustomer.selectedCustomerId, 42);

      // Set back to null
      final withoutCustomer = withCustomer.copyWith(
        selectedCustomerId: () => null,
      );
      expect(withoutCustomer.selectedCustomerId, isNull);
    });

    test('copyWith preserves selectedCustomerId when not specified', () {
      final original = CustomerSalesReturnsData(
        dateRange: ReportDateRange.thisMonth(),
        selectedCustomerId: 99,
      );

      final updated = original.copyWith(totalReturnsCents: 5000);
      expect(updated.selectedCustomerId, 99);
    });
  });

  group('CustomerSalesReturnsEvent', () {
    test('CustomerSalesReturnsDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = CustomerSalesReturnsDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('CustomerSalesReturnsSortChanged stores sort type', () {
      const event = CustomerSalesReturnsSortChanged(
        ReturnsSortType.customerAsc,
      );
      expect(event.sort, ReturnsSortType.customerAsc);
    });
  });

  group('ReturnsSortType', () {
    test('enum has all expected values', () {
      expect(ReturnsSortType.values.length, 6);
      expect(ReturnsSortType.values, contains(ReturnsSortType.customerAsc));
      expect(ReturnsSortType.values, contains(ReturnsSortType.customerDesc));
      expect(ReturnsSortType.values, contains(ReturnsSortType.totalDesc));
      expect(ReturnsSortType.values, contains(ReturnsSortType.totalAsc));
      expect(ReturnsSortType.values, contains(ReturnsSortType.countDesc));
      expect(ReturnsSortType.values, contains(ReturnsSortType.countAsc));
    });

    test('sort by customer name ascending works', () {
      final items = [
        const CustomerReturnSummary(
          customerId: 1,
          customerName: 'Zara',
          segment: 'retail',
          returnCount: 2,
          totalReturnedCents: 5000,
          totalItemsReturned: 3,
        ),
        const CustomerReturnSummary(
          customerId: 2,
          customerName: 'Ahmed',
          segment: 'wholesale',
          returnCount: 5,
          totalReturnedCents: 15000,
          totalItemsReturned: 10,
        ),
        const CustomerReturnSummary(
          customerId: 3,
          customerName: 'Mohamed',
          segment: 'premium',
          returnCount: 1,
          totalReturnedCents: 3000,
          totalItemsReturned: 1,
        ),
      ];

      items.sort((a, b) => a.customerName.compareTo(b.customerName));

      expect(items[0].customerName, 'Ahmed');
      expect(items[1].customerName, 'Mohamed');
      expect(items[2].customerName, 'Zara');
    });

    test('sort by total returned descending works', () {
      final items = [
        const CustomerReturnSummary(
          customerId: 1,
          customerName: 'A',
          segment: 'retail',
          returnCount: 2,
          totalReturnedCents: 5000,
          totalItemsReturned: 3,
        ),
        const CustomerReturnSummary(
          customerId: 2,
          customerName: 'B',
          segment: 'retail',
          returnCount: 5,
          totalReturnedCents: 15000,
          totalItemsReturned: 10,
        ),
        const CustomerReturnSummary(
          customerId: 3,
          customerName: 'C',
          segment: 'retail',
          returnCount: 1,
          totalReturnedCents: 3000,
          totalItemsReturned: 1,
        ),
      ];

      items.sort(
        (a, b) => b.totalReturnedCents.compareTo(a.totalReturnedCents),
      );

      expect(items[0].totalReturnedCents, 15000);
      expect(items[1].totalReturnedCents, 5000);
      expect(items[2].totalReturnedCents, 3000);
    });

    test('sort by return count ascending works', () {
      final items = [
        const CustomerReturnSummary(
          customerId: 1,
          customerName: 'A',
          segment: 'retail',
          returnCount: 5,
          totalReturnedCents: 5000,
          totalItemsReturned: 3,
        ),
        const CustomerReturnSummary(
          customerId: 2,
          customerName: 'B',
          segment: 'retail',
          returnCount: 1,
          totalReturnedCents: 15000,
          totalItemsReturned: 10,
        ),
        const CustomerReturnSummary(
          customerId: 3,
          customerName: 'C',
          segment: 'retail',
          returnCount: 3,
          totalReturnedCents: 3000,
          totalItemsReturned: 1,
        ),
      ];

      items.sort((a, b) => a.returnCount.compareTo(b.returnCount));

      expect(items[0].returnCount, 1);
      expect(items[1].returnCount, 3);
      expect(items[2].returnCount, 5);
    });
  });

  group('ReportDateRange for customer returns', () {
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

  group('Money calculations verification (integer cents)', () {
    test('total returns aggregation uses integer cents', () {
      const summaries = [
        CustomerReturnSummary(
          customerId: 1,
          customerName: 'A',
          segment: 'retail',
          returnCount: 3,
          totalReturnedCents: 15050,
          totalItemsReturned: 5,
        ),
        CustomerReturnSummary(
          customerId: 2,
          customerName: 'B',
          segment: 'wholesale',
          returnCount: 2,
          totalReturnedCents: 25075,
          totalItemsReturned: 4,
        ),
        CustomerReturnSummary(
          customerId: 3,
          customerName: 'C',
          segment: 'premium',
          returnCount: 1,
          totalReturnedCents: 9999,
          totalItemsReturned: 1,
        ),
      ];

      int totalCents = 0;
      int totalCount = 0;
      int totalItems = 0;
      for (final s in summaries) {
        totalCents += s.totalReturnedCents;
        totalCount += s.returnCount;
        totalItems += s.totalItemsReturned;
      }

      // Verify exact integer arithmetic - no floating point errors
      expect(totalCents, 50124); // 15050 + 25075 + 9999
      expect(totalCount, 6); // 3 + 2 + 1
      expect(totalItems, 10); // 5 + 4 + 1
    });

    test('average return uses integer division (no floating point)', () {
      const item = CustomerReturnSummary(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        returnCount: 7,
        totalReturnedCents: 10000,
        totalItemsReturned: 14,
      );

      // 10000 ~/ 7 = 1428 (integer division, not 1428.57)
      expect(item.averageReturnCents, 1428);
      expect(item.averageReturnCents, isA<int>());
    });

    test('reason breakdown totals match individual items', () {
      const reasons = [
        ReturnReasonBreakdown(reason: 'defective', count: 5, totalCents: 12500),
        ReturnReasonBreakdown(reason: 'wrong_size', count: 3, totalCents: 7500),
        ReturnReasonBreakdown(
          reason: 'changed_mind',
          count: 2,
          totalCents: 5000,
        ),
      ];

      int grandTotalCount = 0;
      int grandTotalCents = 0;
      for (final r in reasons) {
        grandTotalCount += r.count;
        grandTotalCents += r.totalCents;
      }

      expect(grandTotalCount, 10);
      expect(grandTotalCents, 25000);
    });

    test('percentage calculation from reason breakdown', () {
      const reasons = [
        ReturnReasonBreakdown(reason: 'defective', count: 5, totalCents: 12500),
        ReturnReasonBreakdown(reason: 'wrong_size', count: 3, totalCents: 7500),
        ReturnReasonBreakdown(
          reason: 'changed_mind',
          count: 2,
          totalCents: 5000,
        ),
      ];

      int grandTotalCount = 0;
      for (final r in reasons) {
        grandTotalCount += r.count;
      }

      // Verify percentage calculations
      final defectivePct = reasons[0].count / grandTotalCount * 100;
      final wrongSizePct = reasons[1].count / grandTotalCount * 100;
      final changedMindPct = reasons[2].count / grandTotalCount * 100;

      expect(defectivePct, 50.0);
      expect(wrongSizePct, 30.0);
      expect(changedMindPct, 20.0);
      // Percentages should sum to 100
      expect(defectivePct + wrongSizePct + changedMindPct, 100.0);
    });
  });

  group('Return detail item fields', () {
    test('all disposition types are valid strings', () {
      const validTypes = [
        'restock',
        'write_off',
        'exchange',
        'store_credit',
        'refund',
      ];
      for (final type in validTypes) {
        final item = ReturnDetailItem(
          returnId: 1,
          returnNumber: 'RET-001',
          returnDate: DateTime(2026, 1, 1),
          status: 'posted',
          dispositionType: type,
          refundMethod: 'cash',
          totalCents: 1000,
          itemCount: 1,
        );
        expect(validTypes, contains(item.dispositionType));
      }
    });

    test('all refund methods are valid strings', () {
      const validMethods = ['cash', 'credit', 'cheque'];
      for (final method in validMethods) {
        final item = ReturnDetailItem(
          returnId: 1,
          returnNumber: 'RET-001',
          returnDate: DateTime(2026, 1, 1),
          status: 'posted',
          dispositionType: 'restock',
          refundMethod: method,
          totalCents: 1000,
          itemCount: 1,
        );
        expect(validMethods, contains(item.refundMethod));
      }
    });

    test('all reason types are valid strings', () {
      const validReasons = [
        'wrong_size',
        'defective',
        'wrong_item',
        'changed_mind',
        'other',
      ];
      for (final reason in validReasons) {
        final item = ReturnDetailItem(
          returnId: 1,
          returnNumber: 'RET-001',
          returnDate: DateTime(2026, 1, 1),
          status: 'posted',
          dispositionType: 'restock',
          refundMethod: 'cash',
          reason: reason,
          totalCents: 1000,
          itemCount: 1,
        );
        expect(validReasons, contains(item.reason));
      }
    });
  });

  group('ReturnedProductItem data model', () {
    test('stores correct values', () {
      const item = ReturnedProductItem(
        returnId: 5,
        productName: 'Blue T-Shirt',
        sku: 'TS-BLU-M',
        colorName: 'Blue',
        sizeName: 'M',
        quantity: 2,
        refundCents: 6000,
        reason: 'wrong_size',
      );

      expect(item.returnId, 5);
      expect(item.productName, 'Blue T-Shirt');
      expect(item.sku, 'TS-BLU-M');
      expect(item.colorName, 'Blue');
      expect(item.sizeName, 'M');
      expect(item.quantity, 2);
      expect(item.refundCents, 6000);
      expect(item.reason, 'wrong_size');
    });

    test('nullable fields default to null', () {
      const item = ReturnedProductItem(
        returnId: 1,
        productName: 'Generic Product',
        quantity: 1,
        refundCents: 1000,
      );

      expect(item.sku, isNull);
      expect(item.colorName, isNull);
      expect(item.sizeName, isNull);
      expect(item.reason, isNull);
    });

    test('refundCents uses integer cents', () {
      const item = ReturnedProductItem(
        returnId: 1,
        productName: 'Test',
        quantity: 3,
        refundCents: 15075,
      );

      expect(item.refundCents, 15075);
      expect(item.refundCents, isA<int>());
    });
  });

  group('CustomerSalesReturnsData with returnedProducts', () {
    test('default returnedProducts is empty', () {
      final data = CustomerSalesReturnsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.returnedProducts, isEmpty);
    });

    test('copyWith preserves returnedProducts when not specified', () {
      final original = CustomerSalesReturnsData(
        dateRange: ReportDateRange.thisMonth(),
        returnedProducts: const [
          ReturnedProductItem(
            returnId: 1,
            productName: 'Test',
            quantity: 1,
            refundCents: 1000,
          ),
        ],
      );

      final updated = original.copyWith(totalReturnsCents: 5000);
      expect(updated.returnedProducts.length, 1);
      expect(updated.returnedProducts[0].productName, 'Test');
    });

    test('copyWith updates returnedProducts', () {
      final original = CustomerSalesReturnsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        returnedProducts: const [
          ReturnedProductItem(
            returnId: 1,
            productName: 'Product A',
            quantity: 2,
            refundCents: 4000,
          ),
          ReturnedProductItem(
            returnId: 1,
            productName: 'Product B',
            sku: 'SKU-B',
            quantity: 1,
            refundCents: 2000,
          ),
        ],
      );

      expect(updated.returnedProducts.length, 2);
      expect(updated.returnedProducts[1].sku, 'SKU-B');
    });
  });
}
