import 'package:decimal/decimal.dart';

const int medicineStrengthScale = 1000000;

class PharmacyValidationException implements Exception {
  const PharmacyValidationException(this.code, [this.details]);

  final String code;
  final String? details;

  @override
  String toString() => details == null ? code : '$code: $details';
}

class NormalizedMedicineStrength {
  const NormalizedMedicineStrength({
    required this.valueMicros,
    required this.unit,
    this.basisValueMicros,
    this.basisUnit,
  });

  final int valueMicros;
  final String unit;
  final int? basisValueMicros;
  final String? basisUnit;

  bool equivalentTo(NormalizedMedicineStrength other) {
    if (unit != other.unit || basisUnit != other.basisUnit) return false;
    final leftBasis = basisValueMicros;
    final rightBasis = other.basisValueMicros;
    if (leftBasis == null || rightBasis == null) {
      return leftBasis == null &&
          rightBasis == null &&
          valueMicros == other.valueMicros;
    }
    return BigInt.from(valueMicros) * BigInt.from(rightBasis) ==
        BigInt.from(other.valueMicros) * BigInt.from(leftBasis);
  }
}

class MedicineNormalizationService {
  const MedicineNormalizationService();

  static final RegExp _arabicMarks = RegExp(
    r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]',
  );
  static final RegExp _separators = RegExp(r'[\s\-_.،,؛;:/\\(){}\[\]]+');
  static final BigInt _sqliteIntMax = BigInt.parse('9223372036854775807');

  static final Map<String, _UnitDefinition> _strengthUnits = {
    'ng': _UnitDefinition('mg', Decimal.parse('0.000001')),
    'nanogram': _UnitDefinition('mg', Decimal.parse('0.000001')),
    'nanograms': _UnitDefinition('mg', Decimal.parse('0.000001')),
    'mcg': _UnitDefinition('mg', Decimal.parse('0.001')),
    'ug': _UnitDefinition('mg', Decimal.parse('0.001')),
    'microgram': _UnitDefinition('mg', Decimal.parse('0.001')),
    'micrograms': _UnitDefinition('mg', Decimal.parse('0.001')),
    'ميكروجرام': _UnitDefinition('mg', Decimal.parse('0.001')),
    'mg': _UnitDefinition('mg', Decimal.one),
    'milligram': _UnitDefinition('mg', Decimal.one),
    'milligrams': _UnitDefinition('mg', Decimal.one),
    'مجم': _UnitDefinition('mg', Decimal.one),
    'ملجم': _UnitDefinition('mg', Decimal.one),
    'g': _UnitDefinition('mg', Decimal.fromInt(1000)),
    'gram': _UnitDefinition('mg', Decimal.fromInt(1000)),
    'grams': _UnitDefinition('mg', Decimal.fromInt(1000)),
    'gramme': _UnitDefinition('mg', Decimal.fromInt(1000)),
    'جرام': _UnitDefinition('mg', Decimal.fromInt(1000)),
    'جم': _UnitDefinition('mg', Decimal.fromInt(1000)),
    'kg': _UnitDefinition('mg', Decimal.fromInt(1000000)),
    'kilogram': _UnitDefinition('mg', Decimal.fromInt(1000000)),
    'kilograms': _UnitDefinition('mg', Decimal.fromInt(1000000)),
    'كجم': _UnitDefinition('mg', Decimal.fromInt(1000000)),
    'ul': _UnitDefinition('ml', Decimal.parse('0.001')),
    'microliter': _UnitDefinition('ml', Decimal.parse('0.001')),
    'microlitre': _UnitDefinition('ml', Decimal.parse('0.001')),
    'ml': _UnitDefinition('ml', Decimal.one),
    'milliliter': _UnitDefinition('ml', Decimal.one),
    'millilitre': _UnitDefinition('ml', Decimal.one),
    'مل': _UnitDefinition('ml', Decimal.one),
    'مللي': _UnitDefinition('ml', Decimal.one),
    'cl': _UnitDefinition('ml', Decimal.fromInt(10)),
    'dl': _UnitDefinition('ml', Decimal.fromInt(100)),
    'l': _UnitDefinition('ml', Decimal.fromInt(1000)),
    'liter': _UnitDefinition('ml', Decimal.fromInt(1000)),
    'litre': _UnitDefinition('ml', Decimal.fromInt(1000)),
    'لتر': _UnitDefinition('ml', Decimal.fromInt(1000)),
    'iu': _UnitDefinition('iu', Decimal.one),
    'internationalunit': _UnitDefinition('iu', Decimal.one),
    'internationalunits': _UnitDefinition('iu', Decimal.one),
    'وحدهدوليه': _UnitDefinition('iu', Decimal.one),
    'وحداتدوليه': _UnitDefinition('iu', Decimal.one),
    'unit': _UnitDefinition('unit', Decimal.one),
    'units': _UnitDefinition('unit', Decimal.one),
    'وحده': _UnitDefinition('unit', Decimal.one),
    'وحدات': _UnitDefinition('unit', Decimal.one),
    'mmol': _UnitDefinition('mmol', Decimal.one),
    'umol': _UnitDefinition('mmol', Decimal.parse('0.001')),
    'mol': _UnitDefinition('mmol', Decimal.fromInt(1000)),
    'meq': _UnitDefinition('meq', Decimal.one),
    '%': _UnitDefinition('percent', Decimal.one),
    'percent': _UnitDefinition('percent', Decimal.one),
  };

  static final Map<String, _UnitDefinition> _basisUnits = {
    'ul': _UnitDefinition('ml', Decimal.parse('0.001')),
    'microliter': _UnitDefinition('ml', Decimal.parse('0.001')),
    'microlitre': _UnitDefinition('ml', Decimal.parse('0.001')),
    'ml': _UnitDefinition('ml', Decimal.one),
    'milliliter': _UnitDefinition('ml', Decimal.one),
    'millilitre': _UnitDefinition('ml', Decimal.one),
    'مل': _UnitDefinition('ml', Decimal.one),
    'مللي': _UnitDefinition('ml', Decimal.one),
    'cl': _UnitDefinition('ml', Decimal.fromInt(10)),
    'dl': _UnitDefinition('ml', Decimal.fromInt(100)),
    'l': _UnitDefinition('ml', Decimal.fromInt(1000)),
    'liter': _UnitDefinition('ml', Decimal.fromInt(1000)),
    'litre': _UnitDefinition('ml', Decimal.fromInt(1000)),
    'لتر': _UnitDefinition('ml', Decimal.fromInt(1000)),
    'dose': _UnitDefinition('dose', Decimal.one),
    'جرعه': _UnitDefinition('dose', Decimal.one),
    'tablet': _UnitDefinition('tablet', Decimal.one),
    'قرص': _UnitDefinition('tablet', Decimal.one),
    'capsule': _UnitDefinition('capsule', Decimal.one),
    'كبسوله': _UnitDefinition('capsule', Decimal.one),
    'actuation': _UnitDefinition('actuation', Decimal.one),
    'بخه': _UnitDefinition('actuation', Decimal.one),
  };

  String normalizeIngredientName(String raw) {
    var value = raw.trim().toLowerCase().replaceAll(_arabicMarks, '');
    value = value
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ى', 'ي');
    value = value.replaceAll(_separators, ' ').trim();
    if (value.isEmpty) {
      throw const PharmacyValidationException('ingredient_name_required');
    }
    return value;
  }

  String normalizeCode(String raw, {required String field}) {
    final value = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-]+'), '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    if (value.isEmpty) {
      throw PharmacyValidationException('${field}_required');
    }
    return value;
  }

  NormalizedMedicineStrength normalizeStrength({
    required String value,
    required String unit,
    String? basisValue,
    String? basisUnit,
  }) {
    final hasBasisValue = basisValue != null && basisValue.trim().isNotEmpty;
    final hasBasisUnit = basisUnit != null && basisUnit.trim().isNotEmpty;
    if (hasBasisValue != hasBasisUnit) {
      throw const PharmacyValidationException('strength_basis_incomplete');
    }

    final strengthDefinition = _findUnit(unit, _strengthUnits);
    final normalizedValue = _toMicros(value, strengthDefinition);
    if (!hasBasisValue) {
      return NormalizedMedicineStrength(
        valueMicros: normalizedValue,
        unit: strengthDefinition.canonical,
      );
    }

    final basisDefinition = _findUnit(basisUnit!, _basisUnits);
    return NormalizedMedicineStrength(
      valueMicros: normalizedValue,
      unit: strengthDefinition.canonical,
      basisValueMicros: _toMicros(basisValue, basisDefinition),
      basisUnit: basisDefinition.canonical,
    );
  }

  String editableValue(int micros) {
    final value =
        Decimal.fromInt(micros) / Decimal.fromInt(medicineStrengthScale);
    return value
        .toDecimal(scaleOnInfinitePrecision: 6)
        .toString()
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  _UnitDefinition _findUnit(
    String raw,
    Map<String, _UnitDefinition> definitions,
  ) {
    final key = raw
        .trim()
        .toLowerCase()
        .replaceAll('μ', 'u')
        .replaceAll('µ', 'u')
        .replaceAll(_arabicMarks, '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('.', '')
        .replaceAll(RegExp(r'\s+'), '');
    final definition = definitions[key];
    if (definition == null) {
      throw PharmacyValidationException('strength_unit_unsupported', raw);
    }
    return definition;
  }

  int _toMicros(String raw, _UnitDefinition definition) {
    final normalized = _normalizeDigits(
      raw.trim(),
    ).replaceAll('٫', '.').replaceAll('٬', '').replaceAll(',', '.');
    final parsed = Decimal.tryParse(normalized);
    if (parsed == null || parsed <= Decimal.zero) {
      throw const PharmacyValidationException('strength_value_invalid');
    }
    final scaled =
        parsed * definition.factor * Decimal.fromInt(medicineStrengthScale);
    if (!scaled.isInteger) {
      throw const PharmacyValidationException('strength_precision_exceeded');
    }
    final integer = scaled.toBigInt();
    if (integer > _sqliteIntMax) {
      throw const PharmacyValidationException('strength_value_too_large');
    }
    return integer.toInt();
  }

  String _normalizeDigits(String value) {
    const source = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
    const target = '01234567890123456789';
    var result = value;
    for (var index = 0; index < source.length; index++) {
      result = result.replaceAll(source[index], target[index]);
    }
    return result;
  }
}

class _UnitDefinition {
  const _UnitDefinition(this.canonical, this.factor);

  final String canonical;
  final Decimal factor;
}
