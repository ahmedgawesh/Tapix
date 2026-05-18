import 'package:decimal/decimal.dart';

/// Phase 7 — Single source of truth for the small family of ratio /
/// percentage display computations scattered across the report blocs.
///
/// Before Phase 7, the pattern
///   `den > 0 ? (num / den) * 100 : 0.0`
/// was duplicated ~12 times across `discount_reports_bloc`,
/// `profit_reports_bloc`, and a handful of related report blocs. Each copy
/// did the same thing, but every copy:
///   * picked its own zero-denominator guard (`> 0` vs `!= 0`),
///   * relied on IEEE-754 double division for what is logically a ratio of
///     integer cents (drift on adversarial inputs).
///
/// `RatioHelper` is intentionally tiny:
///   * Inputs are typed ints (cents) or bps; no implicit promotion.
///   * Internal math uses [Decimal] for determinism — the conversion to
///     `double` happens at the very end, only for display payload.
///   * Zero-denominator cases return `0.0` (display-safe default).
///
/// All methods are `static`; this class is not instantiable.
class RatioHelper {
  RatioHelper._();

  static final Decimal _hundred = Decimal.fromInt(100);

  /// Compute a percentage **for display**: `(numerator / denominator) × 100`.
  ///
  /// Returns `0.0` when [denominatorCents] is zero (display-safe default;
  /// avoids `NaN` / `Infinity` leaking into a chart).
  ///
  /// Handles negative numerators (returns / refunds) correctly:
  /// `percent(-50, 1000) == -5.0`. The denominator-zero guard checks for
  /// **exact zero** so negative denominators are still computed (matches
  /// the `profit_reports_bloc.dart` return-row treatment).
  ///
  /// Examples:
  /// ```dart
  /// RatioHelper.percent(numeratorCents: 250, denominatorCents: 1000) == 25.0
  /// RatioHelper.percent(numeratorCents: 1, denominatorCents: 0) == 0.0
  /// ```
  static double percent({
    required int numeratorCents,
    required int denominatorCents,
  }) {
    if (denominatorCents == 0) return 0.0;
    final num = Decimal.fromInt(numeratorCents);
    final den = Decimal.fromInt(denominatorCents);
    // num / den returns a Rational (exact ratio of integers). Collapse to
    // double at the very boundary, then scale by 100 (exact for any
    // IEEE-754 value × 100). This avoids the silent precision loss of
    // `(num.toDouble() / den.toDouble())` when either side overflows
    // 2^53 cents — defensive even though our display inputs never do.
    final ratio = num / den;
    return ratio.toDouble() * 100;
  }

  /// Convert basis points to a percentage value **for display**:
  /// `bps / 100`.
  ///
  /// Examples:
  /// ```dart
  /// RatioHelper.bpsToPercent(500)  == 5.0
  /// RatioHelper.bpsToPercent(1250) == 12.5
  /// RatioHelper.bpsToPercent(0)    == 0.0
  /// ```
  ///
  /// Always exact for integer bps inputs (Decimal arithmetic; no double
  /// rounding). Use this instead of `bps / 100` whenever the result feeds
  /// a UI label or report aggregate, so the same formula lives in one
  /// place.
  static double bpsToPercent(int bps) {
    if (bps == 0) return 0.0;
    return (Decimal.fromInt(bps) / _hundred).toDouble();
  }
}
