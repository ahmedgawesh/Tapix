import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/top_customers_pdf_service.dart';
import '../bloc/top_customers_bloc.dart';
import '../widgets/date_range_selector.dart';

class TopCustomersScreen extends StatelessWidget {
  const TopCustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<TopCustomersBloc>(),
      child: const _TopCustomersView(),
    );
  }
}

class _TopCustomersView extends StatelessWidget {
  const _TopCustomersView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.top_customers'.tr()),
        actions: [
          BlocBuilder<TopCustomersBloc, RealtimeState<TopCustomersData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<TopCustomersData>) {
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
      body: BlocBuilder<TopCustomersBloc, RealtimeState<TopCustomersData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<TopCustomersData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<TopCustomersData>) {
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

          if (state is RealtimeSuccess<TopCustomersData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<TopCustomersBloc>()
                        .add(TopCustomersDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),

                // View toggle (Revenue / Volume)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ViewToggle(view: state.data.view),
                ),
                const SizedBox(height: 8),

                // Summary cards
                _buildSummaryCards(context, state.data),
                const SizedBox(height: 8),

                // Customer rankings table
                Expanded(
                  child: _TopCustomersTable(data: state.data),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context, TopCustomersData data) {
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
              label: 'reports.total_revenue'.tr(),
              value: cs.formatCents(data.grandTotalRevenueCents),
              icon: LucideIcons.trendingUp,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.total_transactions_label'.tr(),
              value: data.grandTotalTransactions.toString(),
              icon: LucideIcons.shoppingCart,
              color: colorScheme.tertiary,
            ),
            _SummaryCard(
              label: 'reports.unique_customers'.tr(),
              value: data.uniqueCustomerCount.toString(),
              icon: LucideIcons.users,
              color: colorScheme.secondary,
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
              SizedBox(width: double.infinity, child: cards[2]),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, TopCustomersData data) async {
    await TopCustomersPdfService.printTopCustomersReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_top_customers_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, TopCustomersData data) async {
    await TopCustomersPdfService.shareTopCustomersReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_top_customers_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// VIEW TOGGLE
// ═══════════════════════════════════════════════════════

class _ViewToggle extends StatelessWidget {
  final TopCustomersViewType view;
  const _ViewToggle({required this.view});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TopCustomersViewType>(
      segments: [
        ButtonSegment(
          value: TopCustomersViewType.byRevenue,
          label: Text('reports.by_revenue'.tr()),
          icon: const Icon(LucideIcons.dollarSign, size: 16),
        ),
        ButtonSegment(
          value: TopCustomersViewType.byVolume,
          label: Text('reports.by_volume'.tr()),
          icon: const Icon(LucideIcons.barChart2, size: 16),
        ),
      ],
      selected: {view},
      onSelectionChanged: (selected) {
        context
            .read<TopCustomersBloc>()
            .add(TopCustomersViewChanged(selected.first));
      },
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
// TOP CUSTOMERS TABLE
// ═══════════════════════════════════════════════════════

class _TopCustomersTable extends StatelessWidget {
  final TopCustomersData data;
  const _TopCustomersTable({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.customers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.users,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('reports.no_top_customers'.tr(),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('reports.no_top_customers_desc'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.view == TopCustomersViewType.byRevenue
                ? 'reports.top_customers_by_revenue'.tr()
                : 'reports.top_customers_by_volume'.tr(),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              horizontalMargin: 8,
              columns: [
                const DataColumn(label: Text('#')),
                DataColumn(label: Text('reports.customer'.tr())),
                DataColumn(label: Text('reports.segment_label'.tr())),
                DataColumn(
                    label: Text('reports.revenue_label'.tr()), numeric: true),
                DataColumn(
                    label: Text('reports.transactions_label'.tr()),
                    numeric: true),
                DataColumn(
                    label: Text('reports.quantity_label'.tr()), numeric: true),
                DataColumn(
                    label: Text('reports.avg_order_label'.tr()),
                    numeric: true),
                DataColumn(label: Text('reports.last_purchase_label'.tr())),
              ],
              rows: data.customers.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final item = entry.value;
                final isTop3 = idx <= 3;
                return DataRow(cells: [
                  DataCell(Text(
                    '$idx',
                    style: isTop3
                        ? TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _rankColor(idx, theme),
                          )
                        : null,
                  )),
                  DataCell(ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(item.customerName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  )),
                  DataCell(Text(_segmentLabel(item.segment))),
                  DataCell(Text(
                    cs.formatCents(item.totalRevenueCents),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  )),
                  DataCell(Text(item.transactionCount.toString())),
                  DataCell(Text(item.totalQuantity.toString())),
                  DataCell(Text(cs.formatCents(item.averageOrderCents))),
                  DataCell(Text(
                    item.lastPurchaseDate != null
                        ? DateFormat.yMd().format(item.lastPurchaseDate!)
                        : '-',
                    style: theme.textTheme.bodySmall,
                  )),
                ]);
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Totals row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 400;
                final items = [
                  _TotalItem(
                    label: 'reports.total_revenue'.tr(),
                    value: cs.formatCents(data.grandTotalRevenueCents),
                    color: theme.colorScheme.primary,
                  ),
                  _TotalItem(
                    label: 'reports.total_transactions_label'.tr(),
                    value: data.grandTotalTransactions.toString(),
                  ),
                  _TotalItem(
                    label: 'reports.unique_customers'.tr(),
                    value: data.uniqueCustomerCount.toString(),
                  ),
                ];

                if (isWide) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: items,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items
                      .map((i) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: i,
                          ))
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _rankColor(int rank, ThemeData theme) {
    switch (rank) {
      case 1:
        return Colors.amber.shade700;
      case 2:
        return Colors.grey.shade500;
      case 3:
        return Colors.brown.shade400;
      default:
        return theme.colorScheme.onSurface;
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
}

// ═══════════════════════════════════════════════════════
// TOTAL ITEM
// ═══════════════════════════════════════════════════════

class _TotalItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _TotalItem({required this.label, required this.value, this.color});

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
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            )),
      ],
    );
  }
}
