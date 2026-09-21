import '../../../../core/services/business/warehouse_read_scope.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/business/document_posting_scope.dart';
import '../../../../core/services/business/warehouse_document_scope.dart';
import '../../../../core/services/reporting/ratio_helper.dart';
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
  final WarehouseReadScope? warehouseScope;
  ReportDateRange _dateRange;

  // Exact COGS expressions shared by every profit breakdown. FIFO reads the
  // frozen batch-consumption ledger, WAC reads the posting snapshot, and
  // service/non-stock products always contribute zero inventory cost.
  static const _saleCostSql = '''
    CASE
      WHEN pr.track_inventory = 0 THEN 0
      WHEN EXISTS (
        SELECT 1 FROM batch_consumptions bc
        WHERE bc.sale_item_id = si.id AND bc.direction = 'out'
          AND bc.consumption_type = 'sale'
      ) THEN (
        SELECT COALESCE(SUM(CAST(ROUND(1.0 * bc.quantity * bc.unit_cost_cents / si.quantity_scale) AS INTEGER)), 0)
        FROM batch_consumptions bc
        WHERE bc.sale_item_id = si.id AND bc.direction = 'out'
          AND bc.consumption_type = 'sale'
      )
      ELSE CAST(ROUND(1.0 * COALESCE(si.cost_cents, pv.cost_cents, pr.cost_cents)
                      * si.quantity / si.quantity_scale) AS INTEGER)
    END
  ''';

  static const _linkedReturnCostSql = '''
    CASE
      WHEN pr.track_inventory = 0 THEN 0
      WHEN EXISTS (
        SELECT 1 FROM batch_consumptions bc
        WHERE bc.sale_return_item_id = sri.id AND bc.direction = 'in'
          AND bc.consumption_type = 'sale_return_reverse'
      ) THEN (
        SELECT COALESCE(SUM(CAST(ROUND(1.0 * bc.quantity * bc.unit_cost_cents / sri.quantity_scale) AS INTEGER)), 0)
        FROM batch_consumptions bc
        WHERE bc.sale_return_item_id = sri.id AND bc.direction = 'in'
          AND bc.consumption_type = 'sale_return_reverse'
      )
      ELSE CAST(ROUND(1.0 * COALESCE(sri.unit_cost_at_post_cents, si.cost_cents,
                    pv.cost_cents, pr.cost_cents) * sri.quantity
                    / sri.quantity_scale) AS INTEGER)
    END
  ''';

  static const _adjustmentReturnCostSql = '''
    CASE WHEN pr.track_inventory = 0 THEN 0
         ELSE CAST(ROUND(1.0 * COALESCE(srai.unit_cost_at_post_cents,
                       srai.unit_cost_cents) * srai.quantity
                       / srai.quantity_scale) AS INTEGER)
    END
  ''';

  ProfitReportsBloc(
    this._db, {
    String defaultDateRange = 'month',
    this.warehouseScope,
  }) : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
       super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<ProfitReportsData> get dataStream {
    // Watch every table that can change revenue or frozen COGS.
    final trigger = _db
        .customSelect(
          'SELECT 1 AS _t',
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.sales,
            _db.saleItems,
            _db.saleReturns,
            _db.saleReturnItems,
            _db.saleReturnAdjustments,
            _db.saleReturnAdjustmentItems,
            _db.batchConsumptions,
            _db.products,
          },
        )
        .watch();
    return trigger.asyncMap(
      (_) => WarehouseReadScope.snapshot(_db, warehouseScope, _loadAll),
    );
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
    // Phase 7 — percentage via RatioHelper SoT.
    final margin = RatioHelper.percent(
      numeratorCents: totalProfit,
      denominatorCents: totalRevenue,
    );

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

    // Net tax = Sales tax − Linked-return tax − Adjustment-return tax.
    // Each source is aggregated independently to avoid any row duplication.
    final rows = await _db
        .customSelect(
          '''
      SELECT
        (SELECT COALESCE(SUM(s.tax_cents), 0)
           FROM ${warehouseScope?.documents(InventoryPostingDocument.sale) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} s
          WHERE s.status = 'completed'
            AND s.sale_date >= ? AND s.sale_date <= ?)
        -
        (SELECT COALESCE(SUM(sri.tax_cents), 0)
           FROM sale_return_items sri
           INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr ON sr.id = sri.return_id
          WHERE sr.status = 'posted'
            AND sr.return_date >= ? AND sr.return_date <= ?)
        -
        (SELECT COALESCE(SUM(srai.tax_cents), 0)
           FROM sale_return_adjustment_items srai
           INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra ON sra.id = srai.return_id
          WHERE sra.status = 'posted'
            AND sra.return_date >= ? AND sra.return_date <= ?)
        AS total_tax
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.sales,
            _db.saleReturnItems,
            _db.saleReturns,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
          },
        )
        .get();

    return rows.isNotEmpty ? rows.first.read<int>('total_tax') : 0;
  }

  /// Profit by product.
  ///
  /// NET formula (matches journal entries):
  ///   Net Revenue = Sales − Linked Returns − Adjustment Returns
  ///   Net COGS    = Sales COGS − Linked Returns COGS − Adjustment Returns COGS
  ///   Profit      = Net Revenue − Net COGS
  ///
  /// Implementation notes:
  /// - Uses UNION ALL so each source is aggregated independently (no row duplication).
  /// - Linked returns use the ORIGINAL cost snapshot on sale_items (sri.sale_item_id → si).
  /// - Adjustment returns are treated as independent negative sales (use srai.unit_cost_cents).
  /// - invoice_count uses a distinct transaction key per source ('S'/'LR'/'AR').
  Future<List<ProfitByProductItem>> _loadByProduct() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT
        product_id,
        MAX(product_name) AS product_name,
        MAX(category_name) AS category_name,
        SUM(qty) AS total_quantity,
        SUM(revenue_cents) AS total_revenue_cents,
        SUM(discount_cents) AS total_discount_cents,
        SUM(cost_cents) AS total_cost_cents,
        COUNT(DISTINCT tx_key) AS invoice_count
      FROM (
        -- (1) Sales: positive revenue & COGS
        SELECT
          pr.id AS product_id,
          pr.name AS product_name,
          pc.name AS category_name,
          si.quantity AS qty,
          (si.total_cents - si.tax_cents) AS revenue_cents,
          si.discount_cents AS discount_cents,
          $_saleCostSql AS cost_cents,
          ('S' || s.id) AS tx_key
        FROM sale_items si
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.sale) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} s ON s.id = si.sale_id
        INNER JOIN products pr ON pr.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        LEFT JOIN product_categories pc ON pc.id = pr.category_id
        WHERE s.status = 'completed'
          AND s.sale_date >= ? AND s.sale_date <= ?

        UNION ALL

        -- (2) Linked returns: subtract original sale's revenue & original cost
        SELECT
          pr.id,
          pr.name,
          pc.name,
          -sri.quantity,
          -(sri.refund_cents - sri.tax_cents),
          -sri.discount_cents,
          -($_linkedReturnCostSql),
          ('LR' || sr.id)
        FROM sale_return_items sri
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr ON sr.id = sri.return_id
        INNER JOIN sale_items si ON si.id = sri.sale_item_id
        INNER JOIN products pr ON pr.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        LEFT JOIN product_categories pc ON pc.id = pr.category_id
        WHERE sr.status = 'posted'
          AND sr.return_date >= ? AND sr.return_date <= ?

        UNION ALL

        -- (3) Adjustment returns: independent negative sales (frozen unit_cost_cents)
        SELECT
          pr.id,
          pr.name,
          pc.name,
          -srai.quantity,
          -(srai.total_cents - srai.tax_cents),
          -srai.discount_cents,
          -($_adjustmentReturnCostSql),
          ('AR' || sra.id)
        FROM sale_return_adjustment_items srai
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra ON sra.id = srai.return_id
        INNER JOIN products pr ON pr.id = srai.product_id
        LEFT JOIN product_categories pc ON pc.id = pr.category_id
        WHERE sra.status = 'posted'
          AND sra.return_date >= ? AND sra.return_date <= ?
      ) u
      GROUP BY product_id
      ORDER BY (SUM(revenue_cents) - SUM(cost_cents)) DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleItems,
            _db.sales,
            _db.products,
            _db.productVariants,
            _db.productCategories,
            _db.saleReturnItems,
            _db.saleReturns,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
          },
        )
        .get();

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
        profitMarginPercent: RatioHelper.percent(
          numeratorCents: profit,
          denominatorCents: revenue,
        ),
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  /// Profit by category — net of linked + adjustment returns (see _loadByProduct docs).
  Future<List<ProfitByCategoryItem>> _loadByCategory() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT
        category_id,
        MAX(category_name) AS category_name,
        COUNT(DISTINCT product_id) AS product_count,
        SUM(qty) AS total_quantity,
        SUM(revenue_cents) AS total_revenue_cents,
        SUM(cost_cents) AS total_cost_cents,
        COUNT(DISTINCT tx_key) AS invoice_count
      FROM (
        -- (1) Sales
        SELECT
          COALESCE(pc.id, 0) AS category_id,
          COALESCE(pc.name, 'Uncategorized') AS category_name,
          pr.id AS product_id,
          si.quantity AS qty,
          (si.total_cents - si.tax_cents) AS revenue_cents,
          $_saleCostSql AS cost_cents,
          ('S' || s.id) AS tx_key
        FROM sale_items si
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.sale) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} s ON s.id = si.sale_id
        INNER JOIN products pr ON pr.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        LEFT JOIN product_categories pc ON pc.id = pr.category_id
        WHERE s.status = 'completed'
          AND s.sale_date >= ? AND s.sale_date <= ?

        UNION ALL

        -- (2) Linked returns (negative, original cost)
        SELECT
          COALESCE(pc.id, 0),
          COALESCE(pc.name, 'Uncategorized'),
          pr.id,
          -sri.quantity,
          -(sri.refund_cents - sri.tax_cents),
          -($_linkedReturnCostSql),
          ('LR' || sr.id)
        FROM sale_return_items sri
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr ON sr.id = sri.return_id
        INNER JOIN sale_items si ON si.id = sri.sale_item_id
        INNER JOIN products pr ON pr.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        LEFT JOIN product_categories pc ON pc.id = pr.category_id
        WHERE sr.status = 'posted'
          AND sr.return_date >= ? AND sr.return_date <= ?

        UNION ALL

        -- (3) Adjustment returns (negative, frozen unit_cost)
        SELECT
          COALESCE(pc.id, 0),
          COALESCE(pc.name, 'Uncategorized'),
          pr.id,
          -srai.quantity,
          -(srai.total_cents - srai.tax_cents),
          -($_adjustmentReturnCostSql),
          ('AR' || sra.id)
        FROM sale_return_adjustment_items srai
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra ON sra.id = srai.return_id
        INNER JOIN products pr ON pr.id = srai.product_id
        LEFT JOIN product_categories pc ON pc.id = pr.category_id
        WHERE sra.status = 'posted'
          AND sra.return_date >= ? AND sra.return_date <= ?
      ) u
      GROUP BY category_id
      ORDER BY (SUM(revenue_cents) - SUM(cost_cents)) DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleItems,
            _db.sales,
            _db.products,
            _db.productVariants,
            _db.productCategories,
            _db.saleReturnItems,
            _db.saleReturns,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
          },
        )
        .get();

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
        profitMarginPercent: RatioHelper.percent(
          numeratorCents: profit,
          denominatorCents: revenue,
        ),
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  /// Profit by customer — net of linked + adjustment returns (see _loadByProduct docs).
  ///
  /// Linked-return customer = parent sale's customer (s.customer_id).
  /// Adjustment-return customer = sra.customer_id (independent, may be NULL → 'Walk-in').
  Future<List<ProfitByCustomerItem>> _loadByCustomer() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT
        customer_id,
        MAX(customer_name) AS customer_name,
        SUM(revenue_cents) AS total_revenue_cents,
        SUM(cost_cents) AS total_cost_cents,
        COUNT(DISTINCT tx_key) AS invoice_count
      FROM (
        -- (1) Sales
        SELECT
          COALESCE(c.id, 0) AS customer_id,
          COALESCE(c.name, 'Walk-in') AS customer_name,
          (si.total_cents - si.tax_cents) AS revenue_cents,
          $_saleCostSql AS cost_cents,
          ('S' || s.id) AS tx_key
        FROM sale_items si
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.sale) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} s ON s.id = si.sale_id
        INNER JOIN products pr ON pr.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        LEFT JOIN customers c ON c.id = s.customer_id
        WHERE s.status = 'completed'
          AND s.sale_date >= ? AND s.sale_date <= ?

        UNION ALL

        -- (2) Linked returns: customer from parent sale
        SELECT
          COALESCE(c.id, 0),
          COALESCE(c.name, 'Walk-in'),
          -(sri.refund_cents - sri.tax_cents),
          -($_linkedReturnCostSql),
          ('LR' || sr.id)
        FROM sale_return_items sri
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr ON sr.id = sri.return_id
        INNER JOIN sales s ON s.id = sr.sale_id
        INNER JOIN sale_items si ON si.id = sri.sale_item_id
        INNER JOIN products pr ON pr.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        LEFT JOIN customers c ON c.id = s.customer_id
        WHERE sr.status = 'posted'
          AND sr.return_date >= ? AND sr.return_date <= ?

        UNION ALL

        -- (3) Adjustment returns: customer from sra.customer_id (independent)
        SELECT
          COALESCE(c.id, 0),
          COALESCE(c.name, 'Walk-in'),
          -(srai.total_cents - srai.tax_cents),
          -($_adjustmentReturnCostSql),
          ('AR' || sra.id)
        FROM sale_return_adjustment_items srai
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra ON sra.id = srai.return_id
        INNER JOIN products pr ON pr.id = srai.product_id
        LEFT JOIN customers c ON c.id = sra.customer_id
        WHERE sra.status = 'posted'
          AND sra.return_date >= ? AND sra.return_date <= ?
      ) u
      GROUP BY customer_id
      ORDER BY (SUM(revenue_cents) - SUM(cost_cents)) DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleItems,
            _db.sales,
            _db.products,
            _db.productVariants,
            _db.customers,
            _db.saleReturnItems,
            _db.saleReturns,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
          },
        )
        .get();

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
        profitMarginPercent: RatioHelper.percent(
          numeratorCents: profit,
          denominatorCents: revenue,
        ),
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  /// Profit by document for the selected accounting period.
  ///
  /// Sales, linked returns, and adjustment returns are independent rows dated
  /// by their own posting document. Netted-in-place linked returns are wrong
  /// across period boundaries: a return this month for a sale last month would
  /// disappear because the parent sale is outside the filter.
  Future<List<ProfitByInvoiceItem>> _loadByInvoice() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // (A) Completed sales in the period.
    final saleRows = await _db
        .customSelect(
          '''
      SELECT
        s.id AS sale_id,
        s.invoice_number,
        c.name AS customer_name,
        (s.total_cents - s.tax_cents) AS revenue_cents,
        s.discount_cents AS discount_cents,
        s.sale_date,
        s.payment_method,
        COALESCE(cost_q.total_cost, 0) AS cost_cents
      FROM ${warehouseScope?.documents(InventoryPostingDocument.sale) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN (
        SELECT
          si.sale_id,
          SUM($_saleCostSql) AS total_cost
        FROM sale_items si
        INNER JOIN products pr ON pr.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        GROUP BY si.sale_id
      ) cost_q ON cost_q.sale_id = s.id
      WHERE s.status = 'completed'
        AND s.sale_date >= ? AND s.sale_date <= ?
      ORDER BY ((s.total_cents - s.tax_cents)
               - COALESCE(cost_q.total_cost, 0)) DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.sales,
            _db.customers,
            _db.saleItems,
            _db.products,
            _db.productVariants,
            _db.batchConsumptions,
          },
        )
        .get();

    final results = saleRows.map((row) {
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
        profitMarginPercent: RatioHelper.percent(
          numeratorCents: profit,
          denominatorCents: revenue,
        ),
        saleDate: DateTime.parse(row.read<String>('sale_date')),
        paymentMethod: row.read<String>('payment_method'),
      );
    }).toList();

    // (B) Posted linked returns in the period, even if the parent sale was in
    // another period. The large negative key cannot collide with sale or SRA.
    final linkedRows = await _db
        .customSelect(
          '''
      SELECT
        sr.id AS sr_id,
        sr.return_number,
        c.name AS customer_name,
        -SUM(sri.refund_cents - sri.tax_cents) AS revenue_cents,
        -SUM(sri.discount_cents) AS discount_cents,
        -SUM($_linkedReturnCostSql) AS cost_cents,
        sr.return_date,
        sr.refund_method
      FROM ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr
      INNER JOIN sale_return_items sri ON sri.return_id = sr.id
      INNER JOIN sale_items si ON si.id = sri.sale_item_id
      INNER JOIN products pr ON pr.id = si.product_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      INNER JOIN sales s ON s.id = sr.sale_id
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE sr.status = 'posted'
        AND sr.return_date >= ? AND sr.return_date <= ?
      GROUP BY sr.id
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleReturns,
            _db.saleReturnItems,
            _db.saleItems,
            _db.sales,
            _db.products,
            _db.productVariants,
            _db.customers,
            _db.batchConsumptions,
          },
        )
        .get();

    for (final row in linkedRows) {
      final revenue = row.read<int>('revenue_cents');
      final cost = row.read<int>('cost_cents');
      final profit = revenue - cost;
      results.add(
        ProfitByInvoiceItem(
          saleId: -(1000000000 + row.read<int>('sr_id')),
          invoiceNumber: row.read<String>('return_number'),
          customerName: row.readNullable<String>('customer_name'),
          revenueCents: revenue,
          costCents: cost,
          profitCents: profit,
          discountCents: row.read<int>('discount_cents'),
          profitMarginPercent: RatioHelper.percent(
            numeratorCents: profit,
            denominatorCents: revenue,
          ),
          saleDate: DateTime.parse(row.read<String>('return_date')),
          paymentMethod: row.read<String>('refund_method'),
        ),
      );
    }

    // (C) Posted adjustment returns as independent negative rows.
    final adjRows = await _db
        .customSelect(
          '''
      SELECT
        sra.id AS sra_id,
        sra.return_number,
        c.name AS customer_name,
        -SUM(srai.total_cents - srai.tax_cents) AS revenue_cents,
        -SUM(srai.discount_cents) AS discount_cents,
        -SUM($_adjustmentReturnCostSql) AS cost_cents,
        sra.return_date,
        sra.refund_method
      FROM ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra
      INNER JOIN sale_return_adjustment_items srai ON srai.return_id = sra.id
      INNER JOIN products pr ON pr.id = srai.product_id
      LEFT JOIN customers c ON c.id = sra.customer_id
      WHERE sra.status = 'posted'
        AND sra.return_date >= ? AND sra.return_date <= ?
      GROUP BY sra.id
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleReturnAdjustments,
            _db.saleReturnAdjustmentItems,
            _db.products,
            _db.customers,
          },
        )
        .get();

    for (final row in adjRows) {
      final revenue = row.read<int>('revenue_cents');
      final cost = row.read<int>('cost_cents');
      final profit = revenue - cost;
      results.add(
        ProfitByInvoiceItem(
          // Use negative id so SRA rows never collide with real sale ids downstream.
          saleId: -row.read<int>('sra_id'),
          invoiceNumber: row.read<String>('return_number'),
          customerName: row.readNullable<String>('customer_name'),
          revenueCents: revenue,
          costCents: cost,
          profitCents: profit,
          discountCents: row.read<int>('discount_cents'),
          // Margin via SoT — RatioHelper.percent treats `denom == 0` as 0.0
          // (display-safe). Negative revenue (pure return rows) is preserved.
          profitMarginPercent: RatioHelper.percent(
            numeratorCents: profit,
            denominatorCents: revenue,
          ),
          saleDate: DateTime.parse(row.read<String>('return_date')),
          paymentMethod: row.read<String>('refund_method'),
        ),
      );
    }

    results.sort((a, b) => b.profitCents.compareTo(a.profitCents));
    return results;
  }
}
