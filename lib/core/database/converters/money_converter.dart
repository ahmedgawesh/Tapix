import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

class MoneyConverter extends TypeConverter<Decimal, int> {
  const MoneyConverter();

  @override
  Decimal fromSql(int fromDb) {
    return Decimal.fromInt(fromDb);
  }

  @override
  int toSql(Decimal value) {
    return value.toBigInt().toInt();
  }
}

class BasisPointsConverter extends TypeConverter<double, int> {
  const BasisPointsConverter();

  @override
  double fromSql(int fromDb) {
    return fromDb / 10000.0;
  }

  @override
  int toSql(double value) {
    return (value * 10000).round();
  }
}
