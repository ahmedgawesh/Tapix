import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class TopCustomersEvent extends RealtimeEvent {
  const TopCustomersEvent();
}

class TopCustomersDateRangeChanged extends TopCustomersEvent {
  final ReportDateRange dateRange;
  const TopCustomersDateRangeChanged(this.dateRange);
}

class TopCustomersSortChanged extends TopCustomersEvent {
  final TopCustomersSortType sort;
  const TopCustomersSortChanged(this.sort);
}

class TopCustomersViewChanged extends TopCustomersEvent {
  final TopCustomersViewType view;
  const TopCustomersViewChanged(this.view);
}

// ==================== ENUMS ====================

enum TopCustomersSortType {
  revenueDesc,
  revenueAsc,
  volumeDesc,
  volumeAsc,
  nameAsc,
  nameDesc,
}

enum TopCustomersViewType {
  byRevenue,
  byVolume,
}

// ==================== DATA MODELS ====================

class TopCustomerItem {
  final int customerId;
  final String customerName;
  final String segment;
  final int totalRevenueCents;
  final int transactionCount;
  final int totalQuantity;
  final int averageOrderCents;
  final DateTime? lastPurchaseDate;

  const TopCustomerItem({
    required this.customerId,
    required this.customerName,
    required this.segment,
    required this.totalRevenueCents,
    required this.transactionCount,
    required this.totalQuantity,
    required this.averageOrderCents,
    this.lastPurchaseDate,
  });
}

class TopCustomersData {
  final List<TopCustomerItem> customers;
  final int grandTotalRevenueCents;
  final int grandTotalTransactions;
  final int grandTotalQuantity;
  final int uniqueCustomerCount;
  final ReportDateRange dateRange;
  final TopCustomersSortType sort;
  final TopCustomersViewType view;

  const TopCustomersData({
    this.customers = const [],
    this.grandTotalRevenueCents = 0,
    this.grandTotalTransactions = 0,
    this.grandTotalQuantity = 0,
    this.uniqueCustomerCount = 0,
    required this.dateRange,
    this.sort = TopCustomersSortType.revenueDesc,
    this.view = TopCustomersViewType.byRevenue,
  });

  TopCustomersData copyWith({
    List<TopCustomerItem>? customers,
    int? grandTotalRevenueCents,
    int? grandTotalTransactions,
    int? grandTotalQuantity,
    int? uniqueCustomerCount,
    ReportDateRange? dateRange,
    TopCustomersSortType? sort,
    TopCustomersViewType? view,
  }) {
    return TopCustomersData(
      customers: customers ?? this.customers,
      grandTotalRevenueCents:
          grandTotalRevenueCents ?? this.grandTotalRevenueCents,
      grandTotalTransactions:
          grandTotalTransactions ?? this.grandTotalTransactions,
      grandTotalQuantity: grandTotalQuantity ?? this.grandTotalQuantity,
      uniqueCustomerCount: uniqueCustomerCount ?? this.uniqueCustomerCount,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
      view: view ?? this.view,
    );
  }
}

// ==================== BLOC ====================

