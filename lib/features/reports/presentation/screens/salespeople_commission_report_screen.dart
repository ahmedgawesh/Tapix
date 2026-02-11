import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/salespeople_commission_pdf_service.dart';
import '../bloc/salespeople_commission_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class SalespeopleCommissionReportScreen extends StatelessWidget {
  const SalespeopleCommissionReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SalespeopleCommissionReportBloc>(),
      child: const _SalespeopleCommissionReportView(),
    );
  }
}

class _SalespeopleCommissionReportView extends StatelessWidget {
  const _SalespeopleCommissionReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.salespeople_commission'.tr()),
        actions: [
          BlocBuilder<SalespeopleCommissionReportBloc,
              RealtimeState<SalespeopleCommissionReportData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<SalespeopleCommissionReportData>) {
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
      body: BlocBuilder<SalespeopleCommissionReportBloc,
          RealtimeState<SalespeopleCommissionReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<SalespeopleCommissionReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<SalespeopleCommissionReportData>) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.error.toString(),
                      style: theme.textTheme.bodyLarge),
                ],
              ),
            );
          }

          if (state is RealtimeSuccess<SalespeopleCommissionReportData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<SalespeopleCommissionReportBloc>()
                        .add(SalespeopleCommissionReportDateRangeChanged(
                            range)),
                  ),
                ),
                const SizedBox(height: 8),

                // Summary cards
                _buildSummaryCards(context, state.data),
                const SizedBox(height: 8),

                // Sort selector
                _buildSortSelector(context, state.data),
                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: _SalespeopleCommissionContent(data: state.data),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSummaryCards(
      BuildContext context, SalespeopleCommissionReportData data) {
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
              label: 'reports.total_sales'.tr(),
              value: cs.formatCents(data.grandTotalSalesCents),
              icon: LucideIcons.shoppingCart,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.total_commission'.tr(),
              value: cs.formatCents(data.grandTotalCommissionCents),
              icon: LucideIcons.coins,
              color: colorScheme.tertiary,
            ),
            _SummaryCard(
              label: 'reports.commission_paid'.tr(),
              value: cs.formatCents(data.grandTotalPaidCents),
              icon: LucideIcons.checkCircle,
              color: data.grandTotalPaidCents > 0
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            _SummaryCard(
              label: 'reports.avg_target_achievement'.tr(),
              value:
                  '${data.avgTargetAchievementPercent.toStringAsFixed(1)}%',
              icon: LucideIcons.target,
              color: data.avgTargetAchievementPercent >= 100
                  ? colorScheme.primary
                  : data.avgTargetAchievementPercent >= 70
                      ? colorScheme.tertiary
                      : colorScheme.error,
            ),
          ];

          if (isWide) {
            return Row(
              children: cards
                  .map((c) => Expanded(
                          child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: c,
                      )))
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
                  )),
                  Expanded(
                      child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: cards[1],
                  )),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: cards[2],
                  )),
                  Expanded(
                      child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: cards[3],
                  )),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSortSelector(
      BuildContext context, SalespeopleCommissionReportData data) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            'reports.sort_by'.tr(),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SortChip(
                    label: 'reports.sort_revenue'.tr(),
                    selected: data.sort ==
                            SalespeopleCommissionSortType.revenueDesc ||
                        data.sort ==
                            SalespeopleCommissionSortType.revenueAsc,
                    onTap: () {
                      final next = data.sort ==
                              SalespeopleCommissionSortType.revenueDesc
                          ? SalespeopleCommissionSortType.revenueAsc
                          : SalespeopleCommissionSortType.revenueDesc;
                      context
                          .read<SalespeopleCommissionReportBloc>()
                          .add(SalespeopleCommissionReportSortChanged(next));
                    },
                    ascending: data.sort ==
                        SalespeopleCommissionSortType.revenueAsc,
                  ),
                  _SortChip(
                    label: 'reports.sort_name'.tr(),
                    selected:
                        data.sort == SalespeopleCommissionSortType.nameAsc ||
                            data.sort ==
                                SalespeopleCommissionSortType.nameDesc,
                    onTap: () {
                      final next =
                          data.sort == SalespeopleCommissionSortType.nameAsc
                              ? SalespeopleCommissionSortType.nameDesc
                              : SalespeopleCommissionSortType.nameAsc;
                      context
                          .read<SalespeopleCommissionReportBloc>()
                          .add(SalespeopleCommissionReportSortChanged(next));
                    },
                    ascending:
                        data.sort == SalespeopleCommissionSortType.nameAsc,
                  ),
                  _SortChip(
                    label: 'reports.sort_commission'.tr(),
                    selected: data.sort ==
                        SalespeopleCommissionSortType.commissionDesc,
                    onTap: () {
                      context.read<SalespeopleCommissionReportBloc>().add(
                          const SalespeopleCommissionReportSortChanged(
                              SalespeopleCommissionSortType.commissionDesc));
                    },
                  ),
                  _SortChip(
                    label: 'reports.sort_sales_count'.tr(),
                    selected: data.sort ==
                        SalespeopleCommissionSortType.salesCountDesc,
                    onTap: () {
                      context.read<SalespeopleCommissionReportBloc>().add(
                          const SalespeopleCommissionReportSortChanged(
                              SalespeopleCommissionSortType.salesCountDesc));
                    },
                  ),
                  _SortChip(
                    label: 'reports.sort_target'.tr(),
                    selected: data.sort ==
                        SalespeopleCommissionSortType
                            .targetAchievementDesc,
                    onTap: () {
                      context.read<SalespeopleCommissionReportBloc>().add(
                          const SalespeopleCommissionReportSortChanged(
                              SalespeopleCommissionSortType
                                  .targetAchievementDesc));
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, SalespeopleCommissionReportData data) async {
    await SalespeopleCommissionPdfService.printSalespeopleCommissionReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_salespeople_commission_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, SalespeopleCommissionReportData data) async {
    await SalespeopleCommissionPdfService.shareSalespeopleCommissionReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_salespeople_commission_report',
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
// SORT CHIP
// ═══════════════════════════════════════════════════════

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool ascending;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.ascending = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(
                ascending ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                size: 12,
              ),
            ],
          ],
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// SALESPEOPLE COMMISSION CONTENT
// ═══════════════════════════════════════════════════════

