import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/employee_dao.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/repositories/employee_repository.dart';

/// Implementation of EmployeeRepository
class EmployeeRepositoryImpl implements EmployeeRepository {
  final EmployeeDao _dao;
  final JournalEntryService _journalService;

  EmployeeRepositoryImpl(this._dao, this._journalService);

  // ==================== EMPLOYEES ====================

  @override
  Stream<List<Employee>> watchAllEmployees({
    bool? isActive,
    String? department,
    int? roleId,
  }) {
    return _dao.watchAllEmployees(
      isActive: isActive,
      department: department,
      roleId: roleId,
    );
  }

  @override
  Stream<Employee?> watchEmployee(int id) {
    return _dao.watchEmployee(id);
  }

  @override
  Future<Employee?> getEmployee(int id) {
    return _dao.getEmployee(id);
  }

  @override
  Future<List<Employee>> searchEmployees(String query, {bool? isActive}) {
    return _dao.searchEmployees(query, isActive: isActive);
  }

  @override
  Future<int> createEmployee({
    required String name,
    String? nameAr,
    String? nameFr,
    String? employeeCode,
    int? userId,
    String? email,
    String? phone,
    String? position,
    String? department,
    int? roleId,
    int? managerId,
    int? salaryCents,
    int defaultCommissionRateBps = 0,
    int? fixedCommissionCents,
    String commissionType = 'percentage',
    int? salesTargetCents,
    int? targetBonusCents,
    String targetPeriod = 'monthly',
    String payPeriodType = 'monthly',
    int workingDaysPerPeriod = 26,
    int workingHoursPerDay = 8,
    int absenceDeductionRateBps = 10000,
    int lateDeductionRateBps = 2500,
    required int currencyId,
    DateTime? hireDate,
    String weeklyOffDays = '[5,6]',
    int annualLeaveDays = 21,
    String? notes,
  }) {
    final now = DateTime.now();
    final companion = EmployeesCompanion(
      name: Value(name),
      nameAr: Value(nameAr),
      nameFr: Value(nameFr),
      employeeCode: Value(employeeCode),
      userId: Value(userId),
      email: Value(email),
      phone: Value(phone),
      position: Value(position),
      department: Value(department),
      roleId: Value(roleId),
      managerId: Value(managerId),
      salaryCents: Value(salaryCents != null ? Decimal.fromInt(salaryCents) : null),
      defaultCommissionRateBps: Value(defaultCommissionRateBps),
      fixedCommissionCents: Value(fixedCommissionCents != null ? Decimal.fromInt(fixedCommissionCents) : null),
      commissionType: Value(commissionType),
      salesTargetCents: Value(salesTargetCents != null ? Decimal.fromInt(salesTargetCents) : null),
      targetBonusCents: Value(targetBonusCents != null ? Decimal.fromInt(targetBonusCents) : null),
      targetPeriod: Value(targetPeriod),
      payPeriodType: Value(payPeriodType),
      workingDaysPerPeriod: Value(workingDaysPerPeriod),
      workingHoursPerDay: Value(workingHoursPerDay),
      absenceDeductionRateBps: Value(absenceDeductionRateBps),
      lateDeductionRateBps: Value(lateDeductionRateBps),
      currencyId: Value(currencyId),
      hireDate: Value(hireDate ?? now),
      weeklyOffDays: Value(weeklyOffDays),
      annualLeaveDays: Value(annualLeaveDays),
      notes: Value(notes),
      isActive: const Value(true),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    return _dao.createEmployee(companion);
  }

  @override
  Future<bool> updateEmployee(Employee employee) {
    return _dao.updateEmployee(employee);
  }

  @override
  Future<int> deleteEmployee(int id) {
    return _dao.deleteEmployee(id);
  }

  @override
  Stream<int> watchEmployeeCount({bool? isActive}) {
    return _dao.watchEmployeeCount(isActive: isActive);
  }

  @override
  Stream<List<Employee>> watchEmployeesByDepartment(String department) {
    return _dao.watchEmployeesByDepartment(department);
  }

  @override
  Stream<List<Employee>> watchEmployeesByRole(int roleId) {
    return _dao.watchEmployeesByRole(roleId);
  }

  @override
  Future<List<Employee>> getSubordinates(int managerId) {
    return _dao.getSubordinates(managerId);
  }

  @override
  Stream<List<String>> watchDepartments() {
    return _dao.watchDepartments();
  }

  @override
  Future<String> generateEmployeeCode() async {
    final maxNum = await _dao.getMaxEmployeeCodeNumber();
    final nextNum = maxNum + 1;
    return 'EMP${nextNum.toString().padLeft(4, '0')}';
  }

  // ==================== ROLES ====================

  @override
  Stream<List<Role>> watchAllRoles({bool? isActive}) {
    return _dao.watchAllRoles(isActive: isActive);
  }

  @override
  Future<Role?> getRole(int id) {
    return _dao.getRole(id);
  }

  @override
  Future<int> createRole({
    required String name,
    String? nameAr,
    String? nameFr,
    String? description,
    List<String> permissions = const [],
    bool isSystemRole = false,
  }) {
    final now = DateTime.now();
    final companion = RolesCompanion(
      name: Value(name),
      nameAr: Value(nameAr),
      nameFr: Value(nameFr),
      description: Value(description),
      permissions: Value(jsonEncode(permissions)),
      isSystemRole: Value(isSystemRole),
      isActive: const Value(true),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    return _dao.createRole(companion);
  }

  @override
  Future<bool> updateRole(Role role) {
    return _dao.updateRole(role);
  }

  @override
  Future<int> deleteRole(int id) {
    return _dao.deleteRole(id);
  }

  // ==================== ATTENDANCE ====================

  @override
  Stream<List<Attendance>> watchAttendanceByDate(DateTime date) {
    return _dao.watchAttendanceByDate(date);
  }

  @override
  Stream<List<Attendance>> watchEmployeeAttendance(
    int employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _dao.watchEmployeeAttendance(
      employeeId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  Future<Attendance?> getAttendance(int employeeId, DateTime date) {
    return _dao.getAttendance(employeeId, date);
  }

  @override
  Future<int> checkIn({
    required int employeeId,
    required DateTime date,
    required DateTime checkInTime,
    String? checkInMethod,
    String? location,
    AttendanceStatus? status,
    String? notes,
  }) async {
    final existing = await _dao.getAttendance(employeeId, date);
    final now = DateTime.now();
    final statusStr = status?.name ?? 'present';

    if (existing != null) {
      // Update existing record (e.g. auto-generated absent → present)
      final updated = existing.copyWith(
        checkInTime: Value(checkInTime),
        status: statusStr,
        checkInMethod: Value(checkInMethod),
        location: Value(location),
        notes: Value(notes),
        updatedAt: now,
      );
      await _dao.updateAttendance(updated);
      return existing.id;
    }

    final companion = AttendancesCompanion(
      employeeId: Value(employeeId),
      attendanceDate: Value(DateTime(date.year, date.month, date.day)),
      checkInTime: Value(checkInTime),
      status: Value(statusStr),
      checkInMethod: Value(checkInMethod),
      location: Value(location),
      notes: Value(notes),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    return _dao.createAttendance(companion);
  }

  @override
  Future<int> markAbsent({
    required int employeeId,
    required DateTime date,
    String? notes,
  }) async {
    final existing = await _dao.getAttendance(employeeId, date);
    final now = DateTime.now();

    if (existing != null) {
      // Update existing record to absent
      final updated = existing.copyWith(
        status: 'absent',
        checkInTime: const Value(null),
        checkOutTime: const Value(null),
        notes: Value(notes),
        updatedAt: now,
      );
      await _dao.updateAttendance(updated);
      return existing.id;
    }

    final companion = AttendancesCompanion(
      employeeId: Value(employeeId),
      attendanceDate: Value(DateTime(date.year, date.month, date.day)),
      status: const Value('absent'),
      notes: Value(notes),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    return _dao.createAttendance(companion);
  }

  @override
  Future<bool> checkOut({
    required int employeeId,
    required DateTime date,
    required DateTime checkOutTime,
    int overtimeMinutes = 0,
  }) async {
    final existing = await _dao.getAttendance(employeeId, date);
    if (existing == null) {
      throw Exception('No check-in found for this date');
    }

    // Auto-calculate overtime if check-in time is available
    int computedOvertime = overtimeMinutes;
    if (existing.checkInTime != null && overtimeMinutes == 0) {
      final employee = await _dao.getEmployee(employeeId);
      if (employee != null) {
        final workedMinutes = checkOutTime.difference(existing.checkInTime!).inMinutes;
        final expectedMinutes = employee.workingHoursPerDay * 60;
        if (workedMinutes > expectedMinutes) {
          computedOvertime = workedMinutes - expectedMinutes;
        }
      }
    }

    final updated = existing.copyWith(
      checkOutTime: Value(checkOutTime),
      overtimeMinutes: computedOvertime,
      updatedAt: DateTime.now(),
    );
    return _dao.updateAttendance(updated);
  }

  @override
  Future<bool> updateAttendanceStatus({
    required int employeeId,
    required DateTime date,
    required AttendanceStatus status,
    String? notes,
    int? approvedBy,
  }) async {
    final existing = await _dao.getAttendance(employeeId, date);
    if (existing == null) {
      final now = DateTime.now();
      final companion = AttendancesCompanion(
        employeeId: Value(employeeId),
        attendanceDate: Value(DateTime(date.year, date.month, date.day)),
        status: Value(status.name),
        notes: Value(notes),
        approvedBy: Value(approvedBy),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
      await _dao.createAttendance(companion);
      return true;
    }

    final updated = existing.copyWith(
      status: status.name,
      notes: Value(notes),
      approvedBy: Value(approvedBy),
      updatedAt: DateTime.now(),
    );
    return _dao.updateAttendance(updated);
  }

  @override
  Future<Map<String, int>> getEmployeeAttendanceCounts(
    int employeeId,
    DateTime startDate,
    DateTime endDate,
  ) {
    return _dao.getEmployeeAttendanceCounts(employeeId, startDate, endDate);
  }

  @override
  Stream<AttendanceSummary> watchAttendanceSummary(DateTime date) {
    return _dao.watchAttendanceCountsByDate(date).map((counts) {
      return AttendanceSummary(
        date: date,
        presentCount: counts['present'] ?? 0,
        lateCount: counts['late'] ?? 0,
        absentCount: counts['absent'] ?? 0,
        onLeaveCount: counts['leave'] ?? 0,
      );
    });
  }

  @override
  Future<List<AttendanceSummary>> getAttendanceSummaryRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final summaries = <AttendanceSummary>[];
    var current = startDate;
    while (!current.isAfter(endDate)) {
      final counts = await _dao.watchAttendanceCountsByDate(current).first;
      summaries.add(AttendanceSummary(
        date: current,
        presentCount: counts['present'] ?? 0,
        lateCount: counts['late'] ?? 0,
        absentCount: counts['absent'] ?? 0,
        onLeaveCount: counts['leave'] ?? 0,
      ));
      current = current.add(const Duration(days: 1));
    }
    return summaries;
  }

  // ==================== LEAVE REQUESTS ====================

  @override
  Stream<List<LeaveRequest>> watchAllLeaveRequests({
    LeaveRequestStatus? status,
  }) {
    return _dao.watchAllLeaveRequests(status: status?.name);
  }

  @override
  Stream<List<LeaveRequest>> watchEmployeeLeaveRequests(
    int employeeId, {
    LeaveRequestStatus? status,
  }) {
    return _dao.watchEmployeeLeaveRequests(employeeId, status: status?.name);
  }

  @override
  Future<LeaveRequest?> getLeaveRequest(int id) {
    return _dao.getLeaveRequest(id);
  }

  @override
  Future<int> createLeaveRequest({
    required int employeeId,
    required LeaveType leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required int daysCount,
    String? reason,
  }) {
    final now = DateTime.now();
    final companion = LeaveRequestsCompanion(
      employeeId: Value(employeeId),
      leaveType: Value(leaveType.name),
      startDate: Value(startDate),
      endDate: Value(endDate),
      daysCount: Value(daysCount),
      reason: Value(reason),
      status: const Value('pending'),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    return _dao.createLeaveRequest(companion);
  }

  @override
  Future<bool> approveLeaveRequest({
    required int id,
    required int approvedBy,
  }) async {
    final request = await _dao.getLeaveRequest(id);
    if (request == null) return false;

    final updated = request.copyWith(
      status: 'approved',
      approvedBy: Value(approvedBy),
      approvedAt: Value(DateTime.now()),
      updatedAt: DateTime.now(),
    );
    return _dao.updateLeaveRequest(updated);
  }

  @override
  Future<bool> rejectLeaveRequest({
    required int id,
    required int rejectedBy,
    String? rejectionReason,
  }) async {
    final request = await _dao.getLeaveRequest(id);
    if (request == null) return false;

    final updated = request.copyWith(
      status: 'rejected',
      approvedBy: Value(rejectedBy),
      approvedAt: Value(DateTime.now()),
      rejectionReason: Value(rejectionReason),
      updatedAt: DateTime.now(),
    );
    return _dao.updateLeaveRequest(updated);
  }

  @override
  Future<bool> cancelLeaveRequest(int id) async {
    final request = await _dao.getLeaveRequest(id);
    if (request == null) return false;

    final updated = request.copyWith(
      status: 'cancelled',
      updatedAt: DateTime.now(),
    );
    return _dao.updateLeaveRequest(updated);
  }

  // ==================== PAYROLL ====================

  @override
  Stream<List<Payroll>> watchPayrollsByPeriod(String period, {
    PayrollStatus? status,
  }) {
    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final periodStart = DateTime(year, month, 1);
    final periodEnd = DateTime(year, month + 1, 0);

    return _dao.watchPayrollsByPeriod(
      periodStart,
      periodEnd,
      status: status?.name,
    );
  }

  @override
  Stream<List<Payroll>> watchEmployeePayrolls(int employeeId) {
    return _dao.watchEmployeePayrolls(employeeId);
  }

  @override
  Future<Payroll?> getPayroll(int id) {
    return _dao.getPayroll(id);
  }

  @override
  Future<int> createPayroll({
    required int employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int basicSalaryCents,
    int commissionCents = 0,
    int bonusCents = 0,
    int overtimeCents = 0,
    int deductionCents = 0,
    required int netPayCents,
    required int currencyId,
    String? notes,
  }) async {
    final now = DateTime.now();
    final companion = PayrollsCompanion(
      employeeId: Value(employeeId),
      periodStart: Value(periodStart),
      periodEnd: Value(periodEnd),
      basicSalaryCents: Value(Decimal.fromInt(basicSalaryCents)),
      commissionCents: Value(Decimal.fromInt(commissionCents)),
      bonusCents: Value(Decimal.fromInt(bonusCents)),
      overtimeCents: Value(Decimal.fromInt(overtimeCents)),
      deductionCents: Value(Decimal.fromInt(deductionCents)),
      netPayCents: Value(Decimal.fromInt(netPayCents)),
      currencyId: Value(currencyId),
      status: const Value('draft'),
      notes: Value(notes),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
    // No journal entry on creation — only when paid.
    // STRICT RULE: No accrual. Direct expense on payment only.
    final payrollId = await _dao.createPayroll(companion);

    return payrollId;
  }

  @override
  Future<bool> updatePayrollStatus({
    required int id,
    required PayrollStatus status,
    DateTime? processedAt,
    String? bankReference,
  }) async {
    final payroll = await _dao.getPayroll(id);
    if (payroll == null) return false;

    final updated = payroll.copyWith(
      status: status.name,
      processedAt: Value(processedAt),
      bankReference: Value(bankReference),
      updatedAt: DateTime.now(),
    );

    // ATOMIC: Wrap status update and payment journal entry in a single
    // transaction so both succeed or fail together.
    final ok = await _dao.db.transaction(() async {
      final result = await _dao.updatePayroll(updated);

      // STRICT RULE: Dr Salaries Expense (5200), Cr Cash/Bank
      // No accrual. Direct expense on payment only.
      if (result && status == PayrollStatus.paid) {
        final netPayCents = payroll.netPayCents.toBigInt().toInt();
        if (netPayCents > 0) {
          await _journalService.recordPayrollJournalEntry(
            payrollId: id,
            netPayCents: netPayCents,
            currencyId: payroll.currencyId,
          );
        }
      }

      return result;
    });

    return ok;
  }

  @override
  Future<int> deletePayroll(int id) {
    return _dao.deletePayroll(id);
  }

  @override
  Stream<PayrollSummary> watchPayrollSummary(String period) {
    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final periodStart = DateTime(year, month, 1);
    final periodEnd = DateTime(year, month + 1, 0);

    return _dao.watchPayrollSummary(periodStart, periodEnd).map((summary) {
      return PayrollSummary(
        period: period,
        totalGrossCents: summary['totalGross'] ?? 0,
        totalDeductionsCents: summary['totalDeductions'] ?? 0,
        totalNetCents: summary['totalNet'] ?? 0,
        employeeCount: summary['count'] ?? 0,
      );
    });
  }

  @override
  Future<List<String>> getPayrollPeriods() {
    return _dao.getPayrollPeriods();
  }

  // ==================== COMMISSIONS ====================

  @override
  Stream<List<Commission>> watchEmployeeCommissions(
    int employeeId, {
    CommissionStatus? status,
  }) {
    return _dao.watchEmployeeCommissions(employeeId, status: status?.name);
  }

  @override
  Stream<List<Commission>> watchCommissionsByPeriod(
    String period, {
    CommissionStatus? status,
  }) {
    return _dao.watchCommissionsByPeriod(period, status: status?.name);
  }

  @override
  Future<int> createCommission({
    required int employeeId,
    int? saleId,
    required int commissionRateBps,
    required int commissionAmountCents,
    required int currencyId,
    String? period,
  }) {
    final companion = CommissionsCompanion(
      employeeId: Value(employeeId),
      saleId: Value(saleId),
      commissionRateBps: Value(commissionRateBps.toDouble()),
      commissionAmountCents: Value(Decimal.fromInt(commissionAmountCents)),
      currencyId: Value(currencyId),
      period: Value(period),
      status: const Value('pending'),
      createdAt: Value(DateTime.now()),
    );
    return _dao.createCommission(companion);
  }

  @override
  Future<bool> updateCommissionStatus({
    required int id,
    required CommissionStatus status,
  }) async {
    final commission = await _dao.getCommissionById(id);
    if (commission == null) {
      throw Exception('Commission #$id not found');
    }

    final updated = commission.copyWith(status: status.name);
    return _dao.updateCommission(updated);
  }

  @override
  Future<int> getTotalCommissionCents(int employeeId, String period) {
    return _dao.getTotalCommissionCents(employeeId, period);
  }

  @override
  Future<Map<String, int>> getEmployeeSalesStats(
    int employeeId,
    DateTime periodStart,
    DateTime periodEnd,
  ) {
    return _dao.getEmployeeSalesStats(employeeId, periodStart, periodEnd);
  }

  // ==================== PERFORMANCE ====================

  @override
  Stream<List<PerformanceMetric>> watchEmployeePerformance(
    int employeeId, {
    String? metricType,
    String? period,
  }) {
    return _dao.watchEmployeePerformance(
      employeeId,
      metricType: metricType,
      period: period,
    );
  }

  @override
  Future<int> createPerformanceMetric({
    required int employeeId,
    required String metricType,
    required double metricValue,
    double? targetValue,
    required String period,
    required String periodIdentifier,
    int? recordedBy,
  }) {
    final now = DateTime.now();
    final companion = PerformanceMetricsCompanion(
      employeeId: Value(employeeId),
      metricType: Value(metricType),
      metricValue: Value(metricValue),
      targetValue: Value(targetValue),
      period: Value(period),
      periodIdentifier: Value(periodIdentifier),
      recordedAt: Value(now),
      recordedBy: Value(recordedBy),
      createdAt: Value(now),
    );
    return _dao.createPerformanceMetric(companion);
  }

  @override
  Future<double?> getAveragePerformanceScore(
    int employeeId, {
    String? period,
  }) {
    return _dao.getAveragePerformanceScore(employeeId, period: period);
  }
}
