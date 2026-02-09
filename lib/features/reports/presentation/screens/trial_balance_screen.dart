import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../accounting/domain/repositories/journal_repository.dart';
import '../../../accounting/presentation/services/journal_pdf_service.dart';
import '../../../accounting/domain/models/trial_balance.dart';
import '../bloc/reports_bloc.dart';
import '../widgets/date_range_selector.dart';

class TrialBalanceScreen extends StatelessWidget {
  const TrialBalanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ReportsBloc>(),
      child: const _TrialBalanceView(),
    );
  }
}

class _TrialBalanceView extends StatelessWidget {
  const _TrialBalanceView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.trial_balance'.tr()),
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
                  Text(state.error.toString(), style: theme.textTheme.bodyLarge),
                ],
              ),
            );
          }

          if (state is RealtimeSuccess<ReportsData>) {
            final tb = state.data.trialBalance;

            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<ReportsBloc>()
                        .add(ReportsDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),

                // Balance status banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: tb.isBalanced
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                  child: Row(
                    children: [
                      Icon(
                        tb.isBalanced ? Icons.check_circle : Icons.warning,
                        color: tb.isBalanced
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tb.isBalanced
                              ? 'reports.trial_balance_balanced'.tr()
                              : 'reports.trial_balance_unbalanced'.tr(
                                  args: [cs.formatCents(tb.differenceCents.abs())]),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Account list
                Expanded(child: _buildAccountTable(context, tb, cs)),

                // Totals footer
                _buildTotalsFooter(context, tb, cs),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _printReport(BuildContext context, ReportsData data) async {
    final repo = sl<JournalRepository>();
    final rawAccounts = await repo.watchAllAccounts().first;
    if (!context.mounted) return;
    await JournalPdfService.printTrialBalance(
      context: context,
      accounts: rawAccounts,
      asOfDate: data.trialBalance.asOfDate,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_trial_balance',
    );
  }

  Future<void> _shareReport(BuildContext context, ReportsData data) async {
    final repo = sl<JournalRepository>();
    final rawAccounts = await repo.watchAllAccounts().first;
    if (!context.mounted) return;
    await JournalPdfService.shareTrialBalance(
      context: context,
      accounts: rawAccounts,
      asOfDate: data.trialBalance.asOfDate,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_trial_balance',
    );
  }

  Widget _buildAccountTable(
    BuildContext context,
    TrialBalance tb,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final items = tb.nonZeroItems;

    if (items.isEmpty) {
      return Center(child: Text('reports.no_accounts_with_balance'.tr()));
    }

    return SingleChildScrollView(
      child: DataTable(
        columnSpacing: 16,
        horizontalMargin: 16,
        columns: [
          DataColumn(label: Text('reports.code'.tr())),
          DataColumn(label: Text('reports.account'.tr())),
          DataColumn(label: Text('reports.debit'.tr()), numeric: true),
          DataColumn(label: Text('reports.credit'.tr()), numeric: true),
        ],
        rows: items.map((item) {
          return DataRow(cells: [
            DataCell(Text(
              item.accountCode,
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            )),
            DataCell(Text(item.accountName)),
            DataCell(Text(
              item.debitCents > 0 ? cs.formatCents(item.debitCents) : '-',
              style: TextStyle(
                fontWeight: item.debitCents > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            )),
            DataCell(Text(
              item.creditCents > 0 ? cs.formatCents(item.creditCents) : '-',
              style: TextStyle(
                fontWeight: item.creditCents > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildTotalsFooter(
    BuildContext context,
    TrialBalance tb,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('reports.total_debits'.tr(), style: theme.textTheme.bodySmall),
                Text(
                  cs.formatCents(tb.totalDebitCents),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('reports.total_credits'.tr(), style: theme.textTheme.bodySmall),
                Text(
                  cs.formatCents(tb.totalCreditCents),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
