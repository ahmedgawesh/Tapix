import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerSalesReportEvent extends RealtimeEvent {
  const CustomerSalesReportEvent();
}

class CustomerSalesReportDateRangeChanged extends CustomerSalesReportEvent {
  final ReportDateRange dateRange;
  const CustomerSalesReportDateRangeChanged(this.dateRange);
}

class CustomerSalesReportSortChanged extends CustomerSalesReportEvent {
  final CustomerSalesSortType sort;
  const CustomerSalesReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum CustomerSalesSortType {
  revenueDesc,
  revenueAsc,
  invoiceCountDesc,
  invoiceCountAsc,
  nameAsc,
  nameDesc,
}

// ==================== DATA MODELS ====================

class CustomerSalesItem {
  final int customerId;
  final String customerName;
  final String segment;
  final int totalSalesCents;
  final int invoiceCount;
  final int totalQuantity;
  final int averageOrderCents;
  final DateTime? lastSaleDate;

  const CustomerSalesItem({
    required this.customerId,
    required this.customerName,
    required this.segment,
    required this.totalSalesCents,
    required this.invoiceCount,
    required this.totalQuantity,
    required this.averageOrderCents,
    this.lastSaleDate,
  });
}

class CustomerSalesReportData {
  final List<CustomerSalesItem> customers;
  final int grandTotalSalesCents;
  final int grandTotalInvoices;
  final int grandTotalQuantity;
  final int uniqueCustomerCount;
  final ReportDateRange dateRange;
  final CustomerSalesSortType sort;

  const CustomerSalesReportData({
    this.customers = const [],
    this.grandTotalSalesCents = 0,
    this.grandTotalInvoices = 0,
    this.grandTotalQuantity = 0,
    this.uniqueCustomerCount = 0,
    required this.dateRange,
    this.sort = CustomerSalesSortType.revenueDesc,
  });

  CustomerSalesReportData copyWith({
    List<CustomerSalesItem>? customers,
    int? grandTotalSalesCents,
    int? grandTotalInvoices,
    int? grandTotalQuantity,
    int? uniqueCustomerCount,
    ReportDateRange? dateRange,
    CustomerSalesSortType? sort,
  }) {
    return CustomerSalesReportData(
      customers: customers ?? this.customers,
      grandTotalSalesCents: grandTotalSalesCents ?? this.grandTotalSalesCents,
      grandTotalInvoices: grandTotalInvoices ?? this.grandTotalInvoices,
      grandTotalQuantity: grandTotalQuantity ?? this.grandTotalQuantity,
      uniqueCustomerCount: uniqueCustomerCount ?? this.uniqueCustomerCount,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class CustomerSalesReportBloc
    extends RealtimeBloc<CustomerSalesReportData, CustomerSalesReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  CustomerSalesSortType _sort = CustomerSalesSortType.revenueDesc;

  CustomerSalesReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<CustomerSalesReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<CustomerSalesReportDateRangeChanged>(_onDateRangeChanged);
    on<CustomerSalesReportSortChanged>(_onSortChanged);
  }

  Stream<CustomerSalesReportData> _buildCombinedStream() {
    // Watch sales table for real-time changes.
    // Note: This watches ALL sales (not date-filtered) because Drift
    // table-level watches don't support WHERE clauses. The asyncMap re-queries
    // with the current date range, so data is always correct.
    return _db.select(_db.sales).watch().asyncMap((_) async {
      final customers = await _loadCustomerSales();

      int totalSales = 0;
      int totalInvoices = 0;
      int totalQuantity = 0;
      for (final c in customers) {
        totalSales += c.totalSalesCents;
        totalInvoices += c.invoiceCount;
        totalQuantity += c.totalQuantity;
      }

      final sorted = _applySortToCustomers(customers, _sort);

      return CustomerSalesReportData(
        customers: sorted,
        grandTotalSalesCents: totalSales,
        grandTotalInvoices: totalInvoices,
        grandTotalQuantity: totalQuantity,
        uniqueCustomerCount: customers.length,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    CustomerSalesReportDateRangeChanged event,
    Emitter<RealtimeState<CustomerSalesReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    CustomerSalesReportSortChanged event,
    Emitter<RealtimeState<CustomerSalesReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToCustomers(current.customers, event.sort);
      emit(RealtimeSuccess<CustomerSalesReportData>(
        data: current.copyWith(
          customers: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<CustomerSalesItem> _applySortToCustomers(
    List<CustomerSalesItem> items,
    CustomerSalesSortType sort,
  ) {
    final list = List<CustomerSalesItem>.from(items);
    switch (sort) {
      case CustomerSalesSortType.revenueDesc:
        list.sort((a, b) => b.totalSalesCents.compareTo(a.totalSalesCents));
      case CustomerSalesSortType.revenueAsc:
        list.sort((a, b) => a.totalSalesCents.compareTo(b.totalSalesCents));
      case CustomerSalesSortType.invoiceCountDesc:
        list.sort((a, b) => b.invoiceCount.compareTo(a.invoiceCount));
      case CustomerSalesSortType.invoiceCountAsc:
        list.sort((a, b) => a.invoiceCount.compareTo(b.invoiceCount));
      case CustomerSalesSortType.nameAsc:
        list.sort((a, b) => a.customerName.compareTo(b.customerName));
      case CustomerSalesSortType.nameDesc:
        list.sort((a, b) => b.customerName.compareTo(a.customerName));
    }
    return list;
  }

  Future<List<CustomerSalesItem>> _loadCustomerSales() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        c.id AS customer_id,
        c.name AS customer_name,
        c.segment AS segment,
        COUNT(s.id) AS invoice_count,
        COALESCE(SUM(s.total_cents), 0) AS total_sales_cents,
        COALESCE(SUM(item_totals.total_qty), 0) AS total_quantity,
        MAX(s.sale_date) AS last_sale_date
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
      HAVING total_sales_cents > 0
      ORDER BY total_sales_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {
        _db.sales,
        _db.saleItems,
        _db.customers,
      },
    ).get();

    return rows.map((row) {
      final totalSales = row.read<int>('total_sales_cents');
      final invoices = row.read<int>('invoice_count');
      final avgOrder = invoices > 0 ? totalSales ~/ invoices : 0;
      final lastDateVal = row.readNullable<String>('last_sale_date');

      return CustomerSalesItem(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        segment: row.read<String>('segment'),
        totalSalesCents: totalSales,
        invoiceCount: invoices,
        totalQuantity: row.read<int>('total_quantity'),
        averageOrderCents: avgOrder,
        lastSaleDate: lastDateVal != null
            ? DateTime.parse(lastDateVal)
            : null,
      );
    }).toList();
  }
}
