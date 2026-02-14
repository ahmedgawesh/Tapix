import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';
import 'transactions.dart';
import 'users.dart';

/// Roles table for role-based permissions
@DataClassName('Role')
class Roles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
  TextColumn get nameAr => text().nullable()();
  TextColumn get nameFr => text().nullable()();
  TextColumn get description => text().nullable()();
  /// JSON array of permission strings (e.g., ["employees.view", "employees.create"])
  TextColumn get permissions => text().withDefault(const Constant('[]'))();
  BoolColumn get isSystemRole => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Employee')
class Employees extends Table {
  IntColumn get id => integer().autoIncrement()();
  /// Unique employee code (e.g., EMP001)
  TextColumn get employeeCode => text().unique().nullable()();
  /// Link to users table for system access
  IntColumn get userId => integer().nullable().references(Users, #id, onDelete: KeyAction.setNull)();
  TextColumn get name => text()();
  TextColumn get nameAr => text().nullable()();
  TextColumn get nameFr => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get position => text().nullable()();
  TextColumn get department => text().nullable()();
  /// Role for permissions
  IntColumn get roleId => integer().nullable().references(Roles, #id, onDelete: KeyAction.setNull)();
  /// Manager (self-referencing for hierarchy)
  IntColumn get managerId => integer().nullable()();
  IntColumn get salaryCents => integer().map(const MoneyConverter()).nullable()();
  /// Default commission rate in basis points (e.g., 500 = 5%)
  IntColumn get defaultCommissionRateBps => integer().withDefault(const Constant(0))();
  /// Fixed commission amount in cents (used when commission type is 'fixed')
  IntColumn get fixedCommissionCents => integer().map(const MoneyConverter()).nullable()();
  /// Commission type: 'percentage' or 'fixed'
  TextColumn get commissionType => text().withDefault(const Constant('percentage'))();
  /// Monthly sales target in cents
  IntColumn get salesTargetCents => integer().map(const MoneyConverter()).nullable()();
  /// Bonus amount in cents when sales target is achieved
  IntColumn get targetBonusCents => integer().map(const MoneyConverter()).nullable()();
  /// Target period: monthly, quarterly, yearly
  TextColumn get targetPeriod => text().withDefault(const Constant('monthly'))();
  /// Pay period type: monthly, weekly, daily
  TextColumn get payPeriodType => text().withDefault(const Constant('monthly'))();
  /// Working days per pay period (e.g., 26 for monthly)
  IntColumn get workingDaysPerPeriod => integer().withDefault(const Constant(26))();
  /// Working hours per day (e.g., 8)
  IntColumn get workingHoursPerDay => integer().withDefault(const Constant(8))();
  /// Absence deduction rate in basis points (10000 = 100% of daily rate)
  IntColumn get absenceDeductionRateBps => integer().withDefault(const Constant(10000))();
  /// Late deduction rate in basis points (2500 = 25% of daily rate)
  IntColumn get lateDeductionRateBps => integer().withDefault(const Constant(2500))();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get hireDate => dateTime().nullable()();
  DateTimeColumn get terminationDate => dateTime().nullable()();
  /// JSON array of weekly off-day numbers (1=Mon..7=Sun), e.g. "[5,6]" for Fri+Sat
  TextColumn get weeklyOffDays => text().withDefault(const Constant('[5,6]'))();
  /// Annual leave allowance in days
  IntColumn get annualLeaveDays => integer().withDefault(const Constant(21))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Commission')
class Commissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id, onDelete: KeyAction.cascade)();
  IntColumn get saleId => integer().nullable().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get commissionRateBps => integer().map(const BasisPointsConverter())();
  IntColumn get commissionAmountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  /// Period for commission (e.g., "2026-01" for January 2026)
  TextColumn get period => text().nullable()();
  /// Status: pending, approved, paid
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Attendance tracking table
@DataClassName('Attendance')
class Attendances extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id, onDelete: KeyAction.cascade)();
  /// Date of attendance (stored as date only)
  DateTimeColumn get attendanceDate => dateTime()();
  /// Check-in time
  DateTimeColumn get checkInTime => dateTime().nullable()();
  /// Check-out time
  DateTimeColumn get checkOutTime => dateTime().nullable()();
  /// Status: present, late, absent, leave, holiday
  TextColumn get status => text().withDefault(const Constant('present'))();
  /// Check-in method: manual, biometric, mobile, web, gps
  TextColumn get checkInMethod => text().nullable()();
  /// Location for GPS check-in
  TextColumn get location => text().nullable()();
  /// Overtime minutes worked
  IntColumn get overtimeMinutes => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  /// Approved by manager
  IntColumn get approvedBy => integer().nullable().references(Employees, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {employeeId, attendanceDate},
  ];
}