class TopCustomersBloc
    extends RealtimeBloc<TopCustomersData, TopCustomersEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  TopCustomersSortType _sort = TopCustomersSortType.revenueDesc;
  TopCustomersViewType _view = TopCustomersViewType.byRevenue;

  TopCustomersBloc(this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<TopCustomersData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<TopCustomersDateRangeChanged>(_onDateRangeChanged);
    on<TopCustomersSortChanged>(_onSortChanged);
    on<TopCustomersViewChanged>(_onViewChanged);
  }

  Stream<TopCustomersData> _buildCombinedStream() {
    // Watch sales table for real-time changes
    return _db.select(_db.sales).watch().asyncMap((_) async {
      final customers = await _loadTopCustomers();

      int totalRevenue = 0;
      int totalTransactions = 0;
      int totalQuantity = 0;
      for (final c in customers) {
        totalRevenue += c.totalRevenueCents;
        totalTransactions += c.transactionCount;
        totalQuantity += c.totalQuantity;
      }

      final sorted = _applySortToCustomers(customers, _sort);

      return TopCustomersData(
        customers: sorted,
        grandTotalRevenueCents: totalRevenue,
        grandTotalTransactions: totalTransactions,
        grandTotalQuantity: totalQuantity,
        uniqueCustomerCount: customers.length,
        dateRange: _dateRange,
        sort: _sort,
        view: _view,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    TopCustomersDateRangeChanged event,
    Emitter<RealtimeState<TopCustomersData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    TopCustomersSortChanged event,
    Emitter<RealtimeState<TopCustomersData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToCustomers(current.customers, event.sort);
      emit(RealtimeSuccess<TopCustomersData>(
        data: current.copyWith(
          customers: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  void _onViewChanged(
    TopCustomersViewChanged event,
    Emitter<RealtimeState<TopCustomersData>> emit,
  ) {
    _view = event.view;
    final current = currentData;
    if (current != null) {
      // Re-sort based on view type
      final newSort = event.view == TopCustomersViewType.byRevenue
          ? TopCustomersSortType.revenueDesc
          : TopCustomersSortType.volumeDesc;
      _sort = newSort;
      final sorted = _applySortToCustomers(current.customers, newSort);
      emit(RealtimeSuccess<TopCustomersData>(
        data: current.copyWith(
          customers: sorted,
          sort: newSort,
          view: event.view,
        ),
      ));
    }
  }

  List<TopCustomerItem> _applySortToCustomers(
    List<TopCustomerItem> items,
    TopCustomersSortType sort,
  ) {
    final list = List<TopCustomerItem>.from(items);
    switch (sort) {
      case TopCustomersSortType.revenueDesc:
        list.sort(
            (a, b) => b.totalRevenueCents.compareTo(a.totalRevenueCents));
      case TopCustomersSortType.revenueAsc:
        list.sort(
            (a, b) => a.totalRevenueCents.compareTo(b.totalRevenueCents));
      case TopCustomersSortType.volumeDesc:
        list.sort(
            (a, b) => b.transactionCount.compareTo(a.transactionCount));
      case TopCustomersSortType.volumeAsc:
        list.sort(
            (a, b) => a.transactionCount.compareTo(b.transactionCount));
      case TopCustomersSortType.nameAsc:
        list.sort((a, b) => a.customerName.compareTo(b.customerName));
      case TopCustomersSortType.nameDesc:
        list.sort((a, b) => b.customerName.compareTo(a.customerName));
    }
    return list;
  }

  Future<List<TopCustomerItem>> _loadTopCustomers() async {
    final startUnix =
        _dateRange.startDate.millisecondsSinceEpoch ~/ 1000;
    final endUnix = _dateRange.endDate.millisecondsSinceEpoch ~/ 1000;

    final rows = await _db.customSelect(
      '''
      SELECT 
        c.id AS customer_id,
        c.name AS customer_name,
        c.segment AS segment,
        COUNT(s.id) AS transaction_count,
        COALESCE(SUM(s.total_cents), 0) AS total_revenue_cents,
        COALESCE(SUM(item_totals.total_qty), 0) AS total_quantity,
        MAX(s.sale_date) AS last_purchase_date
      FROM sales s
      INNER JOIN customers c ON c.id = s.customer_id
      LEFT JOIN (
        SELECT si.sale_id, SUM(si.quantity) AS total_qty
        FROM sale_items si
        GROUP BY si.sale_id
      ) item_totals ON item_totals.sale_id = s.id
      WHERE s.status != 'voided'
        AND s.customer_id IS NOT NULL
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY c.id
      HAVING total_revenue_cents > 0
      ORDER BY total_revenue_cents DESC
      ''',
      variables: [
        Variable<int>(startUnix),
        Variable<int>(endUnix),
      ],
      readsFrom: {
        _db.sales,
        _db.saleItems,
        _db.customers,
      },
    ).get();

    return rows.map((row) {
      final totalRevenue = row.read<int>('total_revenue_cents');
      final txCount = row.read<int>('transaction_count');
      final avgOrder = txCount > 0 ? totalRevenue ~/ txCount : 0;
      final lastDateVal = row.readNullable<int>('last_purchase_date');

      return TopCustomerItem(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        segment: row.read<String>('segment'),
        totalRevenueCents: totalRevenue,
        transactionCount: txCount,
        totalQuantity: row.read<int>('total_quantity'),
        averageOrderCents: avgOrder,
        lastPurchaseDate: lastDateVal != null
            ? DateTime.fromMillisecondsSinceEpoch(lastDateVal * 1000)
            : null,
      );
    }).toList();
  }
}
