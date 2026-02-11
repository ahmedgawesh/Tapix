import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierAnalysisReportEvent extends RealtimeEvent {
  const SupplierAnalysisReportEvent();
}

class SupplierAnalysisReportDateRangeChanged
    extends SupplierAnalysisReportEvent {
  final ReportDateRange dateRange;
  const SupplierAnalysisReportDateRangeChanged(this.dateRange);
}

class SupplierAnalysisReportSortChanged extends SupplierAnalysisReportEvent {
  final SupplierAnalysisSortType sort;
  const SupplierAnalysisReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum SupplierAnalysisSortType {
  purchaseVolumeDesc,
  purchaseVolumeAsc,
  nameAsc,
  nameDesc,
  returnRateDesc,
  avgPaymentDaysAsc,
  settlementRatioDesc,
  avgOrderValueDesc,
}

// ==================== DATA MODELS ====================

class SupplierAnalysisItem {
  final int supplierId;
  final String supplierName;
  final String? phone;
  final int totalPurchasesCents;
  final int purchaseCount;
  final int totalReturnsCents;
  final int returnCount;
  final int totalPaymentsCents;
  final int paymentCount;
  final double returnRatePercent;
  final double avgPaymentDays;
  final double settlementRatioPercent;
  final int avgOrderValueCents;
  final DateTime? lastTransactionAt;

  const SupplierAnalysisItem({
    required this.supplierId,
    required this.supplierName,
    this.phone,
    required this.totalPurchasesCents,
    required this.purchaseCount,
    required this.totalReturnsCents,
    required this.returnCount,
    required this.totalPaymentsCents,
    required this.paymentCount,
    required this.returnRatePercent,
    required this.avgPaymentDays,
    required this.settlementRatioPercent,
    required this.avgOrderValueCents,
    this.lastTransactionAt,
  });
}

class SupplierAnalysisReportData {
  final List<SupplierAnalysisItem> suppliers;
  final int grandTotalPurchasesCents;
  final int grandTotalReturnsCents;
  final int grandTotalPaymentsCents;
  final int totalSuppliers;
  final double avgReturnRatePercent;
  final double avgPaymentDays;
  final double avgSettlementRatioPercent;
  final ReportDateRange dateRange;
  final SupplierAnalysisSortType sort;

  const SupplierAnalysisReportData({
    this.suppliers = const [],
    this.grandTotalPurchasesCents = 0,
    this.grandTotalReturnsCents = 0,
    this.grandTotalPaymentsCents = 0,
    this.totalSuppliers = 0,
    this.avgReturnRatePercent = 0,
    this.avgPaymentDays = 0,
    this.avgSettlementRatioPercent = 0,
    required this.dateRange,
    this.sort = SupplierAnalysisSortType.purchaseVolumeDesc,
  });

