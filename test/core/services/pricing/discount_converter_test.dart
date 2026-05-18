import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/pricing/discount_converter.dart';

/// Phase 3.5.5 — locks the discount conversion invariants.
void main() {
  const c = DiscountConverter();
  Decimal d(String s) => Decimal.parse(s);

  group('fixedFromPercent', () {
    test('10% of 10000 cents → 1000', () {
      expect(c.fixedFromPercent(subtotalCents: 10000, percent: d('10')), 1000);
    });
    test('0% → 0', () {
      expect(c.fixedFromPercent(subtotalCents: 10000, percent: Decimal.zero), 0);
    });
    test('100% → full subtotal', () {
      expect(c.fixedFromPercent(subtotalCents: 10000, percent: d('100')), 10000);
    });
    test('> 100% clamps to subtotal', () {
      expect(c.fixedFromPercent(subtotalCents: 10000, percent: d('150')), 10000);
    });
    test('negative percent clamps to 0', () {
      expect(c.fixedFromPercent(subtotalCents: 10000, percent: d('-5')), 0);
    });
    test('subtotal 0 → 0 (no division by zero)', () {
      expect(c.fixedFromPercent(subtotalCents: 0, percent: d('10')), 0);
    });
    test('fractional percent rounds half-away-from-zero', () {
      // 33.33% of 10000 = 3333.0 → 3333
      expect(c.fixedFromPercent(subtotalCents: 10000, percent: d('33.33')), 3333);
    });
    test('percent is never negative output', () {
      expect(c.fixedFromPercent(subtotalCents: 100, percent: d('0.001')), 0);
    });
  });

  group('percentFromFixed', () {
    test('1000 of 10000 → 10.00', () {
      expect(c.percentFromFixed(subtotalCents: 10000, fixedCents: 1000), d('10'));
    });
    test('subtotal 0 → 0 (no division by zero)', () {
      expect(c.percentFromFixed(subtotalCents: 0, fixedCents: 100), Decimal.zero);
    });
    test('fixed 0 → 0', () {
      expect(c.percentFromFixed(subtotalCents: 10000, fixedCents: 0), Decimal.zero);
    });
    test('fixed > subtotal clamps to 100%', () {
      expect(c.percentFromFixed(subtotalCents: 10000, fixedCents: 15000), d('100'));
    });
    test('rounds to 2 decimals by default', () {
      // 3333 / 10000 = 33.33%
      expect(c.percentFromFixed(subtotalCents: 10000, fixedCents: 3333), d('33.33'));
    });
    test('custom decimalDigits honoured', () {
      // 1 / 3 = 33.3333...; ask for 4 digits → 33.3333
      expect(
        c.percentFromFixed(subtotalCents: 30000, fixedCents: 10000, decimalDigits: 4),
        d('33.3333'),
      );
    });
  });

  group('round-trip invariants', () {
    test('percent → fixed → percent is stable for exact values', () {
      final pct = d('25');
      final fixed = c.fixedFromPercent(subtotalCents: 20000, percent: pct);
      expect(fixed, 5000);
      expect(c.percentFromFixed(subtotalCents: 20000, fixedCents: fixed), pct);
    });
    test('fixed → percent → fixed is stable when percent is representable', () {
      const fixed = 2500;
      final pct = c.percentFromFixed(subtotalCents: 10000, fixedCents: fixed);
      expect(c.fixedFromPercent(subtotalCents: 10000, percent: pct), fixed);
    });
  });
}
