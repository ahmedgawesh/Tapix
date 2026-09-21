import '../../../../core/services/business/warehouse_read_scope.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/business/document_posting_scope.dart';
import '../../../../core/services/business/warehouse_document_scope.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerSalesReturnsEvent extends RealtimeEvent {
  const CustomerSalesReturnsEvent();
}

class CustomerSalesReturnsDateRangeChanged extends CustomerSalesReturnsEvent {
  final ReportDateRange dateRange;
  const CustomerSalesReturnsDateRangeChanged(this.dateRange);
}

class CustomerSalesReturnsSortChanged extends CustomerSalesReturnsEvent {
  final ReturnsSortType sort;
  const CustomerSalesReturnsSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum ReturnsSortType {
  customerAsc,
  customerDesc,
  totalDesc,
  totalAsc,
  countDesc,
  countAsc,
}

// ==================== DATA MODELS ====================

class CustomerReturnSummary {
  final int customerId;
  final String customerName;
  final String segment;
  final int returnCount;
  final int totalReturnedCents;
  final int totalItemsReturned;
  final DateTime? lastReturnDate;

  const CustomerReturnSummary({
    required this.customerId,
    required this.customerName,
    required this.segment,
    required this.returnCount,
    required this.totalReturnedCents,
    required this.totalItemsReturned,
    this.lastReturnDate,
  });

  /// Average return value in cents
  int get averageReturnCents =>
      returnCount > 0 ? totalReturnedCents ~/ returnCount : 0;
}

class ReturnDetailItem {
  final int returnId;
  final String returnNumber;
  final DateTime returnDate;
  final String status;
  final String dispositionType;
  final String refundMethod;
  final String? reason;
  final int totalCents;
  final int itemCount;
  final String? originalInvoiceNumber;

  const ReturnDetailItem({
    required this.returnId,
    required this.returnNumber,
    required this.returnDate,
    required this.status,
    required this.dispositionType,
    required this.refundMethod,
    this.reason,
    required this.totalCents,
    required this.itemCount,
    this.originalInvoiceNumber,
  });
}

class ReturnReasonBreakdown {
  final String reason;
  final int count;
  final int totalCents;

  const ReturnReasonBreakdown({
    required this.reason,
    required this.count,
    required this.totalCents,
  });
}

class ReturnedProductItem {
  final int returnId;
  final String productName;
  final String? sku;
  final String? colorName;
  final String? sizeName;
  final int quantity;
  final String measurementType;
  final int refundCents;
  final String? reason;

  const ReturnedProductItem({
    required this.returnId,
    required this.productName,
    this.sku,
    this.colorName,
    this.sizeName,
    required this.quantity,
    this.measurementType = 'piece',
    required this.refundCents,
    this.reason,
  });
}

class CustomerSalesReturnsData {
  final List<CustomerReturnSummary> customerSummaries;
  final List<ReturnDetailItem> returnDetails;
  final List<ReturnReasonBreakdown> reasonBreakdown;
  final List<ReturnedProductItem> returnedProducts;
  final int totalReturnsCents;
  final int totalReturnCount;
  final int totalItemsReturned;
  final int customersWithReturns;
  final ReportDateRange dateRange;
  final ReturnsSortType sort;
  final int? selectedCustomerId;

  const CustomerSalesReturnsData({
    this.customerSummaries = const [],
    this.returnDetails = const [],
    this.reasonBreakdown = const [],
    this.returnedProducts = const [],
    this.totalReturnsCents = 0,
    this.totalReturnCount = 0,
    this.totalItemsReturned = 0,
    this.customersWithReturns = 0,
    required this.dateRange,
    this.sort = ReturnsSortType.totalDesc,
    this.selectedCustomerId,
  });

