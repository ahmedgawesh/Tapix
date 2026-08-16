import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/supplier_balance_ledger_service.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierBalanceReportEvent extends RealtimeEvent {
  const SupplierBalanceReportEvent();
}

class SupplierBalanceReportDateRangeChanged extends SupplierBalanceReportEvent {
  final ReportDateRange dateRange;
  const SupplierBalanceReportDateRangeChanged(this.dateRange);
}

class SupplierBalanceReportSortChanged extends SupplierBalanceReportEvent {
  final SupplierBalanceSortType sort;
  const SupplierBalanceReportSortChanged(this.sort);
}

class SupplierBalanceReportSearchChanged extends SupplierBalanceReportEvent {
  final String query;
  const SupplierBalanceReportSearchChanged(this.query);
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

/// Detailed supplier balance item with all financial breakdown
class SupplierBalanceItem {
  final int supplierId;
  final String supplierName;
  final String? phone;
  final String? email;

  /// Opening balance from suppliers.opening_balance_cents
  /// Positive = we owe them (debit), Negative = they owe us (credit)
  final int openingBalanceCents;

  /// Total purchases (increases what we owe)
  final int totalPurchasesCents;

  /// Total payments made to supplier (decreases what we owe)
  final int totalPaymentsCents;

  /// Total returns/credit notes (decreases what we owe)
  final int totalReturnsCents;

  /// Total discounts received (decreases what we owe)
  final int totalDiscountsCents;

  /// Net balance = opening + purchases - payments - returns - discounts
  /// Positive = we owe them (payable), Negative = they owe us (receivable)
  final int netBalanceCents;

  final int transactionCount;
  final DateTime? lastTransactionAt;

  const SupplierBalanceItem({
    required this.supplierId,
    required this.supplierName,
    this.phone,
    this.email,
    required this.openingBalanceCents,
    required this.totalPurchasesCents,
    required this.totalPaymentsCents,
    required this.totalReturnsCents,
    required this.totalDiscountsCents,
    required this.netBalanceCents,
    required this.transactionCount,
    this.lastTransactionAt,
  });

  /// Total debit (what we owe) = opening debit + purchases
  int get totalDebitCents {
    final openingDebit = openingBalanceCents > 0 ? openingBalanceCents : 0;
    return openingDebit + totalPurchasesCents;
  }

  /// Total credit (what reduces our debt) = opening credit + payments + returns + discounts
  int get totalCreditCents {
    final openingCredit = openingBalanceCents < 0
        ? openingBalanceCents.abs()
        : 0;
    return openingCredit +
        totalPaymentsCents +
        totalReturnsCents +
        totalDiscountsCents;
  }

  /// Is this a payable (we owe them)?
  bool get isPayable => netBalanceCents > 0;

  /// Is this a receivable (they owe us)?
  bool get isReceivable => netBalanceCents < 0;
}

/// Summary data for the report header
class SupplierBalanceSummary {
  /// Total payables (what we owe to all suppliers)
  final int totalPayablesCents;

  /// Total receivables (what suppliers owe us - overpayments, credits)
  final int totalReceivablesCents;

  /// Opening balance debit (suppliers we owed at start)
  final int openingDebitCents;

  /// Opening balance credit (suppliers that owed us at start)
  final int openingCreditCents;

  /// Total purchases in period
  final int totalPurchasesCents;

  /// Total payments in period
  final int totalPaymentsCents;

  /// Total returns in period
  final int totalReturnsCents;

  /// Total discounts in period
  final int totalDiscountsCents;

  /// Number of suppliers with payable balance
  final int suppliersWithPayable;

  /// Number of suppliers with receivable balance
  final int suppliersWithReceivable;

  const SupplierBalanceSummary({
    this.totalPayablesCents = 0,
    this.totalReceivablesCents = 0,
    this.openingDebitCents = 0,
    this.openingCreditCents = 0,
    this.totalPurchasesCents = 0,
    this.totalPaymentsCents = 0,
    this.totalReturnsCents = 0,
    this.totalDiscountsCents = 0,
    this.suppliersWithPayable = 0,
    this.suppliersWithReceivable = 0,
  });

  /// Net balance across all suppliers
  int get netBalanceCents => totalPayablesCents - totalReceivablesCents;
}

class SupplierBalanceReportData {
  final List<SupplierBalanceItem> suppliers;
  final List<SupplierBalanceItem> filteredSuppliers;
  final SupplierBalanceSummary summary;
  final ReportDateRange dateRange;
  final SupplierBalanceSortType sort;
  final String searchQuery;

  const SupplierBalanceReportData({
    this.suppliers = const [],
    this.filteredSuppliers = const [],
    this.summary = const SupplierBalanceSummary(),
    required this.dateRange,
    this.sort = SupplierBalanceSortType.balanceDesc,
    this.searchQuery = '',
  });

  SupplierBalanceReportData copyWith({
    List<SupplierBalanceItem>? suppliers,
    List<SupplierBalanceItem>? filteredSuppliers,
    SupplierBalanceSummary? summary,
    ReportDateRange? dateRange,
    SupplierBalanceSortType? sort,
    String? searchQuery,
  }) {
    return SupplierBalanceReportData(
      suppliers: suppliers ?? this.suppliers,
      filteredSuppliers: filteredSuppliers ?? this.filteredSuppliers,
      summary: summary ?? this.summary,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  // Legacy getters for backward compatibility
  int get grandTotalDebitCents => summary.totalPayablesCents;
  int get grandTotalCreditCents => summary.totalReceivablesCents;
  int get grandNetBalanceCents => summary.netBalanceCents;
  int get totalSuppliers => suppliers.length;
  int get suppliersWithDebit => summary.suppliersWithPayable;
  int get suppliersWithCredit => summary.suppliersWithReceivable;
}

// ==================== BLOC ====================

class SupplierBalanceReportBloc
    extends
        RealtimeBloc<SupplierBalanceReportData, SupplierBalanceReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  SupplierBalanceSortType _sort = SupplierBalanceSortType.balanceDesc;
  String _searchQuery = '';

  SupplierBalanceReportBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<SupplierBalanceReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SupplierBalanceReportDateRangeChanged>(_onDateRangeChanged);
    on<SupplierBalanceReportSortChanged>(_onSortChanged);
    on<SupplierBalanceReportSearchChanged>(_onSearchChanged);
  }

