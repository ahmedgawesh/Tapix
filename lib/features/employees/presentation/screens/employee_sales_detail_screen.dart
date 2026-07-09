import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/daos/employee_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';

/// Which drill-down the screen shows.
enum EmployeeLineDetailMode { sales, returns }

/// Line-level drill-down for the employee detail screen's green "Sales Total"
/// tile and red "Returns Total" tile.
///
/// Lists every piece the salesperson sold (or returned) in the selected month,
/// with the post-discount line total, the invoice / return number, the date,
/// and the customer name when available.
class EmployeeSalesDetailScreen extends StatefulWidget {
  final int employeeId;
  final String employeeName;

  /// `yyyy-MM` — the month currently selected on the employee detail screen.
  final String period;
  final EmployeeLineDetailMode mode;

  const EmployeeSalesDetailScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.period,
    required this.mode,
  });

  @override
  State<EmployeeSalesDetailScreen> createState() =>
      _EmployeeSalesDetailScreenState();
}

class _EmployeeSalesDetailScreenState extends State<EmployeeSalesDetailScreen> {
  late Future<List<EmployeeLineDetail>> _future;

  bool get _isReturns => widget.mode == EmployeeLineDetailMode.returns;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EmployeeLineDetail>> _load() {
    final parts = widget.period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final periodStart = DateTime(year, month, 1);
    final periodEnd = DateTime(year, month + 1, 0, 23, 59, 59);

    final dao = sl<EmployeeDao>();
    return _isReturns
        ? dao.getEmployeeReturnsLineDetails(
            widget.employeeId, periodStart, periodEnd)
        : dao.getEmployeeSalesLineDetails(
            widget.employeeId, periodStart, periodEnd);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _isReturns ? Colors.red : Colors.green;
    final parts = widget.period.split('-');
    final periodLabel = DateFormat('MMMM yyyy', context.locale.toString())
        .format(DateTime(int.parse(parts[0]), int.parse(parts[1])));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isReturns
                  ? 'employees.returns_detail_title'.tr()
                  : 'employees.sales_detail_title'.tr(),
            ),
            Text(
              '${widget.employeeName} · $periodLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<EmployeeLineDetail>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final items = snapshot.data ?? const <EmployeeLineDetail>[];
          if (items.isEmpty) {
            return _EmptyState(isReturns: _isReturns);
          }

          final cs = sl<CurrencyService>();
          final totalCents =
              items.fold<int>(0, (sum, e) => sum + e.lineTotalCents);
          final totalQty = items.fold<int>(0, (sum, e) => sum + e.quantity);

          return Column(
            children: [
              _SummaryBar(
                accent: accent,
                lineCount: items.length,
                totalQty: totalQty,
                totalLabel: cs.format(totalCents),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _LineCard(
                    detail: items[index],
                    accent: accent,
                    isReturns: _isReturns,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final Color accent;
  final int lineCount;
  final int totalQty;
  final String totalLabel;

  const _SummaryBar({
    required this.accent,
    required this.lineCount,
    required this.totalQty,
    required this.totalLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${'employees.detail_items_count'.tr(args: [
                        lineCount.toString()
                      ])} · ${'employees.detail_qty'.tr()}: $totalQty',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'employees.detail_total'.tr(),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Text(
            totalLabel,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final EmployeeLineDetail detail;
  final Color accent;
  final bool isReturns;

  const _LineCard({
    required this.detail,
    required this.accent,
    required this.isReturns,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();
    final dateLabel = DateFormat('yMMMd', context.locale.toString())
        .format(detail.documentDate);
    final variant = detail.variantLabel;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.productName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (variant != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            variant,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isReturns ? '- ' : ''}${cs.format(detail.lineTotalCents)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${'employees.detail_qty'.tr()}: ${detail.quantity}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),
            _MetaRow(
              icon: isReturns
                  ? Icons.assignment_return_outlined
                  : Icons.receipt_long_outlined,
              label: isReturns
                  ? 'employees.detail_return_no'.tr()
                  : 'employees.detail_invoice'.tr(),
              value: detail.documentNumber.isEmpty ? '—' : detail.documentNumber,
            ),
            const SizedBox(height: 6),
            _MetaRow(
              icon: Icons.calendar_today_outlined,
              label: 'employees.detail_date'.tr(),
              value: dateLabel,
            ),
            const SizedBox(height: 6),
            _MetaRow(
              icon: Icons.person_outline,
              label: 'employees.detail_customer'.tr(),
              value: (detail.customerName == null ||
                      detail.customerName!.isEmpty)
                  ? 'employees.detail_no_customer'.tr()
                  : detail.customerName!,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isReturns;

  const _EmptyState({required this.isReturns});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isReturns
                ? Icons.assignment_return_outlined
                : Icons.receipt_long_outlined,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            isReturns
                ? 'employees.no_returns_records'.tr()
                : 'employees.no_sales_records'.tr(),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
