import 'package:equatable/equatable.dart';

/// Enum for attendance status
enum AttendanceStatus {
  present,
  late,
  absent,
  leave,
  holiday,
  // ignore: constant_identifier_names
  early_departure;

  String get displayName {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.leave:
        return 'On Leave';
      case AttendanceStatus.holiday:
        return 'Holiday';
      case AttendanceStatus.early_departure:
        return 'Early Departure';
    }
  }

  static AttendanceStatus fromString(String value) {
    return AttendanceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AttendanceStatus.present,
    );
  }
}

/// Enum for leave request status
enum LeaveRequestStatus {
  pending,
  approved,
  rejected,
  cancelled;

  String get displayName {
    switch (this) {
      case LeaveRequestStatus.pending:
        return 'Pending';
      case LeaveRequestStatus.approved:
        return 'Approved';
      case LeaveRequestStatus.rejected:
        return 'Rejected';
      case LeaveRequestStatus.cancelled:
        return 'Cancelled';
    }
  }

  static LeaveRequestStatus fromString(String value) {
    return LeaveRequestStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => LeaveRequestStatus.pending,
    );
  }
}

/// Enum for leave types
enum LeaveType {
  annual,
  sick,
  personal,
  unpaid,
  maternity,
  paternity;

  String get displayName {
    switch (this) {
      case LeaveType.annual:
        return 'Annual Leave';
      case LeaveType.sick:
        return 'Sick Leave';
      case LeaveType.personal:
        return 'Personal Leave';
      case LeaveType.unpaid:
        return 'Unpaid Leave';
      case LeaveType.maternity:
        return 'Maternity Leave';
      case LeaveType.paternity:
        return 'Paternity Leave';
    }
  }

  static LeaveType fromString(String value) {
    return LeaveType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => LeaveType.annual,
    );
  }
}

/// Enum for payroll status
enum PayrollStatus {
  draft,
  pending,
  approved,
  processed,
  paid;

  String get displayName {
    switch (this) {
      case PayrollStatus.draft:
        return 'Draft';
      case PayrollStatus.pending:
        return 'Pending';
      case PayrollStatus.approved:
        return 'Approved';
      case PayrollStatus.processed:
        return 'Processed';
      case PayrollStatus.paid:
        return 'Paid';
    }
  }

  static PayrollStatus fromString(String value) {
    return PayrollStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PayrollStatus.draft,
    );
  }
}

/// Enum for commission status
enum CommissionStatus {
  pending,
  approved,
  paid;

  String get displayName {
    switch (this) {
      case CommissionStatus.pending:
        return 'Pending';
      case CommissionStatus.approved:
        return 'Approved';
      case CommissionStatus.paid:
        return 'Paid';
    }
  }

  static CommissionStatus fromString(String value) {
    return CommissionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => CommissionStatus.pending,
    );
  }
}

