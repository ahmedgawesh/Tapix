import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerInvoicesReportEvent extends RealtimeEvent {
  const CustomerInvoicesReportEvent();
}

class CustomerInvoicesDateRangeChanged extends CustomerInvoicesReportEvent {
  final ReportDateRange dateRange;
  const CustomerInvoicesDateRangeChanged(this.dateRange);
}

class CustomerInvoicesCustomerChanged extends CustomerInvoicesReportEvent {
  final int? customerId;
  const CustomerInvoicesCustomerChanged(this.customerId);
}

// ==================== DATA MODELS ====================

/// A single line item within an invoice.
class InvoiceLineItem {
  final String productName;
  final String? variantLabel;
  final int quantity;
  final int unitPriceCents;
  final int totalCents;

  const InvoiceLineItem({
    required this.productName,
    this.variantLabel,
    required this.quantity,
    required this.unitPriceCents,
    required this.totalCents,
  });
}

/// One customer invoice (sale) with its items.
class CustomerInvoice {
  final int id;
  final String invoiceNumber;
  final DateTime date;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int paidAmountCents;
  final String paymentMethod;
  final String status;
  final List<InvoiceLineItem> items;

  const CustomerInvoice({
    required this.id,
    required this.invoiceNumber,
    required this.date,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidAmountCents,
    required this.paymentMethod,
    required this.status,
    this.items = const [],
  });

  /// Total number of pieces across all items.
  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);

  /// Number of distinct line items.
  int get lineCount => items.length;
}

class CustomerInvoicesData {
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;

  final List<CustomerInvoice> invoices;

  final int totalAmountCents;
  final int totalDiscountCents;
  final int totalPaidCents;
  final int totalQuantity;

  final ReportDateRange dateRange;
  final List<CustomerInvoiceOption> customers;

  const CustomerInvoicesData({
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.invoices = const [],
    this.totalAmountCents = 0,
    this.totalDiscountCents = 0,
    this.totalPaidCents = 0,
    this.totalQuantity = 0,
    required this.dateRange,
    this.customers = const [],
  });

  int get invoiceCount => invoices.length;
}

class CustomerInvoiceOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const CustomerInvoiceOption({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

// ==================== BLOC ====================

class CustomerInvoicesReportBloc
    extends RealtimeBloc<CustomerInvoicesData, CustomerInvoicesReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  int? _customerId;

  CustomerInvoicesReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;
  int? get customerId => _customerId;

  @override
  Stream<CustomerInvoicesData> get dataStream => _buildStream();

  @override
  void registerEventHandlers() {
    on<CustomerInvoicesDateRangeChanged>(_onDateRangeChanged);
    on<CustomerInvoicesCustomerChanged>(_onCustomerChanged);
  }

  Stream<CustomerInvoicesData> _buildStream() {
    return _db.select(_db.sales).watch().asyncMap((_) async => _loadData());
  }

  Future<void> _onDateRangeChanged(
    CustomerInvoicesDateRangeChanged event,
    Emitter<RealtimeState<CustomerInvoicesData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onCustomerChanged(
    CustomerInvoicesCustomerChanged event,
    Emitter<RealtimeState<CustomerInvoicesData>> emit,
  ) async {
    _customerId = event.customerId;
    refresh();
  }

  Future<CustomerInvoicesData> _loadData() async {
    // ── Customer list for the selector ──
    final customerRows = await _db.customSelect(
      '''
      SELECT c.id, c.name, c.phone, c.balance_cents
      FROM customers c WHERE c.is_active = 1
      ORDER BY c.name ASC
      ''',
      readsFrom: {_db.customers},
    ).get();

    final customers = customerRows
        .map((r) => CustomerInvoiceOption(
              id: r.read<int>('id'),
              name: r.read<String>('name'),
              phone: r.readNullable<String>('phone'),
              balanceCents: r.read<int>('balance_cents'),
            ))
        .toList();

    if (_customerId == null) {
      return CustomerInvoicesData(dateRange: _dateRange, customers: customers);
    }

    // ── Customer info ──
    final cRows = await _db.customSelect(
      'SELECT name, phone, address FROM customers WHERE id = ?',
      variables: [Variable.withInt(_customerId!)],
      readsFrom: {_db.customers},
    ).get();
    if (cRows.isEmpty) {
      return CustomerInvoicesData(dateRange: _dateRange, customers: customers);
    }
    final cInfo = cRows.first;

    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = DateTime(
      _dateRange.endDate.year,
      _dateRange.endDate.month,
      _dateRange.endDate.day,
      23, 59, 59,
    ).toIso8601String();

    // ── Invoices (sales) in range ──
    final saleRows = await _db.customSelect(
      '''
      SELECT s.id, s.invoice_number, s.subtotal_cents, s.discount_cents,
             s.tax_cents, s.total_cents, s.paid_amount_cents,
             s.payment_method, s.status, s.sale_date
      FROM sales s
      WHERE s.customer_id = ?
        AND s.status != 'voided'
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      ORDER BY s.sale_date ASC, s.id ASC
      ''',
      variables: [
        Variable.withInt(_customerId!),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.sales},
    ).get();

    int totalAmount = 0;
    int totalDiscount = 0;
    int totalPaid = 0;
    int totalQty = 0;

    final invoices = <CustomerInvoice>[];

    for (final row in saleRows) {
      final saleId = row.read<int>('id');
      final items = await _loadInvoiceItems(saleId);

      final invoice = CustomerInvoice(
        id: saleId,
        invoiceNumber: row.read<String>('invoice_number'),
        date: DateTime.parse(row.read<String>('sale_date')),
        subtotalCents: row.read<int>('subtotal_cents'),
        discountCents: row.read<int>('discount_cents'),
        taxCents: row.read<int>('tax_cents'),
        totalCents: row.read<int>('total_cents'),
        paidAmountCents: row.read<int>('paid_amount_cents'),
        paymentMethod: row.read<String>('payment_method'),
        status: row.read<String>('status'),
        items: items,
      );

      totalAmount += invoice.totalCents;
      totalDiscount += invoice.discountCents;
      totalPaid += invoice.paidAmountCents;
      totalQty += invoice.totalQuantity;

      invoices.add(invoice);
    }

    return CustomerInvoicesData(
      customerId: _customerId,
      customerName: cInfo.read<String>('name'),
      customerPhone: cInfo.readNullable<String>('phone'),
      customerAddress: cInfo.readNullable<String>('address'),
      invoices: invoices,
      totalAmountCents: totalAmount,
      totalDiscountCents: totalDiscount,
      totalPaidCents: totalPaid,
      totalQuantity: totalQty,
      dateRange: _dateRange,
      customers: customers,
    );
  }

  Future<List<InvoiceLineItem>> _loadInvoiceItems(int saleId) async {
    final rows = await _db.customSelect(
      '''
      SELECT p.name AS product_name,
             pc.name AS color_name,
             sz.name AS size_name,
             si.quantity AS quantity,
             si.unit_price_cents AS unit_price_cents,
             si.total_cents AS total_cents
      FROM sale_items si
      INNER JOIN products p ON p.id = si.product_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      LEFT JOIN product_colors pc ON pc.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE si.sale_id = ?
      ORDER BY si.id ASC
      ''',
      variables: [Variable.withInt(saleId)],
      readsFrom: {
        _db.saleItems,
        _db.products,
        _db.productVariants,
        _db.productColors,
        _db.sizes,
      },
    ).get();

    return rows.map((r) {
      final parts = <String>[];
      final color = r.readNullable<String>('color_name');
      final size = r.readNullable<String>('size_name');
      if (color != null && color.isNotEmpty) parts.add(color);
      if (size != null && size.isNotEmpty) parts.add(size);
      return InvoiceLineItem(
        productName: r.read<String>('product_name'),
        variantLabel: parts.isEmpty ? null : parts.join(' · '),
        quantity: r.read<int>('quantity'),
        unitPriceCents: r.read<int>('unit_price_cents'),
        totalCents: r.read<int>('total_cents'),
      );
    }).toList();
  }
}
