import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierAgingReportEvent extends RealtimeEvent {
  const SupplierAgingReportEvent();
}

class SupplierAgingReportDateRangeChanged extends SupplierAgingReportEvent {
  final ReportDateRange dateRange;
  const SupplierAgingReportDateRangeChanged(this.dateRange);
}

class SupplierAgingReportSortChanged extends SupplierAgingReportEvent {
  final SupplierAgingSortType sort;
  const SupplierAgingReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum SupplierAgingSortType {
  totalDesc,
  totalAsc,
  over90Desc,
  over90Asc,
  nameAsc,
  nameDesc,
}

// ==================== DATA MODELS ====================

class SupplierAgingItem {
  final int supplierId;
  final String supplierName;
  final String? phone;
  final String? email;
  final int currentCents;
  final int days30Cents;
  final int days60Cents;
  final int days90Cents;
  final int over90Cents;
  final int totalCents;

  const SupplierAgingItem({
    required this.supplierId,
    required this.supplierName,
    this.phone,
    this.email,
    required this.currentCents,
    required this.days30Cents,
    required this.days60Cents,
    required this.days90Cents,
    required this.over90Cents,
    required this.totalCents,
  });
}

class SupplierAgingReportData {
  final List<SupplierAgingItem> suppliers;
  final int grandTotalCurrentCents;
  final int grandTotal30Cents;
  final int grandTotal60Cents;
  final int grandTotal90Cents;
  final int grandTotalOver90Cents;
  final int grandTotalCents;
  final int supplierCount;
  final ReportDateRange dateRange;
  final SupplierAgingSortType sort;

  const SupplierAgingReportData({
    this.suppliers = const [],
    this.grandTotalCurrentCents = 0,
    this.grandTotal30Cents = 0,
    this.grandTotal60Cents = 0,
    this.grandTotal90Cents = 0,
    this.grandTotalOver90Cents = 0,
    this.grandTotalCents = 0,
    this.supplierCount = 0,
    required this.dateRange,
    this.sort = SupplierAgingSortType.totalDesc,
  });

  int get grandTotalOverdueCents =>
      grandTotal30Cents + grandTotal60Cents + grandTotal90Cents + grandTotalOver90Cents;

