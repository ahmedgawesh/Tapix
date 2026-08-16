// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee_dao.dart';

// ignore_for_file: type=lint
mixin _$EmployeeDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $RolesTable get roles => attachedDatabase.roles;
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $EmployeesTable get employees => attachedDatabase.employees;
  $AttendancesTable get attendances => attachedDatabase.attendances;
  $LeaveRequestsTable get leaveRequests => attachedDatabase.leaveRequests;
  $PayrollsTable get payrolls => attachedDatabase.payrolls;
  $PayrollDeductionsTable get payrollDeductions =>
      attachedDatabase.payrollDeductions;
  $LoyaltyTiersTable get loyaltyTiers => attachedDatabase.loyaltyTiers;
  $CustomersTable get customers => attachedDatabase.customers;
  $CashierShiftsTable get cashierShifts => attachedDatabase.cashierShifts;
  $SalesTable get sales => attachedDatabase.sales;
  $CommissionsTable get commissions => attachedDatabase.commissions;
  $PerformanceMetricsTable get performanceMetrics =>
      attachedDatabase.performanceMetrics;
  $ShiftSchedulesTable get shiftSchedules => attachedDatabase.shiftSchedules;
  $EmployeeDocumentsTable get employeeDocuments =>
      attachedDatabase.employeeDocuments;
  $OvertimeRulesTable get overtimeRules => attachedDatabase.overtimeRules;
  EmployeeDaoManager get managers => EmployeeDaoManager(this);
}

class EmployeeDaoManager {
  final _$EmployeeDaoMixin _db;
  EmployeeDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$RolesTableTableManager get roles =>
      $$RolesTableTableManager(_db.attachedDatabase, _db.roles);
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$EmployeesTableTableManager get employees =>
      $$EmployeesTableTableManager(_db.attachedDatabase, _db.employees);
  $$AttendancesTableTableManager get attendances =>
      $$AttendancesTableTableManager(_db.attachedDatabase, _db.attendances);
  $$LeaveRequestsTableTableManager get leaveRequests =>
      $$LeaveRequestsTableTableManager(_db.attachedDatabase, _db.leaveRequests);
  $$PayrollsTableTableManager get payrolls =>
      $$PayrollsTableTableManager(_db.attachedDatabase, _db.payrolls);
  $$PayrollDeductionsTableTableManager get payrollDeductions =>
      $$PayrollDeductionsTableTableManager(
        _db.attachedDatabase,
        _db.payrollDeductions,
      );
  $$LoyaltyTiersTableTableManager get loyaltyTiers =>
      $$LoyaltyTiersTableTableManager(_db.attachedDatabase, _db.loyaltyTiers);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$CashierShiftsTableTableManager get cashierShifts =>
      $$CashierShiftsTableTableManager(_db.attachedDatabase, _db.cashierShifts);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$CommissionsTableTableManager get commissions =>
      $$CommissionsTableTableManager(_db.attachedDatabase, _db.commissions);
  $$PerformanceMetricsTableTableManager get performanceMetrics =>
      $$PerformanceMetricsTableTableManager(
        _db.attachedDatabase,
        _db.performanceMetrics,
      );
  $$ShiftSchedulesTableTableManager get shiftSchedules =>
      $$ShiftSchedulesTableTableManager(
        _db.attachedDatabase,
        _db.shiftSchedules,
      );
  $$EmployeeDocumentsTableTableManager get employeeDocuments =>
      $$EmployeeDocumentsTableTableManager(
        _db.attachedDatabase,
        _db.employeeDocuments,
      );
  $$OvertimeRulesTableTableManager get overtimeRules =>
      $$OvertimeRulesTableTableManager(_db.attachedDatabase, _db.overtimeRules);
}
