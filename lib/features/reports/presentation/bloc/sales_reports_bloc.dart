import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SalesReportsEvent extends RealtimeEvent {
  const SalesReportsEvent();
}

class SalesReportsDateRangeChanged extends SalesReportsEvent {
  final ReportDateRange dateRange;
  const SalesReportsDateRangeChanged(this.dateRange);
}

// ==================== DATA MODELS ====================

/// A single sale invoice row for list reports
class SaleInvoiceItem {
  final int saleId;
  final String invoiceNumber;
  final String? customerName;
  final String? cashierName;
  final String? cashierShiftNumber;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int paidAmountCents;
  final String paymentMethod;
  final String? chequeStatuses;
  final String status;
  final DateTime saleDate;

  const SaleInvoiceItem({
    required this.saleId,
    required this.invoiceNumber,
    this.customerName,
    this.cashierName,
    this.cashierShiftNumber,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidAmountCents,
    required this.paymentMethod,
    this.chequeStatuses,
    required this.status,
    required this.saleDate,
  });
}

/// Sales grouped by product
class SalesByProductItem {
  final int productId;
  final String productName;
  final String? categoryName;
  final int totalQuantity;
  final int totalSalesCents;
  final int totalDiscountCents;
  final int totalTaxCents;
  final int invoiceCount;

  const SalesByProductItem({
    required this.productId,
    required this.productName,
    this.categoryName,
    required this.totalQuantity,
    required this.totalSalesCents,
    required this.totalDiscountCents,
    required this.totalTaxCents,
    required this.invoiceCount,
  });
}

/// Sales grouped by category
class SalesByCategoryItem {
  final int categoryId;
  final String categoryName;
  final int totalQuantity;
  final int totalSalesCents;
  final int totalDiscountCents;
  final int totalTaxCents;
  final int productCount;
  final int invoiceCount;

  const SalesByCategoryItem({
    required this.categoryId,
    required this.categoryName,
    required this.totalQuantity,
    required this.totalSalesCents,
    required this.totalDiscountCents,
    required this.totalTaxCents,
    required this.productCount,
    required this.invoiceCount,
  });
}

/// Sales grouped by customer
class SalesByCustomerItem {
  final int customerId;
  final String customerName;
  final int totalSalesCents;
  final int totalDiscountCents;
  final int totalTaxCents;
  final int invoiceCount;
  final int totalQuantity;
  final DateTime? lastSaleDate;

  const SalesByCustomerItem({
    required this.customerId,
    required this.customerName,
    required this.totalSalesCents,
    required this.totalDiscountCents,
    required this.totalTaxCents,
    required this.invoiceCount,
    required this.totalQuantity,
    this.lastSaleDate,
  });
}

/// Tax breakdown by product
class TaxByProductItem {
  final int productId;
  final String productName;
  final int totalSalesCents;
  final int totalTaxCents;
  final int taxRateBps;
  final int totalQuantity;

  const TaxByProductItem({
    required this.productId,
    required this.productName,
    required this.totalSalesCents,
    required this.totalTaxCents,
    required this.taxRateBps,
    required this.totalQuantity,
  });
}

/// Tax breakdown by customer
class TaxByCustomerItem {
  final int customerId;
  final String customerName;
  final int totalSalesCents;
  final int totalTaxCents;
  final int invoiceCount;

  const TaxByCustomerItem({
    required this.customerId,
    required this.customerName,
    required this.totalSalesCents,
    required this.totalTaxCents,
    required this.invoiceCount,
  });
}

/// Cancelled/voided invoice
class CancelledInvoiceItem {
  final int saleId;
  final String invoiceNumber;
  final String? customerName;
  final int totalCents;
  final String status;
  final DateTime saleDate;
  final String? notes;

  const CancelledInvoiceItem({
    required this.saleId,
    required this.invoiceNumber,
    this.customerName,
    required this.totalCents,
    required this.status,
    required this.saleDate,
    this.notes,
  });
}

/// Summary data for the reports
class SalesReportsSummary {
  final int totalSalesCents;
  final int totalDiscountCents;
  final int totalTaxCents;
  final int totalPaidCents;
  final int invoiceCount;
  final int cancelledCount;
  final int cashSalesCents;
  final int creditSalesCents;
  final int cardSalesCents;
  final int chequeSalesCents;

