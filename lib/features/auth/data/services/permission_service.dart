import '../../../../core/router/route_permissions.dart';
import '../../domain/entities/permission_constants.dart';
import '../../domain/entities/user_entity.dart';

class PermissionService {
  static const List<UserRole> _roleHierarchy = [
    UserRole.salesperson,
    UserRole.cashier,
    UserRole.accountant,
    UserRole.manager,
    UserRole.owner,
  ];

  static const Map<UserRole, List<String>> _rolePermissions = {
    UserRole.owner: [
      // User Management (Owner only)
      Permissions.manageUsers,
      Permissions.promoteUsers,
      Permissions.deactivateUsers,
      Permissions.viewUserActivity,
      // Employee Management
      Permissions.manageEmployees,
      Permissions.viewEmployees,
      // Product Management
      Permissions.editProducts,
      Permissions.deleteProducts,
      Permissions.adjustStock,
      Permissions.manageCategories,
      Permissions.viewProducts,
      Permissions.manageBarcodes,
      // Financial Operations
      Permissions.viewReports,
      Permissions.manageExpenses,
      Permissions.accessSettings,
      Permissions.manageTaxes,
      Permissions.manageAccounting,
      Permissions.exportData,
      Permissions.backupRestore,
      // Sales Operations
      Permissions.processSales,
      Permissions.handleReturns,
      Permissions.viewDailyReports,
      Permissions.manageDiscounts,
      Permissions.voidTransactions,
      Permissions.createSales,
      // Customer/Supplier Management
      Permissions.manageCustomers,
      Permissions.viewCustomers,
      Permissions.manageSuppliers,
      Permissions.viewSuppliers,
      Permissions.managePurchases,
      Permissions.viewPurchases,
      // Audit
      Permissions.viewAuditLogs,
      // Legacy permissions for backward compatibility
      'manage_users',
      'manage_employees',
      'view_reports',
      'manage_settings',
      'manage_products',
      'manage_customers',
      'manage_suppliers',
      'manage_sales',
      'manage_purchases',
      'manage_expenses',
      'manage_accounting',
      'void_transactions',
      'view_audit_logs',
      'export_data',
      'backup_restore',
    ],
    UserRole.manager: [
      // Employee Management
      Permissions.manageEmployees,
      Permissions.viewEmployees,
      // Product Management
      Permissions.editProducts,
      Permissions.deleteProducts,
      Permissions.adjustStock,
      Permissions.manageCategories,
      Permissions.viewProducts,
      Permissions.manageBarcodes,
      // Financial Operations
      Permissions.viewReports,
      Permissions.manageExpenses,
      Permissions.exportData,
      // Sales Operations
      Permissions.processSales,
      Permissions.handleReturns,
      Permissions.viewDailyReports,
      Permissions.manageDiscounts,
      Permissions.voidTransactions,
      Permissions.createSales,
      // Customer/Supplier Management
      Permissions.manageCustomers,
      Permissions.viewCustomers,
      Permissions.manageSuppliers,
      Permissions.viewSuppliers,
      Permissions.managePurchases,
      Permissions.viewPurchases,
      // Legacy permissions
      'manage_employees',
      'view_reports',
      'manage_products',
      'manage_customers',
      'manage_suppliers',
      'manage_sales',
      'manage_purchases',
      'manage_expenses',
      'void_transactions',
      'export_data',
    ],
    UserRole.accountant: [
      // Financial & Accounting
      Permissions.viewReports,
      Permissions.viewDailyReports,
      Permissions.manageExpenses,
      Permissions.manageAccounting,
      Permissions.exportData,
      Permissions.viewAuditLogs,
      // View only (read access to data for reconciliation)
      Permissions.viewProducts,
      Permissions.viewCustomers,
      Permissions.viewSuppliers,
      Permissions.viewPurchases,
      // Legacy permissions
      'view_reports',
      'manage_expenses',
      'manage_accounting',
      'export_data',
      'view_audit_logs',
      'view_customers',
      'view_products',
      'view_suppliers',
      'view_purchases',
    ],
    UserRole.cashier: [
      // Sales Operations
      Permissions.processSales,
      Permissions.handleReturns,
      Permissions.viewDailyReports,
      Permissions.createSales,
      // View only
      Permissions.viewProducts,
      Permissions.viewCustomers,
      // Legacy permissions
      'manage_sales',
      'view_customers',
      'view_products',
    ],
    UserRole.salesperson: [
      // Limited Sales Operations
      Permissions.processSales,
      Permissions.viewDailyReports,
      Permissions.createSales,
      // View only
      Permissions.viewProducts,
      Permissions.viewCustomers,
      // Legacy permissions
      'create_sales',
      'view_customers',
      'view_products',
    ],
  };

  bool hasPermission(UserEntity? user, String permission) {
    if (user == null || !user.isActive) return false;
    final permissions = _rolePermissions[user.role] ?? [];
    return permissions.contains(permission);
  }

  bool hasAnyPermission(UserEntity? user, List<String> permissions) {
    if (user == null || !user.isActive) return false;
    final userPermissions = _rolePermissions[user.role] ?? [];
    return permissions.any((p) => userPermissions.contains(p));
  }

  bool hasAllPermissions(UserEntity? user, List<String> permissions) {
    if (user == null || !user.isActive) return false;
    final userPermissions = _rolePermissions[user.role] ?? [];
    return permissions.every((p) => userPermissions.contains(p));
  }

  bool canAccessRoute(UserEntity? user, String route) {
    if (user == null || !user.isActive) return false;

    final allowedRoles = RoutePermissions.map[route];
    if (allowedRoles == null) return true;
    return allowedRoles.contains(user.role);
  }

  List<String> getPermissionsForRole(UserRole role) {
    return _rolePermissions[role] ?? [];
  }

  int getRoleLevel(UserRole role) {
    return _roleHierarchy.indexOf(role);
  }

  bool isRoleAtLeast(UserEntity? user, UserRole requiredRole) {
    if (user == null || !user.isActive) return false;
    return getRoleLevel(user.role) >= getRoleLevel(requiredRole);
  }

  bool canPromoteUser(
    UserEntity? promoter,
    UserEntity targetUser,
    UserRole newRole,
  ) {
    if (promoter == null || !promoter.isActive) return false;
    if (!targetUser.isActive) return false;

    // Only owners can promote users
    if (promoter.role != UserRole.owner) return false;

    // Cannot promote to owner role
    if (newRole == UserRole.owner) return false;

    // New role must be higher than current role
    return getRoleLevel(newRole) > getRoleLevel(targetUser.role);
  }

  bool canDemoteUser(
    UserEntity? demoter,
    UserEntity targetUser,
    UserRole newRole,
  ) {
    if (demoter == null || !demoter.isActive) return false;
    if (!targetUser.isActive) return false;

    // Only owners can demote users
    if (demoter.role != UserRole.owner) return false;

    // New role must be strictly lower than current role
    return getRoleLevel(newRole) < getRoleLevel(targetUser.role);
  }
}
