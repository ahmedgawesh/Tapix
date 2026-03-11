import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class PurchaseReportsEvent extends RealtimeEvent {
  const PurchaseReportsEvent();
}

class PurchaseReportsDateRangeChanged extends PurchaseReportsEvent {
  final ReportDateRange dateRange;
  const PurchaseReportsDateRangeChanged(this.dateRange);
}

// ==================== DATA MODELS ====================

/// A single purchase invoice row for list reports
class PurchaseInvoiceItem {
  final int purchaseId;
  final String purchaseNumber;
  final String supplierName;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int paidAmountCents;
  final String? paymentMethod;
  final String status;
  final DateTime purchaseDate;

  const PurchaseInvoiceItem({
    required this.purchaseId,
    required this.purchaseNumber,
    required this.supplierName,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidAmountCents,
    this.paymentMethod,
    required this.status,
    required this.purchaseDate,
  });
}

/// Purchases grouped by product
class PurchasesByProductItem {
  final int productId;
  final String productName;
  final String? categoryName;
  final int totalQuantity;
  final int totalPurchasesCents;
  final int totalDiscountCents;
  final int totalTaxCents;
  final int invoiceCount;

  const PurchasesByProductItem({
    required this.productId,
    required this.productName,
    this.categoryName,
    required this.totalQuantity,
    required this.totalPurchasesCents,
    required this.totalDiscountCents,
    required this.totalTaxCents,
    required this.invoiceCount,
  });
}

/// Purchases grouped by category
class PurchasesByCategoryItem {
  final int categoryId;
  final String categoryName;
  final int totalQuantity;
  final int totalPurchasesCents;
  final int totalDiscountCents;
  final int totalTaxCents;
  final int productCount;
  final int invoiceCount;

  const PurchasesByCategoryItem({
    required this.categoryId,
    required this.categoryName,
    required this.totalQuantity,
    required this.totalPurchasesCents,
    required this.totalDiscountCents,
    required this.totalTaxCents,
    required this.productCount,
    required this.invoiceCount,
  });
}

/// Purchases grouped by supplier
class PurchasesBySupplierItem {
  final int supplierId;
  final String supplierName;
  final int totalPurchasesCents;
  final int totalDiscountCents;
  final int totalTaxCents;
  final int invoiceCount;
  final int totalQuantity;
  final DateTime? lastPurchaseDate;

  const PurchasesBySupplierItem({
    required this.supplierId,
    required this.supplierName,
    required this.totalPurchasesCents,
    required this.totalDiscountCents,
    required this.totalTaxCents,
    required this.invoiceCount,
    required this.totalQuantity,
    this.lastPurchaseDate,
  });
}

/// Cancelled/voided purchase invoice
class CancelledPurchaseItem {
  final int purchaseId;
  final String purchaseNumber;
  final String supplierName;
  final int totalCents;
  final String status;
  final DateTime purchaseDate;
  final String? notes;

  const CancelledPurchaseItem({
    required this.purchaseId,
    required this.purchaseNumber,
    required this.supplierName,
    required this.totalCents,
    required this.status,
    required this.purchaseDate,
    this.notes,
  });
}

/// Purchase order item
class PurchaseOrderItem {
  final int purchaseId;
  final String purchaseNumber;
  final String supplierName;
  final int totalCents;
  final String status;
  final DateTime purchaseDate;
  final DateTime? dueDate;

  const PurchaseOrderItem({
    required this.purchaseId,
    required this.purchaseNumber,
    required this.supplierName,
    required this.totalCents,
    required this.status,
    required this.purchaseDate,
    this.dueDate,
  });
}

/// Summary data for the purchase reports
class PurchaseReportsSummary {
  final int totalPurchasesCents;
  final int totalDiscountCents;
  final int totalTaxCents;
  final int totalPaidCents;
  final int invoiceCount;
  final int cancelledCount;
  final int cashPurchasesCents;
  final int creditPurchasesCents;
  final int cardPurchasesCents;
  final int chequePurchasesCents;

  const PurchaseReportsSummary({
    this.totalPurchasesCents = 0,
    this.totalDiscountCents = 0,
    this.totalTaxCents = 0,
    this.totalPaidCents = 0,
    this.invoiceCount = 0,
    this.cancelledCount = 0,
    this.cashPurchasesCents = 0,
    this.creditPurchasesCents = 0,
    this.cardPurchasesCents = 0,
    this.chequePurchasesCents = 0,
  });
}

