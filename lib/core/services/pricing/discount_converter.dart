import 'package:decimal/decimal.dart';

/// Phase 3.5.5 — single source of truth for fixed ↔ percent discount
/// conversions.
///
/// ## Why this exists
///
/// The same bidirectional conversion (percent ↔ cents) was being
/// re-implemented in at least three widgets (`sale_form_dialogs.dart` in
/// two places plus the line-edit sheet). Each copy used `double` math
/// with `* 100 / 100` round-trips which silently lost precision on
/// common inputs (e.g. `33.33%` of `10000 cents` → `3333` one way but
/// `33.33%` back the other way, rounding differently depending on
/// intermediate precision).
///
/// This service owns the conversion end-to-end using [Decimal] and
/// exposes a minimal, side-effect-free API that the widgets just call.
///
/// ## Semantics
///
/// *All cents are non-negative integers.* A negative subtotal is an
/// invariant violation and the caller is responsible for short-circuiting
/// before calling this service.
///
/// *Percentages are Decimals in the `[0, 100]` range.* Values outside
/// that range are clamped (the UI forbids > 100 and < 0 anyway, but the
/// clamp makes the service robust against stale controller text).
///
/// *Rounding is half-away-from-zero* (Dart's default `round()`). This
/// matches the convention used across `PricingEngine` and
/// `ReturnCalculationService` so the UI preview and the posted invoice
/// always agree on the last digit.
///
/// *The fixed amount never exceeds the subtotal.* `fixedFromPercent`
/// always clamps to `[0, subtotalCents]` so a 110%-by-bug input cannot
/// generate a negative line total downstream.
class DiscountConverter {
  const DiscountConverter();

  /// Convert a percent (0..100) into a fixed discount in cents against
  /// [subtotalCents]. Returns `0` if the subtotal is `<= 0` or the
  /// percent rounds to zero.
  int fixedFromPercent({required int subtotalCents, required Decimal percent}) {
    if (subtotalCents <= 0) return 0;
    final p = _clampPercent(percent);
    if (p == Decimal.zero) return 0;
    // (subtotal * percent) / 100, rounded half-away-from-zero. We stay
    // inside Decimal/Rational and only collapse to int at the boundary.
    final rational =
        (Decimal.fromInt(subtotalCents) * p) / Decimal.fromInt(100);
    final cents = rational
        .toDecimal(scaleOnInfinitePrecision: 6)
        .round()
        .toBigInt()
        .toInt();
    if (cents <= 0) return 0;
    if (cents > subtotalCents) return subtotalCents;
    return cents;
  }

  /// Convert a fixed discount in cents into a percent (0..100) against
  /// [subtotalCents]. Returns `Decimal.zero` if either side is `<= 0`.
  ///
  /// The result is rounded to [decimalDigits] fractional digits (default
  /// 2) so the UI does not jitter to 4+ decimals between keystrokes.
  Decimal percentFromFixed({
    required int subtotalCents,
    required int fixedCents,
    int decimalDigits = 2,
  }) {
    if (subtotalCents <= 0 || fixedCents <= 0) return Decimal.zero;
    final clamped = fixedCents > subtotalCents ? subtotalCents : fixedCents;
    final rational =
        (Decimal.fromInt(clamped) * Decimal.fromInt(100)) /
        Decimal.fromInt(subtotalCents);
    // Truncate the infinite-precision result to the requested digits so
    // the UI does not jitter between keystrokes.
    return rational
        .toDecimal(scaleOnInfinitePrecision: decimalDigits)
        .round(scale: decimalDigits);
  }

  Decimal _clampPercent(Decimal p) {
    if (p < Decimal.zero) return Decimal.zero;
    final max = Decimal.fromInt(100);
    if (p > max) return max;
    return p;
  }
}
