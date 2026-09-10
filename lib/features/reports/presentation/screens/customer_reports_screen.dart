import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../bloc/customer_reports_bloc.dart';
import '../services/customer_report_pdf_service.dart';
import '../widgets/date_range_selector.dart';

class CustomerReportsScreen extends StatelessWidget {
  const CustomerReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerReportsBloc>(),
      child: const _CustomerReportsView(),
    );
  }
}

class _CustomerReportsView extends StatelessWidget {
  const _CustomerReportsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('reports.customer_reports'.tr()),
          actions: [
            BlocBuilder<
              CustomerReportsBloc,
              RealtimeState<CustomerReportsData>
            >(
              builder: (context, state) {
                if (state is! RealtimeSuccess<CustomerReportsData>) {
                  return const SizedBox.shrink();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.printer),
                      tooltip: 'common.print'.tr(),
                      onPressed: () =>
                          CustomerReportPdfService.printAllCustomersReport(
                            context: context,
                            data: state.data,
                          ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.share2),
                      tooltip: 'common.share'.tr(),
                      onPressed: () =>
                          CustomerReportPdfService.shareAllCustomersReport(
                            context: context,
                            data: state.data,
                          ),
                    ),
                  ],
                );
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'reports.customer_statement'.tr()),
              Tab(text: 'reports.customer_aging'.tr()),
              Tab(text: 'reports.customer_analytics'.tr()),
            ],
          ),
        ),
        body:
            BlocBuilder<
              CustomerReportsBloc,
              RealtimeState<CustomerReportsData>
            >(
              builder: (context, state) {
                if (state is RealtimeLoading<CustomerReportsData>) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is RealtimeError<CustomerReportsData>) {
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

                if (state is RealtimeSuccess<CustomerReportsData>) {
                  return Column(
                    children: [
                      // Date range selector
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: DateRangeSelector(
                          dateRange: state.data.dateRange,
                          onChanged: (range) => context
                              .read<CustomerReportsBloc>()
                              .add(CustomerReportsDateRangeChanged(range)),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Tab views
                      Expanded(
                        child: TabBarView(
                          children: [
                            _StatementTab(data: state.data),
                            _AgingTab(data: state.data),
                            _AnalyticsTab(data: state.data),
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
}

// ═══════════════════════════════════════════════════════
// SUMMARY CARDS (used in Statement tab)
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
// STATEMENT TAB (rebuilt)
// ═══════════════════════════════════════════════════════

class _StatementTab extends StatelessWidget {
  final CustomerReportsData data;
  const _StatementTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();
    final filtered = data.filteredCustomers;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Summary cards ──
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'reports.total_receivables'.tr(),
                value: cs.formatCents(data.totalReceivablesCents),
                icon: LucideIcons.trendingUp,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                label: 'reports.total_payables'.tr(),
                value: cs.formatCents(data.totalPayablesCents),
                icon: LucideIcons.trendingDown,
                color: colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'reports.opening_debit'.tr(),
                value: cs.formatCents(data.totalOpeningDebitCents),
                icon: LucideIcons.arrowUpRight,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                label: 'reports.opening_credit'.tr(),
                value: cs.formatCents(data.totalOpeningCreditCents),
                icon: LucideIcons.arrowDownRight,
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'reports.total_discounts'.tr(),
                value: cs.formatCents(data.totalDiscountsCents),
                icon: LucideIcons.percent,
                color: colorScheme.tertiary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                label: 'reports.total_payments'.tr(),
                value: cs.formatCents(data.totalPaymentsCents),
                icon: LucideIcons.banknote,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: _SummaryCard(
            label: 'reports.active_customers'.tr(),
            value: data.activeCustomerCount.toString(),
            icon: LucideIcons.users,
            color: colorScheme.tertiary,
          ),
        ),

        const SizedBox(height: 16),

        // ── Search ──
        TextField(
          decoration: InputDecoration(
            hintText: 'reports.search_customers'.tr(),
            prefixIcon: const Icon(LucideIcons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            isDense: true,
          ),
          onChanged: (q) => context.read<CustomerReportsBloc>().add(
            CustomerReportsSearchChanged(q),
          ),
        ),

        const SizedBox(height: 16),

        // ── Per-customer list ──
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    LucideIcons.fileText,
                    size: 48,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'reports.no_customer_data'.tr(),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          )
        else
          ...filtered.map((c) => _CustomerBalanceCard(customer: c, cs: cs)),
      ],
    );
  }
}

class _CustomerBalanceCard extends StatelessWidget {
  final CustomerBalanceItem customer;
  final CurrencyService cs;

  const _CustomerBalanceCard({required this.customer, required this.cs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bal = customer.currentBalanceCents;
    final isReceivable = bal > 0;
    final isZero = bal == 0;
    final balColor = isZero
        ? colorScheme.onSurface
        : isReceivable
        ? Colors.green
        : colorScheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          customer.customerName,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${'customers.balance'.tr()}: ${cs.formatCents(bal)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: balColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // PDF button per customer
            IconButton(
              icon: Icon(
                LucideIcons.fileText,
                size: 18,
                color: colorScheme.primary,
              ),
              tooltip: 'reports.customer_pdf'.tr(),
              onPressed: () =>
                  CustomerReportPdfService.printSingleCustomerReport(
                    context: context,
                    customer: customer,
                  ),
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                _BalanceRow(
                  label: 'reports.opening_balance'.tr(),
                  value: cs.formatCents(customer.openingBalanceCents),
                  subLabel: customer.openingBalanceCents > 0
                      ? '(${'customers.opening_balance_receivable'.tr()})'
                      : customer.openingBalanceCents < 0
                      ? '(${'customers.opening_balance_payable'.tr()})'
                      : null,
                ),
                _BalanceRow(
                  label: 'reports.total_sales'.tr(),
                  value: cs.formatCents(customer.totalSalesCents),
                ),
                _BalanceRow(
                  label: 'reports.total_payments'.tr(),
                  value: cs.formatCents(customer.totalPaymentsCents),
                ),
                _BalanceRow(
                  label: 'reports.total_discounts'.tr(),
                  value: cs.formatCents(customer.totalDiscountsCents),
                ),
                _BalanceRow(
                  label: 'reports.total_returns'.tr(),
                  value: cs.formatCents(customer.totalReturnsCents),
                ),
                const Divider(),
                _BalanceRow(
                  label: 'reports.current_balance'.tr(),
                  value: cs.formatCents(bal),
                  valueColor: balColor,
                  isBold: true,
                  subLabel: isZero
                      ? 'customers.balance_settled'.tr()
                      : isReceivable
                      ? 'customers.balance_receivable'.tr()
                      : 'customers.balance_credit'.tr(),
                ),
                const SizedBox(height: 8),
                // Navigate to customer profile
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(LucideIcons.user, size: 16),
                    label: Text('reports.view_customer_profile'.tr()),
                    onPressed: () =>
                        context.push('/customers/${customer.customerId}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  final String label;
  final String value;
  final String? subLabel;
  final Color? valueColor;
  final bool isBold;

  const _BalanceRow({
    required this.label,
    required this.value,
    this.subLabel,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: isBold
                    ? theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      )
                    : theme.textTheme.bodySmall,
              ),
              if (subLabel != null)
                Text(
                  subLabel!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          Text(
            value,
            style:
                (isBold
                        ? theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          )
                        : theme.textTheme.bodySmall)
                    ?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// AGING TAB
// ═══════════════════════════════════════════════════════

class _AgingTab extends StatelessWidget {
  final CustomerReportsData data;
  const _AgingTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.agingItems.isEmpty) {
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
              'reports.no_outstanding_balances'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.no_outstanding_balances_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    int totalCurrent = 0,
        total30 = 0,
        total60 = 0,
        total90 = 0,
        totalOver90 = 0,
        grandTotal = 0;
    for (final item in data.agingItems) {
      totalCurrent += item.currentCents;
      total30 += item.days30Cents;
      total60 += item.days60Cents;
      total90 += item.days90Cents;
      totalOver90 += item.over90Cents;
      grandTotal += item.totalCents;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'reports.aging_summary'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AgingSummaryRow(
                    label: 'reports.aging_current'.tr(),
                    value: cs.formatCents(totalCurrent),
                    color: theme.colorScheme.primary,
                  ),
                  _AgingSummaryRow(
                    label: 'reports.aging_30'.tr(),
                    value: cs.formatCents(total30),
                    color: theme.colorScheme.tertiary,
                  ),
                  _AgingSummaryRow(
                    label: 'reports.aging_60'.tr(),
                    value: cs.formatCents(total60),
                    color: theme.colorScheme.error.withValues(alpha: 0.7),
                  ),
                  _AgingSummaryRow(
                    label: 'reports.aging_90'.tr(),
                    value: cs.formatCents(total90),
                    color: theme.colorScheme.error,
                  ),
                  _AgingSummaryRow(
                    label: 'reports.aging_over_90'.tr(),
                    value: cs.formatCents(totalOver90),
                    color: theme.colorScheme.error,
                  ),
                  const Divider(),
                  _AgingSummaryRow(
                    label: 'reports.aging_total'.tr(),
                    value: cs.formatCents(grandTotal),
                    color: theme.colorScheme.onSurface,
                    isBold: true,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'reports.customer_aging_detail'.tr(),
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
                  label: Text('reports.aging_current'.tr()),
                  numeric: true,
                ),
                DataColumn(label: Text('reports.aging_30'.tr()), numeric: true),
                DataColumn(label: Text('reports.aging_60'.tr()), numeric: true),
                DataColumn(label: Text('reports.aging_90'.tr()), numeric: true),
                DataColumn(
                  label: Text('reports.aging_over_90'.tr()),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('reports.aging_total'.tr()),
                  numeric: true,
                ),
              ],
              rows: data.agingItems.map((item) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        item.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DataCell(
                      Text(
                        item.currentCents > 0
                            ? cs.formatCents(item.currentCents)
                            : '-',
                      ),
                    ),
                    DataCell(
                      Text(
                        item.days30Cents > 0
                            ? cs.formatCents(item.days30Cents)
                            : '-',
                      ),
                    ),
                    DataCell(
                      Text(
                        item.days60Cents > 0
                            ? cs.formatCents(item.days60Cents)
                            : '-',
                      ),
                    ),
                    DataCell(
                      Text(
                        item.days90Cents > 0
                            ? cs.formatCents(item.days90Cents)
                            : '-',
                      ),
                    ),
                    DataCell(
                      Text(
                        item.over90Cents > 0
                            ? cs.formatCents(item.over90Cents)
                            : '-',
                      ),
                    ),
                    DataCell(
                      Text(
                        cs.formatCents(item.totalCents),
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
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          )
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ANALYTICS TAB
// ═══════════════════════════════════════════════════════

class _AnalyticsTab extends StatelessWidget {
  final CustomerReportsData data;
  const _AnalyticsTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.analyticsItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.users,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'reports.no_customer_data'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    final segmentCounts = <String, int>{};
    int totalSpent = 0;
    for (final item in data.analyticsItems) {
      segmentCounts[item.segment] = (segmentCounts[item.segment] ?? 0) + 1;
      totalSpent += item.totalSpentCents;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'reports.segment_overview'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: segmentCounts.entries.map((e) {
                    return Chip(
                      label: Text('${_segmentLabel(e.key)}: ${e.value}'),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'reports.total_spent'.tr(),
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      cs.formatCents(totalSpent),
                      style: theme.textTheme.titleSmall?.copyWith(
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
        Text(
          'reports.customer_analytics_detail'.tr(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...data.analyticsItems.map(
          (item) => Card(
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
                          item.customerName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Chip(
                        label: Text(
                          _segmentLabel(item.segment),
                          style: theme.textTheme.labelSmall,
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 400;
                      final metrics = [
                        _MetricItem(
                          label: 'reports.total_spent'.tr(),
                          value: cs.formatCents(item.totalSpentCents),
                        ),
                        _MetricItem(
                          label: 'reports.transactions'.tr(),
                          value: item.totalTransactions.toString(),
                        ),
                        _MetricItem(
                          label: 'reports.avg_order'.tr(),
                          value: cs.formatCents(item.averageOrderCents),
                        ),
                        _MetricItem(
                          label: 'reports.balance'.tr(),
                          value: cs.formatCents(item.balanceCents),
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
                  if (item.lastTransactionAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${'reports.last_transaction'.tr()}: ${DateFormat('dd/MM/yyyy').format(item.lastTransactionAt!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
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
