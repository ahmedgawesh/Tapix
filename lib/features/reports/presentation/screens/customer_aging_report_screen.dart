import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/customer_aging_pdf_service.dart';
import '../bloc/customer_aging_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class CustomerAgingReportScreen extends StatelessWidget {
  const CustomerAgingReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerAgingReportBloc>(),
      child: const _CustomerAgingReportView(),
    );
  }
}

class _CustomerAgingReportView extends StatelessWidget {
  const _CustomerAgingReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.customer_aging_report'.tr()),
        actions: [
          BlocBuilder<CustomerAgingReportBloc,
              RealtimeState<CustomerAgingReportData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<CustomerAgingReportData>) {
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
      body: BlocBuilder<CustomerAgingReportBloc,
          RealtimeState<CustomerAgingReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<CustomerAgingReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<CustomerAgingReportData>) {
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

          if (state is RealtimeSuccess<CustomerAgingReportData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<CustomerAgingReportBloc>()
                        .add(CustomerAgingReportDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),

                // Summary cards
                _buildSummaryCards(context, state.data),
                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: _AgingReportContent(data: state.data),
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
      BuildContext context, CustomerAgingReportData data) {
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
              label: 'reports.total_receivables'.tr(),
              value: cs.formatCents(data.grandTotalCents),
              icon: LucideIcons.wallet,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.total_overdue'.tr(),
              value: cs.formatCents(data.grandTotalOverdueCents),
              icon: LucideIcons.alertTriangle,
              color: data.grandTotalOverdueCents > 0
                  ? colorScheme.error
                  : colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.customers_with_balance'.tr(),
              value: data.customerCount.toString(),
              icon: LucideIcons.users,
              color: colorScheme.tertiary,
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
      BuildContext context, CustomerAgingReportData data) async {
    await CustomerAgingPdfService.printCustomerAgingReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_customer_aging_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, CustomerAgingReportData data) async {
    await CustomerAgingPdfService.shareCustomerAgingReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_customer_aging_report',
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
// AGING REPORT CONTENT
// ═══════════════════════════════════════════════════════

class _AgingReportContent extends StatelessWidget {
  final CustomerAgingReportData data;
  const _AgingReportContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.customers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.checkCircle,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('reports.no_outstanding_balances'.tr(),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('reports.no_outstanding_balances_desc'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Aging summary card
        _buildAgingSummary(context, cs),
        const SizedBox(height: 16),

        // Customer aging table
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('reports.customer_aging_detail'.tr(),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              'reports.customer_count'.tr(args: ['${data.customers.length}']),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            horizontalMargin: 8,
            sortColumnIndex: _sortColumnIndex(data.sort),
            sortAscending: _isSortAscending(data.sort),
            columns: [
              DataColumn(
                label: Text('reports.customer'.tr()),
                onSort: (columnIndex, ascending) => _toggleSort(
                  context,
                  CustomerAgingSortType.nameAsc,
                  CustomerAgingSortType.nameDesc,
                  data.sort,
                ),
              ),
              DataColumn(
                label: Text('reports.aging_current'.tr()),
                numeric: true,
              ),
              DataColumn(
                label: Text('reports.aging_30'.tr()),
                numeric: true,
              ),
              DataColumn(
                label: Text('reports.aging_60'.tr()),
                numeric: true,
              ),
              DataColumn(
                label: Text('reports.aging_90'.tr()),
                numeric: true,
              ),
              DataColumn(
                label: Text('reports.aging_over_90'.tr()),
                numeric: true,
                onSort: (columnIndex, ascending) => _toggleSort(
                  context,
                  CustomerAgingSortType.over90Asc,
                  CustomerAgingSortType.over90Desc,
                  data.sort,
                ),
              ),
              DataColumn(
                label: Text('reports.aging_total'.tr()),
                numeric: true,
                onSort: (columnIndex, ascending) => _toggleSort(
                  context,
                  CustomerAgingSortType.totalAsc,
                  CustomerAgingSortType.totalDesc,
                  data.sort,
                ),
              ),
            ],
            rows: data.customers.map((item) {
              return DataRow(cells: [
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.phone != null && item.phone!.isNotEmpty)
                        Text(
                          item.phone!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                DataCell(Text(
                  item.currentCents > 0 ? cs.formatCents(item.currentCents) : '-',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                )),
                DataCell(Text(
                  item.days30Cents > 0 ? cs.formatCents(item.days30Cents) : '-',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                )),
                DataCell(Text(
                  item.days60Cents > 0 ? cs.formatCents(item.days60Cents) : '-',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error.withValues(alpha: 0.7),
                  ),
                )),
                DataCell(Text(
                  item.days90Cents > 0 ? cs.formatCents(item.days90Cents) : '-',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                )),
                DataCell(Text(
                  item.over90Cents > 0 ? cs.formatCents(item.over90Cents) : '-',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.error,
                  ),
                )),
                DataCell(Text(
                  cs.formatCents(item.totalCents),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                )),
              ]);
            }).toList(),
          ),
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
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  cs.formatCents(data.grandTotalCents),
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

  Widget _buildAgingSummary(BuildContext context, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('reports.aging_summary'.tr(),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _AgingSummaryRow(
              label: 'reports.aging_current'.tr(),
              value: cs.formatCents(data.grandTotalCurrentCents),
              color: colorScheme.primary,
            ),
            _AgingSummaryRow(
              label: 'reports.aging_30'.tr(),
              value: cs.formatCents(data.grandTotal30Cents),
              color: colorScheme.tertiary,
            ),
            _AgingSummaryRow(
              label: 'reports.aging_60'.tr(),
              value: cs.formatCents(data.grandTotal60Cents),
              color: colorScheme.error.withValues(alpha: 0.7),
            ),
            _AgingSummaryRow(
              label: 'reports.aging_90'.tr(),
              value: cs.formatCents(data.grandTotal90Cents),
              color: colorScheme.error,
            ),
            _AgingSummaryRow(
              label: 'reports.aging_over_90'.tr(),
              value: cs.formatCents(data.grandTotalOver90Cents),
              color: colorScheme.error,
            ),
            const Divider(),
            _AgingSummaryRow(
              label: 'reports.aging_total'.tr(),
              value: cs.formatCents(data.grandTotalCents),
              color: colorScheme.onSurface,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  int? _sortColumnIndex(CustomerAgingSortType sort) {
    switch (sort) {
      case CustomerAgingSortType.nameAsc:
      case CustomerAgingSortType.nameDesc:
        return 0;
      case CustomerAgingSortType.over90Asc:
      case CustomerAgingSortType.over90Desc:
        return 5;
      case CustomerAgingSortType.totalAsc:
      case CustomerAgingSortType.totalDesc:
        return 6;
    }
  }

  bool _isSortAscending(CustomerAgingSortType sort) {
    switch (sort) {
      case CustomerAgingSortType.nameAsc:
      case CustomerAgingSortType.totalAsc:
      case CustomerAgingSortType.over90Asc:
        return true;
      case CustomerAgingSortType.nameDesc:
      case CustomerAgingSortType.totalDesc:
      case CustomerAgingSortType.over90Desc:
        return false;
    }
  }

  void _toggleSort(
    BuildContext context,
    CustomerAgingSortType asc,
    CustomerAgingSortType desc,
    CustomerAgingSortType current,
  ) {
    final newSort = current == desc ? asc : desc;
    context
        .read<CustomerAgingReportBloc>()
        .add(CustomerAgingReportSortChanged(newSort));
  }
}

class _AgingSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _AgingSummaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.bold, color: color)
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
