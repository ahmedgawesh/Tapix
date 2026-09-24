import '../../../../core/database/app_database.dart';

/// Result of payroll calculation with full breakdown.
///
/// Follows international payslip convention (SAP / QuickBooks / ADP):
/// - [basicSalaryCents]: the contractual basic (full salary).
/// - [earnedBasicCents]: the portion actually earned after absence proration
///   using the configured `absenceDeductionRateBps` (100% by default).
/// - [absenceDeductionCents] = basicSalaryCents - earnedBasicCents.
class PayrollCalculation {
  final int basicSalaryCents;
  final int earnedBasicCents;
  final int commissionCents;
  final int bonusCents;
  final int overtimeCents;
  final int absenceDeductionCents;
  final int lateDeductionCents;
  final int earlyDepartureDeductionCents;
  final int totalDeductionCents;
  final int grossPayCents;
  final int netPayCents;

  // Attendance data used in calculation
  final int workingDays;
  final int presentDays;
  final int lateDays;
  final int absentDays;
  final int leaveDays;
  final int earlyDepartureDays;
  final int dailyRateCents;

  const PayrollCalculation({
    required this.basicSalaryCents,
    required this.earnedBasicCents,
    required this.commissionCents,
    required this.bonusCents,
    required this.overtimeCents,
    required this.absenceDeductionCents,
    required this.lateDeductionCents,
    required this.earlyDepartureDeductionCents,
    required this.totalDeductionCents,
    required this.grossPayCents,
    required this.netPayCents,
    required this.workingDays,
    required this.presentDays,
    required this.lateDays,
    required this.absentDays,
    required this.leaveDays,
    required this.earlyDepartureDays,
    required this.dailyRateCents,
  });
}

/// Result of sales target bonus check.
///
/// `achieved` reflects whether actual sales met the target, independent of
/// payout timing. `targetBonusCents` is the amount actually payable in the
/// current payroll period — this is 0 until the target period closes, to
/// prevent paying the same bonus every month within a quarterly/yearly window.
class SalesTargetBonusResult {
  final int salesTargetCents;
  final int actualSalesCents;
  final int targetBonusCents;
  final bool achieved;

  /// True when the payroll period being settled is the closing month of the
  /// employee's target window (monthly: always; quarterly: Mar/Jun/Sep/Dec;
  /// yearly: Dec). The bonus is only payable in this month.
  final bool isPayoutMonth;

  const SalesTargetBonusResult({
    required this.salesTargetCents,
    required this.actualSalesCents,
    required this.targetBonusCents,
    required this.achieved,
    this.isPayoutMonth = true,
  });
}

/// Date range + closing-month flag for an employee's target window.
class TargetPeriodRange {
  final DateTime start;
  final DateTime end;
  final bool isClosingMonth;

  const TargetPeriodRange({
    required this.start,
    required this.end,
    required this.isClosingMonth,
  });
}

/// Service that calculates payroll based on employee config and attendance.
///
/// **Calculation logic (aligned with international ERP standards — SAP,
/// QuickBooks, ADP, FLSA):**
/// - Daily rate            = basic salary / working days per period
/// - Hourly rate           = daily rate / working hours per day
/// - Absent days           = working days − paid days (present + late + leave
///                           + early_departure are all considered paid days)
/// - Absence deduction     = absent days × daily rate × (absenceRateBps/10000)
/// - Late deduction        = late days × daily rate × (lateRateBps / 10000)
/// - Early dep. deduction  = early dep. days × daily rate × (lateRateBps / 10000)
/// - Overtime (see [calculateOvertimeCents]):
///     * hourly_rate : hours × hourlyRate × (rateBps / 10000)   (e.g. 1.5×)
///     * percentage  : hours × dailyRate  × (rateBps / 10000)
///     * fixed       : hours × rateCents  (rateBps stored as cents/hour)
/// - Gross pay  = basic salary + commission + bonus + overtime
/// - Net pay    = gross pay − (absence + late + early_departure) deductions
class PayrollCalculationService {
  const PayrollCalculationService._();

