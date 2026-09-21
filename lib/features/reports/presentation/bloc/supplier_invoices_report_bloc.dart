import '../../../../core/services/business/warehouse_read_scope.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/business/document_posting_scope.dart';
import '../../../../core/services/business/warehouse_document_scope.dart';
import '../widgets/report_date_range.dart';
import 'customer_invoices_report_bloc.dart' show InvoiceLineItem;

// ==================== EVENTS ====================

abstract class SupplierInvoicesReportEvent extends RealtimeEvent {
  const SupplierInvoicesReportEvent();
}

class SupplierInvoicesDateRangeChanged extends SupplierInvoicesReportEvent {
  final ReportDateRange dateRange;
  const SupplierInvoicesDateRangeChanged(this.dateRange);
}

class SupplierInvoicesSupplierChanged extends SupplierInvoicesReportEvent {
  final int? supplierId;
  const SupplierInvoicesSupplierChanged(this.supplierId);
}

// ==================== DATA MODELS ====================

/// One supplier invoice (purchase) with its items.
class SupplierInvoice {
  final int id;
  final String invoiceNumber;
  final String? supplierInvoiceRef;
  final DateTime date;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int paidAmountCents;
  final String? paymentMethod;
  final String status;
  final List<InvoiceLineItem> items;

  const SupplierInvoice({
    required this.id,
    required this.invoiceNumber,
    this.supplierInvoiceRef,
    required this.date,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidAmountCents,
    this.paymentMethod,
    required this.status,
    this.items = const [],
  });

  /// Total number of pieces across all items.
  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);

  /// Number of distinct line items.
  int get lineCount => items.length;
}

class SupplierInvoicesData {
  final int? supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final String? supplierAddress;

  final List<SupplierInvoice> invoices;

  final int totalAmountCents;
  final int totalDiscountCents;
  final int totalPaidCents;
  final int totalQuantity;

  final ReportDateRange dateRange;
  final List<SupplierInvoiceOption> suppliers;

  const SupplierInvoicesData({
    this.supplierId,
    this.supplierName,
    this.supplierPhone,
    this.supplierAddress,
    this.invoices = const [],
    this.totalAmountCents = 0,
    this.totalDiscountCents = 0,
    this.totalPaidCents = 0,
    this.totalQuantity = 0,
    required this.dateRange,
    this.suppliers = const [],
  });

  int get invoiceCount => invoices.length;
}

class SupplierInvoiceOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const SupplierInvoiceOption({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

// ==================== BLOC ====================

class SupplierInvoicesReportBloc
    extends RealtimeBloc<SupplierInvoicesData, SupplierInvoicesReportEvent> {
  final AppDatabase _db;
  final WarehouseReadScope? warehouseScope;
  ReportDateRange _dateRange;
  int? _supplierId;

  SupplierInvoicesReportBloc(
    this._db, {
    String defaultDateRange = 'month',
    this.warehouseScope,
  }) : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
       super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;
  int? get supplierId => _supplierId;

  @override
  Stream<SupplierInvoicesData> get dataStream => _buildStream();

  @override
  void registerEventHandlers() {
    on<SupplierInvoicesDateRangeChanged>(_onDateRangeChanged);
    on<SupplierInvoicesSupplierChanged>(_onSupplierChanged);
  }

  Stream<SupplierInvoicesData> _buildStream() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.purchases,
            _db.purchaseItems,
            _db.suppliers,
            ...WarehouseDocumentScope.dependencies(_db),
          },
        )
        .watch()
        .asyncMap((_) async => _loadData());
  }

  Future<void> _onDateRangeChanged(
    SupplierInvoicesDateRangeChanged event,
    Emitter<RealtimeState<SupplierInvoicesData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSupplierChanged(
    SupplierInvoicesSupplierChanged event,
    Emitter<RealtimeState<SupplierInvoicesData>> emit,
  ) async {
    _supplierId = event.supplierId;
    refresh();
  }

  Future<SupplierInvoicesData> _loadData() async {
    // ── Supplier list for the selector ──
    final supplierRows = await _db
        .customSelect(
          '''
      SELECT s.id, s.name, s.phone, s.balance_cents
      FROM suppliers s WHERE s.is_active = 1
      ORDER BY s.name ASC
      ''',
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.suppliers,
          },
        )
        .get();

    final suppliers = supplierRows
        .map(
          (r) => SupplierInvoiceOption(
            id: r.read<int>('id'),
            name: r.read<String>('name'),
            phone: r.readNullable<String>('phone'),
            balanceCents: r.read<int>('balance_cents'),
          ),
        )
        .toList();

    if (_supplierId == null) {
      return SupplierInvoicesData(dateRange: _dateRange, suppliers: suppliers);
    }

    // ── Supplier info ──
    final sRows = await _db
        .customSelect(
          'SELECT name, phone, address FROM suppliers WHERE id = ?',
          variables: [Variable.withInt(_supplierId!)],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.suppliers,
          },
        )
        .get();
    if (sRows.isEmpty) {
      return SupplierInvoicesData(dateRange: _dateRange, suppliers: suppliers);
    }
    final sInfo = sRows.first;

    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = DateTime(
      _dateRange.endDate.year,
      _dateRange.endDate.month,
      _dateRange.endDate.day,
      23,
      59,
      59,
    ).toIso8601String();

    // ── Invoices (purchases) in range ──
    final purchaseRows = await _db
        .customSelect(
          '''
      SELECT p.id, p.purchase_number, p.supplier_invoice_ref, p.subtotal_cents,
             p.discount_cents, p.tax_cents, p.total_cents, p.paid_amount_cents,
             p.payment_method, p.status, p.purchase_date
      FROM ${warehouseScope?.documents(InventoryPostingDocument.purchase) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchase)} p
      WHERE p.supplier_id = ?
        AND p.status NOT IN ('voided', 'draft')
        AND p.purchase_date >= ?
        AND p.purchase_date <= ?
      ORDER BY p.purchase_date ASC, p.id ASC
      ''',
          variables: [
            Variable.withInt(_supplierId!),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.purchases,
          },
        )
        .get();

    int totalAmount = 0;
    int totalDiscount = 0;
    int totalPaid = 0;
    int totalQty = 0;

    final invoices = <SupplierInvoice>[];

    for (final row in purchaseRows) {
      final purchaseId = row.read<int>('id');
      final items = await _loadInvoiceItems(purchaseId);

      final invoice = SupplierInvoice(
        id: purchaseId,
        invoiceNumber: row.read<String>('purchase_number'),
        supplierInvoiceRef: row.readNullable<String>('supplier_invoice_ref'),
        date: DateTime.parse(row.read<String>('purchase_date')),
        subtotalCents: row.read<int>('subtotal_cents'),
        discountCents: row.read<int>('discount_cents'),
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
        paidAmountCents: row.read<int>('paid_amount_cents'),
        paymentMethod: row.readNullable<String>('payment_method'),
        status: row.read<String>('status'),
        items: items,
      );

      totalAmount += invoice.totalCents;
      totalDiscount += invoice.discountCents;
      totalPaid += invoice.paidAmountCents;
      totalQty += invoice.totalQuantity;

      invoices.add(invoice);
    }

    return SupplierInvoicesData(
      supplierId: _supplierId,
      supplierName: sInfo.read<String>('name'),
      supplierPhone: sInfo.readNullable<String>('phone'),
      supplierAddress: sInfo.readNullable<String>('address'),
      invoices: invoices,
      totalAmountCents: totalAmount,
      totalDiscountCents: totalDiscount,
      totalPaidCents: totalPaid,
      totalQuantity: totalQty,
      dateRange: _dateRange,
      suppliers: suppliers,
    );
  }

  Future<List<InvoiceLineItem>> _loadInvoiceItems(int purchaseId) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT p.name AS product_name,
             COALESCE(pv.sku, p.sku) AS sku,
             pc.name AS color_name,
             sz.name AS size_name,
             pi.quantity AS quantity,
             pi.measurement_type AS measurement_type,
             pi.unit_cost_cents AS unit_cost_cents,
             pi.total_cents AS total_cents
      FROM purchase_items pi
      INNER JOIN products p ON p.id = pi.product_id
      LEFT JOIN product_variants pv ON pv.id = pi.variant_id
      LEFT JOIN product_colors pc ON pc.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE pi.purchase_id = ?
      ORDER BY pi.id ASC
      ''',
          variables: [Variable.withInt(purchaseId)],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.purchaseItems,
            _db.products,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .get();

    return rows.map((r) {
      final parts = <String>[];
      final color = r.readNullable<String>('color_name');
      final size = r.readNullable<String>('size_name');
      if (color != null && color.isNotEmpty) parts.add(color);
      if (size != null && size.isNotEmpty) parts.add(size);
      return InvoiceLineItem(
        productName: r.read<String>('product_name'),
        sku: r.readNullable<String>('sku'),
        variantLabel: parts.isEmpty ? null : parts.join(' · '),
        quantity: r.read<int>('quantity'),
        measurementType: r.read<String>('measurement_type'),
        unitPriceCents: r.read<int>('unit_cost_cents'),
        totalCents: r.read<int>('total_cents'),
      );
    }).toList();
  }
}
