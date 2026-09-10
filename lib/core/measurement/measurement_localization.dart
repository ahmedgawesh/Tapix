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
  final normalized = <String, int>{};
  for (final entry in quantitiesByType.entries) {
    final type = MeasurementType.fromDb(entry.key).dbValue;
    normalized.update(
      type,
      (value) => value + entry.value,
      ifAbsent: () => entry.value,
    );
  }
  final nonZero = Map<String, int>.fromEntries(
    normalized.entries.where((entry) => entry.value != 0),
  );
  final values = nonZero.isEmpty ? normalized : nonZero;
  if (values.isEmpty) return localizedQuantity(0, 'piece');
  return MeasurementType.values
      .where((type) => values.containsKey(type.dbValue))
      .map((type) => localizedQuantity(values[type.dbValue]!, type.dbValue))
      .join(' • ');
}

Map<String, int> aggregateQuantityTotals<T>(
  Iterable<T> items, {
  required int Function(T item) quantityOf,
  required String Function(T item) measurementTypeOf,
}) {
  final totals = <String, int>{};
  for (final item in items) {
    final type = MeasurementType.fromDb(measurementTypeOf(item)).dbValue;
    final quantity = quantityOf(item);
    totals.update(type, (value) => value + quantity, ifAbsent: () => quantity);
  }
  return totals;
}

/// Builds a display-ready total while keeping pieces, lengths, weights, and
/// volumes in separate buckets. Stored milli-units are converted only after
/// aggregation, so 2 pieces plus 2 metres can never become 2002 pieces.
String localizedQuantitySummary<T>(
  Iterable<T> items, {
  required int Function(T item) quantityOf,
  required String Function(T item) measurementTypeOf,
}) {
  return localizedQuantityTotals(
    aggregateQuantityTotals(
      items,
      quantityOf: quantityOf,
      measurementTypeOf: measurementTypeOf,
    ),
  );
}
