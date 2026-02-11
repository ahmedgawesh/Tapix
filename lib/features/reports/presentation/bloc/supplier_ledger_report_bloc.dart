import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
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
  final int balanceCents;

  const SupplierLedgerOption({
    required this.id,
    required this.name,
    required this.balanceCents,
  });
}

// ==================== BLOC ====================

class SupplierLedgerReportBloc
    extends RealtimeBloc<SupplierLedgerData, SupplierLedgerReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  int? _supplierId;

  SupplierLedgerReportBloc(this._db) : super(const RealtimeLoading());

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
        .select(_db.supplierTransactions)
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
    // ── Supplier list ──
    final supplierRows = await _db.customSelect(
      '''
      SELECT s.id, s.name, s.balance_cents
      FROM suppliers s WHERE s.is_active = 1
      ORDER BY s.name ASC
      ''',
      readsFrom: {_db.suppliers},
    ).get();

    final suppliers = supplierRows
        .map((r) => SupplierLedgerOption(
              id: r.read<int>('id'),
              name: r.read<String>('name'),
              balanceCents: r.read<int>('balance_cents'),
            ))
        .toList();

    if (_supplierId == null) {
      return SupplierLedgerData(dateRange: _dateRange, suppliers: suppliers);
    }

    // ── Supplier info ──
    final sRows = await _db.customSelect(
      'SELECT name, phone, address FROM suppliers WHERE id = ?',
      variables: [Variable.withInt(_supplierId!)],
      readsFrom: {_db.suppliers},
    ).get();
    if (sRows.isEmpty) {
      return SupplierLedgerData(dateRange: _dateRange, suppliers: suppliers);
    }
    final sInfo = sRows.first;

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
        s.balance_cents AS current_balance,
        COALESCE(a.total, 0) AS all_total,
        COALESCE(b.total, 0) AS before_total
      FROM suppliers s
      LEFT JOIN (
        SELECT COALESCE(SUM(amount_cents), 0) AS total
        FROM supplier_transactions WHERE supplier_id = ?
      ) a ON 1=1
      LEFT JOIN (
        SELECT COALESCE(SUM(amount_cents), 0) AS total
        FROM supplier_transactions WHERE supplier_id = ? AND transaction_date < ?
      ) b ON 1=1
      WHERE s.id = ?
      ''',
      variables: [
        Variable.withInt(_supplierId!),
        Variable.withInt(_supplierId!),
        Variable.withString(startIso),
        Variable.withInt(_supplierId!),
      ],
      readsFrom: {_db.suppliers, _db.supplierTransactions},
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
        st.id,
        st.transaction_type,
        st.transaction_number,
        st.amount_cents,
        st.description,
        st.reference_id,
        st.reference_type,
        st.transaction_date
      FROM supplier_transactions st
      WHERE st.supplier_id = ?
        AND st.transaction_date >= ?
        AND st.transaction_date <= ?
      ORDER BY st.transaction_date ASC, st.id ASC
      ''',
      variables: [
        Variable.withInt(_supplierId!),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.supplierTransactions},
    ).get();

    // ── Build ledger rows ──
    int runningBalance = openingBalanceCents;
    int totalPurchases = 0;
    int totalReturns = 0;
    int totalPayments = 0;
    int totalDiscounts = 0;
    int totalPurchaseItems = 0;
    int totalReturnItems = 0;

    final ledgerRows = <LedgerRow>[];

    for (final row in txnRows) {
      final type = row.read<String>('transaction_type');
      final amountCents = row.read<int>('amount_cents');
      final txNumber = row.readNullable<String>('transaction_number');
      final refId = row.readNullable<int>('reference_id');
      final refType = row.readNullable<String>('reference_type');
      final date = DateTime.parse(row.read<String>('transaction_date'));

      runningBalance += amountCents;

      // Determine item count for purchase/return from the reference
      int itemCount = 0;
      if (refId != null && (type == 'purchase' || type == 'return')) {
        itemCount = await _getItemCount(refId, refType);
      }

      // Build a ledger row based on type
      switch (type) {
        case 'purchase':
          totalPurchases += amountCents.abs();
          totalPurchaseItems += itemCount;
          ledgerRows.add(LedgerRow(
            date: date,
            purchaseId: refId,
            purchaseNumber: txNumber ?? (refId != null ? 'PUR-$refId' : null),
            purchaseItemCount: itemCount,
            purchaseTotalCents: amountCents.abs(),
            runningBalanceCents: runningBalance,
          ));
          break;
        case 'return':
          totalReturns += amountCents.abs();
          totalReturnItems += itemCount;
          ledgerRows.add(LedgerRow(
            date: date,
            returnId: refId,
            returnNumber: txNumber ?? (refId != null ? 'RET-$refId' : null),
            returnItemCount: itemCount,
            returnTotalCents: amountCents.abs(),
            runningBalanceCents: runningBalance,
          ));
          break;
        case 'payment':
          totalPayments += amountCents.abs();
          ledgerRows.add(LedgerRow(
            date: date,
            paymentNumber: txNumber,
            paymentAmountCents: amountCents.abs(),
            runningBalanceCents: runningBalance,
          ));
          break;
        case 'discount':
          totalDiscounts += amountCents.abs();
          ledgerRows.add(LedgerRow(
            date: date,
            discountNumber: txNumber,
            discountAmountCents: amountCents.abs(),
            runningBalanceCents: runningBalance,
          ));
          break;
        default:
          // credit_note, adjustment, etc. — show as payment-like
          if (amountCents < 0) {
            totalPayments += amountCents.abs();
            ledgerRows.add(LedgerRow(
              date: date,
              paymentNumber: txNumber,
              paymentAmountCents: amountCents.abs(),
              runningBalanceCents: runningBalance,
            ));
          } else {
            totalPurchases += amountCents.abs();
            ledgerRows.add(LedgerRow(
              date: date,
              purchaseNumber: txNumber,
              purchaseTotalCents: amountCents.abs(),
              runningBalanceCents: runningBalance,
            ));
          }
      }
    }

    return SupplierLedgerData(
      supplierId: _supplierId,
      supplierName: sInfo.read<String>('name'),
      supplierPhone: sInfo.readNullable<String>('phone'),
      supplierAddress: sInfo.readNullable<String>('address'),
      openingBalanceCents: openingBalanceCents,
      closingBalanceCents: runningBalance,
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

  /// Get item count for a purchase or return reference
  Future<int> _getItemCount(int refId, String? refType) async {
    try {
      if (refType == 'purchase' || refType == null) {
        final result = await _db.customSelect(
          'SELECT COUNT(*) AS cnt FROM purchase_items WHERE purchase_id = ?',
          variables: [Variable.withInt(refId)],
          readsFrom: {_db.purchaseItems},
        ).getSingle();
        return result.read<int>('cnt');
      } else if (refType == 'purchase_return') {
        final result = await _db.customSelect(
          'SELECT COUNT(*) AS cnt FROM purchase_return_items WHERE purchase_return_id = ?',
          variables: [Variable.withInt(refId)],
          readsFrom: {_db.purchaseReturnItems},
        ).getSingle();
        return result.read<int>('cnt');
      }
    } catch (_) {
      // Table might not exist or other error
    }
    return 0;
  }
}
