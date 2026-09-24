import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/employees/domain/services/payroll_calculation_service.dart';

/// Factory that builds a minimal [Employee] with overridable fields. Keeps
/// tests concise — only the fields the payroll logic inspects are surfaced.
Employee buildEmployee({
  int? salaryCents,
  int workingDaysPerPeriod = 26,
  int workingHoursPerDay = 8,
  int absenceDeductionRateBps = 10000,
  int lateDeductionRateBps = 2500,
  String overtimeCalcType = 'hourly_rate',
  int overtimeRateBps = 15000,
  int? salesTargetCents,
  int? targetBonusCents,
  String targetPeriod = 'monthly',
}) {
  final now = DateTime(2026, 1, 1);
  return Employee(
    id: 1,
    name: 'Test Employee',
    salaryCents: salaryCents == null ? null : Decimal.fromInt(salaryCents),
    defaultCommissionRateBps: 0,
    commissionType: 'percentage',
    salesTargetCents: salesTargetCents == null
        ? null
        : Decimal.fromInt(salesTargetCents),
    targetBonusCents: targetBonusCents == null
        ? null
        : Decimal.fromInt(targetBonusCents),
    targetPeriod: targetPeriod,
    payPeriodType: 'monthly',
    workingDaysPerPeriod: workingDaysPerPeriod,
    workingHoursPerDay: workingHoursPerDay,
    absenceDeductionRateBps: absenceDeductionRateBps,
    lateDeductionRateBps: lateDeductionRateBps,
    overtimeCalcType: overtimeCalcType,
    overtimeRateBps: overtimeRateBps,
    currencyId: 1,
    isActive: true,
    weeklyOffDays: '[5,6]',
    annualLeaveDays: 21,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // calculateOvertimeCents
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateOvertimeCents', () {
    test('hourly_rate policy with 150% multiplier (FLSA default)', () {
      // 2,600 SAR monthly / 26 days = 100/day. /8h = 12.50/hour.
      // 2 overtime hours × 12.50 × 1.5 = 37.50 → 3,750 cents.
      final cents = PayrollCalculationService.calculateOvertimeCents(
        overtimeMinutes: 120,
        salaryCents: 260000,
        workingDaysPerPeriod: 26,
        workingHoursPerDay: 8,
        overtimeCalcType: 'hourly_rate',
        overtimeRateBps: 15000,
      );
      expect(cents, 3750);
    });

    test('hourly_rate at 200% multiplier (holiday rate)', () {
      final cents = PayrollCalculationService.calculateOvertimeCents(
        overtimeMinutes: 60,
        salaryCents: 260000,
        workingDaysPerPeriod: 26,
        workingHoursPerDay: 8,
        overtimeCalcType: 'hourly_rate',
        overtimeRateBps: 20000,
      );
      // 1h × 12.50 × 2.0 = 25.00 → 2,500 cents.
      expect(cents, 2500);
    });

    test('percentage policy computes % of daily rate per hour', () {
      // 2,600 SAR / 26 days = 100/day. 20% of 100 = 20/hour.
      // 3 overtime hours × 20 = 60 → 6,000 cents.
      final cents = PayrollCalculationService.calculateOvertimeCents(
        overtimeMinutes: 180,
        salaryCents: 260000,
        workingDaysPerPeriod: 26,
        workingHoursPerDay: 8,
        overtimeCalcType: 'percentage',
        overtimeRateBps: 2000,
      );
      expect(cents, 6000);
    });

    test('fixed policy pays the configured cents per overtime hour', () {
      // 2 hours × 500 cents/hour = 1,000 cents.
      final cents = PayrollCalculationService.calculateOvertimeCents(
        overtimeMinutes: 120,
        salaryCents: 260000,
        workingDaysPerPeriod: 26,
        workingHoursPerDay: 8,
        overtimeCalcType: 'fixed',
        overtimeRateBps: 500,
      );
      expect(cents, 1000);
    });

    test('returns 0 when overtime minutes or salary is non-positive', () {
      expect(
        PayrollCalculationService.calculateOvertimeCents(
          overtimeMinutes: 0,
          salaryCents: 260000,
          workingDaysPerPeriod: 26,
          workingHoursPerDay: 8,
          overtimeCalcType: 'hourly_rate',
          overtimeRateBps: 15000,
        ),
        0,
      );
      expect(
        PayrollCalculationService.calculateOvertimeCents(
          overtimeMinutes: 60,
          salaryCents: 0,
          workingDaysPerPeriod: 26,
          workingHoursPerDay: 8,
          overtimeCalcType: 'hourly_rate',
          overtimeRateBps: 15000,
        ),
        0,
      );
    });

    test('partial-hour overtime rounds correctly (30 min at 150%)', () {
      // 0.5h × 12.50 × 1.5 = 9.375 → rounds to 938 cents.
      final cents = PayrollCalculationService.calculateOvertimeCents(
        overtimeMinutes: 30,
        salaryCents: 260000,
        workingDaysPerPeriod: 26,
        workingHoursPerDay: 8,
        overtimeCalcType: 'hourly_rate',
        overtimeRateBps: 15000,
      );
      expect(cents, 938);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // targetPeriodRange
  // ═══════════════════════════════════════════════════════════════════════════

  group('targetPeriodRange', () {
    test('monthly target: any month is a closing month', () {
      final r = PayrollCalculationService.targetPeriodRange(
        targetPeriod: 'monthly',
        year: 2026,
        month: 5,
      );
      expect(r.start, DateTime(2026, 5, 1));
      expect(r.end, DateTime(2026, 5, 31, 23, 59, 59));
      expect(r.isClosingMonth, true);
    });

    test('quarterly target: Q1 closing is March', () {
      final jan = PayrollCalculationService.targetPeriodRange(
        targetPeriod: 'quarterly',
        year: 2026,
        month: 1,
      );
      final feb = PayrollCalculationService.targetPeriodRange(
        targetPeriod: 'quarterly',
        year: 2026,
        month: 2,
      );
      final mar = PayrollCalculationService.targetPeriodRange(
        targetPeriod: 'quarterly',
        year: 2026,
        month: 3,
      );
      expect(jan.start, DateTime(2026, 1, 1));
      expect(jan.end, DateTime(2026, 3, 31, 23, 59, 59));
      expect(jan.isClosingMonth, false);
      expect(feb.isClosingMonth, false);
      expect(mar.isClosingMonth, true);
    });

    test('quarterly target: Q4 spans Oct–Dec with Dec as closing', () {
      final dec = PayrollCalculationService.targetPeriodRange(
        targetPeriod: 'quarterly',
        year: 2026,
        month: 12,
      );
      expect(dec.start, DateTime(2026, 10, 1));
      expect(dec.end, DateTime(2026, 12, 31, 23, 59, 59));
      expect(dec.isClosingMonth, true);
    });

    test('yearly target: only December is a closing month', () {
      for (var m = 1; m <= 11; m++) {
        final r = PayrollCalculationService.targetPeriodRange(
          targetPeriod: 'yearly',
          year: 2026,
          month: m,
        );
        expect(r.isClosingMonth, false, reason: 'month $m');
      }
      final dec = PayrollCalculationService.targetPeriodRange(
        targetPeriod: 'yearly',
        year: 2026,
        month: 12,
      );
      expect(dec.isClosingMonth, true);
      expect(dec.start, DateTime(2026, 1, 1));
      expect(dec.end, DateTime(2026, 12, 31, 23, 59, 59));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // checkSalesTargetBonus
  // ═══════════════════════════════════════════════════════════════════════════

  group('checkSalesTargetBonus', () {
    test('monthly: bonus paid when target achieved', () {
      final emp = buildEmployee(
        salesTargetCents: 100000,
        targetBonusCents: 5000,
        targetPeriod: 'monthly',
      );
      final r = PayrollCalculationService.checkSalesTargetBonus(
        employee: emp,
        actualSalesCents: 120000,
        periodYear: 2026,
        periodMonth: 3,
      );
      expect(r.achieved, true);
      expect(r.targetBonusCents, 5000);
    });

    test('monthly: no bonus when target missed', () {
      final emp = buildEmployee(
        salesTargetCents: 100000,
        targetBonusCents: 5000,
        targetPeriod: 'monthly',
      );
      final r = PayrollCalculationService.checkSalesTargetBonus(
        employee: emp,
        actualSalesCents: 50000,
        periodYear: 2026,
        periodMonth: 3,
      );
      expect(r.achieved, false);
      expect(r.targetBonusCents, 0);
    });

    test(
      'quarterly: target achieved in Feb yields no payout — must wait until March',
      () {
        final emp = buildEmployee(
          salesTargetCents: 100000,
          targetBonusCents: 5000,
          targetPeriod: 'quarterly',
        );
        // Feb: target met but not payout month.
        final feb = PayrollCalculationService.checkSalesTargetBonus(
          employee: emp,
          actualSalesCents: 120000,
          periodYear: 2026,
          periodMonth: 2,
        );
        expect(feb.achieved, true);
        expect(
          feb.targetBonusCents,
          0,
          reason: 'Bonus must accrue until quarter-close',
        );
        expect(feb.isPayoutMonth, false);

        // March: payout month — bonus released.
        final mar = PayrollCalculationService.checkSalesTargetBonus(
          employee: emp,
          actualSalesCents: 120000,
          periodYear: 2026,
          periodMonth: 3,
        );
        expect(mar.achieved, true);
        expect(mar.targetBonusCents, 5000);
        expect(mar.isPayoutMonth, true);
      },
    );

    test(
      'yearly: bonus withheld until December regardless of early achievement',
      () {
        final emp = buildEmployee(
          salesTargetCents: 1000000,
          targetBonusCents: 12000,
          targetPeriod: 'yearly',
        );
        final jun = PayrollCalculationService.checkSalesTargetBonus(
          employee: emp,
          actualSalesCents: 1500000,
          periodYear: 2026,
          periodMonth: 6,
        );
        expect(jun.targetBonusCents, 0);
        final dec = PayrollCalculationService.checkSalesTargetBonus(
          employee: emp,
          actualSalesCents: 1500000,
          periodYear: 2026,
          periodMonth: 12,
        );
        expect(dec.targetBonusCents, 12000);
      },
    );

    test('returns zero bonus when target or bonus not configured', () {
      final empNoTarget = buildEmployee(
        salesTargetCents: null,
        targetBonusCents: 5000,
        targetPeriod: 'monthly',
      );
      final r = PayrollCalculationService.checkSalesTargetBonus(
        employee: empNoTarget,
        actualSalesCents: 999999,
        periodYear: 2026,
        periodMonth: 3,
      );
      expect(r.achieved, false);
      expect(r.targetBonusCents, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // calculate (payroll)
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculate', () {
    test('full attendance: basic = earned basic, no deductions', () {
      final emp = buildEmployee(salaryCents: 260000); // 2,600 SAR
      final calc = PayrollCalculationService.calculate(
        employee: emp,
        attendanceCounts: {
          'present': 26,
          'late': 0,
          'absent': 0,
          'leave': 0,
          'early_departure': 0,
        },
      );
      expect(calc.basicSalaryCents, 260000);
      expect(calc.earnedBasicCents, 260000);
      expect(calc.absenceDeductionCents, 0);
      expect(calc.lateDeductionCents, 0);
      expect(calc.netPayCents, 260000);
    });

    test('absent days deduct daily rate at 100% (default policy)', () {
      final emp = buildEmployee(salaryCents: 260000);
      final calc = PayrollCalculationService.calculate(
        employee: emp,
        attendanceCounts: {
          'present': 20,
          'late': 0,
          'absent': 6,
          'leave': 0,
          'early_departure': 0,
        },
      );
      // 6 days × 100 SAR = 600 SAR absent.
      expect(calc.absenceDeductionCents, 60000);
      expect(calc.earnedBasicCents, 200000);
      expect(calc.netPayCents, 200000);
    });

    test('50% absence policy only deducts half the daily rate', () {
      final emp = buildEmployee(
        salaryCents: 260000,
        absenceDeductionRateBps: 5000, // 50%
      );
      final calc = PayrollCalculationService.calculate(
        employee: emp,
        attendanceCounts: {
          'present': 20,
          'late': 0,
          'absent': 6,
          'leave': 0,
          'early_departure': 0,
        },
      );
      // 6 × 100 × 0.5 = 300 SAR absence deduction.
      expect(calc.absenceDeductionCents, 30000);
      expect(calc.earnedBasicCents, 230000);
      expect(calc.netPayCents, 230000);
    });

    test('unrecorded days (partial attendance) still prorate salary', () {
      // Only 10 days recorded as present → remaining 16 count as absent.
      final emp = buildEmployee(salaryCents: 260000);
      final calc = PayrollCalculationService.calculate(
        employee: emp,
        attendanceCounts: {
          'present': 10,
          'late': 0,
          'absent': 0,
          'leave': 0,
          'early_departure': 0,
        },
      );
      expect(calc.absenceDeductionCents, 160000);
      expect(calc.earnedBasicCents, 100000);
    });

    test('late days deduct at the configured rate', () {
      // lateRate 25% × daily 100 × 3 late days = 75 SAR.
      final emp = buildEmployee(salaryCents: 260000);
      final calc = PayrollCalculationService.calculate(
        employee: emp,
        attendanceCounts: {
          'present': 23,
          'late': 3,
          'absent': 0,
          'leave': 0,
          'early_departure': 0,
        },
      );
      expect(calc.lateDeductionCents, 7500);
      expect(
        calc.absenceDeductionCents,
        0,
        reason: 'Late days count as paid days',
      );
      expect(calc.netPayCents, 260000 - 7500);
    });

    test('leave and early_departure count as paid days', () {
      final emp = buildEmployee(salaryCents: 260000);
      final calc = PayrollCalculationService.calculate(
        employee: emp,
        attendanceCounts: {
          'present': 20,
          'late': 0,
          'absent': 0,
          'leave': 4,
          'early_departure': 2,
        },
      );
      expect(calc.absenceDeductionCents, 0);
      // Early-departure deducts at the late rate (25% × daily × 2).
      expect(calc.earlyDepartureDeductionCents, 5000);
      expect(calc.earnedBasicCents, 260000);
      expect(calc.netPayCents, 260000 - 5000);
    });

    test(
      'gross = basic + commission + bonus + overtime; net subtracts dedns',
      () {
        final emp = buildEmployee(salaryCents: 260000);
        final calc = PayrollCalculationService.calculate(
          employee: emp,
          attendanceCounts: {
            'present': 25,
            'late': 1,
            'absent': 0,
            'leave': 0,
            'early_departure': 0,
          },
          commissionCents: 20000,
          bonusCents: 10000,
          overtimeCents: 5000,
        );
        expect(calc.grossPayCents, 260000 + 20000 + 10000 + 5000);
        // Late 1 day × 100 × 25% = 25 SAR deduction.
        expect(calc.lateDeductionCents, 2500);
        expect(calc.totalDeductionCents, 2500);
        expect(calc.netPayCents, calc.grossPayCents - 2500);
      },
    );

    test('zero salary yields zero payroll — graceful degradation', () {
      final emp = buildEmployee(salaryCents: 0);
      final calc = PayrollCalculationService.calculate(
        employee: emp,
        attendanceCounts: {
          'present': 26,
          'late': 0,
          'absent': 0,
          'leave': 0,
          'early_departure': 0,
        },
      );
      expect(calc.basicSalaryCents, 0);
      expect(calc.earnedBasicCents, 0);
      expect(calc.netPayCents, 0);
    });

    test('null salary is treated as zero', () {
      final emp = buildEmployee(salaryCents: null);
      final calc = PayrollCalculationService.calculate(
        employee: emp,
        attendanceCounts: {
          'present': 26,
          'late': 0,
          'absent': 0,
          'leave': 0,
          'early_departure': 0,
        },
      );
      expect(calc.basicSalaryCents, 0);
      expect(calc.netPayCents, 0);
    });
  });
}
