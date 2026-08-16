import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/supplier_balance_ledger_service.dart';
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

class SupplierDebitBalanceReportBloc
    extends
        RealtimeBloc<
          SupplierDebitBalanceReportData,
          SupplierDebitBalanceReportEvent
        > {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  SupplierDebitBalanceSortType _sort = SupplierDebitBalanceSortType.balanceDesc;

  SupplierDebitBalanceReportBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

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
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.suppliers, _db.supplierTransactions},
        )
        .watch()
        .asyncMap((_) async {
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
      emit(
        RealtimeSuccess<SupplierDebitBalanceReportData>(
          data: current.copyWith(suppliers: sorted, sort: event.sort),
        ),
      );
    }
  }

  List<SupplierDebitBalanceItem> _applySortToSuppliers(
    List<SupplierDebitBalanceItem> items,
    SupplierDebitBalanceSortType sort,
  ) {
    final list = List<SupplierDebitBalanceItem>.from(items);
    switch (sort) {
      case SupplierDebitBalanceSortType.balanceDesc:
        list.sort((a, b) => b.debitBalanceCents.compareTo(a.debitBalanceCents));
      case SupplierDebitBalanceSortType.balanceAsc:
        list.sort((a, b) => a.debitBalanceCents.compareTo(b.debitBalanceCents));
      case SupplierDebitBalanceSortType.nameAsc:
        list.sort((a, b) => a.supplierName.compareTo(b.supplierName));
      case SupplierDebitBalanceSortType.nameDesc:
        list.sort((a, b) => b.supplierName.compareTo(a.supplierName));
      case SupplierDebitBalanceSortType.purchasesDesc:
        list.sort(
          (a, b) => b.totalPurchasesCents.compareTo(a.totalPurchasesCents),
        );
      case SupplierDebitBalanceSortType.paymentsDesc:
        list.sort(
          (a, b) => b.totalPaymentsCents.compareTo(a.totalPaymentsCents),
        );
    }
    return list;
  }

  /// Payables are suppliers whose signed balance is positive at the
  /// report end date. Activity columns remain period-specific.
  Future<List<SupplierDebitBalanceItem>> _loadSupplierDebitBalances() async {
    final records = await SupplierBalanceLedgerService(
      _db,
    ).load(startDate: _dateRange.startDate, endDate: _dateRange.endDate);
    return records.where((record) => record.netBalanceCents > 0).map((record) {
      return SupplierDebitBalanceItem(
        supplierId: record.supplierId,
        supplierName: record.supplierName,
        phone: record.phone,
        totalPurchasesCents: record.totalPurchasesCents,
        totalReturnsCents: record.totalReturnsCents,
        totalPaymentsCents: record.totalPaymentsCents,
        totalDiscountsCents: record.totalDiscountsCents,
        debitBalanceCents: record.netBalanceCents,
        transactionCount: record.transactionCount,
        lastTransactionAt: record.lastTransactionAt,
      );
    }).toList();
  }
}
