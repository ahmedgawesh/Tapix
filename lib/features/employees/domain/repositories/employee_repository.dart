import '../../../../core/database/app_database.dart';
import '../entities/employee_entity.dart';

/// Domain repository interface for employee operations
abstract class EmployeeRepository {
  // ==================== EMPLOYEES ====================

  /// Watch all employees with optional filters
  Stream<List<Employee>> watchAllEmployees({
    bool? isActive,
    String? department,
    int? roleId,
  });

  /// Watch a single employee by ID
  Stream<Employee?> watchEmployee(int id);

  /// Get a single employee by ID
  Future<Employee?> getEmployee(int id);

  /// Search employees by name, phone, email, or employee code
  Future<List<Employee>> searchEmployees(String query, {bool? isActive});

  /// Create a new employee
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
    String overtimeCalcType = 'hourly_rate',
    int overtimeRateBps = 15000,
    required int currencyId,
    DateTime? hireDate,
    String weeklyOffDays = '[5,6]',
    int annualLeaveDays = 21,
    String? notes,
  });

  /// Update an existing employee
  Future<bool> updateEmployee(Employee employee);

  /// Delete an employee by ID
  Future<int> deleteEmployee(int id);

  /// Watch employee count
  Stream<int> watchEmployeeCount({bool? isActive});

  /// Watch employees by department
  Stream<List<Employee>> watchEmployeesByDepartment(String department);

  /// Watch employees by role
  Stream<List<Employee>> watchEmployeesByRole(int roleId);

  /// Get subordinates of a manager
  Future<List<Employee>> getSubordinates(int managerId);

  /// Watch distinct departments
  Stream<List<String>> watchDepartments();

  /// Generate next employee code
  Future<String> generateEmployeeCode();

  // ==================== ROLES ====================

  /// Watch all roles
  Stream<List<Role>> watchAllRoles({bool? isActive});

  /// Get a role by ID
  Future<Role?> getRole(int id);

  /// Create a new role
  Future<int> createRole({
    required String name,
    String? nameAr,
    String? nameFr,
    String? description,
    List<String> permissions = const [],
    bool isSystemRole = false,
  });

  /// Update an existing role
  Future<bool> updateRole(Role role);

  /// Delete a role by ID
  Future<int> deleteRole(int id);

  // ==================== ATTENDANCE ====================

  /// Watch attendance for a specific date
  Stream<List<Attendance>> watchAttendanceByDate(DateTime date);

  /// Watch attendance for an employee
  Stream<List<Attendance>> watchEmployeeAttendance(
    int employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Get attendance for a specific employee and date
  Future<Attendance?> getAttendance(int employeeId, DateTime date);

  /// Create or update attendance (check-in)
  Future<int> checkIn({
    required int employeeId,
    required DateTime date,
    required DateTime checkInTime,
    String? checkInMethod,
    String? location,
    AttendanceStatus? status,
    String? notes,
  });

  /// Mark employee as absent
  Future<int> markAbsent({
    required int employeeId,
    required DateTime date,
    String? notes,
  });

  /// Update attendance (check-out)
  Future<bool> checkOut({
    required int employeeId,
    required DateTime date,
    required DateTime checkOutTime,
    int overtimeMinutes = 0,
  });

  /// Update attendance status
  Future<bool> updateAttendanceStatus({
    required int employeeId,
    required DateTime date,
    required AttendanceStatus status,
    String? notes,
    int? approvedBy,
  });

  /// Get employee attendance counts for a period
  Future<Map<String, int>> getEmployeeAttendanceCounts(
    int employeeId,
    DateTime startDate,
    DateTime endDate,
  );

  /// Watch attendance summary for a date
  Stream<AttendanceSummary> watchAttendanceSummary(DateTime date);

  /// Get attendance summary for a date range
  Future<List<AttendanceSummary>> getAttendanceSummaryRange(
    DateTime startDate,
    DateTime endDate,
  );

  // ==================== LEAVE REQUESTS ====================

  /// Watch all leave requests with optional status filter
  Stream<List<LeaveRequest>> watchAllLeaveRequests({
    LeaveRequestStatus? status,
  });

  /// Watch leave requests for an employee
  Stream<List<LeaveRequest>> watchEmployeeLeaveRequests(
    int employeeId, {
    LeaveRequestStatus? status,
  });

  /// Get a leave request by ID
  Future<LeaveRequest?> getLeaveRequest(int id);

  /// Create a new leave request
  Future<int> createLeaveRequest({
    required int employeeId,
    required LeaveType leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required int daysCount,
    String? reason,
  });

  /// Approve a leave request
  Future<bool> approveLeaveRequest({
    required int id,
    required int approvedBy,
  });

  /// Reject a leave request
  Future<bool> rejectLeaveRequest({
    required int id,
    required int rejectedBy,
    String? rejectionReason,
  });

  /// Cancel a leave request
  Future<bool> cancelLeaveRequest(int id);

  // ==================== PAYROLL ====================

  /// Watch payrolls for a period
  Stream<List<Payroll>> watchPayrollsByPeriod(String period, {
    PayrollStatus? status,
  });

  /// Watch payroll for an employee
  Stream<List<Payroll>> watchEmployeePayrolls(int employeeId);

  /// Get a payroll by ID
  Future<Payroll?> getPayroll(int id);

  /// Create a new payroll record
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
  });

  /// Update payroll status
  Future<bool> updatePayrollStatus({
    required int id,
    required PayrollStatus status,
    DateTime? processedAt,
    String? bankReference,
  });

  /// Delete a payroll record
  Future<int> deletePayroll(int id);

  /// Watch payroll summary for a period
  Stream<PayrollSummary> watchPayrollSummary(String period);

  /// Get distinct payroll periods
  Future<List<String>> getPayrollPeriods();

  // ==================== COMMISSIONS ====================

  /// Watch commissions for an employee
  Stream<List<Commission>> watchEmployeeCommissions(
    int employeeId, {
    CommissionStatus? status,
  });

  /// Watch commissions for a period
  Stream<List<Commission>> watchCommissionsByPeriod(
    String period, {
    CommissionStatus? status,
  });

  /// Create a new commission
  Future<int> createCommission({
    required int employeeId,
    int? saleId,
    required int commissionRateBps,
    required int commissionAmountCents,
    required int currencyId,
    String? period,
  });

  /// Update commission status
  Future<bool> updateCommissionStatus({
    required int id,
    required CommissionStatus status,
  });

  /// Get total commission for an employee in a period
  Future<int> getTotalCommissionCents(int employeeId, String period);

  /// Get sales statistics for an employee within a date range.
  /// Returns: {salesCount, salesTotalCents, returnsCount, returnsTotalCents}
  Future<Map<String, int>> getEmployeeSalesStats(
    int employeeId,
    DateTime periodStart,
    DateTime periodEnd,
  );

  // ==================== PERFORMANCE ====================

  /// Watch performance metrics for an employee
  Stream<List<PerformanceMetric>> watchEmployeePerformance(
    int employeeId, {
    String? metricType,
    String? period,
  });

  /// Create a new performance metric
  Future<int> createPerformanceMetric({
    required int employeeId,
    required String metricType,
    required double metricValue,
    double? targetValue,
    required String period,
    required String periodIdentifier,
    int? recordedBy,
  });

  /// Get average performance score for an employee
  Future<double?> getAveragePerformanceScore(
    int employeeId, {
    String? period,
  });
}
