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
  ReportDateRange _dateRange;
  SupplierAgingSortType _sort = SupplierAgingSortType.totalDesc;

  SupplierAgingReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

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

  /// Aging report: derive net balance from transactions (not cached balance_cents),
  /// then age the outstanding amount using FIFO — payments retire the oldest
  /// purchases first. Opening balance is treated as the oldest debt (>90 days).
  Future<List<SupplierAgingItem>> _loadAgingData() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final d30 = today.subtract(const Duration(days: 30));
    final d60 = today.subtract(const Duration(days: 60));
    final d90 = today.subtract(const Duration(days: 90));

    // Step 1: Get all active suppliers with their opening balances
    final supplierRows = await _db.customSelect(
      '''
      SELECT s.id, s.name, s.phone, s.email, s.opening_balance_cents
      FROM suppliers s
      WHERE s.is_active = 1
      ''',
      readsFrom: {_db.suppliers},
    ).get();

    final items = <SupplierAgingItem>[];

    for (final sRow in supplierRows) {
      final supplierId = sRow.read<int>('id');
      final openingBalance = sRow.read<int>('opening_balance_cents');

      // Step 2: Get purchase amounts bucketed by age for this supplier
      // Buckets: current (0-30d), 31-60d, 61-90d, 90+d
      final bucketRows = await _db.customSelect(
        '''
        SELECT
          COALESCE(SUM(CASE WHEN st.transaction_date >= ? THEN st.amount_cents ELSE 0 END), 0) AS bucket_current,
          COALESCE(SUM(CASE WHEN st.transaction_date >= ? AND st.transaction_date < ? THEN st.amount_cents ELSE 0 END), 0) AS bucket_30,
          COALESCE(SUM(CASE WHEN st.transaction_date >= ? AND st.transaction_date < ? THEN st.amount_cents ELSE 0 END), 0) AS bucket_60,
          COALESCE(SUM(CASE WHEN st.transaction_date < ? THEN st.amount_cents ELSE 0 END), 0) AS bucket_over90
        FROM supplier_transactions st
        WHERE st.supplier_id = ?
          AND st.transaction_type = 'purchase'
        ''',
        variables: [
          Variable.withString(d30.toIso8601String()),   // current: >= d30
          Variable.withString(d60.toIso8601String()),   // 31-60: >= d60
          Variable.withString(d30.toIso8601String()),   //        AND < d30
          Variable.withString(d90.toIso8601String()),   // 61-90: >= d90
          Variable.withString(d60.toIso8601String()),   //        AND < d60
          Variable.withString(d90.toIso8601String()),   // over90: < d90
          Variable.withInt(supplierId),
        ],
        readsFrom: {_db.supplierTransactions},
      ).getSingle();

      // Step 3: Get total credits (payments + discounts + returns) for this supplier
      final creditRow = await _db.customSelect(
        '''
        SELECT COALESCE(SUM(ABS(st.amount_cents)), 0) AS total_credits
        FROM supplier_transactions st
        WHERE st.supplier_id = ?
          AND st.transaction_type IN ('payment', 'discount', 'credit_note', 'refund')
        ''',
        variables: [Variable.withInt(supplierId)],
        readsFrom: {_db.supplierTransactions},
      ).getSingle();

      final bucketCurrent = bucketRows.read<int>('bucket_current');
      final bucket30 = bucketRows.read<int>('bucket_30');
      final bucket60 = bucketRows.read<int>('bucket_60');
      final bucketOver90 = bucketRows.read<int>('bucket_over90');
      final totalCredits = creditRow.read<int>('total_credits');

      // Step 4: FIFO aging — payments retire oldest debt first.
      // Buckets from oldest to newest: opening > over90 > 60 > 30 > current
      var remaining = totalCredits;

      // Opening balance is the oldest debt
      int agedOpening = openingBalance > 0 ? openingBalance : 0;
      if (remaining > 0 && agedOpening > 0) {
        final applied = remaining < agedOpening ? remaining : agedOpening;
        agedOpening -= applied;
        remaining -= applied;
      }

      int agedOver90 = bucketOver90 > 0 ? bucketOver90 : 0;
      if (remaining > 0 && agedOver90 > 0) {
        final applied = remaining < agedOver90 ? remaining : agedOver90;
        agedOver90 -= applied;
        remaining -= applied;
      }

      int aged60 = bucket60 > 0 ? bucket60 : 0;
      if (remaining > 0 && aged60 > 0) {
        final applied = remaining < aged60 ? remaining : aged60;
        aged60 -= applied;
        remaining -= applied;
      }

      int aged30 = bucket30 > 0 ? bucket30 : 0;
      if (remaining > 0 && aged30 > 0) {
        final applied = remaining < aged30 ? remaining : aged30;
        aged30 -= applied;
        remaining -= applied;
      }

      int agedCurrent = bucketCurrent > 0 ? bucketCurrent : 0;
      if (remaining > 0 && agedCurrent > 0) {
        final applied = remaining < agedCurrent ? remaining : agedCurrent;
        agedCurrent -= applied;
        remaining -= applied;
      }

      // Combine opening balance into the over-90 bucket
      final finalOver90 = agedOpening + agedOver90;
      final totalOutstanding = agedCurrent + aged30 + aged60 + finalOver90;

      // Only include suppliers with outstanding balance > 0
      if (totalOutstanding > 0) {
        items.add(SupplierAgingItem(
          supplierId: supplierId,
          supplierName: sRow.read<String>('name'),
          phone: sRow.readNullable<String>('phone'),
          email: sRow.readNullable<String>('email'),
          currentCents: agedCurrent,
          days30Cents: aged30,
          days60Cents: aged60,
          days90Cents: 0,
          over90Cents: finalOver90,
          totalCents: totalOutstanding,
        ));
      }
    }

    return items;
  }
}