  SupplierAnalysisReportData copyWith({
    List<SupplierAnalysisItem>? suppliers,
    int? grandTotalPurchasesCents,
    int? grandTotalReturnsCents,
    int? grandTotalPaymentsCents,
    int? totalSuppliers,
    double? avgReturnRatePercent,
    double? avgPaymentDays,
    double? avgSettlementRatioPercent,
    ReportDateRange? dateRange,
    SupplierAnalysisSortType? sort,
  }) {
    return SupplierAnalysisReportData(
      suppliers: suppliers ?? this.suppliers,
      grandTotalPurchasesCents:
          grandTotalPurchasesCents ?? this.grandTotalPurchasesCents,
      grandTotalReturnsCents:
          grandTotalReturnsCents ?? this.grandTotalReturnsCents,
      grandTotalPaymentsCents:
          grandTotalPaymentsCents ?? this.grandTotalPaymentsCents,
      totalSuppliers: totalSuppliers ?? this.totalSuppliers,
      avgReturnRatePercent: avgReturnRatePercent ?? this.avgReturnRatePercent,
      avgPaymentDays: avgPaymentDays ?? this.avgPaymentDays,
      avgSettlementRatioPercent:
          avgSettlementRatioPercent ?? this.avgSettlementRatioPercent,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class SupplierAnalysisReportBloc extends RealtimeBloc<
    SupplierAnalysisReportData, SupplierAnalysisReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  SupplierAnalysisSortType _sort =
      SupplierAnalysisSortType.purchaseVolumeDesc;

  SupplierAnalysisReportBloc(this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<SupplierAnalysisReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SupplierAnalysisReportDateRangeChanged>(_onDateRangeChanged);
    on<SupplierAnalysisReportSortChanged>(_onSortChanged);
  }

  Stream<SupplierAnalysisReportData> _buildCombinedStream() {
    return _db.select(_db.supplierTransactions).watch().asyncMap((_) async {
      final items = await _loadSupplierAnalysis();

      int totalPurchases = 0;
      int totalReturns = 0;
      int totalPayments = 0;
      double sumReturnRate = 0;
      double sumPaymentDays = 0;
      double sumSettlementRatio = 0;
      int suppliersWithData = 0;

      for (final item in items) {
        totalPurchases += item.totalPurchasesCents;
        totalReturns += item.totalReturnsCents;
        totalPayments += item.totalPaymentsCents;
        sumReturnRate += item.returnRatePercent;
        sumPaymentDays += item.avgPaymentDays;
        sumSettlementRatio += item.settlementRatioPercent;
        suppliersWithData++;
      }

      final avgReturnRate =
          suppliersWithData > 0 ? sumReturnRate / suppliersWithData : 0.0;
      final avgPayDays =
          suppliersWithData > 0 ? sumPaymentDays / suppliersWithData : 0.0;
      final avgSettlement =
          suppliersWithData > 0 ? sumSettlementRatio / suppliersWithData : 0.0;

      final sorted = _applySortToSuppliers(items, _sort);

      return SupplierAnalysisReportData(
        suppliers: sorted,
        grandTotalPurchasesCents: totalPurchases,
        grandTotalReturnsCents: totalReturns,
        grandTotalPaymentsCents: totalPayments,
        totalSuppliers: items.length,
        avgReturnRatePercent: avgReturnRate,
        avgPaymentDays: avgPayDays,
        avgSettlementRatioPercent: avgSettlement,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    SupplierAnalysisReportDateRangeChanged event,
    Emitter<RealtimeState<SupplierAnalysisReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    SupplierAnalysisReportSortChanged event,
    Emitter<RealtimeState<SupplierAnalysisReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToSuppliers(current.suppliers, event.sort);
      emit(RealtimeSuccess<SupplierAnalysisReportData>(
        data: current.copyWith(
          suppliers: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<SupplierAnalysisItem> _applySortToSuppliers(
    List<SupplierAnalysisItem> items,
    SupplierAnalysisSortType sort,
  ) {
    final list = List<SupplierAnalysisItem>.from(items);
    switch (sort) {
      case SupplierAnalysisSortType.purchaseVolumeDesc:
        list.sort((a, b) =>
            b.totalPurchasesCents.compareTo(a.totalPurchasesCents));
      case SupplierAnalysisSortType.purchaseVolumeAsc:
        list.sort((a, b) =>
            a.totalPurchasesCents.compareTo(b.totalPurchasesCents));
      case SupplierAnalysisSortType.nameAsc:
        list.sort((a, b) => a.supplierName.compareTo(b.supplierName));
      case SupplierAnalysisSortType.nameDesc:
        list.sort((a, b) => b.supplierName.compareTo(a.supplierName));
      case SupplierAnalysisSortType.returnRateDesc:
        list.sort(
            (a, b) => b.returnRatePercent.compareTo(a.returnRatePercent));
      case SupplierAnalysisSortType.avgPaymentDaysAsc:
        list.sort((a, b) => a.avgPaymentDays.compareTo(b.avgPaymentDays));
      case SupplierAnalysisSortType.settlementRatioDesc:
        list.sort((a, b) =>
            b.settlementRatioPercent.compareTo(a.settlementRatioPercent));
      case SupplierAnalysisSortType.avgOrderValueDesc:
        list.sort((a, b) =>
            b.avgOrderValueCents.compareTo(a.avgOrderValueCents));
    }
    return list;
  }

  /// Loads supplier analysis data from supplier_transactions within the date range.
  ///
  /// Transaction types in supplier_transactions:
  /// - 'purchase' (positive amount_cents) = purchase from supplier
  /// - 'purchase_return' (negative amount_cents) = return to supplier
  /// - 'payment' (negative amount_cents) = payment to supplier
  /// - 'refund' (positive amount_cents) = refund from supplier
  /// - 'discount' (negative amount_cents) = discount from supplier
  ///
  /// Analytics calculations:
  /// - totalPurchases = SUM of purchase-type transactions (positive amounts)
  /// - totalReturns = ABS(SUM of return-type transactions)
  /// - totalPayments = ABS(SUM of payment-type transactions)
  /// - returnRate = (totalReturns / totalPurchases) * 100
  /// - settlementRatio = (totalPayments / totalPurchases) * 100
  /// - avgOrderValue = totalPurchases / purchaseCount
  /// - avgPaymentDays = AVG days between purchase and payment dates
  Future<List<SupplierAnalysisItem>> _loadSupplierAnalysis() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        s.id AS supplier_id,
        s.name AS supplier_name,
        s.phone AS phone,
        COALESCE(SUM(CASE WHEN st.amount_cents > 0 THEN st.amount_cents ELSE 0 END), 0) AS total_purchases_cents,
        COALESCE(SUM(CASE WHEN st.amount_cents > 0 THEN 1 ELSE 0 END), 0) AS purchase_count,
        COALESCE(SUM(CASE WHEN st.transaction_type IN ('purchase_return', 'return') AND st.amount_cents < 0 THEN ABS(st.amount_cents) ELSE 0 END), 0) AS total_returns_cents,
        COALESCE(SUM(CASE WHEN st.transaction_type IN ('purchase_return', 'return') THEN 1 ELSE 0 END), 0) AS return_count,
        COALESCE(SUM(CASE WHEN st.transaction_type = 'payment' AND st.amount_cents < 0 THEN ABS(st.amount_cents) ELSE 0 END), 0) AS total_payments_cents,
        COALESCE(SUM(CASE WHEN st.transaction_type = 'payment' THEN 1 ELSE 0 END), 0) AS payment_count,
        MAX(st.transaction_date) AS last_transaction_at
      FROM suppliers s
      LEFT JOIN supplier_transactions st 
        ON st.supplier_id = s.id
        AND st.transaction_date >= ?
        AND st.transaction_date <= ?
      WHERE s.is_active = 1
      GROUP BY s.id
      HAVING purchase_count > 0 OR return_count > 0 OR payment_count > 0
      ORDER BY total_purchases_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.suppliers, _db.supplierTransactions},
    ).get();

    // Calculate avg payment days per supplier from payment transactions
    final paymentDaysMap = await _calculateAvgPaymentDays(startIso, endIso);

    return rows.map((row) {
      final supplierId = row.read<int>('supplier_id');
      final totalPurchasesCents = row.read<int>('total_purchases_cents');
      final purchaseCount = row.read<int>('purchase_count');
      final totalReturnsCents = row.read<int>('total_returns_cents');
      final returnCount = row.read<int>('return_count');
      final totalPaymentsCents = row.read<int>('total_payments_cents');
      final paymentCount = row.read<int>('payment_count');
      final lastTxStr = row.readNullable<String>('last_transaction_at');

      // returnRate = (totalReturns / totalPurchases) * 100
      final returnRate = totalPurchasesCents > 0
          ? (totalReturnsCents / totalPurchasesCents) * 100
          : 0.0;

      // settlementRatio = (totalPayments / totalPurchases) * 100
      final settlementRatio = totalPurchasesCents > 0
          ? (totalPaymentsCents / totalPurchasesCents) * 100
          : 0.0;

      // avgOrderValue = totalPurchases / purchaseCount
      final avgOrderValue =
          purchaseCount > 0 ? totalPurchasesCents ~/ purchaseCount : 0;

      // avgPaymentDays from pre-calculated map
      final avgPayDays = paymentDaysMap[supplierId] ?? 0.0;

      return SupplierAnalysisItem(
        supplierId: supplierId,
        supplierName: row.read<String>('supplier_name'),
        phone: row.readNullable<String>('phone'),
        totalPurchasesCents: totalPurchasesCents,
        purchaseCount: purchaseCount,
        totalReturnsCents: totalReturnsCents,
        returnCount: returnCount,
        totalPaymentsCents: totalPaymentsCents,
        paymentCount: paymentCount,
        returnRatePercent: returnRate,
        avgPaymentDays: avgPayDays,
        settlementRatioPercent: settlementRatio,
        avgOrderValueCents: avgOrderValue,
        lastTransactionAt:
            lastTxStr != null ? DateTime.tryParse(lastTxStr) : null,
      );
    }).toList();
  }

  /// Calculates average payment days per supplier.
  /// For each supplier, finds the average number of days between
  /// purchase transactions and payment transactions within the date range.
  /// This is an approximation: AVG(payment_date - first_purchase_date_in_range).
  Future<Map<int, double>> _calculateAvgPaymentDays(
      String startIso, String endIso) async {
    final rows = await _db.customSelect(
      '''
      SELECT 
        st.supplier_id,
        AVG(
          JULIANDAY(st.transaction_date) - JULIANDAY(
            (SELECT MIN(st2.transaction_date) 
             FROM supplier_transactions st2 
             WHERE st2.supplier_id = st.supplier_id 
               AND st2.amount_cents > 0
               AND st2.transaction_date >= ?
               AND st2.transaction_date <= ?)
          )
        ) AS avg_days
      FROM supplier_transactions st
      WHERE st.transaction_type = 'payment'
        AND st.transaction_date >= ?
        AND st.transaction_date <= ?
      GROUP BY st.supplier_id
      HAVING avg_days IS NOT NULL
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.supplierTransactions},
    ).get();

    final map = <int, double>{};
    for (final row in rows) {
      final supplierId = row.read<int>('supplier_id');
      final avgDays = row.readNullable<double>('avg_days');
      if (avgDays != null && avgDays >= 0) {
        map[supplierId] = avgDays;
      }
    }
    return map;
  }
}
