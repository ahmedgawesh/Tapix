import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/employee_entity.dart';

class PayrollSummaryCards extends StatelessWidget {
  final PayrollSummary summary;

  const PayrollSummaryCards({
    super.key,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final currencyService = sl<CurrencyService>();

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.attach_money,
            color: Colors.green,
            value: currencyService.format(summary.totalGrossCents),
            label: 'employees.total_gross'.tr(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            icon: Icons.remove_circle_outline,
            color: Colors.red,
            value: currencyService.format(summary.totalDeductionsCents),
            label: 'employees.deductions'.tr(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryCard(
            icon: Icons.account_balance_wallet_outlined,
            color: Colors.blue,
            value: currencyService.format(summary.totalNetCents),
            label: 'employees.total_net'.tr(),
          ),
        ),
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
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
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
