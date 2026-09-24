import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../auth.dart';

class PermissionGate extends StatelessWidget {
  final String permission;
  final Widget child;
  final Widget? fallback;
  final bool showDisabled;
  final String? disabledTooltip;
  final double disabledOpacity;

  const PermissionGate({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
    this.showDisabled = false,
    this.disabledTooltip,
    this.disabledOpacity = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
      builder: (context, state) {
        if (state is! AuthAuthenticated) {
          return fallback ?? const SizedBox.shrink();
        }

        final permissionService = sl<PermissionService>();
        if (permissionService.hasPermission(state.user, permission)) {
          return child;
        }

        if (showDisabled) {
          final disabledChild = Opacity(
            opacity: disabledOpacity,
            child: IgnorePointer(child: child),
          );

          if (disabledTooltip != null) {
            return Tooltip(message: disabledTooltip!, child: disabledChild);
          }

          return disabledChild;
        }

        return fallback ?? const SizedBox.shrink();
      },
    );
  }
}

class RoleGate extends StatelessWidget {
  final List<UserRole>? allowedRoles;
  final UserRole? minRole;
  final Widget child;
  final Widget? fallback;
  final bool showDisabled;
  final String? disabledTooltip;
  final double disabledOpacity;

  const RoleGate({
    super.key,
    this.allowedRoles,
    this.minRole,
    required this.child,
    this.fallback,
    this.showDisabled = false,
    this.disabledTooltip,
    this.disabledOpacity = 0.5,
  }) : assert(
         allowedRoles != null || minRole != null,
         'Either allowedRoles or minRole must be provided',
       );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
      builder: (context, state) {
        if (state is! AuthAuthenticated) {
          return fallback ?? const SizedBox.shrink();
        }

        final hasAccess = _checkAccess(state.user);

        if (hasAccess) {
          return child;
        }

        if (showDisabled) {
          final disabledChild = Opacity(
            opacity: disabledOpacity,
            child: IgnorePointer(child: child),
          );

          if (disabledTooltip != null) {
            return Tooltip(message: disabledTooltip!, child: disabledChild);
          }

          return disabledChild;
        }

        return fallback ?? const SizedBox.shrink();
      },
    );
  }

  bool _checkAccess(UserEntity user) {
    if (minRole != null) {
      final permissionService = sl<PermissionService>();
      return permissionService.isRoleAtLeast(user, minRole!);
    }

    if (allowedRoles != null) {
      return allowedRoles!.contains(user.role);
    }

    return false;
  }
}

class MultiPermissionGate extends StatelessWidget {
  final List<String> permissions;
  final bool requireAll;
  final Widget child;
  final Widget? fallback;
  final bool showDisabled;
  final String? disabledTooltip;
  final double disabledOpacity;

  const MultiPermissionGate({
    super.key,
    required this.permissions,
    this.requireAll = true,
    required this.child,
    this.fallback,
    this.showDisabled = false,
    this.disabledTooltip,
    this.disabledOpacity = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
      builder: (context, state) {
        if (state is! AuthAuthenticated) {
          return fallback ?? const SizedBox.shrink();
        }

        final permissionService = sl<PermissionService>();
        final hasAccess = requireAll
            ? permissionService.hasAllPermissions(state.user, permissions)
            : permissionService.hasAnyPermission(state.user, permissions);

        if (hasAccess) {
          return child;
        }

        if (showDisabled) {
          final disabledChild = Opacity(
            opacity: disabledOpacity,
            child: IgnorePointer(child: child),
          );

          if (disabledTooltip != null) {
            return Tooltip(message: disabledTooltip!, child: disabledChild);
          }

          return disabledChild;
        }

        return fallback ?? const SizedBox.shrink();
      },
    );
  }
}
