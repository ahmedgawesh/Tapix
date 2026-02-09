import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/customer_sales_pdf_service.dart';
import '../bloc/customer_sales_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class CustomerSalesReportScreen extends StatelessWidget {
  const CustomerSalesReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerSalesReportBloc>(),
      child: const _CustomerSalesReportView(),
    );
  }
}

class _CustomerSalesReportView extends StatelessWidget {
  const _CustomerSalesReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.customer_sales'.tr()),
        actions: [
          BlocBuilder<CustomerSalesReportBloc,
              RealtimeState<CustomerSalesReportData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<CustomerSalesReportData>) {
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
      body: BlocBuilder<CustomerSalesReportBloc,
          RealtimeState<CustomerSalesReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<CustomerSalesReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<CustomerSalesReportData>) {
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

          if (state is RealtimeSuccess<CustomerSalesReportData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<CustomerSalesReportBloc>()
                        .add(CustomerSalesReportDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),

                // Summary cards
                _buildSummaryCards(context, state.data),
                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: _CustomerSalesContent(data: state.data),
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
      BuildContext context, CustomerSalesReportData data) {
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
              label: 'reports.invoice_count'.tr(),
              value: data.grandTotalInvoices.toString(),
              icon: LucideIcons.receipt,
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
      BuildContext context, CustomerSalesReportData data) async {
    await CustomerSalesPdfService.printCustomerSalesReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_customer_sales_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, CustomerSalesReportData data) async {
    await CustomerSalesPdfService.shareCustomerSalesReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_customer_sales_report',
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
// CUSTOMER SALES CONTENT
// ═══════════════════════════════════════════════════════

class _CustomerSalesContent extends StatelessWidget {
  final CustomerSalesReportData data;
  const _CustomerSalesContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.customers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.shoppingCart,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('reports.no_sales_data'.tr(),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('reports.no_sales_data_desc'.tr(),
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
        // Customer sales table
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('reports.customer_sales_details'.tr(),
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
              const DataColumn(
                label: Text('#'),
                numeric: true,
              ),
              DataColumn(
                label: Text('reports.customer'.tr()),
                onSort: (columnIndex, ascending) => _toggleSort(
                  context,
                  CustomerSalesSortType.nameAsc,
                  CustomerSalesSortType.nameDesc,
                  data.sort,
                ),
              ),
              DataColumn(
                label: Text('reports.segment'.tr()),
              ),
              DataColumn(
                label: Text('reports.total_sales'.tr()),
                numeric: true,
                onSort: (columnIndex, ascending) => _toggleSort(
                  context,
                  CustomerSalesSortType.revenueAsc,
                  CustomerSalesSortType.revenueDesc,
                  data.sort,
                ),
              ),
              DataColumn(
                label: Text('reports.invoices'.tr()),
                numeric: true,
                onSort: (columnIndex, ascending) => _toggleSort(
                  context,
                  CustomerSalesSortType.invoiceCountAsc,
                  CustomerSalesSortType.invoiceCountDesc,
                  data.sort,
                ),
              ),
              DataColumn(
                label: Text('reports.avg_order'.tr()),
                numeric: true,
              ),
              DataColumn(
                label: Text('reports.last_sale'.tr()),
              ),
            ],
            rows: data.customers.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final item = entry.value;
              return DataRow(cells: [
                DataCell(Text(
                  '$idx',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: idx <= 3
                        ? _rankColor(idx, theme.colorScheme)
                        : null,
                  ),
                )),
                DataCell(Text(
                  item.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )),
                DataCell(Text(
                  _segmentLabel(item.segment),
                  style: theme.textTheme.bodySmall,
                )),
                DataCell(Text(
                  cs.formatCents(item.totalSalesCents),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                )),
                DataCell(Text(
                  '${item.invoiceCount}',
                  style: theme.textTheme.bodySmall,
                )),
                DataCell(Text(
                  cs.formatCents(item.averageOrderCents),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )),
                DataCell(Text(
                  item.lastSaleDate != null
                      ? DateFormat.yMd().format(item.lastSaleDate!)
                      : '-',
                  style: theme.textTheme.bodySmall,
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
                  cs.formatCents(data.grandTotalSalesCents),
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

  Color _rankColor(int rank, ColorScheme colorScheme) {
    switch (rank) {
      case 1:
        return Colors.amber.shade700;
      case 2:
        return Colors.blueGrey.shade400;
      case 3:
        return Colors.brown.shade400;
      default:
        return colorScheme.onSurface;
    }
  }

  int? _sortColumnIndex(CustomerSalesSortType sort) {
    switch (sort) {
      case CustomerSalesSortType.nameAsc:
      case CustomerSalesSortType.nameDesc:
        return 1;
      case CustomerSalesSortType.revenueAsc:
      case CustomerSalesSortType.revenueDesc:
        return 3;
      case CustomerSalesSortType.invoiceCountAsc:
      case CustomerSalesSortType.invoiceCountDesc:
        return 4;
    }
  }

  bool _isSortAscending(CustomerSalesSortType sort) {
    switch (sort) {
      case CustomerSalesSortType.nameAsc:
      case CustomerSalesSortType.revenueAsc:
      case CustomerSalesSortType.invoiceCountAsc:
        return true;
      case CustomerSalesSortType.nameDesc:
      case CustomerSalesSortType.revenueDesc:
      case CustomerSalesSortType.invoiceCountDesc:
        return false;
    }
  }

  void _toggleSort(
    BuildContext context,
    CustomerSalesSortType asc,
    CustomerSalesSortType desc,
    CustomerSalesSortType current,
  ) {
    final newSort = current == desc ? asc : desc;
    context
        .read<CustomerSalesReportBloc>()
        .add(CustomerSalesReportSortChanged(newSort));
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
