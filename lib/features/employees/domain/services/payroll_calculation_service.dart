import '../../../../core/database/app_database.dart';

/// Result of payroll calculation with full breakdown
class PayrollCalculation {
  final int basicSalaryCents;
  final int commissionCents;
  final int bonusCents;
  final int overtimeCents;
  final int absenceDeductionCents;
  final int lateDeductionCents;
  final int totalDeductionCents;
  final int grossPayCents;
  final int netPayCents;

  // Attendance data used in calculation
  final int workingDays;
  final int presentDays;
  final int lateDays;
  final int absentDays;
  final int leaveDays;
  final int dailyRateCents;

  const PayrollCalculation({
    required this.basicSalaryCents,
    required this.commissionCents,
    required this.bonusCents,
    required this.overtimeCents,
    required this.absenceDeductionCents,
    required this.lateDeductionCents,
    required this.totalDeductionCents,
    required this.grossPayCents,
    required this.netPayCents,
    required this.workingDays,
    required this.presentDays,
    required this.lateDays,
    required this.absentDays,
    required this.leaveDays,
    required this.dailyRateCents,
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

  /// Calculate payroll for an employee given attendance counts.
  ///
  /// [employee] - the employee record (contains salary and payroll config)
  /// [attendanceCounts] - map with keys: present, late, absent, leave
  /// [commissionCents] - total commission earned in the period
  /// [bonusCents] - bonus for the period
  /// [overtimeCents] - overtime pay for the period
  static PayrollCalculation calculate({
    required Employee employee,
    required Map<String, int> attendanceCounts,
    int commissionCents = 0,
    int bonusCents = 0,
    int overtimeCents = 0,
  }) {
    final basicSalary = employee.salaryCents?.toBigInt().toInt() ?? 0;
    final workingDays = employee.workingDaysPerPeriod;
    final absenceRateBps = employee.absenceDeductionRateBps;
    final lateRateBps = employee.lateDeductionRateBps;

    final presentDays = attendanceCounts['present'] ?? 0;
    final lateDays = attendanceCounts['late'] ?? 0;
    final absentDays = attendanceCounts['absent'] ?? 0;
    final leaveDays = attendanceCounts['leave'] ?? 0;

    // Daily rate in cents (integer math to avoid floating point)
    final dailyRateCents = workingDays > 0 ? basicSalary ~/ workingDays : 0;

    // Absence deduction: absentDays × dailyRate × (absenceRateBps / 10000)
    // Using integer math: (absentDays * dailyRate * absenceRateBps) / 10000
    final absenceDeduction = workingDays > 0
        ? (absentDays * dailyRateCents * absenceRateBps) ~/ 10000
        : 0;

    // Late deduction: lateDays × dailyRate × (lateRateBps / 10000)
    final lateDeduction = workingDays > 0
        ? (lateDays * dailyRateCents * lateRateBps) ~/ 10000
        : 0;

    final totalDeduction = absenceDeduction + lateDeduction;
    final grossPay = basicSalary + commissionCents + bonusCents + overtimeCents;
    final netPay = grossPay - totalDeduction;

    return PayrollCalculation(
      basicSalaryCents: basicSalary,
      commissionCents: commissionCents,
      bonusCents: bonusCents,
      overtimeCents: overtimeCents,
      absenceDeductionCents: absenceDeduction,
      lateDeductionCents: lateDeduction,
      totalDeductionCents: totalDeduction,
      grossPayCents: grossPay,
      netPayCents: netPay,
      workingDays: workingDays,
      presentDays: presentDays,
      lateDays: lateDays,
      absentDays: absentDays,
      leaveDays: leaveDays,
      dailyRateCents: dailyRateCents,
    );
  }
}
