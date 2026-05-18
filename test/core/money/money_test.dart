// Money value-object tests.
//
// Coverage matrix:
//   • Construction & properties
//   • Arithmetic (+, -, unary -, * scalar)
//   • Comparison & ordering
//   • Clamping
//   • Rounding (halfUp, halfEven, down)
//   • Percentage (the bug-fix path)
//   • Allocation invariants (sum, length, signs)
//   • Equality, hashCode, toString
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/money/money.dart';

void main() {
  group('Money — construction & properties', () {
    test('zero / fromCents / fromDecimalCents / fromBigIntCents', () {
      expect(Money.zero.cents, 0);
      expect(Money.fromCents(123).cents, 123);
      expect(Money.fromDecimalCents(Decimal.fromInt(456)).cents, 456);
      expect(Money.fromBigIntCents(BigInt.from(789)).cents, 789);
    });

    test('isZero / isNegative / isPositive', () {
      expect(Money.zero.isZero, isTrue);
      expect(Money.fromCents(1).isPositive, isTrue);
      expect(Money.fromCents(-1).isNegative, isTrue);
    });

    test('cents getter throws on fractional value', () {
      final m = Money.fromDecimalCents(Decimal.parse('1.5'));
      expect(() => m.cents, throwsStateError);
      expect(m.decimalCents, Decimal.parse('1.5'));
    });
  });

  group('Money — arithmetic', () {
    test('+ and -', () {
      final a = Money.fromCents(100);
      final b = Money.fromCents(40);
      expect((a + b).cents, 140);
      expect((a - b).cents, 60);
      expect((-a).cents, -100);
    });

    test('* by integer scalar', () {
      expect((Money.fromCents(250) * 4).cents, 1000);
      expect((Money.fromCents(250) * 0).cents, 0);
      expect((Money.fromCents(250) * -3).cents, -750);
    });

    test('multiplyDecimal preserves precision', () {
      final m = Money.fromCents(100).multiplyDecimal(Decimal.parse('0.5'));
      expect(m.decimalCents, Decimal.parse('50.0'));
      expect(m.round().cents, 50);
    });
  });

  group('Money — comparison & clamping', () {
    test('ordering operators', () {
      final a = Money.fromCents(10);
      final b = Money.fromCents(20);
      expect(a < b, isTrue);
      expect(a <= b, isTrue);
      expect(b > a, isTrue);
      expect(b >= a, isTrue);
      expect(a.compareTo(b) < 0, isTrue);
    });

    test('min / max / clampNonNegative / clamp', () {
      final a = Money.fromCents(5);
      final b = Money.fromCents(15);
      expect(a.min(b), a);
      expect(a.max(b), b);
      expect(Money.fromCents(-3).clampNonNegative(), Money.zero);
      expect(Money.fromCents(20).clamp(a, b), b);
      expect(Money.fromCents(0).clamp(a, b), a);
      expect(Money.fromCents(10).clamp(a, b), Money.fromCents(10));
    });
  });

  group('Money — rounding modes', () {
    test('halfUp rounds 0.5 away from zero', () {
      expect(
        Money.fromDecimalCents(Decimal.parse('0.5')).round().cents,
        1,
      );
      expect(
        Money.fromDecimalCents(Decimal.parse('-0.5')).round().cents,
        -1,
      );
      expect(
        Money.fromDecimalCents(Decimal.parse('1.4')).round().cents,
        1,
      );
    });

    test('halfEven rounds 0.5 to even neighbor', () {
      expect(
        Money.fromDecimalCents(Decimal.parse('0.5'))
            .round(MoneyRoundingMode.halfEven)
            .cents,
        0,
      );
      expect(
        Money.fromDecimalCents(Decimal.parse('1.5'))
            .round(MoneyRoundingMode.halfEven)
            .cents,
        2,
      );
      expect(
        Money.fromDecimalCents(Decimal.parse('2.5'))
            .round(MoneyRoundingMode.halfEven)
            .cents,
        2,
      );
    });

    test('down truncates toward zero', () {
      expect(
        Money.fromDecimalCents(Decimal.parse('1.9'))
            .round(MoneyRoundingMode.down)
            .cents,
        1,
      );
      expect(
        Money.fromDecimalCents(Decimal.parse('-1.9'))
            .round(MoneyRoundingMode.down)
            .cents,
        -1,
      );
    });
  });

  group('Money — percentage (bug-fix path)', () {
    test('1 % of 80000¢ = 800¢ exactly', () {
      // The exact scenario from the user's bug report.
      expect(Money.fromCents(80000).percentage(100).cents, 800);
    });

    test('1 % of 0¢ = 0¢', () {
      expect(Money.fromCents(0).percentage(100).cents, 0);
    });

    test('0 % of any amount = 0¢', () {
      expect(Money.fromCents(99999).percentage(0).cents, 0);
    });

    test('halfUp vs halfEven on .5 boundary', () {
      // 50¢ × 1 % = 0.5¢ → halfUp = 1, halfEven = 0
      final m = Money.fromCents(50);
      expect(m.percentage(100).cents, 1);
      expect(m.percentage(100, mode: MoneyRoundingMode.halfEven).cents, 0);
    });

    test('large bps (>100 %) is allowed', () {
      // Caller is expected to clamp via Discount.resolve; the raw API
      // computes whatever was requested.
      expect(Money.fromCents(100).percentage(15000).cents, 150);
    });
  });

  group('Money — allocate', () {
    test('sum of allocations equals total exactly', () {
      final m = Money.fromCents(100);
      final alloc = m.allocate([1, 1, 1]);
      expect(alloc.length, 3);
      final sum = alloc.fold<int>(0, (s, x) => s + x.cents);
      expect(sum, 100);
    });

    test('allocates more to larger weights (largest remainder)', () {
      final m = Money.fromCents(10);
      final alloc = m.allocate([3, 1]);
      expect(alloc[0].cents + alloc[1].cents, 10);
      // weights 3/4 and 1/4 → exact 7.5 and 2.5 → halfUp gives 8 and 3,
      // but sum invariant means largest-remainder picks 8 + 2 or 7 + 3.
      // Either way, slot 0 gets the larger share.
      expect(alloc[0].cents > alloc[1].cents, isTrue);
    });

    test('zero total → all zero', () {
      final alloc = Money.zero.allocate([1, 2, 3]);
      expect(alloc.every((m) => m.isZero), isTrue);
    });

    test('all-zero weights → all to slot 0 (deterministic)', () {
      final alloc = Money.fromCents(5).allocate([0, 0, 0]);
      expect(alloc[0].cents, 5);
      expect(alloc[1].cents, 0);
      expect(alloc[2].cents, 0);
    });

    test('throws on empty weights', () {
      expect(() => Money.fromCents(1).allocate([]), throwsArgumentError);
    });

    test('throws on negative weight', () {
      expect(() => Money.fromCents(1).allocate([1, -1]), throwsArgumentError);
    });

    test('throws on fractional cents (must round first)', () {
      final frac = Money.fromDecimalCents(Decimal.parse('1.5'));
      expect(() => frac.allocate([1, 1]), throwsStateError);
    });

    test('property: random total + weights → sum invariant holds', () {
      // Lightweight property check (no fast_check yet — manual seed).
      final cases = <List<int>>[
        [100, 1, 2, 3],
        [1, 7, 11, 13],
        [9999, 1, 1, 1, 1, 1, 1, 1],
        [12345, 100, 200, 300, 400, 500],
        [1, 1, 0, 0, 0, 0],
        [777, 0, 0, 5],
      ];
      for (final c in cases) {
        final total = c[0];
        final weights = c.sublist(1);
        final alloc = Money.fromCents(total).allocate(weights);
        final sum = alloc.fold<int>(0, (s, x) => s + x.cents);
        expect(sum, total, reason: 'case $c');
        expect(alloc.length, weights.length);
      }
    });
  });

  group('Money — equality & toString', () {
    test('== and hashCode', () {
      expect(Money.fromCents(42), Money.fromCents(42));
      expect(Money.fromCents(42).hashCode, Money.fromCents(42).hashCode);
      expect(Money.fromCents(42), isNot(Money.fromCents(43)));
    });

    test('toString includes value', () {
      expect(Money.fromCents(123).toString(), contains('123'));
    });
  });
}
