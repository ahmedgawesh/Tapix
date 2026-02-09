import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierBalanceReportEvent extends RealtimeEvent {
  const SupplierBalanceReportEvent();
}

class SupplierBalanceReportDateRangeChanged
    extends SupplierBalanceReportEvent {
  final ReportDateRange dateRange;
  const SupplierBalanceReportDateRangeChanged(this.dateRange);
}

class SupplierBalanceReportSortChanged extends SupplierBalanceReportEvent {
  final SupplierBalanceSortType sort;
  const SupplierBalanceReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum SupplierBalanceSortType {
  balanceDesc,
  balanceAsc,
  nameAsc,
  nameDesc,
  debitDesc,
  creditDesc,
}

// ==================== DATA MODELS ====================

class SupplierBalanceItem {
  final int supplierId;
  final String supplierName;
  final String? phone;
  final int totalDebitCents;
  final int totalCreditCents;
  final int netBalanceCents;
  final int transactionCount;
  final DateTime? lastTransactionAt;

  const SupplierBalanceItem({
    required this.supplierId,
    required this.supplierName,
    this.phone,
    required this.totalDebitCents,
    required this.totalCreditCents,
    required this.netBalanceCents,
    required this.transactionCount,
    this.lastTransactionAt,
  });
}

class SupplierBalanceReportData {
  final List<SupplierBalanceItem> suppliers;
  final int grandTotalDebitCents;
  final int grandTotalCreditCents;
  final int grandNetBalanceCents;
  final int totalSuppliers;
  final int suppliersWithDebit;
  final int suppliersWithCredit;
  final ReportDateRange dateRange;
  final SupplierBalanceSortType sort;

  const SupplierBalanceReportData({
    this.suppliers = const [],
    this.grandTotalDebitCents = 0,
    this.grandTotalCreditCents = 0,
    this.grandNetBalanceCents = 0,
    this.totalSuppliers = 0,
    this.suppliersWithDebit = 0,
    this.suppliersWithCredit = 0,
    required this.dateRange,
    this.sort = SupplierBalanceSortType.balanceDesc,
  });

