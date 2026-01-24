import 'package:flutter_test/flutter_test.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/converters/money_converter.dart';

void main() {
  group('MoneyConverter', () {
    late MoneyConverter converter;

    setUp(() {
      converter = const MoneyConverter();
    });

    test('converts cents to Decimal correctly', () {
      expect(converter.fromSql(10000), equals(Decimal.fromInt(10000)));
      expect(converter.fromSql(1050), equals(Decimal.fromInt(1050)));
      expect(converter.fromSql(1), equals(Decimal.fromInt(1)));
      expect(converter.fromSql(0), equals(Decimal.zero));
    });

    test('converts Decimal to cents correctly', () {
      expect(converter.toSql(Decimal.fromInt(10000)), equals(10000));
      expect(converter.toSql(Decimal.fromInt(1050)), equals(1050));
      expect(converter.toSql(Decimal.fromInt(1)), equals(1));
      expect(converter.toSql(Decimal.zero), equals(0));
    });

    test('maintains precision for money calculations', () {
      final amount1 = Decimal.fromInt(1999);
      final amount2 = Decimal.fromInt(1);
      final sum = amount1 + amount2;
      
      final cents = converter.toSql(sum);
      final backToDecimal = converter.fromSql(cents);
      
      expect(backToDecimal, equals(Decimal.fromInt(2000)));
    });

    test('handles large amounts correctly', () {
      final largeAmount = Decimal.fromInt(99999999);
      final cents = converter.toSql(largeAmount);
      expect(cents, equals(99999999));
      expect(converter.fromSql(cents), equals(largeAmount));
    });

    test('round-trip conversion maintains accuracy', () {
      final testValues = [
        Decimal.fromInt(1),
        Decimal.fromInt(100),
        Decimal.fromInt(1050),
        Decimal.fromInt(10099),
        Decimal.fromInt(123456),
      ];

      for (final value in testValues) {
        final cents = converter.toSql(value);
        final backToDecimal = converter.fromSql(cents);
        expect(backToDecimal, equals(value), reason: 'Failed for $value');
      }
    });
  });

  group('BasisPointsConverter', () {
    late BasisPointsConverter converter;

    setUp(() {
      converter = const BasisPointsConverter();
    });

    test('converts basis points to percentage correctly', () {
      expect(converter.fromSql(10000), equals(1.0));
      expect(converter.fromSql(500), equals(0.05));
      expect(converter.fromSql(1), equals(0.0001));
      expect(converter.fromSql(0), equals(0.0));
    });

    test('converts percentage to basis points correctly', () {
      expect(converter.toSql(1.0), equals(10000));
      expect(converter.toSql(0.05), equals(500));
      expect(converter.toSql(0.0001), equals(1));
      expect(converter.toSql(0.0), equals(0));
    });

    test('handles tax rates correctly', () {
      final taxRate = 0.19;
      final bps = converter.toSql(taxRate);
      expect(bps, equals(1900));
      expect(converter.fromSql(bps), equals(taxRate));
    });
  });
}
