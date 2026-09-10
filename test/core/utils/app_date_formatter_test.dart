import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/utils/app_date_formatter.dart';

void main() {
  test('formats user-facing dates as day month year', () {
    expect(AppDateFormatter.date(DateTime(2026, 9, 10)), '10/09/2026');
  });

  test('formats user-facing date-times with the same date order', () {
    expect(
      AppDateFormatter.dateTime(DateTime(2026, 9, 10, 7, 5)),
      '10/09/2026 07:05',
    );
  });
}
