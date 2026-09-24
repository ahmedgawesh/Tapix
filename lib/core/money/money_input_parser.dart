import 'package:decimal/decimal.dart';

import '../services/currency_service.dart';

/// Result of attempting to parse a free-form user-typed amount.
///
/// Use [isValid] to gate UI submission and [cents] only when [isValid] is
/// true. The pair (`error`, `cents`) is mutually exclusive.
class MoneyInputParseResult {
  /// Parsed integer cents. Always `0` when [isValid] is false.
  final int cents;

  /// Localized error reason when parsing failed; `null` when the input
  /// represented a well-formed non-negative monetary amount.
  final MoneyInputError? error;

  const MoneyInputParseResult._(this.cents, this.error);

  bool get isValid => error == null;
}

/// Reasons a user-typed amount can fail validation. Kept as an enum so
/// callers can localize each variant independently and so unit tests can
/// assert the exact rejection cause.
enum MoneyInputError { empty, notANumber, negative, tooManyDecimals, overflow }

/// Single source of truth for converting a free-form text amount typed by a
/// user (e.g. into a `TextField`) into the canonical integer-cents
/// representation used everywhere else in the codebase.
///
/// Why a dedicated service exists:
///
/// 1. **`Decimal` not `double`** — IEEE-754 doubles silently lose precision
///    at common monetary edges (e.g. `99999.99 * 100 = 9999998.999...`). A
///    single missed `.round()` then drops a cent. Using
///    `Decimal.tryParse(...) * 100` keeps base-10 precision until the very
///    end.
///
/// 2. **Currency-aware decimal digits** — JOD/KWD/BHD/OMR have 3 digits;
///    JPY/KRW/IQD have 0. Hard-coding `* 100` is wrong for any of these.
///    This parser asks [CurrencyService] for the active currency's
///    `decimalDigits` and rejects user input that exceeds it (so a user
///    cannot type `12.345` for USD and have the trailing `5` silently
///    dropped — it becomes a validation error).
///
/// 3. **No silent sign flips** — negative input is rejected. The
///    "payment-is-negative" rule is a *posting* concern, not a parsing
///    concern, and lives inside the repositories
///    (`CustomerRepository.recordPayment`, etc.).
///
/// All UI forms must route through [parse]; widgets should never call
/// `double.parse(...) * 100`. A regression test in
/// `test/core/money/money_input_parser_test.dart` locks this behaviour in.
class MoneyInputParser {
  final CurrencyService _currencyService;

  const MoneyInputParser(this._currencyService);

  /// Parse [text] as a monetary amount in the user's active currency and
  /// return the equivalent integer cents.
  ///
  /// When [decimalDigits] is omitted the parser uses the active currency's
  /// own `decimalDigits` (so 3-decimal-digit currencies like KWD are
  /// handled correctly). Pass an explicit value only for tests or for
  /// flows that need to override the active currency (e.g. multi-currency
  /// invoice lines).
  MoneyInputParseResult parse(String? text, {int? decimalDigits}) {
    final raw = (text ?? '').trim();
    if (raw.isEmpty) {
      return const MoneyInputParseResult._(0, MoneyInputError.empty);
    }

    // Normalize: accept Arabic-Indic digits and commas as decimal
    // separators (common in fr/ar locales). Strip thousands separators.
    final normalized = _normalize(raw);

    final parsed = Decimal.tryParse(normalized);
    if (parsed == null) {
      return const MoneyInputParseResult._(0, MoneyInputError.notANumber);
    }
    if (parsed < Decimal.zero) {
      return const MoneyInputParseResult._(0, MoneyInputError.negative);
    }

    final digits =
        decimalDigits ?? _currencyService.getCurrency().decimalDigits;
    final scale = _scaleOf(parsed);
    if (scale > digits) {
      return const MoneyInputParseResult._(0, MoneyInputError.tooManyDecimals);
    }

    final factor = _powerOfTen(digits);
    final centsDecimal = (parsed * Decimal.fromInt(factor));
    // After scaling by 10^digits the value MUST be an integer because we
    // already rejected over-precision input above.
    if (!centsDecimal.isInteger) {
      // Defense in depth — should be unreachable.
      return const MoneyInputParseResult._(0, MoneyInputError.tooManyDecimals);
    }
    final big = centsDecimal.toBigInt();
    if (!big.isValidInt) {
      return const MoneyInputParseResult._(0, MoneyInputError.overflow);
    }
    return MoneyInputParseResult._(big.toInt(), null);
  }

