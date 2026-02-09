import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../accounting/presentation/services/journal_pdf_service.dart';
import '../bloc/reports_bloc.dart';
import '../widgets/date_range_selector.dart';

class ProfitLossScreen extends StatelessWidget {
  const ProfitLossScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ReportsBloc>(),
      child: const _ProfitLossView(),
    );
  }
}

class _ProfitLossView extends StatelessWidget {
  const _ProfitLossView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.profit_loss'.tr()),
        actions: [
          BlocBuilder<ReportsBloc, RealtimeState<ReportsData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<ReportsData>) {
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
      body: BlocBuilder<ReportsBloc, RealtimeState<ReportsData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<ReportsData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<ReportsData>) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.error.toString()),
                ],
              ),
            );
          }

          if (state is RealtimeSuccess<ReportsData>) {
            final tb = state.data.trialBalance;

            final revenueItems = tb.getItemsByType('revenue');
            final expenseItems = tb.getItemsByType('expense');

            final totalRevenue = revenueItems.fold<int>(
                0, (sum, item) => sum + item.creditCents - item.debitCents);
            final totalExpenses = expenseItems.fold<int>(
                0, (sum, item) => sum + item.debitCents - item.creditCents);
            final netProfit = totalRevenue - totalExpenses;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Date range selector
                DateRangeSelector(
                  dateRange: state.data.dateRange,
                  onChanged: (range) => context
                      .read<ReportsBloc>()
                      .add(ReportsDateRangeChanged(range)),
                ),
                const SizedBox(height: 12),

                // Net Profit/Loss card
                Card(
                  color: netProfit >= 0
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          netProfit >= 0
                              ? 'reports.net_profit'.tr()
                              : 'reports.net_loss'.tr(),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          cs.formatCents(netProfit.abs()),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: netProfit >= 0
                                ? colorScheme.primary
                                : colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Revenue section
                _SectionTitle(
                  title: 'reports.revenue'.tr(),
                  total: cs.formatCents(totalRevenue),
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 8),
                ...revenueItems
                    .where((i) => i.creditCents > 0 || i.debitCents > 0)
                    .map((item) => _LineItem(
                          name: item.accountName,
                          code: item.accountCode,
                          amount: cs.formatCents(
                              item.creditCents - item.debitCents),
                        )),
                const Divider(height: 32),

                // Expenses section
                _SectionTitle(
                  title: 'reports.expenses'.tr(),
                  total: cs.formatCents(totalExpenses),
                  color: colorScheme.error,
                ),
                const SizedBox(height: 8),
                ...expenseItems
                    .where((i) => i.debitCents > 0 || i.creditCents > 0)
                    .map((item) => _LineItem(
                          name: item.accountName,
                          code: item.accountCode,
                          amount: cs.formatCents(
                              item.debitCents - item.creditCents),
                        )),
                const Divider(height: 32),

                // Summary
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _SummaryRow(
                          label: 'reports.total_revenue'.tr(),
                          value: cs.formatCents(totalRevenue),
                        ),
                        const SizedBox(height: 8),
                        _SummaryRow(
                          label: 'reports.total_expenses'.tr(),
                          value: '(${cs.formatCents(totalExpenses)})',
                        ),
                        const Divider(),
                        _SummaryRow(
                          label: netProfit >= 0
                              ? 'reports.net_profit'.tr()
                              : 'reports.net_loss'.tr(),
                          value: cs.formatCents(netProfit.abs()),
                          isBold: true,
                          color: netProfit >= 0
                              ? colorScheme.primary
                              : colorScheme.error,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _printReport(BuildContext context, ReportsData data) async {
    final tb = data.trialBalance;
    final revenueItems = tb.getItemsByType('revenue');
    final expenseItems = tb.getItemsByType('expense');
    final totalRevenue = revenueItems.fold<int>(
        0, (sum, item) => sum + item.creditCents - item.debitCents);
    final totalExpenses = expenseItems.fold<int>(
        0, (sum, item) => sum + item.debitCents - item.creditCents);

    await JournalPdfService.printProfitLoss(
      context: context,
      sections: [
        PnlSection(
          title: 'reports.revenue'.tr(),
          items: revenueItems
              .where((i) => i.creditCents > 0 || i.debitCents > 0)
              .map((i) => PnlLineItem(
                    code: i.accountCode,
                    name: i.accountName,
                    amountCents: i.creditCents - i.debitCents,
                  ))
              .toList(),
          totalCents: totalRevenue,
        ),
        PnlSection(
          title: 'reports.expenses'.tr(),
          items: expenseItems
              .where((i) => i.debitCents > 0 || i.creditCents > 0)
              .map((i) => PnlLineItem(
                    code: i.accountCode,
                    name: i.accountName,
                    amountCents: i.debitCents - i.creditCents,
                  ))
              .toList(),
          totalCents: totalExpenses,
        ),
      ],
      totalRevenue: totalRevenue,
      totalExpenses: totalExpenses,
      netProfit: totalRevenue - totalExpenses,
      asOfDate: tb.asOfDate,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_profit_loss',
    );
  }

  Future<void> _shareReport(BuildContext context, ReportsData data) async {
    final tb = data.trialBalance;
    final revenueItems = tb.getItemsByType('revenue');
    final expenseItems = tb.getItemsByType('expense');
    final totalRevenue = revenueItems.fold<int>(
        0, (sum, item) => sum + item.creditCents - item.debitCents);
    final totalExpenses = expenseItems.fold<int>(
        0, (sum, item) => sum + item.debitCents - item.creditCents);

    await JournalPdfService.shareProfitLoss(
      context: context,
      sections: [
        PnlSection(
          title: 'reports.revenue'.tr(),
          items: revenueItems
              .where((i) => i.creditCents > 0 || i.debitCents > 0)
              .map((i) => PnlLineItem(
                    code: i.accountCode,
                    name: i.accountName,
                    amountCents: i.creditCents - i.debitCents,
                  ))
              .toList(),
          totalCents: totalRevenue,
        ),
        PnlSection(
          title: 'reports.expenses'.tr(),
          items: expenseItems
              .where((i) => i.debitCents > 0 || i.creditCents > 0)
              .map((i) => PnlLineItem(
                    code: i.accountCode,
                    name: i.accountName,
                    amountCents: i.debitCents - i.creditCents,
                  ))
              .toList(),
          totalCents: totalExpenses,
        ),
      ],
      totalRevenue: totalRevenue,
      totalExpenses: totalExpenses,
      netProfit: totalRevenue - totalExpenses,
      asOfDate: tb.asOfDate,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_profit_loss',
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String total;
  final Color color;

  const _SectionTitle({
    required this.title,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold, color: color)),
        Text(total, style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _LineItem extends StatelessWidget {
  final String name;
  final String code;
  final String amount;

  const _LineItem({required this.name, required this.code, required this.amount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Text(code, style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace', color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(width: 12),
          Expanded(child: Text(name)),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? color;

  const _SummaryRow({
    required this.label, required this.value, this.isBold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold, color: color)
        : Theme.of(context).textTheme.bodyLarge;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}
