import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/supplier_debit_balance_pdf_service.dart';
import '../bloc/supplier_debit_balance_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class SupplierDebitBalanceReportScreen extends StatelessWidget {
  const SupplierDebitBalanceReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SupplierDebitBalanceReportBloc>(),
      child: const _SupplierDebitBalanceReportView(),
    );
  }
}

class _SupplierDebitBalanceReportView extends StatelessWidget {
  const _SupplierDebitBalanceReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.supplier_debit_balance'.tr()),
        actions: [
          BlocBuilder<SupplierDebitBalanceReportBloc,
              RealtimeState<SupplierDebitBalanceReportData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<SupplierDebitBalanceReportData>) {
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
      body: BlocBuilder<SupplierDebitBalanceReportBloc,
          RealtimeState<SupplierDebitBalanceReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<SupplierDebitBalanceReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<SupplierDebitBalanceReportData>) {
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

          if (state is RealtimeSuccess<SupplierDebitBalanceReportData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<SupplierDebitBalanceReportBloc>()
                        .add(SupplierDebitBalanceReportDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),

                // Summary cards
                _buildSummaryCards(context, state.data),
                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: _SupplierDebitBalanceContent(data: state.data),
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
      BuildContext context, SupplierDebitBalanceReportData data) {
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
              color: colorScheme.error,
            ),
            _SummaryCard(
              label: 'reports.total_payments'.tr(),
              value: cs.formatCents(data.grandTotalPaymentsCents),
              icon: LucideIcons.banknote,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.debit_balance'.tr(),
              value: cs.formatCents(data.grandTotalDebitBalanceCents),
              icon: LucideIcons.arrowUpRight,
              color: data.grandTotalDebitBalanceCents > 0
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
      BuildContext context, SupplierDebitBalanceReportData data) async {
    await SupplierDebitBalancePdfService.printSupplierDebitBalanceReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_supplier_debit_balance_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, SupplierDebitBalanceReportData data) async {
    await SupplierDebitBalancePdfService.shareSupplierDebitBalanceReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_supplier_debit_balance_report',
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
// SUPPLIER DEBIT BALANCE CONTENT
// ═══════════════════════════════════════════════════════

class _SupplierDebitBalanceContent extends StatelessWidget {
  final SupplierDebitBalanceReportData data;
  const _SupplierDebitBalanceContent({required this.data});

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
            Text('reports.no_supplier_debit_balances'.tr(),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('reports.no_supplier_debit_balances_desc'.tr(),
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
        return _SupplierDebitBalanceCard(item: item, cs: cs);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUPPLIER DEBIT BALANCE CARD
// ═══════════════════════════════════════════════════════

class _SupplierDebitBalanceCard extends StatelessWidget {
  final SupplierDebitBalanceItem item;
  final CurrencyService cs;

  const _SupplierDebitBalanceCard({
    required this.item,
    required this.cs,
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
            // Header row: name + debit badge
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
                    'reports.payable'.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                  backgroundColor: colorScheme.error.withValues(alpha: 0.1),
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
                    label: 'reports.total_purchases'.tr(),
                    value: cs.formatCents(item.totalPurchasesCents),
                    valueColor: colorScheme.error,
                  ),
                  _MetricItem(
                    label: 'reports.total_payments'.tr(),
                    value: cs.formatCents(item.totalPaymentsCents),
                    valueColor: colorScheme.primary,
                  ),
                  _MetricItem(
                    label: 'reports.debit_balance'.tr(),
                    value: cs.formatCents(item.debitBalanceCents),
                    valueColor: colorScheme.error,
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
