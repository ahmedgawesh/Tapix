import 'package:flutter/material.dart';
import '../../../../core/di/injection_container.dart';
import '../../auth.dart';

class PermissionNavigator {
  final PermissionService _permissionService;

  PermissionNavigator._internal(this._permissionService);

  factory PermissionNavigator() => PermissionNavigator._internal(sl<PermissionService>());

  bool canNavigate(UserEntity? user, String route) {
    return _permissionService.canAccessRoute(user, route);
  }

  bool hasPermissionForRoute(UserEntity? user, String permission) {
    return _permissionService.hasPermission(user, permission);
  }

  void navigateWithPermission(
    BuildContext context,
    UserEntity? user,
    String route,
    Widget destination, {
    String? requiredPermission,
    UserRole? requiredRole,
    String? accessDeniedMessage,
  }) {
    if (user == null || !user.isActive) {
      _showAccessDenied(
        context,
        message: 'Please log in to access this feature.',
      );
      return;
    }

    bool hasAccess = true;

    if (requiredPermission != null) {
      hasAccess = _permissionService.hasPermission(user, requiredPermission);
    } else if (requiredRole != null) {
      hasAccess = _permissionService.isRoleAtLeast(user, requiredRole);
    } else {
      hasAccess = _permissionService.canAccessRoute(user, route);
    }

    if (hasAccess) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (context) => destination),
      );
    } else {
      _showAccessDenied(
        context,
        message: accessDeniedMessage,
        requiredPermission: requiredPermission,
        requiredRole: requiredRole,
      );
    }
  }

  void _showAccessDenied(
    BuildContext context, {
    String? message,
    String? requiredPermission,
    UserRole? requiredRole,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AccessDeniedScreen(
          message: message,
          requiredPermission: requiredPermission,
          requiredRole: requiredRole,
          onBack: () => Navigator.of(context).pop(),
          onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
    );
  }
}

class PermissionRouteGuard extends StatelessWidget {
  final UserEntity? user;
  final String? requiredPermission;
  final UserRole? requiredRole;
  final Widget child;
  final Widget? accessDeniedWidget;
  final String? accessDeniedMessage;

  const PermissionRouteGuard({
    super.key,
    required this.user,
    this.requiredPermission,
    this.requiredRole,
    required this.child,
    this.accessDeniedWidget,
    this.accessDeniedMessage,
  }) : assert(requiredPermission != null || requiredRole != null,
            'Either requiredPermission or requiredRole must be provided');

  @override
  Widget build(BuildContext context) {
    if (user == null || !user!.isActive) {
      return accessDeniedWidget ??
          AccessDeniedScreen(
            message: 'Please log in to access this feature.',
            onBack: () => Navigator.of(context).pop(),
          );
    }

    final permissionService = sl<PermissionService>();
    bool hasAccess = false;

    if (requiredPermission != null) {
      hasAccess = permissionService.hasPermission(user, requiredPermission!);
    } else if (requiredRole != null) {
      hasAccess = permissionService.isRoleAtLeast(user, requiredRole!);
    }

    if (hasAccess) {
      return child;
    }

    return accessDeniedWidget ??
        AccessDeniedScreen(
          message: accessDeniedMessage,
          requiredPermission: requiredPermission,
          requiredRole: requiredRole,
          onBack: () => Navigator.of(context).pop(),
        );
  }
}
