/// Represents a date range for report filtering.
class ReportDateRange {
  final DateTime startDate;
  final DateTime endDate;
  final ReportPeriodPreset preset;

  const ReportDateRange({
    required this.startDate,
    required this.endDate,
    this.preset = ReportPeriodPreset.custom,
  });

  /// Last representable instant of [date]'s local calendar day.
  static DateTime endOfDay(DateTime date) => DateTime(
    date.year,
    date.month,
    date.day,
  ).add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));

  /// Today only
  factory ReportDateRange.today() {
    final now = DateTime.now();
    return ReportDateRange(
      startDate: DateTime(now.year, now.month, now.day),
      endDate: endOfDay(now),
      preset: ReportPeriodPreset.today,
    );
  }

  /// This week (Monday to Sunday)
  factory ReportDateRange.thisWeek() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return ReportDateRange(
      startDate: DateTime(monday.year, monday.month, monday.day),
      endDate: endOfDay(now),
      preset: ReportPeriodPreset.thisWeek,
    );
  }

  /// This month
  factory ReportDateRange.thisMonth() {
    final now = DateTime.now();
    return ReportDateRange(
      startDate: DateTime(now.year, now.month, 1),
      endDate: endOfDay(now),
      preset: ReportPeriodPreset.thisMonth,
    );
  }

  /// Last month
  factory ReportDateRange.lastMonth() {
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, 1);
    final lastDay = DateTime(now.year, now.month, 0);
    return ReportDateRange(
      startDate: lastMonth,
      endDate: endOfDay(lastDay),
      preset: ReportPeriodPreset.lastMonth,
    );
  }

  /// This quarter
  factory ReportDateRange.thisQuarter() {
    final now = DateTime.now();
    final quarterStart = DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
    return ReportDateRange(
      startDate: quarterStart,
      endDate: endOfDay(now),
      preset: ReportPeriodPreset.thisQuarter,
    );
  }

  /// This year
  factory ReportDateRange.thisYear() {
    final now = DateTime.now();
    return ReportDateRange(
      startDate: DateTime(now.year, 1, 1),
      endDate: endOfDay(now),
      preset: ReportPeriodPreset.thisYear,
    );
  }

  /// Last year
  factory ReportDateRange.lastYear() {
    final now = DateTime.now();
    return ReportDateRange(
      startDate: DateTime(now.year - 1, 1, 1),
      endDate: endOfDay(DateTime(now.year - 1, 12, 31)),
      preset: ReportPeriodPreset.lastYear,
    );
  }

  /// All time (from epoch to now)
  factory ReportDateRange.allTime() {
    final now = DateTime.now();
    return ReportDateRange(
      startDate: DateTime(2000, 1, 1),
      endDate: endOfDay(now),
      preset: ReportPeriodPreset.allTime,
    );
  }

  /// Create from AppSettings default range string ('today', 'week', 'month')
  factory ReportDateRange.fromSettingsDefault(String defaultRange) {
    switch (defaultRange) {
      case 'today':
        return ReportDateRange.today();
      case 'week':
        return ReportDateRange.thisWeek();
      case 'month':
      default:
        return ReportDateRange.thisMonth();
    }
  }

  ReportDateRange copyWith({
    DateTime? startDate,
    DateTime? endDate,
    ReportPeriodPreset? preset,
  }) {
    return ReportDateRange(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      preset: preset ?? this.preset,
    );
  }
}

enum ReportPeriodPreset {
  today,
  thisWeek,
  thisMonth,
  lastMonth,
  thisQuarter,
  thisYear,
  lastYear,
  allTime,
  custom,
}