  SupplierAgingReportData copyWith({
    List<SupplierAgingItem>? suppliers,
    int? grandTotalCurrentCents,
    int? grandTotal30Cents,
    int? grandTotal60Cents,
    int? grandTotal90Cents,
    int? grandTotalOver90Cents,
    int? grandTotalCents,
    int? supplierCount,
    ReportDateRange? dateRange,
    SupplierAgingSortType? sort,
  }) {
    return SupplierAgingReportData(
      suppliers: suppliers ?? this.suppliers,
      grandTotalCurrentCents: grandTotalCurrentCents ?? this.grandTotalCurrentCents,
      grandTotal30Cents: grandTotal30Cents ?? this.grandTotal30Cents,
      grandTotal60Cents: grandTotal60Cents ?? this.grandTotal60Cents,
      grandTotal90Cents: grandTotal90Cents ?? this.grandTotal90Cents,
      grandTotalOver90Cents: grandTotalOver90Cents ?? this.grandTotalOver90Cents,
      grandTotalCents: grandTotalCents ?? this.grandTotalCents,
      supplierCount: supplierCount ?? this.supplierCount,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class SupplierAgingReportBloc
    extends RealtimeBloc<SupplierAgingReportData, SupplierAgingReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  SupplierAgingSortType _sort = SupplierAgingSortType.totalDesc;

  SupplierAgingReportBloc(this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<SupplierAgingReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SupplierAgingReportDateRangeChanged>(_onDateRangeChanged);
    on<SupplierAgingReportSortChanged>(_onSortChanged);
  }

  Stream<SupplierAgingReportData> _buildCombinedStream() {
    // Watch supplier_transactions for real-time changes.
    // Drift table-level watches don't support WHERE clauses, so we watch ALL
    // transactions and re-query with the current date range in asyncMap.
    return _db.select(_db.supplierTransactions).watch().asyncMap((_) async {
      final suppliers = await _loadAgingData();

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

      final sorted = _applySortToSuppliers(suppliers, _sort);

      return SupplierAgingReportData(
        suppliers: sorted,
        grandTotalCurrentCents: totalCurrent,
        grandTotal30Cents: total30,
        grandTotal60Cents: total60,
        grandTotal90Cents: total90,
        grandTotalOver90Cents: totalOver90,
        grandTotalCents: grandTotal,
        supplierCount: suppliers.length,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    SupplierAgingReportDateRangeChanged event,
    Emitter<RealtimeState<SupplierAgingReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    SupplierAgingReportSortChanged event,
    Emitter<RealtimeState<SupplierAgingReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToSuppliers(current.suppliers, event.sort);
      emit(RealtimeSuccess<SupplierAgingReportData>(
        data: current.copyWith(
          suppliers: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<SupplierAgingItem> _applySortToSuppliers(
    List<SupplierAgingItem> items,
    SupplierAgingSortType sort,
  ) {
    final list = List<SupplierAgingItem>.from(items);
    switch (sort) {
      case SupplierAgingSortType.totalDesc:
        list.sort((a, b) => b.totalCents.compareTo(a.totalCents));
      case SupplierAgingSortType.totalAsc:
        list.sort((a, b) => a.totalCents.compareTo(b.totalCents));
      case SupplierAgingSortType.over90Desc:
        list.sort((a, b) => b.over90Cents.compareTo(a.over90Cents));
      case SupplierAgingSortType.over90Asc:
        list.sort((a, b) => a.over90Cents.compareTo(b.over90Cents));
      case SupplierAgingSortType.nameAsc:
        list.sort((a, b) => a.supplierName.compareTo(b.supplierName));
      case SupplierAgingSortType.nameDesc:
        list.sort((a, b) => b.supplierName.compareTo(a.supplierName));
    }
    return list;
  }

  Future<List<SupplierAgingItem>> _loadAgingData() async {
    // Aging buckets are calculated relative to "now", not the date range.
    // The date range filters which transactions are included in the aging
    // calculation (only transactions up to the end date are considered).
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final days30 = today.subtract(const Duration(days: 30));
    final days60 = today.subtract(const Duration(days: 60));
    final days90 = today.subtract(const Duration(days: 90));

    // Use the date range end date as the cutoff for which transactions to include
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      -- Aging buckets based on days overdue (not transaction date)
      -- Current: 0 days overdue (not due yet)
      -- 1-30: 1-30 days overdue
      -- 31-60: 31-60 days overdue  
      -- 61-90: 61-90 days overdue
      -- 90+: 91+ days overdue
      SELECT 
        s.id AS supplier_id,
        s.name AS supplier_name,
        s.phone AS phone,
        s.email AS email,
        COALESCE(SUM(CASE WHEN st.transaction_date >= ? THEN st.amount_cents ELSE 0 END), 0) AS current_cents,
        COALESCE(SUM(CASE WHEN st.transaction_date >= ? AND st.transaction_date < ? THEN st.amount_cents ELSE 0 END), 0) AS days_30_cents,
        COALESCE(SUM(CASE WHEN st.transaction_date >= ? AND st.transaction_date < ? THEN st.amount_cents ELSE 0 END), 0) AS days_60_cents,
        COALESCE(SUM(CASE WHEN st.transaction_date >= ? AND st.transaction_date < ? THEN st.amount_cents ELSE 0 END), 0) AS days_90_cents,
        COALESCE(SUM(CASE WHEN st.transaction_date < ? THEN st.amount_cents ELSE 0 END), 0) AS over_90_cents,
        COALESCE(SUM(st.amount_cents), 0) AS total_cents
      FROM suppliers s
      LEFT JOIN supplier_transactions st ON st.supplier_id = s.id
        AND st.transaction_date <= ?
      WHERE s.is_active = 1
      GROUP BY s.id
      HAVING total_cents > 0
      ORDER BY total_cents DESC
      ''',
      variables: [
        Variable.withString(today.toIso8601String()),
        Variable.withString(days30.toIso8601String()),
        Variable.withString(today.toIso8601String()),
        Variable.withString(days60.toIso8601String()),
        Variable.withString(days30.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
        Variable.withString(days60.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.suppliers, _db.supplierTransactions},
    ).get();

    return rows.map((row) {
      return SupplierAgingItem(
        supplierId: row.read<int>('supplier_id'),
        supplierName: row.read<String>('supplier_name'),
        phone: row.readNullable<String>('phone'),
        email: row.readNullable<String>('email'),
        currentCents: row.read<int>('current_cents'),
        days30Cents: row.read<int>('days_30_cents'),
        days60Cents: row.read<int>('days_60_cents'),
        days90Cents: row.read<int>('days_90_cents'),
        over90Cents: row.read<int>('over_90_cents'),
        totalCents: row.read<int>('total_cents'),
      );
    }).toList();
  }
}
