import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../accounting/presentation/services/journal_pdf_service.dart';
import '../bloc/customer_sales_returns_reports_bloc.dart';
import '../widgets/date_range_selector.dart';

String _reasonLabel(String reason) {
  switch (reason) {
    case 'wrong_size':
      return 'reports.reason_wrong_size'.tr();
    case 'defective':
      return 'reports.reason_defective'.tr();
    case 'wrong_item':
      return 'reports.reason_wrong_item'.tr();
    case 'changed_mind':
      return 'reports.reason_changed_mind'.tr();
    case 'other':
      return 'reports.reason_other'.tr();
    default:
      return reason;
  }
}

class CustomerSalesReturnsReportsScreen extends StatelessWidget {
  const CustomerSalesReturnsReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerSalesReturnsBloc>(),
      child: const _CustomerSalesReturnsView(),
    );
  }
}

class _CustomerSalesReturnsView extends StatelessWidget {
  const _CustomerSalesReturnsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('reports.customer_returns'.tr()),
          actions: [
            BlocBuilder<
              CustomerSalesReturnsBloc,
              RealtimeState<CustomerSalesReturnsData>
            >(
              builder: (context, state) {
                if (state is! RealtimeSuccess<CustomerSalesReturnsData>) {
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
          bottom: TabBar(
            tabs: [
              Tab(text: 'reports.returns_by_customer'.tr()),
              Tab(text: 'reports.return_details'.tr()),
              Tab(text: 'reports.return_reasons'.tr()),
            ],
          ),
        ),
        body:
            BlocBuilder<
              CustomerSalesReturnsBloc,
              RealtimeState<CustomerSalesReturnsData>
            >(
              builder: (context, state) {
                if (state is RealtimeLoading<CustomerSalesReturnsData>) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is RealtimeError<CustomerSalesReturnsData>) {
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

                if (state is RealtimeSuccess<CustomerSalesReturnsData>) {
                  return Column(
                    children: [
                      // Date range selector
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: DateRangeSelector(
                          dateRange: state.data.dateRange,
                          onChanged: (range) => context
                              .read<CustomerSalesReturnsBloc>()
                              .add(CustomerSalesReturnsDateRangeChanged(range)),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Summary cards
                      _buildSummaryCards(context, state.data),
                      const SizedBox(height: 8),

                      // Tab views
                      Expanded(
                        child: TabBarView(
                          children: [
                            _CustomerSummaryTab(data: state.data),
                            _ReturnDetailsTab(data: state.data),
                            _ReturnReasonsTab(data: state.data),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return const SizedBox.shrink();
              },
            ),
      ),
    );
  }

  Widget _buildSummaryCards(
    BuildContext context,
    CustomerSalesReturnsData data,
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
              label: 'reports.total_returns_value'.tr(),
              value: cs.formatCents(data.totalReturnsCents),
              icon: LucideIcons.undo2,
              color: colorScheme.error,
            ),
            _SummaryCard(
              label: 'reports.total_return_count'.tr(),
              value: data.totalReturnCount.toString(),
              icon: LucideIcons.fileText,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.customers_with_returns'.tr(),
              value: data.customersWithReturns.toString(),
              icon: LucideIcons.users,
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
    CustomerSalesReturnsData data,
  ) async {
    await JournalPdfService.printCustomerReturnsReport(
      context: context,
      customerSummaries: data.customerSummaries,
      returnDetails: data.returnDetails,
      reasonBreakdown: data.reasonBreakdown,
      returnedProducts: data.returnedProducts,
      totalReturnsCents: data.totalReturnsCents,
      totalReturnCount: data.totalReturnCount,
      dateRange: data.dateRange,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_customer_returns_report',
    );
  }

  Future<void> _shareReport(
    BuildContext context,
    CustomerSalesReturnsData data,
  ) async {
    await JournalPdfService.shareCustomerReturnsReport(
      context: context,
      customerSummaries: data.customerSummaries,
      returnDetails: data.returnDetails,
      reasonBreakdown: data.reasonBreakdown,
      returnedProducts: data.returnedProducts,
      totalReturnsCents: data.totalReturnsCents,
      totalReturnCount: data.totalReturnCount,
      dateRange: data.dateRange,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_customer_returns_report',
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
// CUSTOMER SUMMARY TAB
// ═══════════════════════════════════════════════════════

class _CustomerSummaryTab extends StatelessWidget {
  final CustomerSalesReturnsData data;
  const _CustomerSummaryTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.customerSummaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.checkCircle,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'reports.no_customer_returns'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.no_customer_returns_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
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
            'reports.returns_by_customer_detail'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              horizontalMargin: 8,
              columns: [
                DataColumn(label: Text('reports.customer'.tr())),
                DataColumn(
                  label: Text('reports.return_count_short'.tr()),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('reports.items_returned'.tr()),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('reports.total_returned'.tr()),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('reports.avg_return'.tr()),
                  numeric: true,
                ),
                DataColumn(label: Text('reports.last_return'.tr())),
              ],
              rows: data.customerSummaries.map((item) {
                return DataRow(
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          item.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(item.returnCount.toString())),
                    DataCell(
                      Text(
                        data.returnedProducts.any(
                              (product) => product.measurementType != 'piece',
                            )
                            ? '—'
                            : item.totalItemsReturned.toString(),
                      ),
                    ),
                    DataCell(
                      Text(
                        cs.formatCents(item.totalReturnedCents),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                    DataCell(Text(cs.formatCents(item.averageReturnCents))),
                    DataCell(
                      Text(
                        item.lastReturnDate != null
                            ? DateFormat.yMd().format(item.lastReturnDate!)
                            : '-',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                );
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
                    label: 'reports.total_returns_value'.tr(),
                    value: cs.formatCents(data.totalReturnsCents),
                    color: theme.colorScheme.error,
                  ),
                  _TotalItem(
                    label: 'reports.total_return_count'.tr(),
                    value: data.totalReturnCount.toString(),
                  ),
                  _TotalItem(
                    label: 'reports.total_items_returned'.tr(),
                    value: localizedQuantityTotals(
                      aggregateQuantityTotals(
                        data.returnedProducts,
                        quantityOf: (item) => item.quantity,
                        measurementTypeOf: (item) => item.measurementType,
                      ),
                    ),
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
                      .map(
                        (i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: i,
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// RETURN DETAILS TAB
// ═══════════════════════════════════════════════════════

class _ReturnDetailsTab extends StatelessWidget {
  final CustomerSalesReturnsData data;
  const _ReturnDetailsTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.returnDetails.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.fileText,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'reports.no_return_details'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: data.returnDetails.length,
      itemBuilder: (context, index) {
        final item = data.returnDetails[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.returnNumber,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Chip(
                      label: Text(
                        _dispositionLabel(item.dispositionType),
                        style: theme.textTheme.labelSmall,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: theme.colorScheme.secondaryContainer,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 400;
                    final metrics = [
                      _MetricItem(
                        label: 'reports.return_date_label'.tr(),
                        value: DateFormat.yMd().format(item.returnDate),
                      ),
                      _MetricItem(
                        label: 'reports.refund_method'.tr(),
                        value: _refundMethodLabel(item.refundMethod),
                      ),
                      _MetricItem(
                        label: 'reports.items_returned'.tr(),
                        value: item.itemCount.toString(),
                      ),
                      _MetricItem(
                        label: 'reports.total_returned'.tr(),
                        value: cs.formatCents(item.totalCents),
                        valueColor: theme.colorScheme.error,
                      ),
                    ];

                    if (isWide) {
                      return Row(
                        children: metrics
                            .map((m) => Expanded(child: m))
                            .toList(),
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
                if (item.reason != null && item.reason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${'reports.reason'.tr()}: ${_reasonLabel(item.reason!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (item.originalInvoiceNumber != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${'reports.original_invoice'.tr()}: ${item.originalInvoiceNumber}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _dispositionLabel(String type) {
    switch (type) {
      case 'restock':
        return 'reports.disposition_restock'.tr();
      case 'write_off':
        return 'reports.disposition_write_off'.tr();
      case 'exchange':
        return 'reports.disposition_exchange'.tr();
      case 'store_credit':
        return 'reports.disposition_store_credit'.tr();
      case 'refund':
        return 'reports.disposition_refund'.tr();
      case 'adjustment':
        return 'reports.disposition_adjustment'.tr();
      default:
        return type;
    }
  }

  String _refundMethodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'reports.refund_cash'.tr();
      case 'credit':
        return 'reports.refund_credit'.tr();
      case 'cheque':
        return 'reports.refund_cheque'.tr();
      default:
        return method;
    }
  }
}

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

// ═══════════════════════════════════════════════════════
// RETURN REASONS TAB
// ═══════════════════════════════════════════════════════

class _ReturnReasonsTab extends StatelessWidget {
  final CustomerSalesReturnsData data;
  const _ReturnReasonsTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.reasonBreakdown.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.pieChart,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'reports.no_return_reasons'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    // Calculate totals for percentage
    int grandTotalCount = 0;
    int grandTotalCents = 0;
    for (final r in data.reasonBreakdown) {
      grandTotalCount += r.count;
      grandTotalCents += r.totalCents;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reason summary card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'reports.return_reason_breakdown'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...data.reasonBreakdown.map((r) {
                    final pct = grandTotalCount > 0
                        ? (r.count / grandTotalCount * 100)
                        : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _reasonLabel(r.reason),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${r.count} (${pct.toStringAsFixed(1)}%)',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: grandTotalCount > 0
                                  ? r.count / grandTotalCount
                                  : 0,
                              minHeight: 8,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              color: _reasonColor(r.reason, theme),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cs.formatCents(r.totalCents),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'reports.aging_total'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$grandTotalCount — ${cs.formatCents(grandTotalCents)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Detailed table
          Text(
            'reports.return_reason_detail'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              horizontalMargin: 8,
              columns: [
                DataColumn(label: Text('reports.reason'.tr())),
                DataColumn(
                  label: Text('reports.return_count_short'.tr()),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('reports.percentage'.tr()),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('reports.total_returned'.tr()),
                  numeric: true,
                ),
              ],
              rows: data.reasonBreakdown.map((r) {
                final pct = grandTotalCount > 0
                    ? (r.count / grandTotalCount * 100)
                    : 0.0;
                return DataRow(
                  cells: [
                    DataCell(Text(_reasonLabel(r.reason))),
                    DataCell(Text(r.count.toString())),
                    DataCell(Text('${pct.toStringAsFixed(1)}%')),
                    DataCell(
                      Text(
                        cs.formatCents(r.totalCents),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Color _reasonColor(String reason, ThemeData theme) {
    switch (reason) {
      case 'defective':
        return theme.colorScheme.error;
      case 'wrong_size':
        return theme.colorScheme.tertiary;
      case 'wrong_item':
        return theme.colorScheme.error.withValues(alpha: 0.7);
      case 'changed_mind':
        return theme.colorScheme.primary;
      default:
        return theme.colorScheme.tertiary;
    }
  }
}
