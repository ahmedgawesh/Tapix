import '../../../../core/services/business/warehouse_read_scope.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/reporting/ratio_helper.dart';
import '../widgets/report_date_range.dart';
import '../../../../core/services/commissions/commission_report_scope.dart';
import '../../../../core/services/business/warehouse_document_scope.dart';
import '../../../../core/services/business/document_posting_scope.dart';
export '../../../../core/services/commissions/commission_report_scope.dart'
    show CommissionReportScope, UnresolvedCommissionSources;

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

class SalespeopleCommissionReportScopeChanged
    extends SalespeopleCommissionReportEvent {
  final CommissionReportScope scope;
  const SalespeopleCommissionReportScopeChanged(this.scope);
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
  final CommissionReportScope scope;
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
    this.scope = CommissionReportScope.account,
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
      scope: scope,
      salespeople: salespeople ?? this.salespeople,
      grandTotalSalesCents: grandTotalSalesCents ?? this.grandTotalSalesCents,
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

class SalespeopleCommissionReportBloc
    extends
        RealtimeBloc<
          SalespeopleCommissionReportData,
          SalespeopleCommissionReportEvent
        > {
  final AppDatabase _db;
  final WarehouseReadScope? warehouseScope;
  ReportDateRange _dateRange;
  CommissionReportScope _scope;
  CommissionReportScope get scope => _scope;
  SalespeopleCommissionSortType _sort =
      SalespeopleCommissionSortType.revenueDesc;

  SalespeopleCommissionReportBloc(
    this._db, {
    String defaultDateRange = 'month',
    this.warehouseScope,
    CommissionReportScope scope = CommissionReportScope.account,
  }) : _scope = scope,
       _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
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
    on<SalespeopleCommissionReportScopeChanged>((event, emit) {
      _scope = event.scope;
      refresh();
    });
    on<SalespeopleCommissionReportDateRangeChanged>(_onDateRangeChanged);
    on<SalespeopleCommissionReportSortChanged>(_onSortChanged);
  }

  Stream<SalespeopleCommissionReportData> _buildCombinedStream() {
    // Watch both the sales and commissions tables for real-time changes.
    // Commissions must be watched independently because a return-reversal
    // inserts a commission row without necessarily mutating the sales table.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.employees,
            ...CommissionSourceScope.dependencies(_db),
          },
        )
        .watch()
        .asyncMap((_) async {
          final reportScope = _scope;
          final reportRange = _dateRange;
          final items = await WarehouseReadScope.snapshot(
            _db,
            warehouseScope,
            () => _loadSalespeopleCommission(reportScope, reportRange),
          );

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
            scope: reportScope,
            salespeople: sorted,
            grandTotalSalesCents: totalSales,
            grandTotalCommissionCents: totalCommission,
            grandTotalPendingCents: totalPending,
            grandTotalPaidCents: totalPaid,
            totalSalesCount: totalCount,
            totalSalespeople: items.length,
            avgCommissionRatePercent: avgRate,
            avgTargetAchievementPercent: avgTarget,
            dateRange: reportRange,
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
    if (state is RealtimeSuccess<SalespeopleCommissionReportData> &&
        current != null &&
        current.scope == _scope) {
      final sorted = _applySortToSalespeople(current.salespeople, event.sort);
      emit(
        RealtimeSuccess<SalespeopleCommissionReportData>(
          data: current.copyWith(salespeople: sorted, sort: event.sort),
        ),
      );
    }
  }

  List<SalespersonCommissionItem> _applySortToSalespeople(
    List<SalespersonCommissionItem> items,
    SalespeopleCommissionSortType sort,
  ) {
    final list = List<SalespersonCommissionItem>.from(items);
    switch (sort) {
      case SalespeopleCommissionSortType.revenueDesc:
        list.sort((a, b) => b.totalSalesCents.compareTo(a.totalSalesCents));
      case SalespeopleCommissionSortType.revenueAsc:
        list.sort((a, b) => a.totalSalesCents.compareTo(b.totalSalesCents));
      case SalespeopleCommissionSortType.nameAsc:
        list.sort((a, b) => a.employeeName.compareTo(b.employeeName));
      case SalespeopleCommissionSortType.nameDesc:
        list.sort((a, b) => b.employeeName.compareTo(a.employeeName));
      case SalespeopleCommissionSortType.commissionDesc:
        list.sort(
          (a, b) => b.totalCommissionEarnedCents.compareTo(
            a.totalCommissionEarnedCents,
          ),
        );
      case SalespeopleCommissionSortType.salesCountDesc:
        list.sort((a, b) => b.salesCount.compareTo(a.salesCount));
      case SalespeopleCommissionSortType.targetAchievementDesc:
        list.sort(
          (a, b) =>
              b.targetAchievementPercent.compareTo(a.targetAchievementPercent),
        );
    }
    return list;
  }

  /// Loads salesperson commission data by joining sales with employees
  /// and commissions tables within the date range.
  ///
  /// Earned commission comes only from recorded commission events. Missing
  /// records are not estimated using today's rate or tax-inclusive sales.
  /// Include commission-only periods and inactive employees with history.
  ///
  /// Target achievement:
  /// - Based on monthlyTargetCents constant
  /// - Prorated for non-monthly date ranges
  Future<List<SalespersonCommissionItem>> _loadSalespeopleCommission(
    CommissionReportScope scope,
    ReportDateRange range,
  ) async {
    final local =
        warehouseScope != null ||
        scope == CommissionReportScope.primaryWarehouse;
    if (local) {
      await CommissionSourceScope.requireResolvedPeriod(
        _db,
        range.startDate,
        range.endDate,
      );
    }
    final salesSource = local
        ? (warehouseScope?.documents(InventoryPostingDocument.sale) ??
              WarehouseDocumentScope.primaryDocuments(
                InventoryPostingDocument.sale,
              ))
        : 'sales';
    final commissionSource = local
        ? (warehouseScope == null
              ? CommissionSourceScope.primary
              : CommissionSourceScope.forWarehouse(warehouseScope!))
        : 'commissions';
    final startIso = range.startDate.toIso8601String();
    final endIso = range.endDate.toIso8601String();

    // Get sales data grouped by employee
    final salesRows = await _db
        .customSelect(
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
      LEFT JOIN $salesSource s ON s.employee_id = e.id
        AND s.sale_date >= ?
        AND s.sale_date <= ?
        AND s.status = 'completed'
      GROUP BY e.id
      HAVING sales_count > 0 OR EXISTS (
        SELECT 1 FROM $commissionSource event
        WHERE event.employee_id = e.id
          AND COALESCE(event.effective_date, event.created_at) >= ?
          AND COALESCE(event.effective_date, event.created_at) <= ?
      )
      ORDER BY total_sales_cents DESC
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.employees,
            ...CommissionSourceScope.dependencies(_db),
          },
        )
        .get();

    // Get commission data grouped by employee for the period.
    //
    // Attribution basis: each commission row is attributed by its OWN
    // economic-event date (`effective_date` — the sale date for earned rows,
    // the return date for reversal rows), NOT by the linked sale's
    // `sale_date`. This is the SAP / NetSuite / QuickBooks "posting date"
    // convention: a return-reversal lands in the period the return occurred
    // in — the accounting-correct rule — instead of being dragged back to the
    // original sale's month, and it stays correct for backdated documents.
    // `COALESCE(effective_date, created_at)` defends any legacy row that
    // predates the backfill / was written without a posting date.
    final commissionRows = await _db
        .customSelect(
          '''
      SELECT 
        c.employee_id,
        COALESCE(SUM(c.commission_amount_cents), 0) AS total_commission_cents,
        COALESCE(SUM(CASE WHEN c.status = 'pending' THEN c.commission_amount_cents ELSE 0 END), 0) AS pending_cents,
        COALESCE(SUM(CASE WHEN c.status = 'approved' THEN c.commission_amount_cents ELSE 0 END), 0) AS approved_cents,
        COALESCE(SUM(CASE WHEN c.status = 'paid' THEN c.commission_amount_cents ELSE 0 END), 0) AS paid_cents
      FROM $commissionSource c
      WHERE COALESCE(c.effective_date, c.created_at) >= ?
        AND COALESCE(c.effective_date, c.created_at) <= ?
      GROUP BY c.employee_id
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: CommissionSourceScope.dependencies(_db),
        )
        .get();

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
    final rangeDays = range.endDate.difference(range.startDate).inDays + 1;
    final proRatedTarget = (monthlyTargetCents * rangeDays / 30).round();

    return salesRows.map((row) {
      final employeeId = row.read<int>('employee_id');
      final totalSalesCents = row.read<int>('total_sales_cents');
      final salesCount = row.read<int>('sales_count');
      final commissionRateBps = row.read<int>('commission_rate_bps');
      final lastSaleStr = row.readNullable<String>('last_sale_at');

      // Financial totals reflect saved events, including zero/negative sums.
      // The current default rate is employee metadata, not historical earnings.
      final commBreakdown = commissionMap[employeeId];
      final totalCommission = commBreakdown?.totalCents ?? 0;
      final pendingComm = commBreakdown?.pendingCents ?? 0;
      final approvedComm = commBreakdown?.approvedCents ?? 0;
      final paidComm = commBreakdown?.paidCents ?? 0;

      // avgOrderValue = totalSales / salesCount
      final avgOrderValue = salesCount > 0 ? totalSalesCents ~/ salesCount : 0;

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
        lastSaleAt: lastSaleStr != null ? DateTime.tryParse(lastSaleStr) : null,
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
