import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/party_aging_ledger_service.dart';
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
      grandTotal30Cents +
      grandTotal60Cents +
      grandTotal90Cents +
      grandTotalOver90Cents;

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
      grandTotalCurrentCents:
          grandTotalCurrentCents ?? this.grandTotalCurrentCents,
      grandTotal30Cents: grandTotal30Cents ?? this.grandTotal30Cents,
      grandTotal60Cents: grandTotal60Cents ?? this.grandTotal60Cents,
      grandTotal90Cents: grandTotal90Cents ?? this.grandTotal90Cents,
      grandTotalOver90Cents:
          grandTotalOver90Cents ?? this.grandTotalOver90Cents,
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
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.suppliers, _db.supplierTransactions},
        )
        .watch()
        .asyncMap((_) async {
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
      emit(
        RealtimeSuccess<SupplierAgingReportData>(
          data: current.copyWith(suppliers: sorted, sort: event.sort),
        ),
      );
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
    final rows = await PartyAgingLedgerService(
      _db,
    ).loadSuppliers(asOf: _dateRange.endDate);
    return rows.map((row) {
      final buckets = row.buckets;
      return SupplierAgingItem(
        supplierId: row.partyId,
        supplierName: row.partyName,
        phone: row.phone,
        email: row.email,
        currentCents: buckets.currentCents,
        days30Cents: buckets.days30Cents,
        days60Cents: buckets.days60Cents,
        days90Cents: buckets.days90Cents,
        over90Cents: buckets.over90Cents,
        totalCents: buckets.totalCents,
      );
    }).toList();
  }
}