class PurchaseReportsData {
  final PurchaseReportsSummary summary;
  final List<PurchaseInvoiceItem> allPurchases;
  final List<PurchasesByProductItem> byProduct;
  final List<PurchasesByCategoryItem> byCategory;
  final List<PurchasesBySupplierItem> bySupplier;
  final List<CancelledPurchaseItem> cancelledInvoices;
  final List<PurchaseOrderItem> purchaseOrders;
  final ReportDateRange dateRange;

  const PurchaseReportsData({
    this.summary = const PurchaseReportsSummary(),
    this.allPurchases = const [],
    this.byProduct = const [],
    this.byCategory = const [],
    this.bySupplier = const [],
    this.cancelledInvoices = const [],
    this.purchaseOrders = const [],
    required this.dateRange,
  });

  /// Filter purchases by payment method
  List<PurchaseInvoiceItem> purchasesByPaymentMethod(String method) =>
      allPurchases.where((p) => p.paymentMethod == method).toList();

  List<PurchaseInvoiceItem> get cashPurchases => purchasesByPaymentMethod('cash');
  List<PurchaseInvoiceItem> get creditPurchases => purchasesByPaymentMethod('credit');
  List<PurchaseInvoiceItem> get cardPurchases => purchasesByPaymentMethod('card');
  List<PurchaseInvoiceItem> get chequePurchases => purchasesByPaymentMethod('cheque');

  PurchaseReportsData copyWith({
    PurchaseReportsSummary? summary,
    List<PurchaseInvoiceItem>? allPurchases,
    List<PurchasesByProductItem>? byProduct,
    List<PurchasesByCategoryItem>? byCategory,
    List<PurchasesBySupplierItem>? bySupplier,
    List<CancelledPurchaseItem>? cancelledInvoices,
    List<PurchaseOrderItem>? purchaseOrders,
    ReportDateRange? dateRange,
  }) {
    return PurchaseReportsData(
      summary: summary ?? this.summary,
      allPurchases: allPurchases ?? this.allPurchases,
      byProduct: byProduct ?? this.byProduct,
      byCategory: byCategory ?? this.byCategory,
      bySupplier: bySupplier ?? this.bySupplier,
      cancelledInvoices: cancelledInvoices ?? this.cancelledInvoices,
      purchaseOrders: purchaseOrders ?? this.purchaseOrders,
      dateRange: dateRange ?? this.dateRange,
    );
  }
}

// ==================== BLOC ====================

