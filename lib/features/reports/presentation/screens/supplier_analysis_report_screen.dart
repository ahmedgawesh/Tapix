import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/supplier_analysis_pdf_service.dart';
import '../bloc/supplier_analysis_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class SupplierAnalysisReportScreen extends StatelessWidget {
  const SupplierAnalysisReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SupplierAnalysisReportBloc>(),
      child: const _SupplierAnalysisReportView(),
    );
  }
}

class _SupplierAnalysisReportView extends StatelessWidget {
  const _SupplierAnalysisReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.supplier_analysis'.tr()),
        actions: [
          BlocBuilder<SupplierAnalysisReportBloc,
              RealtimeState<SupplierAnalysisReportData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<SupplierAnalysisReportData>) {
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
      body: BlocBuilder<SupplierAnalysisReportBloc,
          RealtimeState<SupplierAnalysisReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<SupplierAnalysisReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<SupplierAnalysisReportData>) {
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

          if (state is RealtimeSuccess<SupplierAnalysisReportData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<SupplierAnalysisReportBloc>()
                        .add(SupplierAnalysisReportDateRangeChanged(range)),
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
                  child: _SupplierAnalysisContent(data: state.data),
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
      BuildContext context, SupplierAnalysisReportData data) {
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
              label: 'reports.total_purchases'.tr(),
              value: cs.formatCents(data.grandTotalPurchasesCents),
              icon: LucideIcons.shoppingCart,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.avg_return_rate'.tr(),
              value: '${data.avgReturnRatePercent.toStringAsFixed(1)}%',
              icon: LucideIcons.undo2,
              color: data.avgReturnRatePercent > 10
                  ? colorScheme.error
                  : colorScheme.tertiary,
            ),
            _SummaryCard(
              label: 'reports.avg_settlement'.tr(),
              value: '${data.avgSettlementRatioPercent.toStringAsFixed(1)}%',
              icon: LucideIcons.checkCircle,
              color: data.avgSettlementRatioPercent >= 80
                  ? colorScheme.primary
                  : colorScheme.error,
            ),
            _SummaryCard(
              label: 'reports.avg_payment_days'.tr(),
              value: '${data.avgPaymentDays.toStringAsFixed(0)} ${'reports.days'.tr()}',
              icon: LucideIcons.clock,
              color: data.avgPaymentDays > 30
                  ? colorScheme.error
                  : colorScheme.tertiary,
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
      BuildContext context, SupplierAnalysisReportData data) {
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
                    label: 'reports.sort_volume'.tr(),
                    selected: data.sort ==
                            SupplierAnalysisSortType.purchaseVolumeDesc ||
                        data.sort ==
                            SupplierAnalysisSortType.purchaseVolumeAsc,
                    onTap: () {
                      final next = data.sort ==
                              SupplierAnalysisSortType.purchaseVolumeDesc
                          ? SupplierAnalysisSortType.purchaseVolumeAsc
                          : SupplierAnalysisSortType.purchaseVolumeDesc;
                      context
                          .read<SupplierAnalysisReportBloc>()
                          .add(SupplierAnalysisReportSortChanged(next));
                    },
                    ascending: data.sort ==
                        SupplierAnalysisSortType.purchaseVolumeAsc,
                  ),
                  _SortChip(
                    label: 'reports.sort_name'.tr(),
                    selected:
                        data.sort == SupplierAnalysisSortType.nameAsc ||
                            data.sort == SupplierAnalysisSortType.nameDesc,
                    onTap: () {
                      final next =
                          data.sort == SupplierAnalysisSortType.nameAsc
                              ? SupplierAnalysisSortType.nameDesc
                              : SupplierAnalysisSortType.nameAsc;
                      context
                          .read<SupplierAnalysisReportBloc>()
                          .add(SupplierAnalysisReportSortChanged(next));
                    },
                    ascending:
                        data.sort == SupplierAnalysisSortType.nameAsc,
                  ),
                  _SortChip(
                    label: 'reports.sort_return_rate'.tr(),
                    selected: data.sort ==
                        SupplierAnalysisSortType.returnRateDesc,
                    onTap: () {
                      context.read<SupplierAnalysisReportBloc>().add(
                          const SupplierAnalysisReportSortChanged(
                              SupplierAnalysisSortType.returnRateDesc));
                    },
                  ),
                  _SortChip(
                    label: 'reports.sort_payment_days'.tr(),
                    selected: data.sort ==
                        SupplierAnalysisSortType.avgPaymentDaysAsc,
                    onTap: () {
                      context.read<SupplierAnalysisReportBloc>().add(
                          const SupplierAnalysisReportSortChanged(
                              SupplierAnalysisSortType.avgPaymentDaysAsc));
                    },
                  ),
                  _SortChip(
                    label: 'reports.sort_settlement'.tr(),
                    selected: data.sort ==
                        SupplierAnalysisSortType.settlementRatioDesc,
                    onTap: () {
                      context.read<SupplierAnalysisReportBloc>().add(
                          const SupplierAnalysisReportSortChanged(
                              SupplierAnalysisSortType
                                  .settlementRatioDesc));
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
      BuildContext context, SupplierAnalysisReportData data) async {
    await SupplierAnalysisPdfService.printSupplierAnalysisReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_supplier_analysis_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, SupplierAnalysisReportData data) async {
    await SupplierAnalysisPdfService.shareSupplierAnalysisReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_supplier_analysis_report',
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
// SUPPLIER ANALYSIS CONTENT
// ═══════════════════════════════════════════════════════

class _SupplierAnalysisContent extends StatelessWidget {
  final SupplierAnalysisReportData data;
  const _SupplierAnalysisContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.suppliers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.truck, size: 48,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('reports.no_supplier_analysis'.tr(),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('reports.no_supplier_analysis_desc'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: data.suppliers.length,
      itemBuilder: (context, index) {
        final item = data.suppliers[index];
        return _SupplierAnalysisCard(
          item: item,
          cs: cs,
          rank: index + 1,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUPPLIER ANALYSIS CARD
// ═══════════════════════════════════════════════════════

class _SupplierAnalysisCard extends StatelessWidget {
  final SupplierAnalysisItem item;
  final CurrencyService cs;
  final int rank;

  const _SupplierAnalysisCard({
    required this.item,
    required this.cs,
    required this.rank,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Performance indicator color
    final settlementColor = item.settlementRatioPercent >= 80
        ? colorScheme.primary
        : item.settlementRatioPercent >= 50
            ? colorScheme.tertiary
            : colorScheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: rank + name + settlement badge
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
                        item.supplierName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.phone != null && item.phone!.isNotEmpty)
                        Text(
                          item.phone!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    '${item.settlementRatioPercent.toStringAsFixed(0)}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: settlementColor,
                    ),
                  ),
                  backgroundColor: settlementColor.withValues(alpha: 0.1),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Analytics metrics
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 400;
                final metrics = [
                  _MetricItem(
                    label: 'reports.purchases'.tr(),
                    value: cs.formatCents(item.totalPurchasesCents),
                    subtitle: '${item.purchaseCount} ${'reports.orders'.tr()}',
                    valueColor: colorScheme.primary,
                  ),
                  _MetricItem(
                    label: 'reports.return_rate'.tr(),
                    value: '${item.returnRatePercent.toStringAsFixed(1)}%',
                    subtitle:
                        cs.formatCents(item.totalReturnsCents),
                    valueColor: item.returnRatePercent > 10
                        ? colorScheme.error
                        : null,
                  ),
                  _MetricItem(
                    label: 'reports.payment_days'.tr(),
                    value:
                        '${item.avgPaymentDays.toStringAsFixed(0)} ${'reports.days'.tr()}',
                    subtitle:
                        cs.formatCents(item.totalPaymentsCents),
                    valueColor: item.avgPaymentDays > 30
                        ? colorScheme.error
                        : null,
                  ),
                  _MetricItem(
                    label: 'reports.avg_order'.tr(),
                    value: cs.formatCents(item.avgOrderValueCents),
                    valueColor: colorScheme.tertiary,
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

            if (item.lastTransactionAt != null) ...[
              const SizedBox(height: 4),
              Text(
                '${'reports.last_transaction'.tr()}: ${DateFormat.yMMMd().format(item.lastTransactionAt!)}',
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
