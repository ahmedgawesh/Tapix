import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/reporting/ratio_helper.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class DiscountReportsEvent extends RealtimeEvent {
  const DiscountReportsEvent();
}

class DiscountReportsDateRangeChanged extends DiscountReportsEvent {
  final ReportDateRange dateRange;
  const DiscountReportsDateRangeChanged(this.dateRange);
}

// ==================== DATA MODELS ====================

/// Discount breakdown by product
class DiscountByProductItem {
  final int productId;
  final String productName;
  final String? categoryName;
  final int totalQuantity;
  final int totalSalesCents;
  final int totalDiscountCents;
  final int invoiceCount;
  final double discountPercent;

  const DiscountByProductItem({
    required this.productId,
    required this.productName,
    this.categoryName,
    required this.totalQuantity,
    required this.totalSalesCents,
    required this.totalDiscountCents,
    required this.invoiceCount,
    required this.discountPercent,
  });
}

/// Discount breakdown by category
class DiscountByCategoryItem {
  final int categoryId;
  final String categoryName;
  final int productCount;
  final int totalQuantity;
  final int totalSalesCents;
  final int totalDiscountCents;
  final int invoiceCount;
  final double discountPercent;

  const DiscountByCategoryItem({
    required this.categoryId,
    required this.categoryName,
    required this.productCount,
    required this.totalQuantity,
    required this.totalSalesCents,
    required this.totalDiscountCents,
    required this.invoiceCount,
    required this.discountPercent,
  });
}

/// Discount breakdown by customer
class DiscountByCustomerItem {
  final int customerId;
  final String customerName;
  final int totalSalesCents;
  final int totalDiscountCents;
  final int invoiceCount;
  final double discountPercent;

  const DiscountByCustomerItem({
    required this.customerId,
    required this.customerName,
    required this.totalSalesCents,
    required this.totalDiscountCents,
    required this.invoiceCount,
    required this.discountPercent,
  });
}

/// Discount breakdown by invoice
class DiscountByInvoiceItem {
  final int saleId;
  final String invoiceNumber;
  final String? customerName;
  final int subtotalCents;
  final int discountCents;
  final int totalCents;
  final DateTime saleDate;
  final String paymentMethod;
  final double discountPercent;

  const DiscountByInvoiceItem({
    required this.saleId,
    required this.invoiceNumber,
    this.customerName,
    required this.subtotalCents,
    required this.discountCents,
    required this.totalCents,
    required this.saleDate,
    required this.paymentMethod,
    required this.discountPercent,
  });
}

/// Summary data
class DiscountReportsSummary {
  final int totalSalesCents;
  final int totalDiscountCents;
  final int invoiceCount;
  final int discountedInvoiceCount;
  final double averageDiscountPercent;

  const DiscountReportsSummary({
    this.totalSalesCents = 0,
    this.totalDiscountCents = 0,
    this.invoiceCount = 0,
    this.discountedInvoiceCount = 0,
    this.averageDiscountPercent = 0.0,
  });
}

class DiscountReportsData {
  final DiscountReportsSummary summary;
  final List<DiscountByProductItem> byProduct;
  final List<DiscountByCategoryItem> byCategory;
  final List<DiscountByCustomerItem> byCustomer;
  final List<DiscountByInvoiceItem> byInvoice;
  final ReportDateRange dateRange;

  const DiscountReportsData({
    this.summary = const DiscountReportsSummary(),
    this.byProduct = const [],
    this.byCategory = const [],
    this.byCustomer = const [],
    this.byInvoice = const [],
    required this.dateRange,
  });

  DiscountReportsData copyWith({
    DiscountReportsSummary? summary,
    List<DiscountByProductItem>? byProduct,
    List<DiscountByCategoryItem>? byCategory,
    List<DiscountByCustomerItem>? byCustomer,
    List<DiscountByInvoiceItem>? byInvoice,
    ReportDateRange? dateRange,
  }) {
    return DiscountReportsData(
      summary: summary ?? this.summary,
      byProduct: byProduct ?? this.byProduct,
      byCategory: byCategory ?? this.byCategory,
      byCustomer: byCustomer ?? this.byCustomer,
      byInvoice: byInvoice ?? this.byInvoice,
      dateRange: dateRange ?? this.dateRange,
    );
  }
}

// ==================== BLOC ====================

