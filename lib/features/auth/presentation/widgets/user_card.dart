import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/user_entity.dart';

class UserCard extends StatelessWidget {
  final UserEntity user;
  final VoidCallback? onTap;
  final VoidCallback? onToggleActive;

  const UserCard({
    super.key,
    required this.user,
    this.onTap,
    this.onToggleActive,
  });

  Color _roleColor(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return Colors.amber.shade700;
      case UserRole.manager:
        return Colors.blue;
      case UserRole.accountant:
        return Colors.indigo;
      case UserRole.cashier:
        return Colors.green;
      case UserRole.salesperson:
        return Colors.teal;
    }
  }

  IconData _roleIcon(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return Icons.workspace_premium_outlined;
      case UserRole.manager:
        return Icons.manage_accounts_outlined;
      case UserRole.accountant:
        return Icons.account_balance_outlined;
      case UserRole.cashier:
        return Icons.point_of_sale_outlined;
      case UserRole.salesperson:
        return Icons.storefront_outlined;
    }
  }

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return 'users.role_owner'.tr();
      case UserRole.manager:
        return 'users.role_manager'.tr();
      case UserRole.accountant:
        return 'users.role_accountant'.tr();
      case UserRole.cashier:
        return 'users.role_cashier'.tr();
      case UserRole.salesperson:
        return 'users.role_salesperson'.tr();
    }
  }

  String _formatLastLogin(DateTime? lastLogin) {
    final label = 'users.last_login'.tr();
    if (lastLogin == null) return '$label: —';
    final now = DateTime.now();
    final diff = now.difference(lastLogin);
    if (diff.inMinutes < 1) {
      return '$label: ${'common.just_now'.tr()}';
    } else if (diff.inHours < 1) {
      return '$label: ${diff.inMinutes}m';
    } else if (diff.inDays < 1) {
      return '$label: ${diff.inHours}h';
    } else {
      final month = lastLogin.month.toString().padLeft(2, '0');
      final day = lastLogin.day.toString().padLeft(2, '0');
      final hour = lastLogin.hour.toString().padLeft(2, '0');
      final minute = lastLogin.minute.toString().padLeft(2, '0');
      return '$label: ${lastLogin.year}-$month-$day $hour:$minute';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final roleColor = _roleColor(user.role);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar with role icon
              CircleAvatar(
                radius: 24,
                backgroundColor: roleColor.withValues(alpha: 0.15),
                child: Icon(_roleIcon(user.role), color: roleColor, size: 24),
              ),
              const SizedBox(width: 12),
              // User info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.username,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _roleIcon(user.role),
                                size: 14,
                                color: roleColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _roleLabel(user.role),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: roleColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_outlined,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _formatLastLogin(user.lastLoginAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: colorScheme.onSurfaceVariant,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onTap?.call();
                      break;
                    case 'toggle':
                      onToggleActive?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_outlined,
                          size: 20,
                          color: colorScheme.onSurface,
                        ),
                        const SizedBox(width: 12),
                        Text('users.edit'.tr()),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          user.isActive
                              ? Icons.person_off_outlined
                              : Icons.person_outlined,
                          size: 20,
                          color: user.isActive
                              ? colorScheme.error
                              : Colors.green,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          user.isActive
                              ? 'users.deactivate'.tr()
                              : 'users.activate'.tr(),
                        ),
                      ],
                    ),
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