  /// Convenience wrapper for callers who only care about a successfully
  /// parsed value and want to fall back to `0` on bad input. Prefer
  /// [parse] in production paths so the validation error is preserved and
  /// the user gets actionable feedback.
  int parseOrZero(String? text, {int? decimalDigits}) {
    final result = parse(text, decimalDigits: decimalDigits);
    return result.isValid ? result.cents : 0;
  }

  /// Phase 8 — Signed variant for *opening-balance / adjustment* fields
  /// that legitimately accept a negative magnitude (e.g. a customer who
  /// holds credit on file, or a supplier opening balance that represents
  /// a prepaid advance). The parser strips a single leading `-`, parses
  /// the magnitude through the standard [parse] pipeline (which preserves
  /// every guard — currency decimal digits, IEEE-754 avoidance,
  /// Arabic-Indic digits, etc.), then re-applies the sign.
  ///
  /// Returns `0` on malformed input (mirrors [parseOrZero]).
  ///
  /// Distinct from [parse] because opening-balance is the *one* place
  /// where a negative magnitude is a semantic value, not a sign-flip bug.
  /// Payment / receipt / discount flows must continue to use [parse] and
  /// let the repository own the negation rule.
  int parseSignedOrZero(String? text, {int? decimalDigits}) {
    final raw = (text ?? '').trim();
    if (raw.isEmpty) return 0;
    final negative = raw.startsWith('-');
    final magnitudeText = negative ? raw.substring(1) : raw;
    final magnitude = parseOrZero(magnitudeText, decimalDigits: decimalDigits);
    return negative ? -magnitude : magnitude;
  }

  /// Number of fractional digits in [d]. `Decimal` does not expose `scale`
  /// directly across all versions, so we derive it from the canonical
  /// string representation.
  int _scaleOf(Decimal d) {
    final s = d.toString();
    final dot = s.indexOf('.');
    if (dot < 0) return 0;
    return s.length - dot - 1;
  }

  int _powerOfTen(int n) {
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }

  /// Map Arabic-Indic digits to ASCII and treat `,` as decimal separator
  /// when no `.` is present (locales like fr/ar). Drops leading `+` and
  /// removes spaces commonly inserted as thousands separators.
  String _normalize(String input) {
    final buf = StringBuffer();
    for (final code in input.runes) {
      // Arabic-Indic digits 0660–0669 → 0030–0039
      if (code >= 0x0660 && code <= 0x0669) {
        buf.writeCharCode(0x0030 + (code - 0x0660));
        continue;
      }
      // Extended Arabic-Indic digits 06F0–06F9 (Persian/Urdu) → ASCII
      if (code >= 0x06F0 && code <= 0x06F9) {
        buf.writeCharCode(0x0030 + (code - 0x06F0));
        continue;
      }
      buf.writeCharCode(code);
    }
    var s = buf.toString();
    s = s.replaceAll(' ', '');
    if (s.startsWith('+')) s = s.substring(1);
    // If string contains a comma but no dot, treat the comma as the
    // decimal separator. If it contains both, assume the comma is a
    // thousands separator and drop it.
    final hasDot = s.contains('.');
    final hasComma = s.contains(',');
    if (hasComma && !hasDot) {
      s = s.replaceAll(',', '.');
    } else if (hasComma && hasDot) {
      s = s.replaceAll(',', '');
    }
    return s;
  }
}
