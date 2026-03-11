import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SalesTaxReportEvent extends RealtimeEvent {
  const SalesTaxReportEvent();
}

class SalesTaxReportDateRangeChanged extends SalesTaxReportEvent {
  final ReportDateRange dateRange;
  const SalesTaxReportDateRangeChanged(this.dateRange);
}

class SalesTaxReportSortChanged extends SalesTaxReportEvent {
  final SalesTaxSortType sort;
  const SalesTaxReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum SalesTaxSortType {
  dateDesc,
  dateAsc,
  taxDesc,
  taxAsc,
  totalDesc,
  totalAsc,
}

// ==================== DATA MODELS ====================

class SalesTaxInvoiceItem {
  final int saleId;
  final String invoiceNumber;
  final String? customerName;
  final DateTime saleDate;
  final int subtotalCents;
  final int discountCents;
  final int taxableCents; // subtotal - discount
  final int taxCents;
  final int totalCents;
  final String status;

  const SalesTaxInvoiceItem({
    required this.saleId,
    required this.invoiceNumber,
    this.customerName,
    required this.saleDate,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxableCents,
    required this.taxCents,
    required this.totalCents,
    required this.status,
  });
}

class SalesTaxReturnItem {
  final int returnId;
  final String returnNumber;
  final String? customerName;
  final DateTime returnDate;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;

  const SalesTaxReturnItem({
    required this.returnId,
    required this.returnNumber,
    this.customerName,
    required this.returnDate,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
  });
}

class SalesTaxReportData {
  final List<SalesTaxInvoiceItem> invoices;
  final List<SalesTaxReturnItem> returns;
  final int totalSubtotalCents;
  final int totalDiscountCents;
  final int totalTaxableCents;
  final int totalTaxCollectedCents;
  final int totalSalesCents;
  final int returnTaxCents;
  final int netTaxCents; // collected - return tax
  final int invoiceCount;
  final int returnCount;
  final ReportDateRange dateRange;
  final SalesTaxSortType sort;

  const SalesTaxReportData({
    this.invoices = const [],
    this.returns = const [],
    this.totalSubtotalCents = 0,
    this.totalDiscountCents = 0,
    this.totalTaxableCents = 0,
    this.totalTaxCollectedCents = 0,
    this.totalSalesCents = 0,
    this.returnTaxCents = 0,
    this.netTaxCents = 0,
    this.invoiceCount = 0,
    this.returnCount = 0,
    required this.dateRange,
    this.sort = SalesTaxSortType.dateDesc,
  });

