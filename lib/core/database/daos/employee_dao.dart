import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/people.dart';

part 'employee_dao.g.dart';

@DriftAccessor(tables: [
  Employees,
  Roles,
  Attendances,
  LeaveRequests,
  Payrolls,
  PayrollDeductions,
  Commissions,
  PerformanceMetrics,
  ShiftSchedules,
  EmployeeDocuments,
  OvertimeRules,
])
class EmployeeDao extends DatabaseAccessor<AppDatabase>
    with _$EmployeeDaoMixin {
  EmployeeDao(super.db);

  // ==================== EMPLOYEES ====================

  /// Watch all employees with optional filters
  Stream<List<Employee>> watchAllEmployees({
    bool? isActive,
    String? department,
    int? roleId,
  }) {
    var query = select(employees);

    if (isActive != null) {
      query = query..where((e) => e.isActive.equals(isActive));
    }
    if (department != null) {
      query = query..where((e) => e.department.equals(department));
    }
    if (roleId != null) {
      query = query..where((e) => e.roleId.equals(roleId));
    }

    return (query..orderBy([(e) => OrderingTerm.asc(e.name)])).watch();
  }

  /// Watch a single employee by ID
  Stream<Employee?> watchEmployee(int id) {
    return (select(employees)..where((e) => e.id.equals(id)))
        .watchSingleOrNull();
  }

  /// Get a single employee by ID
  Future<Employee?> getEmployee(int id) {
    return (select(employees)..where((e) => e.id.equals(id))).getSingleOrNull();
  }

  /// Search employees by name, phone, email, or employee code
  Future<List<Employee>> searchEmployees(String query, {bool? isActive}) {
    final searchQuery = '%$query%';
    var selectQuery = select(employees)
      ..where((e) =>
          e.name.like(searchQuery) |
          e.email.like(searchQuery) |
          e.phone.like(searchQuery) |
          e.employeeCode.like(searchQuery));

    if (isActive != null) {
      selectQuery = selectQuery..where((e) => e.isActive.equals(isActive));
    }

    return selectQuery.get();
  }

  /// Create a new employee
  Future<int> createEmployee(EmployeesCompanion companion) {
    return into(employees).insert(companion);
  }

  /// Update an existing employee
  Future<bool> updateEmployee(Employee employee) {
    return update(employees).replace(employee);
  }

  /// Delete an employee by ID
  Future<int> deleteEmployee(int id) {
    return (delete(employees)..where((e) => e.id.equals(id))).go();
  }

  /// Watch employee count
  Stream<int> watchEmployeeCount({bool? isActive}) {
    final countExp = employees.id.count();
    var query = selectOnly(employees)..addColumns([countExp]);

    if (isActive != null) {
      query = query..where(employees.isActive.equals(isActive));
    }

    return query.map((row) => row.read(countExp) ?? 0).watchSingle();
  }

  /// Watch employees by department
  Stream<List<Employee>> watchEmployeesByDepartment(String department) {
    return (select(employees)
          ..where((e) => e.department.equals(department))
          ..orderBy([(e) => OrderingTerm.asc(e.name)]))
        .watch();
  }

  /// Watch employees by role
  Stream<List<Employee>> watchEmployeesByRole(int roleId) {
    return (select(employees)
          ..where((e) => e.roleId.equals(roleId))
          ..orderBy([(e) => OrderingTerm.asc(e.name)]))
        .watch();
  }

  /// Get subordinates of a manager
  Future<List<Employee>> getSubordinates(int managerId) {
    return (select(employees)
          ..where((e) => e.managerId.equals(managerId))
          ..orderBy([(e) => OrderingTerm.asc(e.name)]))
        .get();
  }

  /// Watch distinct departments
  Stream<List<String>> watchDepartments() {
    final query = selectOnly(employees, distinct: true)
      ..addColumns([employees.department])
      ..where(employees.department.isNotNull());

    return query
        .map((row) => row.read(employees.department))
        .watch()
        .map((list) => list.whereType<String>().toList());
  }

  /// Get the highest employee code number
  Future<int> getMaxEmployeeCodeNumber() async {
    final result = await customSelect(
      "SELECT MAX(CAST(SUBSTR(employee_code, 4) AS INTEGER)) as max_num FROM employees WHERE employee_code LIKE 'EMP%'",
    ).getSingleOrNull();

    return result?.read<int?>('max_num') ?? 0;
  }

  // ==================== ROLES ====================

  /// Watch all roles
  Stream<List<Role>> watchAllRoles({bool? isActive}) {
    var query = select(roles);

    if (isActive != null) {
      query = query..where((r) => r.isActive.equals(isActive));
    }

    return (query..orderBy([(r) => OrderingTerm.asc(r.name)])).watch();
  }

  /// Get a role by ID
  Future<Role?> getRole(int id) {
    return (select(roles)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// Create a new role
  Future<int> createRole(RolesCompanion companion) {
    return into(roles).insert(companion);
  }

  /// Update an existing role
  Future<bool> updateRole(Role role) {
    return update(roles).replace(role);
  }

  /// Delete a role by ID
  Future<int> deleteRole(int id) {
    return (delete(roles)..where((r) => r.id.equals(id))).go();
  }

  // ==================== ATTENDANCE ====================

  /// Watch attendance for a specific date
  Stream<List<Attendance>> watchAttendanceByDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(attendances)
          ..where((a) =>
              a.attendanceDate.isBiggerOrEqualValue(startOfDay) &
              a.attendanceDate.isSmallerThanValue(endOfDay))
          ..orderBy([(a) => OrderingTerm.asc(a.employeeId)]))
        .watch();
  }

  /// Watch attendance for an employee
  Stream<List<Attendance>> watchEmployeeAttendance(
    int employeeId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    var query = select(attendances)..where((a) => a.employeeId.equals(employeeId));

    if (startDate != null) {
      query = query..where((a) => a.attendanceDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query..where((a) => a.attendanceDate.isSmallerOrEqualValue(endDate));
    }

    return (query..orderBy([(a) => OrderingTerm.desc(a.attendanceDate)])).watch();
  }

  /// Get attendance for a specific employee and date
  Future<Attendance?> getAttendance(int employeeId, DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(attendances)
          ..where((a) =>
              a.employeeId.equals(employeeId) &
              a.attendanceDate.isBiggerOrEqualValue(startOfDay) &
              a.attendanceDate.isSmallerThanValue(endOfDay)))
        .getSingleOrNull();
  }

  /// Create attendance record
  Future<int> createAttendance(AttendancesCompanion companion) {
    return into(attendances).insert(companion);
  }

  /// Update attendance record
  Future<bool> updateAttendance(Attendance attendance) {
    return update(attendances).replace(attendance);
  }

  /// Watch attendance counts for a date
  Stream<Map<String, int>> watchAttendanceCountsByDate(DateTime date) {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return (select(attendances)
          ..where((a) =>
              a.attendanceDate.isBiggerOrEqualValue(startOfDay) &
              a.attendanceDate.isSmallerThanValue(endOfDay)))
        .watch()
        .map((list) {
      final counts = <String, int>{
        'present': 0,
        'late': 0,
        'absent': 0,
        'leave': 0,
      };
      for (final attendance in list) {
        final status = attendance.status;
        counts[status] = (counts[status] ?? 0) + 1;
      }
      return counts;
    });
  }

  /// Get employee attendance counts for a period
  /// Returns: {present, late, absent, leave, overtimeMinutes}
  Future<Map<String, int>> getEmployeeAttendanceCounts(
    int employeeId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final result = await (select(attendances)
          ..where((a) =>
              a.employeeId.equals(employeeId) &
              a.attendanceDate.isBiggerOrEqualValue(startDate) &
              a.attendanceDate.isSmallerOrEqualValue(endDate)))
        .get();

    final counts = <String, int>{
      'present': 0,
      'late': 0,
      'absent': 0,
      'leave': 0,
      'overtimeMinutes': 0,
    };
    for (final a in result) {
      counts[a.status] = (counts[a.status] ?? 0) + 1;
      counts['overtimeMinutes'] = (counts['overtimeMinutes'] ?? 0) + a.overtimeMinutes;
    }
    return counts;
  }

  /// Get all active employees
  Future<List<Employee>> getAllActiveEmployees() {
    return (select(employees)
          ..where((e) => e.isActive.equals(true))
          ..orderBy([(e) => OrderingTerm.asc(e.name)]))
        .get();
  }

  /// Get attendance records for a date range
  Future<List<Attendance>> getAttendanceByDateRange(DateTime startDate, DateTime endDate) {
    return (select(attendances)
          ..where((a) =>
              a.attendanceDate.isBiggerOrEqualValue(startDate) &
              a.attendanceDate.isSmallerOrEqualValue(endDate)))
        .get();
  }

  // ==================== LEAVE REQUESTS ====================

  /// Watch all leave requests with optional status filter
  Stream<List<LeaveRequest>> watchAllLeaveRequests({String? status}) {
    var query = select(leaveRequests);

    if (status != null) {
      query = query..where((l) => l.status.equals(status));
    }

    return (query..orderBy([(l) => OrderingTerm.desc(l.createdAt)])).watch();
  }

  /// Watch leave requests for an employee
  Stream<List<LeaveRequest>> watchEmployeeLeaveRequests(
    int employeeId, {
    String? status,
  }) {
    var query = select(leaveRequests)
      ..where((l) => l.employeeId.equals(employeeId));

    if (status != null) {
      query = query..where((l) => l.status.equals(status));
    }

    return (query..orderBy([(l) => OrderingTerm.desc(l.createdAt)])).watch();
  }

  /// Get a leave request by ID
  Future<LeaveRequest?> getLeaveRequest(int id) {
    return (select(leaveRequests)..where((l) => l.id.equals(id)))
        .getSingleOrNull();
  }

  /// Create a new leave request
  Future<int> createLeaveRequest(LeaveRequestsCompanion companion) {
    return into(leaveRequests).insert(companion);
  }

  /// Update a leave request
  Future<bool> updateLeaveRequest(LeaveRequest request) {
    return update(leaveRequests).replace(request);
  }

  // ==================== PAYROLL ====================

  /// Watch payrolls for a period
  Stream<List<Payroll>> watchPayrollsByPeriod(
    DateTime periodStart,
    DateTime periodEnd, {
    String? status,
  }) {
    var query = select(payrolls)
      ..where((p) =>
          p.periodStart.isBiggerOrEqualValue(periodStart) &
          p.periodEnd.isSmallerOrEqualValue(periodEnd));

    if (status != null) {
      query = query..where((p) => p.status.equals(status));
    }

    return (query..orderBy([(p) => OrderingTerm.asc(p.employeeId)])).watch();
  }

  /// Watch payroll for an employee
  Stream<List<Payroll>> watchEmployeePayrolls(int employeeId) {
    return (select(payrolls)
          ..where((p) => p.employeeId.equals(employeeId))
          ..orderBy([(p) => OrderingTerm.desc(p.periodStart)]))
        .watch();
  }

  /// Get a payroll by ID
  Future<Payroll?> getPayroll(int id) {
    return (select(payrolls)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Create a new payroll record
  Future<int> createPayroll(PayrollsCompanion companion) {
    return into(payrolls).insert(companion);
  }

  /// Update a payroll record
  Future<bool> updatePayroll(Payroll payroll) {
    return update(payrolls).replace(payroll);
  }

  /// Delete a payroll record
  Future<int> deletePayroll(int id) {
    return (delete(payrolls)..where((p) => p.id.equals(id))).go();
  }

  /// Watch payroll summary for a period
  Stream<Map<String, int>> watchPayrollSummary(
    DateTime periodStart,
    DateTime periodEnd,
  ) {
    return (select(payrolls)
          ..where((p) =>
              p.periodStart.isBiggerOrEqualValue(periodStart) &
              p.periodEnd.isSmallerOrEqualValue(periodEnd)))
        .watch()
        .map((list) {
      var totalGross = Decimal.zero;
      var totalDeductions = Decimal.zero;
      var totalNet = Decimal.zero;

      for (final payroll in list) {
        totalGross += payroll.basicSalaryCents +
            payroll.commissionCents +
            payroll.bonusCents +
            payroll.overtimeCents;
        totalDeductions += payroll.deductionCents;
        totalNet += payroll.netPayCents;
      }

      return {
        'totalGross': totalGross.toBigInt().toInt(),
        'totalDeductions': totalDeductions.toBigInt().toInt(),
        'totalNet': totalNet.toBigInt().toInt(),
        'count': list.length,
      };
    });
  }

  /// Get distinct payroll periods
  Future<List<String>> getPayrollPeriods() async {
    final result = await customSelect(
      "SELECT DISTINCT strftime('%Y-%m', period_start) as period FROM payrolls WHERE period_start IS NOT NULL ORDER BY period DESC",
    ).get();

    return result
        .map((row) => row.readNullable<String>('period'))
        .where((p) => p != null)
        .cast<String>()
        .toList();
  }

  // ==================== COMMISSIONS ====================

  /// Get a single commission by ID
  Future<Commission?> getCommissionById(int id) {
    return (select(commissions)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  /// Watch commissions for an employee
  Stream<List<Commission>> watchEmployeeCommissions(
    int employeeId, {
    String? status,
  }) {
    var query = select(commissions)
      ..where((c) => c.employeeId.equals(employeeId));

    if (status != null) {
      query = query..where((c) => c.status.equals(status));
    }

    return (query..orderBy([(c) => OrderingTerm.desc(c.createdAt)])).watch();
  }

  /// Watch commissions for a period
  Stream<List<Commission>> watchCommissionsByPeriod(
    String period, {
    String? status,
  }) {
    var query = select(commissions)..where((c) => c.period.equals(period));

    if (status != null) {
      query = query..where((c) => c.status.equals(status));
    }

    return (query..orderBy([(c) => OrderingTerm.desc(c.createdAt)])).watch();
  }

  /// Create a new commission
  Future<int> createCommission(CommissionsCompanion companion) {
    return into(commissions).insert(companion);
  }

  /// Update a commission
  Future<bool> updateCommission(Commission commission) {
    return update(commissions).replace(commission);
  }

  /// Get sales statistics for an employee within a date range.
  ///
  /// Returns: {salesCount, salesTotalCents, returnsCount, returnsTotalCents}
  ///
  /// Aggregates from **all** salesperson-attribution paths supported by the
  /// sales engine — keeping this query as the single source of truth that
  /// both the employee detail screen and the target-bonus calculation in
  /// `EmployeeDetailBloc._onSettleAccount` consume:
  ///
  /// **Sales**
  /// * Per-invoice mode — `sales.employee_id = ?` → credit the full
  ///   `sales.total_cents` to this employee for that sale.
  /// * Per-item mode — `sales.employee_id IS NULL` and one or more
  ///   `sale_items.employee_id = ?` → credit the sum of those items'
  ///   `sale_items.total_cents`. Same distinct sale only counts once.
  ///
  /// **Returns** (both linked and adjustment / unlinked are included)
  /// * Linked return on a per-invoice-mode sale → full `sale_returns.total_cents`.
  /// * Linked return on a per-item-mode sale → sum of
  ///   `sale_return_items.refund_cents` whose originating sale item is
  ///   assigned to this employee.
  /// * Adjustment return — `sale_return_adjustments.employee_id = ?` →
  ///   full `sale_return_adjustments.total_cents`.
  ///
  /// Voided rows (`status = 'voided'`) are excluded across every path.
  /// The per-invoice and per-item branches use mutually exclusive
  /// `employee_id IS NULL` / `IS NOT NULL` predicates on the header,
  /// matching the commission attribution rule in `SaleRepositoryImpl`,
  /// so the same sale can never be credited twice.
  Future<Map<String, int>> getEmployeeSalesStats(
    int employeeId,
    DateTime periodStart,
    DateTime periodEnd,
  ) async {
    final salesResult = await customSelect(
      '''
      SELECT
        COUNT(*) AS sales_count,
        COALESCE(SUM(contribution_cents), 0) AS sales_total
      FROM (
        -- Per-invoice mode: the whole sale is credited to the header employee.
        SELECT s.id AS sale_id, s.total_cents AS contribution_cents
        FROM sales s
        WHERE s.employee_id = ?
          AND s.sale_date >= ?
          AND s.sale_date <= ?
          AND s.status != 'voided'
        UNION ALL
        -- Per-item mode: header is NULL, sum only this employee's line items.
        SELECT s.id AS sale_id,
               COALESCE(SUM(si.total_cents), 0) AS contribution_cents
        FROM sales s
        INNER JOIN sale_items si ON si.sale_id = s.id
        WHERE s.employee_id IS NULL
          AND si.employee_id = ?
          AND s.sale_date >= ?
          AND s.sale_date <= ?
          AND s.status != 'voided'
        GROUP BY s.id
        HAVING SUM(si.total_cents) > 0
      )
      ''',
      variables: [
        Variable.withInt(employeeId),
        Variable.withDateTime(periodStart),
        Variable.withDateTime(periodEnd),
        Variable.withInt(employeeId),
        Variable.withDateTime(periodStart),
        Variable.withDateTime(periodEnd),
      ],
    ).getSingleOrNull();

    final returnsResult = await customSelect(
      '''
      SELECT
        COUNT(*) AS returns_count,
        COALESCE(SUM(contribution_cents), 0) AS returns_total
      FROM (
        -- A) Linked return on per-invoice-mode sale: full return total.
        SELECT sr.id AS ref_id, sr.total_cents AS contribution_cents
        FROM sale_returns sr
        INNER JOIN sales s ON s.id = sr.sale_id
        WHERE s.employee_id = ?
          AND sr.return_date >= ?
          AND sr.return_date <= ?
          AND sr.status != 'voided'
        UNION ALL
        -- B) Linked return on per-item-mode sale: sum only this employee's
        --    return lines (via the original sale_items.employee_id link).
        SELECT sr.id AS ref_id,
               COALESCE(SUM(sri.refund_cents), 0) AS contribution_cents
        FROM sale_returns sr
        INNER JOIN sales s ON s.id = sr.sale_id
        INNER JOIN sale_return_items sri ON sri.return_id = sr.id
        INNER JOIN sale_items si ON si.id = sri.sale_item_id
        WHERE s.employee_id IS NULL
          AND si.employee_id = ?
          AND sr.return_date >= ?
          AND sr.return_date <= ?
          AND sr.status != 'voided'
        GROUP BY sr.id
        HAVING SUM(sri.refund_cents) > 0
        UNION ALL
        -- C) Adjustment (unlinked) return: header employee_id.
        SELECT sra.id AS ref_id, sra.total_cents AS contribution_cents
        FROM sale_return_adjustments sra
        WHERE sra.employee_id = ?
          AND sra.return_date >= ?
          AND sra.return_date <= ?
          AND sra.status != 'voided'
      )
      ''',
      variables: [
        Variable.withInt(employeeId),
        Variable.withDateTime(periodStart),
        Variable.withDateTime(periodEnd),
        Variable.withInt(employeeId),
        Variable.withDateTime(periodStart),
        Variable.withDateTime(periodEnd),
        Variable.withInt(employeeId),
        Variable.withDateTime(periodStart),
        Variable.withDateTime(periodEnd),
      ],
    ).getSingleOrNull();

    return {
      'salesCount': salesResult?.read<int>('sales_count') ?? 0,
      'salesTotalCents': salesResult?.read<int>('sales_total') ?? 0,
      'returnsCount': returnsResult?.read<int>('returns_count') ?? 0,
      'returnsTotalCents': returnsResult?.read<int>('returns_total') ?? 0,
    };
  }

  /// Get all commissions linked to a specific sale
  Future<List<Commission>> getCommissionsBySaleId(int saleId) {
    return (select(commissions)..where((c) => c.saleId.equals(saleId))).get();
  }

  /// Delete all commissions linked to a specific sale
  Future<int> deleteCommissionsBySaleId(int saleId) {
    return (delete(commissions)..where((c) => c.saleId.equals(saleId))).go();
  }

  /// Get total commission for an employee in a period
  Future<int> getTotalCommissionCents(int employeeId, String period) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(commission_amount_cents), 0) as total FROM commissions WHERE employee_id = ? AND period = ?',
      variables: [Variable.withInt(employeeId), Variable.withString(period)],
    ).getSingleOrNull();

    return result?.readNullable<int>('total') ?? 0;
  }

  // ==================== PERFORMANCE ====================

  /// Watch performance metrics for an employee
  Stream<List<PerformanceMetric>> watchEmployeePerformance(
    int employeeId, {
    String? metricType,
    String? period,
  }) {
    var query = select(performanceMetrics)
      ..where((p) => p.employeeId.equals(employeeId));

    if (metricType != null) {
      query = query..where((p) => p.metricType.equals(metricType));
    }
    if (period != null) {
      query = query..where((p) => p.period.equals(period));
    }

    return (query..orderBy([(p) => OrderingTerm.desc(p.recordedAt)])).watch();
  }

  /// Create a new performance metric
  Future<int> createPerformanceMetric(PerformanceMetricsCompanion companion) {
    return into(performanceMetrics).insert(companion);
  }

  /// Get average performance score for an employee
  Future<double?> getAveragePerformanceScore(
    int employeeId, {
    String? period,
  }) async {
    String sql =
        'SELECT AVG(metric_value) as avg_score FROM performance_metrics WHERE employee_id = ?';
    final variables = <Variable>[Variable.withInt(employeeId)];

    if (period != null) {
      sql += ' AND period = ?';
      variables.add(Variable.withString(period));
    }

    final result = await customSelect(sql, variables: variables).getSingleOrNull();
    return result?.read<double?>('avg_score');
  }
}
