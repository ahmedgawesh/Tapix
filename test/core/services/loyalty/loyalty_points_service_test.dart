// ════════════════════════════════════════════════════════════════════════════
// LoyaltyPointsService — pure-formula regression suite.
// ════════════════════════════════════════════════════════════════════════════
//
// Phase 6 of the scattered-calculation-logic migration. These tests pin
// down the single award formula that both the live award path and the
// UI preview path now share. Any drift between the two would manifest
// as a `compute` vs `previewSync` divergence.
//
// All tests are PURE — no Drift DB, no DI. The orchestrators
// (`awardForSale`, `reverseForReturn`) wrap I/O around the same
// formula, so locking the formula here is sufficient to protect every
// caller.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';

void main() {
  test('minor-unit factors preserve whole-currency loyalty accrual', () {
    for (final factor in [1, 100, 1000]) {
      expect(
        LoyaltyPointsService.compute(
          LoyaltyAwardInput(
            amountCents: 20 * factor,
            pointsPerCurrencyUnit: 1,
            minSpendForPoints: 0,
            minorUnitFactor: factor,
          ),
        ).totalPoints,
        20,
      );
    }
  });

  group('LoyaltyPointsService.compute — gating conditions', () {
    test('returns zero when amountCents is below min-spend threshold', () {
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 999,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 1000,
        ),
      );
      expect(r.totalPoints, 0);
      expect(r.basePoints, 0);
    });

    test('returns zero when amountCents is zero or negative', () {
      expect(
        LoyaltyPointsService.compute(
          const LoyaltyAwardInput(
            amountCents: 0,
            pointsPerCurrencyUnit: 1,
            minSpendForPoints: 0,
          ),
        ).totalPoints,
        0,
      );
      expect(
        LoyaltyPointsService.compute(
          const LoyaltyAwardInput(
            amountCents: -500,
            pointsPerCurrencyUnit: 1,
            minSpendForPoints: 0,
          ),
        ).totalPoints,
        0,
      );
    });

    test('returns zero when pointsPerCurrencyUnit is zero', () {
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 100000,
          pointsPerCurrencyUnit: 0,
          minSpendForPoints: 0,
        ),
      );
      expect(r.totalPoints, 0);
    });
  });

  group('LoyaltyPointsService.compute — base points', () {
    test('base = (amountCents * pointsPerCurrencyUnit) ~/ 100', () {
      // $10.00 at 1 point per currency unit = 10 base points.
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 1000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
        ),
      );
      expect(r.basePoints, 10);
      expect(r.totalPoints, 10);
    });

    test('pointsPerCurrencyUnit scales linearly', () {
      // $10.00 at 5 points per currency unit = 50 base points.
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 1000,
          pointsPerCurrencyUnit: 5,
          minSpendForPoints: 0,
        ),
      );
      expect(r.basePoints, 50);
    });

    test('floor division on sub-unit amounts (legacy semantics)', () {
      // $0.99 → (99 * 1) ~/ 100 = 0 → no points.
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 99,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
        ),
      );
      expect(r.basePoints, 0);
      expect(r.totalPoints, 0);
    });
  });

  group('LoyaltyPointsService.compute — tier multiplier', () {
    test('multiplier 1.0 is a no-op', () {
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 5000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: 1.0,
        ),
      );
      expect(r.basePoints, 50);
      expect(r.tierAdjustedPoints, 50);
      expect(r.totalPoints, 50);
    });

    test('multiplier 2.0 doubles base', () {
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 5000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: 2.0,
        ),
      );
      expect(r.tierAdjustedPoints, 100);
      expect(r.totalPoints, 100);
    });

    test('multiplier 1.5 with even base = exact integer', () {
      // 100 * 1.5 = 150 exactly.
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 10000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: 1.5,
        ),
      );
      expect(r.tierAdjustedPoints, 150);
    });

    test('multiplier 1.5 with odd base rounds half-away-from-zero', () {
      // 15 * 1.5 = 22.5 → rounds to 23 with half-away-from-zero
      // (matches the legacy `double.round()` semantics).
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 1500,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: 1.5,
        ),
      );
      expect(r.basePoints, 15);
      expect(r.tierAdjustedPoints, 23);
    });
  });

  group('LoyaltyPointsService.compute — bonus percentage', () {
    test('bonusPercent 0 is a no-op', () {
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 10000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: 1.0,
          bonusPercent: 0.0,
        ),
      );
      expect(r.bonusPoints, 0);
      expect(r.totalPoints, 100);
    });

    test('bonusPercent 10 adds 10% of tier-adjusted', () {
      // base 100 → tier 100 → bonus 10 → total 110.
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 10000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          bonusPercent: 10.0,
        ),
      );
      expect(r.bonusPoints, 10);
      expect(r.totalPoints, 110);
    });

    test('bonus is applied AFTER tier multiplier (compounding)', () {
      // base 100 → tier×2 = 200 → bonus 10% of 200 = 20 → total 220.
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 10000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: 2.0,
          bonusPercent: 10.0,
        ),
      );
      expect(r.tierAdjustedPoints, 200);
      expect(r.bonusPoints, 20);
      expect(r.totalPoints, 220);
    });
  });

  group('LoyaltyPointsService.compute — birthday bonuses', () {
    test('applyBirthdayBonus=false ignores both flat and percent bonuses', () {
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 10000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          applyBirthdayBonus: false,
          birthdayBonusPoints: 50,
          birthdayDiscountPercent: 20.0,
        ),
      );
      expect(r.birthdayFlatBonus, 0);
      expect(r.birthdayPercentBonus, 0);
      expect(r.totalPoints, 100);
    });

    test('flat birthday bonus is added on top of tier+bonus', () {
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 10000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          applyBirthdayBonus: true,
          birthdayBonusPoints: 50,
        ),
      );
      expect(r.birthdayFlatBonus, 50);
      expect(r.totalPoints, 150);
    });

    test('birthday percent compounds AFTER the flat bonus', () {
      // base 100, flat +50 → 150, then +20% = 30 → 180.
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 10000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          applyBirthdayBonus: true,
          birthdayBonusPoints: 50,
          birthdayDiscountPercent: 20.0,
        ),
      );
      expect(r.birthdayFlatBonus, 50);
      expect(r.birthdayPercentBonus, 30);
      expect(r.totalPoints, 180);
    });

    test('full stack: base × tier × bonus + flat × birthdayPct', () {
      // base 100 → tier×1.5 = 150 → bonus 10% (15) → 165 →
      // birthday flat +50 = 215 → birthday 10% (21.5 → 22) = 237.
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 10000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: 1.5,
          bonusPercent: 10.0,
          applyBirthdayBonus: true,
          birthdayBonusPoints: 50,
          birthdayDiscountPercent: 10.0,
        ),
      );
      expect(r.basePoints, 100);
      expect(r.tierAdjustedPoints, 150);
      expect(r.bonusPoints, 15);
      expect(r.birthdayFlatBonus, 50);
      expect(r.birthdayPercentBonus, 22);
      expect(r.totalPoints, 237);
    });
  });

  group('LoyaltyPointsService.compute — IEEE-754 hardening', () {
    test('multiplier 1.1 × base 15 yields exact 17 (no FP drift)', () {
      // In IEEE-754: (15 * 1.1) = 16.500000000000004, which `double.round()`
      // turns into 17. Decimal arithmetic computes 16.5 exactly and rounds
      // half-away-from-zero — also 17. Both paths agree on this case but
      // Decimal is correct for the right reason.
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 1500,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: 1.1,
        ),
      );
      expect(r.basePoints, 15);
      expect(r.tierAdjustedPoints, 17);
    });

    test('multiplier 0.0 yields zero (short-circuit)', () {
      final r = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: 10000,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: 0.0,
        ),
      );
      // basePoints survives (100) but multiplier=0 zeros the tier-adjusted
      // layer; subsequent bonus/birthday layers compound on 0 → total 0.
      expect(r.basePoints, 100);
      expect(r.tierAdjustedPoints, 0);
      expect(r.totalPoints, 0);
    });
  });

  group('LoyaltyPointsService.previewSync — parity with award path', () {
    test('default preview mirrors compute with pointsPerCurrencyUnit=1', () {
      const amount = 5000;
      const multiplier = 1.5;
      final previewPoints = LoyaltyPointsService.previewSync(
        amountCents: amount,
        multiplier: multiplier,
      );
      final computed = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: amount,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 0,
          multiplier: multiplier,
        ),
      ).totalPoints;
      expect(previewPoints, computed);
    });

    test('settings-aware preview mirrors compute byte-for-byte', () {
      const amount = 12345;
      const ppu = 3;
      const minSpend = 500;
      const multiplier = 1.25;
      final previewPoints = LoyaltyPointsService.previewSync(
        amountCents: amount,
        multiplier: multiplier,
        pointsPerCurrencyUnit: ppu,
        minSpendForPoints: minSpend,
      );
      final computed = LoyaltyPointsService.compute(
        const LoyaltyAwardInput(
          amountCents: amount,
          pointsPerCurrencyUnit: ppu,
          minSpendForPoints: minSpend,
          multiplier: multiplier,
        ),
      ).totalPoints;
      expect(previewPoints, computed);
    });

    test('preview respects min-spend gate', () {
      expect(
        LoyaltyPointsService.previewSync(
          amountCents: 100,
          multiplier: 1.0,
          pointsPerCurrencyUnit: 1,
          minSpendForPoints: 1000,
        ),
        0,
      );
    });
  });
}
