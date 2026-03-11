import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class ProfitReportsEvent extends RealtimeEvent {
  const ProfitReportsEvent();
}

class ProfitReportsDateRangeChanged extends ProfitReportsEvent {
  final ReportDateRange dateRange;
  const ProfitReportsDateRangeChanged(this.dateRange);
}

// ==================== DATA MODELS ====================

/// Profit breakdown by product
class ProfitByProductItem {
  final int productId;
  final String productName;
  final String? categoryName;
  final int totalQuantity;
  final int totalRevenueCents;
  final int totalCostCents;
  final int totalProfitCents;
  final int totalDiscountCents;
  final double profitMarginPercent;
  final int invoiceCount;

  const ProfitByProductItem({
    required this.productId,
    required this.productName,
    this.categoryName,
    required this.totalQuantity,
    required this.totalRevenueCents,
    required this.totalCostCents,
    required this.totalProfitCents,
    required this.totalDiscountCents,
    required this.profitMarginPercent,
    required this.invoiceCount,
  });
}

/// Profit breakdown by category
class ProfitByCategoryItem {
  final int categoryId;
  final String categoryName;
  final int productCount;
  final int totalQuantity;
  final int totalRevenueCents;
  final int totalCostCents;
  final int totalProfitCents;
  final double profitMarginPercent;
  final int invoiceCount;

  const ProfitByCategoryItem({
    required this.categoryId,
    required this.categoryName,
    required this.productCount,
    required this.totalQuantity,
    required this.totalRevenueCents,
    required this.totalCostCents,
    required this.totalProfitCents,
    required this.profitMarginPercent,
    required this.invoiceCount,
  });
}

/// Profit breakdown by customer
class ProfitByCustomerItem {
  final int customerId;
  final String customerName;
  final int totalRevenueCents;
  final int totalCostCents;
  final int totalProfitCents;
  final double profitMarginPercent;
  final int invoiceCount;

  const ProfitByCustomerItem({
    required this.customerId,
    required this.customerName,
    required this.totalRevenueCents,
    required this.totalCostCents,
    required this.totalProfitCents,
    required this.profitMarginPercent,
    required this.invoiceCount,
  });
}

/// Profit breakdown by invoice
class ProfitByInvoiceItem {
  final int saleId;
  final String invoiceNumber;
  final String? customerName;
  final int revenueCents;
  final int costCents;
  final int profitCents;
  final int discountCents;
  final double profitMarginPercent;
  final DateTime saleDate;
  final String paymentMethod;

  const ProfitByInvoiceItem({
    required this.saleId,
    required this.invoiceNumber,
    this.customerName,
    required this.revenueCents,
    required this.costCents,
    required this.profitCents,
    required this.discountCents,
    required this.profitMarginPercent,
    required this.saleDate,
    required this.paymentMethod,
  });
}

/// Overall sales & profit summary
class ProfitReportsSummary {
  final int totalRevenueCents;
  final int totalCostCents;
  final int totalProfitCents;
  final int totalDiscountCents;
  final int totalTaxCents;
  final double profitMarginPercent;
  final int invoiceCount;
  final int productCount;

  const ProfitReportsSummary({
    this.totalRevenueCents = 0,
    this.totalCostCents = 0,
    this.totalProfitCents = 0,
    this.totalDiscountCents = 0,
    this.totalTaxCents = 0,
    this.profitMarginPercent = 0.0,
    this.invoiceCount = 0,
    this.productCount = 0,
  });
}

class ProfitReportsData {
  final ProfitReportsSummary summary;
  final List<ProfitByProductItem> byProduct;
  final List<ProfitByCategoryItem> byCategory;
  final List<ProfitByCustomerItem> byCustomer;
  final List<ProfitByInvoiceItem> byInvoice;
  final ReportDateRange dateRange;

  const ProfitReportsData({
    this.summary = const ProfitReportsSummary(),
    this.byProduct = const [],
    this.byCategory = const [],
    this.byCustomer = const [],
    this.byInvoice = const [],
    required this.dateRange,
  });

