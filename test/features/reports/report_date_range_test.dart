import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  test('endOfDay includes the complete final second', () {
    final end = ReportDateRange.endOfDay(DateTime(2026, 8, 8, 10, 30));

    expect(end, DateTime(2026, 8, 8, 23, 59, 59, 999, 999));
    expect(end.add(const Duration(microseconds: 1)), DateTime(2026, 8, 9));
  });

  test('all report presets end at the last microsecond of a day', () {
    final ranges = [
      ReportDateRange.today(),
      ReportDateRange.thisWeek(),
      ReportDateRange.thisMonth(),
      ReportDateRange.lastMonth(),
      ReportDateRange.thisQuarter(),
      ReportDateRange.thisYear(),
      ReportDateRange.lastYear(),
      ReportDateRange.allTime(),
    ];

    for (final range in ranges) {
      expect(range.endDate.hour, 23);
      expect(range.endDate.minute, 59);
      expect(range.endDate.second, 59);
      expect(range.endDate.millisecond, 999);
      expect(range.endDate.microsecond, 999);
    }
  });
}
