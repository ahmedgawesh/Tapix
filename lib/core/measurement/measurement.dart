import 'package:decimal/decimal.dart';

/// The stock dimension selected for a product.
///
/// Products with variants deliberately inherit this value from their parent;
/// mixing dimensions between variants would make aggregate stock and costing
/// meaningless.
enum MeasurementType {
  piece('piece'),
  length('length'),
  weight('weight'),
  volume('volume');

  const MeasurementType(this.dbValue);
  final String dbValue;

  static MeasurementType fromDb(String? value) {
    return MeasurementType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => MeasurementType.piece,
    );
  }

  /// Integer quantity units used by stock tables.
  ///
  /// Legacy/count products remain 1:1. Measured products use one thousand
  /// internal units per major unit (kg/litre/metre), so stock and FIFO remain
  /// exact integers and existing rows remain untouched.
  int get quantityScale => this == MeasurementType.piece ? 1 : 1000;

  MeasurementUnit get majorUnit => switch (this) {
    MeasurementType.piece => MeasurementUnit.piece,
    MeasurementType.length => MeasurementUnit.meter,
    MeasurementType.weight => MeasurementUnit.kilogram,
    MeasurementType.volume => MeasurementUnit.liter,
  };

  MeasurementUnit? get minorUnit => switch (this) {
    MeasurementType.piece => null,
    MeasurementType.length => MeasurementUnit.centimeter,
    MeasurementType.weight => MeasurementUnit.gram,
    MeasurementType.volume => MeasurementUnit.milliliter,
  };

  List<MeasurementUnit> get inputUnits => [majorUnit, ?minorUnit];
}

enum MeasurementUnit {
  piece('piece', MeasurementType.piece, 1),
  meter('meter', MeasurementType.length, 1000),
  centimeter('centimeter', MeasurementType.length, 10),
  kilogram('kilogram', MeasurementType.weight, 1000),
  gram('gram', MeasurementType.weight, 1),
  liter('liter', MeasurementType.volume, 1000),
  milliliter('milliliter', MeasurementType.volume, 1);

  const MeasurementUnit(this.dbValue, this.type, this.internalFactor);
  final String dbValue;
  final MeasurementType type;

  /// Number of internal stock units represented by one input unit.
  final int internalFactor;
}

/// Exact conversions and formatting for stock quantities.
class MeasuredQuantity {
  const MeasuredQuantity._();

  /// Converts user input to the integer quantity stored in SQLite.
  /// Throws rather than silently rounding and changing stock.
  static int parseToStored(String raw, MeasurementUnit unit) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      throw const FormatException('quantity_required');
    }
    final value = Decimal.tryParse(normalized);
    if (value == null || value < Decimal.zero) {
      throw const FormatException('quantity_invalid');
    }
    final scaled = value * Decimal.fromInt(unit.internalFactor);
    if (!scaled.isInteger) {
      throw const FormatException('quantity_precision_exceeded');
    }
    return scaled.toBigInt().toInt();
  }

  static String editableValue(int stored, MeasurementUnit unit) {
    final value =
        Decimal.fromInt(stored) / Decimal.fromInt(unit.internalFactor);
    return _trimDecimal(
      value.toDecimal(scaleOnInfinitePrecision: 6).toString(),
    );
  }

  static String majorValue(int stored, MeasurementType type) {
    if (type == MeasurementType.piece) return stored.toString();
    final value = Decimal.fromInt(stored) / Decimal.fromInt(type.quantityScale);
    return _trimDecimal(
      value.toDecimal(scaleOnInfinitePrecision: 3).toString(),
    );
  }

  static String _trimDecimal(String value) {
    if (!value.contains('.')) return value;
    return value.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

/// Monetary helpers for a price/cost expressed per major measurement unit.
class MeasuredAmount {
  const MeasuredAmount._();

  /// Commercial half-up rounding to the nearest cent. Quantities and amounts
  /// used by inventory valuation are non-negative; signed callers should
  /// apply the sign after computing the absolute amount.
  static int cents({
    required int unitCents,
    required int quantity,
    required int quantityScale,
  }) {
    if (quantityScale <= 0) {
      throw ArgumentError.value(quantityScale, 'quantityScale');
    }
    final negative = (unitCents < 0) != (quantity < 0);
    final numerator =
        BigInt.from(unitCents.abs()) * BigInt.from(quantity.abs());
    final divisor = BigInt.from(quantityScale);
    final rounded = (numerator + (divisor ~/ BigInt.two)) ~/ divisor;
    final value = rounded.toInt();
    return negative ? -value : value;
  }

  static int unitCentsFromTotal({
    required int totalCents,
    required int quantity,
    required int quantityScale,
  }) {
    if (quantity <= 0 || quantityScale <= 0) return 0;
    final numerator = BigInt.from(totalCents) * BigInt.from(quantityScale);
    return ((numerator + BigInt.from(quantity ~/ 2)) ~/ BigInt.from(quantity))
        .toInt();
  }
}
