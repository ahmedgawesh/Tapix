import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerAgingReportEvent extends RealtimeEvent {
  const CustomerAgingReportEvent();
}

class CustomerAgingReportDateRangeChanged extends CustomerAgingReportEvent {
  final ReportDateRange dateRange;
  const CustomerAgingReportDateRangeChanged(this.dateRange);
}

class CustomerAgingReportSortChanged extends CustomerAgingReportEvent {
  final CustomerAgingSortType sort;
  const CustomerAgingReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum CustomerAgingSortType {
  totalDesc,
  totalAsc,
  over90Desc,
  over90Asc,
  nameAsc,
  nameDesc,
}

// ==================== DATA MODELS ====================

class CustomerAgingItem {
  final int customerId;
  final String customerName;
  final String segment;
  final String? phone;
  final String? email;
  final int currentCents;
  final int days30Cents;
  final int days60Cents;
  final int days90Cents;
  final int over90Cents;
  final int totalCents;

  const CustomerAgingItem({
    required this.customerId,
    required this.customerName,
    required this.segment,
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

class CustomerAgingReportData {
  final List<CustomerAgingItem> customers;
  final int grandTotalCurrentCents;
  final int grandTotal30Cents;
  final int grandTotal60Cents;
  final int grandTotal90Cents;
  final int grandTotalOver90Cents;
  final int grandTotalCents;
  final int customerCount;
  final ReportDateRange dateRange;
  final CustomerAgingSortType sort;

  const CustomerAgingReportData({
    this.customers = const [],
    this.grandTotalCurrentCents = 0,
    this.grandTotal30Cents = 0,
    this.grandTotal60Cents = 0,
    this.grandTotal90Cents = 0,
    this.grandTotalOver90Cents = 0,
    this.grandTotalCents = 0,
    this.customerCount = 0,
    required this.dateRange,
    this.sort = CustomerAgingSortType.totalDesc,
  });

  int get grandTotalOverdueCents =>
      grandTotal30Cents + grandTotal60Cents + grandTotal90Cents + grandTotalOver90Cents;

  CustomerAgingReportData copyWith({
    List<CustomerAgingItem>? customers,
    int? grandTotalCurrentCents,
    int? grandTotal30Cents,
    int? grandTotal60Cents,
    int? grandTotal90Cents,
    int? grandTotalOver90Cents,
    int? grandTotalCents,
    int? customerCount,
    ReportDateRange? dateRange,
    CustomerAgingSortType? sort,
  }) {
    return CustomerAgingReportData(
      customers: customers ?? this.customers,
      grandTotalCurrentCents: grandTotalCurrentCents ?? this.grandTotalCurrentCents,
      grandTotal30Cents: grandTotal30Cents ?? this.grandTotal30Cents,
      grandTotal60Cents: grandTotal60Cents ?? this.grandTotal60Cents,
      grandTotal90Cents: grandTotal90Cents ?? this.grandTotal90Cents,
      grandTotalOver90Cents: grandTotalOver90Cents ?? this.grandTotalOver90Cents,
      grandTotalCents: grandTotalCents ?? this.grandTotalCents,
      customerCount: customerCount ?? this.customerCount,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class CustomerAgingReportBloc
    extends RealtimeBloc<CustomerAgingReportData, CustomerAgingReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  CustomerAgingSortType _sort = CustomerAgingSortType.totalDesc;

  CustomerAgingReportBloc(this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<CustomerAgingReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<CustomerAgingReportDateRangeChanged>(_onDateRangeChanged);
    on<CustomerAgingReportSortChanged>(_onSortChanged);
  }

  Stream<CustomerAgingReportData> _buildCombinedStream() {
    // Watch customer_transactions for real-time changes.
    // Note: This watches ALL transactions (not date-filtered) because Drift
    // table-level watches don't support WHERE clauses. The asyncMap re-queries
    // with the current date range, so data is always correct.
    return _db.select(_db.customerTransactions).watch().asyncMap((_) async {
      final customers = await _loadAgingData();

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

      final sorted = _applySortToCustomers(customers, _sort);

      return CustomerAgingReportData(
        customers: sorted,
        grandTotalCurrentCents: totalCurrent,
        grandTotal30Cents: total30,
        grandTotal60Cents: total60,
        grandTotal90Cents: total90,
        grandTotalOver90Cents: totalOver90,
        grandTotalCents: grandTotal,
        customerCount: customers.length,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    CustomerAgingReportDateRangeChanged event,
    Emitter<RealtimeState<CustomerAgingReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    CustomerAgingReportSortChanged event,
    Emitter<RealtimeState<CustomerAgingReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToCustomers(current.customers, event.sort);
      emit(RealtimeSuccess<CustomerAgingReportData>(
        data: current.copyWith(
          customers: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<CustomerAgingItem> _applySortToCustomers(
    List<CustomerAgingItem> items,
    CustomerAgingSortType sort,
  ) {
    final list = List<CustomerAgingItem>.from(items);
    switch (sort) {
      case CustomerAgingSortType.totalDesc:
        list.sort((a, b) => b.totalCents.compareTo(a.totalCents));
      case CustomerAgingSortType.totalAsc:
        list.sort((a, b) => a.totalCents.compareTo(b.totalCents));
      case CustomerAgingSortType.over90Desc:
        list.sort((a, b) => b.over90Cents.compareTo(a.over90Cents));
      case CustomerAgingSortType.over90Asc:
        list.sort((a, b) => a.over90Cents.compareTo(b.over90Cents));
      case CustomerAgingSortType.nameAsc:
        list.sort((a, b) => a.customerName.compareTo(b.customerName));
      case CustomerAgingSortType.nameDesc:
        list.sort((a, b) => b.customerName.compareTo(a.customerName));
    }
    return list;
  }

  Future<List<CustomerAgingItem>> _loadAgingData() async {
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
      SELECT 
        c.id AS customer_id,
        c.name AS customer_name,
        c.segment AS segment,
        c.phone AS phone,
        c.email AS email,
        COALESCE(SUM(CASE WHEN ct.transaction_date >= ? THEN ct.amount_cents ELSE 0 END), 0) AS current_cents,
        COALESCE(SUM(CASE WHEN ct.transaction_date >= ? AND ct.transaction_date < ? THEN ct.amount_cents ELSE 0 END), 0) AS days_30_cents,
        COALESCE(SUM(CASE WHEN ct.transaction_date >= ? AND ct.transaction_date < ? THEN ct.amount_cents ELSE 0 END), 0) AS days_60_cents,
        COALESCE(SUM(CASE WHEN ct.transaction_date >= ? AND ct.transaction_date < ? THEN ct.amount_cents ELSE 0 END), 0) AS days_90_cents,
        COALESCE(SUM(CASE WHEN ct.transaction_date < ? THEN ct.amount_cents ELSE 0 END), 0) AS over_90_cents,
        COALESCE(SUM(ct.amount_cents), 0) AS total_cents
      FROM customers c
      LEFT JOIN customer_transactions ct ON ct.customer_id = c.id
        AND ct.transaction_date <= ?
      WHERE c.is_active = 1
      GROUP BY c.id
      HAVING total_cents > 0
      ORDER BY total_cents DESC
      ''',
      variables: [
        Variable.withString(days30.toIso8601String()),
        Variable.withString(days60.toIso8601String()),
        Variable.withString(days30.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
        Variable.withString(days60.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.customers, _db.customerTransactions},
    ).get();

    return rows.map((row) {
      return CustomerAgingItem(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        segment: row.read<String>('segment'),
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
