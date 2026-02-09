import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../accounting/presentation/services/journal_pdf_service.dart';
import '../../../accounting/domain/models/trial_balance.dart';
import '../bloc/reports_bloc.dart';
import '../widgets/date_range_selector.dart';

class BalanceSheetScreen extends StatelessWidget {
  const BalanceSheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ReportsBloc>(),
      child: const _BalanceSheetView(),
    );
  }
}

class _BalanceSheetView extends StatelessWidget {
  const _BalanceSheetView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.balance_sheet'.tr()),
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

            final assetItems = tb.getItemsByType('asset');
            final liabilityItems = tb.getItemsByType('liability');
            final equityItems = tb.getItemsByType('equity');

            final totalAssets = assetItems.fold<int>(
                0, (sum, item) => sum + item.debitCents - item.creditCents);
            final totalLiabilities = liabilityItems.fold<int>(
                0, (sum, item) => sum + item.creditCents - item.debitCents);
            final totalEquity = equityItems.fold<int>(
                0, (sum, item) => sum + item.creditCents - item.debitCents);

            final revenueItems = tb.getItemsByType('revenue');
            final expenseItems = tb.getItemsByType('expense');
            final totalRevenue = revenueItems.fold<int>(
                0, (sum, item) => sum + item.creditCents - item.debitCents);
            final totalExpenses = expenseItems.fold<int>(
                0, (sum, item) => sum + item.debitCents - item.creditCents);
            final retainedEarnings = totalRevenue - totalExpenses;

            final totalLiabilitiesAndEquity =
                totalLiabilities + totalEquity + retainedEarnings;
            final isBalanced = totalAssets == totalLiabilitiesAndEquity;

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