/// Leave requests table
@DataClassName('LeaveRequest')
class LeaveRequests extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id, onDelete: KeyAction.cascade)();
  /// Leave type: annual, sick, personal, unpaid, maternity, paternity
  TextColumn get leaveType => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  IntColumn get daysCount => integer()();
  TextColumn get reason => text().nullable()();
  /// Status: pending, approved, rejected, cancelled
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get approvedBy => integer().nullable().references(Employees, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  TextColumn get rejectionReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Payroll records table
@DataClassName('Payroll')
class Payrolls extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id, onDelete: KeyAction.cascade)();
  /// Period start date
  DateTimeColumn get periodStart => dateTime()();
  /// Period end date
  DateTimeColumn get periodEnd => dateTime()();
  /// Basic salary in cents
  IntColumn get basicSalaryCents => integer().map(const MoneyConverter())();
  /// Total commission in cents
  IntColumn get commissionCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Bonus in cents
  IntColumn get bonusCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Overtime pay in cents
  IntColumn get overtimeCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Total deductions in cents (taxes, loans, advances, penalties)
  IntColumn get deductionCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// Net pay in cents
  IntColumn get netPayCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  /// Status: draft, pending, approved, processed, paid
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get processedAt => dateTime().nullable()();
  TextColumn get bankReference => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Payroll deductions breakdown
@DataClassName('PayrollDeduction')
class PayrollDeductions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get payrollId => integer().references(Payrolls, #id, onDelete: KeyAction.cascade)();
  /// Deduction type: tax, loan, advance, penalty, insurance, other
  TextColumn get deductionType => text()();
  TextColumn get description => text().nullable()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Shift schedules table
@DataClassName('ShiftSchedule')
class ShiftSchedules extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get shiftDate => dateTime()();
  /// Shift start time (stored as DateTime for time component)
  DateTimeColumn get startTime => dateTime()();
  /// Shift end time
  DateTimeColumn get endTime => dateTime()();
  /// Shift type: morning, evening, night, split
  TextColumn get shiftType => text().withDefault(const Constant('morning'))();
  TextColumn get location => text().nullable()();
  /// Status: scheduled, completed, absent, swapped
  TextColumn get status => text().withDefault(const Constant('scheduled'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {employeeId, shiftDate},
  ];
}

/// Employee documents table
@DataClassName('EmployeeDocument')
class EmployeeDocuments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id, onDelete: KeyAction.cascade)();
  /// Document type: contract, id_card, medical, certificate, other
  TextColumn get documentType => text()();
  TextColumn get documentName => text()();
  TextColumn get filePath => text()();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get mimeType => text().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get uploadedBy => integer().nullable().references(Users, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Overtime rules table
@DataClassName('OvertimeRule')
class OvertimeRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get ruleName => text()();
  /// Daily hours threshold before overtime kicks in
  RealColumn get dailyHoursThreshold => real().withDefault(const Constant(8.0))();
  /// Weekly hours threshold
  RealColumn get weeklyHoursThreshold => real().withDefault(const Constant(40.0))();
  /// Overtime rate multiplier for first tier (e.g., 1.25 = 125%)
  RealColumn get overtimeRate1x => real().withDefault(const Constant(1.25))();
  /// Overtime rate for second tier
  RealColumn get overtimeRate2x => real().withDefault(const Constant(1.5))();
  /// Overtime rate for third tier
  RealColumn get overtimeRate3x => real().withDefault(const Constant(2.0))();
  /// Weekend rate multiplier
  RealColumn get weekendRate => real().withDefault(const Constant(2.0))();
  /// Holiday rate multiplier
  RealColumn get holidayRate => real().withDefault(const Constant(3.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Performance metrics table
@DataClassName('PerformanceMetric')
class PerformanceMetrics extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id, onDelete: KeyAction.cascade)();
  /// Metric type: sales, customer_satisfaction, attendance, goals
  TextColumn get metricType => text()();
  RealColumn get metricValue => real()();
  RealColumn get targetValue => real().nullable()();
  /// Period: daily, weekly, monthly, quarterly, yearly
  TextColumn get period => text()();
  /// Period identifier (e.g., "2026-01" for monthly, "2026-Q1" for quarterly)
  TextColumn get periodIdentifier => text()();
  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get recordedBy => integer().nullable().references(Users, #id, onDelete: KeyAction.setNull)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

