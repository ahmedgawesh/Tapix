import '../../../../core/database/app_database.dart';

/// Result of payroll calculation with full breakdown
class PayrollCalculation {
  final int basicSalaryCents;
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

/// Result of sales target bonus check
class SalesTargetBonusResult {
  final int salesTargetCents;
  final int actualSalesCents;
  final int targetBonusCents;
  final bool achieved;

  const SalesTargetBonusResult({
    required this.salesTargetCents,
    required this.actualSalesCents,
    required this.targetBonusCents,
    required this.achieved,
  });
}

/// Service that calculates payroll based on employee config and attendance.
///
/// **Calculation logic (global best practice):**
/// - Daily rate = basic salary / working days per period
/// - Absence deduction = absent days × daily rate × (absence rate bps / 10000)
/// - Late deduction = late days × daily rate × (late rate bps / 10000)
/// - Gross pay = basic salary + commission + bonus + overtime
/// - Net pay = gross pay - absence deduction - late deduction
class PayrollCalculationService {
  const PayrollCalculationService._();

  /// Check if an employee achieved their sales target and return the bonus.
  static SalesTargetBonusResult checkSalesTargetBonus({
    required Employee employee,
    required int actualSalesCents,
  }) {
    final targetCents = employee.salesTargetCents?.toBigInt().toInt() ?? 0;
    final bonusCents = employee.targetBonusCents?.toBigInt().toInt() ?? 0;

    if (targetCents <= 0 || bonusCents <= 0) {
      return SalesTargetBonusResult(
        salesTargetCents: targetCents,
        actualSalesCents: actualSalesCents,
        targetBonusCents: 0,
        achieved: false,
      );
    }

    final achieved = actualSalesCents >= targetCents;
    return SalesTargetBonusResult(
      salesTargetCents: targetCents,
      actualSalesCents: actualSalesCents,
      targetBonusCents: achieved ? bonusCents : 0,
      achieved: achieved,
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

    final presentDays = attendanceCounts['present'] ?? 0;
    final lateDays = attendanceCounts['late'] ?? 0;
    final absentDays = attendanceCounts['absent'] ?? 0;
    final leaveDays = attendanceCounts['leave'] ?? 0;
    final earlyDepartureDays = attendanceCounts['early_departure'] ?? 0;

    // Daily rate in cents (integer math to avoid floating point)
    final dailyRateCents = workingDays > 0 ? fullSalary ~/ workingDays : 0;

    // Paid days = days the employee worked or was on approved leave
    // present + late + leave + early_departure all count as paid days
    // absent days and unrecorded days get NO pay
    final paidDays = presentDays + lateDays + leaveDays + earlyDepartureDays;

    // Prorated basic salary based on actual paid days
    final basicSalary = workingDays > 0
        ? (dailyRateCents * paidDays)
        : 0;

    // Absence deduction is implicit (unrecorded/absent days simply don't get paid)
    // We track it for display: difference between full salary and prorated salary
    final absenceDeduction = fullSalary - basicSalary;

    // Late deduction: lateDays × dailyRate × (lateRateBps / 10000)
    final lateDeduction = workingDays > 0
        ? (lateDays * dailyRateCents * lateRateBps) ~/ 10000
        : 0;

    // Early departure deduction: same rate as late (>2hrs early = late rate)
    final earlyDepartureDeduction = workingDays > 0
        ? (earlyDepartureDays * dailyRateCents * lateRateBps) ~/ 10000
        : 0;

    final totalDeduction = absenceDeduction + lateDeduction + earlyDepartureDeduction;
    final grossPay = fullSalary + commissionCents + bonusCents + overtimeCents;
    final netPay = grossPay - totalDeduction;

    return PayrollCalculation(
      basicSalaryCents: fullSalary,
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
      absentDays: absentDays,
      leaveDays: leaveDays,
      earlyDepartureDays: earlyDepartureDays,
      dailyRateCents: dailyRateCents,
    );
  }
}
