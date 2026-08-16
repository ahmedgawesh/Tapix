import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/party_statement_ledger_service.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierLedgerReportEvent extends RealtimeEvent {
  const SupplierLedgerReportEvent();
}

class SupplierLedgerDateRangeChanged extends SupplierLedgerReportEvent {
  final ReportDateRange dateRange;
  const SupplierLedgerDateRangeChanged(this.dateRange);
}

class SupplierLedgerSupplierChanged extends SupplierLedgerReportEvent {
  final int? supplierId;
  const SupplierLedgerSupplierChanged(this.supplierId);
}

// ==================== DATA MODELS ====================

/// A single row in the ledger — one per day that has activity.
class LedgerRow {
  final DateTime date;

  // Purchase invoices
  final int? purchaseId;
  final String? purchaseNumber;
  final int purchaseItemCount;
  final int purchaseTotalCents;

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

  const LedgerRow({
    required this.date,
    this.purchaseId,
    this.purchaseNumber,
    this.purchaseItemCount = 0,
    this.purchaseTotalCents = 0,
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

class SupplierLedgerData {
  final int? supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final String? supplierAddress;

  final int openingBalanceCents;
  final int closingBalanceCents;

  // Subtotals
  final int totalPurchasesCents;
  final int totalReturnsCents;
  final int totalPaymentsCents;
  final int totalDiscountsCents;

  final int totalPurchaseItems;
  final int totalReturnItems;

  final List<LedgerRow> rows;
  final ReportDateRange dateRange;
  final List<SupplierLedgerOption> suppliers;

  const SupplierLedgerData({
    this.supplierId,
    this.supplierName,
    this.supplierPhone,
    this.supplierAddress,
    this.openingBalanceCents = 0,
    this.closingBalanceCents = 0,
    this.totalPurchasesCents = 0,
    this.totalReturnsCents = 0,
    this.totalPaymentsCents = 0,
    this.totalDiscountsCents = 0,
    this.totalPurchaseItems = 0,
    this.totalReturnItems = 0,
    this.rows = const [],
    required this.dateRange,
    this.suppliers = const [],
  });
}

class SupplierLedgerOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const SupplierLedgerOption({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

// ==================== BLOC ====================

class SupplierLedgerReportBloc
    extends RealtimeBloc<SupplierLedgerData, SupplierLedgerReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  int? _supplierId;

  SupplierLedgerReportBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;
  int? get supplierId => _supplierId;

  @override
  Stream<SupplierLedgerData> get dataStream => _buildStream();

  @override
  void registerEventHandlers() {
    on<SupplierLedgerDateRangeChanged>(_onDateRangeChanged);
    on<SupplierLedgerSupplierChanged>(_onSupplierChanged);
  }

  Stream<SupplierLedgerData> _buildStream() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.suppliers, _db.supplierTransactions},
        )
        .watch()
        .asyncMap((_) async => _loadLedgerData());
  }

  Future<void> _onDateRangeChanged(
    SupplierLedgerDateRangeChanged event,
    Emitter<RealtimeState<SupplierLedgerData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSupplierChanged(
    SupplierLedgerSupplierChanged event,
    Emitter<RealtimeState<SupplierLedgerData>> emit,
  ) async {
    _supplierId = event.supplierId;
    refresh();
  }

  Future<SupplierLedgerData> _loadLedgerData() async {
    final snapshot = await PartyStatementLedgerService(_db).loadSupplier(
      supplierId: _supplierId,
      startDate: _dateRange.startDate,
      endDate: _dateRange.endDate,
    );
    final suppliers = snapshot.options
        .map(
          (option) => SupplierLedgerOption(
            id: option.id,
            name: option.name,
            phone: option.phone,
            balanceCents: option.balanceCents,
          ),
        )
        .toList();
    final supplier = snapshot.party;
    if (supplier == null) {
      return SupplierLedgerData(dateRange: _dateRange, suppliers: suppliers);
    }

    var totalPurchases = 0;
    var totalReturns = 0;
    var totalPayments = 0;
    var totalDiscounts = 0;
    var totalPurchaseItems = 0;
    var totalReturnItems = 0;
    final ledgerRows = <LedgerRow>[];

    for (final transaction in snapshot.transactions) {
      final type = transaction.type;
      final amountCents = transaction.amountCents;
      final txNumber = transaction.transactionNumber;
      final refId = transaction.referenceId;
      final date = transaction.date;
      final runningBalance = transaction.runningBalanceCents;

      final isPurchaseTx = type == 'purchase' || type == 'purchase_void';
      final isLinkedReturnTx =
          type == 'credit_note' ||
          type == 'purchase_return' ||
          type == 'credit_note_reversal' ||
          type == 'purchase_return_reversal';
      final isAdjustmentReturnTx =
          type == 'adjustment_return' || type == 'adjustment_return_reversal';
      final isReturnTx = isLinkedReturnTx || isAdjustmentReturnTx;

      var totalPiecesCount = 0;
      if (refId != null && isPurchaseTx) {
        totalPiecesCount = await _getTotalPieces(refId, 'purchase');
      } else if (refId != null && isLinkedReturnTx) {
        totalPiecesCount = await _getTotalPieces(refId, 'purchase_return');
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
          LedgerRow(
            date: date,
            returnId: refId,
            returnNumber: isAdjustmentReturnTx ? '${label ?? ''} ⓐ' : label,
            returnItemCount: totalPiecesCount,
            returnTotalCents: returnValue,
            runningBalanceCents: runningBalance,
          ),
        );
      } else if (isPurchaseTx) {
        totalPurchases += amountCents;
        totalPurchaseItems += amountCents > 0
            ? totalPiecesCount
            : amountCents < 0
            ? -totalPiecesCount
            : 0;
        ledgerRows.add(
          LedgerRow(
            date: date,
            purchaseId: refId,
            purchaseNumber: txNumber ?? (refId != null ? 'PUR-$refId' : null),
            purchaseItemCount: totalPiecesCount,
            purchaseTotalCents: amountCents,
            runningBalanceCents: runningBalance,
          ),
        );
      } else if (type == 'payment' || type == 'payment_reversal') {
        final paymentValue = -amountCents;
        totalPayments += paymentValue;
        ledgerRows.add(
          LedgerRow(
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
          LedgerRow(
            date: date,
            discountNumber: txNumber,
            discountAmountCents: discountValue,
            runningBalanceCents: runningBalance,
          ),
        );
      } else if (amountCents < 0) {
        totalPayments += -amountCents;
        ledgerRows.add(
          LedgerRow(
            date: date,
            paymentNumber: txNumber,
            paymentAmountCents: -amountCents,
            runningBalanceCents: runningBalance,
          ),
        );
      } else {
        totalPurchases += amountCents;
        ledgerRows.add(
          LedgerRow(
            date: date,
            purchaseNumber: txNumber,
            purchaseTotalCents: amountCents,
            runningBalanceCents: runningBalance,
          ),
        );
      }
    }

    return SupplierLedgerData(
      supplierId: supplier.id,
      supplierName: supplier.name,
      supplierPhone: supplier.phone,
      supplierAddress: supplier.address,
      openingBalanceCents: snapshot.openingBalanceCents,
      closingBalanceCents: snapshot.closingBalanceCents,
      totalPurchasesCents: totalPurchases,
      totalReturnsCents: totalReturns,
      totalPaymentsCents: totalPayments,
      totalDiscountsCents: totalDiscounts,
      totalPurchaseItems: totalPurchaseItems,
      totalReturnItems: totalReturnItems,
      rows: ledgerRows,
      dateRange: _dateRange,
      suppliers: suppliers,
    );
  }

  /// Get total pieces (sum of quantities) for a purchase or return reference
  Future<int> _getTotalPieces(int refId, String? refType) async {
    try {
      if (refType == 'purchase' || refType == null) {
        final result = await _db
            .customSelect(
              'SELECT COALESCE(SUM(quantity), 0) AS total_qty FROM purchase_items WHERE purchase_id = ?',
              variables: [Variable.withInt(refId)],
              readsFrom: {_db.purchaseItems},
            )
            .getSingle();
        return result.read<int>('total_qty');
      } else if (refType == 'purchase_return') {
        final result = await _db
            .customSelect(
              'SELECT COALESCE(SUM(quantity), 0) AS total_qty FROM purchase_return_items WHERE return_id = ?',
              variables: [Variable.withInt(refId)],
              readsFrom: {_db.purchaseReturnItems},
            )
            .getSingle();
        return result.read<int>('total_qty');
      }
    } catch (_) {
      // Table might not exist or other error
    }
    return 0;
  }

  /// Get the return number from the purchase_returns table
  Future<String?> _getReturnNumber(int returnId) async {
    try {
      final result = await _db
          .customSelect(
            'SELECT return_number FROM purchase_returns WHERE id = ?',
            variables: [Variable.withInt(returnId)],
            readsFrom: {_db.purchaseReturns},
          )
          .getSingleOrNull();
      return result?.readNullable<String>('return_number');
    } catch (_) {
      return null;
    }
  }

  /// Get total pieces for an adjustment return
  Future<int> _getAdjReturnTotalPieces(int returnId) async {
    try {
      final result = await _db
          .customSelect(
            'SELECT COALESCE(SUM(quantity), 0) AS total_qty FROM purchase_return_adjustment_items WHERE return_id = ?',
            variables: [Variable.withInt(returnId)],
            readsFrom: {_db.purchaseReturnAdjustmentItems},
          )
          .getSingle();
      return result.read<int>('total_qty');
    } catch (_) {
      return 0;
    }
  }

  /// Get the return number from the purchase_return_adjustments table
  Future<String?> _getAdjReturnNumber(int returnId) async {
    try {
      final result = await _db
          .customSelect(
            'SELECT return_number FROM purchase_return_adjustments WHERE id = ?',
            variables: [Variable.withInt(returnId)],
            readsFrom: {_db.purchaseReturnAdjustments},
          )
          .getSingleOrNull();
      return result?.readNullable<String>('return_number');
    } catch (_) {
      return null;
    }
  }
}
