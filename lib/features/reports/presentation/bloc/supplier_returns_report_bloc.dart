import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';
import 'customer_invoices_report_bloc.dart' show InvoiceLineItem;

// ==================== EVENTS ====================

abstract class SupplierReturnsReportEvent extends RealtimeEvent {
  const SupplierReturnsReportEvent();
}

class SupplierReturnsDateRangeChanged extends SupplierReturnsReportEvent {
  final ReportDateRange dateRange;
  const SupplierReturnsDateRangeChanged(this.dateRange);
}

class SupplierReturnsSupplierChanged extends SupplierReturnsReportEvent {
  final int? supplierId;
  const SupplierReturnsSupplierChanged(this.supplierId);
}

// ==================== DATA MODELS ====================

/// One supplier return (linked to an invoice, or an unlinked adjustment).
class SupplierReturnInvoice {
  final int id;
  final String returnNumber;

  /// true  → linked to an original purchase invoice (`purchase_returns`)
  /// false → unlinked adjustment return (`purchase_return_adjustments`)
  final bool isLinked;

  /// The original purchase invoice number, only for linked returns.
  final String? originalInvoiceNumber;

  final DateTime date;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;

  /// cash, credit, cheque
  final String refundMethod;
  final String status;
  final List<InvoiceLineItem> items;

  const SupplierReturnInvoice({
    required this.id,
    required this.returnNumber,
    required this.isLinked,
    this.originalInvoiceNumber,
    required this.date,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.refundMethod,
    required this.status,
    this.items = const [],
  });

  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);

  int get lineCount => items.length;
}

class SupplierReturnsData {
  final int? supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final String? supplierAddress;

  final List<SupplierReturnInvoice> returns;

  final int totalAmountCents;
  final int totalDiscountCents;
  final int totalQuantity;
  final int linkedCount;
  final int adjustmentCount;

  final ReportDateRange dateRange;
  final List<SupplierReturnOption> suppliers;

  const SupplierReturnsData({
    this.supplierId,
    this.supplierName,
    this.supplierPhone,
    this.supplierAddress,
    this.returns = const [],
    this.totalAmountCents = 0,
    this.totalDiscountCents = 0,
    this.totalQuantity = 0,
    this.linkedCount = 0,
    this.adjustmentCount = 0,
    required this.dateRange,
    this.suppliers = const [],
  });

  int get returnCount => returns.length;
}

class SupplierReturnOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const SupplierReturnOption({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

// ==================== BLOC ====================

class SupplierReturnsReportBloc
    extends RealtimeBloc<SupplierReturnsData, SupplierReturnsReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  int? _supplierId;

  SupplierReturnsReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;
  int? get supplierId => _supplierId;

  @override
  Stream<SupplierReturnsData> get dataStream => _buildStream();

  @override
  void registerEventHandlers() {
    on<SupplierReturnsDateRangeChanged>(_onDateRangeChanged);
    on<SupplierReturnsSupplierChanged>(_onSupplierChanged);
  }

  Stream<SupplierReturnsData> _buildStream() {
    // Reload whenever either linked or adjustment return tables change.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.purchaseReturns, _db.purchaseReturnAdjustments},
        )
        .watch()
        .asyncMap((_) async => _loadData());
  }

  Future<void> _onDateRangeChanged(
    SupplierReturnsDateRangeChanged event,
    Emitter<RealtimeState<SupplierReturnsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSupplierChanged(
    SupplierReturnsSupplierChanged event,
    Emitter<RealtimeState<SupplierReturnsData>> emit,
  ) async {
    _supplierId = event.supplierId;
    refresh();
  }

  Future<SupplierReturnsData> _loadData() async {
    // ── Supplier list for the selector ──
    final supplierRows = await _db.customSelect(
      '''
      SELECT s.id, s.name, s.phone, s.balance_cents
      FROM suppliers s WHERE s.is_active = 1
      ORDER BY s.name ASC
      ''',
      readsFrom: {_db.suppliers},
    ).get();

    final suppliers = supplierRows
        .map((r) => SupplierReturnOption(
              id: r.read<int>('id'),
              name: r.read<String>('name'),
              phone: r.readNullable<String>('phone'),
              balanceCents: r.read<int>('balance_cents'),
            ))
        .toList();

    if (_supplierId == null) {
      return SupplierReturnsData(dateRange: _dateRange, suppliers: suppliers);
    }

    // ── Supplier info ──
    final sRows = await _db.customSelect(
      'SELECT name, phone, address FROM suppliers WHERE id = ?',
      variables: [Variable.withInt(_supplierId!)],
      readsFrom: {_db.suppliers},
    ).get();
    if (sRows.isEmpty) {
      return SupplierReturnsData(dateRange: _dateRange, suppliers: suppliers);
    }
    final sInfo = sRows.first;

    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = DateTime(
      _dateRange.endDate.year,
      _dateRange.endDate.month,
      _dateRange.endDate.day,
      23, 59, 59,
    ).toIso8601String();

    final returns = <SupplierReturnInvoice>[];

    // ── Linked returns (purchase_returns via purchases) ──
    final linkedRows = await _db.customSelect(
      '''
      SELECT pr.id, pr.return_number, pr.subtotal_cents, pr.discount_cents,
             pr.tax_cents, pr.total_cents, pr.refund_method, pr.status,
             pr.return_date, p.purchase_number AS original_invoice
      FROM purchase_returns pr
      INNER JOIN purchases p ON p.id = pr.purchase_id
      WHERE p.supplier_id = ?
        AND pr.status != 'voided'
        AND pr.return_date >= ?
        AND pr.return_date <= ?
      ORDER BY pr.return_date ASC, pr.id ASC
      ''',
      variables: [
        Variable.withInt(_supplierId!),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchaseReturns, _db.purchases},
    ).get();

    for (final row in linkedRows) {
      final returnId = row.read<int>('id');
      final items = await _loadLinkedReturnItems(returnId);
      returns.add(SupplierReturnInvoice(
        id: returnId,
        returnNumber: row.read<String>('return_number'),
        isLinked: true,
        originalInvoiceNumber: row.readNullable<String>('original_invoice'),
        date: DateTime.parse(row.read<String>('return_date')),
        subtotalCents: row.read<int>('subtotal_cents'),
        discountCents: row.read<int>('discount_cents'),
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
        refundMethod: row.read<String>('refund_method'),
        status: row.read<String>('status'),
        items: items,
      ));
    }

    // ── Adjustment (unlinked) returns (purchase_return_adjustments) ──
    final adjRows = await _db.customSelect(
      '''
      SELECT pra.id, pra.return_number, pra.subtotal_cents, pra.discount_cents,
             pra.tax_cents, pra.total_cents, pra.refund_method, pra.status,
             pra.return_date
      FROM purchase_return_adjustments pra
      WHERE pra.supplier_id = ?
        AND pra.status != 'voided'
        AND pra.return_date >= ?
        AND pra.return_date <= ?
      ORDER BY pra.return_date ASC, pra.id ASC
      ''',
      variables: [
        Variable.withInt(_supplierId!),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchaseReturnAdjustments},
    ).get();

    for (final row in adjRows) {
      final returnId = row.read<int>('id');
      final items = await _loadAdjustmentReturnItems(returnId);
      returns.add(SupplierReturnInvoice(
        id: returnId,
        returnNumber: row.read<String>('return_number'),
        isLinked: false,
        date: DateTime.parse(row.read<String>('return_date')),
        subtotalCents: row.read<int>('subtotal_cents'),
        discountCents: row.read<int>('discount_cents'),
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
        refundMethod: row.read<String>('refund_method'),
        status: row.read<String>('status'),
        items: items,
      ));
    }

    // ── Chronological merge ──
    returns.sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.id.compareTo(b.id);
    });

    int totalAmount = 0;
    int totalDiscount = 0;
    int totalQty = 0;
    int linkedCount = 0;
    int adjustmentCount = 0;
    for (final r in returns) {
      totalAmount += r.totalCents;
      totalDiscount += r.discountCents;
      totalQty += r.totalQuantity;
      if (r.isLinked) {
        linkedCount++;
      } else {
        adjustmentCount++;
      }
    }

    return SupplierReturnsData(
      supplierId: _supplierId,
      supplierName: sInfo.read<String>('name'),
      supplierPhone: sInfo.readNullable<String>('phone'),
      supplierAddress: sInfo.readNullable<String>('address'),
      returns: returns,
      totalAmountCents: totalAmount,
      totalDiscountCents: totalDiscount,
      totalQuantity: totalQty,
      linkedCount: linkedCount,
      adjustmentCount: adjustmentCount,
      dateRange: _dateRange,
      suppliers: suppliers,
    );
  }

  Future<List<InvoiceLineItem>> _loadLinkedReturnItems(int returnId) async {
    final rows = await _db.customSelect(
      '''
      SELECT p.name AS product_name,
             pc.name AS color_name,
             sz.name AS size_name,
             pri.quantity AS quantity,
             pri.refund_cents AS refund_cents
      FROM purchase_return_items pri
      INNER JOIN purchase_items pit ON pit.id = pri.purchase_item_id
      INNER JOIN products p ON p.id = pit.product_id
      LEFT JOIN product_variants pv ON pv.id = pit.variant_id
      LEFT JOIN product_colors pc ON pc.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE pri.return_id = ?
      ORDER BY pri.id ASC
      ''',
      variables: [Variable.withInt(returnId)],
      readsFrom: {
        _db.purchaseReturnItems,
        _db.purchaseItems,
        _db.products,
        _db.productVariants,
        _db.productColors,
        _db.sizes,
      },
    ).get();

    return rows.map((r) {
      final quantity = r.read<int>('quantity');
      final refund = r.read<int>('refund_cents');
      final unit = quantity > 0 ? (refund / quantity).round() : refund;
      return InvoiceLineItem(
        productName: r.read<String>('product_name'),
        variantLabel: _variantLabel(
          r.readNullable<String>('color_name'),
          r.readNullable<String>('size_name'),
        ),
        quantity: quantity,
        unitPriceCents: unit,
        totalCents: refund,
      );
    }).toList();
  }

  Future<List<InvoiceLineItem>> _loadAdjustmentReturnItems(int returnId) async {
    final rows = await _db.customSelect(
      '''
      SELECT p.name AS product_name,
             pc.name AS color_name,
             sz.name AS size_name,
             pria.quantity AS quantity,
             pria.unit_price_cents AS unit_price_cents,
             pria.total_cents AS total_cents
      FROM purchase_return_adjustment_items pria
      INNER JOIN products p ON p.id = pria.product_id
      LEFT JOIN product_variants pv ON pv.id = pria.variant_id
      LEFT JOIN product_colors pc ON pc.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE pria.return_id = ?
      ORDER BY pria.id ASC
      ''',
      variables: [Variable.withInt(returnId)],
      readsFrom: {
        _db.purchaseReturnAdjustmentItems,
        _db.products,
        _db.productVariants,
        _db.productColors,
        _db.sizes,
      },
    ).get();

    return rows.map((r) {
      return InvoiceLineItem(
        productName: r.read<String>('product_name'),
        variantLabel: _variantLabel(
          r.readNullable<String>('color_name'),
          r.readNullable<String>('size_name'),
        ),
        quantity: r.read<int>('quantity'),
        unitPriceCents: r.read<int>('unit_price_cents'),
        totalCents: r.read<int>('total_cents'),
      );
    }).toList();
  }

  String? _variantLabel(String? color, String? size) {
    final parts = <String>[];
    if (color != null && color.isNotEmpty) parts.add(color);
    if (size != null && size.isNotEmpty) parts.add(size);
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
