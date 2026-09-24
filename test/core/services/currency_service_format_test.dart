import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/money/money_input_parser.dart';
import 'package:tapix/core/services/currency_service.dart';

void main() {
  late CurrencyService service;
  String? oldLocale;
  setUp(() async {
    oldLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en';
    SharedPreferences.setMockInitialValues({});
    service = CurrencyService(await SharedPreferences.getInstance());
  });
  tearDown(() async {
    await service.dispose();
    Intl.defaultLocale = oldLocale;
  });

  for (final entry in {
    'USD': '12.34',
    'EGP': '12.34',
    'JPY': '1234',
    'KWD': '12.345',
  }.entries) {
    test('${entry.key} input and display agree on minor-unit scale', () async {
      await service.setCurrency(entry.key);
      final value = MoneyInputParser(service).parse(entry.value);
      expect(value.isValid, isTrue);
      expect(service.centsToDecimalString(value.cents), entry.value);
      expect(
        service.format(value.cents, showSymbol: false).replaceAll(',', ''),
        entry.value,
      );
      expect(service.centsToDecimalString(-value.cents), '-${entry.value}');
    });
  }

  test('document currency formatting ignores the device currency', () async {
    await service.setCurrency('USD');

    expect(service.formatForCode(12345, 'KWD', showSymbol: false), '12.345');
    expect(service.minorUnitsToDecimalStringForCode(12345, 'KWD'), '12.345');
    expect(service.decimalDigitsForCode('KWD'), 3);
  });

  test(
    'decimal editor conversion preserves large integer minor units',
    () async {
      await service.setCurrency('KWD');
      const value = 9007199254740991;
      final text = service.centsToDecimalString(value);
      expect(text, '9007199254740.991');
      expect(MoneyInputParser(service).parse(text).cents, value);
    },
  );
}
