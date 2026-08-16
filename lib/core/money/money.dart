// ════════════════════════════════════════════════════════════════════════════
// Money value object — Tapix accounting kernel
// ════════════════════════════════════════════════════════════════════════════
//
// PURPOSE
//   A single, immutable, type-safe representation of monetary amounts in cents.
//   This class is the **foundation** of every financial calculation in Tapix.
//   Replacing scattered `int cents` and `Decimal` arithmetic with one well-
//   defined contract eliminates entire classes of rounding / "scattered code"
//   bugs (see history note below).
//
// DESIGN
//   * Internally backed by [Decimal] of cents — exact rational arithmetic.
//   * Construction is explicit: `Money.fromCents(int)`, `Money.zero`, etc.
//     There is **no implicit conversion** from `int`/`double`.
//   * Arithmetic operators allow only `Money + Money` and `Money * int` (a
//     scalar quantity). `Money * Money` is a type error by design — money
//     squared is meaningless in accounting.
//   * Percentages are computed via [Money.percentage] with an explicit
//     [RoundingMode]; no caller may invent a different formula.
//   * Allocation across weights uses the **largest-remainder method**, so
//     `sum(allocate(weights)) == self` exactly — no "lost cent" bugs.
//
// HISTORY
//   Created as part of the Phase 1 accounting hardening (Apr 2026) after the
//   "799.84 vs 799.92" discrepancy bug demonstrated that ad-hoc cents math
//   in form-state classes is unsafe at scale.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';

/// Rounding strategy for monetary operations that produce fractional cents.
///
/// * [halfUp] — round 0.5 away from zero (commercial / POS default).
/// * [halfEven] — banker's rounding; minimizes cumulative bias. IFRS friendly.
/// * [down] — truncate toward zero. Use only when explicitly required by law
///   or contract (rarely correct for general accounting).
enum MoneyRoundingMode { halfUp, halfEven, down }

/// Immutable value object representing an amount of money in **cents**.
///
/// All accounting calculations in Tapix should produce and consume [Money]
/// values rather than raw `int` cents. This makes the contract explicit and
/// makes accidental mixing of "raw number" and "cents" impossible at the
/// type level.
class Money implements Comparable<Money> {
  /// Exact value in cents. Preserved as [Decimal] to allow intermediate
  /// fractional values during chained operations; rounded back to integer
  /// cents at API boundaries.
  final Decimal _cents;

  const Money._(this._cents);

  // ── Construction ────────────────────────────────────────────────────────

  /// Zero money. Identity for addition.
  static final Money zero = Money._(Decimal.zero);

  /// Construct from an integer number of cents. Most common entry point.
  factory Money.fromCents(int cents) => Money._(Decimal.fromInt(cents));

  /// Construct from a [Decimal] cents value. The value must already be
  /// expressed in cents (not in major units). Fractional cents are
  /// permitted at construction time — round explicitly via [round] when
  /// needed.
  factory Money.fromDecimalCents(Decimal cents) => Money._(cents);

  /// Construct from a [BigInt] number of cents (for very large values).
  factory Money.fromBigIntCents(BigInt cents) =>
      Money._(Decimal.fromBigInt(cents));

  // ── Properties ──────────────────────────────────────────────────────────

  /// The amount in cents as an integer. Throws [StateError] if the value
  /// is not a whole number of cents — call [round] first if needed.
  int get cents {
    if (!_cents.isInteger) {
      throw StateError(
        'Money.cents called on non-integer value $_cents — '
        'call .round() first to commit to a whole-cent amount.',
      );
    }
    return _cents.toBigInt().toInt();
  }

  /// The amount in cents as a [Decimal] (always safe, may be fractional
  /// during intermediate computation).
  Decimal get decimalCents => _cents;

  /// The amount in cents as a [BigInt]. Throws if non-integer.
  BigInt get bigIntCents {
    if (!_cents.isInteger) {
      throw StateError('Money.bigIntCents called on non-integer value $_cents');
    }
    return _cents.toBigInt();
  }

  bool get isZero => _cents == Decimal.zero;
  bool get isNegative => _cents < Decimal.zero;
  bool get isPositive => _cents > Decimal.zero;

  // ── Arithmetic ──────────────────────────────────────────────────────────

  Money operator +(Money other) => Money._(_cents + other._cents);
  Money operator -(Money other) => Money._(_cents - other._cents);
  Money operator -() => Money._(-_cents);

  /// Scalar multiplication by an integer quantity. The most common use is
  /// `unitPrice * quantity`. Money × Money is intentionally not provided.
  Money operator *(int scalar) => Money._(_cents * Decimal.fromInt(scalar));

  /// Scalar multiplication by a [Decimal] (e.g. for fractional weights or
  /// rates). The result keeps full precision — call [round] to commit.
  Money multiplyDecimal(Decimal factor) => Money._(_cents * factor);

  /// Multiply by an exact rational quantity. Used by measured stock where
  /// quantities are stored as grams/ml/milli-metres while monetary unit rates
  /// are expressed per kg/litre/metre.
  Money multiplyRatio(int numerator, int denominator) {
    if (denominator <= 0) {
      throw ArgumentError.value(denominator, 'denominator');
    }
    final result =
        _cents * Decimal.fromInt(numerator) / Decimal.fromInt(denominator);
    return Money._(result.toDecimal(scaleOnInfinitePrecision: 12));
  }

  // ── Comparison ──────────────────────────────────────────────────────────

  bool operator <(Money other) => _cents < other._cents;
  bool operator <=(Money other) => _cents <= other._cents;
  bool operator >(Money other) => _cents > other._cents;
  bool operator >=(Money other) => _cents >= other._cents;