  CustomerSalesReturnsData copyWith({
    List<CustomerReturnSummary>? customerSummaries,
    List<ReturnDetailItem>? returnDetails,
    List<ReturnReasonBreakdown>? reasonBreakdown,
    List<ReturnedProductItem>? returnedProducts,
    int? totalReturnsCents,
    int? totalReturnCount,
    int? totalItemsReturned,
    int? customersWithReturns,
    ReportDateRange? dateRange,
    ReturnsSortType? sort,
    int? Function()? selectedCustomerId,
  }) {
    return CustomerSalesReturnsData(
      customerSummaries: customerSummaries ?? this.customerSummaries,
      returnDetails: returnDetails ?? this.returnDetails,
      reasonBreakdown: reasonBreakdown ?? this.reasonBreakdown,
      returnedProducts: returnedProducts ?? this.returnedProducts,
      totalReturnsCents: totalReturnsCents ?? this.totalReturnsCents,
      totalReturnCount: totalReturnCount ?? this.totalReturnCount,
      totalItemsReturned: totalItemsReturned ?? this.totalItemsReturned,
      customersWithReturns: customersWithReturns ?? this.customersWithReturns,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
      selectedCustomerId: selectedCustomerId != null
          ? selectedCustomerId()
          : this.selectedCustomerId,
    );
  }
}

// ==================== BLOC ====================

class CustomerSalesReturnsBloc
    extends RealtimeBloc<CustomerSalesReturnsData, CustomerSalesReturnsEvent> {
  final AppDatabase _db;
  final WarehouseReadScope? warehouseScope;
  ReportDateRange _dateRange;
  ReturnsSortType _sort = ReturnsSortType.totalDesc;

  CustomerSalesReturnsBloc(
    this._db, {
    String defaultDateRange = 'month',
    this.warehouseScope,
  }) : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
       super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<CustomerSalesReturnsData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<CustomerSalesReturnsDateRangeChanged>(_onDateRangeChanged);
    on<CustomerSalesReturnsSortChanged>(_onSortChanged);
  }

