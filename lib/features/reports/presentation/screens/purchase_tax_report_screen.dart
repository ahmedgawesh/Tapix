import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/purchase_tax_pdf_service.dart';
import '../bloc/purchase_tax_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class PurchaseTaxReportScreen extends StatelessWidget {
  const PurchaseTaxReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PurchaseTaxReportBloc>(),
      child: const _PurchaseTaxReportView(),
    );
  }
}

class _PurchaseTaxReportView extends StatelessWidget {
  const _PurchaseTaxReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.purchase_tax_report'.tr()),
        actions: [
          BlocBuilder<PurchaseTaxReportBloc,
              RealtimeState<PurchaseTaxReportData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<PurchaseTaxReportData>) {
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
      body: BlocBuilder<PurchaseTaxReportBloc,
          RealtimeState<PurchaseTaxReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<PurchaseTaxReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<PurchaseTaxReportData>) {
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

          if (state is RealtimeSuccess<PurchaseTaxReportData>) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<PurchaseTaxReportBloc>()
                        .add(PurchaseTaxReportDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),
                _buildSummaryCards(context, state.data),
                const SizedBox(height: 8),
                Expanded(
                  child: _PurchaseTaxContent(data: state.data),
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
      BuildContext context, PurchaseTaxReportData data) {
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
              label: 'reports.tax_paid'.tr(),
              value: cs.formatCents(data.totalTaxPaidCents),
              icon: LucideIcons.receipt,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.tax_returns'.tr(),
              value: '- ${cs.formatCents(data.returnTaxCents)}',
              icon: LucideIcons.undo2,
              color: colorScheme.error,
            ),
            _SummaryCard(
              label: 'reports.net_tax'.tr(),
              value: cs.formatCents(data.netTaxCents),
              icon: LucideIcons.landmark,
              color: colorScheme.tertiary,
            ),
            _SummaryCard(
              label: 'reports.taxable_amount'.tr(),
              value: cs.formatCents(data.totalTaxableCents),
              icon: LucideIcons.calculator,
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
              Row(children: [
                Expanded(child: Padding(
                    padding: const EdgeInsets.only(right: 4), child: cards[0])),
                Expanded(child: Padding(
                    padding: const EdgeInsets.only(left: 4), child: cards[1])),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Padding(
                    padding: const EdgeInsets.only(right: 4), child: cards[2])),
                Expanded(child: Padding(
                    padding: const EdgeInsets.only(left: 4), child: cards[3])),
              ]),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, PurchaseTaxReportData data) async {
    await PurchaseTaxPdfService.printPurchaseTaxReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_purchase_tax_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, PurchaseTaxReportData data) async {
    await PurchaseTaxPdfService.sharePurchaseTaxReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_purchase_tax_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// CONTENT
// ═══════════════════════════════════════════════════════

class _PurchaseTaxContent extends StatelessWidget {
  final PurchaseTaxReportData data;
  const _PurchaseTaxContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    if (data.invoices.isEmpty && data.returns.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.receipt, size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('reports.no_tax_data'.tr(),
                style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: '${'reports.invoices'.tr()} (${data.invoiceCount})'),
              Tab(text: '${'reports.returns_tab'.tr()} (${data.returnCount})'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _InvoicesTab(invoices: data.invoices, cs: cs),
                _ReturnsTab(returns: data.returns, cs: cs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoicesTab extends StatelessWidget {
  final List<PurchaseTaxInvoiceItem> invoices;
  final CurrencyService cs;
  const _InvoicesTab({required this.invoices, required this.cs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (invoices.isEmpty) {
      return Center(child: Text('reports.no_invoices'.tr()));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: invoices.length,
      separatorBuilder: (context, i) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final inv = invoices[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.fileText, size: 16,
                        color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(inv.purchaseNumber,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600)),
                    ),
                    Text(DateFormat.yMMMd().format(inv.purchaseDate),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant)),
                  ],
                ),
                if (inv.supplierName != null) ...[
                  const SizedBox(height: 4),
                  Text(inv.supplierName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _DetailCol(
                      label: 'reports.taxable_amount'.tr(),
                      value: cs.formatCents(inv.taxableCents),
                    )),
                    Expanded(child: _DetailCol(
                      label: 'reports.tax_amount'.tr(),
                      value: cs.formatCents(inv.taxCents),
                      valueColor: colorScheme.error,
                    )),
                    Expanded(child: _DetailCol(
                      label: 'reports.total'.tr(),
                      value: cs.formatCents(inv.totalCents),
                      valueColor: colorScheme.primary,
                    )),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReturnsTab extends StatelessWidget {
  final List<PurchaseTaxReturnItem> returns;
  final CurrencyService cs;
  const _ReturnsTab({required this.returns, required this.cs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (returns.isEmpty) {
      return Center(child: Text('reports.no_returns_data'.tr()));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: returns.length,
      separatorBuilder: (context, i) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ret = returns[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.undo2, size: 16,
                        color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(ret.returnNumber,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600)),
                    ),
                    Text(DateFormat.yMMMd().format(ret.returnDate),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant)),
                  ],
                ),
                if (ret.supplierName != null) ...[
                  const SizedBox(height: 4),
                  Text(ret.supplierName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _DetailCol(
                      label: 'reports.tax_refunded'.tr(),
                      value: cs.formatCents(ret.taxCents),
                      valueColor: colorScheme.error,
                    )),
                    Expanded(child: _DetailCol(
                      label: 'reports.total'.tr(),
                      value: cs.formatCents(ret.totalCents),
                    )),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// SHARED WIDGETS
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
                  child: Text(label,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

class _DetailCol extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailCol({
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
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor)),
      ],
    );
  }
}
