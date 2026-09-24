import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/employees_bloc.dart';

class EmployeeStatsCards extends StatelessWidget {
  const EmployeeStatsCards({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EmployeeStatsBloc, EmployeeStatsState>(
      builder: (context, state) {
        if (state.isLoading) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;

            if (isWide) {
              return Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.people_alt_outlined,
                      iconColor: Colors.blue,
                      value: state.activeCount.toString(),
                      label: 'employees.active_employees'.tr(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.people_outline,
                      iconColor: Colors.orange,
                      value: state.totalCount.toString(),
                      label: 'employees.total_employees'.tr(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.business_outlined,
                      iconColor: Colors.green,
                      value: state.departments.length.toString(),
                      label: 'employees.departments'.tr(),
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
                        icon: Icons.people_alt_outlined,
                        iconColor: Colors.blue,
                        value: state.activeCount.toString(),
                        label: 'employees.active_employees'.tr(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.people_outline,
                        iconColor: Colors.orange,
                        value: state.totalCount.toString(),
                        label: 'employees.total_employees'.tr(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _StatCard(
                  icon: Icons.business_outlined,
                  iconColor: Colors.green,
                  value: state.departments.length.toString(),
                  label: 'employees.departments'.tr(),
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
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? iconColor.withValues(alpha: 0.15)
            : iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.white70 : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