  ProfitReportsData copyWith({
    ProfitReportsSummary? summary,
    List<ProfitByProductItem>? byProduct,
    List<ProfitByCategoryItem>? byCategory,
    List<ProfitByCustomerItem>? byCustomer,
    List<ProfitByInvoiceItem>? byInvoice,
    ReportDateRange? dateRange,
  }) {
    return ProfitReportsData(
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

class ProfitReportsBloc
    extends RealtimeBloc<ProfitReportsData, ProfitReportsEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;

  ProfitReportsBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<ProfitReportsData> get dataStream {
    return _db.select(_db.sales).watch().asyncMap((_) => _loadAll());
  }

  @override
  void registerEventHandlers() {
    on<ProfitReportsDateRangeChanged>(_onDateRangeChanged);
  }

  Future<void> _onDateRangeChanged(
    ProfitReportsDateRangeChanged event,
    Emitter<RealtimeState<ProfitReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<ProfitReportsData> _loadAll() async {
    final results = await Future.wait([
      _loadByProduct(),
      _loadByCategory(),
      _loadByCustomer(),
      _loadByInvoice(),
    ]);

    final byProduct = results[0] as List<ProfitByProductItem>;
    final byCategory = results[1] as List<ProfitByCategoryItem>;
    final byCustomer = results[2] as List<ProfitByCustomerItem>;
    final byInvoice = results[3] as List<ProfitByInvoiceItem>;

    // Calculate summary from byInvoice
    int totalRevenue = 0;
    int totalCost = 0;
    int totalDiscount = 0;

    for (final inv in byInvoice) {
      totalRevenue += inv.revenueCents;
      totalCost += inv.costCents;
      totalDiscount += inv.discountCents;
    }

    final totalProfit = totalRevenue - totalCost;
    final margin = totalRevenue > 0 ? (totalProfit / totalRevenue) * 100 : 0.0;

    // Get total tax separately
    final taxResult = await _loadTotalTax();

    return ProfitReportsData(
      summary: ProfitReportsSummary(
        totalRevenueCents: totalRevenue,
        totalCostCents: totalCost,
        totalProfitCents: totalProfit,
        totalDiscountCents: totalDiscount,
        totalTaxCents: taxResult,
        profitMarginPercent: margin,
        invoiceCount: byInvoice.length,
        productCount: byProduct.length,
      ),
      byProduct: byProduct,
      byCategory: byCategory,
      byCustomer: byCustomer,
      byInvoice: byInvoice,
      dateRange: _dateRange,
    );
  }

  Future<int> _loadTotalTax() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(s.tax_cents), 0) AS total_tax
      FROM sales s
      WHERE s.status NOT IN ('voided', 'draft')
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.sales},
    ).get();