  Stream<SupplierBalanceReportData> _buildCombinedStream() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.suppliers, _db.supplierTransactions},
        )
        .watch()
        .asyncMap((_) async {
          final items = await _loadSupplierBalances();
          final summary = _calculateSummary(items);
          final sorted = _applySortToSuppliers(items, _sort);
          final filtered = _applySearch(sorted, _searchQuery);

          return SupplierBalanceReportData(
            suppliers: sorted,
            filteredSuppliers: filtered,
            summary: summary,
            dateRange: _dateRange,
            sort: _sort,
            searchQuery: _searchQuery,
          );
        });
  }

  SupplierBalanceSummary _calculateSummary(List<SupplierBalanceItem> items) {
    int totalPayables = 0;
    int totalReceivables = 0;
    int openingDebit = 0;
    int openingCredit = 0;
    int totalPurchases = 0;
    int totalPayments = 0;
    int totalReturns = 0;
    int totalDiscounts = 0;
    int withPayable = 0;
    int withReceivable = 0;

    for (final item in items) {
      // Opening balances
      if (item.openingBalanceCents > 0) {
        openingDebit += item.openingBalanceCents;
      } else if (item.openingBalanceCents < 0) {
        openingCredit += item.openingBalanceCents.abs();
      }

      // Transaction totals
      totalPurchases += item.totalPurchasesCents;
      totalPayments += item.totalPaymentsCents;
      totalReturns += item.totalReturnsCents;
      totalDiscounts += item.totalDiscountsCents;

      // Net balance classification
      if (item.netBalanceCents > 0) {
        totalPayables += item.netBalanceCents;
        withPayable++;
      } else if (item.netBalanceCents < 0) {
        totalReceivables += item.netBalanceCents.abs();
        withReceivable++;
      }
    }

    return SupplierBalanceSummary(
      totalPayablesCents: totalPayables,
      totalReceivablesCents: totalReceivables,
      openingDebitCents: openingDebit,
      openingCreditCents: openingCredit,
      totalPurchasesCents: totalPurchases,
      totalPaymentsCents: totalPayments,
      totalReturnsCents: totalReturns,
      totalDiscountsCents: totalDiscounts,
      suppliersWithPayable: withPayable,
      suppliersWithReceivable: withReceivable,
    );
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
      final filtered = _applySearch(sorted, _searchQuery);
      emit(
        RealtimeSuccess<SupplierBalanceReportData>(
          data: current.copyWith(
            suppliers: sorted,
            filteredSuppliers: filtered,
            sort: event.sort,
          ),
        ),
      );
    }
  }

  void _onSearchChanged(
    SupplierBalanceReportSearchChanged event,
    Emitter<RealtimeState<SupplierBalanceReportData>> emit,
  ) {
    _searchQuery = event.query;
    final current = currentData;
    if (current != null) {
      final filtered = _applySearch(current.suppliers, event.query);
      emit(
        RealtimeSuccess<SupplierBalanceReportData>(
          data: current.copyWith(
            filteredSuppliers: filtered,
            searchQuery: event.query,
          ),
        ),
      );
    }
  }

  List<SupplierBalanceItem> _applySearch(
    List<SupplierBalanceItem> items,
    String query,
  ) {
    if (query.isEmpty) return items;
    final lowerQuery = query.toLowerCase();
    return items.where((item) {
      return item.supplierName.toLowerCase().contains(lowerQuery) ||
          (item.phone?.toLowerCase().contains(lowerQuery) ?? false) ||
          (item.email?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  List<SupplierBalanceItem> _applySortToSuppliers(
    List<SupplierBalanceItem> items,
    SupplierBalanceSortType sort,
  ) {
    final list = List<SupplierBalanceItem>.from(items);
    switch (sort) {
      case SupplierBalanceSortType.balanceDesc:
        list.sort(
          (a, b) => b.netBalanceCents.abs().compareTo(a.netBalanceCents.abs()),
        );
      case SupplierBalanceSortType.balanceAsc:
        list.sort(
          (a, b) => a.netBalanceCents.abs().compareTo(b.netBalanceCents.abs()),
        );
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

  /// Loads the signed supplier balance as of the report end date while
  /// keeping the activity columns limited to the selected period.
  Future<List<SupplierBalanceItem>> _loadSupplierBalances() async {
    final records = await SupplierBalanceLedgerService(
      _db,
    ).load(startDate: _dateRange.startDate, endDate: _dateRange.endDate);
    return records.map((record) {
      return SupplierBalanceItem(
        supplierId: record.supplierId,
        supplierName: record.supplierName,
        phone: record.phone,
        email: record.email,
        openingBalanceCents: record.openingBalanceCents,
        totalPurchasesCents: record.totalPurchasesCents,
        totalPaymentsCents: record.totalPaymentsCents,
        totalReturnsCents: record.totalReturnsCents,
        totalDiscountsCents: record.totalDiscountsCents,
        netBalanceCents: record.netBalanceCents,
        transactionCount: record.transactionCount,
        lastTransactionAt: record.lastTransactionAt,
      );
    }).toList();
  }
}
