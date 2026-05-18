import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/reporting/ratio_helper.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SalespeopleCommissionReportEvent extends RealtimeEvent {
  const SalespeopleCommissionReportEvent();
}

class SalespeopleCommissionReportDateRangeChanged
    extends SalespeopleCommissionReportEvent {
  final ReportDateRange dateRange;
  const SalespeopleCommissionReportDateRangeChanged(this.dateRange);
}

class SalespeopleCommissionReportSortChanged
    extends SalespeopleCommissionReportEvent {
  final SalespeopleCommissionSortType sort;
  const SalespeopleCommissionReportSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum SalespeopleCommissionSortType {
  revenueDesc,
  revenueAsc,
  nameAsc,
  nameDesc,
  commissionDesc,
  salesCountDesc,
  targetAchievementDesc,
}

// ==================== DATA MODELS ====================

class SalespersonCommissionItem {
  final int employeeId;
  final String employeeName;
  final String? position;
  final String? department;
  final int defaultCommissionRateBps;
  final int totalSalesCents;
  final int salesCount;
  final int totalCommissionEarnedCents;
  final int pendingCommissionCents;
  final int approvedCommissionCents;
  final int paidCommissionCents;
  final int avgOrderValueCents;
  final double targetAchievementPercent;
  final DateTime? lastSaleAt;

  const SalespersonCommissionItem({
    required this.employeeId,
    required this.employeeName,
    this.position,
    this.department,
    required this.defaultCommissionRateBps,
    required this.totalSalesCents,
    required this.salesCount,
    required this.totalCommissionEarnedCents,
    required this.pendingCommissionCents,
    required this.approvedCommissionCents,
    required this.paidCommissionCents,
    required this.avgOrderValueCents,
    required this.targetAchievementPercent,
    this.lastSaleAt,
  });

  /// Commission rate as percentage (e.g., 500 bps = 5.0%).
  // Phase 7 — bps→percent via RatioHelper SoT (Decimal-exact for all bps).
  double get commissionRatePercent =>
      RatioHelper.bpsToPercent(defaultCommissionRateBps);
}

class SalespeopleCommissionReportData {
  final List<SalespersonCommissionItem> salespeople;
  final int grandTotalSalesCents;
  final int grandTotalCommissionCents;
  final int grandTotalPendingCents;
  final int grandTotalPaidCents;
  final int totalSalesCount;
  final int totalSalespeople;
  final double avgCommissionRatePercent;
  final double avgTargetAchievementPercent;
  final ReportDateRange dateRange;
  final SalespeopleCommissionSortType sort;

  const SalespeopleCommissionReportData({
    this.salespeople = const [],
    this.grandTotalSalesCents = 0,
    this.grandTotalCommissionCents = 0,
    this.grandTotalPendingCents = 0,
    this.grandTotalPaidCents = 0,
    this.totalSalesCount = 0,
    this.totalSalespeople = 0,
    this.avgCommissionRatePercent = 0,
    this.avgTargetAchievementPercent = 0,
    required this.dateRange,
    this.sort = SalespeopleCommissionSortType.revenueDesc,
  });

  SalespeopleCommissionReportData copyWith({
    List<SalespersonCommissionItem>? salespeople,
    int? grandTotalSalesCents,
    int? grandTotalCommissionCents,
    int? grandTotalPendingCents,
    int? grandTotalPaidCents,
    int? totalSalesCount,
    int? totalSalespeople,
    double? avgCommissionRatePercent,
    double? avgTargetAchievementPercent,
    ReportDateRange? dateRange,
    SalespeopleCommissionSortType? sort,
  }) {
    return SalespeopleCommissionReportData(
      salespeople: salespeople ?? this.salespeople,
      grandTotalSalesCents:
          grandTotalSalesCents ?? this.grandTotalSalesCents,
      grandTotalCommissionCents:
          grandTotalCommissionCents ?? this.grandTotalCommissionCents,
      grandTotalPendingCents:
          grandTotalPendingCents ?? this.grandTotalPendingCents,
      grandTotalPaidCents: grandTotalPaidCents ?? this.grandTotalPaidCents,
      totalSalesCount: totalSalesCount ?? this.totalSalesCount,
      totalSalespeople: totalSalespeople ?? this.totalSalespeople,
      avgCommissionRatePercent:
          avgCommissionRatePercent ?? this.avgCommissionRatePercent,
      avgTargetAchievementPercent:
          avgTargetAchievementPercent ?? this.avgTargetAchievementPercent,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class SalespeopleCommissionReportBloc extends RealtimeBloc<
    SalespeopleCommissionReportData, SalespeopleCommissionReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  SalespeopleCommissionSortType _sort =
      SalespeopleCommissionSortType.revenueDesc;

  SalespeopleCommissionReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  /// Monthly sales target in cents (configurable, default 100,000 = 1000.00)
  static const int monthlyTargetCents = 10000000; // 100,000.00

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<SalespeopleCommissionReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SalespeopleCommissionReportDateRangeChanged>(_onDateRangeChanged);
    on<SalespeopleCommissionReportSortChanged>(_onSortChanged);
  }

  Stream<SalespeopleCommissionReportData> _buildCombinedStream() {
    // Watch sales table for real-time changes
    return _db.select(_db.sales).watch().asyncMap((_) async {
      final items = await _loadSalespeopleCommission();

      int totalSales = 0;
      int totalCommission = 0;
      int totalPending = 0;
      int totalPaid = 0;
      int totalCount = 0;
      double sumRate = 0;
      double sumTarget = 0;
      int withData = 0;

      for (final item in items) {
        totalSales += item.totalSalesCents;
        totalCommission += item.totalCommissionEarnedCents;
        totalPending += item.pendingCommissionCents;
        totalPaid += item.paidCommissionCents;
        totalCount += item.salesCount;
        sumRate += item.commissionRatePercent;
        sumTarget += item.targetAchievementPercent;
        withData++;
      }

      final avgRate = withData > 0 ? sumRate / withData : 0.0;
      final avgTarget = withData > 0 ? sumTarget / withData : 0.0;

      final sorted = _applySortToSalespeople(items, _sort);

      return SalespeopleCommissionReportData(
        salespeople: sorted,
        grandTotalSalesCents: totalSales,
        grandTotalCommissionCents: totalCommission,
        grandTotalPendingCents: totalPending,
        grandTotalPaidCents: totalPaid,
        totalSalesCount: totalCount,
        totalSalespeople: items.length,
        avgCommissionRatePercent: avgRate,
        avgTargetAchievementPercent: avgTarget,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    SalespeopleCommissionReportDateRangeChanged event,
    Emitter<RealtimeState<SalespeopleCommissionReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    SalespeopleCommissionReportSortChanged event,
    Emitter<RealtimeState<SalespeopleCommissionReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToSalespeople(current.salespeople, event.sort);
      emit(RealtimeSuccess<SalespeopleCommissionReportData>(
        data: current.copyWith(
          salespeople: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<SalespersonCommissionItem> _applySortToSalespeople(
    List<SalespersonCommissionItem> items,
    SalespeopleCommissionSortType sort,
  ) {
    final list = List<SalespersonCommissionItem>.from(items);
    switch (sort) {
      case SalespeopleCommissionSortType.revenueDesc:
        list.sort(
            (a, b) => b.totalSalesCents.compareTo(a.totalSalesCents));
      case SalespeopleCommissionSortType.revenueAsc:
        list.sort(
            (a, b) => a.totalSalesCents.compareTo(b.totalSalesCents));
      case SalespeopleCommissionSortType.nameAsc:
        list.sort((a, b) => a.employeeName.compareTo(b.employeeName));
      case SalespeopleCommissionSortType.nameDesc:
        list.sort((a, b) => b.employeeName.compareTo(a.employeeName));
      case SalespeopleCommissionSortType.commissionDesc:
        list.sort((a, b) => b.totalCommissionEarnedCents
            .compareTo(a.totalCommissionEarnedCents));
      case SalespeopleCommissionSortType.salesCountDesc:
        list.sort((a, b) => b.salesCount.compareTo(a.salesCount));
      case SalespeopleCommissionSortType.targetAchievementDesc:
        list.sort((a, b) => b.targetAchievementPercent
            .compareTo(a.targetAchievementPercent));
    }
    return list;
  }

  /// Loads salesperson commission data by joining sales with employees
  /// and commissions tables within the date range.
  ///
  /// Commission calculation:
  /// - Uses actual commissions table entries if available
  /// - Falls back to employee's defaultCommissionRateBps applied to sales total
  /// - Commission = (totalSalesCents * commissionRateBps) / 10000
  ///   (bps = basis points, 100 bps = 1%)
  ///
  /// Target achievement:
  /// - Based on monthlyTargetCents constant
  /// - Prorated for non-monthly date ranges
  Future<List<SalespersonCommissionItem>> _loadSalespeopleCommission() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Get sales data grouped by employee
    final salesRows = await _db.customSelect(
      '''
      SELECT 
        e.id AS employee_id,
        e.name AS employee_name,
        e.position AS position,
        e.department AS department,
        e.default_commission_rate_bps AS commission_rate_bps,
        COALESCE(SUM(s.total_cents), 0) AS total_sales_cents,
        COUNT(s.id) AS sales_count,
        MAX(s.sale_date) AS last_sale_at
      FROM employees e
      INNER JOIN sales s ON s.employee_id = e.id
        AND s.sale_date >= ?
        AND s.sale_date <= ?
        AND s.status != 'voided'
      WHERE e.is_active = 1
      GROUP BY e.id
      HAVING sales_count > 0
      ORDER BY total_sales_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.employees, _db.sales},
    ).get();

    // Get commission data grouped by employee for the period
    final commissionRows = await _db.customSelect(
      '''
      SELECT 
        c.employee_id,
        COALESCE(SUM(c.commission_amount_cents), 0) AS total_commission_cents,
        COALESCE(SUM(CASE WHEN c.status = 'pending' THEN c.commission_amount_cents ELSE 0 END), 0) AS pending_cents,
        COALESCE(SUM(CASE WHEN c.status = 'approved' THEN c.commission_amount_cents ELSE 0 END), 0) AS approved_cents,
        COALESCE(SUM(CASE WHEN c.status = 'paid' THEN c.commission_amount_cents ELSE 0 END), 0) AS paid_cents
      FROM commissions c
      INNER JOIN sales s ON s.id = c.sale_id
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY c.employee_id
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.commissions, _db.sales},
    ).get();

    // Build commission lookup map
    final commissionMap = <int, _CommissionBreakdown>{};
    for (final row in commissionRows) {
      final empId = row.read<int>('employee_id');
      commissionMap[empId] = _CommissionBreakdown(
        totalCents: row.read<int>('total_commission_cents'),
        pendingCents: row.read<int>('pending_cents'),
        approvedCents: row.read<int>('approved_cents'),
        paidCents: row.read<int>('paid_cents'),
      );
    }

    // Calculate target based on date range duration
    final rangeDays =
        _dateRange.endDate.difference(_dateRange.startDate).inDays + 1;
    final proRatedTarget =
        (monthlyTargetCents * rangeDays / 30).round();

    return salesRows.map((row) {
      final employeeId = row.read<int>('employee_id');
      final totalSalesCents = row.read<int>('total_sales_cents');
      final salesCount = row.read<int>('sales_count');
      final commissionRateBps = row.read<int>('commission_rate_bps');
      final lastSaleStr = row.readNullable<String>('last_sale_at');

      // Use actual commission records if available, otherwise calculate
      final commBreakdown = commissionMap[employeeId];
      int totalCommission;
      int pendingComm;
      int approvedComm;
      int paidComm;

      if (commBreakdown != null && commBreakdown.totalCents > 0) {
        totalCommission = commBreakdown.totalCents;
        pendingComm = commBreakdown.pendingCents;
        approvedComm = commBreakdown.approvedCents;
        paidComm = commBreakdown.paidCents;
      } else {
        // Calculate commission from rate: (sales * bps) / 10000
        totalCommission =
            (totalSalesCents * commissionRateBps) ~/ 10000;
        pendingComm = totalCommission;
        approvedComm = 0;
        paidComm = 0;
      }

      // avgOrderValue = totalSales / salesCount
      final avgOrderValue =
          salesCount > 0 ? totalSalesCents ~/ salesCount : 0;

      // Phase 7 — percentage via RatioHelper SoT.
      // targetAchievement = (totalSales / proRatedTarget) * 100
      final targetAchievement = RatioHelper.percent(
        numeratorCents: totalSalesCents,
        denominatorCents: proRatedTarget,
      );

      return SalespersonCommissionItem(
        employeeId: employeeId,
        employeeName: row.read<String>('employee_name'),
        position: row.readNullable<String>('position'),
        department: row.readNullable<String>('department'),
        defaultCommissionRateBps: commissionRateBps,
        totalSalesCents: totalSalesCents,
        salesCount: salesCount,
        totalCommissionEarnedCents: totalCommission,
        pendingCommissionCents: pendingComm,
        approvedCommissionCents: approvedComm,
        paidCommissionCents: paidComm,
        avgOrderValueCents: avgOrderValue,
        targetAchievementPercent: targetAchievement,
        lastSaleAt:
            lastSaleStr != null ? DateTime.tryParse(lastSaleStr) : null,
      );
    }).toList();
  }
}

class _CommissionBreakdown {
  final int totalCents;
  final int pendingCents;
  final int approvedCents;
  final int paidCents;

  const _CommissionBreakdown({
    required this.totalCents,
    required this.pendingCents,
    required this.approvedCents,
    required this.paidCents,
  });
}