  /// Total value of ALL posted sale returns in the period — linked
  /// (invoice-based) AND adjustment (unlinked) returns combined.
  final int totalReturnsCents;

  /// Count of ALL posted sale returns (linked + adjustment).
  final int returnCount;

  const SalesReportsSummary({
    this.totalSalesCents = 0,
    this.totalDiscountCents = 0,
    this.totalTaxCents = 0,
    this.totalPaidCents = 0,
    this.invoiceCount = 0,
    this.cancelledCount = 0,
    this.cashSalesCents = 0,
    this.creditSalesCents = 0,
    this.cardSalesCents = 0,
    this.chequeSalesCents = 0,
    this.totalReturnsCents = 0,
    this.returnCount = 0,
  });

  /// Net sales = gross sales − all returns (linked + adjustment).
  int get netSalesCents => totalSalesCents - totalReturnsCents;
}

class SalesReportsData {
  final SalesReportsSummary summary;
  final List<SaleInvoiceItem> allSales;
  final List<SalesByProductItem> byProduct;
  final List<SalesByCategoryItem> byCategory;
  final List<SalesByCustomerItem> byCustomer;
  final List<CancelledInvoiceItem> cancelledInvoices;
  final List<TaxByProductItem> taxByProduct;
  final List<TaxByCustomerItem> taxByCustomer;
  final ReportDateRange dateRange;

  const SalesReportsData({
    this.summary = const SalesReportsSummary(),
    this.allSales = const [],
    this.byProduct = const [],
    this.byCategory = const [],
    this.byCustomer = const [],
    this.cancelledInvoices = const [],
    this.taxByProduct = const [],
    this.taxByCustomer = const [],
    required this.dateRange,
  });

  /// Filter sales by payment method
  List<SaleInvoiceItem> salesByPaymentMethod(String method) =>
      allSales.where((s) => s.paymentMethod == method).toList();

  List<SaleInvoiceItem> get cashSales => salesByPaymentMethod('cash');
  List<SaleInvoiceItem> get creditSales => salesByPaymentMethod('credit');
  List<SaleInvoiceItem> get cardSales => salesByPaymentMethod('card');
  List<SaleInvoiceItem> get chequeSales => salesByPaymentMethod('cheque');

  SalesReportsData copyWith({
    SalesReportsSummary? summary,
    List<SaleInvoiceItem>? allSales,
    List<SalesByProductItem>? byProduct,
    List<SalesByCategoryItem>? byCategory,
    List<SalesByCustomerItem>? byCustomer,
    List<CancelledInvoiceItem>? cancelledInvoices,
    List<TaxByProductItem>? taxByProduct,
    List<TaxByCustomerItem>? taxByCustomer,
    ReportDateRange? dateRange,
  }) {
    return SalesReportsData(
      summary: summary ?? this.summary,
      allSales: allSales ?? this.allSales,
      byProduct: byProduct ?? this.byProduct,
      byCategory: byCategory ?? this.byCategory,
      byCustomer: byCustomer ?? this.byCustomer,
      cancelledInvoices: cancelledInvoices ?? this.cancelledInvoices,
      taxByProduct: taxByProduct ?? this.taxByProduct,
      taxByCustomer: taxByCustomer ?? this.taxByCustomer,
      dateRange: dateRange ?? this.dateRange,
    );
  }
}

// ==================== BLOC ====================

