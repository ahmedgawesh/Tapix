import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class PurchaseTaxReportEvent extends RealtimeEvent {
  const PurchaseTaxReportEvent();
}

class PurchaseTaxReportDateRangeChanged extends PurchaseTaxReportEvent {
  final ReportDateRange dateRange;
  const PurchaseTaxReportDateRangeChanged(this.dateRange);
}

class PurchaseTaxReportSortChanged extends PurchaseTaxReportEvent {
  final PurchaseTaxSortType sort;
  const PurchaseTaxReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum PurchaseTaxSortType {
  dateDesc,
  dateAsc,
  taxDesc,
  taxAsc,
  totalDesc,
  totalAsc,
}

// ==================== DATA MODELS ====================

class PurchaseTaxInvoiceItem {
  final int purchaseId;
  final String purchaseNumber;
  final String? supplierName;
  final DateTime purchaseDate;
  final int subtotalCents;
  final int discountCents;
  final int taxableCents;
  final int taxCents;
  final int totalCents;
  final String status;

  const PurchaseTaxInvoiceItem({
    required this.purchaseId,
    required this.purchaseNumber,
    this.supplierName,
    required this.purchaseDate,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxableCents,
    required this.taxCents,
    required this.totalCents,
    required this.status,
  });
}

class PurchaseTaxReturnItem {
  final int returnId;
  final String returnNumber;
  final String? supplierName;
  final DateTime returnDate;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;

  const PurchaseTaxReturnItem({
    required this.returnId,
    required this.returnNumber,
    this.supplierName,
    required this.returnDate,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
  });
}

class PurchaseTaxReportData {
  final List<PurchaseTaxInvoiceItem> invoices;
  final List<PurchaseTaxReturnItem> returns;
  final int totalSubtotalCents;
  final int totalDiscountCents;
  final int totalTaxableCents;
  final int totalTaxPaidCents;
  final int totalPurchasesCents;
  final int returnTaxCents;
  final int netTaxCents;
  final int invoiceCount;
  final int returnCount;
  final ReportDateRange dateRange;
  final PurchaseTaxSortType sort;

  const PurchaseTaxReportData({
    this.invoices = const [],
    this.returns = const [],
    this.totalSubtotalCents = 0,
    this.totalDiscountCents = 0,
    this.totalTaxableCents = 0,
    this.totalTaxPaidCents = 0,
    this.totalPurchasesCents = 0,
    this.returnTaxCents = 0,
    this.netTaxCents = 0,
    this.invoiceCount = 0,
    this.returnCount = 0,
    required this.dateRange,
    this.sort = PurchaseTaxSortType.dateDesc,
  });

  PurchaseTaxReportData copyWith({
    List<PurchaseTaxInvoiceItem>? invoices,
    List<PurchaseTaxReturnItem>? returns,
    int? totalSubtotalCents,
    int? totalDiscountCents,
    int? totalTaxableCents,
    int? totalTaxPaidCents,
    int? totalPurchasesCents,
    int? returnTaxCents,
    int? netTaxCents,
    int? invoiceCount,
    int? returnCount,
    ReportDateRange? dateRange,
    PurchaseTaxSortType? sort,
  }) {
    return PurchaseTaxReportData(
      invoices: invoices ?? this.invoices,
      returns: returns ?? this.returns,
      totalSubtotalCents: totalSubtotalCents ?? this.totalSubtotalCents,
      totalDiscountCents: totalDiscountCents ?? this.totalDiscountCents,
      totalTaxableCents: totalTaxableCents ?? this.totalTaxableCents,
      totalTaxPaidCents: totalTaxPaidCents ?? this.totalTaxPaidCents,
      totalPurchasesCents: totalPurchasesCents ?? this.totalPurchasesCents,
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

class PurchaseTaxReportBloc
    extends RealtimeBloc<PurchaseTaxReportData, PurchaseTaxReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  PurchaseTaxSortType _sort = PurchaseTaxSortType.dateDesc;

  PurchaseTaxReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  @override
  Stream<PurchaseTaxReportData> get dataStream {
    // React to purchases AND both return sources so posting/voiding a linked or
    // adjustment (unlinked) return live-refreshes the tax figures.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.purchases,
            _db.purchaseReturns,
            _db.purchaseReturnAdjustments,
          },
        )
        .watch()
        .asyncMap((_) => _loadData());
  }

  @override
  void registerEventHandlers() {
    on<PurchaseTaxReportDateRangeChanged>(_onDateRangeChanged);
    on<PurchaseTaxReportSortChanged>(_onSortChanged);
  }

  Future<void> _onDateRangeChanged(
    PurchaseTaxReportDateRangeChanged event,
    Emitter<RealtimeState<PurchaseTaxReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    PurchaseTaxReportSortChanged event,
    Emitter<RealtimeState<PurchaseTaxReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToInvoices(current.invoices, event.sort);
      emit(RealtimeSuccess<PurchaseTaxReportData>(
        data: current.copyWith(invoices: sorted, sort: event.sort),
      ));
    }
  }

  Future<PurchaseTaxReportData> _loadData() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final purchaseRows = await _db.customSelect(
      '''
      SELECT 
        p.id AS purchase_id,
        p.purchase_number,
        sup.name AS supplier_name,
        p.purchase_date,
        p.subtotal_cents,
        p.discount_cents,
        p.tax_cents,
        p.total_cents,
        p.status
      FROM purchases p
      LEFT JOIN suppliers sup ON sup.id = p.supplier_id
      WHERE p.status != 'voided'
        AND p.purchase_date >= ?
        AND p.purchase_date <= ?
      ORDER BY p.purchase_date DESC
      ''',
      variables: [Variable.withString(startIso), Variable.withString(endIso)],
      readsFrom: {_db.purchases, _db.suppliers},
    ).get();

