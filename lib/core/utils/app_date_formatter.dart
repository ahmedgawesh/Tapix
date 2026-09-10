import 'package:intl/intl.dart';

/// The single user-facing date format used throughout Tapix.
///
/// A fixed day/month/year order avoids locale-dependent ambiguity such as
/// `9/10/2026`, which can mean different dates to different readers.
abstract final class AppDateFormatter {
  static final DateFormat _date = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTime = DateFormat('dd/MM/yyyy HH:mm');

  static String date(DateTime value) => _date.format(value);

  static String dateTime(DateTime value) => _dateTime.format(value);
}