class _SalespeopleCommissionContent extends StatelessWidget {
  final SalespeopleCommissionReportData data;
  const _SalespeopleCommissionContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.salespeople.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.users, size: 48,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('reports.no_salespeople_commission'.tr(),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('reports.no_salespeople_commission_desc'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: data.salespeople.length,
      itemBuilder: (context, index) {
        final item = data.salespeople[index];
        return _SalespersonCommissionCard(
          item: item,
          cs: cs,
          rank: index + 1,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// SALESPERSON COMMISSION CARD
// ═══════════════════════════════════════════════════════

class _SalespersonCommissionCard extends StatelessWidget {
  final SalespersonCommissionItem item;
  final CurrencyService cs;
  final int rank;

  const _SalespersonCommissionCard({
    required this.item,
    required this.cs,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Target achievement color
    final targetColor = item.targetAchievementPercent >= 100
        ? colorScheme.primary
        : item.targetAchievementPercent >= 70
            ? colorScheme.tertiary
            : colorScheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: rank + name + target badge
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.employeeName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.position != null && item.position!.isNotEmpty)
                        Text(
                          item.position!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    '${item.targetAchievementPercent.toStringAsFixed(0)}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: targetColor,
                    ),
                  ),
                  backgroundColor: targetColor.withValues(alpha: 0.1),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Target progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (item.targetAchievementPercent / 100).clamp(0.0, 1.0),
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: targetColor,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),

            // Analytics metrics
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 400;
                final metrics = [
                  _MetricItem(
                    label: 'reports.sales'.tr(),
                    value: cs.formatCents(item.totalSalesCents),
                    subtitle:
                        '${item.salesCount} ${'reports.invoices'.tr()}',
                    valueColor: colorScheme.primary,
                  ),
                  _MetricItem(
                    label: 'reports.commission'.tr(),
                    value: cs.formatCents(item.totalCommissionEarnedCents),
                    subtitle:
                        '${item.commissionRatePercent.toStringAsFixed(1)}%',
                    valueColor: colorScheme.tertiary,
                  ),
                  _MetricItem(
                    label: 'reports.commission_paid'.tr(),
                    value: cs.formatCents(item.paidCommissionCents),
                    subtitle: '${cs.formatCents(item.pendingCommissionCents)} ${'reports.pending'.tr()}',
                    valueColor: item.paidCommissionCents > 0
                        ? colorScheme.primary
                        : null,
                  ),
                  _MetricItem(
                    label: 'reports.avg_order'.tr(),
                    value: cs.formatCents(item.avgOrderValueCents),
                    valueColor: colorScheme.secondary,
                  ),
                ];

                if (isWide) {
                  return Row(
                    children:
                        metrics.map((m) => Expanded(child: m)).toList(),
                  );
                }
                return Column(
                  children: [
                    Row(children: [
                      Expanded(child: metrics[0]),
                      Expanded(child: metrics[1]),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(child: metrics[2]),
                      Expanded(child: metrics[3]),
                    ]),
                  ],
                );
              },
            ),

            if (item.lastSaleAt != null) ...[
              const SizedBox(height: 4),
              Text(
                '${'reports.last_sale'.tr()}: ${DateFormat.yMMMd().format(item.lastSaleAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
  final String? subtitle;
  final Color? valueColor;

  const _MetricItem({
    required this.label,
    required this.value,
    this.subtitle,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        Text(value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            )),
        if (subtitle != null)
          Text(subtitle!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
      ],
    );
  }
}