class DiscountReportsBloc
    extends RealtimeBloc<DiscountReportsData, DiscountReportsEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;

  DiscountReportsBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<DiscountReportsData> get dataStream {
    return _db.select(_db.sales).watch().asyncMap((_) => _loadAll());
  }

  @override
  void registerEventHandlers() {
    on<DiscountReportsDateRangeChanged>(_onDateRangeChanged);
  }

  Future<void> _onDateRangeChanged(
    DiscountReportsDateRangeChanged event,
    Emitter<RealtimeState<DiscountReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<DiscountReportsData> _loadAll() async {
    final results = await Future.wait([
      _loadByProduct(),
      _loadByCategory(),
      _loadByCustomer(),
      _loadByInvoice(),
    ]);

    final byProduct = results[0] as List<DiscountByProductItem>;
    final byCategory = results[1] as List<DiscountByCategoryItem>;
    final byCustomer = results[2] as List<DiscountByCustomerItem>;
    final byInvoice = results[3] as List<DiscountByInvoiceItem>;

    // Calculate summary
    int totalSales = 0;
    int totalDiscount = 0;
    int invoiceCount = byInvoice.length;
    int discountedCount = 0;

    for (final inv in byInvoice) {
      totalSales += inv.subtotalCents;
      totalDiscount += inv.discountCents;
      if (inv.discountCents > 0) discountedCount++;
    }

    // Phase 7 — percentage via RatioHelper SoT.
    final avgDiscount = RatioHelper.percent(
      numeratorCents: totalDiscount,
      denominatorCents: totalSales,
    );

    return DiscountReportsData(
      summary: DiscountReportsSummary(
        totalSalesCents: totalSales,
        totalDiscountCents: totalDiscount,
        invoiceCount: invoiceCount,
        discountedInvoiceCount: discountedCount,
        averageDiscountPercent: avgDiscount,
      ),
      byProduct: byProduct,
      byCategory: byCategory,
      byCustomer: byCustomer,
      byInvoice: byInvoice,
      dateRange: _dateRange,
    );
  }

  Future<List<DiscountByProductItem>> _loadByProduct() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        pr.id AS product_id,
        pr.name AS product_name,
        pc.name AS category_name,
        SUM(si.quantity) AS total_quantity,
        SUM(si.subtotal_cents) AS total_sales_cents,
        SUM(si.discount_cents) AS total_discount_cents,
        COUNT(DISTINCT s.id) AS invoice_count
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      INNER JOIN products pr ON pr.id = si.product_id
      LEFT JOIN product_categories pc ON pc.id = pr.category_id
      WHERE s.status NOT IN ('voided', 'draft')
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY pr.id
      HAVING total_discount_cents > 0
      ORDER BY total_discount_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.saleItems, _db.sales, _db.products, _db.productCategories},
    ).get();

    return rows.map((row) {
      final sales = row.read<int>('total_sales_cents');
      final discount = row.read<int>('total_discount_cents');
      return DiscountByProductItem(
        productId: row.read<int>('product_id'),
        productName: row.read<String>('product_name'),
        categoryName: row.readNullable<String>('category_name'),
        totalQuantity: row.read<int>('total_quantity'),
        totalSalesCents: sales,
        totalDiscountCents: discount,
        invoiceCount: row.read<int>('invoice_count'),
        discountPercent: RatioHelper.percent(
          numeratorCents: discount,
          denominatorCents: sales,
        ),
      );
    }).toList();
  }

  Future<List<DiscountByCategoryItem>> _loadByCategory() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        COALESCE(pc.id, 0) AS category_id,
        COALESCE(pc.name, 'Uncategorized') AS category_name,
        COUNT(DISTINCT pr.id) AS product_count,
        SUM(si.quantity) AS total_quantity,
        SUM(si.subtotal_cents) AS total_sales_cents,
        SUM(si.discount_cents) AS total_discount_cents,
        COUNT(DISTINCT s.id) AS invoice_count
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      INNER JOIN products pr ON pr.id = si.product_id
      LEFT JOIN product_categories pc ON pc.id = pr.category_id
      WHERE s.status NOT IN ('voided', 'draft')
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY COALESCE(pc.id, 0)
      HAVING total_discount_cents > 0
      ORDER BY total_discount_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.saleItems, _db.sales, _db.products, _db.productCategories},
    ).get();

    return rows.map((row) {
      final sales = row.read<int>('total_sales_cents');
      final discount = row.read<int>('total_discount_cents');
      return DiscountByCategoryItem(
        categoryId: row.read<int>('category_id'),
        categoryName: row.read<String>('category_name'),
        productCount: row.read<int>('product_count'),
        totalQuantity: row.read<int>('total_quantity'),
        totalSalesCents: sales,
        totalDiscountCents: discount,
        invoiceCount: row.read<int>('invoice_count'),
        discountPercent: RatioHelper.percent(
          numeratorCents: discount,
          denominatorCents: sales,
        ),
      );
    }).toList();
  }

  Future<List<DiscountByCustomerItem>> _loadByCustomer() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        COALESCE(c.id, 0) AS customer_id,
        COALESCE(c.name, 'Walk-in') AS customer_name,
        SUM(s.subtotal_cents) AS total_sales_cents,
        SUM(s.discount_cents) AS total_discount_cents,
        COUNT(s.id) AS invoice_count
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.status NOT IN ('voided', 'draft')
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY COALESCE(c.id, 0)
      HAVING total_discount_cents > 0
      ORDER BY total_discount_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.sales, _db.customers},
    ).get();

    return rows.map((row) {
      final sales = row.read<int>('total_sales_cents');
      final discount = row.read<int>('total_discount_cents');
      return DiscountByCustomerItem(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        totalSalesCents: sales,
        totalDiscountCents: discount,
        invoiceCount: row.read<int>('invoice_count'),
        discountPercent: RatioHelper.percent(
          numeratorCents: discount,
          denominatorCents: sales,
        ),
      );
    }).toList();
  }

  Future<List<DiscountByInvoiceItem>> _loadByInvoice() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        s.id AS sale_id,
        s.invoice_number,
        c.name AS customer_name,
        s.subtotal_cents,
        s.discount_cents,
        s.total_cents,
        s.sale_date,
        s.payment_method
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.status NOT IN ('voided', 'draft')
        AND s.discount_cents > 0
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      ORDER BY s.discount_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.sales, _db.customers},
    ).get();

    return rows.map((row) {
      final subtotal = row.read<int>('subtotal_cents');
      final discount = row.read<int>('discount_cents');
      return DiscountByInvoiceItem(
        saleId: row.read<int>('sale_id'),
        invoiceNumber: row.read<String>('invoice_number'),
        customerName: row.readNullable<String>('customer_name'),
        subtotalCents: subtotal,
        discountCents: discount,
        totalCents: row.read<int>('total_cents'),
        saleDate: DateTime.parse(row.read<String>('sale_date')),
        paymentMethod: row.read<String>('payment_method'),
        discountPercent: RatioHelper.percent(
          numeratorCents: discount,
          denominatorCents: subtotal,
        ),
      );
    }).toList();
  }
}