  /// Compute overtime pay based on the employee's overtime policy.
  ///
  /// Interprets `overtimeRateBps`:
  /// - `hourly_rate`: multiplier in bps (15000 = 150%). Follows FLSA § 207
  ///   convention where overtime = regular rate × 1.5.
  /// - `percentage` : % of daily rate per overtime hour (2000 = 20%).
  /// - `fixed`      : fixed amount per overtime hour, stored in cents.
  static int calculateOvertimeCents({
    required int overtimeMinutes,
    required int salaryCents,
    required int workingDaysPerPeriod,
    required int workingHoursPerDay,
    required String overtimeCalcType,
    required int overtimeRateBps,
  }) {
    if (overtimeMinutes <= 0 || salaryCents <= 0) return 0;

    final dailyRateCents = workingDaysPerPeriod > 0
        ? salaryCents ~/ workingDaysPerPeriod
        : 0;
    final hourlyRateCents = workingHoursPerDay > 0
        ? dailyRateCents ~/ workingHoursPerDay
        : 0;
    final overtimeHours = overtimeMinutes / 60.0;

    switch (overtimeCalcType) {
      case 'percentage':
        return (overtimeHours * dailyRateCents * overtimeRateBps / 10000)
            .round();
      case 'fixed':
        // overtimeRateBps is the fixed amount in cents per overtime hour.
        return (overtimeHours * overtimeRateBps).round();
      case 'hourly_rate':
      default:
        return (overtimeHours * hourlyRateCents * overtimeRateBps / 10000)
            .round();
    }
  }

  /// Compute the date range of an employee's target window that contains the
  /// given payroll period (identified by [year] + [month]).
  ///
  /// - `monthly`   : the month itself (always a closing month).
  /// - `quarterly` : the calendar quarter the month belongs to; the closing
  ///                 month is Mar / Jun / Sep / Dec.
  /// - `yearly`    : the calendar year; the closing month is December.
  static TargetPeriodRange targetPeriodRange({
    required String targetPeriod,
    required int year,
    required int month,
  }) {
    if (targetPeriod == 'quarterly') {
      final quarterIdx = (month - 1) ~/ 3;
      final startMonth = quarterIdx * 3 + 1;
      final endMonth = quarterIdx * 3 + 3;
      return TargetPeriodRange(
        start: DateTime(year, startMonth, 1),
        end: DateTime(year, endMonth + 1, 0, 23, 59, 59),
        isClosingMonth: month == endMonth,
      );
    }
    if (targetPeriod == 'yearly') {
      return TargetPeriodRange(
        start: DateTime(year, 1, 1),
        end: DateTime(year, 12, 31, 23, 59, 59),
        isClosingMonth: month == 12,
      );
    }
    // monthly (default)
    return TargetPeriodRange(
      start: DateTime(year, month, 1),
      end: DateTime(year, month + 1, 0, 23, 59, 59),
      isClosingMonth: true,
    );
  }

  /// Check if an employee achieved their sales target and return the bonus.
  ///
  /// [actualSalesCents] MUST be the net sales aggregated over the employee's
  /// target window (monthly/quarterly/yearly), not just the current month —
  /// use [targetPeriodRange] to determine the correct date range.
  ///
  /// Bonuses are only **payable** in the closing month of the target window
  /// (accrual-at-period-close, matching SAP SuccessFactors and Salesforce
  /// Commission defaults). This prevents paying the same quarterly/yearly
  /// bonus multiple times across the months it spans.
  static SalesTargetBonusResult checkSalesTargetBonus({
    required Employee employee,
    required int actualSalesCents,
    required int periodYear,
    required int periodMonth,
  }) {
    final targetCents = employee.salesTargetCents?.toBigInt().toInt() ?? 0;
    final bonusCents = employee.targetBonusCents?.toBigInt().toInt() ?? 0;
    final range = targetPeriodRange(
      targetPeriod: employee.targetPeriod,
      year: periodYear,
      month: periodMonth,
    );

    if (targetCents <= 0 || bonusCents <= 0) {
      return SalesTargetBonusResult(
        salesTargetCents: targetCents,
        actualSalesCents: actualSalesCents,
        targetBonusCents: 0,
        achieved: false,
        isPayoutMonth: range.isClosingMonth,
      );
    }

    final achieved = actualSalesCents >= targetCents;
    // Only pay in the closing month — prevents duplicate payouts across the
    // months spanned by quarterly/yearly target windows.
    final payable = achieved && range.isClosingMonth;
    return SalesTargetBonusResult(
      salesTargetCents: targetCents,
      actualSalesCents: actualSalesCents,
      targetBonusCents: payable ? bonusCents : 0,
      achieved: achieved,
      isPayoutMonth: range.isClosingMonth,
    );
  }

