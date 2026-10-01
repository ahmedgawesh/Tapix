import 'package:equatable/equatable.dart';

enum UserRole {
  owner,
  manager,
  accountant,
  cashier,
  warehouseClerk,
  salesperson;

  static UserRole fromString(String value) {
    String normalize(String role) => role
        .trim()
        .toLowerCase()
        .replaceAll('_', '')
        .replaceAll('-', '')
        .replaceAll(' ', '');
    final normalizedValue = normalize(value);
    return UserRole.values.firstWhere(
      (e) => normalize(e.name) == normalizedValue,
      orElse: () => UserRole.salesperson,
    );
  }

  String get displayName {
    switch (this) {
      case UserRole.owner:
        return 'Owner';
      case UserRole.manager:
        return 'Manager';
      case UserRole.accountant:
        return 'Accountant';
      case UserRole.cashier:
        return 'Cashier';
      case UserRole.warehouseClerk:
        return 'Warehouse Clerk';
      case UserRole.salesperson:
        return 'Salesperson';
    }
  }
}

class UserEntity extends Equatable {
  final int id;
  final String username;
  final UserRole role;
  final int? employeeId;
  final String? branchId;
  final String? warehouseId;
  final bool hasGlobalLocationAccess;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;

  const UserEntity({
    required this.id,
    required this.username,
    required this.role,
    this.employeeId,
    this.branchId,
    this.warehouseId,
    this.hasGlobalLocationAccess = false,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
  });

  bool get isOwner => role == UserRole.owner;
  bool get isManager => role == UserRole.manager;
  bool get isAccountant => role == UserRole.accountant;
  bool get isCashier => role == UserRole.cashier;
  bool get isWarehouseClerk => role == UserRole.warehouseClerk;
  bool get isSalesperson => role == UserRole.salesperson;

  bool hasPermission(UserRole requiredRole) {
    int level(UserRole value) => switch (value) {
      UserRole.salesperson => 0,
      UserRole.cashier || UserRole.warehouseClerk => 1,
      UserRole.accountant => 2,
      UserRole.manager => 3,
      UserRole.owner => 4,
    };
    return level(role) >= level(requiredRole);
  }

  UserEntity copyWith({
    int? id,
    String? username,
    UserRole? role,
    int? employeeId,
    String? branchId,
    String? warehouseId,
    bool? hasGlobalLocationAccess,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      employeeId: employeeId ?? this.employeeId,
      branchId: branchId ?? this.branchId,
      warehouseId: warehouseId ?? this.warehouseId,
      hasGlobalLocationAccess:
          hasGlobalLocationAccess ?? this.hasGlobalLocationAccess,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    username,
    role,
    employeeId,
    branchId,
    warehouseId,
    hasGlobalLocationAccess,
    isActive,
    createdAt,
    updatedAt,
    lastLoginAt,
  ];
}