/// Employee entity for domain layer
class EmployeeEntity extends Equatable {
  final int id;
  final String? employeeCode;
  final int? userId;
  final String name;
  final String? nameAr;
  final String? nameFr;
  final String? email;
  final String? phone;
  final String? position;
  final String? department;
  final int? roleId;
  final int? managerId;
  final int? salaryCents;
  final int defaultCommissionRateBps;
  final int currencyId;
  final bool isActive;
  final DateTime? hireDate;
  final DateTime? terminationDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EmployeeEntity({
    required this.id,
    this.employeeCode,
    this.userId,
    required this.name,
    this.nameAr,
    this.nameFr,
    this.email,
    this.phone,
    this.position,
    this.department,
    this.roleId,
    this.managerId,
    this.salaryCents,
    this.defaultCommissionRateBps = 0,
    required this.currencyId,
    this.isActive = true,
    this.hireDate,
    this.terminationDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Get salary in decimal format
  double get salaryAmount => (salaryCents ?? 0) / 100;

  /// Get commission rate as percentage
  double get commissionRatePercent => defaultCommissionRateBps / 100;

  /// Check if employee is terminated
  bool get isTerminated => terminationDate != null;

  /// Get years of service
  int get yearsOfService {
    if (hireDate == null) return 0;
    final endDate = terminationDate ?? DateTime.now();
    return endDate.difference(hireDate!).inDays ~/ 365;
  }

  EmployeeEntity copyWith({
    int? id,
    String? employeeCode,
    int? userId,
    String? name,
    String? nameAr,
    String? nameFr,
    String? email,
    String? phone,
    String? position,
    String? department,
    int? roleId,
    int? managerId,
    int? salaryCents,
    int? defaultCommissionRateBps,
    int? currencyId,
    bool? isActive,
    DateTime? hireDate,
    DateTime? terminationDate,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeEntity(
      id: id ?? this.id,
      employeeCode: employeeCode ?? this.employeeCode,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      nameFr: nameFr ?? this.nameFr,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      position: position ?? this.position,
      department: department ?? this.department,
      roleId: roleId ?? this.roleId,
      managerId: managerId ?? this.managerId,
      salaryCents: salaryCents ?? this.salaryCents,
      defaultCommissionRateBps:
          defaultCommissionRateBps ?? this.defaultCommissionRateBps,
      currencyId: currencyId ?? this.currencyId,
      isActive: isActive ?? this.isActive,
      hireDate: hireDate ?? this.hireDate,
      terminationDate: terminationDate ?? this.terminationDate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    employeeCode,
    userId,
    name,
    nameAr,
    nameFr,
    email,
    phone,
    position,
    department,
    roleId,
    managerId,
    salaryCents,
    defaultCommissionRateBps,
    currencyId,
    isActive,
    hireDate,
    terminationDate,
    notes,
    createdAt,
    updatedAt,
  ];
}

/// Role entity for domain layer
class RoleEntity extends Equatable {
  final int id;
  final String name;
  final String? nameAr;
  final String? nameFr;
  final String? description;
  final List<String> permissions;
  final bool isSystemRole;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleEntity({
    required this.id,
    required this.name,
    this.nameAr,
    this.nameFr,
    this.description,
    this.permissions = const [],
    this.isSystemRole = false,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  RoleEntity copyWith({
    int? id,
    String? name,
    String? nameAr,
    String? nameFr,
    String? description,
    List<String>? permissions,
    bool? isSystemRole,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoleEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      nameAr: nameAr ?? this.nameAr,
      nameFr: nameFr ?? this.nameFr,
      description: description ?? this.description,
      permissions: permissions ?? this.permissions,
      isSystemRole: isSystemRole ?? this.isSystemRole,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    nameAr,
    nameFr,
    description,
    permissions,
    isSystemRole,
    isActive,
    createdAt,
    updatedAt,
  ];
}

/// Attendance entity for domain layer
class AttendanceEntity extends Equatable {
  final int id;
  final int employeeId;
  final DateTime attendanceDate;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final AttendanceStatus status;
  final String? checkInMethod;
  final String? location;
  final int overtimeMinutes;
  final String? notes;
  final int? approvedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AttendanceEntity({
    required this.id,
    required this.employeeId,
    required this.attendanceDate,
    this.checkInTime,
    this.checkOutTime,
    this.status = AttendanceStatus.present,
    this.checkInMethod,
    this.location,
    this.overtimeMinutes = 0,
    this.notes,
    this.approvedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Calculate hours worked
  double get hoursWorked {
    if (checkInTime == null || checkOutTime == null) return 0;
    return checkOutTime!.difference(checkInTime!).inMinutes / 60;
  }

  /// Get overtime hours
  double get overtimeHours => overtimeMinutes / 60;

  AttendanceEntity copyWith({
    int? id,
    int? employeeId,
    DateTime? attendanceDate,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    AttendanceStatus? status,
    String? checkInMethod,
    String? location,
    int? overtimeMinutes,
    String? notes,
    int? approvedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AttendanceEntity(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      attendanceDate: attendanceDate ?? this.attendanceDate,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      status: status ?? this.status,
      checkInMethod: checkInMethod ?? this.checkInMethod,
      location: location ?? this.location,
      overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
      notes: notes ?? this.notes,
      approvedBy: approvedBy ?? this.approvedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    employeeId,
    attendanceDate,
    checkInTime,
    checkOutTime,
    status,
    checkInMethod,
    location,
    overtimeMinutes,
    notes,
    approvedBy,
    createdAt,
    updatedAt,
  ];
}

/// Leave request entity for domain layer
class LeaveRequestEntity extends Equatable {
  final int id;
  final int employeeId;
  final LeaveType leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final int daysCount;
  final String? reason;
  final LeaveRequestStatus status;
  final int? approvedBy;
  final DateTime? approvedAt;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LeaveRequestEntity({
    required this.id,
    required this.employeeId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.daysCount,
    this.reason,
    this.status = LeaveRequestStatus.pending,
    this.approvedBy,
    this.approvedAt,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Check if leave request is pending
  bool get isPending => status == LeaveRequestStatus.pending;

  /// Check if leave request is approved
  bool get isApproved => status == LeaveRequestStatus.approved;

  LeaveRequestEntity copyWith({
    int? id,
    int? employeeId,
    LeaveType? leaveType,
    DateTime? startDate,
    DateTime? endDate,
    int? daysCount,
    String? reason,
    LeaveRequestStatus? status,
    int? approvedBy,
    DateTime? approvedAt,
    String? rejectionReason,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LeaveRequestEntity(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      leaveType: leaveType ?? this.leaveType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      daysCount: daysCount ?? this.daysCount,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    employeeId,
    leaveType,
    startDate,
    endDate,
    daysCount,
    reason,
    status,
    approvedBy,
    approvedAt,
    rejectionReason,
    createdAt,
    updatedAt,
  ];
}

/// Payroll entity for domain layer
class PayrollEntity extends Equatable {
  final int id;
  final int employeeId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int basicSalaryCents;
  final int commissionCents;
  final int bonusCents;
  final int overtimeCents;
  final int deductionCents;
  final int netPayCents;
  final int currencyId;
  final PayrollStatus status;
  final DateTime? processedAt;
  final String? bankReference;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PayrollEntity({
    required this.id,
    required this.employeeId,
    required this.periodStart,
    required this.periodEnd,
    required this.basicSalaryCents,
    this.commissionCents = 0,
    this.bonusCents = 0,
    this.overtimeCents = 0,
    this.deductionCents = 0,
    required this.netPayCents,
    required this.currencyId,
    this.status = PayrollStatus.draft,
    this.processedAt,
    this.bankReference,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Get basic salary amount
  double get basicSalaryAmount => basicSalaryCents / 100;

  /// Get commission amount
  double get commissionAmount => commissionCents / 100;

  /// Get bonus amount
  double get bonusAmount => bonusCents / 100;

  /// Get overtime amount
  double get overtimeAmount => overtimeCents / 100;

  /// Get deduction amount
  double get deductionAmount => deductionCents / 100;

  /// Get net pay amount
  double get netPayAmount => netPayCents / 100;

  /// Get total gross (before deductions)
  int get totalGrossCents =>
      basicSalaryCents + commissionCents + bonusCents + overtimeCents;

  /// Get total gross amount
  double get totalGrossAmount => totalGrossCents / 100;

  /// Get period string (e.g., "2026-02")
  String get periodString {
    final year = periodStart.year;
    final month = periodStart.month.toString().padLeft(2, '0');
    return '$year-$month';
  }

  PayrollEntity copyWith({
    int? id,
    int? employeeId,
    DateTime? periodStart,
    DateTime? periodEnd,
    int? basicSalaryCents,
    int? commissionCents,
    int? bonusCents,
    int? overtimeCents,
    int? deductionCents,
    int? netPayCents,
    int? currencyId,
    PayrollStatus? status,
    DateTime? processedAt,
    String? bankReference,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PayrollEntity(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      basicSalaryCents: basicSalaryCents ?? this.basicSalaryCents,
      commissionCents: commissionCents ?? this.commissionCents,
      bonusCents: bonusCents ?? this.bonusCents,
      overtimeCents: overtimeCents ?? this.overtimeCents,
      deductionCents: deductionCents ?? this.deductionCents,
      netPayCents: netPayCents ?? this.netPayCents,
      currencyId: currencyId ?? this.currencyId,
      status: status ?? this.status,
      processedAt: processedAt ?? this.processedAt,
      bankReference: bankReference ?? this.bankReference,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    employeeId,
    periodStart,
    periodEnd,
    basicSalaryCents,
    commissionCents,
    bonusCents,
    overtimeCents,
    deductionCents,
    netPayCents,
    currencyId,
    status,
    processedAt,
    bankReference,
    notes,
    createdAt,
    updatedAt,
  ];
}

/// Commission entity for domain layer
class CommissionEntity extends Equatable {
  final int id;
  final int employeeId;
  final int? saleId;
  final int commissionRateBps;
  final int commissionAmountCents;
  final int currencyId;
  final String? period;
  final CommissionStatus status;
  final DateTime createdAt;

  const CommissionEntity({
    required this.id,
    required this.employeeId,
    this.saleId,
    required this.commissionRateBps,
    required this.commissionAmountCents,
    required this.currencyId,
    this.period,
    this.status = CommissionStatus.pending,
    required this.createdAt,
  });

  /// Get commission rate as percentage
  double get commissionRatePercent => commissionRateBps / 100;

  /// Get commission amount
  double get commissionAmount => commissionAmountCents / 100;

  CommissionEntity copyWith({
    int? id,
    int? employeeId,
    int? saleId,
    int? commissionRateBps,
    int? commissionAmountCents,
    int? currencyId,
    String? period,
    CommissionStatus? status,
    DateTime? createdAt,
  }) {
    return CommissionEntity(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      saleId: saleId ?? this.saleId,
      commissionRateBps: commissionRateBps ?? this.commissionRateBps,
      commissionAmountCents:
          commissionAmountCents ?? this.commissionAmountCents,
      currencyId: currencyId ?? this.currencyId,
      period: period ?? this.period,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    employeeId,
    saleId,
    commissionRateBps,
    commissionAmountCents,
    currencyId,
    period,
    status,
    createdAt,
  ];
}

/// Performance metric entity for domain layer
class PerformanceMetricEntity extends Equatable {
  final int id;
  final int employeeId;
  final String metricType;
  final double metricValue;
  final double? targetValue;
  final String period;
  final String periodIdentifier;
  final DateTime recordedAt;
  final int? recordedBy;
  final DateTime createdAt;

  const PerformanceMetricEntity({
    required this.id,
    required this.employeeId,
    required this.metricType,
    required this.metricValue,
    this.targetValue,
    required this.period,
    required this.periodIdentifier,
    required this.recordedAt,
    this.recordedBy,
    required this.createdAt,
  });

  /// Get achievement percentage
  double? get achievementPercent {
    if (targetValue == null || targetValue == 0) return null;
    return (metricValue / targetValue!) * 100;
  }

  /// Check if target is met
  bool get isTargetMet {
    if (targetValue == null) return true;
    return metricValue >= targetValue!;
  }

  PerformanceMetricEntity copyWith({
    int? id,
    int? employeeId,
    String? metricType,
    double? metricValue,
    double? targetValue,
    String? period,
    String? periodIdentifier,
    DateTime? recordedAt,
    int? recordedBy,
    DateTime? createdAt,
  }) {
    return PerformanceMetricEntity(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      metricType: metricType ?? this.metricType,
      metricValue: metricValue ?? this.metricValue,
      targetValue: targetValue ?? this.targetValue,
      period: period ?? this.period,
      periodIdentifier: periodIdentifier ?? this.periodIdentifier,
      recordedAt: recordedAt ?? this.recordedAt,
      recordedBy: recordedBy ?? this.recordedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    employeeId,
    metricType,
    metricValue,
    targetValue,
    period,
    periodIdentifier,
    recordedAt,
    recordedBy,
    createdAt,
  ];
}

/// Employee with role for display purposes
class EmployeeWithRole {
  final EmployeeEntity employee;
  final RoleEntity? role;
  final EmployeeEntity? manager;

  const EmployeeWithRole({required this.employee, this.role, this.manager});
}

/// Attendance summary for a date
class AttendanceSummary {
  final DateTime? date;
  final int presentCount;
  final int lateCount;
  final int absentCount;
  final int onLeaveCount;

  const AttendanceSummary({
    this.date,
    this.presentCount = 0,
    this.lateCount = 0,
    this.absentCount = 0,
    this.onLeaveCount = 0,
  });

  int get totalCount => presentCount + lateCount + absentCount + onLeaveCount;
}

/// Payroll summary for a period
class PayrollSummary {
  final String period;
  final int totalGrossCents;
  final int totalDeductionsCents;
  final int totalNetCents;
  final int employeeCount;
  final int paidCount;
  final int unpaidCount;
  final int totalPaidCents;
  final int totalUnpaidCents;

  const PayrollSummary({
    required this.period,
    this.totalGrossCents = 0,
    this.totalDeductionsCents = 0,
    this.totalNetCents = 0,
    this.employeeCount = 0,
    this.paidCount = 0,
    this.unpaidCount = 0,
    this.totalPaidCents = 0,
    this.totalUnpaidCents = 0,
  });

  double get totalGrossAmount => totalGrossCents / 100;
  double get totalDeductionsAmount => totalDeductionsCents / 100;
  double get totalNetAmount => totalNetCents / 100;
}
