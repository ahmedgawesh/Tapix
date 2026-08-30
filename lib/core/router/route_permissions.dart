import '../../features/auth/domain/entities/user_entity.dart';

class RoutePermissions {
  static const List<UserRole> productManagers = [
    UserRole.owner,
    UserRole.manager,
  ];

  static final Map<String, List<UserRole>> map = {
    '/dashboard': [
      UserRole.owner,
      UserRole.manager,
      UserRole.accountant,
      UserRole.cashier,
      UserRole.salesperson,
    ],
    '/cashier-shifts': [
      UserRole.owner,
      UserRole.manager,
      UserRole.accountant,
      UserRole.cashier,
      UserRole.salesperson,
    ],
    '/products': [
      UserRole.owner,
      UserRole.manager,
      UserRole.accountant,
      UserRole.cashier,
      UserRole.salesperson,
    ],
    '/products/variants': [
      UserRole.owner,
      UserRole.manager,
      UserRole.accountant,
      UserRole.cashier,
      UserRole.salesperson,
    ],
    '/products/export': [UserRole.owner, UserRole.manager, UserRole.accountant],
    '/products/new': productManagers,
    '/products/bulk': productManagers,
    '/products/edit-prices': productManagers,
    '/products/import': productManagers,
    '/products/categories': productManagers,
    '/products/colors': productManagers,
    '/products/sizes': productManagers,
    '/sales': [
      UserRole.owner,
      UserRole.manager,
      UserRole.accountant,
      UserRole.cashier,
      UserRole.salesperson,
    ],
    '/sales/new': [
      UserRole.owner,
      UserRole.manager,
      UserRole.cashier,
      UserRole.salesperson,
    ],
    '/sales/returns': [UserRole.owner, UserRole.manager, UserRole.cashier],
    '/customers': [
      UserRole.owner,
      UserRole.manager,
      UserRole.accountant,
      UserRole.cashier,
    ],
    '/suppliers': [UserRole.owner, UserRole.manager, UserRole.accountant],
    '/purchases': [UserRole.owner, UserRole.manager, UserRole.accountant],
    '/expenses': [UserRole.owner, UserRole.manager, UserRole.accountant],
    '/reports': [UserRole.owner, UserRole.manager, UserRole.accountant],
    '/settings': [UserRole.owner],
    '/devices': [UserRole.owner],
    '/settings/admin-tools': [UserRole.owner],
    '/users': [UserRole.owner],
    '/employees': [UserRole.owner, UserRole.manager],
    '/employees/attendance': [UserRole.owner, UserRole.manager],
    '/employees/leave-requests': [UserRole.owner, UserRole.manager],
    '/employees/payroll': [UserRole.owner, UserRole.manager],
    '/employees/create': [UserRole.owner, UserRole.manager],
    '/employees/settings': [UserRole.owner, UserRole.manager],
    '/accounting': [UserRole.owner, UserRole.accountant],
    '/financial-management': [UserRole.owner, UserRole.accountant],
    '/financial-management/chart-of-accounts': [
      UserRole.owner,
      UserRole.accountant,
    ],
    '/financial-management/journal-entries': [
      UserRole.owner,
      UserRole.accountant,
    ],
    '/financial-management/periods': [UserRole.owner, UserRole.accountant],
    '/audit': [UserRole.owner, UserRole.accountant],
  };

  /// Resolves both exact and parameterized routes. Product editing contains
  /// cost, margin and revaluation data, so a typed URL must not bypass the
  /// same owner/manager restriction enforced by the visible UI.
  static List<UserRole>? rolesForPath(String path) {
    final exact = map[path];
    if (exact != null) return exact;
    if (RegExp(r'^/products/\d+/edit$').hasMatch(path)) {
      return productManagers;
    }
    final prefixes = map.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final prefix in prefixes) {
      if (path.startsWith('$prefix/')) return map[prefix];
    }
    return null;
  }
}
