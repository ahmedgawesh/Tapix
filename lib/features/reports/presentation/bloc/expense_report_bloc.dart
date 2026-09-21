import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class ExpenseReportEvent extends RealtimeEvent {
  const ExpenseReportEvent();
}

class ExpenseReportDateRangeChanged extends ExpenseReportEvent {
  final ReportDateRange dateRange;
  const ExpenseReportDateRangeChanged(this.dateRange);
}

class ExpenseReportSortChanged extends ExpenseReportEvent {
  final ExpenseReportSortType sort;
  const ExpenseReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum ExpenseReportSortType {
  amountDesc,
  amountAsc,
  categoryAsc,
  categoryDesc,
  countDesc,
  countAsc,
}

// ==================== DATA MODELS ====================

class ExpenseCategorySummary {
  final int categoryId;
  final String categoryName;
  final int totalAmountCents;
  final int expenseCount;
  final double percentage;

  const ExpenseCategorySummary({
    required this.categoryId,
    required this.categoryName,
    required this.totalAmountCents,
    required this.expenseCount,
    required this.percentage,
  });
}

class ExpenseReportData {
  final List<ExpenseCategorySummary> categories;
  final int grandTotalCents;
  final int totalExpenseCount;
  final int totalCategories;
  final int highestCategoryCents;
  final String? highestCategoryName;
  final int lowestCategoryCents;
  final String? lowestCategoryName;
  final ReportDateRange dateRange;
  final ExpenseReportSortType sort;

  const ExpenseReportData({
    this.categories = const [],
    this.grandTotalCents = 0,
    this.totalExpenseCount = 0,
    this.totalCategories = 0,
    this.highestCategoryCents = 0,
    this.highestCategoryName,
    this.lowestCategoryCents = 0,
    this.lowestCategoryName,
    required this.dateRange,
    this.sort = ExpenseReportSortType.amountDesc,
  });

