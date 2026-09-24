import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/employee_entity.dart';

class AttendanceStatusCards extends StatelessWidget {
  final AttendanceSummary summary;

  const AttendanceStatusCards({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatusCard(
            icon: Icons.check_circle_outline,
            color: Colors.green,
            count: summary.presentCount,
            label: 'employees.status_present'.tr(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusCard(
            icon: Icons.access_time,
            color: Colors.orange,
            count: summary.lateCount,
            label: 'employees.status_late'.tr(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusCard(
            icon: Icons.cancel_outlined,
            color: Colors.red,
            count: summary.absentCount,
            label: 'employees.status_absent'.tr(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusCard(
            icon: Icons.beach_access_outlined,
            color: Colors.blue,
            count: summary.onLeaveCount,
            label: 'employees.status_on_leave'.tr(),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const _StatusCard({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isDark ? Colors.white70 : color.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
