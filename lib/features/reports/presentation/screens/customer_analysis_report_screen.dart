import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/customer_analysis_pdf_service.dart';
import '../bloc/customer_analysis_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class CustomerAnalysisReportScreen extends StatelessWidget {
  const CustomerAnalysisReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerAnalysisReportBloc>(),
      child: const _CustomerAnalysisReportView(),
    );
  }
}

class _CustomerAnalysisReportView extends StatelessWidget {
  const _CustomerAnalysisReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.customer_analysis'.tr()),
        actions: [
          BlocBuilder<
            CustomerAnalysisReportBloc,
            RealtimeState<CustomerAnalysisReportData>
          >(
            builder: (context, state) {
              if (state is! RealtimeSuccess<CustomerAnalysisReportData>) {
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
      body:
          BlocBuilder<
            CustomerAnalysisReportBloc,
            RealtimeState<CustomerAnalysisReportData>
          >(
            builder: (context, state) {
              if (state is RealtimeLoading<CustomerAnalysisReportData>) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is RealtimeError<CustomerAnalysisReportData>) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        state.error.toString(),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              }

              if (state is RealtimeSuccess<CustomerAnalysisReportData>) {
                return Column(
                  children: [
                    // Date range selector
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: DateRangeSelector(
                        dateRange: state.data.dateRange,
                        onChanged: (range) => context
                            .read<CustomerAnalysisReportBloc>()
                            .add(CustomerAnalysisDateRangeChanged(range)),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Summary cards
                    _buildSummaryCards(context, state.data),
                    const SizedBox(height: 8),

                    // Content
                    Expanded(child: _CustomerAnalysisContent(data: state.data)),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),
    );
  }

  Widget _buildSummaryCards(
    BuildContext context,
    CustomerAnalysisReportData data,
  ) {
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
              label: 'reports.total_spent'.tr(),
              value: cs.formatCents(data.grandTotalSpentCents),
              icon: LucideIcons.wallet,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.total_purchases'.tr(),
              value: data.grandTotalPurchases.toString(),
              icon: LucideIcons.shoppingCart,
              color: colorScheme.tertiary,
            ),
            _SummaryCard(
              label: 'reports.avg_order'.tr(),
              value: cs.formatCents(data.overallAvgOrderCents),
              icon: LucideIcons.trendingUp,
              color: colorScheme.secondary,
            ),
            _SummaryCard(
              label: 'reports.active_customers'.tr(),
              value: data.totalCustomers.toString(),
              icon: LucideIcons.users,
              color: colorScheme.primary,
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
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: cards[2],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: cards[3],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printReport(
    BuildContext context,
    CustomerAnalysisReportData data,
  ) async {
    await CustomerAnalysisPdfService.printCustomerAnalysisReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_customer_analysis_report',
    );
  }

  Future<void> _shareReport(
    BuildContext context,
    CustomerAnalysisReportData data,
  ) async {
    await CustomerAnalysisPdfService.shareCustomerAnalysisReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_customer_analysis_report',
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
// CUSTOMER ANALYSIS CONTENT
// ═══════════════════════════════════════════════════════

class _CustomerAnalysisContent extends StatelessWidget {
  final CustomerAnalysisReportData data;
  const _CustomerAnalysisContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.customers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.barChart3,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'reports.no_analysis_data'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.no_analysis_data_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // RFM Segment Overview
        _buildRfmOverview(context, data),
        const SizedBox(height: 16),

        // Customer analysis table
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'reports.customer_analysis_details'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'reports.customer_count'.tr(args: ['${data.customers.length}']),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Customer cards
        ...data.customers.map(
          (item) => _CustomerAnalysisCard(item: item, cs: cs),
        ),

        const SizedBox(height: 8),

        // Grand total row
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'reports.grand_total'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  cs.formatCents(data.grandTotalSpentCents),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRfmOverview(
    BuildContext context,
    CustomerAnalysisReportData data,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'reports.rfm_segment_overview'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: data.segmentCounts.entries.map((e) {
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: _rfmColor(e.key, colorScheme),
                    radius: 10,
                    child: Text(
                      '${e.value}',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                  label: Text(
                    _rfmLabel(e.key),
                    style: theme.textTheme.labelSmall,
                  ),
                  backgroundColor: colorScheme.surfaceContainerHighest,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CUSTOMER ANALYSIS CARD
// ═══════════════════════════════════════════════════════

class _CustomerAnalysisCard extends StatelessWidget {
  final CustomerAnalysisItem item;
  final CurrencyService cs;

  const _CustomerAnalysisCard({required this.item, required this.cs});

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
            // Header: name + RFM segment badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.customerName,
                    style: theme.textTheme.titleSmall?.copyWith(
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
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _rfmColor(
                      item.rfmSegment,
                      colorScheme,
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _rfmColor(
                        item.rfmSegment,
                        colorScheme,
                      ).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _rfmLabel(item.rfmSegment),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _rfmColor(item.rfmSegment, colorScheme),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Segment + RFM scores
            Row(
              children: [
                Text(
                  _segmentLabel(item.segment),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  'R:${item.recencyScore} F:${item.frequencyScore} M:${item.monetaryScore}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Metrics grid
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 400;
                final metrics = [
                  _MetricItem(
                    label: 'reports.total_spent'.tr(),
                    value: cs.formatCents(item.totalSpentCents),
                  ),
                  _MetricItem(
                    label: 'reports.purchases'.tr(),
                    value: item.purchaseCount.toString(),
                  ),
                  _MetricItem(
                    label: 'reports.avg_order'.tr(),
                    value: cs.formatCents(item.avgOrderValueCents),
                  ),
                  _MetricItem(
                    label: 'reports.avg_frequency'.tr(),
                    value: item.avgDaysBetweenPurchases > 0
                        ? 'reports.days_value'.tr(
                            args: ['${item.avgDaysBetweenPurchases.round()}'],
                          )
                        : '-',
                  ),
                ];

                if (isWide) {
                  return Row(
                    children: metrics.map((m) => Expanded(child: m)).toList(),
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: metrics[0]),
                        Expanded(child: metrics[1]),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: metrics[2]),
                        Expanded(child: metrics[3]),
                      ],
                    ),
                  ],
                );
              },
            ),
            if (item.lastPurchaseDate != null) ...[
              const SizedBox(height: 4),
              Text(
                '${'reports.last_purchase'.tr()}: ${DateFormat('dd/MM/yyyy').format(item.lastPurchaseDate!)} (${item.daysSinceLastPurchase} ${'reports.days_ago'.tr()})',
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

  const _MetricItem({required this.label, required this.value});

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
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════

String _rfmLabel(RfmSegment segment) {
  switch (segment) {
    case RfmSegment.champions:
      return 'reports.rfm_champions'.tr();
    case RfmSegment.loyalCustomers:
      return 'reports.rfm_loyal'.tr();
    case RfmSegment.potentialLoyalists:
      return 'reports.rfm_potential_loyal'.tr();
    case RfmSegment.newCustomers:
      return 'reports.rfm_new'.tr();
    case RfmSegment.promising:
      return 'reports.rfm_promising'.tr();
    case RfmSegment.needsAttention:
      return 'reports.rfm_needs_attention'.tr();
    case RfmSegment.aboutToSleep:
      return 'reports.rfm_about_to_sleep'.tr();
    case RfmSegment.atRisk:
      return 'reports.rfm_at_risk'.tr();
    case RfmSegment.cantLoseThem:
      return 'reports.rfm_cant_lose'.tr();
    case RfmSegment.hibernating:
      return 'reports.rfm_hibernating'.tr();
    case RfmSegment.lost:
      return 'reports.rfm_lost'.tr();
  }
}

Color _rfmColor(RfmSegment segment, ColorScheme colorScheme) {
  switch (segment) {
    case RfmSegment.champions:
      return Colors.amber.shade700;
    case RfmSegment.loyalCustomers:
      return colorScheme.primary;
    case RfmSegment.potentialLoyalists:
      return Colors.teal;
    case RfmSegment.newCustomers:
      return Colors.blue;
    case RfmSegment.promising:
      return Colors.cyan;
    case RfmSegment.needsAttention:
      return Colors.orange;
    case RfmSegment.aboutToSleep:
      return Colors.deepOrange;
    case RfmSegment.atRisk:
      return colorScheme.error;
    case RfmSegment.cantLoseThem:
      return Colors.red.shade900;
    case RfmSegment.hibernating:
      return Colors.blueGrey;
    case RfmSegment.lost:
      return Colors.grey;
  }
}

String _segmentLabel(String segment) {
  switch (segment) {
    case 'retail':
      return 'customers.segment_retail'.tr();
    case 'wholesale':
      return 'customers.segment_wholesale'.tr();
    case 'premium':
      return 'customers.segment_premium'.tr();
    default:
      return segment;
  }
}