    return rows.isNotEmpty ? rows.first.read<int>('total_tax') : 0;
  }

  /// Profit by product: revenue = SUM(si.total_cents), cost = SUM(cost_cents * quantity)
  /// Uses COALESCE to pick variant cost first, then product cost
  Future<List<ProfitByProductItem>> _loadByProduct() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        pr.id AS product_id,
        pr.name AS product_name,
        pc.name AS category_name,
        SUM(si.quantity) AS total_quantity,
        SUM(si.total_cents) AS total_revenue_cents,
        SUM(si.discount_cents) AS total_discount_cents,
        SUM(
          COALESCE(pv.cost_cents, pr.cost_cents) * si.quantity
        ) AS total_cost_cents,
        COUNT(DISTINCT s.id) AS invoice_count
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      INNER JOIN products pr ON pr.id = si.product_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      LEFT JOIN product_categories pc ON pc.id = pr.category_id
      WHERE s.status NOT IN ('voided', 'draft')
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY pr.id
      ORDER BY (SUM(si.total_cents) - SUM(COALESCE(pv.cost_cents, pr.cost_cents) * si.quantity)) DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.saleItems, _db.sales, _db.products, _db.productVariants, _db.productCategories},
    ).get();

    return rows.map((row) {
      final revenue = row.read<int>('total_revenue_cents');
      final cost = row.read<int>('total_cost_cents');
      final profit = revenue - cost;
      return ProfitByProductItem(
        productId: row.read<int>('product_id'),
        productName: row.read<String>('product_name'),
        categoryName: row.readNullable<String>('category_name'),
        totalQuantity: row.read<int>('total_quantity'),
        totalRevenueCents: revenue,
        totalCostCents: cost,
        totalProfitCents: profit,
        totalDiscountCents: row.read<int>('total_discount_cents'),
        profitMarginPercent: revenue > 0 ? (profit / revenue) * 100 : 0.0,
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  Future<List<ProfitByCategoryItem>> _loadByCategory() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        COALESCE(pc.id, 0) AS category_id,
        COALESCE(pc.name, 'Uncategorized') AS category_name,
        COUNT(DISTINCT pr.id) AS product_count,
        SUM(si.quantity) AS total_quantity,
        SUM(si.total_cents) AS total_revenue_cents,
        SUM(
          COALESCE(pv.cost_cents, pr.cost_cents) * si.quantity
        ) AS total_cost_cents,
        COUNT(DISTINCT s.id) AS invoice_count
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      INNER JOIN products pr ON pr.id = si.product_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      LEFT JOIN product_categories pc ON pc.id = pr.category_id
      WHERE s.status NOT IN ('voided', 'draft')
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY COALESCE(pc.id, 0)
      ORDER BY (SUM(si.total_cents) - SUM(COALESCE(pv.cost_cents, pr.cost_cents) * si.quantity)) DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.saleItems, _db.sales, _db.products, _db.productVariants, _db.productCategories},
    ).get();

    return rows.map((row) {
      final revenue = row.read<int>('total_revenue_cents');
      final cost = row.read<int>('total_cost_cents');
      final profit = revenue - cost;
      return ProfitByCategoryItem(
        categoryId: row.read<int>('category_id'),
        categoryName: row.read<String>('category_name'),
        productCount: row.read<int>('product_count'),
        totalQuantity: row.read<int>('total_quantity'),
        totalRevenueCents: revenue,
        totalCostCents: cost,
        totalProfitCents: profit,
        profitMarginPercent: revenue > 0 ? (profit / revenue) * 100 : 0.0,
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  Future<List<ProfitByCustomerItem>> _loadByCustomer() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        COALESCE(c.id, 0) AS customer_id,
        COALESCE(c.name, 'Walk-in') AS customer_name,
        SUM(si.total_cents) AS total_revenue_cents,
        SUM(
          COALESCE(pv.cost_cents, pr.cost_cents) * si.quantity
        ) AS total_cost_cents,
        COUNT(DISTINCT s.id) AS invoice_count
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      INNER JOIN products pr ON pr.id = si.product_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.status NOT IN ('voided', 'draft')
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY COALESCE(c.id, 0)
      ORDER BY (SUM(si.total_cents) - SUM(COALESCE(pv.cost_cents, pr.cost_cents) * si.quantity)) DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.saleItems, _db.sales, _db.products, _db.productVariants, _db.customers},
    ).get();

    return rows.map((row) {
      final revenue = row.read<int>('total_revenue_cents');
      final cost = row.read<int>('total_cost_cents');
      final profit = revenue - cost;
      return ProfitByCustomerItem(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        totalRevenueCents: revenue,
        totalCostCents: cost,
        totalProfitCents: profit,
        profitMarginPercent: revenue > 0 ? (profit / revenue) * 100 : 0.0,
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  Future<List<ProfitByInvoiceItem>> _loadByInvoice() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        s.id AS sale_id,
        s.invoice_number,
        c.name AS customer_name,
        s.total_cents AS revenue_cents,
        s.discount_cents,
        s.sale_date,
        s.payment_method,
        COALESCE(cost_q.total_cost, 0) AS cost_cents
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN (
        SELECT 
          si.sale_id,
          SUM(COALESCE(pv.cost_cents, pr.cost_cents) * si.quantity) AS total_cost
        FROM sale_items si
        INNER JOIN products pr ON pr.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        GROUP BY si.sale_id
      ) cost_q ON cost_q.sale_id = s.id
      WHERE s.status NOT IN ('voided', 'draft')
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      ORDER BY (s.total_cents - COALESCE(cost_q.total_cost, 0)) DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.sales, _db.customers, _db.saleItems, _db.products, _db.productVariants},
    ).get();

    return rows.map((row) {
      final revenue = row.read<int>('revenue_cents');
      final cost = row.read<int>('cost_cents');
      final profit = revenue - cost;
      return ProfitByInvoiceItem(
        saleId: row.read<int>('sale_id'),
        invoiceNumber: row.read<String>('invoice_number'),
        customerName: row.readNullable<String>('customer_name'),
        revenueCents: revenue,
        costCents: cost,
        profitCents: profit,
        discountCents: row.read<int>('discount_cents'),
        profitMarginPercent: revenue > 0 ? (profit / revenue) * 100 : 0.0,
        saleDate: DateTime.parse(row.read<String>('sale_date')),
        paymentMethod: row.read<String>('payment_method'),
      );
    }).toList();
  }
}
