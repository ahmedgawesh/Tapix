import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/party_aging_ledger_service.dart';
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
      grandTotal30Cents +
      grandTotal60Cents +
      grandTotal90Cents +
      grandTotalOver90Cents;

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
      grandTotalCurrentCents:
          grandTotalCurrentCents ?? this.grandTotalCurrentCents,
      grandTotal30Cents: grandTotal30Cents ?? this.grandTotal30Cents,
      grandTotal60Cents: grandTotal60Cents ?? this.grandTotal60Cents,
      grandTotal90Cents: grandTotal90Cents ?? this.grandTotal90Cents,
      grandTotalOver90Cents:
          grandTotalOver90Cents ?? this.grandTotalOver90Cents,
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
  ReportDateRange _dateRange;
  CustomerAgingSortType _sort = CustomerAgingSortType.totalDesc;

  CustomerAgingReportBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

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
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.customers, _db.customerTransactions},
        )
        .watch()
        .asyncMap((_) async {
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
      emit(
        RealtimeSuccess<CustomerAgingReportData>(
          data: current.copyWith(customers: sorted, sort: event.sort),
        ),
      );
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
    final rows = await PartyAgingLedgerService(
      _db,
    ).loadCustomers(asOf: _dateRange.endDate);
    return rows.map((row) {
      final buckets = row.buckets;
      return CustomerAgingItem(
        customerId: row.partyId,
        customerName: row.partyName,
        segment: row.segment ?? 'retail',
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
