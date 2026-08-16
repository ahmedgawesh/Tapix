import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/party_statement_ledger_service.dart';
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
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.customers, _db.customerTransactions},
        )
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
    final snapshot = await PartyStatementLedgerService(_db).loadCustomer(
      customerId: _customerId,
      startDate: _dateRange.startDate,
      endDate: _dateRange.endDate,
    );
    final customers = snapshot.options
        .map(
          (option) => CustomerLedgerOption(
            id: option.id,
            name: option.name,
            phone: option.phone,
            balanceCents: option.balanceCents,
          ),
        )
        .toList();
    final customer = snapshot.party;
    if (customer == null) {
      return CustomerLedgerData(dateRange: _dateRange, customers: customers);
    }

    var totalSales = 0;
    var totalReturns = 0;
    var totalPayments = 0;
    var totalDiscounts = 0;
    var totalSaleItems = 0;
    var totalReturnItems = 0;
    final ledgerRows = <CustomerLedgerRow>[];

    for (final transaction in snapshot.transactions) {
      final type = transaction.type;
      final amountCents = transaction.amountCents;
      final txNumber = transaction.transactionNumber;
      final refId = transaction.referenceId;
      final date = transaction.date;
      final runningBalance = transaction.runningBalanceCents;

      final isSaleTx = type == 'sale' || type == 'sale_void';
      final isLinkedReturnTx =
          type == 'credit_note' ||
          type == 'sale_return' ||
          type == 'return' ||
          type == 'credit_note_reversal' ||
          type == 'sale_return_reversal';
      final isAdjustmentReturnTx =
          type == 'adjustment_return' || type == 'adjustment_return_reversal';
      final isReturnTx = isLinkedReturnTx || isAdjustmentReturnTx;

      var totalPiecesCount = 0;
      if (refId != null && isSaleTx) {
        totalPiecesCount = await _getTotalPieces(refId, 'sale');
      } else if (refId != null && isLinkedReturnTx) {
        totalPiecesCount = await _getTotalPieces(refId, 'sale_return');
      } else if (refId != null && isAdjustmentReturnTx) {
        totalPiecesCount = await _getAdjReturnTotalPieces(refId);
      }

      String? resolvedReturnNumber;
      if (isLinkedReturnTx && refId != null) {
        resolvedReturnNumber = await _getReturnNumber(refId);
      } else if (isAdjustmentReturnTx && refId != null) {
        resolvedReturnNumber = await _getAdjReturnNumber(refId);
      }

      if (isReturnTx) {
        final returnValue = -amountCents;
        totalReturns += returnValue;
        totalReturnItems += amountCents < 0
            ? totalPiecesCount
            : amountCents > 0
            ? -totalPiecesCount
            : 0;
        final label =
            resolvedReturnNumber ??
            txNumber ??
            (refId != null ? 'RET-$refId' : null);
        ledgerRows.add(
          CustomerLedgerRow(
            date: date,
            returnId: refId,
            returnNumber: isAdjustmentReturnTx ? '${label ?? ''} ⓐ' : label,
            returnItemCount: totalPiecesCount,
            returnTotalCents: returnValue,
            runningBalanceCents: runningBalance,
          ),
        );
      } else if (isSaleTx) {
        totalSales += amountCents;
        totalSaleItems += amountCents > 0
            ? totalPiecesCount
            : amountCents < 0
            ? -totalPiecesCount
            : 0;
        ledgerRows.add(
          CustomerLedgerRow(
            date: date,
            saleId: refId,
            saleNumber: txNumber ?? (refId != null ? 'SAL-$refId' : null),
            saleItemCount: totalPiecesCount,
            saleTotalCents: amountCents,
            runningBalanceCents: runningBalance,
          ),
        );
      } else if (type == 'payment' || type == 'payment_reversal') {
        final paymentValue = -amountCents;
        totalPayments += paymentValue;
        ledgerRows.add(
          CustomerLedgerRow(
            date: date,
            paymentNumber: txNumber,
            paymentAmountCents: paymentValue,
            runningBalanceCents: runningBalance,
          ),
        );
      } else if (type == 'discount' || type == 'discount_reversal') {
        final discountValue = -amountCents;
        totalDiscounts += discountValue;
        ledgerRows.add(
          CustomerLedgerRow(
            date: date,
            discountNumber: txNumber,
            discountAmountCents: discountValue,
            runningBalanceCents: runningBalance,
          ),
        );
      } else if (amountCents < 0) {
        totalPayments += -amountCents;
        ledgerRows.add(
          CustomerLedgerRow(
            date: date,
            paymentNumber: txNumber,
            paymentAmountCents: -amountCents,
            runningBalanceCents: runningBalance,
          ),
        );
      } else {
        totalSales += amountCents;
        ledgerRows.add(
          CustomerLedgerRow(
            date: date,
            saleNumber: txNumber,
            saleTotalCents: amountCents,
            runningBalanceCents: runningBalance,
          ),
        );
      }
    }

    return CustomerLedgerData(
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      customerAddress: customer.address,
      openingBalanceCents: snapshot.openingBalanceCents,
      closingBalanceCents: snapshot.closingBalanceCents,
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
        final result = await _db
            .customSelect(
              'SELECT COALESCE(SUM(quantity), 0) AS total_qty FROM sale_items WHERE sale_id = ?',
              variables: [Variable.withInt(refId)],
              readsFrom: {_db.saleItems},
            )
            .getSingle();
        return result.read<int>('total_qty');
      } else if (refType == 'sale_return') {
        final result = await _db
            .customSelect(
              'SELECT COALESCE(SUM(quantity), 0) AS total_qty FROM sale_return_items WHERE return_id = ?',
              variables: [Variable.withInt(refId)],
              readsFrom: {_db.saleReturnItems},
            )
            .getSingle();
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
      final result = await _db
          .customSelect(
            'SELECT return_number FROM sale_returns WHERE id = ?',
            variables: [Variable.withInt(returnId)],
            readsFrom: {_db.saleReturns},
          )
          .getSingleOrNull();
      return result?.readNullable<String>('return_number');
    } catch (_) {
      return null;
    }
  }

  /// Get total pieces for a sale adjustment return
  Future<int> _getAdjReturnTotalPieces(int returnId) async {
    try {
      final result = await _db
          .customSelect(
            'SELECT COALESCE(SUM(quantity), 0) AS total_qty FROM sale_return_adjustment_items WHERE return_id = ?',
            variables: [Variable.withInt(returnId)],
            readsFrom: {_db.saleReturnAdjustmentItems},
          )
          .getSingle();
      return result.read<int>('total_qty');
    } catch (_) {
      return 0;
    }
  }

  /// Get the return number from the sale_return_adjustments table
  Future<String?> _getAdjReturnNumber(int returnId) async {
    try {
      final result = await _db
          .customSelect(
            'SELECT return_number FROM sale_return_adjustments WHERE id = ?',
            variables: [Variable.withInt(returnId)],
            readsFrom: {_db.saleReturnAdjustments},
          )
          .getSingleOrNull();
      return result?.readNullable<String>('return_number');
    } catch (_) {
      return null;
    }
  }
}