  Stream<CustomerSalesReturnsData> _buildCombinedStream() {
    // Watch BOTH linked sale_returns and adjustment (unlinked) sale returns so
    // posting/voiding either flow live-refreshes every figure in this report.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleReturns,
            _db.saleReturnAdjustments,
          },
        )
        .watch()
        .asyncMap(
          (_) => WarehouseReadScope.snapshot(_db, warehouseScope, () async {
            final summaries = await _loadCustomerSummaries();
            final details = await _loadReturnDetails();
            final reasons = await _loadReasonBreakdown();
            final products = await _loadReturnedProducts();

            int totalCents = 0;
            int totalCount = 0;
            int totalItems = 0;
            for (final s in summaries) {
              totalCents += s.totalReturnedCents;
              totalCount += s.returnCount;
              totalItems += s.totalItemsReturned;
            }

            final sorted = _applySortToSummaries(summaries, _sort);

            return CustomerSalesReturnsData(
              customerSummaries: sorted,
              returnDetails: details,
              reasonBreakdown: reasons,
              returnedProducts: products,
              totalReturnsCents: totalCents,
              totalReturnCount: totalCount,
              totalItemsReturned: totalItems,
              customersWithReturns: summaries.length,
              dateRange: _dateRange,
              sort: _sort,
            );
          }),
        );
  }

  Future<void> _onDateRangeChanged(
    CustomerSalesReturnsDateRangeChanged event,
    Emitter<RealtimeState<CustomerSalesReturnsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    CustomerSalesReturnsSortChanged event,
    Emitter<RealtimeState<CustomerSalesReturnsData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToSummaries(
        current.customerSummaries,
        event.sort,
      );
      emit(
        RealtimeSuccess<CustomerSalesReturnsData>(
          data: current.copyWith(customerSummaries: sorted, sort: event.sort),
        ),
      );
    }
  }

  List<CustomerReturnSummary> _applySortToSummaries(
    List<CustomerReturnSummary> items,
    ReturnsSortType sort,
  ) {
    final list = List<CustomerReturnSummary>.from(items);
    switch (sort) {
      case ReturnsSortType.customerAsc:
        list.sort((a, b) => a.customerName.compareTo(b.customerName));
      case ReturnsSortType.customerDesc:
        list.sort((a, b) => b.customerName.compareTo(a.customerName));
      case ReturnsSortType.totalDesc:
        list.sort(
          (a, b) => b.totalReturnedCents.compareTo(a.totalReturnedCents),
        );
      case ReturnsSortType.totalAsc:
        list.sort(
          (a, b) => a.totalReturnedCents.compareTo(b.totalReturnedCents),
        );
      case ReturnsSortType.countDesc:
        list.sort((a, b) => b.returnCount.compareTo(a.returnCount));
      case ReturnsSortType.countAsc:
        list.sort((a, b) => a.returnCount.compareTo(b.returnCount));
    }
    return list;
  }

  Future<List<CustomerReturnSummary>> _loadCustomerSummaries() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Combine linked (invoice-based) returns and adjustment (unlinked) returns.
    // Only returns attributed to a real customer are grouped here (walk-in
    // adjustment returns with a NULL customer are excluded, matching the
    // existing by-customer convention used elsewhere in reports).
    final rows = await _db
        .customSelect(
          '''
      SELECT 
        c.id AS customer_id,
        c.name AS customer_name,
        c.segment AS segment,
        COUNT(r.return_id) AS return_count,
        COALESCE(SUM(r.total_cents), 0) AS total_returned_cents,
        COALESCE(SUM(r.item_qty), 0) AS total_items_returned,
        MAX(r.return_date) AS last_return_date
      FROM (
        SELECT sr.id AS return_id, s.customer_id AS customer_id,
               sr.total_cents AS total_cents, sr.return_date AS return_date,
               (SELECT COALESCE(SUM(sri.quantity), 0) FROM sale_return_items sri
                  WHERE sri.return_id = sr.id) AS item_qty
        FROM ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr
        INNER JOIN sales s ON s.id = sr.sale_id
        WHERE sr.status = 'posted'
          AND sr.return_date >= ? AND sr.return_date <= ?
        UNION ALL
        SELECT sra.id AS return_id, sra.customer_id AS customer_id,
               sra.total_cents AS total_cents, sra.return_date AS return_date,
               (SELECT COALESCE(SUM(srai.quantity), 0) FROM sale_return_adjustment_items srai
                  WHERE srai.return_id = sra.id) AS item_qty
        FROM ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra
        WHERE sra.status = 'posted'
          AND sra.return_date >= ? AND sra.return_date <= ?
      ) r
      INNER JOIN customers c ON c.id = r.customer_id
      GROUP BY c.id
      ORDER BY total_returned_cents DESC
      ''',
          variables: [
            Variable<String>(startIso),
            Variable<String>(endIso),
            Variable<String>(startIso),
            Variable<String>(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleReturns,
            _db.saleReturnItems,
            _db.saleReturnAdjustments,
            _db.saleReturnAdjustmentItems,
            _db.sales,
            _db.customers,
          },
        )
        .get();

    return rows.map((row) {
      final lastDateStr = row.readNullable<String>('last_return_date');
      return CustomerReturnSummary(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        segment: row.read<String>('segment'),
        returnCount: row.read<int>('return_count'),
        totalReturnedCents: row.read<int>('total_returned_cents'),
        totalItemsReturned: row.read<int>('total_items_returned'),
        lastReturnDate: lastDateStr != null
            ? DateTime.tryParse(lastDateStr)
            : null,
      );
    }).toList();
  }

  Future<List<ReturnDetailItem>> _loadReturnDetails() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Linked returns carry a real disposition + original invoice number.
    // Adjustment (unlinked) returns are marked with disposition 'adjustment'
    // and have no originating invoice; item_count comes from their own items.
    final rows = await _db
        .customSelect(
          '''
      SELECT return_id, return_number, return_date, status, disposition_type,
             refund_method, reason, total_cents, item_count, original_invoice_number
      FROM (
        SELECT 
          sr.id AS return_id,
          sr.return_number AS return_number,
          sr.return_date AS return_date,
          sr.status AS status,
          sr.disposition_type AS disposition_type,
          sr.refund_method AS refund_method,
          sr.reason AS reason,
          sr.total_cents AS total_cents,
          (SELECT COALESCE(SUM(sri.quantity), 0) FROM sale_return_items sri
             WHERE sri.return_id = sr.id) AS item_count,
          s.invoice_number AS original_invoice_number
        FROM ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr
        INNER JOIN sales s ON s.id = sr.sale_id
        WHERE sr.status = 'posted'
          AND sr.return_date >= ? AND sr.return_date <= ?
        UNION ALL
        SELECT 
          sra.id AS return_id,
          sra.return_number AS return_number,
          sra.return_date AS return_date,
          sra.status AS status,
          'adjustment' AS disposition_type,
          sra.refund_method AS refund_method,
          NULL AS reason,
          sra.total_cents AS total_cents,
          (SELECT COALESCE(SUM(srai.quantity), 0) FROM sale_return_adjustment_items srai
             WHERE srai.return_id = sra.id) AS item_count,
          NULL AS original_invoice_number
        FROM ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra
        WHERE sra.status = 'posted'
          AND sra.return_date >= ? AND sra.return_date <= ?
      )
      ORDER BY return_date DESC
      ''',
          variables: [
            Variable<String>(startIso),
            Variable<String>(endIso),
            Variable<String>(startIso),
            Variable<String>(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleReturns,
            _db.saleReturnItems,
            _db.saleReturnAdjustments,
            _db.saleReturnAdjustmentItems,
            _db.sales,
          },
        )
        .get();

    return rows.map((row) {
      return ReturnDetailItem(
        returnId: row.read<int>('return_id'),
        returnNumber: row.read<String>('return_number'),
        returnDate: DateTime.parse(row.read<String>('return_date')),
        status: row.read<String>('status'),
        dispositionType: row.read<String>('disposition_type'),
        refundMethod: row.read<String>('refund_method'),
        reason: row.readNullable<String>('reason'),
        totalCents: row.read<int>('total_cents'),
        itemCount: row.read<int>('item_count'),
        originalInvoiceNumber: row.readNullable<String>(
          'original_invoice_number',
        ),
      );
    }).toList();
  }

  Future<List<ReturnReasonBreakdown>> _loadReasonBreakdown() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT reason, COUNT(*) AS count, COALESCE(SUM(amount_cents), 0) AS total_cents
      FROM (
        SELECT COALESCE(sri.reason, 'other') AS reason, sri.refund_cents AS amount_cents
        FROM sale_return_items sri
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr ON sr.id = sri.return_id
        WHERE sr.status = 'posted'
          AND sr.return_date >= ? AND sr.return_date <= ?
        UNION ALL
        SELECT COALESCE(srai.reason, 'other') AS reason, srai.total_cents AS amount_cents
        FROM sale_return_adjustment_items srai
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra ON sra.id = srai.return_id
        WHERE sra.status = 'posted'
          AND sra.return_date >= ? AND sra.return_date <= ?
      )
      GROUP BY reason
      ORDER BY total_cents DESC
      ''',
          variables: [
            Variable<String>(startIso),
            Variable<String>(endIso),
            Variable<String>(startIso),
            Variable<String>(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleReturnItems,
            _db.saleReturns,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
          },
        )
        .get();

    return rows.map((row) {
      return ReturnReasonBreakdown(
        reason: row.read<String>('reason'),
        count: row.read<int>('count'),
        totalCents: row.read<int>('total_cents'),
      );
    }).toList();
  }

  Future<List<ReturnedProductItem>> _loadReturnedProducts() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db
        .customSelect(
          '''
      SELECT return_id, product_name, sku, color_name, size_name,
             quantity, measurement_type, refund_cents, reason, return_date
      FROM (
        SELECT 
          sri.return_id AS return_id,
          p.name AS product_name,
          pv.sku AS sku,
          pc.name AS color_name,
          sz.name AS size_name,
          sri.quantity AS quantity,
          sri.measurement_type AS measurement_type,
          sri.refund_cents AS refund_cents,
          sri.reason AS reason,
          sr.return_date AS return_date,
          sri.id AS order_key
        FROM sale_return_items sri
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr ON sr.id = sri.return_id
        INNER JOIN sale_items si ON si.id = sri.sale_item_id
        INNER JOIN products p ON p.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        LEFT JOIN product_colors pc ON pc.id = pv.color_id
        LEFT JOIN sizes sz ON sz.id = pv.size_id
        WHERE sr.status = 'posted'
          AND sr.return_date >= ? AND sr.return_date <= ?
        UNION ALL
        SELECT 
          srai.return_id AS return_id,
          p.name AS product_name,
          pv.sku AS sku,
          pc.name AS color_name,
          sz.name AS size_name,
          srai.quantity AS quantity,
          srai.measurement_type AS measurement_type,
          srai.total_cents AS refund_cents,
          srai.reason AS reason,
          sra.return_date AS return_date,
          srai.id AS order_key
        FROM sale_return_adjustment_items srai
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra ON sra.id = srai.return_id
        INNER JOIN products p ON p.id = srai.product_id
        LEFT JOIN product_variants pv ON pv.id = srai.variant_id
        LEFT JOIN product_colors pc ON pc.id = pv.color_id
        LEFT JOIN sizes sz ON sz.id = pv.size_id
        WHERE sra.status = 'posted'
          AND sra.return_date >= ? AND sra.return_date <= ?
      )
      ORDER BY return_date DESC, order_key ASC
      ''',
          variables: [
            Variable<String>(startIso),
            Variable<String>(endIso),
            Variable<String>(startIso),
            Variable<String>(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleReturnItems,
            _db.saleReturns,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
            _db.saleItems,
            _db.products,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .get();

    return rows.map((row) {
      return ReturnedProductItem(
        returnId: row.read<int>('return_id'),
        productName: row.read<String>('product_name'),
        sku: row.readNullable<String>('sku'),
        colorName: row.readNullable<String>('color_name'),
        sizeName: row.readNullable<String>('size_name'),
        quantity: row.read<int>('quantity'),
        measurementType: row.read<String>('measurement_type'),
        refundCents: row.read<int>('refund_cents'),
        reason: row.readNullable<String>('reason'),
      );
    }).toList();
  }
}