  SupplierBalanceReportData copyWith({
    List<SupplierBalanceItem>? suppliers,
    int? grandTotalDebitCents,
    int? grandTotalCreditCents,
    int? grandNetBalanceCents,
    int? totalSuppliers,
    int? suppliersWithDebit,
    int? suppliersWithCredit,
    ReportDateRange? dateRange,
    SupplierBalanceSortType? sort,
  }) {
    return SupplierBalanceReportData(
      suppliers: suppliers ?? this.suppliers,
      grandTotalDebitCents: grandTotalDebitCents ?? this.grandTotalDebitCents,
      grandTotalCreditCents:
          grandTotalCreditCents ?? this.grandTotalCreditCents,
      grandNetBalanceCents: grandNetBalanceCents ?? this.grandNetBalanceCents,
      totalSuppliers: totalSuppliers ?? this.totalSuppliers,
      suppliersWithDebit: suppliersWithDebit ?? this.suppliersWithDebit,
      suppliersWithCredit: suppliersWithCredit ?? this.suppliersWithCredit,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class SupplierBalanceReportBloc extends RealtimeBloc<SupplierBalanceReportData,
    SupplierBalanceReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  SupplierBalanceSortType _sort = SupplierBalanceSortType.balanceDesc;

  SupplierBalanceReportBloc(this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<SupplierBalanceReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SupplierBalanceReportDateRangeChanged>(_onDateRangeChanged);
    on<SupplierBalanceReportSortChanged>(_onSortChanged);
  }

  Stream<SupplierBalanceReportData> _buildCombinedStream() {
    // Watch supplier_transactions for real-time changes.
    // Drift table-level watches don't support WHERE clauses, so we watch
    // ALL transactions and re-query with the current date range in asyncMap.
    return _db.select(_db.supplierTransactions).watch().asyncMap((_) async {
      final items = await _loadSupplierBalances();

      int totalDebit = 0;
      int totalCredit = 0;
      int totalNet = 0;
      int withDebit = 0;
      int withCredit = 0;

      for (final item in items) {
        totalDebit += item.totalDebitCents;
        totalCredit += item.totalCreditCents;
        totalNet += item.netBalanceCents;
        if (item.netBalanceCents > 0) withDebit++;
        if (item.netBalanceCents < 0) withCredit++;
      }

      final sorted = _applySortToSuppliers(items, _sort);

      return SupplierBalanceReportData(
        suppliers: sorted,
        grandTotalDebitCents: totalDebit,
        grandTotalCreditCents: totalCredit,
        grandNetBalanceCents: totalNet,
        totalSuppliers: items.length,
        suppliersWithDebit: withDebit,
        suppliersWithCredit: withCredit,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    SupplierBalanceReportDateRangeChanged event,
    Emitter<RealtimeState<SupplierBalanceReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    SupplierBalanceReportSortChanged event,
    Emitter<RealtimeState<SupplierBalanceReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToSuppliers(current.suppliers, event.sort);
      emit(RealtimeSuccess<SupplierBalanceReportData>(
        data: current.copyWith(
          suppliers: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<SupplierBalanceItem> _applySortToSuppliers(
    List<SupplierBalanceItem> items,
    SupplierBalanceSortType sort,
  ) {
    final list = List<SupplierBalanceItem>.from(items);
    switch (sort) {
      case SupplierBalanceSortType.balanceDesc:
        list.sort(
            (a, b) => b.netBalanceCents.abs().compareTo(a.netBalanceCents.abs()));
      case SupplierBalanceSortType.balanceAsc:
        list.sort(
            (a, b) => a.netBalanceCents.abs().compareTo(b.netBalanceCents.abs()));
      case SupplierBalanceSortType.nameAsc:
        list.sort((a, b) => a.supplierName.compareTo(b.supplierName));
      case SupplierBalanceSortType.nameDesc:
        list.sort((a, b) => b.supplierName.compareTo(a.supplierName));
      case SupplierBalanceSortType.debitDesc:
        list.sort((a, b) => b.totalDebitCents.compareTo(a.totalDebitCents));
      case SupplierBalanceSortType.creditDesc:
        list.sort((a, b) => b.totalCreditCents.compareTo(a.totalCreditCents));
    }
    return list;
  }

  /// Loads supplier balances from supplier_transactions within the date range.
  ///
  /// Balance logic:
  /// - Positive amount_cents in supplier_transactions = debit (we owe more)
  ///   e.g. purchases increase what we owe
  /// - Negative amount_cents = credit (reduces what we owe)
  ///   e.g. payments, returns reduce what we owe
  /// - Net balance = SUM(amount_cents) per supplier
  ///   Positive net = we owe the supplier (debit/payable)
  ///   Negative net = supplier owes us (credit/receivable)
  Future<List<SupplierBalanceItem>> _loadSupplierBalances() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        s.id AS supplier_id,
        s.name AS supplier_name,
        s.phone AS phone,
        COALESCE(SUM(CASE WHEN st.amount_cents > 0 THEN st.amount_cents ELSE 0 END), 0) AS total_debit_cents,
        COALESCE(SUM(CASE WHEN st.amount_cents < 0 THEN ABS(st.amount_cents) ELSE 0 END), 0) AS total_credit_cents,
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
      HAVING transaction_count > 0
      ORDER BY ABS(net_balance_cents) DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.suppliers, _db.supplierTransactions},
    ).get();

    return rows.map((row) {
      final lastTxStr = row.readNullable<String>('last_transaction_at');

      return SupplierBalanceItem(
        supplierId: row.read<int>('supplier_id'),
        supplierName: row.read<String>('supplier_name'),
        phone: row.readNullable<String>('phone'),
        totalDebitCents: row.read<int>('total_debit_cents'),
        totalCreditCents: row.read<int>('total_credit_cents'),
        netBalanceCents: row.read<int>('net_balance_cents'),
        transactionCount: row.read<int>('transaction_count'),
        lastTransactionAt:
            lastTxStr != null ? DateTime.tryParse(lastTxStr) : null,
      );
    }).toList();
  }
}
