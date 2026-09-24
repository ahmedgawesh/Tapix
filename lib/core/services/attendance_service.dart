import '../database/daos/employee_dao.dart';

/// Service to manage automatic attendance creation for active employees.
/// Respects each employee's hireDate and weeklyOffDays configuration.
class AttendanceService {
  final EmployeeDao _dao;

  AttendanceService(this._dao);

  /// Previously auto-generated attendance records (absent/leave) for all
  /// active employees. Now disabled — attendance must be recorded manually
  /// by the manager via check-in, check-out, mark absent, etc.
  /// Kept as a no-op to avoid breaking callers.
  Future<void> generateDailyAttendance(DateTime date) async {
    // No-op: attendance is now fully manual.
    // The manager must record check-in/check-out/absent/leave for each employee.
    return;
  }

  /// Generate attendance for a date range (useful for backfilling a month).
  Future<void> generateAttendanceRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    var current = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    while (!current.isAfter(end)) {
      await generateDailyAttendance(current);
      current = current.add(const Duration(days: 1));
    }
  }

  /// Check if attendance exists for an employee on a specific date.
  Future<bool> hasAttendanceRecord(int employeeId, DateTime date) async {
    final attendance = await _dao.getAttendance(employeeId, date);
    return attendance != null;
  }

  /// Get attendance statistics for a date.
  Future<Map<String, int>> getAttendanceStats(DateTime date) async {
    final counts = await _dao.watchAttendanceCountsByDate(date).first;
    return counts;
  }
}