  static PayrollCalculation calculate({
    required Employee employee,
    required Map<String, int> attendanceCounts,
    int commissionCents = 0,
    int bonusCents = 0,
    int overtimeCents = 0,
  }) {
    final fullSalary = employee.salaryCents?.toBigInt().toInt() ?? 0;
    final workingDays = employee.workingDaysPerPeriod;
    final lateRateBps = employee.lateDeductionRateBps;
    final absenceRateBps = employee.absenceDeductionRateBps;

    final presentDays = attendanceCounts['present'] ?? 0;
    final lateDays = attendanceCounts['late'] ?? 0;
    final recordedAbsentDays = attendanceCounts['absent'] ?? 0;
    final leaveDays = attendanceCounts['leave'] ?? 0;
    final earlyDepartureDays = attendanceCounts['early_departure'] ?? 0;

    // Daily rate in cents (integer math to avoid floating point drift).
    final dailyRateCents = workingDays > 0 ? fullSalary ~/ workingDays : 0;

    // Paid days = days the employee worked or was on approved leave.
    // present + late + leave + early_departure all count as paid days.
    final paidDays = presentDays + lateDays + leaveDays + earlyDepartureDays;

    // Effective absent days = any working day that was NOT paid.
    // This includes both explicitly-recorded absences and unrecorded days.
    // Using this (instead of only `recordedAbsentDays`) keeps behaviour
    // consistent when attendance isn't fully logged — the employee simply
    // doesn't get paid for days we have no record of.
    final effectiveAbsentDays = workingDays > paidDays
        ? workingDays - paidDays
        : 0;

    // Absence deduction now respects the employee's `absenceDeductionRateBps`
    // (e.g. 10000 = 100% full-day deduction, 5000 = half-day deduction for
    // excused absences). Previously this field was stored but never applied.
    final absenceDeduction = workingDays > 0
        ? (effectiveAbsentDays * dailyRateCents * absenceRateBps) ~/ 10000
        : 0;

    // Earned basic = contractual basic minus absence deduction.
    // Matches SAP/QuickBooks/ADP payslip convention where the contract salary
    // is shown alongside the earned portion.
    final earnedBasic = fullSalary - absenceDeduction;

    // Late deduction: lateDays × dailyRate × (lateRateBps / 10000)
    final lateDeduction = workingDays > 0
        ? (lateDays * dailyRateCents * lateRateBps) ~/ 10000
        : 0;

    // Early departure deduction: same rate as late (>2hrs early = late rate)
    final earlyDepartureDeduction = workingDays > 0
        ? (earlyDepartureDays * dailyRateCents * lateRateBps) ~/ 10000
        : 0;

    final totalDeduction =
        absenceDeduction + lateDeduction + earlyDepartureDeduction;
    final grossPay = fullSalary + commissionCents + bonusCents + overtimeCents;
    final netPay = grossPay - totalDeduction;

    return PayrollCalculation(
      basicSalaryCents: fullSalary,
      earnedBasicCents: earnedBasic,
      commissionCents: commissionCents,
      bonusCents: bonusCents,
      overtimeCents: overtimeCents,
      absenceDeductionCents: absenceDeduction,
      lateDeductionCents: lateDeduction,
      earlyDepartureDeductionCents: earlyDepartureDeduction,
      totalDeductionCents: totalDeduction,
      grossPayCents: grossPay,
      netPayCents: netPay,
      workingDays: workingDays,
      presentDays: presentDays,
      lateDays: lateDays,
      absentDays: recordedAbsentDays,
      leaveDays: leaveDays,
      earlyDepartureDays: earlyDepartureDays,
      dailyRateCents: dailyRateCents,
    );
  }
}
