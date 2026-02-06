import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/user_entity.dart';
import '../bloc/users_bloc.dart';

class UserStatsCards extends StatelessWidget {
  const UserStatsCards({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserStatsBloc, RealtimeState<Map<UserRole, int>>>(
      builder: (context, state) {
        int totalUsers = 0;
        int owners = 0;
        int activeUsers = 0;
        int managers = 0;

        if (state is RealtimeSuccess<Map<UserRole, int>>) {
          final counts = state.data;
          owners = counts[UserRole.owner] ?? 0;
          managers = counts[UserRole.manager] ?? 0;
          totalUsers = counts.values.fold(0, (sum, c) => sum + c);
        }

        // Also get active count from users bloc
        final usersState = context.watch<UsersBloc>().state;
        if (usersState is RealtimeSuccess<List<UserEntity>>) {
          // We need to count active from the full unfiltered list
          // Since the bloc applies filters, we use stats bloc total
          activeUsers = usersState.data.where((u) => u.isActive).length;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 500;
            if (isWide) {
              return Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.group_outlined,
                      iconColor: Colors.blue,
                      value: totalUsers.toString(),
                      label: 'users.total_users'.tr(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.workspace_premium_outlined,
                      iconColor: Colors.amber.shade700,
                      value: owners.toString(),
                      label: 'users.owners'.tr(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.person_outline,
                      iconColor: Colors.green,
                      value: activeUsers.toString(),
                      label: 'users.active_users'.tr(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.manage_accounts_outlined,
                      iconColor: Colors.teal,
                      value: managers.toString(),
                      label: 'users.managers'.tr(),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.group_outlined,
                        iconColor: Colors.blue,
                        value: totalUsers.toString(),
                        label: 'users.total_users'.tr(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.workspace_premium_outlined,
                        iconColor: Colors.amber.shade700,
                        value: owners.toString(),
                        label: 'users.owners'.tr(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.person_outline,
                        iconColor: Colors.green,
                        value: activeUsers.toString(),
                        label: 'users.active_users'.tr(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.manage_accounts_outlined,
                        iconColor: Colors.teal,
                        value: managers.toString(),
                        label: 'users.managers'.tr(),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