  @override
  int compareTo(Money other) => _cents.compareTo(other._cents);

  /// The smaller of `this` and [other].
  Money min(Money other) => this <= other ? this : other;

  /// The larger of `this` and [other].
  Money max(Money other) => this >= other ? this : other;

  /// Clamp to `>= 0`. Negative amounts become zero. Useful for guarding
  /// totals against display going negative due to rounding/subtraction.
  Money clampNonNegative() => isNegative ? Money.zero : this;

  /// Clamp into `[lower, upper]`.
  Money clamp(Money lower, Money upper) {
    if (this < lower) return lower;
    if (this > upper) return upper;
    return this;
  }

  // ── Rounding ────────────────────────────────────────────────────────────

  /// Round to a whole number of cents using [mode]. The default is
  /// [MoneyRoundingMode.halfUp] — the commercial convention used in POS
  /// and consistent with `TaxCalculationService` defaults.
  Money round([MoneyRoundingMode mode = MoneyRoundingMode.halfUp]) {
    if (_cents.isInteger) return this;
    switch (mode) {
      case MoneyRoundingMode.halfUp:
        return Money._(Decimal.fromBigInt(_cents.round().toBigInt()));
      case MoneyRoundingMode.halfEven:
        final floored = _cents.floor();
        final flooredBig = floored.toBigInt();
        final fraction = _cents - floored;
        final half = Decimal.parse('0.5');
        if (fraction == half) {
          final rounded = flooredBig.isEven
              ? flooredBig
              : flooredBig + BigInt.one;
          return Money._(Decimal.fromBigInt(rounded));
        }
        return Money._(Decimal.fromBigInt(_cents.round().toBigInt()));
      case MoneyRoundingMode.down:
        return Money._(Decimal.fromBigInt(_cents.truncate().toBigInt()));
    }
  }

  // ── Percentage ──────────────────────────────────────────────────────────

  /// Compute a percentage of this amount.
  ///
  /// [bps] is in **basis points**: `100 bps = 1 %`, `10 000 bps = 100 %`.
  /// The result is rounded to whole cents using [mode] (default
  /// [MoneyRoundingMode.halfUp]).
  ///
  /// **Contract:** the percent base is **this** [Money] value as supplied —
  /// no caller may transform the base elsewhere. This is the core fix for
  /// the "1% of net vs 1% of net+tax" class of bugs.
  Money percentage(
    int bps, {
    MoneyRoundingMode mode = MoneyRoundingMode.halfUp,
  }) {
    if (bps == 0 || isZero) return Money.zero;
    final raw = _cents * Decimal.fromInt(bps) / Decimal.fromInt(10000);
    final rawDec = raw.toDecimal(scaleOnInfinitePrecision: 12);
    return Money._(rawDec).round(mode);
  }

  // ── Allocation ──────────────────────────────────────────────────────────

  /// Distribute this amount across [weights] using the **largest-remainder
  /// method**. The returned list always satisfies:
  ///
  ///     sum(result) == this   (exactly, in cents)
  ///     length(result) == length(weights)
  ///
  /// This is the canonical safe way to prorate a discount, tax, or any
  /// other money amount across line items without losing or creating
  /// cents from rounding. Used by `InvoicePricingEngine` to distribute
  /// invoice-level discounts.
  ///
  /// Preconditions:
  /// - [weights] must be non-empty.
  /// - All weights must be non-negative.
  /// - This amount must be a whole number of cents (call [round] first).
  /// - Weights must be representable as `int`.
  ///
  /// Edge cases:
  /// - If all weights are zero, the amount is distributed equally to the
  ///   first slot (deterministic) and zero to the rest.
  /// - If `this == zero`, all results are zero.
  List<Money> allocate(List<int> weights) {
    if (weights.isEmpty) {
      throw ArgumentError('Money.allocate: weights must not be empty');
    }
    for (final w in weights) {
      if (w < 0) {
        throw ArgumentError('Money.allocate: weights must be non-negative');
      }
    }
    if (!_cents.isInteger) {
      throw StateError(
        'Money.allocate called on non-integer value $_cents — '
        'call .round() first.',
      );
    }
    final totalCents = _cents.toBigInt().toInt();
    final weightSum = weights.fold<int>(0, (a, b) => a + b);

    if (totalCents == 0) {
      return List<Money>.filled(weights.length, Money.zero);
    }

    if (weightSum == 0) {
      // Degenerate: nowhere to put the money — assign all to slot 0 to
      // preserve sum invariant deterministically.
      return List<Money>.generate(
        weights.length,
        (i) => i == 0 ? Money.fromCents(totalCents) : Money.zero,
      );
    }

    // Largest-remainder method.
    final result = List<int>.filled(weights.length, 0);
    final remainders = <int, double>{};
    int allocated = 0;
    for (int i = 0; i < weights.length; i++) {
      final exact = (totalCents * weights[i]) / weightSum;
      result[i] = exact.floor();
      remainders[i] = exact - result[i];
      allocated += result[i];
    }
    var remaining = totalCents - allocated;
    final ordered = remainders.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in ordered) {
      if (remaining <= 0) break;
      result[e.key]++;
      remaining--;
    }
    // If totalCents was negative, the loops above still produce correct
    // sign because (negative * positive)/positive distributes the negative
    // to floor(); remaining would be <= 0 and the loop would not execute.
    return result.map(Money.fromCents).toList(growable: false);
  }

  // ── Equality / hash / debug ─────────────────────────────────────────────

  @override
  bool operator ==(Object other) => other is Money && other._cents == _cents;

  @override
  int get hashCode => _cents.hashCode;

  @override
  String toString() => 'Money($_cents¢)';
}
