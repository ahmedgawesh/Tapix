import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/user_entity.dart';

class AccessDeniedScreen extends StatelessWidget {
  final String? message;
  final String? requiredPermission;
  final UserRole? requiredRole;
  final VoidCallback? onBack;
  final VoidCallback? onHome;

  const AccessDeniedScreen({
    super.key,
    this.message,
    this.requiredPermission,
    this.requiredRole,
    this.onBack,
    this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack ?? () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
          tooltip: 'common.back'.tr(),
        ),
        title: Text('common.access_denied'.tr()),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 80,
                color: theme.colorScheme.error.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 24),
              Text(
                'common.access_denied'.tr(),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message ?? 'common.access_denied_message'.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (requiredPermission != null || requiredRole != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    requiredRole != null
                        ? 'common.required_role'.tr(args: [requiredRole!.name.toUpperCase()])
                        : 'common.required_permission'.tr(args: [requiredPermission ?? '']),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (onBack != null)
                    OutlinedButton.icon(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                      label: Text('common.go_back'.tr()),
                    ),
                  if (onBack != null && onHome != null)
                    const SizedBox(width: 16),
                  if (onHome != null)
                    FilledButton.icon(
                      onPressed: onHome,
                      icon: const Icon(Icons.home),
                      label: Text('common.home'.tr()),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionDeniedDialog extends StatelessWidget {
  final String? title;
  final String? message;
  final String? requiredPermission;
  final UserRole? requiredRole;

  const PermissionDeniedDialog({
    super.key,
    this.title,
    this.message,
    this.requiredPermission,
    this.requiredRole,
  });

  static Future<void> show(
    BuildContext context, {
    String? title,
    String? message,
    String? requiredPermission,
    UserRole? requiredRole,
  }) {
    return showDialog(
      context: context,
      builder: (context) => PermissionDeniedDialog(
        title: title,
        message: message,
        requiredPermission: requiredPermission,
        requiredRole: requiredRole,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: Icon(
        Icons.lock_outline,
        color: theme.colorScheme.error,
        size: 48,
      ),
      title: Text(title ?? 'common.access_denied'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message ?? 'common.access_denied_message'.tr(),
            textAlign: TextAlign.center,
          ),
          if (requiredPermission != null || requiredRole != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'common.contact_admin'.tr(),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.ok'.tr()),
        ),
      ],
    );
  }
}

class PermissionDeniedException implements Exception {
  final String message;
  final String? permission;
  final UserRole? requiredRole;

  const PermissionDeniedException(
    this.message, {
    this.permission,
    this.requiredRole,
  });

  @override
  String toString() => 'PermissionDeniedException: $message';
}
