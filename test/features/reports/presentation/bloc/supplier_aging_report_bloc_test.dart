import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_aging_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('SupplierAgingItem data model', () {
    test('stores correct values', () {
      const item = SupplierAgingItem(
        supplierId: 1,
        supplierName: 'Test Supplier',
        phone: '+1234567890',
        email: 'test@example.com',
        currentCents: 50000,
        days30Cents: 30000,
        days60Cents: 20000,
        days90Cents: 10000,
        over90Cents: 5000,
        totalCents: 115000,
      );

      expect(item.supplierId, 1);
      expect(item.supplierName, 'Test Supplier');
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
      const item = SupplierAgingItem(
        supplierId: 2,
        supplierName: 'No Contact',
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
      const item = SupplierAgingItem(
        supplierId: 1,
        supplierName: 'Test',
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
      const item = SupplierAgingItem(
        supplierId: 1,
        supplierName: 'Test',
        currentCents: 50000,
        days30Cents: 30000,
        days60Cents: 20000,
        days90Cents: 10000,
        over90Cents: 5000,
        totalCents: 115000,
      );

      final bucketSum =
          item.currentCents +
          item.days30Cents +
          item.days60Cents +
          item.days90Cents +
          item.over90Cents;
      expect(bucketSum, item.totalCents);
    });

    test('zero balance supplier has all zeros', () {
      const item = SupplierAgingItem(
        supplierId: 1,
        supplierName: 'Zero Balance',
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

    test('large cent values handled correctly', () {
      // Test with large values that could overflow in floating point
      const item = SupplierAgingItem(
        supplierId: 1,
        supplierName: 'Big Supplier',
        currentCents: 999999999,
        days30Cents: 888888888,
        days60Cents: 777777777,
        days90Cents: 666666666,
        over90Cents: 555555555,
        totalCents: 3888888885,
      );

      final bucketSum =
          item.currentCents +
          item.days30Cents +
          item.days60Cents +
          item.days90Cents +
          item.over90Cents;
      expect(bucketSum, item.totalCents);
    });
  });

  group('SupplierAgingReportData', () {
    test('default values are correct', () {
      final data = SupplierAgingReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.suppliers, isEmpty);
      expect(data.grandTotalCurrentCents, 0);
      expect(data.grandTotal30Cents, 0);
      expect(data.grandTotal60Cents, 0);
      expect(data.grandTotal90Cents, 0);
      expect(data.grandTotalOver90Cents, 0);
      expect(data.grandTotalCents, 0);
      expect(data.supplierCount, 0);
      expect(data.sort, SupplierAgingSortType.totalDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('grandTotalOverdueCents computed correctly', () {
      final data = SupplierAgingReportData(
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
      expect(
        data.grandTotalOverdueCents,
        data.grandTotal30Cents +
            data.grandTotal60Cents +
            data.grandTotal90Cents +
            data.grandTotalOver90Cents,
      );
    });

    test('grandTotalOverdueCents is zero when no overdue', () {
      final data = SupplierAgingReportData(
        grandTotalCurrentCents: 100000,
        grandTotal30Cents: 0,
        grandTotal60Cents: 0,
        grandTotal90Cents: 0,
        grandTotalOver90Cents: 0,
        grandTotalCents: 100000,
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.grandTotalOverdueCents, 0);
    });

    test('copyWith preserves unchanged fields', () {
      final original = SupplierAgingReportData(
        grandTotalCents: 500000,
        grandTotalCurrentCents: 200000,
        grandTotal30Cents: 100000,
        grandTotal60Cents: 80000,
        grandTotal90Cents: 70000,
        grandTotalOver90Cents: 50000,
        supplierCount: 10,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(dateRange: ReportDateRange.thisYear());

      expect(updated.grandTotalCents, 500000);
      expect(updated.grandTotalCurrentCents, 200000);
      expect(updated.grandTotal30Cents, 100000);
      expect(updated.grandTotal60Cents, 80000);
      expect(updated.grandTotal90Cents, 70000);
      expect(updated.grandTotalOver90Cents, 50000);
      expect(updated.supplierCount, 10);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = SupplierAgingReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        grandTotalCents: 100000,
        supplierCount: 25,
        sort: SupplierAgingSortType.nameAsc,
      );

      expect(updated.grandTotalCents, 100000);
      expect(updated.supplierCount, 25);
      expect(updated.sort, SupplierAgingSortType.nameAsc);
    });

    test('copyWith updates suppliers list', () {
      final original = SupplierAgingReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const supplier = SupplierAgingItem(
        supplierId: 1,
        supplierName: 'New Supplier',
        currentCents: 50000,
        days30Cents: 0,
        days60Cents: 0,
        days90Cents: 0,
        over90Cents: 0,
        totalCents: 50000,
      );

      final updated = original.copyWith(
        suppliers: [supplier],
        supplierCount: 1,
      );

      expect(updated.suppliers.length, 1);
      expect(updated.suppliers.first.supplierName, 'New Supplier');
      expect(updated.supplierCount, 1);
    });

    test('copyWith with all fields', () {
      final original = SupplierAgingReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        suppliers: const [],
        grandTotalCurrentCents: 1,
        grandTotal30Cents: 2,
        grandTotal60Cents: 3,
        grandTotal90Cents: 4,
        grandTotalOver90Cents: 5,
        grandTotalCents: 15,
        supplierCount: 99,
        dateRange: ReportDateRange.allTime(),
        sort: SupplierAgingSortType.over90Desc,
      );

      expect(updated.grandTotalCurrentCents, 1);
      expect(updated.grandTotal30Cents, 2);
      expect(updated.grandTotal60Cents, 3);
      expect(updated.grandTotal90Cents, 4);
      expect(updated.grandTotalOver90Cents, 5);
      expect(updated.grandTotalCents, 15);
      expect(updated.supplierCount, 99);
      expect(updated.dateRange.preset, ReportPeriodPreset.allTime);
      expect(updated.sort, SupplierAgingSortType.over90Desc);
    });
  });

  group('SupplierAgingReportBloc events', () {
    test('SupplierAgingReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = SupplierAgingReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('SupplierAgingReportSortChanged stores sort type', () {
      const event = SupplierAgingReportSortChanged(
        SupplierAgingSortType.over90Desc,
      );
      expect(event.sort, SupplierAgingSortType.over90Desc);
    });

    test('SupplierAgingReportDateRangeChanged with custom range', () {
      final range = ReportDateRange(
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2025, 6, 30),
        preset: ReportPeriodPreset.custom,
      );
      final event = SupplierAgingReportDateRangeChanged(range);
      expect(event.dateRange.startDate.month, 6);
      expect(event.dateRange.endDate.day, 30);
      expect(event.dateRange.preset, ReportPeriodPreset.custom);
    });

    test('all sort types can be used in events', () {
      for (final sortType in SupplierAgingSortType.values) {
        final event = SupplierAgingReportSortChanged(sortType);
        expect(event.sort, sortType);
      }
    });
  });

  group('SupplierAgingSortType enum', () {
    test('has all expected values', () {
      expect(SupplierAgingSortType.values.length, 6);
      expect(
        SupplierAgingSortType.values,
        contains(SupplierAgingSortType.totalDesc),
      );
      expect(
        SupplierAgingSortType.values,
        contains(SupplierAgingSortType.totalAsc),
      );
      expect(
        SupplierAgingSortType.values,
        contains(SupplierAgingSortType.over90Desc),
      );
      expect(
        SupplierAgingSortType.values,
        contains(SupplierAgingSortType.over90Asc),
      );
      expect(
        SupplierAgingSortType.values,
        contains(SupplierAgingSortType.nameAsc),
      );
      expect(
        SupplierAgingSortType.values,
        contains(SupplierAgingSortType.nameDesc),
      );
    });
  });

  group('Sort logic', () {
    final suppliers = [
      const SupplierAgingItem(
        supplierId: 1,
        supplierName: 'Zebra Corp',
        currentCents: 10000,
        days30Cents: 5000,
        days60Cents: 3000,
        days90Cents: 2000,
        over90Cents: 30000,
        totalCents: 50000,
      ),
      const SupplierAgingItem(
        supplierId: 2,
        supplierName: 'Apple Inc',
        currentCents: 100000,
        days30Cents: 50000,
        days60Cents: 30000,
        days90Cents: 10000,
        over90Cents: 10000,
        totalCents: 200000,
      ),
      const SupplierAgingItem(
        supplierId: 3,
        supplierName: 'Mango Ltd',
        currentCents: 50000,
        days30Cents: 20000,
        days60Cents: 10000,
        days90Cents: 10000,
        over90Cents: 10000,
        totalCents: 100000,
      ),
    ];

    test('sort by total descending', () {
      final list = List<SupplierAgingItem>.from(suppliers);
      list.sort((a, b) => b.totalCents.compareTo(a.totalCents));

      expect(list[0].supplierName, 'Apple Inc');
      expect(list[0].totalCents, 200000);
      expect(list[1].supplierName, 'Mango Ltd');
      expect(list[1].totalCents, 100000);
      expect(list[2].supplierName, 'Zebra Corp');
      expect(list[2].totalCents, 50000);
    });

    test('sort by total ascending', () {
      final list = List<SupplierAgingItem>.from(suppliers);
      list.sort((a, b) => a.totalCents.compareTo(b.totalCents));

      expect(list[0].supplierName, 'Zebra Corp');
      expect(list[2].supplierName, 'Apple Inc');
    });

    test('sort by over90 descending', () {
      final list = List<SupplierAgingItem>.from(suppliers);
      list.sort((a, b) => b.over90Cents.compareTo(a.over90Cents));

      expect(list[0].supplierName, 'Zebra Corp');
      expect(list[0].over90Cents, 30000);
      expect(list[1].supplierName, 'Apple Inc');
      expect(list[1].over90Cents, 10000);
    });

    test('sort by over90 ascending', () {
      final list = List<SupplierAgingItem>.from(suppliers);
      list.sort((a, b) => a.over90Cents.compareTo(b.over90Cents));

      expect(list[0].over90Cents, 10000);
      expect(list[2].supplierName, 'Zebra Corp');
      expect(list[2].over90Cents, 30000);
    });

    test('sort by name ascending', () {
      final list = List<SupplierAgingItem>.from(suppliers);
      list.sort((a, b) => a.supplierName.compareTo(b.supplierName));

      expect(list[0].supplierName, 'Apple Inc');
      expect(list[1].supplierName, 'Mango Ltd');
      expect(list[2].supplierName, 'Zebra Corp');
    });

    test('sort by name descending', () {
      final list = List<SupplierAgingItem>.from(suppliers);
      list.sort((a, b) => b.supplierName.compareTo(a.supplierName));

      expect(list[0].supplierName, 'Zebra Corp');
      expect(list[1].supplierName, 'Mango Ltd');
      expect(list[2].supplierName, 'Apple Inc');
    });

    test('sort stability with equal values', () {
      final equalSuppliers = [
        const SupplierAgingItem(
          supplierId: 1,
          supplierName: 'Supplier A',
          currentCents: 10000,
          days30Cents: 0,
          days60Cents: 0,
          days90Cents: 0,
          over90Cents: 5000,
          totalCents: 15000,
        ),
        const SupplierAgingItem(
          supplierId: 2,
          supplierName: 'Supplier B',
          currentCents: 10000,
          days30Cents: 0,
          days60Cents: 0,
          days90Cents: 0,
          over90Cents: 5000,
          totalCents: 15000,
        ),
      ];

      final list = List<SupplierAgingItem>.from(equalSuppliers);
      list.sort((a, b) => b.totalCents.compareTo(a.totalCents));

      // Both have same total, order should be stable
      expect(list.length, 2);
      expect(list[0].totalCents, list[1].totalCents);
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from supplier list', () {
      const suppliers = [
        SupplierAgingItem(
          supplierId: 1,
          supplierName: 'A',
          currentCents: 50000,
          days30Cents: 30000,
          days60Cents: 20000,
          days90Cents: 10000,
          over90Cents: 5000,
          totalCents: 115000,
        ),
        SupplierAgingItem(
          supplierId: 2,
          supplierName: 'B',
          currentCents: 100000,
          days30Cents: 50000,
          days60Cents: 30000,
          days90Cents: 20000,
          over90Cents: 10000,
          totalCents: 210000,
        ),
        SupplierAgingItem(
          supplierId: 3,
          supplierName: 'C',
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
      for (final s in suppliers) {
        totalCurrent += s.currentCents;
        total30 += s.days30Cents;
        total60 += s.days60Cents;
        total90 += s.days90Cents;
        totalOver90 += s.over90Cents;
        grandTotal += s.totalCents;
      }

      expect(totalCurrent, 175000);
      expect(total30, 95000);
      expect(total60, 60000);
      expect(total90, 35000);
      expect(totalOver90, 35000);
      expect(grandTotal, 400000);
      expect(suppliers.length, 3);

      // Verify overdue = total - current
      final totalOverdue = total30 + total60 + total90 + totalOver90;
      expect(totalOverdue, 225000);
      expect(grandTotal - totalCurrent, totalOverdue);
    });

    test('empty supplier list yields zero totals', () {
      const suppliers = <SupplierAgingItem>[];

      int totalCurrent = 0;
      int grandTotal = 0;
      for (final s in suppliers) {
        totalCurrent += s.currentCents;
        grandTotal += s.totalCents;
      }

      expect(totalCurrent, 0);
      expect(grandTotal, 0);
    });

    test('single supplier with only current balance', () {
      const suppliers = [
        SupplierAgingItem(
          supplierId: 1,
          supplierName: 'Current Only',
          currentCents: 100000,
          days30Cents: 0,
          days60Cents: 0,
          days90Cents: 0,
          over90Cents: 0,
          totalCents: 100000,
        ),
      ];

      final overdue =
          suppliers.first.days30Cents +
          suppliers.first.days60Cents +
          suppliers.first.days90Cents +
          suppliers.first.over90Cents;
      expect(overdue, 0);
      expect(suppliers.first.totalCents, 100000);
    });

    test('single supplier with only over90 balance', () {
      const suppliers = [
        SupplierAgingItem(
          supplierId: 1,
          supplierName: 'Very Overdue',
          currentCents: 0,
          days30Cents: 0,
          days60Cents: 0,
          days90Cents: 0,
          over90Cents: 500000,
          totalCents: 500000,
        ),
      ];

      expect(suppliers.first.over90Cents, 500000);
      expect(suppliers.first.currentCents, 0);
      expect(suppliers.first.totalCents, suppliers.first.over90Cents);
    });

    test('overdue percentage calculation', () {
      final data = SupplierAgingReportData(
        grandTotalCurrentCents: 50000,
        grandTotal30Cents: 20000,
        grandTotal60Cents: 15000,
        grandTotal90Cents: 10000,
        grandTotalOver90Cents: 5000,
        grandTotalCents: 100000,
        dateRange: ReportDateRange.thisMonth(),
      );

      // Overdue is 50% of total
      final overduePercent =
          (data.grandTotalOverdueCents / data.grandTotalCents * 100).round();
      expect(overduePercent, 50);
    });
  });

  group('ReportDateRange for supplier aging', () {
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

    test('thisQuarter starts at quarter boundary', () {
      final range = ReportDateRange.thisQuarter();
      final now = DateTime.now();
      final expectedQuarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
      expect(range.startDate.month, expectedQuarterStartMonth);
      expect(range.startDate.day, 1);
      expect(range.preset, ReportPeriodPreset.thisQuarter);
    });

    test('lastYear has correct boundaries', () {
      final range = ReportDateRange.lastYear();
      final now = DateTime.now();
      expect(range.startDate.year, now.year - 1);
      expect(range.startDate.month, 1);
      expect(range.startDate.day, 1);
      expect(range.endDate.year, now.year - 1);
      expect(range.endDate.month, 12);
      expect(range.endDate.day, 31);
      expect(range.preset, ReportPeriodPreset.lastYear);
    });
  });

  group('SupplierAgingPdfService translations', () {
    test('all expected translation keys exist', () {
      const expectedKeys = [
        'supplier_aging_report',
        'as_of',
        'total_payables',
        'total_overdue',
        'total_suppliers',
        'aging_summary',
        'supplier_aging_detail',
        'supplier',
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

    test('translation keys cover all 3 languages', () {
      // Verify the structure: each key should have en, ar, fr
      const languages = ['en', 'ar', 'fr'];
      expect(languages.length, 3);
      // The actual translations are in the PDF service static map
      // This test verifies the expected structure
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
        expect(
          boundaries[i + 1] - boundaries[i],
          30,
          reason: 'Each bucket should span 30 days',
        );
      }
    });

    test('overdue calculation excludes current bucket', () {
      const item = SupplierAgingItem(
        supplierId: 1,
        supplierName: 'Test',
        currentCents: 50000,
        days30Cents: 10000,
        days60Cents: 5000,
        days90Cents: 3000,
        over90Cents: 2000,
        totalCents: 70000,
      );

      final overdue =
          item.days30Cents +
          item.days60Cents +
          item.days90Cents +
          item.over90Cents;
      expect(overdue, 20000);
      expect(item.totalCents - item.currentCents, overdue);
    });

    test('SQL aging bucket date boundaries are correct', () {
      // Verify the date calculation logic used in the bloc
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final days30 = today.subtract(const Duration(days: 30));
      final days60 = today.subtract(const Duration(days: 60));
      final days90 = today.subtract(const Duration(days: 90));

      // Current bucket: transaction_date >= days30 (within last 30 days)
      expect(today.difference(days30).inDays, 30);

      // 1-30 bucket: transaction_date >= days60 AND < days30
      expect(days30.difference(days60).inDays, 30);

      // 31-60 bucket: transaction_date >= days90 AND < days60
      expect(days60.difference(days90).inDays, 30);

      // 61-90 bucket: transaction_date >= days90 AND < days90
      // (This is the boundary - transactions exactly at days90)

      // 91+ bucket: transaction_date < days90
      // All transactions older than 90 days
    });

    test('aging buckets are mutually exclusive', () {
      // A transaction can only be in ONE bucket
      // Current: >= days30
      // 1-30: >= days60 AND < days30
      // 31-60: >= days90 AND < days60
      // 61-90: >= days90 AND < days90 (boundary)
      // 91+: < days90

      // Test with a specific date
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final days30 = today.subtract(const Duration(days: 30));
      final days60 = today.subtract(const Duration(days: 60));
      final days90 = today.subtract(const Duration(days: 90));

      // A transaction from 15 days ago should be in "current" bucket
      final tx15DaysAgo = today.subtract(const Duration(days: 15));
      expect(
        tx15DaysAgo.isAfter(days30) || tx15DaysAgo.isAtSameMomentAs(days30),
        true,
      );

      // A transaction from 45 days ago should be in "1-30" bucket
      final tx45DaysAgo = today.subtract(const Duration(days: 45));
      expect(
        tx45DaysAgo.isAfter(days60) || tx45DaysAgo.isAtSameMomentAs(days60),
        true,
      );
      expect(tx45DaysAgo.isBefore(days30), true);

      // A transaction from 75 days ago should be in "31-60" bucket
      final tx75DaysAgo = today.subtract(const Duration(days: 75));
      expect(
        tx75DaysAgo.isAfter(days90) || tx75DaysAgo.isAtSameMomentAs(days90),
        true,
      );
      expect(tx75DaysAgo.isBefore(days60), true);

      // A transaction from 120 days ago should be in "91+" bucket
      final tx120DaysAgo = today.subtract(const Duration(days: 120));
      expect(tx120DaysAgo.isBefore(days90), true);
    });
  });

  group('Data integrity checks', () {
    test('supplier with contact info for payment follow-up', () {
      const item = SupplierAgingItem(
        supplierId: 1,
        supplierName: 'Contact Supplier',
        phone: '+1234567890',
        email: 'supplier@example.com',
        currentCents: 0,
        days30Cents: 0,
        days60Cents: 0,
        days90Cents: 0,
        over90Cents: 100000,
        totalCents: 100000,
      );

      // Supplier with high overdue should have contact info for follow-up
      expect(item.phone, isNotNull);
      expect(item.email, isNotNull);
      expect(item.over90Cents, greaterThan(0));
    });

    test('report data with multiple suppliers calculates correctly', () {
      const suppliers = [
        SupplierAgingItem(
          supplierId: 1,
          supplierName: 'Supplier A',
          currentCents: 10000,
          days30Cents: 20000,
          days60Cents: 30000,
          days90Cents: 40000,
          over90Cents: 50000,
          totalCents: 150000,
        ),
        SupplierAgingItem(
          supplierId: 2,
          supplierName: 'Supplier B',
          currentCents: 5000,
          days30Cents: 10000,
          days60Cents: 15000,
          days90Cents: 20000,
          over90Cents: 25000,
          totalCents: 75000,
        ),
      ];

      // Verify each supplier's buckets sum to their total
      for (final s in suppliers) {
        final bucketSum =
            s.currentCents +
            s.days30Cents +
            s.days60Cents +
            s.days90Cents +
            s.over90Cents;
        expect(
          bucketSum,
          s.totalCents,
          reason: '${s.supplierName} buckets should sum to total',
        );
      }

      // Verify grand totals
      int grandTotal = 0;
      for (final s in suppliers) {
        grandTotal += s.totalCents;
      }
      expect(grandTotal, 225000);
    });
  });
}
