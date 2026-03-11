import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerAnalysisReportEvent extends RealtimeEvent {
  const CustomerAnalysisReportEvent();
}

class CustomerAnalysisDateRangeChanged extends CustomerAnalysisReportEvent {
  final ReportDateRange dateRange;
  const CustomerAnalysisDateRangeChanged(this.dateRange);
}

class CustomerAnalysisSortChanged extends CustomerAnalysisReportEvent {
  final CustomerAnalysisSortType sort;
  const CustomerAnalysisSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum CustomerAnalysisSortType {
  totalSpentDesc,
  totalSpentAsc,
  frequencyDesc,
  frequencyAsc,
  recencyDesc,
  recencyAsc,
  nameAsc,
  nameDesc,
}

enum RfmSegment {
  champions,
  loyalCustomers,
  potentialLoyalists,
  newCustomers,
  promising,
  needsAttention,
  aboutToSleep,
  atRisk,
  cantLoseThem,
  hibernating,
  lost,
}

// ==================== DATA MODELS ====================

class CustomerAnalysisItem {
  final int customerId;
  final String customerName;
  final String segment;
  final int purchaseCount;
  final double avgDaysBetweenPurchases;
  final int avgOrderValueCents;
  final int totalSpentCents;
  final int largestOrderCents;
  final DateTime? lastPurchaseDate;
  final int daysSinceLastPurchase;
  final int recencyScore;
  final int frequencyScore;
  final int monetaryScore;
  final RfmSegment rfmSegment;

  const CustomerAnalysisItem({
    required this.customerId,
    required this.customerName,
    required this.segment,
    required this.purchaseCount,
    required this.avgDaysBetweenPurchases,
    required this.avgOrderValueCents,
    required this.totalSpentCents,
    required this.largestOrderCents,
    this.lastPurchaseDate,
    required this.daysSinceLastPurchase,
    required this.recencyScore,
    required this.frequencyScore,
    required this.monetaryScore,
    required this.rfmSegment,
  });
}

class CustomerAnalysisReportData {
  final List<CustomerAnalysisItem> customers;
  final int totalCustomers;
  final int grandTotalSpentCents;
  final int grandTotalPurchases;
  final int overallAvgOrderCents;
  final Map<RfmSegment, int> segmentCounts;
  final ReportDateRange dateRange;
  final CustomerAnalysisSortType sort;

  const CustomerAnalysisReportData({
    this.customers = const [],
    this.totalCustomers = 0,
    this.grandTotalSpentCents = 0,
    this.grandTotalPurchases = 0,
    this.overallAvgOrderCents = 0,
    this.segmentCounts = const {},
    required this.dateRange,
    this.sort = CustomerAnalysisSortType.totalSpentDesc,
  });

  CustomerAnalysisReportData copyWith({
    List<CustomerAnalysisItem>? customers,
    int? totalCustomers,
    int? grandTotalSpentCents,
    int? grandTotalPurchases,
    int? overallAvgOrderCents,
    Map<RfmSegment, int>? segmentCounts,
    ReportDateRange? dateRange,
    CustomerAnalysisSortType? sort,
  }) {
    return CustomerAnalysisReportData(
      customers: customers ?? this.customers,
      totalCustomers: totalCustomers ?? this.totalCustomers,
      grandTotalSpentCents: grandTotalSpentCents ?? this.grandTotalSpentCents,
      grandTotalPurchases: grandTotalPurchases ?? this.grandTotalPurchases,
      overallAvgOrderCents: overallAvgOrderCents ?? this.overallAvgOrderCents,
      segmentCounts: segmentCounts ?? this.segmentCounts,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
    );
  }
}

// ==================== BLOC ====================

class CustomerAnalysisReportBloc
    extends RealtimeBloc<CustomerAnalysisReportData, CustomerAnalysisReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  CustomerAnalysisSortType _sort = CustomerAnalysisSortType.totalSpentDesc;

  CustomerAnalysisReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<CustomerAnalysisReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<CustomerAnalysisDateRangeChanged>(_onDateRangeChanged);
    on<CustomerAnalysisSortChanged>(_onSortChanged);
  }

  Stream<CustomerAnalysisReportData> _buildCombinedStream() {
    return _db.select(_db.sales).watch().asyncMap((_) async {
      final customers = await _loadCustomerAnalysis();

      int totalSpent = 0;
      int totalPurchases = 0;
      final segmentCounts = <RfmSegment, int>{};

      for (final c in customers) {
        totalSpent += c.totalSpentCents;
        totalPurchases += c.purchaseCount;
        segmentCounts[c.rfmSegment] = (segmentCounts[c.rfmSegment] ?? 0) + 1;
      }

      final overallAvg = totalPurchases > 0 ? totalSpent ~/ totalPurchases : 0;
      final sorted = _applySortToCustomers(customers, _sort);

      return CustomerAnalysisReportData(
        customers: sorted,
        totalCustomers: customers.length,
        grandTotalSpentCents: totalSpent,
        grandTotalPurchases: totalPurchases,
        overallAvgOrderCents: overallAvg,
        segmentCounts: segmentCounts,
        dateRange: _dateRange,
        sort: _sort,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    CustomerAnalysisDateRangeChanged event,
    Emitter<RealtimeState<CustomerAnalysisReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    CustomerAnalysisSortChanged event,
    Emitter<RealtimeState<CustomerAnalysisReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToCustomers(current.customers, event.sort);
      emit(RealtimeSuccess<CustomerAnalysisReportData>(
        data: current.copyWith(
          customers: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<CustomerAnalysisItem> _applySortToCustomers(
    List<CustomerAnalysisItem> items,
    CustomerAnalysisSortType sort,
  ) {
    final list = List<CustomerAnalysisItem>.from(items);
    switch (sort) {
      case CustomerAnalysisSortType.totalSpentDesc:
        list.sort((a, b) => b.totalSpentCents.compareTo(a.totalSpentCents));
      case CustomerAnalysisSortType.totalSpentAsc:
        list.sort((a, b) => a.totalSpentCents.compareTo(b.totalSpentCents));
      case CustomerAnalysisSortType.frequencyDesc:
        list.sort((a, b) => b.purchaseCount.compareTo(a.purchaseCount));
      case CustomerAnalysisSortType.frequencyAsc:
        list.sort((a, b) => a.purchaseCount.compareTo(b.purchaseCount));
      case CustomerAnalysisSortType.recencyDesc:
        list.sort((a, b) => a.daysSinceLastPurchase.compareTo(b.daysSinceLastPurchase));
      case CustomerAnalysisSortType.recencyAsc:
        list.sort((a, b) => b.daysSinceLastPurchase.compareTo(a.daysSinceLastPurchase));
      case CustomerAnalysisSortType.nameAsc:
        list.sort((a, b) => a.customerName.compareTo(b.customerName));
      case CustomerAnalysisSortType.nameDesc:
        list.sort((a, b) => b.customerName.compareTo(a.customerName));
    }
    return list;
  }

  Future<List<CustomerAnalysisItem>> _loadCustomerAnalysis() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();
    final now = DateTime.now();

    final rows = await _db.customSelect(
      '''
      SELECT 
        c.id AS customer_id,
        c.name AS customer_name,
        c.segment AS segment,
        COUNT(s.id) AS purchase_count,
        COALESCE(SUM(s.total_cents), 0) AS total_spent_cents,
        COALESCE(MAX(s.total_cents), 0) AS largest_order_cents,
        MAX(s.sale_date) AS last_sale_date,
        MIN(s.sale_date) AS first_sale_date
      FROM sales s
      INNER JOIN customers c ON c.id = s.customer_id
      WHERE s.status != 'voided'
        AND s.customer_id IS NOT NULL
        AND s.sale_date >= ?
        AND s.sale_date <= ?
      GROUP BY c.id
      HAVING purchase_count > 0
      ORDER BY total_spent_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {
        _db.sales,
        _db.customers,
      },
    ).get();

    // Compute max values for RFM scoring
    int maxSpent = 0;
    int maxPurchases = 0;
    final rawItems = <_RawAnalysisData>[];

    for (final row in rows) {
      final totalSpent = row.read<int>('total_spent_cents');
      final purchaseCount = row.read<int>('purchase_count');
      final lastDateStr = row.readNullable<String>('last_sale_date');
      final firstDateStr = row.readNullable<String>('first_sale_date');

      if (totalSpent > maxSpent) maxSpent = totalSpent;
      if (purchaseCount > maxPurchases) maxPurchases = purchaseCount;

      final lastDate = lastDateStr != null
          ? DateTime.parse(lastDateStr)
          : null;
      final firstDate = firstDateStr != null
          ? DateTime.parse(firstDateStr)
          : null;

      final daysSinceLast = lastDate != null
          ? now.difference(lastDate).inDays
          : 9999;

      double avgDays = 0;
      if (purchaseCount > 1 && firstDate != null && lastDate != null) {
        final spanDays = lastDate.difference(firstDate).inDays;
        avgDays = spanDays / (purchaseCount - 1);
      }

      final avgOrder = purchaseCount > 0 ? totalSpent ~/ purchaseCount : 0;

      rawItems.add(_RawAnalysisData(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        segment: row.read<String>('segment'),
        purchaseCount: purchaseCount,
        avgDaysBetweenPurchases: avgDays,
        avgOrderValueCents: avgOrder,
        totalSpentCents: totalSpent,
        largestOrderCents: row.read<int>('largest_order_cents'),
        lastPurchaseDate: lastDate,
        daysSinceLastPurchase: daysSinceLast,
      ));
    }

    // Compute max days since last purchase for recency scoring
    int maxDaysSince = 1;
    for (final item in rawItems) {
      if (item.daysSinceLastPurchase < 9999 && item.daysSinceLastPurchase > maxDaysSince) {
        maxDaysSince = item.daysSinceLastPurchase;
      }
    }

    return rawItems.map((item) {
      final recency = computeRecencyScore(item.daysSinceLastPurchase, maxDaysSince);
      final frequency = computeFrequencyScore(item.purchaseCount, maxPurchases);
      final monetary = computeMonetaryScore(item.totalSpentCents, maxSpent);
      final rfm = computeRfmSegment(recency, frequency, monetary);

      return CustomerAnalysisItem(
        customerId: item.customerId,
        customerName: item.customerName,
        segment: item.segment,
        purchaseCount: item.purchaseCount,
        avgDaysBetweenPurchases: item.avgDaysBetweenPurchases,
        avgOrderValueCents: item.avgOrderValueCents,
        totalSpentCents: item.totalSpentCents,
        largestOrderCents: item.largestOrderCents,
        lastPurchaseDate: item.lastPurchaseDate,
        daysSinceLastPurchase: item.daysSinceLastPurchase,
        recencyScore: recency,
        frequencyScore: frequency,
        monetaryScore: monetary,
        rfmSegment: rfm,
      );
    }).toList();
  }

  /// Recency: 5 = most recent, 1 = least recent
  /// Score based on quintile of days since last purchase
  static int computeRecencyScore(int daysSince, int maxDays) {
    if (maxDays <= 0 || daysSince >= 9999) return 1;
    // Lower days = higher score (more recent = better)
    final ratio = daysSince / maxDays;
    if (ratio <= 0.2) return 5;
    if (ratio <= 0.4) return 4;
    if (ratio <= 0.6) return 3;
    if (ratio <= 0.8) return 2;
    return 1;
  }

  /// Frequency: 5 = most frequent, 1 = least frequent
  static int computeFrequencyScore(int count, int maxCount) {
    if (maxCount <= 0) return 1;
    final ratio = count / maxCount;
    if (ratio >= 0.8) return 5;
    if (ratio >= 0.6) return 4;
    if (ratio >= 0.4) return 3;
    if (ratio >= 0.2) return 2;
    return 1;
  }

  /// Monetary: 5 = highest spender, 1 = lowest spender
  static int computeMonetaryScore(int spent, int maxSpent) {
    if (maxSpent <= 0) return 1;
    final ratio = spent / maxSpent;
    if (ratio >= 0.8) return 5;
    if (ratio >= 0.6) return 4;
    if (ratio >= 0.4) return 3;
    if (ratio >= 0.2) return 2;
    return 1;
  }

  /// Map RFM scores to customer segments
  /// Rules ordered from most specific to least specific
  static RfmSegment computeRfmSegment(int r, int f, int m) {
    // Champions: high R, high F, high M
    if (r >= 4 && f >= 4 && m >= 4) return RfmSegment.champions;
    // Can't Lose Them: very low R, very high F, very high M (before loyalCustomers)
    if (r <= 1 && f >= 4 && m >= 4) return RfmSegment.cantLoseThem;
    // Loyal Customers: high F, high M (any R)
    if (f >= 4 && m >= 4) return RfmSegment.loyalCustomers;
    // At Risk: low R, high F, high M (before needsAttention)
    if (r <= 2 && f >= 3 && m >= 3) return RfmSegment.atRisk;
    // Potential Loyalists: high R, moderate F
    if (r >= 4 && f >= 2 && f <= 4) return RfmSegment.potentialLoyalists;
    // New Customers: high R, low F
    if (r >= 4 && f <= 1) return RfmSegment.newCustomers;
    // Promising: moderate R, low F
    if (r >= 3 && f <= 1) return RfmSegment.promising;
    // Needs Attention: moderate R, moderate F, moderate M
    if (r >= 2 && r <= 3 && f >= 2 && f <= 3 && m >= 2 && m <= 3) return RfmSegment.needsAttention;
    // Hibernating: low R, low F, low M (before aboutToSleep)
    if (r <= 2 && f <= 2 && m <= 2) return RfmSegment.hibernating;
    // About to Sleep: low R, low F (any M)
    if (r <= 2 && f <= 2) return RfmSegment.aboutToSleep;
    // Lost: everything else
    return RfmSegment.lost;
  }
}

class _RawAnalysisData {
  final int customerId;
  final String customerName;
  final String segment;
  final int purchaseCount;
  final double avgDaysBetweenPurchases;
  final int avgOrderValueCents;
  final int totalSpentCents;
  final int largestOrderCents;
  final DateTime? lastPurchaseDate;
  final int daysSinceLastPurchase;

  const _RawAnalysisData({
    required this.customerId,
    required this.customerName,
    required this.segment,
    required this.purchaseCount,
    required this.avgDaysBetweenPurchases,
    required this.avgOrderValueCents,
    required this.totalSpentCents,
    required this.largestOrderCents,
    this.lastPurchaseDate,
    required this.daysSinceLastPurchase,
  });
}
