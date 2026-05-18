import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/money/money_input_parser.dart';
import 'package:tapix/core/services/currency_service.dart';

/// Locks the Phase 3.5.1 contract: every monetary text input in the app
/// must travel through [MoneyInputParser] so that:
///
///   * `Decimal` (not `double`) drives parsing → no IEEE-754 cent loss
///   * the active currency's `decimalDigits` decide the cents factor
///   * over-precision, negatives and garbage are rejected with explicit
///     [MoneyInputError] codes (not silent zeros)
///   * Arabic-Indic digits and `fr`/`ar` style commas are normalised
void main() {
  late CurrencyService currency;
  late MoneyInputParser parser;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    currency = CurrencyService(prefs);
    parser = MoneyInputParser(currency);
  });

  group('happy path (USD, 2 digits)', () {
    test('whole number → cents * 100', () {
      final r = parser.parse('15');
      expect(r.isValid, isTrue);
      expect(r.cents, 1500);
    });

    test('two-decimal value preserves both digits', () {
      final r = parser.parse('19.99');
      expect(r.cents, 1999);
    });

    test('one-decimal value pads to two', () {
      final r = parser.parse('19.9');
      expect(r.cents, 1990);
    });

    test('zero is valid', () {
      final r = parser.parse('0');
      expect(r.isValid, isTrue);
      expect(r.cents, 0);
    });

    test('IEEE-754 trap: 0.1 + 0.2 style edges still round-trip exactly', () {
      // double.parse("0.1") * 100 = 10.000000000000002 — the bug we are
      // protecting against. The Decimal-backed parser must give 10 exact.
      expect(parser.parse('0.10').cents, 10);
      expect(parser.parse('0.20').cents, 20);
      // Classic over-precision boundary: 99999.99 * 100 in double space
      // produces 9999998.999999999. Decimal must give 9999999 exact.
      expect(parser.parse('99999.99').cents, 9999999);
    });
  });

  group('rejection cases', () {
    test('empty input → MoneyInputError.empty', () {
      final r = parser.parse('');
      expect(r.isValid, isFalse);
      expect(r.error, MoneyInputError.empty);
      expect(r.cents, 0);
    });

    test('whitespace-only → empty', () {
      expect(parser.parse('   ').error, MoneyInputError.empty);
    });

    test('letters → notANumber', () {
      expect(parser.parse('abc').error, MoneyInputError.notANumber);
    });

    test('negative → negative (sign flip is a posting concern, not parsing)',
        () {
      expect(parser.parse('-5').error, MoneyInputError.negative);
    });

    test('over-precision for 2-digit currency → tooManyDecimals', () {
      // USD is 2 digits; "12.345" has 3 fractional digits.
      expect(parser.parse('12.345').error, MoneyInputError.tooManyDecimals);
    });

    test('parseOrZero falls back to 0 on rejection', () {
      expect(parser.parseOrZero('garbage'), 0);
      expect(parser.parseOrZero('-5'), 0);
      expect(parser.parseOrZero('12.345'), 0);
    });
  });

  group('currency-aware decimal digits', () {
    test('JOD (3 digits) accepts 12.345 and gives 12345 fils', () async {
      await currency.setCurrency('JOD');
      expect(parser.parse('12.345').cents, 12345);
    });

    test('JOD rejects 12.3456 (4 digits) as tooManyDecimals', () async {
      await currency.setCurrency('JOD');
      expect(parser.parse('12.3456').error, MoneyInputError.tooManyDecimals);
    });

    test('JPY (0 digits) treats 1500 as 1500 yen, no scaling', () async {
      await currency.setCurrency('JPY');
      expect(parser.parse('1500').cents, 1500);
    });

    test('JPY rejects 1500.50 because 0 fractional digits allowed',
        () async {
      await currency.setCurrency('JPY');
      expect(parser.parse('1500.50').error, MoneyInputError.tooManyDecimals);
    });

    test('explicit decimalDigits override beats currency setting', () async {
      await currency.setCurrency('USD');
      // Force 3-digit interpretation for a multi-currency line.
      expect(parser.parse('1.234', decimalDigits: 3).cents, 1234);
    });
  });

  group('locale normalization', () {
    test('Arabic-Indic digits are normalised', () {
      // ١٩.٩٩ → 19.99
      expect(parser.parse('١٩.٩٩').cents, 1999);
    });

    test('Persian/Urdu extended Arabic-Indic digits are normalised', () {
      // ۱۹.۹۹ → 19.99
      expect(parser.parse('۱۹.۹۹').cents, 1999);
    });

    test('comma decimal separator (fr/ar) is accepted when no dot present',
        () {
      expect(parser.parse('19,99').cents, 1999);
    });

    test('mixed comma+dot drops commas as thousands separators', () {
      expect(parser.parse('1,234.56').cents, 123456);
    });

    test('embedded spaces (thousands separators) are stripped', () {
      expect(parser.parse('1 234.56').cents, 123456);
    });

    test('leading + is tolerated', () {
      expect(parser.parse('+12.34').cents, 1234);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Phase 8 — signed variant (opening-balance fields only)
  // ───────────────────────────────────────────────────────────────────────
  group('parseSignedOrZero (Phase 8)', () {
    test('positive magnitude matches parseOrZero', () {
      expect(parser.parseSignedOrZero('19.99'), 1999);
      expect(parser.parseSignedOrZero('19.99'), parser.parseOrZero('19.99'));
    });

    test('leading minus produces a negative cent value', () {
      expect(parser.parseSignedOrZero('-19.99'), -1999);
    });

    test('negative integer', () {
      expect(parser.parseSignedOrZero('-100'), -10000);
    });

    test('null / empty / whitespace → 0 (mirrors parseOrZero)', () {
      expect(parser.parseSignedOrZero(null), 0);
      expect(parser.parseSignedOrZero(''), 0);
      expect(parser.parseSignedOrZero('   '), 0);
    });

    test('garbage input → 0 (no throw)', () {
      expect(parser.parseSignedOrZero('not a number'), 0);
      expect(parser.parseSignedOrZero('-not a number'), 0);
    });

    test('IEEE-754 edge case 99999.99 round-trips exactly', () {
      // The legacy `(double.parse(text) * 100).round()` pattern silently
      // dropped a cent here on some platforms; the Decimal-backed parser
      // keeps it exact whether positive or negative.
      expect(parser.parseSignedOrZero('99999.99'), 9999999);
      expect(parser.parseSignedOrZero('-99999.99'), -9999999);
    });

    test('Arabic-Indic digits work with the signed variant', () {
      // -١٩.٩٩ → -1999
      expect(parser.parseSignedOrZero('-١٩.٩٩'), -1999);
    });

    test('comma decimal separator works with the signed variant', () {
      expect(parser.parseSignedOrZero('-19,99'), -1999);
    });

    test('over-precision input → 0 (validation failure is preserved)', () {
      // Three decimal digits with the default USD currency (2 digits)
      // is rejected by the underlying parser; signed variant inherits.
      expect(parser.parseSignedOrZero('-19.999'), 0);
    });
  });
}