                Card(
                  color: isBalanced
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          isBalanced ? Icons.check_circle : Icons.warning,
                          color: isBalanced ? colorScheme.primary : colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isBalanced
                              ? 'reports.balance_sheet_balanced'.tr()
                              : 'reports.balance_sheet_unbalanced'.tr(),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                _BalanceSection(
                  title: 'reports.assets'.tr(),
                  items: assetItems, total: totalAssets,
                  cs: cs, color: colorScheme.primary,
                ),
                const SizedBox(height: 16),

                _BalanceSection(
                  title: 'reports.liabilities'.tr(),
                  items: liabilityItems, total: totalLiabilities,
                  cs: cs, color: colorScheme.error,
                ),
                const SizedBox(height: 16),

                _BalanceSection(
                  title: 'reports.equity'.tr(),
                  items: equityItems, total: totalEquity,
                  cs: cs, color: colorScheme.tertiary,
                  extraItems: retainedEarnings != 0
                      ? [_ExtraLineItem(
                          name: 'reports.retained_earnings'.tr(),
                          amount: cs.formatCents(retainedEarnings))]
                      : null,
                ),
                const SizedBox(height: 16),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _SummaryRow(
                          label: 'reports.total_assets'.tr(),
                          value: cs.formatCents(totalAssets),
                        ),
                        const Divider(),
                        _SummaryRow(
                          label: 'reports.total_liabilities'.tr(),
                          value: cs.formatCents(totalLiabilities),
                        ),
                        const SizedBox(height: 4),
                        _SummaryRow(
                          label: 'reports.total_equity'.tr(),
                          value: cs.formatCents(totalEquity + retainedEarnings),
                        ),
                        const Divider(),
                        _SummaryRow(
                          label: 'reports.total_liabilities_equity'.tr(),
                          value: cs.formatCents(totalLiabilitiesAndEquity),
                          isBold: true,
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
    final cs = sl<CurrencyService>();
    final bsSections = _buildBsSections(tb, cs);
    final totalAssets = tb.getItemsByType('asset').fold<int>(
        0, (sum, item) => sum + item.debitCents - item.creditCents);
    final totalLE = _totalLiabilitiesAndEquity(tb);

    await JournalPdfService.printBalanceSheet(
      context: context,
      sections: bsSections,
      totalAssets: totalAssets,
      totalLiabilitiesAndEquity: totalLE,
      isBalanced: totalAssets == totalLE,
      asOfDate: tb.asOfDate,
    );
    sl<AuditLogService>().log(
      entityType: 'report', entityId: 0, action: 'print_balance_sheet',
    );
  }

  Future<void> _shareReport(BuildContext context, ReportsData data) async {
    final tb = data.trialBalance;
    final cs = sl<CurrencyService>();
    final bsSections = _buildBsSections(tb, cs);
    final totalAssets = tb.getItemsByType('asset').fold<int>(
        0, (sum, item) => sum + item.debitCents - item.creditCents);
    final totalLE = _totalLiabilitiesAndEquity(tb);

    await JournalPdfService.shareBalanceSheet(
      context: context,
      sections: bsSections,
      totalAssets: totalAssets,
      totalLiabilitiesAndEquity: totalLE,
      isBalanced: totalAssets == totalLE,
      asOfDate: tb.asOfDate,
    );
    sl<AuditLogService>().log(
      entityType: 'report', entityId: 0, action: 'share_balance_sheet',
    );
  }

  int _totalLiabilitiesAndEquity(TrialBalance tb) {
    final totalLiabilities = tb.getItemsByType('liability').fold<int>(
        0, (sum, item) => sum + item.creditCents - item.debitCents);
    final totalEquity = tb.getItemsByType('equity').fold<int>(
        0, (sum, item) => sum + item.creditCents - item.debitCents);
    final totalRevenue = tb.getItemsByType('revenue').fold<int>(
        0, (sum, item) => sum + item.creditCents - item.debitCents);
    final totalExpenses = tb.getItemsByType('expense').fold<int>(
        0, (sum, item) => sum + item.debitCents - item.creditCents);
    return totalLiabilities + totalEquity + (totalRevenue - totalExpenses);
  }

  List<BalanceSheetSection> _buildBsSections(TrialBalance tb, CurrencyService cs) {
    List<BalanceSheetLineItem> toLineItems(List<TrialBalanceItem> items) {
      return items
          .where((i) => i.debitCents > 0 || i.creditCents > 0)
          .map((i) => BalanceSheetLineItem(
                code: i.accountCode,
                name: i.accountName,
                amountCents: (i.debitCents - i.creditCents).abs(),
              ))
          .toList();
    }

    final assetItems = tb.getItemsByType('asset');
    final liabilityItems = tb.getItemsByType('liability');
    final equityItems = tb.getItemsByType('equity');

    return [
      BalanceSheetSection(
        title: 'reports.assets'.tr(),
        items: toLineItems(assetItems),
        totalCents: assetItems.fold<int>(
            0, (sum, item) => sum + item.debitCents - item.creditCents),
      ),
      BalanceSheetSection(
        title: 'reports.liabilities'.tr(),
        items: toLineItems(liabilityItems),
        totalCents: liabilityItems.fold<int>(
            0, (sum, item) => sum + item.creditCents - item.debitCents),
      ),
      BalanceSheetSection(
        title: 'reports.equity'.tr(),
        items: toLineItems(equityItems),
        totalCents: equityItems.fold<int>(
            0, (sum, item) => sum + item.creditCents - item.debitCents),
      ),
    ];
  }
}

class _BalanceSection extends StatelessWidget {
  final String title;
  final List<TrialBalanceItem> items;
  final int total;
  final CurrencyService cs;
  final Color color;
  final List<_ExtraLineItem>? extraItems;

  const _BalanceSection({
    required this.title,
    required this.items,
    required this.total,
    required this.cs,
    required this.color,
    this.extraItems,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nonZero =
        items.where((i) => i.debitCents > 0 || i.creditCents > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              cs.formatCents(total),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...nonZero.map((item) {
          final net = item.debitCents - item.creditCents;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Row(
              children: [
                Text(
                  item.accountCode,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(item.accountName)),
                Text(
                  cs.formatCents(net.abs()),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }),
        if (extraItems != null) ...extraItems!,
      ],
    );
  }
}

class _ExtraLineItem extends StatelessWidget {
  final String name;
  final String amount;

  const _ExtraLineItem({required this.name, required this.amount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          const SizedBox(width: 60),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
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

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            )
        : Theme.of(context).textTheme.bodyLarge;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
