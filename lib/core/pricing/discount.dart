// ════════════════════════════════════════════════════════════════════════════
// Discount — sealed value type
// ════════════════════════════════════════════════════════════════════════════
//
// PURPOSE
//   Represent "the amount and the kind of a discount" as a single, exhaustive
//   value. Replaces the historical pattern of two parallel fields
//   (`discountCents` + `isPercent` boolean) which was the *direct* cause of
//   the "edit qty does not reapply %" bug — the percent intent was lost
//   the moment the UI converted to cents.
//
// USAGE
//   ```dart
//   const noDisc = Discount.none;
//   final fixed = Discount.fixed(Money.fromCents(500));
//   final pct   = Discount.percent(100); // 1 %
//
//   // Resolve against a base — the only place where the conversion happens:
//   final amount = pct.resolve(Money.fromCents(80000)); // Money(800¢)
//   ```
// ════════════════════════════════════════════════════════════════════════════

import '../money/money.dart';

/// A discount expressed as either no discount, a fixed money amount, or a
/// percentage in basis points.
sealed class Discount {
  const Discount();

  /// Singleton "no discount".
  static const Discount none = NoDiscount._();

  /// Fixed money discount.
  factory Discount.fixed(Money amount) = FixedDiscount;

  /// Percent discount in basis points (`100 bps = 1 %`).
  factory Discount.percent(int bps) = PercentDiscount;

  /// Resolve this discount against a base amount, returning the actual
  /// money value. The result is always **clamped to `[0, base]`** so a
  /// 110 % discount cannot make the line negative and a fixed discount
  /// cannot exceed the base.
  ///
  /// Rounds to whole cents using [mode].
  Money resolve(
    Money base, {
    MoneyRoundingMode mode = MoneyRoundingMode.halfUp,
  });

  /// True if this discount carries no value.
  bool get isZero;
}

/// No discount applied.
class NoDiscount extends Discount {
  const NoDiscount._();

  @override
  Money resolve(Money base, {MoneyRoundingMode mode = MoneyRoundingMode.halfUp}) =>
      Money.zero;

  @override
  bool get isZero => true;

  @override
  bool operator ==(Object other) => other is NoDiscount;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'Discount.none';
}

/// A fixed money discount, e.g. "5.00 off".
class FixedDiscount extends Discount {
  final Money amount;
  const FixedDiscount(this.amount);

  @override
  Money resolve(Money base, {MoneyRoundingMode mode = MoneyRoundingMode.halfUp}) {
    if (base.isZero || amount.isZero) return Money.zero;
    if (amount.isNegative) {
      throw ArgumentError(
        'FixedDiscount: amount must be non-negative, got $amount',
      );
    }
    // Clamp to [0, base] so we never over-discount.
    return amount.min(base).clampNonNegative();
  }

  @override
  bool get isZero => amount.isZero;

  @override
  bool operator ==(Object other) =>
      other is FixedDiscount && other.amount == amount;

  @override
  int get hashCode => amount.hashCode;

  @override
  String toString() => 'Discount.fixed($amount)';
}

/// A percent discount expressed in basis points. `100 bps = 1 %`.
///
/// **Contract:** the percent base is **exactly** the [Money] passed to
/// [resolve]. The caller is responsible for choosing the correct base
/// (typically `subtotal` for line-level and `Σ subtotal − itemDiscounts`
/// for invoice-level). This contract is what closes the
/// "1 % of net+tax vs 1 % of net" bug class — there is exactly **one**
/// arithmetic path.
class PercentDiscount extends Discount {
  /// Basis points. Must be in `[0, 1_000_000]` (i.e. 0–10 000 %).
  /// 10 000 bps = 100 %.
  final int bps;

  const PercentDiscount(this.bps)
      : assert(bps >= 0, 'PercentDiscount.bps must be non-negative'),
        assert(bps <= 1000000,
            'PercentDiscount.bps capped at 1_000_000 (10 000 %)');

  @override
  Money resolve(Money base, {MoneyRoundingMode mode = MoneyRoundingMode.halfUp}) {
    if (base.isZero || bps == 0) return Money.zero;
    final raw = base.percentage(bps, mode: mode);
    // Clamp so a >100 % rate cannot exceed the base.
    return raw.min(base).clampNonNegative();
  }

  @override
  bool get isZero => bps == 0;

  @override
  bool operator ==(Object other) =>
      other is PercentDiscount && other.bps == bps;

  @override
  int get hashCode => bps.hashCode ^ 0x9E3779B9;

  @override
  String toString() =>
      'Discount.percent(${(bps / 100).toStringAsFixed(2)}%)';
}
