import 'package:equatable/equatable.dart';

enum UserRole {
  owner,
  manager,
  accountant,
  cashier,
  salesperson;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
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
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;

  const UserEntity({
    required this.id,
    required this.username,
    required this.role,
    this.employeeId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
  });

  bool get isOwner => role == UserRole.owner;
  bool get isManager => role == UserRole.manager;
  bool get isAccountant => role == UserRole.accountant;
  bool get isCashier => role == UserRole.cashier;
  bool get isSalesperson => role == UserRole.salesperson;

  bool hasPermission(UserRole requiredRole) {
    const hierarchy = [
      UserRole.salesperson,
      UserRole.cashier,
      UserRole.accountant,
      UserRole.manager,
      UserRole.owner,
    ];
    return hierarchy.indexOf(role) >= hierarchy.indexOf(requiredRole);
  }

  UserEntity copyWith({
    int? id,
    String? username,
    UserRole? role,
    int? employeeId,
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
        isActive,
        createdAt,
        updatedAt,
        lastLoginAt,
      ];
}
