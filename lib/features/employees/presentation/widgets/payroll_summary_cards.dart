import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/employee_entity.dart';

class PayrollSummaryCards extends StatelessWidget {
  final PayrollSummary summary;

  const PayrollSummaryCards({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = sl<CurrencyService>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Top row: Gross, Deductions, Net
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.account_balance_outlined,
                color: Colors.blue,
                value: cs.format(summary.totalGrossCents),
                label: 'employees.total_gross'.tr(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                icon: Icons.trending_down_outlined,
                color: Colors.red,
                value: cs.format(summary.totalDeductionsCents),
                label: 'employees.total_deductions'.tr(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                icon: Icons.account_balance_wallet_outlined,
                color: Colors.green,
                value: cs.format(summary.totalNetCents),
                label: 'employees.total_net'.tr(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Bottom row: Paid / Unpaid / Employee Count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MiniStat(
                icon: Icons.check_circle_outlined,
                iconColor: Colors.green,
                value: '${summary.paidCount}',
                label: 'employees.payroll_paid'.tr(),
                subtitle: cs.format(summary.totalPaidCents),
              ),
              Container(
                height: 36,
                width: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              _MiniStat(
                icon: Icons.schedule_outlined,
                iconColor: Colors.orange,
                value: '${summary.unpaidCount}',
                label: 'employees.payroll_unpaid'.tr(),
                subtitle: cs.format(summary.totalUnpaidCents),
              ),
              Container(
                height: 36,
                width: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              _MiniStat(
                icon: Icons.people_outlined,
                iconColor: colorScheme.primary,
                value: '${summary.employeeCount}',
                label: 'employees.payroll_count'.tr(),
                subtitle: null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String? subtitle;

  const _MiniStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 1),
          Text(
            subtitle!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: iconColor,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _SummaryCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
