import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/expense_pdf_service.dart';
import '../bloc/expense_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class ExpenseReportScreen extends StatelessWidget {
  const ExpenseReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ExpenseReportBloc>(),
      child: const _ExpenseReportView(),
    );
  }
}

class _ExpenseReportView extends StatelessWidget {
  const _ExpenseReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.expense_report'.tr()),
        actions: [
          BlocBuilder<ExpenseReportBloc, RealtimeState<ExpenseReportData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<ExpenseReportData>) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.printer),
                    tooltip: 'common.print'.tr(),
                    onPressed: () => _printReport(context, state.data),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.share2),
                    tooltip: 'common.share'.tr(),
                    onPressed: () => _shareReport(context, state.data),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<ExpenseReportBloc, RealtimeState<ExpenseReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<ExpenseReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<ExpenseReportData>) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    state.error.toString(),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          }

          if (state is RealtimeSuccess<ExpenseReportData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context.read<ExpenseReportBloc>().add(
                      ExpenseReportDateRangeChanged(range),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Summary cards
                _buildSummaryCards(context, state.data),
                const SizedBox(height: 8),

                // Content
                Expanded(child: _ExpenseReportContent(data: state.data)),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context, ExpenseReportData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          final cards = [
            _SummaryCard(
              label: 'reports.total_expenses'.tr(),
              value: cs.formatCents(data.grandTotalCents),
              icon: LucideIcons.receipt,
              color: colorScheme.error,
            ),
            _SummaryCard(
              label: 'reports.expense_count'.tr(),
              value: data.totalExpenseCount.toString(),
              icon: LucideIcons.hash,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.categories_count'.tr(),
              value: data.totalCategories.toString(),
              icon: LucideIcons.layers,
              color: colorScheme.tertiary,
            ),
          ];

          if (isWide) {
            return Row(
              children: cards
                  .map(
                    (c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: c,
                      ),
                    ),
                  )
                  .toList(),
            );
          }

          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: cards[0],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: cards[1],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: cards[2]),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printReport(
    BuildContext context,
    ExpenseReportData data,
  ) async {
    await ExpensePdfService.printExpenseReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_expense_report',
    );
  }

  Future<void> _shareReport(
    BuildContext context,
    ExpenseReportData data,
  ) async {
    await ExpensePdfService.shareExpenseReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_expense_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUMMARY CARD
// ═══════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// EXPENSE REPORT CONTENT
// ═══════════════════════════════════════════════════════

class _ExpenseReportContent extends StatelessWidget {
  final ExpenseReportData data;
  const _ExpenseReportContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.receipt,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'reports.no_expense_data'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.no_expense_data_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: data.categories.length,
      itemBuilder: (context, index) {
        final item = data.categories[index];
        return _ExpenseCategoryCard(
          item: item,
          cs: cs,
          grandTotalCents: data.grandTotalCents,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// EXPENSE CATEGORY CARD
// ═══════════════════════════════════════════════════════

class _ExpenseCategoryCard extends StatelessWidget {
  final ExpenseCategorySummary item;
  final CurrencyService cs;
  final int grandTotalCents;

  const _ExpenseCategoryCard({
    required this.item,
    required this.cs,
    required this.grandTotalCents,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: category name + percentage badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.categoryName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  label: Text(
                    '${item.percentage.toStringAsFixed(1)}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Progress bar showing percentage of total
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: grandTotalCents > 0
                    ? item.totalAmountCents / grandTotalCents
                    : 0,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),

            // Metrics row
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 400;
                final metrics = [
                  _MetricItem(
                    label: 'reports.total_amount'.tr(),
                    value: cs.formatCents(item.totalAmountCents),
                    valueColor: colorScheme.error,
                  ),
                  _MetricItem(
                    label: 'reports.expense_count'.tr(),
                    value: item.expenseCount.toString(),
                  ),
                ];

                if (isWide) {
                  return Row(
                    children: metrics.map((m) => Expanded(child: m)).toList(),
                  );
                }
                return Row(
                  children: [
                    Expanded(child: metrics[0]),
                    Expanded(child: metrics[1]),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// METRIC ITEM
// ═══════════════════════════════════════════════════════

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetricItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
