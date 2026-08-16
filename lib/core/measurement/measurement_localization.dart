import 'package:easy_localization/easy_localization.dart';

import 'measurement.dart';

String localizedQuantity(
  int storedQuantity,
  String measurementType, {
  bool includeUnit = true,
}) {
  final type = MeasurementType.fromDb(measurementType);
  final value = MeasuredQuantity.majorValue(storedQuantity, type);
  if (!includeUnit) return value;
  final unit = 'measurement.units.${type.majorUnit.dbValue}'.tr();
  return '$value $unit';
}

String localizedSignedQuantity(
  int storedQuantity,
  String measurementType, {
  bool showPositiveSign = false,
}) {
  final sign = storedQuantity < 0
      ? '-'
      : (showPositiveSign && storedQuantity > 0 ? '+' : '');
  return [
    sign,
    localizedQuantity(storedQuantity.abs(), measurementType),
  ].join();
}

/// Formats aggregate quantities without ever adding unlike dimensions
/// (for example kilograms to litres).
String localizedQuantityTotals(Map<String, int> quantitiesByType) {
  final nonZero = Map<String, int>.fromEntries(
    quantitiesByType.entries.where((entry) => entry.value != 0),
  );
  final values = nonZero.isEmpty ? quantitiesByType : nonZero;
  if (values.isEmpty) return localizedQuantity(0, 'piece');
  return values.entries
      .map((entry) => localizedQuantity(entry.value, entry.key))
      .join(' • ');
}

Map<String, int> aggregateQuantityTotals<T>(
  Iterable<T> items, {
  required int Function(T item) quantityOf,
  required String Function(T item) measurementTypeOf,
}) {
  final totals = <String, int>{};
  for (final item in items) {
    final type = measurementTypeOf(item);
    final quantity = quantityOf(item);
    totals.update(type, (value) => value + quantity, ifAbsent: () => quantity);
  }
  return totals;
}