class PurchaseReportsBloc
    extends RealtimeBloc<PurchaseReportsData, PurchaseReportsEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;

  PurchaseReportsBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<PurchaseReportsData> get dataStream {
    return _db.select(_db.purchases).watch().asyncMap((_) => _loadAll());
  }

  @override
  void registerEventHandlers() {
    on<PurchaseReportsDateRangeChanged>(_onDateRangeChanged);
  }

  Future<void> _onDateRangeChanged(
    PurchaseReportsDateRangeChanged event,
    Emitter<RealtimeState<PurchaseReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<PurchaseReportsData> _loadAll() async {
    final results = await Future.wait([
      _loadAllPurchases(),
      _loadByProduct(),
      _loadByCategory(),
      _loadBySupplier(),
      _loadCancelledInvoices(),
      _loadPurchaseOrders(),
    ]);

    final allPurchases = results[0] as List<PurchaseInvoiceItem>;
    final byProduct = results[1] as List<PurchasesByProductItem>;
    final byCategory = results[2] as List<PurchasesByCategoryItem>;
    final bySupplier = results[3] as List<PurchasesBySupplierItem>;
    final cancelled = results[4] as List<CancelledPurchaseItem>;
    final orders = results[5] as List<PurchaseOrderItem>;

    // Calculate summary from allPurchases
    int totalPurchases = 0;
    int totalDiscount = 0;
    int totalTax = 0;
    int totalPaid = 0;
    int cashPurchases = 0;
    int creditPurchases = 0;
    int cardPurchases = 0;
    int chequePurchases = 0;

    for (final p in allPurchases) {
      totalPurchases += p.totalCents;
      totalDiscount += p.discountCents;
      totalTax += p.taxCents;
      totalPaid += p.paidAmountCents;
      switch (p.paymentMethod) {
        case 'cash':
          cashPurchases += p.totalCents;
        case 'credit':
          creditPurchases += p.totalCents;
        case 'card':
          cardPurchases += p.totalCents;
        case 'cheque':
          chequePurchases += p.totalCents;
      }
    }

    return PurchaseReportsData(
      summary: PurchaseReportsSummary(
        totalPurchasesCents: totalPurchases,
        totalDiscountCents: totalDiscount,
        totalTaxCents: totalTax,
        totalPaidCents: totalPaid,
        invoiceCount: allPurchases.length,
        cancelledCount: cancelled.length,
        cashPurchasesCents: cashPurchases,
        creditPurchasesCents: creditPurchases,
        cardPurchasesCents: cardPurchases,
        chequePurchasesCents: chequePurchases,
      ),
      allPurchases: allPurchases,
      byProduct: byProduct,
      byCategory: byCategory,
      bySupplier: bySupplier,
      cancelledInvoices: cancelled,
      purchaseOrders: orders,
      dateRange: _dateRange,
    );
  }

  Future<List<PurchaseInvoiceItem>> _loadAllPurchases() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        p.id AS purchase_id,
        p.purchase_number,
        su.name AS supplier_name,
        p.subtotal_cents,
        p.discount_cents,
        p.tax_cents,
        p.total_cents,
        p.paid_amount_cents,
        p.payment_method,
        p.status,
        p.purchase_date
      FROM purchases p
      INNER JOIN suppliers su ON su.id = p.supplier_id
      WHERE p.status NOT IN ('voided', 'draft')
        AND p.purchase_date >= ?
        AND p.purchase_date <= ?
      ORDER BY p.purchase_date DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchases, _db.suppliers},
    ).get();

    return rows.map((row) {
      return PurchaseInvoiceItem(
        purchaseId: row.read<int>('purchase_id'),
        purchaseNumber: row.read<String>('purchase_number'),
        supplierName: row.read<String>('supplier_name'),
        subtotalCents: row.read<int>('subtotal_cents'),
        discountCents: row.read<int>('discount_cents'),
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
        paidAmountCents: row.read<int>('paid_amount_cents'),
        paymentMethod: row.readNullable<String>('payment_method'),
        status: row.read<String>('status'),
        purchaseDate: DateTime.parse(row.read<String>('purchase_date')),
      );
    }).toList();
  }

  Future<List<PurchasesByProductItem>> _loadByProduct() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        pr.id AS product_id,
        pr.name AS product_name,
        pc.name AS category_name,
        COALESCE(SUM(pi.quantity), 0) AS total_quantity,
        COALESCE(SUM(pi.total_cents), 0) AS total_purchases_cents,
        COALESCE(SUM(pi.discount_cents), 0) AS total_discount_cents,
        COALESCE(SUM(pi.tax_cents), 0) AS total_tax_cents,
        COUNT(DISTINCT p.id) AS invoice_count
      FROM purchase_items pi
      INNER JOIN purchases p ON p.id = pi.purchase_id
      INNER JOIN products pr ON pr.id = pi.product_id
      LEFT JOIN product_categories pc ON pc.id = pr.category_id
      WHERE p.status NOT IN ('voided', 'draft')
        AND p.purchase_date >= ?
        AND p.purchase_date <= ?
      GROUP BY pr.id
      ORDER BY total_purchases_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchases, _db.purchaseItems, _db.products, _db.productCategories},
    ).get();

    return rows.map((row) {
      return PurchasesByProductItem(
        productId: row.read<int>('product_id'),
        productName: row.read<String>('product_name'),
        categoryName: row.readNullable<String>('category_name'),
        totalQuantity: row.read<int>('total_quantity'),
        totalPurchasesCents: row.read<int>('total_purchases_cents'),
        totalDiscountCents: row.read<int>('total_discount_cents'),
        totalTaxCents: row.read<int>('total_tax_cents'),
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  Future<List<PurchasesByCategoryItem>> _loadByCategory() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        COALESCE(pc.id, 0) AS category_id,
        COALESCE(pc.name, 'Uncategorized') AS category_name,
        COALESCE(SUM(pi.quantity), 0) AS total_quantity,
        COALESCE(SUM(pi.total_cents), 0) AS total_purchases_cents,
        COALESCE(SUM(pi.discount_cents), 0) AS total_discount_cents,
        COALESCE(SUM(pi.tax_cents), 0) AS total_tax_cents,
        COUNT(DISTINCT pr.id) AS product_count,
        COUNT(DISTINCT p.id) AS invoice_count
      FROM purchase_items pi
      INNER JOIN purchases p ON p.id = pi.purchase_id
      INNER JOIN products pr ON pr.id = pi.product_id
      LEFT JOIN product_categories pc ON pc.id = pr.category_id
      WHERE p.status NOT IN ('voided', 'draft')
        AND p.purchase_date >= ?
        AND p.purchase_date <= ?
      GROUP BY COALESCE(pc.id, 0)
      ORDER BY total_purchases_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchases, _db.purchaseItems, _db.products, _db.productCategories},
    ).get();

    return rows.map((row) {
      return PurchasesByCategoryItem(
        categoryId: row.read<int>('category_id'),
        categoryName: row.read<String>('category_name'),
        totalQuantity: row.read<int>('total_quantity'),
        totalPurchasesCents: row.read<int>('total_purchases_cents'),
        totalDiscountCents: row.read<int>('total_discount_cents'),
        totalTaxCents: row.read<int>('total_tax_cents'),
        productCount: row.read<int>('product_count'),
        invoiceCount: row.read<int>('invoice_count'),
      );
    }).toList();
  }

  Future<List<PurchasesBySupplierItem>> _loadBySupplier() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        su.id AS supplier_id,
        su.name AS supplier_name,
        COALESCE(SUM(p.total_cents), 0) AS total_purchases_cents,
        COALESCE(SUM(p.discount_cents), 0) AS total_discount_cents,
        COALESCE(SUM(p.tax_cents), 0) AS total_tax_cents,
        COUNT(p.id) AS invoice_count,
        COALESCE(SUM(item_totals.total_qty), 0) AS total_quantity,
        MAX(p.purchase_date) AS last_purchase_date
      FROM purchases p
      INNER JOIN suppliers su ON su.id = p.supplier_id
      LEFT JOIN (
        SELECT pi.purchase_id, SUM(pi.quantity) AS total_qty
        FROM purchase_items pi
        GROUP BY pi.purchase_id
      ) item_totals ON item_totals.purchase_id = p.id
      WHERE p.status NOT IN ('voided', 'draft')
        AND p.purchase_date >= ?
        AND p.purchase_date <= ?
      GROUP BY su.id
      ORDER BY total_purchases_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchases, _db.purchaseItems, _db.suppliers},
    ).get();

    return rows.map((row) {
      final lastDateStr = row.readNullable<String>('last_purchase_date');
      return PurchasesBySupplierItem(
        supplierId: row.read<int>('supplier_id'),
        supplierName: row.read<String>('supplier_name'),
        totalPurchasesCents: row.read<int>('total_purchases_cents'),
        totalDiscountCents: row.read<int>('total_discount_cents'),
        totalTaxCents: row.read<int>('total_tax_cents'),
        invoiceCount: row.read<int>('invoice_count'),
        totalQuantity: row.read<int>('total_quantity'),
        lastPurchaseDate: lastDateStr != null ? DateTime.tryParse(lastDateStr) : null,
      );
    }).toList();
  }

  Future<List<CancelledPurchaseItem>> _loadCancelledInvoices() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        p.id AS purchase_id,
        p.purchase_number,
        su.name AS supplier_name,
        p.total_cents,
        p.status,
        p.purchase_date,
        p.notes
      FROM purchases p
      INNER JOIN suppliers su ON su.id = p.supplier_id
      WHERE p.status = 'voided'
        AND p.purchase_date >= ?
        AND p.purchase_date <= ?
      ORDER BY p.purchase_date DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchases, _db.suppliers},
    ).get();

    return rows.map((row) {
      return CancelledPurchaseItem(
        purchaseId: row.read<int>('purchase_id'),
        purchaseNumber: row.read<String>('purchase_number'),
        supplierName: row.read<String>('supplier_name'),
        totalCents: row.read<int>('total_cents'),
        status: row.read<String>('status'),
        purchaseDate: DateTime.parse(row.read<String>('purchase_date')),
        notes: row.readNullable<String>('notes'),
      );
    }).toList();
  }

  Future<List<PurchaseOrderItem>> _loadPurchaseOrders() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        p.id AS purchase_id,
        p.purchase_number,
        su.name AS supplier_name,
        p.total_cents,
        p.status,
        p.purchase_date,
        p.due_date
      FROM purchases p
      INNER JOIN suppliers su ON su.id = p.supplier_id
      WHERE p.payment_method = 'purchaseOrder'
        AND p.status != 'voided'
        AND p.purchase_date >= ?
        AND p.purchase_date <= ?
      ORDER BY p.purchase_date DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchases, _db.suppliers},
    ).get();

    return rows.map((row) {
      final dueDateStr = row.readNullable<String>('due_date');
      return PurchaseOrderItem(
        purchaseId: row.read<int>('purchase_id'),
        purchaseNumber: row.read<String>('purchase_number'),
        supplierName: row.read<String>('supplier_name'),
        totalCents: row.read<int>('total_cents'),
        status: row.read<String>('status'),
        purchaseDate: DateTime.parse(row.read<String>('purchase_date')),
        dueDate: dueDateStr != null ? DateTime.tryParse(dueDateStr) : null,
      );
    }).toList();
  }
}
