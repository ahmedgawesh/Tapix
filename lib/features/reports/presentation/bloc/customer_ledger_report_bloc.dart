import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/ledger/ledger_running_balance.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerLedgerReportEvent extends RealtimeEvent {
  const CustomerLedgerReportEvent();
}

class CustomerLedgerDateRangeChanged extends CustomerLedgerReportEvent {
  final ReportDateRange dateRange;
  const CustomerLedgerDateRangeChanged(this.dateRange);
}

class CustomerLedgerCustomerChanged extends CustomerLedgerReportEvent {
  final int? customerId;
  const CustomerLedgerCustomerChanged(this.customerId);
}

// ==================== DATA MODELS ====================

/// A single row in the ledger — one per transaction.
class CustomerLedgerRow {
  final DateTime date;

  // Sale invoices
  final int? saleId;
  final String? saleNumber;
  final int saleItemCount;
  final int saleTotalCents;

  // Return invoices
  final int? returnId;
  final String? returnNumber;
  final int returnItemCount;
  final int returnTotalCents;

  // Payment
  final String? paymentNumber;
  final int paymentAmountCents;

  // Discount
  final String? discountNumber;
  final int discountAmountCents;

  // Running balance after this row
  final int runningBalanceCents;

  const CustomerLedgerRow({
    required this.date,
    this.saleId,
    this.saleNumber,
    this.saleItemCount = 0,
    this.saleTotalCents = 0,
    this.returnId,
    this.returnNumber,
    this.returnItemCount = 0,
    this.returnTotalCents = 0,
    this.paymentNumber,
    this.paymentAmountCents = 0,
    this.discountNumber,
    this.discountAmountCents = 0,
    required this.runningBalanceCents,
  });
}

class CustomerLedgerData {
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;

  final int openingBalanceCents;
  final int closingBalanceCents;

  // Subtotals
  final int totalSalesCents;
  final int totalReturnsCents;
  final int totalPaymentsCents;
  final int totalDiscountsCents;

  final int totalSaleItems;
  final int totalReturnItems;

  final List<CustomerLedgerRow> rows;
  final ReportDateRange dateRange;
  final List<CustomerLedgerOption> customers;

  const CustomerLedgerData({
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.openingBalanceCents = 0,
    this.closingBalanceCents = 0,
    this.totalSalesCents = 0,
    this.totalReturnsCents = 0,
    this.totalPaymentsCents = 0,
    this.totalDiscountsCents = 0,
    this.totalSaleItems = 0,
    this.totalReturnItems = 0,
    this.rows = const [],
    required this.dateRange,
    this.customers = const [],
  });
}

class CustomerLedgerOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const CustomerLedgerOption({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

// ==================== BLOC ====================

class CustomerLedgerReportBloc
    extends RealtimeBloc<CustomerLedgerData, CustomerLedgerReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  int? _customerId;

  CustomerLedgerReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;
  int? get customerId => _customerId;

  @override
  Stream<CustomerLedgerData> get dataStream => _buildStream();

  @override
  void registerEventHandlers() {
    on<CustomerLedgerDateRangeChanged>(_onDateRangeChanged);
    on<CustomerLedgerCustomerChanged>(_onCustomerChanged);
  }

  Stream<CustomerLedgerData> _buildStream() {
    return _db
        .select(_db.customerTransactions)
        .watch()
        .asyncMap((_) async => _loadLedgerData());
  }

  Future<void> _onDateRangeChanged(
    CustomerLedgerDateRangeChanged event,
    Emitter<RealtimeState<CustomerLedgerData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onCustomerChanged(
    CustomerLedgerCustomerChanged event,
    Emitter<RealtimeState<CustomerLedgerData>> emit,
  ) async {
    _customerId = event.customerId;
    refresh();
  }

  Future<CustomerLedgerData> _loadLedgerData() async {
    // ── Customer list ──
    final customerRows = await _db.customSelect(
      '''
      SELECT c.id, c.name, c.phone, c.balance_cents
      FROM customers c WHERE c.is_active = 1
      ORDER BY c.name ASC
      ''',
      readsFrom: {_db.customers},
    ).get();

    final customers = customerRows
        .map((r) => CustomerLedgerOption(
              id: r.read<int>('id'),
              name: r.read<String>('name'),
              phone: r.readNullable<String>('phone'),
              balanceCents: r.read<int>('balance_cents'),
            ))
        .toList();

    if (_customerId == null) {
      return CustomerLedgerData(dateRange: _dateRange, customers: customers);
    }

    // ── Customer info ──
    final cRows = await _db.customSelect(
      'SELECT name, phone, address FROM customers WHERE id = ?',
      variables: [Variable.withInt(_customerId!)],
      readsFrom: {_db.customers},
    ).get();
    if (cRows.isEmpty) {
      return CustomerLedgerData(dateRange: _dateRange, customers: customers);
    }
    final cInfo = cRows.first;

    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = DateTime(
      _dateRange.endDate.year,
      _dateRange.endDate.month,
      _dateRange.endDate.day,
      23, 59, 59,
    ).toIso8601String();

    // ── Opening balance ──
    final obRows = await _db.customSelect(
      '''
      SELECT
        c.balance_cents AS current_balance,
        COALESCE(a.total, 0) AS all_total,
        COALESCE(b.total, 0) AS before_total
      FROM customers c
      LEFT JOIN (
        SELECT COALESCE(SUM(amount_cents), 0) AS total
        FROM customer_transactions WHERE customer_id = ?
      ) a ON 1=1
      LEFT JOIN (
        SELECT COALESCE(SUM(amount_cents), 0) AS total
        FROM customer_transactions WHERE customer_id = ? AND transaction_date < ?
      ) b ON 1=1
      WHERE c.id = ?
      ''',
      variables: [
        Variable.withInt(_customerId!),
        Variable.withInt(_customerId!),
        Variable.withString(startIso),
        Variable.withInt(_customerId!),
      ],
      readsFrom: {_db.customers, _db.customerTransactions},
    ).get();

    final int openingBalanceCents;
    if (obRows.isNotEmpty) {
      final r = obRows.first;
      openingBalanceCents = (r.read<int>('current_balance') -
              r.read<int>('all_total')) +
          r.read<int>('before_total');
    } else {
      openingBalanceCents = 0;
    }

    // ── Transactions in range ──
    final txnRows = await _db.customSelect(
      '''
      SELECT
        ct.id,
        ct.transaction_type,
        ct.transaction_number,
        ct.amount_cents,
        ct.description,
        ct.reference_id,
        ct.reference_type,
        ct.transaction_date
      FROM customer_transactions ct
      WHERE ct.customer_id = ?
        AND ct.transaction_date >= ?
        AND ct.transaction_date <= ?
      ORDER BY ct.transaction_date ASC, ct.id ASC
      ''',
      variables: [
        Variable.withInt(_customerId!),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.customerTransactions},
    ).get();

    // ── Build ledger rows ──
    // Phase 7 — running balance via SoT helper.
    final running = LedgerRunningBalance(openingBalanceCents);
    int totalSales = 0;
    int totalReturns = 0;
    int totalPayments = 0;
    int totalDiscounts = 0;
    int totalSaleItems = 0;
    int totalReturnItems = 0;

    final ledgerRows = <CustomerLedgerRow>[];

    for (final row in txnRows) {
      final type = row.read<String>('transaction_type');
      final amountCents = row.read<int>('amount_cents');
      final txNumber = row.readNullable<String>('transaction_number');
      final refId = row.readNullable<int>('reference_id');
      final refType = row.readNullable<String>('reference_type');
      final date = DateTime.parse(row.read<String>('transaction_date'));

      final runningBalance = running.apply(amountCents);

      // Determine if this is a sale return
      final isReturnTx = (type == 'credit_note' || type == 'refund' || type == 'return') &&
          refType == 'sale_return';

      // Adjustment returns (unlinked returns)
      final isAdjReturnTx = type == 'adjustment_return';
      final isAdjReturnReversalTx = type == 'adjustment_return_reversal';

      // Determine total pieces for sale/return from the reference
      int totalPiecesCount = 0;
      if (refId != null && (type == 'sale' || isReturnTx)) {
        totalPiecesCount = await _getTotalPieces(refId, refType);
      } else if (isAdjReturnTx && refId != null) {
        totalPiecesCount = await _getAdjReturnTotalPieces(refId);
      }

      // For return transactions, fetch the return number from sale_returns table
      String? resolvedReturnNumber;
      if (isReturnTx && refId != null) {
        resolvedReturnNumber = await _getReturnNumber(refId);
      } else if (isAdjReturnTx && refId != null) {
        resolvedReturnNumber = await _getAdjReturnNumber(refId);
      }

      // Build a ledger row based on type
      if (isReturnTx || isAdjReturnTx) {
        // Sale return or adjustment return — show in return columns
        totalReturns += amountCents.abs();
        totalReturnItems += totalPiecesCount;
        final label = resolvedReturnNumber ?? txNumber ?? (refId != null ? 'RET-$refId' : null);
        ledgerRows.add(CustomerLedgerRow(
          date: date,
          returnId: refId,
          returnNumber: isAdjReturnTx ? '${label ?? ''} ⓐ' : label,
          returnItemCount: totalPiecesCount,
          returnTotalCents: amountCents.abs(),
          runningBalanceCents: runningBalance,
        ));
      } else if (isAdjReturnReversalTx) {
        // Voided adjustment return — show as negative return (reversal)
        totalReturns -= amountCents.abs();
        ledgerRows.add(CustomerLedgerRow(
          date: date,
          returnId: refId,
          returnNumber: '${txNumber ?? 'REV-$refId'} ⓐ',
          returnItemCount: 0,
          returnTotalCents: amountCents.abs(),
          runningBalanceCents: runningBalance,
        ));
      } else if (type == 'sale') {
        totalSales += amountCents.abs();
        totalSaleItems += totalPiecesCount;
        ledgerRows.add(CustomerLedgerRow(
          date: date,
          saleId: refId,
          saleNumber: txNumber ?? (refId != null ? 'SAL-$refId' : null),
          saleItemCount: totalPiecesCount,
          saleTotalCents: amountCents.abs(),
          runningBalanceCents: runningBalance,
        ));
      } else if (type == 'payment') {
        totalPayments += amountCents.abs();
        ledgerRows.add(CustomerLedgerRow(
          date: date,
          paymentNumber: txNumber,
          paymentAmountCents: amountCents.abs(),
          runningBalanceCents: runningBalance,
        ));
      } else if (type == 'discount') {
        totalDiscounts += amountCents.abs();
        ledgerRows.add(CustomerLedgerRow(
          date: date,
          discountNumber: txNumber,
          discountAmountCents: amountCents.abs(),
          runningBalanceCents: runningBalance,
        ));
      } else {
        // adjustment, etc. — show as payment-like or sale-like
        if (amountCents < 0) {
          totalPayments += amountCents.abs();
          ledgerRows.add(CustomerLedgerRow(
            date: date,
            paymentNumber: txNumber,
            paymentAmountCents: amountCents.abs(),
            runningBalanceCents: runningBalance,
          ));
        } else {
          totalSales += amountCents.abs();
          ledgerRows.add(CustomerLedgerRow(
            date: date,
            saleNumber: txNumber,
            saleTotalCents: amountCents.abs(),
            runningBalanceCents: runningBalance,
          ));
        }
      }
    }

    return CustomerLedgerData(
      customerId: _customerId,
      customerName: cInfo.read<String>('name'),
      customerPhone: cInfo.readNullable<String>('phone'),
      customerAddress: cInfo.readNullable<String>('address'),
      openingBalanceCents: openingBalanceCents,
      closingBalanceCents: running.current,
      totalSalesCents: totalSales,
      totalReturnsCents: totalReturns,
      totalPaymentsCents: totalPayments,
      totalDiscountsCents: totalDiscounts,
      totalSaleItems: totalSaleItems,
      totalReturnItems: totalReturnItems,
      rows: ledgerRows,
      dateRange: _dateRange,
      customers: customers,
    );
  }

  /// Get total pieces (sum of quantities) for a sale or return reference
  Future<int> _getTotalPieces(int refId, String? refType) async {
    try {
      if (refType == 'sale' || refType == null) {
        final result = await _db.customSelect(
          'SELECT COALESCE(SUM(quantity), 0) AS total_qty FROM sale_items WHERE sale_id = ?',
          variables: [Variable.withInt(refId)],
          readsFrom: {_db.saleItems},
        ).getSingle();
        return result.read<int>('total_qty');
      } else if (refType == 'sale_return') {
        final result = await _db.customSelect(
          'SELECT COALESCE(SUM(quantity), 0) AS total_qty FROM sale_return_items WHERE return_id = ?',
          variables: [Variable.withInt(refId)],
          readsFrom: {_db.saleReturnItems},
        ).getSingle();
        return result.read<int>('total_qty');
      }
    } catch (_) {
      // Table might not exist or other error
    }
    return 0;
  }

  /// Get the return number from the sale_returns table
  Future<String?> _getReturnNumber(int returnId) async {
    try {
      final result = await _db.customSelect(
        'SELECT return_number FROM sale_returns WHERE id = ?',
        variables: [Variable.withInt(returnId)],
        readsFrom: {_db.saleReturns},
      ).getSingleOrNull();
      return result?.readNullable<String>('return_number');
    } catch (_) {
      return null;
    }
  }

  /// Get total pieces for a sale adjustment return
  Future<int> _getAdjReturnTotalPieces(int returnId) async {
    try {
      final result = await _db.customSelect(
        'SELECT COALESCE(SUM(quantity), 0) AS total_qty FROM sale_return_adjustment_items WHERE return_id = ?',
        variables: [Variable.withInt(returnId)],
        readsFrom: {_db.saleReturnAdjustmentItems},
      ).getSingle();
      return result.read<int>('total_qty');
    } catch (_) {
      return 0;
    }
  }

  /// Get the return number from the sale_return_adjustments table
  Future<String?> _getAdjReturnNumber(int returnId) async {
    try {
      final result = await _db.customSelect(
        'SELECT return_number FROM sale_return_adjustments WHERE id = ?',
        variables: [Variable.withInt(returnId)],
        readsFrom: {_db.saleReturnAdjustments},
      ).getSingleOrNull();
      return result?.readNullable<String>('return_number');
    } catch (_) {
      return null;
    }
  }
}
