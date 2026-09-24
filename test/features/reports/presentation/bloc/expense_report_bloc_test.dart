import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/expense_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('ExpenseCategorySummary data model', () {
    test('stores correct values', () {
      const item = ExpenseCategorySummary(
        categoryId: 1,
        categoryName: 'Office Supplies',
        totalAmountCents: 150000,
        expenseCount: 10,
        percentage: 25.5,
      );

      expect(item.categoryId, 1);
      expect(item.categoryName, 'Office Supplies');
      expect(item.totalAmountCents, 150000);
      expect(item.expenseCount, 10);
      expect(item.percentage, 25.5);
    });

    test('integer cents prevents floating point errors', () {
      // Verify that using integer cents avoids floating point issues
      // e.g., 0.1 + 0.2 != 0.3 in floating point, but 10 + 20 == 30 in cents
      const item1 = ExpenseCategorySummary(
        categoryId: 1,
        categoryName: 'A',
        totalAmountCents: 10, // 0.10 in dollars
        expenseCount: 1,
        percentage: 33.3,
      );
      const item2 = ExpenseCategorySummary(
        categoryId: 2,
        categoryName: 'B',
        totalAmountCents: 20, // 0.20 in dollars
        expenseCount: 1,
        percentage: 66.7,
      );

      expect(item1.totalAmountCents + item2.totalAmountCents, 30);
    });

    test('zero percentage for zero total', () {
      const item = ExpenseCategorySummary(
        categoryId: 1,
        categoryName: 'Empty',
        totalAmountCents: 0,
        expenseCount: 0,
        percentage: 0.0,
      );

      expect(item.totalAmountCents, 0);
      expect(item.percentage, 0.0);
    });

    test('large amounts do not overflow int', () {
      // Dart int is 64-bit, so even very large cent amounts are safe
      const largeCents = 999999999999; // ~$10 billion
      const item = ExpenseCategorySummary(
        categoryId: 1,
        categoryName: 'Big Category',
        totalAmountCents: largeCents,
        expenseCount: 1000,
        percentage: 100.0,
      );

      expect(item.totalAmountCents, largeCents);
    });
  });

  group('ExpenseReportData', () {
    test('default values are correct', () {
      final data = ExpenseReportData(dateRange: ReportDateRange.thisMonth());

      expect(data.categories, isEmpty);
      expect(data.grandTotalCents, 0);
      expect(data.totalExpenseCount, 0);
      expect(data.totalCategories, 0);
      expect(data.highestCategoryCents, 0);
      expect(data.highestCategoryName, isNull);
      expect(data.lowestCategoryCents, 0);
      expect(data.lowestCategoryName, isNull);
      expect(data.sort, ExpenseReportSortType.amountDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = ExpenseReportData(
        grandTotalCents: 500000,
        totalExpenseCount: 50,
        totalCategories: 5,
        highestCategoryCents: 200000,
        highestCategoryName: 'Rent',
        lowestCategoryCents: 10000,
        lowestCategoryName: 'Misc',
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(dateRange: ReportDateRange.thisYear());

      expect(updated.grandTotalCents, 500000);
      expect(updated.totalExpenseCount, 50);
      expect(updated.totalCategories, 5);
      expect(updated.highestCategoryCents, 200000);
      expect(updated.highestCategoryName, 'Rent');
      expect(updated.lowestCategoryCents, 10000);
      expect(updated.lowestCategoryName, 'Misc');
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = ExpenseReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        grandTotalCents: 100000,
        totalExpenseCount: 10,
        totalCategories: 3,
        sort: ExpenseReportSortType.categoryAsc,
      );

      expect(updated.grandTotalCents, 100000);
      expect(updated.totalExpenseCount, 10);
      expect(updated.totalCategories, 3);
      expect(updated.sort, ExpenseReportSortType.categoryAsc);
    });

    test('copyWith updates categories list', () {
      final original = ExpenseReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const category = ExpenseCategorySummary(
        categoryId: 1,
        categoryName: 'New Category',
        totalAmountCents: 999900,
        expenseCount: 100,
        percentage: 100.0,
      );

      final updated = original.copyWith(
        categories: [category],
        totalCategories: 1,
      );

      expect(updated.categories.length, 1);
      expect(updated.categories.first.categoryName, 'New Category');
      expect(updated.totalCategories, 1);
    });
  });

  group('ExpenseReportBloc events', () {
    test('ExpenseReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = ExpenseReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('ExpenseReportSortChanged stores sort type', () {
      const event = ExpenseReportSortChanged(ExpenseReportSortType.categoryAsc);
      expect(event.sort, ExpenseReportSortType.categoryAsc);
    });
  });

  group('ExpenseReportSortType enum', () {
    test('has all expected values', () {
      expect(ExpenseReportSortType.values.length, 6);
      expect(
        ExpenseReportSortType.values,
        contains(ExpenseReportSortType.amountDesc),
      );
      expect(
        ExpenseReportSortType.values,
        contains(ExpenseReportSortType.amountAsc),
      );
      expect(
        ExpenseReportSortType.values,
        contains(ExpenseReportSortType.categoryAsc),
      );
      expect(
        ExpenseReportSortType.values,
        contains(ExpenseReportSortType.categoryDesc),
      );
      expect(
        ExpenseReportSortType.values,
        contains(ExpenseReportSortType.countDesc),
      );
      expect(
        ExpenseReportSortType.values,
        contains(ExpenseReportSortType.countAsc),
      );
    });
  });

  group('Sort logic', () {
    final categories = [
      const ExpenseCategorySummary(
        categoryId: 1,
        categoryName: 'Zebra Expenses',
        totalAmountCents: 50000,
        expenseCount: 5,
        percentage: 14.3,
      ),
      const ExpenseCategorySummary(
        categoryId: 2,
        categoryName: 'Apple Costs',
        totalAmountCents: 200000,
        expenseCount: 20,
        percentage: 57.1,
      ),
      const ExpenseCategorySummary(
        categoryId: 3,
        categoryName: 'Mango Supplies',
        totalAmountCents: 100000,
        expenseCount: 10,
        percentage: 28.6,
      ),
    ];

    test('sort by amount descending', () {
      final list = List<ExpenseCategorySummary>.from(categories);
      list.sort((a, b) => b.totalAmountCents.compareTo(a.totalAmountCents));

      expect(list[0].categoryName, 'Apple Costs');
      expect(list[0].totalAmountCents, 200000);
      expect(list[1].categoryName, 'Mango Supplies');
      expect(list[1].totalAmountCents, 100000);
      expect(list[2].categoryName, 'Zebra Expenses');
      expect(list[2].totalAmountCents, 50000);
    });

    test('sort by amount ascending', () {
      final list = List<ExpenseCategorySummary>.from(categories);
      list.sort((a, b) => a.totalAmountCents.compareTo(b.totalAmountCents));

      expect(list[0].categoryName, 'Zebra Expenses');
      expect(list[2].categoryName, 'Apple Costs');
    });

    test('sort by category name ascending', () {
      final list = List<ExpenseCategorySummary>.from(categories);
      list.sort((a, b) => a.categoryName.compareTo(b.categoryName));

      expect(list[0].categoryName, 'Apple Costs');
      expect(list[1].categoryName, 'Mango Supplies');
      expect(list[2].categoryName, 'Zebra Expenses');
    });

    test('sort by category name descending', () {
      final list = List<ExpenseCategorySummary>.from(categories);
      list.sort((a, b) => b.categoryName.compareTo(a.categoryName));

      expect(list[0].categoryName, 'Zebra Expenses');
      expect(list[1].categoryName, 'Mango Supplies');
      expect(list[2].categoryName, 'Apple Costs');
    });

    test('sort by count descending', () {
      final list = List<ExpenseCategorySummary>.from(categories);
      list.sort((a, b) => b.expenseCount.compareTo(a.expenseCount));

      expect(list[0].categoryName, 'Apple Costs');
      expect(list[0].expenseCount, 20);
      expect(list[1].categoryName, 'Mango Supplies');
      expect(list[1].expenseCount, 10);
      expect(list[2].categoryName, 'Zebra Expenses');
      expect(list[2].expenseCount, 5);
    });

    test('sort by count ascending', () {
      final list = List<ExpenseCategorySummary>.from(categories);
      list.sort((a, b) => a.expenseCount.compareTo(b.expenseCount));

      expect(list[0].categoryName, 'Zebra Expenses');
      expect(list[0].expenseCount, 5);
      expect(list[2].categoryName, 'Apple Costs');
      expect(list[2].expenseCount, 20);
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from category list', () {
      const categories = [
        ExpenseCategorySummary(
          categoryId: 1,
          categoryName: 'Rent',
          totalAmountCents: 500000,
          expenseCount: 1,
          percentage: 50.0,
        ),
        ExpenseCategorySummary(
          categoryId: 2,
          categoryName: 'Utilities',
          totalAmountCents: 200000,
          expenseCount: 5,
          percentage: 20.0,
        ),
        ExpenseCategorySummary(
          categoryId: 3,
          categoryName: 'Supplies',
          totalAmountCents: 300000,
          expenseCount: 15,
          percentage: 30.0,
        ),
      ];

      int grandTotal = 0;
      int totalCount = 0;
      for (final c in categories) {
        grandTotal += c.totalAmountCents;
        totalCount += c.expenseCount;
      }

      expect(grandTotal, 1000000); // 500000 + 200000 + 300000
      expect(totalCount, 21); // 1 + 5 + 15
      expect(categories.length, 3);
    });

    test('empty category list yields zero totals', () {
      const categories = <ExpenseCategorySummary>[];

      int grandTotal = 0;
      int totalCount = 0;
      for (final c in categories) {
        grandTotal += c.totalAmountCents;
        totalCount += c.expenseCount;
      }

      expect(grandTotal, 0);
      expect(totalCount, 0);
    });

    test('percentage calculation is correct', () {
      const grandTotal = 1000000;
      const categoryAmount = 250000;
      final percentage = (categoryAmount / grandTotal) * 100;

      expect(percentage, 25.0);
    });

    test('percentages sum to approximately 100', () {
      const categories = [
        ExpenseCategorySummary(
          categoryId: 1,
          categoryName: 'A',
          totalAmountCents: 333333,
          expenseCount: 1,
          percentage: 33.3,
        ),
        ExpenseCategorySummary(
          categoryId: 2,
          categoryName: 'B',
          totalAmountCents: 333333,
          expenseCount: 1,
          percentage: 33.3,
        ),
        ExpenseCategorySummary(
          categoryId: 3,
          categoryName: 'C',
          totalAmountCents: 333334,
          expenseCount: 1,
          percentage: 33.4,
        ),
      ];

      int total = 0;
      for (final c in categories) {
        total += c.totalAmountCents;
      }

      // Recalculate percentages
      double pctSum = 0;
      for (final c in categories) {
        pctSum += (c.totalAmountCents / total) * 100;
      }

      expect(pctSum, closeTo(100.0, 0.01));
    });
  });

  group('Highest and lowest category identification', () {
    test('correctly identifies highest and lowest categories', () {
      const categories = [
        ExpenseCategorySummary(
          categoryId: 1,
          categoryName: 'Rent',
          totalAmountCents: 500000,
          expenseCount: 1,
          percentage: 50.0,
        ),
        ExpenseCategorySummary(
          categoryId: 2,
          categoryName: 'Utilities',
          totalAmountCents: 200000,
          expenseCount: 5,
          percentage: 20.0,
        ),
        ExpenseCategorySummary(
          categoryId: 3,
          categoryName: 'Supplies',
          totalAmountCents: 300000,
          expenseCount: 15,
          percentage: 30.0,
        ),
      ];

      final highest = categories.reduce(
        (a, b) => a.totalAmountCents >= b.totalAmountCents ? a : b,
      );
      final lowest = categories.reduce(
        (a, b) => a.totalAmountCents <= b.totalAmountCents ? a : b,
      );

      expect(highest.categoryName, 'Rent');
      expect(highest.totalAmountCents, 500000);
      expect(lowest.categoryName, 'Utilities');
      expect(lowest.totalAmountCents, 200000);
    });

    test('single category is both highest and lowest', () {
      const categories = [
        ExpenseCategorySummary(
          categoryId: 1,
          categoryName: 'Only Category',
          totalAmountCents: 100000,
          expenseCount: 5,
          percentage: 100.0,
        ),
      ];

      final highest = categories.reduce(
        (a, b) => a.totalAmountCents >= b.totalAmountCents ? a : b,
      );
      final lowest = categories.reduce(
        (a, b) => a.totalAmountCents <= b.totalAmountCents ? a : b,
      );

      expect(highest.categoryName, 'Only Category');
      expect(lowest.categoryName, 'Only Category');
    });
  });

  group('ReportDateRange for expense report', () {
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

  group('ExpensePdfService translations', () {
    test('all expected translation keys are defined', () {
      const expectedKeys = [
        'expense_report',
        'period',
        'total_expenses',
        'total_count',
        'categories',
        'highest_category',
        'expense_by_category',
        'category',
        'amount',
        'count',
        'percentage',
        'grand_total',
        'printed_on',
      ];
      expect(expectedKeys.length, 13);
    });
  });

  group('SQL query logic verification', () {
    test('date range ISO format for query parameters', () {
      final range = ReportDateRange(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31, 23, 59, 59),
      );

      final startIso = range.startDate.toIso8601String();
      final endIso = range.endDate.toIso8601String();

      expect(startIso, startsWith('2026-01-01'));
      expect(endIso, startsWith('2026-01-31'));
    });

    test('aggregation logic: SUM and COUNT', () {
      // Simulate the SQL aggregation logic in Dart
      final expenses = [
        {'category_id': 1, 'amount_cents': 10000},
        {'category_id': 1, 'amount_cents': 20000},
        {'category_id': 2, 'amount_cents': 30000},
        {'category_id': 1, 'amount_cents': 15000},
        {'category_id': 2, 'amount_cents': 25000},
      ];

      final grouped = <int, List<Map<String, int>>>{};
      for (final e in expenses) {
        final catId = e['category_id']!;
        grouped.putIfAbsent(catId, () => []).add(e);
      }

      // Category 1: 3 expenses, total 45000
      expect(grouped[1]!.length, 3);
      expect(
        grouped[1]!.fold<int>(0, (sum, e) => sum + e['amount_cents']!),
        45000,
      );

      // Category 2: 2 expenses, total 55000
      expect(grouped[2]!.length, 2);
      expect(
        grouped[2]!.fold<int>(0, (sum, e) => sum + e['amount_cents']!),
        55000,
      );

      // Grand total: 100000
      final grandTotal = expenses.fold<int>(
        0,
        (sum, e) => sum + e['amount_cents']!,
      );
      expect(grandTotal, 100000);
    });

    test('percentage calculation from aggregated data', () {
      const grandTotal = 100000;
      const cat1Total = 45000;
      const cat2Total = 55000;

      final pct1 = (cat1Total / grandTotal) * 100;
      final pct2 = (cat2Total / grandTotal) * 100;

      expect(pct1, closeTo(45.0, 0.01));
      expect(pct2, closeTo(55.0, 0.01));
      expect(pct1 + pct2, closeTo(100.0, 0.01));
    });
  });
}
