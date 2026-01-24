import 'package:drift/drift.dart';

class TimestampConverter extends TypeConverter<DateTime, int> {
  const TimestampConverter();

  @override
  DateTime fromSql(int fromDb) {
    return DateTime.fromMillisecondsSinceEpoch(fromDb);
  }

  @override
  int toSql(DateTime value) {
    return value.millisecondsSinceEpoch;
  }
}
