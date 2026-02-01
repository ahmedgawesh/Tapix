import '../../features/auth/domain/entities/user_entity.dart';

class RoutePermissions {
  static final Map<String, List<UserRole>> map = {
    '/dashboard': [UserRole.owner, UserRole.manager, UserRole.cashier, UserRole.salesperson],
    '/products': [UserRole.owner, UserRole.manager, UserRole.cashier, UserRole.salesperson],
    '/products/variants': [UserRole.owner, UserRole.manager, UserRole.cashier, UserRole.salesperson],
    '/products/export': [UserRole.owner, UserRole.manager],
    '/sales': [UserRole.owner, UserRole.manager, UserRole.cashier, UserRole.salesperson],
    '/customers': [UserRole.owner, UserRole.manager, UserRole.cashier],
    '/suppliers': [UserRole.owner, UserRole.manager],
    '/purchases': [UserRole.owner, UserRole.manager],
    '/expenses': [UserRole.owner, UserRole.manager],
    '/reports': [UserRole.owner, UserRole.manager],
    '/settings': [UserRole.owner],
    '/settings/admin-tools': [UserRole.owner],
    '/users': [UserRole.owner],
    '/employees': [UserRole.owner, UserRole.manager],
    '/employees/attendance': [UserRole.owner, UserRole.manager],
    '/employees/leave-requests': [UserRole.owner, UserRole.manager],
    '/employees/payroll': [UserRole.owner, UserRole.manager],
    '/employees/create': [UserRole.owner, UserRole.manager],
    '/employees/settings': [UserRole.owner, UserRole.manager],
    '/accounting': [UserRole.owner],
    '/audit': [UserRole.owner],
  };
}
