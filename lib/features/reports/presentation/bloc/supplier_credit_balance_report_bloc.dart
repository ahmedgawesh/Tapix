import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierCreditBalanceReportEvent extends RealtimeEvent {
  const SupplierCreditBalanceReportEvent();
}

class SupplierCreditBalanceReportDateRangeChanged
    extends SupplierCreditBalanceReportEvent {
  final ReportDateRange dateRange;
  const SupplierCreditBalanceReportDateRangeChanged(this.dateRange);
}

class SupplierCreditBalanceReportSortChanged
    extends SupplierCreditBalanceReportEvent {
  final SupplierCreditBalanceSortType sort;
  const SupplierCreditBalanceReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum SupplierCreditBalanceSortType {
  balanceDesc,
  balanceAsc,
  nameAsc,
  nameDesc,
  purchasesDesc,
  paymentsDesc,
}

// ==================== DATA MODELS ====================

class SupplierCreditBalanceItem {
  final int supplierId;
  final String supplierName;
  final String? phone;
  final int totalPurchasesCents;
  final int totalReturnsCents;
  final int totalPaymentsCents;
  final int totalDiscountsCents;
  final int creditBalanceCents;
  final int transactionCount;
  final DateTime? lastTransactionAt;

  const SupplierCreditBalanceItem({
    required this.supplierId,
    required this.supplierName,
    this.phone,
    required this.totalPurchasesCents,
    required this.totalReturnsCents,
    required this.totalPaymentsCents,
    required this.totalDiscountsCents,
    required this.creditBalanceCents,
    required this.transactionCount,
    this.lastTransactionAt,
  });
}

class SupplierCreditBalanceReportData {
  final List<SupplierCreditBalanceItem> suppliers;
  final int grandTotalPurchasesCents;
  final int grandTotalReturnsCents;
  final int grandTotalPaymentsCents;
  final int grandTotalDiscountsCents;
  final int grandTotalCreditBalanceCents;
  final int totalSuppliers;
  final ReportDateRange dateRange;
  final SupplierCreditBalanceSortType sort;

  const SupplierCreditBalanceReportData({
    this.suppliers = const [],
    this.grandTotalPurchasesCents = 0,
    this.grandTotalReturnsCents = 0,
    this.grandTotalPaymentsCents = 0,
    this.grandTotalDiscountsCents = 0,
    this.grandTotalCreditBalanceCents = 0,
    this.totalSuppliers = 0,
    required this.dateRange,
    this.sort = SupplierCreditBalanceSortType.balanceDesc,
  });

  SupplierCreditBalanceReportData copyWith({
    List<SupplierCreditBalanceItem>? suppliers,
    int? grandTotalPurchasesCents,
    int? grandTotalReturnsCents,
    int? grandTotalPaymentsCents,
    int? grandTotalDiscountsCents,
    int? grandTotalCreditBalanceCents,
    int? totalSuppliers,
    ReportDateRange? dateRange,
    SupplierCreditBalanceSortType? sort,
  }) {
    return SupplierCreditBalanceReportData(
      suppliers: suppliers ?? this.suppliers,
      grandTotalPurchasesCents:
          grandTotalPurchasesCents ?? this.grandTotalPurchasesCents,
      grandTotalReturnsCents:
          grandTotalReturnsCents ?? this.grandTotalReturnsCents,
      grandTotalPaymentsCents:
          grandTotalPaymentsCents ?? this.grandTotalPaymentsCents,
      grandTotalDiscountsCents:
          grandTotalDiscountsCents ?? this.grandTotalDiscountsCents,
      grandTotalCreditBalanceCents:
          grandTotalCreditBalanceCents ?? this.grandTotalCreditBalanceCents,
      totalSuppliers: totalSuppliers ?? this.totalSuppliers,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class SupplierCreditBalanceReportBloc extends RealtimeBloc<
    SupplierCreditBalanceReportData, SupplierCreditBalanceReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  SupplierCreditBalanceSortType _sort =
      SupplierCreditBalanceSortType.balanceDesc;

  SupplierCreditBalanceReportBloc(this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<SupplierCreditBalanceReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SupplierCreditBalanceReportDateRangeChanged>(_onDateRangeChanged);
    on<SupplierCreditBalanceReportSortChanged>(_onSortChanged);
  }

  Stream<SupplierCreditBalanceReportData> _buildCombinedStream() {
    return _db.select(_db.supplierTransactions).watch().asyncMap((_) async {
      final items = await _loadSupplierCreditBalances();

      int totalPurchases = 0;
      int totalReturns = 0;
      int totalPayments = 0;
      int totalDiscounts = 0;
      int totalCreditBalance = 0;

      for (final item in items) {
        totalPurchases += item.totalPurchasesCents;
        totalReturns += item.totalReturnsCents;
        totalPayments += item.totalPaymentsCents;
        totalDiscounts += item.totalDiscountsCents;
        totalCreditBalance += item.creditBalanceCents;
      }

      final sorted = _applySortToSuppliers(items, _sort);

      return SupplierCreditBalanceReportData(
        suppliers: sorted,
        grandTotalPurchasesCents: totalPurchases,
        grandTotalReturnsCents: totalReturns,
        grandTotalPaymentsCents: totalPayments,
        grandTotalDiscountsCents: totalDiscounts,
        grandTotalCreditBalanceCents: totalCreditBalance,
        totalSuppliers: items.length,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    SupplierCreditBalanceReportDateRangeChanged event,
    Emitter<RealtimeState<SupplierCreditBalanceReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    SupplierCreditBalanceReportSortChanged event,
    Emitter<RealtimeState<SupplierCreditBalanceReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToSuppliers(current.suppliers, event.sort);
      emit(RealtimeSuccess<SupplierCreditBalanceReportData>(
        data: current.copyWith(
          suppliers: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<SupplierCreditBalanceItem> _applySortToSuppliers(
    List<SupplierCreditBalanceItem> items,
    SupplierCreditBalanceSortType sort,
  ) {
    final list = List<SupplierCreditBalanceItem>.from(items);
    switch (sort) {
      case SupplierCreditBalanceSortType.balanceDesc:
        list.sort(
            (a, b) => b.creditBalanceCents.compareTo(a.creditBalanceCents));
      case SupplierCreditBalanceSortType.balanceAsc:
        list.sort(
            (a, b) => a.creditBalanceCents.compareTo(b.creditBalanceCents));
      case SupplierCreditBalanceSortType.nameAsc:
        list.sort((a, b) => a.supplierName.compareTo(b.supplierName));
      case SupplierCreditBalanceSortType.nameDesc:
        list.sort((a, b) => b.supplierName.compareTo(a.supplierName));
      case SupplierCreditBalanceSortType.purchasesDesc:
        list.sort(
            (a, b) => b.totalPurchasesCents.compareTo(a.totalPurchasesCents));
      case SupplierCreditBalanceSortType.paymentsDesc:
        list.sort(
            (a, b) => b.totalPaymentsCents.compareTo(a.totalPaymentsCents));
    }
    return list;
  }

  /// Loads supplier credit balances from supplier_transactions within the date range.
  ///
  /// Balance logic (credit = what suppliers owe us):
  /// - Purchases (positive amount_cents) → decrease credit (we owe them)
  /// - Returns (negative amount_cents, type credit_note) → increase credit (they owe us)
  /// - Payments (negative amount_cents, type payment) → increase credit (we overpaid)
  /// - Discounts (negative amount_cents, type discount) → increase credit
  ///
  /// Only suppliers with negative net balance (SUM < 0) are included.
  /// Credit balance is stored as ABS value for display purposes.
  Future<List<SupplierCreditBalanceItem>> _loadSupplierCreditBalances() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        s.id AS supplier_id,
        s.name AS supplier_name,
        s.phone AS phone,
        COALESCE(SUM(CASE WHEN st.amount_cents > 0 THEN st.amount_cents ELSE 0 END), 0) AS total_purchases_cents,
        COALESCE(SUM(CASE WHEN st.amount_cents < 0 AND st.transaction_type = 'credit_note' THEN ABS(st.amount_cents) ELSE 0 END), 0) AS total_returns_cents,
        COALESCE(SUM(CASE WHEN st.amount_cents < 0 AND st.transaction_type = 'payment' THEN ABS(st.amount_cents) ELSE 0 END), 0) AS total_payments_cents,
        COALESCE(SUM(CASE WHEN st.amount_cents < 0 AND st.transaction_type = 'discount' THEN ABS(st.amount_cents) ELSE 0 END), 0) AS total_discounts_cents,
        COALESCE(SUM(st.amount_cents), 0) AS net_balance_cents,
        COUNT(st.id) AS transaction_count,
        MAX(st.transaction_date) AS last_transaction_at
      FROM suppliers s
      LEFT JOIN supplier_transactions st 
        ON st.supplier_id = s.id
        AND st.transaction_date >= ?
        AND st.transaction_date <= ?
      WHERE s.is_active = 1
      GROUP BY s.id
      HAVING net_balance_cents < 0
      ORDER BY net_balance_cents ASC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.suppliers, _db.supplierTransactions},
    ).get();

    return rows.map((row) {
      final lastTxStr = row.readNullable<String>('last_transaction_at');
      final netBalanceCents = row.read<int>('net_balance_cents');

      return SupplierCreditBalanceItem(
        supplierId: row.read<int>('supplier_id'),
        supplierName: row.read<String>('supplier_name'),
        phone: row.readNullable<String>('phone'),
        totalPurchasesCents: row.read<int>('total_purchases_cents'),
        totalReturnsCents: row.read<int>('total_returns_cents'),
        totalPaymentsCents: row.read<int>('total_payments_cents'),
        totalDiscountsCents: row.read<int>('total_discounts_cents'),
        creditBalanceCents: netBalanceCents.abs(),
        transactionCount: row.read<int>('transaction_count'),
        lastTransactionAt:
            lastTxStr != null ? DateTime.tryParse(lastTxStr) : null,
      );
    }).toList();
  }
}