class SalesReportsBloc
    extends RealtimeBloc<SalesReportsData, SalesReportsEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;

  SalesReportsBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<SalesReportsData> get dataStream {
    // Watch sales AND both return sources so posting/voiding a linked or
    // adjustment (unlinked) return live-refreshes the net-sales figures.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.sales, _db.saleReturns, _db.saleReturnAdjustments},
        )
        .watch()
        .asyncMap((_) => _loadAll());
  }

  @override
  void registerEventHandlers() {
    on<SalesReportsDateRangeChanged>(_onDateRangeChanged);
  }

  Future<void> _onDateRangeChanged(
    SalesReportsDateRangeChanged event,
    Emitter<RealtimeState<SalesReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<SalesReportsData> _loadAll() async {
    final results = await Future.wait([
      _loadAllSales(),
      _loadByProduct(),
      _loadByCategory(),
      _loadByCustomer(),
      _loadCancelledInvoices(),
      _loadTaxByProduct(),
      _loadTaxByCustomer(),
      _loadReturnsTotals(),
    ]);

    final allSales = results[0] as List<SaleInvoiceItem>;
    final byProduct = results[1] as List<SalesByProductItem>;
    final byCategory = results[2] as List<SalesByCategoryItem>;
    final byCustomer = results[3] as List<SalesByCustomerItem>;
    final cancelled = results[4] as List<CancelledInvoiceItem>;
    final taxByProduct = results[5] as List<TaxByProductItem>;
    final taxByCustomer = results[6] as List<TaxByCustomerItem>;
    final returnsTotals = results[7] as ({int totalCents, int count});

    // Calculate summary from allSales (only completed/non-voided)
    int totalSales = 0;
    int totalDiscount = 0;
    int totalTax = 0;
    int totalPaid = 0;
    int cashSales = 0;
    int creditSales = 0;
    int cardSales = 0;
    int chequeSales = 0;

    for (final s in allSales) {
      totalSales += s.totalCents;
      totalDiscount += s.discountCents;
      totalTax += s.taxCents;
      totalPaid += s.paidAmountCents;
      switch (s.paymentMethod) {
        case 'cash':
          cashSales += s.totalCents;
        case 'credit':
          creditSales += s.totalCents;
        case 'card':
          cardSales += s.totalCents;
        case 'cheque':
          chequeSales += s.totalCents;
      }
    }

    return SalesReportsData(
      summary: SalesReportsSummary(
        totalSalesCents: totalSales,
        totalDiscountCents: totalDiscount,
        totalTaxCents: totalTax,
        totalPaidCents: totalPaid,
        invoiceCount: allSales.length,
        cancelledCount: cancelled.length,
        cashSalesCents: cashSales,
        creditSalesCents: creditSales,
        cardSalesCents: cardSales,
        chequeSalesCents: chequeSales,
        totalReturnsCents: returnsTotals.totalCents,
        returnCount: returnsTotals.count,
      ),
      allSales: allSales,
      byProduct: byProduct,
      byCategory: byCategory,
      byCustomer: byCustomer,
      cancelledInvoices: cancelled,
      taxByProduct: taxByProduct,
      taxByCustomer: taxByCustomer,
      dateRange: _dateRange,
    );
  }

  /// Total value + count of ALL posted sale returns in the period, combining
  /// linked (invoice-based) returns and adjustment (unlinked) returns. Used to
  /// present net sales (gross − returns) on the summary.
  Future<({int totalCents, int count})> _loadReturnsTotals() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT
        (SELECT COALESCE(SUM(sr.total_cents), 0) FROM sale_returns sr
           WHERE sr.status = 'posted'
             AND sr.return_date >= ? AND sr.return_date <= ?)
        + (SELECT COALESCE(SUM(sra.total_cents), 0) FROM sale_return_adjustments sra
           WHERE sra.status = 'posted'
             AND sra.return_date >= ? AND sra.return_date <= ?) AS total_cents,
        (SELECT COUNT(*) FROM sale_returns sr
           WHERE sr.status = 'posted'
             AND sr.return_date >= ? AND sr.return_date <= ?)
        + (SELECT COUNT(*) FROM sale_return_adjustments sra
           WHERE sra.status = 'posted'
             AND sra.return_date >= ? AND sra.return_date <= ?) AS return_count
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.saleReturns, _db.saleReturnAdjustments},
        )
        .get();

    if (rows.isEmpty) return (totalCents: 0, count: 0);
    return (
      totalCents: rows.first.read<int>('total_cents'),
      count: rows.first.read<int>('return_count'),
    );
  }

  Future<List<SaleInvoiceItem>> _loadAllSales() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT 
        s.id AS sale_id,
        s.invoice_number,
        c.name AS customer_name,
        COALESCE(
          (
            SELECT e.name
            FROM employees e
            WHERE e.id = u.employee_id OR e.user_id = u.id
            ORDER BY CASE WHEN e.id = u.employee_id THEN 0 ELSE 1 END
            LIMIT 1
          ),
          u.username
        ) AS cashier_name,
        cs.shift_number AS cashier_shift_number,
        s.subtotal_cents,
        s.discount_cents,
        s.tax_cents,
        s.total_cents,
        s.paid_amount_cents,
        s.payment_method,
        (
          SELECT GROUP_CONCAT(DISTINCT ci.status)
          FROM cheque_instruments ci
          WHERE ci.source_table = 'sale' AND ci.source_id = s.id
        ) AS cheque_statuses,
        s.status,
        s.sale_date
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN cashier_shifts cs ON cs.id = s.cashier_shift_id
      LEFT JOIN users u ON u.id = cs.cashier_user_id
      WHERE s.status != 'voided'
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      ORDER BY s.sale_date DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.sales,
            _db.customers,
            _db.cashierShifts,
            _db.users,
            _db.employees,
            _db.chequeInstruments,
          },
        )
        .get();

    return rows.map((row) {
      return SaleInvoiceItem(
        saleId: row.read<int>('sale_id'),
        invoiceNumber: row.read<String>('invoice_number'),
        customerName: row.readNullable<String>('customer_name'),
        cashierName: row.readNullable<String>('cashier_name'),
        cashierShiftNumber: row.readNullable<String>('cashier_shift_number'),
        subtotalCents: row.read<int>('subtotal_cents'),
        discountCents: row.read<int>('discount_cents'),
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
        paidAmountCents: row.read<int>('paid_amount_cents'),
        paymentMethod: row.read<String>('payment_method'),
        chequeStatuses: row.readNullable<String>('cheque_statuses'),
        status: row.read<String>('status'),
        saleDate: DateTime.parse(row.read<String>('sale_date')),
      );
    }).toList();
  }

  Future<List<SalesByProductItem>> _loadByProduct() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT 
        p.id AS product_id,
        p.name AS product_name,
        pc.name AS category_name,
        COALESCE(SUM(si.quantity), 0) AS total_quantity,
        COALESCE(SUM(si.total_cents), 0) AS total_sales_cents,
        COALESCE(SUM(si.discount_cents), 0) AS total_discount_cents,
        COALESCE(SUM(si.tax_cents), 0) AS total_tax_cents,
        COUNT(DISTINCT s.id) AS invoice_count
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      INNER JOIN products p ON p.id = si.product_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id
      WHERE s.status != 'voided'
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY p.id
      ORDER BY total_sales_cents DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.sales,
            _db.saleItems,
            _db.products,
            _db.productCategories,
          },
        )
        .get();

    return rows.map((row) {
      return SalesByProductItem(
        productId: row.read<int>('product_id'),
        productName: row.read<String>('product_name'),
        categoryName: row.readNullable<String>('category_name'),
        totalQuantity: row.read<int>('total_quantity'),
        totalSalesCents: row.read<int>('total_sales_cents'),
        totalDiscountCents: row.read<int>('total_discount_cents'),
        totalTaxCents: row.read<int>('total_tax_cents'),
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  Future<List<SalesByCategoryItem>> _loadByCategory() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT 
        COALESCE(pc.id, 0) AS category_id,
        COALESCE(pc.name, 'Uncategorized') AS category_name,
        COALESCE(SUM(si.quantity), 0) AS total_quantity,
        COALESCE(SUM(si.total_cents), 0) AS total_sales_cents,
        COALESCE(SUM(si.discount_cents), 0) AS total_discount_cents,
        COALESCE(SUM(si.tax_cents), 0) AS total_tax_cents,
        COUNT(DISTINCT p.id) AS product_count,
        COUNT(DISTINCT s.id) AS invoice_count
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      INNER JOIN products p ON p.id = si.product_id
      LEFT JOIN product_categories pc ON pc.id = p.category_id
      WHERE s.status != 'voided'
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY COALESCE(pc.id, 0)
      ORDER BY total_sales_cents DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.sales,
            _db.saleItems,
            _db.products,
            _db.productCategories,
          },
        )
        .get();

    return rows.map((row) {
      return SalesByCategoryItem(
        categoryId: row.read<int>('category_id'),
        categoryName: row.read<String>('category_name'),
        totalQuantity: row.read<int>('total_quantity'),
        totalSalesCents: row.read<int>('total_sales_cents'),
        totalDiscountCents: row.read<int>('total_discount_cents'),
        totalTaxCents: row.read<int>('total_tax_cents'),
        productCount: row.read<int>('product_count'),
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  Future<List<SalesByCustomerItem>> _loadByCustomer() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT 
        c.id AS customer_id,
        c.name AS customer_name,
        COALESCE(SUM(s.total_cents), 0) AS total_sales_cents,
        COALESCE(SUM(s.discount_cents), 0) AS total_discount_cents,
        COALESCE(SUM(s.tax_cents), 0) AS total_tax_cents,
        COUNT(s.id) AS invoice_count,
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
      ORDER BY total_sales_cents DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.sales, _db.saleItems, _db.customers},
        )
        .get();

    return rows.map((row) {
      final lastDateStr = row.readNullable<String>('last_sale_date');
      return SalesByCustomerItem(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        totalSalesCents: row.read<int>('total_sales_cents'),
        totalDiscountCents: row.read<int>('total_discount_cents'),
        totalTaxCents: row.read<int>('total_tax_cents'),
        invoiceCount: row.read<int>('invoice_count'),
        totalQuantity: row.read<int>('total_quantity'),
        lastSaleDate: lastDateStr != null
            ? DateTime.tryParse(lastDateStr)
            : null,
      );
    }).toList();
  }

  Future<List<CancelledInvoiceItem>> _loadCancelledInvoices() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT 
        s.id AS sale_id,
        s.invoice_number,
        c.name AS customer_name,
        s.total_cents,
        s.status,
        s.sale_date,
        s.notes
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.status = 'voided'
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      ORDER BY s.sale_date DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.sales, _db.customers},
        )
        .get();

    return rows.map((row) {
      return CancelledInvoiceItem(
        saleId: row.read<int>('sale_id'),
        invoiceNumber: row.read<String>('invoice_number'),
        customerName: row.readNullable<String>('customer_name'),
        totalCents: row.read<int>('total_cents'),
        status: row.read<String>('status'),
        saleDate: DateTime.parse(row.read<String>('sale_date')),
        notes: row.readNullable<String>('notes'),
      );
    }).toList();
  }

  Future<List<TaxByProductItem>> _loadTaxByProduct() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT 
        p.id AS product_id,
        p.name AS product_name,
        COALESCE(SUM(si.total_cents), 0) AS total_sales_cents,
        COALESCE(SUM(si.tax_cents), 0) AS total_tax_cents,
        p.sales_tax_rate_bps AS tax_rate_bps,
        COALESCE(SUM(si.quantity), 0) AS total_quantity
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      INNER JOIN products p ON p.id = si.product_id
      WHERE s.status != 'voided'
        AND si.tax_cents > 0
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY p.id
      ORDER BY total_tax_cents DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.sales, _db.saleItems, _db.products},
        )
        .get();

    return rows.map((row) {
      return TaxByProductItem(
        productId: row.read<int>('product_id'),
        productName: row.read<String>('product_name'),
        totalSalesCents: row.read<int>('total_sales_cents'),
        totalTaxCents: row.read<int>('total_tax_cents'),
        taxRateBps: row.read<int>('tax_rate_bps'),
        totalQuantity: row.read<int>('total_quantity'),
      );
    }).toList();
  }

  Future<List<TaxByCustomerItem>> _loadTaxByCustomer() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT 
        c.id AS customer_id,
        c.name AS customer_name,
        COALESCE(SUM(s.total_cents), 0) AS total_sales_cents,
        COALESCE(SUM(s.tax_cents), 0) AS total_tax_cents,
        COUNT(s.id) AS invoice_count
      FROM sales s
      INNER JOIN customers c ON c.id = s.customer_id
      WHERE s.status != 'voided'
        AND s.tax_cents > 0
        AND s.customer_id IS NOT NULL
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY c.id
      ORDER BY total_tax_cents DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.sales, _db.customers},
        )
        .get();

    return rows.map((row) {
      return TaxByCustomerItem(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        totalSalesCents: row.read<int>('total_sales_cents'),
        totalTaxCents: row.read<int>('total_tax_cents'),
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }
}