    final invoices = purchaseRows.map((row) {
      final subtotal = row.read<int>('subtotal_cents');
      final discount = row.read<int>('discount_cents');
      final taxable = subtotal - discount;
      return PurchaseTaxInvoiceItem(
        purchaseId: row.read<int>('purchase_id'),
        purchaseNumber: row.read<String>('purchase_number'),
        supplierName: row.readNullable<String>('supplier_name'),
        purchaseDate: DateTime.parse(row.read<String>('purchase_date')),
        subtotalCents: subtotal,
        discountCents: discount,
        taxableCents: taxable < 0 ? 0 : taxable,
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
        status: row.read<String>('status'),
      );
    }).toList();

    // Load purchase returns with tax — BOTH linked (invoice-based) returns and
    // adjustment (unlinked, product-based) returns. Input-VAT reversed on an
    // adjustment return is just as real as on a linked return and must reduce
    // the net recoverable tax the same way.
    final returnRows = await _db.customSelect(
      '''
      SELECT return_id, return_number, supplier_name, return_date,
             subtotal_cents, discount_cents, tax_cents, total_cents
      FROM (
        SELECT 
          pr.id AS return_id,
          pr.return_number AS return_number,
          sup.name AS supplier_name,
          pr.return_date AS return_date,
          pr.subtotal_cents AS subtotal_cents,
          pr.discount_cents AS discount_cents,
          pr.tax_cents AS tax_cents,
          pr.total_cents AS total_cents
        FROM purchase_returns pr
        INNER JOIN purchases p ON p.id = pr.purchase_id
        LEFT JOIN suppliers sup ON sup.id = p.supplier_id
        WHERE pr.status = 'posted'
          AND pr.return_date >= ?
          AND pr.return_date <= ?
        UNION ALL
        SELECT 
          pra.id AS return_id,
          pra.return_number AS return_number,
          sup.name AS supplier_name,
          pra.return_date AS return_date,
          pra.subtotal_cents AS subtotal_cents,
          pra.discount_cents AS discount_cents,
          pra.tax_cents AS tax_cents,
          pra.total_cents AS total_cents
        FROM purchase_return_adjustments pra
        LEFT JOIN suppliers sup ON sup.id = pra.supplier_id
        WHERE pra.status = 'posted'
          AND pra.return_date >= ?
          AND pra.return_date <= ?
      )
      ORDER BY return_date DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {
        _db.purchaseReturns,
        _db.purchaseReturnAdjustments,
        _db.purchases,
        _db.suppliers,
      },
    ).get();

    final returns = returnRows.map((row) {
      return PurchaseTaxReturnItem(
        returnId: row.read<int>('return_id'),
        returnNumber: row.read<String>('return_number'),
        supplierName: row.readNullable<String>('supplier_name'),
        returnDate: DateTime.parse(row.read<String>('return_date')),
        subtotalCents: row.read<int>('subtotal_cents'),
        discountCents: row.read<int>('discount_cents'),
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
      );
    }).toList();

    int totalSubtotal = 0, totalDiscount = 0, totalTax = 0, totalPurchases = 0;
    for (final inv in invoices) {
      totalSubtotal += inv.subtotalCents;
      totalDiscount += inv.discountCents;
      totalTax += inv.taxCents;
      totalPurchases += inv.totalCents;
    }
    final totalTaxable = totalSubtotal - totalDiscount;

    int returnTax = 0;
    for (final ret in returns) {
      returnTax += ret.taxCents;
    }

    final sorted = _applySortToInvoices(invoices, _sort);

    return PurchaseTaxReportData(
      invoices: sorted,
      returns: returns,
      totalSubtotalCents: totalSubtotal,
      totalDiscountCents: totalDiscount,
      totalTaxableCents: totalTaxable < 0 ? 0 : totalTaxable,
      totalTaxPaidCents: totalTax,
      totalPurchasesCents: totalPurchases,
      returnTaxCents: returnTax,
      netTaxCents: totalTax - returnTax,
      invoiceCount: invoices.length,
      returnCount: returns.length,
      dateRange: _dateRange,
      sort: _sort,
    );
  }

  List<PurchaseTaxInvoiceItem> _applySortToInvoices(
    List<PurchaseTaxInvoiceItem> items,
    PurchaseTaxSortType sort,
  ) {
    final list = List<PurchaseTaxInvoiceItem>.from(items);
    switch (sort) {
      case PurchaseTaxSortType.dateDesc:
        list.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      case PurchaseTaxSortType.dateAsc:
        list.sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
      case PurchaseTaxSortType.taxDesc:
        list.sort((a, b) => b.taxCents.compareTo(a.taxCents));
      case PurchaseTaxSortType.taxAsc:
        list.sort((a, b) => a.taxCents.compareTo(b.taxCents));
      case PurchaseTaxSortType.totalDesc:
        list.sort((a, b) => b.totalCents.compareTo(a.totalCents));
      case PurchaseTaxSortType.totalAsc:
        list.sort((a, b) => a.totalCents.compareTo(b.totalCents));
    }
    return list;
  }
}