  SalesTaxReportData copyWith({
    List<SalesTaxInvoiceItem>? invoices,
    List<SalesTaxReturnItem>? returns,
    int? totalSubtotalCents,
    int? totalDiscountCents,
    int? totalTaxableCents,
    int? totalTaxCollectedCents,
    int? totalSalesCents,
    int? returnTaxCents,
    int? netTaxCents,
    int? invoiceCount,
    int? returnCount,
    ReportDateRange? dateRange,
    SalesTaxSortType? sort,
  }) {
    return SalesTaxReportData(
      invoices: invoices ?? this.invoices,
      returns: returns ?? this.returns,
      totalSubtotalCents: totalSubtotalCents ?? this.totalSubtotalCents,
      totalDiscountCents: totalDiscountCents ?? this.totalDiscountCents,
      totalTaxableCents: totalTaxableCents ?? this.totalTaxableCents,
      totalTaxCollectedCents: totalTaxCollectedCents ?? this.totalTaxCollectedCents,
      totalSalesCents: totalSalesCents ?? this.totalSalesCents,
      returnTaxCents: returnTaxCents ?? this.returnTaxCents,
      netTaxCents: netTaxCents ?? this.netTaxCents,
      invoiceCount: invoiceCount ?? this.invoiceCount,
      returnCount: returnCount ?? this.returnCount,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class SalesTaxReportBloc
    extends RealtimeBloc<SalesTaxReportData, SalesTaxReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  SalesTaxSortType _sort = SalesTaxSortType.dateDesc;

  SalesTaxReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  @override
  Stream<SalesTaxReportData> get dataStream {
    return _db.select(_db.sales).watch().asyncMap((_) => _loadData());
  }

  @override
  void registerEventHandlers() {
    on<SalesTaxReportDateRangeChanged>(_onDateRangeChanged);
    on<SalesTaxReportSortChanged>(_onSortChanged);
  }

  Future<void> _onDateRangeChanged(
    SalesTaxReportDateRangeChanged event,
    Emitter<RealtimeState<SalesTaxReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    SalesTaxReportSortChanged event,
    Emitter<RealtimeState<SalesTaxReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToInvoices(current.invoices, event.sort);
      emit(RealtimeSuccess<SalesTaxReportData>(
        data: current.copyWith(invoices: sorted, sort: event.sort),
      ));
    }
  }

  Future<SalesTaxReportData> _loadData() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Load sales invoices with tax
    final saleRows = await _db.customSelect(
      '''
      SELECT 
        s.id AS sale_id,
        s.invoice_number,
        c.name AS customer_name,
        s.sale_date,
        s.subtotal_cents,
        s.discount_cents,
        s.tax_cents,
        s.total_cents,
        s.status
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.status != 'voided'
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      ORDER BY s.sale_date DESC
      ''',
      variables: [Variable.withString(startIso), Variable.withString(endIso)],
      readsFrom: {_db.sales, _db.customers},
    ).get();

    final invoices = saleRows.map((row) {
      final subtotal = row.read<int>('subtotal_cents');
      final discount = row.read<int>('discount_cents');
      final taxable = subtotal - discount;
      return SalesTaxInvoiceItem(
        saleId: row.read<int>('sale_id'),
        invoiceNumber: row.read<String>('invoice_number'),
        customerName: row.readNullable<String>('customer_name'),
        saleDate: DateTime.parse(row.read<String>('sale_date')),
        subtotalCents: subtotal,
        discountCents: discount,
        taxableCents: taxable < 0 ? 0 : taxable,
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
        status: row.read<String>('status'),
      );
    }).toList();

    // Load sale returns with tax
    final returnRows = await _db.customSelect(
      '''
      SELECT 
        sr.id AS return_id,
        sr.return_number,
        c.name AS customer_name,
        sr.return_date,
        sr.subtotal_cents,
        sr.discount_cents,
        sr.tax_cents,
        sr.total_cents
      FROM sale_returns sr
      INNER JOIN sales s ON s.id = sr.sale_id
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE sr.status = 'posted'
        AND sr.return_date >= ?
        AND sr.return_date <= ?
      ORDER BY sr.return_date DESC
      ''',
      variables: [Variable.withString(startIso), Variable.withString(endIso)],
      readsFrom: {_db.saleReturns, _db.sales, _db.customers},
    ).get();

    final returns = returnRows.map((row) {
      return SalesTaxReturnItem(
        returnId: row.read<int>('return_id'),
        returnNumber: row.read<String>('return_number'),
        customerName: row.readNullable<String>('customer_name'),
        returnDate: DateTime.parse(row.read<String>('return_date')),
        subtotalCents: row.read<int>('subtotal_cents'),
        discountCents: row.read<int>('discount_cents'),
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
      );
    }).toList();

    // Compute totals
    int totalSubtotal = 0, totalDiscount = 0, totalTax = 0, totalSales = 0;
    for (final inv in invoices) {
      totalSubtotal += inv.subtotalCents;
      totalDiscount += inv.discountCents;
      totalTax += inv.taxCents;
      totalSales += inv.totalCents;
    }
    final totalTaxable = totalSubtotal - totalDiscount;

    int returnTax = 0;
    for (final ret in returns) {
      returnTax += ret.taxCents;
    }

    final sorted = _applySortToInvoices(invoices, _sort);

    return SalesTaxReportData(
      invoices: sorted,
      returns: returns,
      totalSubtotalCents: totalSubtotal,
      totalDiscountCents: totalDiscount,
      totalTaxableCents: totalTaxable < 0 ? 0 : totalTaxable,
      totalTaxCollectedCents: totalTax,
      totalSalesCents: totalSales,
      returnTaxCents: returnTax,
      netTaxCents: totalTax - returnTax,
      invoiceCount: invoices.length,
      returnCount: returns.length,
      dateRange: _dateRange,
      sort: _sort,
    );
  }

  List<SalesTaxInvoiceItem> _applySortToInvoices(
    List<SalesTaxInvoiceItem> items,
    SalesTaxSortType sort,
  ) {
    final list = List<SalesTaxInvoiceItem>.from(items);
    switch (sort) {
      case SalesTaxSortType.dateDesc:
        list.sort((a, b) => b.saleDate.compareTo(a.saleDate));
      case SalesTaxSortType.dateAsc:
        list.sort((a, b) => a.saleDate.compareTo(b.saleDate));
      case SalesTaxSortType.taxDesc:
        list.sort((a, b) => b.taxCents.compareTo(a.taxCents));
      case SalesTaxSortType.taxAsc:
        list.sort((a, b) => a.taxCents.compareTo(b.taxCents));
      case SalesTaxSortType.totalDesc:
        list.sort((a, b) => b.totalCents.compareTo(a.totalCents));
      case SalesTaxSortType.totalAsc:
        list.sort((a, b) => a.totalCents.compareTo(b.totalCents));
    }
    return list;
  }
}
