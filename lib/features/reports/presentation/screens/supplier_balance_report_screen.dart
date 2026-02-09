import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/supplier_balance_pdf_service.dart';
import '../bloc/supplier_balance_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class SupplierBalanceReportScreen extends StatelessWidget {
  const SupplierBalanceReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SupplierBalanceReportBloc>(),
      child: const _SupplierBalanceReportView(),
    );
  }
}

class _SupplierBalanceReportView extends StatelessWidget {
  const _SupplierBalanceReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.supplier_balance'.tr()),
        actions: [
          BlocBuilder<SupplierBalanceReportBloc,
              RealtimeState<SupplierBalanceReportData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<SupplierBalanceReportData>) {
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
      body: BlocBuilder<SupplierBalanceReportBloc,
          RealtimeState<SupplierBalanceReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<SupplierBalanceReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<SupplierBalanceReportData>) {
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

          if (state is RealtimeSuccess<SupplierBalanceReportData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<SupplierBalanceReportBloc>()
                        .add(SupplierBalanceReportDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),

                // Summary cards
                _buildSummaryCards(context, state.data),
                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: _SupplierBalanceContent(data: state.data),
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
      BuildContext context, SupplierBalanceReportData data) {
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
              label: 'reports.total_payables'.tr(),
              value: cs.formatCents(data.grandTotalDebitCents),
              icon: LucideIcons.arrowUpRight,
              color: data.grandTotalDebitCents > 0
                  ? colorScheme.error
                  : colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.total_receivables'.tr(),
              value: cs.formatCents(data.grandTotalCreditCents),
              icon: LucideIcons.arrowDownLeft,
              color: colorScheme.tertiary,
            ),
            _SummaryCard(
              label: 'reports.net_balance'.tr(),
              value: cs.formatCents(data.grandNetBalanceCents),
              icon: LucideIcons.scale,
              color: data.grandNetBalanceCents > 0
                  ? colorScheme.error
                  : colorScheme.primary,
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
      BuildContext context, SupplierBalanceReportData data) async {
    await SupplierBalancePdfService.printSupplierBalanceReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_supplier_balance_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, SupplierBalanceReportData data) async {
    await SupplierBalancePdfService.shareSupplierBalanceReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_supplier_balance_report',
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
// SUPPLIER BALANCE CONTENT
// ═══════════════════════════════════════════════════════

class _SupplierBalanceContent extends StatelessWidget {
  final SupplierBalanceReportData data;
  const _SupplierBalanceContent({required this.data});

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
            Text('reports.no_supplier_balances'.tr(),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('reports.no_supplier_balances_desc'.tr(),
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
        return _SupplierBalanceCard(item: item, cs: cs);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUPPLIER BALANCE CARD
// ═══════════════════════════════════════════════════════

class _SupplierBalanceCard extends StatelessWidget {
  final SupplierBalanceItem item;
  final CurrencyService cs;

  const _SupplierBalanceCard({
    required this.item,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isPayable = item.netBalanceCents > 0;
    final balanceColor = isPayable ? colorScheme.error : colorScheme.primary;
    final balanceLabel = isPayable
        ? 'reports.payable'.tr()
        : item.netBalanceCents < 0
            ? 'reports.receivable'.tr()
            : 'reports.settled'.tr();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: name + balance badge
            Row(
              children: [
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
                    balanceLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: balanceColor,
                    ),
                  ),
                  backgroundColor: balanceColor.withValues(alpha: 0.1),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Balance metrics
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 400;
                final metrics = [
                  _MetricItem(
                    label: 'reports.total_debits'.tr(),
                    value: cs.formatCents(item.totalDebitCents),
                    valueColor: item.totalDebitCents > 0
                        ? colorScheme.error
                        : null,
                  ),
                  _MetricItem(
                    label: 'reports.total_credits'.tr(),
                    value: cs.formatCents(item.totalCreditCents),
                    valueColor: item.totalCreditCents > 0
                        ? colorScheme.primary
                        : null,
                  ),
                  _MetricItem(
                    label: 'reports.net_balance'.tr(),
                    value: cs.formatCents(item.netBalanceCents),
                    valueColor: balanceColor,
                  ),
                  _MetricItem(
                    label: 'reports.transactions'.tr(),
                    value: item.transactionCount.toString(),
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
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        Text(value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            )),
      ],
    );
  }
}
