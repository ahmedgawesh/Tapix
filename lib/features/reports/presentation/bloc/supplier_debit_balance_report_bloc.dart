import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierDebitBalanceReportEvent extends RealtimeEvent {
  const SupplierDebitBalanceReportEvent();
}

class SupplierDebitBalanceReportDateRangeChanged
    extends SupplierDebitBalanceReportEvent {
  final ReportDateRange dateRange;
  const SupplierDebitBalanceReportDateRangeChanged(this.dateRange);
}

class SupplierDebitBalanceReportSortChanged
    extends SupplierDebitBalanceReportEvent {
  final SupplierDebitBalanceSortType sort;
  const SupplierDebitBalanceReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum SupplierDebitBalanceSortType {
  balanceDesc,
  balanceAsc,
  nameAsc,
  nameDesc,
  purchasesDesc,
  paymentsDesc,
}

// ==================== DATA MODELS ====================

class SupplierDebitBalanceItem {
  final int supplierId;
  final String supplierName;
  final String? phone;
  final int totalPurchasesCents;
  final int totalReturnsCents;
  final int totalPaymentsCents;
  final int totalDiscountsCents;
  final int debitBalanceCents;
  final int transactionCount;
  final DateTime? lastTransactionAt;

  const SupplierDebitBalanceItem({
    required this.supplierId,
    required this.supplierName,
    this.phone,
    required this.totalPurchasesCents,
    required this.totalReturnsCents,
    required this.totalPaymentsCents,
    required this.totalDiscountsCents,
    required this.debitBalanceCents,
    required this.transactionCount,
    this.lastTransactionAt,
  });
}

class SupplierDebitBalanceReportData {
  final List<SupplierDebitBalanceItem> suppliers;
  final int grandTotalPurchasesCents;
  final int grandTotalReturnsCents;
  final int grandTotalPaymentsCents;
  final int grandTotalDiscountsCents;
  final int grandTotalDebitBalanceCents;
  final int totalSuppliers;
  final ReportDateRange dateRange;
  final SupplierDebitBalanceSortType sort;

  const SupplierDebitBalanceReportData({
    this.suppliers = const [],
    this.grandTotalPurchasesCents = 0,
    this.grandTotalReturnsCents = 0,
    this.grandTotalPaymentsCents = 0,
    this.grandTotalDiscountsCents = 0,
    this.grandTotalDebitBalanceCents = 0,
    this.totalSuppliers = 0,
    required this.dateRange,
    this.sort = SupplierDebitBalanceSortType.balanceDesc,
  });

  SupplierDebitBalanceReportData copyWith({
    List<SupplierDebitBalanceItem>? suppliers,
    int? grandTotalPurchasesCents,
    int? grandTotalReturnsCents,
    int? grandTotalPaymentsCents,
    int? grandTotalDiscountsCents,
    int? grandTotalDebitBalanceCents,
    int? totalSuppliers,
    ReportDateRange? dateRange,
    SupplierDebitBalanceSortType? sort,
  }) {
    return SupplierDebitBalanceReportData(
      suppliers: suppliers ?? this.suppliers,
      grandTotalPurchasesCents:
          grandTotalPurchasesCents ?? this.grandTotalPurchasesCents,
      grandTotalReturnsCents:
          grandTotalReturnsCents ?? this.grandTotalReturnsCents,
      grandTotalPaymentsCents:
          grandTotalPaymentsCents ?? this.grandTotalPaymentsCents,
      grandTotalDiscountsCents:
          grandTotalDiscountsCents ?? this.grandTotalDiscountsCents,
      grandTotalDebitBalanceCents:
          grandTotalDebitBalanceCents ?? this.grandTotalDebitBalanceCents,
      totalSuppliers: totalSuppliers ?? this.totalSuppliers,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class SupplierDebitBalanceReportBloc extends RealtimeBloc<
    SupplierDebitBalanceReportData, SupplierDebitBalanceReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  SupplierDebitBalanceSortType _sort = SupplierDebitBalanceSortType.balanceDesc;

  SupplierDebitBalanceReportBloc(this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<SupplierDebitBalanceReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SupplierDebitBalanceReportDateRangeChanged>(_onDateRangeChanged);
    on<SupplierDebitBalanceReportSortChanged>(_onSortChanged);
  }

  Stream<SupplierDebitBalanceReportData> _buildCombinedStream() {
    return _db.select(_db.supplierTransactions).watch().asyncMap((_) async {
      final items = await _loadSupplierDebitBalances();

      int totalPurchases = 0;
      int totalReturns = 0;
      int totalPayments = 0;
      int totalDiscounts = 0;
      int totalDebitBalance = 0;

      for (final item in items) {
        totalPurchases += item.totalPurchasesCents;
        totalReturns += item.totalReturnsCents;
        totalPayments += item.totalPaymentsCents;
        totalDiscounts += item.totalDiscountsCents;
        totalDebitBalance += item.debitBalanceCents;
      }

      final sorted = _applySortToSuppliers(items, _sort);

      return SupplierDebitBalanceReportData(
        suppliers: sorted,
        grandTotalPurchasesCents: totalPurchases,
        grandTotalReturnsCents: totalReturns,
        grandTotalPaymentsCents: totalPayments,
        grandTotalDiscountsCents: totalDiscounts,
        grandTotalDebitBalanceCents: totalDebitBalance,
        totalSuppliers: items.length,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    SupplierDebitBalanceReportDateRangeChanged event,
    Emitter<RealtimeState<SupplierDebitBalanceReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    SupplierDebitBalanceReportSortChanged event,
    Emitter<RealtimeState<SupplierDebitBalanceReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToSuppliers(current.suppliers, event.sort);
      emit(RealtimeSuccess<SupplierDebitBalanceReportData>(
        data: current.copyWith(
          suppliers: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<SupplierDebitBalanceItem> _applySortToSuppliers(
    List<SupplierDebitBalanceItem> items,
    SupplierDebitBalanceSortType sort,
  ) {
    final list = List<SupplierDebitBalanceItem>.from(items);
    switch (sort) {
      case SupplierDebitBalanceSortType.balanceDesc:
        list.sort(
            (a, b) => b.debitBalanceCents.compareTo(a.debitBalanceCents));
      case SupplierDebitBalanceSortType.balanceAsc:
        list.sort(
            (a, b) => a.debitBalanceCents.compareTo(b.debitBalanceCents));
      case SupplierDebitBalanceSortType.nameAsc:
        list.sort((a, b) => a.supplierName.compareTo(b.supplierName));
      case SupplierDebitBalanceSortType.nameDesc:
        list.sort((a, b) => b.supplierName.compareTo(a.supplierName));
      case SupplierDebitBalanceSortType.purchasesDesc:
        list.sort(
            (a, b) => b.totalPurchasesCents.compareTo(a.totalPurchasesCents));
      case SupplierDebitBalanceSortType.paymentsDesc:
        list.sort(
            (a, b) => b.totalPaymentsCents.compareTo(a.totalPaymentsCents));
    }
    return list;
  }

  /// Loads supplier debit balances from supplier_transactions within the date range.
  ///
  /// Balance logic (debit = what we owe):
  /// - Purchases (positive amount_cents) → increase debit balance
  /// - Returns (negative amount_cents, type credit_note) → decrease debit balance
  /// - Payments (negative amount_cents, type payment) → decrease debit balance
  /// - Discounts (negative amount_cents, type discount) → decrease debit balance
  ///
  /// Only suppliers with positive net balance (debit > 0) are included.
  Future<List<SupplierDebitBalanceItem>> _loadSupplierDebitBalances() async {
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
        COALESCE(SUM(st.amount_cents), 0) AS debit_balance_cents,
        COUNT(st.id) AS transaction_count,
        MAX(st.transaction_date) AS last_transaction_at
      FROM suppliers s
      LEFT JOIN supplier_transactions st 
        ON st.supplier_id = s.id
        AND st.transaction_date >= ?
        AND st.transaction_date <= ?
      WHERE s.is_active = 1
      GROUP BY s.id
      HAVING debit_balance_cents > 0
      ORDER BY debit_balance_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.suppliers, _db.supplierTransactions},
    ).get();

    return rows.map((row) {
      final lastTxStr = row.readNullable<String>('last_transaction_at');

      return SupplierDebitBalanceItem(
        supplierId: row.read<int>('supplier_id'),
        supplierName: row.read<String>('supplier_name'),
        phone: row.readNullable<String>('phone'),
        totalPurchasesCents: row.read<int>('total_purchases_cents'),
        totalReturnsCents: row.read<int>('total_returns_cents'),
        totalPaymentsCents: row.read<int>('total_payments_cents'),
        totalDiscountsCents: row.read<int>('total_discounts_cents'),
        debitBalanceCents: row.read<int>('debit_balance_cents'),
        transactionCount: row.read<int>('transaction_count'),
        lastTransactionAt:
            lastTxStr != null ? DateTime.tryParse(lastTxStr) : null,
      );
    }).toList();
  }
}
