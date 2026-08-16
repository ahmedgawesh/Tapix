import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/supplier_balance_ledger_service.dart';
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

class SupplierCreditBalanceReportBloc
    extends
        RealtimeBloc<
          SupplierCreditBalanceReportData,
          SupplierCreditBalanceReportEvent
        > {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  SupplierCreditBalanceSortType _sort =
      SupplierCreditBalanceSortType.balanceDesc;

  SupplierCreditBalanceReportBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

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
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.suppliers, _db.supplierTransactions},
        )
        .watch()
        .asyncMap((_) async {
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
      emit(
        RealtimeSuccess<SupplierCreditBalanceReportData>(
          data: current.copyWith(suppliers: sorted, sort: event.sort),
        ),
      );
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
          (a, b) => b.creditBalanceCents.compareTo(a.creditBalanceCents),
        );
      case SupplierCreditBalanceSortType.balanceAsc:
        list.sort(
          (a, b) => a.creditBalanceCents.compareTo(b.creditBalanceCents),
        );
      case SupplierCreditBalanceSortType.nameAsc:
        list.sort((a, b) => a.supplierName.compareTo(b.supplierName));
      case SupplierCreditBalanceSortType.nameDesc:
        list.sort((a, b) => b.supplierName.compareTo(a.supplierName));
      case SupplierCreditBalanceSortType.purchasesDesc:
        list.sort(
          (a, b) => b.totalPurchasesCents.compareTo(a.totalPurchasesCents),
        );
      case SupplierCreditBalanceSortType.paymentsDesc:
        list.sort(
          (a, b) => b.totalPaymentsCents.compareTo(a.totalPaymentsCents),
        );
    }
    return list;
  }

  /// Supplier receivables are suppliers whose signed balance is negative
  /// at the report end date. Activity columns remain period-specific.
  Future<List<SupplierCreditBalanceItem>> _loadSupplierCreditBalances() async {
    final records = await SupplierBalanceLedgerService(
      _db,
    ).load(startDate: _dateRange.startDate, endDate: _dateRange.endDate);
    return records.where((record) => record.netBalanceCents < 0).map((record) {
      return SupplierCreditBalanceItem(
        supplierId: record.supplierId,
        supplierName: record.supplierName,
        phone: record.phone,
        totalPurchasesCents: record.totalPurchasesCents,
        totalReturnsCents: record.totalReturnsCents,
        totalPaymentsCents: record.totalPaymentsCents,
        totalDiscountsCents: record.totalDiscountsCents,
        creditBalanceCents: record.netBalanceCents.abs(),
        transactionCount: record.transactionCount,
        lastTransactionAt: record.lastTransactionAt,
      );
    }).toList();
  }
}
