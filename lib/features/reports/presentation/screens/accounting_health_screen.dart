import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../bloc/reports_bloc.dart';

class AccountingHealthScreen extends StatelessWidget {
  const AccountingHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ReportsBloc>()
        ..add(const ReportsReconciliationRequested()),
      child: const _AccountingHealthView(),
    );
  }
}


class _AccountingHealthView extends StatelessWidget {
  const _AccountingHealthView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.reconciliation'.tr()),
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
            final data = state.data;
            final tb = data.trialBalance;
            final reconciliation = data.reconciliation;
            final healthy = data.isHealthy;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // NOTE: No DateRangeSelector here by design.
                // reconcileBalances() compares control accounts (1100 AR /
                // 2000 AP / 1200 Inventory) against subledger sums
                // (Σ customers.balance / Σ suppliers.balance / Σ stock×cost).
                // Both sides are lifetime-cumulative; scoping by date would
                // break the invariant and mislead the user. The trial-balance
                // check below loads as-of the bloc's default range, which is
                // the correct semantic for a health snapshot.

                // Overall health card
                Card(
                  color: healthy
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(
                          healthy
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                          size: 64,
                          color: healthy ? colorScheme.primary : colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          healthy
                              ? 'reports.all_checks_passed'.tr()
                              : 'reports.issues_detected'.tr(),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (reconciliation != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'reports.last_checked'.tr(args: [
                              _formatTimestamp(reconciliation.timestamp),
                            ]),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Trial Balance Check
                _CheckCard(
                  title: 'reports.trial_balance_check'.tr(),
                  passed: tb.isBalanced,
                  details: tb.isBalanced
                      ? 'reports.debits_equal_credits'.tr(args: [
                          cs.formatCents(tb.totalDebitCents),
                        ])
                      : 'reports.debits_not_equal_credits'.tr(args: [
                          cs.formatCents(tb.totalDebitCents),
                          cs.formatCents(tb.totalCreditCents),
                        ]),
                ),

                // Journal Entries Check
                if (reconciliation != null)
                  _CheckCard(
                    title: 'reports.journal_entries_check'.tr(),
                    passed: reconciliation.issues
                        .where((i) => i.contains('Unbalanced'))
                        .isEmpty,
                    details: reconciliation.issues
                            .where((i) => i.contains('Unbalanced'))
                            .isEmpty
                        ? 'reports.all_entries_balanced'.tr()
                        : reconciliation.issues
                            .where((i) => i.contains('Unbalanced'))
                            .join('\n'),
                  ),

                // Issues list
                if (reconciliation != null && reconciliation.issues.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'reports.issue_details'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...reconciliation.issues.map((issue) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: colorScheme.errorContainer,
                        child: ListTile(
                          leading: Icon(Icons.error, color: colorScheme.error),
                          title: Text(issue),
                        ),
                      )),
                ],
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  String _formatTimestamp(DateTime ts) {
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inSeconds < 60) return 'reports.just_now'.tr();
    if (diff.inMinutes < 60) {
      return 'reports.minutes_ago'.tr(args: ['${diff.inMinutes}']);
    }
    return DateFormat.yMMMd().add_jm().format(ts);
  }
}


class _CheckCard extends StatelessWidget {
  final String title;
  final bool passed;
  final String details;

  const _CheckCard({
    required this.title,
    required this.passed,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          passed ? Icons.check_circle : Icons.cancel,
          color: passed ? colorScheme.primary : colorScheme.error,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(details),
      ),
    );
  }
}