  ExpenseReportData copyWith({
    List<ExpenseCategorySummary>? categories,
    int? grandTotalCents,
    int? totalExpenseCount,
    int? totalCategories,
    int? highestCategoryCents,
    String? highestCategoryName,
    int? lowestCategoryCents,
    String? lowestCategoryName,
    ReportDateRange? dateRange,
    ExpenseReportSortType? sort,
  }) {
    return ExpenseReportData(
      categories: categories ?? this.categories,
      grandTotalCents: grandTotalCents ?? this.grandTotalCents,
      totalExpenseCount: totalExpenseCount ?? this.totalExpenseCount,
      totalCategories: totalCategories ?? this.totalCategories,
      highestCategoryCents: highestCategoryCents ?? this.highestCategoryCents,
      highestCategoryName: highestCategoryName ?? this.highestCategoryName,
      lowestCategoryCents: lowestCategoryCents ?? this.lowestCategoryCents,
      lowestCategoryName: lowestCategoryName ?? this.lowestCategoryName,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class ExpenseReportBloc
    extends RealtimeBloc<ExpenseReportData, ExpenseReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  ExpenseReportSortType _sort = ExpenseReportSortType.amountDesc;

  ExpenseReportBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<ExpenseReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<ExpenseReportDateRangeChanged>(_onDateRangeChanged);
    on<ExpenseReportSortChanged>(_onSortChanged);
  }

  Stream<ExpenseReportData> _buildCombinedStream() {
    // Watch expenses table for real-time changes.
    // Drift table-level watches don't support WHERE clauses, so we watch
    // ALL expenses and re-query with the current date range in asyncMap.
    return _db.select(_db.expenses).watch().asyncMap((_) async {
      final items = await _loadExpenseSummaries();

      int grandTotal = 0;
      int totalCount = 0;
      int highestCents = 0;
      String? highestName;
      int lowestCents = 0;
      String? lowestName;

      for (final item in items) {
        grandTotal += item.totalAmountCents;
        totalCount += item.expenseCount;
      }

      if (items.isNotEmpty) {
        final highest = items.reduce(
          (a, b) => a.totalAmountCents >= b.totalAmountCents ? a : b,
        );
        highestCents = highest.totalAmountCents;
        highestName = highest.categoryName;

        final lowest = items.reduce(
          (a, b) => a.totalAmountCents <= b.totalAmountCents ? a : b,
        );
        lowestCents = lowest.totalAmountCents;
        lowestName = lowest.categoryName;
      }

      // Calculate percentages
      final withPercentages = items.map((item) {
        final pct = grandTotal > 0
            ? (item.totalAmountCents / grandTotal) * 100
            : 0.0;
        return ExpenseCategorySummary(
          categoryId: item.categoryId,
          categoryName: item.categoryName,
          totalAmountCents: item.totalAmountCents,
          expenseCount: item.expenseCount,
          percentage: pct,
        );
      }).toList();

      final sorted = _applySortToCategories(withPercentages, _sort);

      return ExpenseReportData(
        categories: sorted,
        grandTotalCents: grandTotal,
        totalExpenseCount: totalCount,
        totalCategories: items.length,
        highestCategoryCents: highestCents,
        highestCategoryName: highestName,
        lowestCategoryCents: lowestCents,
        lowestCategoryName: lowestName,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    ExpenseReportDateRangeChanged event,
    Emitter<RealtimeState<ExpenseReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    ExpenseReportSortChanged event,
    Emitter<RealtimeState<ExpenseReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToCategories(current.categories, event.sort);
      emit(
        RealtimeSuccess<ExpenseReportData>(
          data: current.copyWith(categories: sorted, sort: event.sort),
        ),
      );
    }
  }

  List<ExpenseCategorySummary> _applySortToCategories(
    List<ExpenseCategorySummary> items,
    ExpenseReportSortType sort,
  ) {
    final list = List<ExpenseCategorySummary>.from(items);
    switch (sort) {
      case ExpenseReportSortType.amountDesc:
        list.sort((a, b) => b.totalAmountCents.compareTo(a.totalAmountCents));
      case ExpenseReportSortType.amountAsc:
        list.sort((a, b) => a.totalAmountCents.compareTo(b.totalAmountCents));
      case ExpenseReportSortType.categoryAsc:
        list.sort((a, b) => a.categoryName.compareTo(b.categoryName));
      case ExpenseReportSortType.categoryDesc:
        list.sort((a, b) => b.categoryName.compareTo(a.categoryName));
      case ExpenseReportSortType.countDesc:
        list.sort((a, b) => b.expenseCount.compareTo(a.expenseCount));
      case ExpenseReportSortType.countAsc:
        list.sort((a, b) => a.expenseCount.compareTo(b.expenseCount));
    }
    return list;
  }

  /// Loads expense summaries grouped by category within the date range.
  ///
  /// Aggregation logic:
  /// - Groups expenses by category_id
  /// - SUM(amount_cents) per category for total spending
  /// - COUNT(*) per category for expense count
  /// - JOIN with expense_categories for category names
  /// - Filters by expense_date within the selected date range
  Future<List<ExpenseCategorySummary>> _loadExpenseSummaries() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT 
        ec.id AS category_id,
        ec.name AS category_name,
        COALESCE(SUM(e.amount_cents), 0) AS total_amount_cents,
        COUNT(e.id) AS expense_count
      FROM expense_categories ec
      INNER JOIN expenses e ON e.category_id = ec.id
      WHERE e.expense_date >= ?
        AND e.expense_date <= ?
      GROUP BY ec.id
      HAVING expense_count > 0
      ORDER BY total_amount_cents DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.expenses, _db.expenseCategories},
        )
        .get();

    return rows.map((row) {
      return ExpenseCategorySummary(
        categoryId: row.read<int>('category_id'),
        categoryName: row.read<String>('category_name'),
        totalAmountCents: row.read<int>('total_amount_cents'),
        expenseCount: row.read<int>('expense_count'),
        percentage: 0, // Will be calculated after totals are known
      );
    }).toList();
  }
}
