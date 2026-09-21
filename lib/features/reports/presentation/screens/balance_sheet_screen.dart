import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../accounting/domain/services/balance_sheet_diagnostic_service.dart';
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

  /// Compute all balance sheet figures from trial balance
  static _BalanceSheetFigures _computeFigures(TrialBalance tb) {
    final assetItems = tb.getItemsByType('asset');
    final liabilityItems = tb.getItemsByType('liability');
    final equityItems = tb.getItemsByType('equity');

    // Phase 7 — natural-balance signing via TrialBalance SoT.
    final totalAssets = tb.totalForType('asset');
    final totalLiabilities = tb.totalForType('liability');
    final ownerCapital = tb.totalForType('equity');
    final totalRevenue = tb.totalForType('revenue');
    final totalExpenses = tb.totalForType('expense');

    // Net Income = Revenue - Expenses
    final netIncome = totalRevenue - totalExpenses;

    // Total Equity = Owner's Capital + Net Income
    final totalEquity = ownerCapital + netIncome;

    // Liabilities + Equity
    final totalLiabilitiesAndEquity = totalLiabilities + totalEquity;

    // Balance check: Assets must equal Liabilities + Equity
    final isBalanced = totalAssets == totalLiabilitiesAndEquity;
    final difference = totalAssets - totalLiabilitiesAndEquity;

    return _BalanceSheetFigures(
      assetItems: assetItems,
      liabilityItems: liabilityItems,
      equityItems: equityItems,
      totalAssets: totalAssets,
      totalLiabilities: totalLiabilities,
      ownerCapital: ownerCapital,
      netIncome: netIncome,
      totalEquity: totalEquity,
      totalLiabilitiesAndEquity: totalLiabilitiesAndEquity,
      isBalanced: isBalanced,
      difference: difference,
    );
  }

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
            final fig = _computeFigures(state.data.trialBalance);

            // Run diagnostics
            const diagService = BalanceSheetDiagnosticService();
            final diagResult = diagService.analyze(
              totalAssets: fig.totalAssets,
              totalLiabilities: fig.totalLiabilities,
              ownerCapital: fig.ownerCapital,
              netIncome: fig.netIncome,
              totalEquity: fig.totalEquity,
              differenceCents: fig.difference,
              hasOpenPeriod: true, // simplified — always true for now
            );

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Date range selector
                DateRangeSelector(
                  dateRange: state.data.dateRange,
                  onChanged: (range) => context.read<ReportsBloc>().add(
                    ReportsDateRangeChanged(range),
                  ),
                ),
                const SizedBox(height: 12),

                // Balance status banner
                Card(
                  color: fig.isBalanced
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          fig.isBalanced ? Icons.check_circle : Icons.warning,
                          color: fig.isBalanced
                              ? colorScheme.primary
                              : colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fig.isBalanced
                                    ? 'reports.balance_sheet_balanced'.tr()
                                    : 'reports.balance_sheet_unbalanced'.tr(),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (!fig.isBalanced) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'reports.balance_sheet_difference'.tr(
                                    args: [
                                      cs.formatCents(fig.difference.abs()),
                                    ],
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.error,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ═══ DIAGNOSTIC PANEL (when unbalanced) ═══
                if (!fig.isBalanced && diagResult.diagnostics.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DiagnosticPanel(
                    diagnostics: diagResult.diagnostics,
                    differenceCents: fig.difference,
                    cs: cs,
                  ),
                ],
                const SizedBox(height: 16),

                // ═══ ASSETS ═══
                _BalanceSection(
                  title: 'reports.assets'.tr(),
                  subtitle: 'financial_management.type_asset_desc'.tr(),
                  items: fig.assetItems,
                  total: fig.totalAssets,
                  cs: cs,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),

                // ═══ LIABILITIES ═══
                _BalanceSection(
                  title: 'reports.liabilities'.tr(),
                  subtitle: 'financial_management.type_liability_desc'.tr(),
                  items: fig.liabilityItems,
                  total: fig.totalLiabilities,
                  cs: cs,
                  color: colorScheme.error,
                ),
                const SizedBox(height: 16),

                // ═══ EQUITY ═══
                _EquitySection(
                  equityItems: fig.equityItems,
                  ownerCapital: fig.ownerCapital,
                  netIncome: fig.netIncome,
                  totalEquity: fig.totalEquity,
                  cs: cs,
                  color: colorScheme.tertiary,
                ),
                const SizedBox(height: 16),

                // ═══ SUMMARY ═══
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _SummaryRow(
                          label: 'reports.total_assets'.tr(),
                          value: cs.formatCents(fig.totalAssets),
                          isBold: true,
                        ),
                        const Divider(height: 16),
                        _SummaryRow(
                          label: 'reports.total_liabilities'.tr(),
                          value: cs.formatCents(fig.totalLiabilities),
                        ),
                        const SizedBox(height: 4),
                        _SummaryRow(
                          label: 'reports.total_equity'.tr(),
                          value: cs.formatCents(fig.totalEquity),
                        ),
                        const Divider(height: 16),
                        _SummaryRow(
                          label: 'reports.total_liabilities_equity'.tr(),
                          value: cs.formatCents(fig.totalLiabilitiesAndEquity),
                          isBold: true,
                        ),
                        if (!fig.isBalanced) ...[
                          const Divider(height: 16),
                          _SummaryRow(
                            label: 'reports.balance_sheet_difference_label'
                                .tr(),
                            value: cs.formatCents(fig.difference),
                            isBold: true,
                            isError: true,
                          ),
                        ],
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
    final fig = _computeFigures(data.trialBalance);
    final cs = sl<CurrencyService>();
    final bsSections = _buildBsSections(data.trialBalance, cs, fig);
    final hints = _buildDiagnosticHints(fig);

    await JournalPdfService.printBalanceSheet(
      context: context,
      sections: bsSections,
      totalAssets: fig.totalAssets,
      totalLiabilitiesAndEquity: fig.totalLiabilitiesAndEquity,
      isBalanced: fig.isBalanced,
      asOfDate: data.trialBalance.asOfDate,
      diagnosticHints: hints,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_balance_sheet',
    );
  }

  Future<void> _shareReport(BuildContext context, ReportsData data) async {
    final fig = _computeFigures(data.trialBalance);
    final cs = sl<CurrencyService>();
    final bsSections = _buildBsSections(data.trialBalance, cs, fig);
    final hints = _buildDiagnosticHints(fig);

    await JournalPdfService.shareBalanceSheet(
      context: context,
      sections: bsSections,
      totalAssets: fig.totalAssets,
      totalLiabilitiesAndEquity: fig.totalLiabilitiesAndEquity,
      isBalanced: fig.isBalanced,
      asOfDate: data.trialBalance.asOfDate,
      diagnosticHints: hints,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_balance_sheet',
    );
  }

  List<String> _buildDiagnosticHints(_BalanceSheetFigures fig) {
    if (fig.isBalanced) return [];
    const diagService = BalanceSheetDiagnosticService();
    final result = diagService.analyze(
      totalAssets: fig.totalAssets,
      totalLiabilities: fig.totalLiabilities,
      ownerCapital: fig.ownerCapital,
      netIncome: fig.netIncome,
      totalEquity: fig.totalEquity,
      differenceCents: fig.difference,
      hasOpenPeriod: true,
    );
    return result.diagnostics
        .map((d) => '${d.hintTitleKey.tr()}: ${d.hintDescriptionKey.tr()}')
        .toList();
  }

  List<BalanceSheetSection> _buildBsSections(
    TrialBalance tb,
    CurrencyService cs,
    _BalanceSheetFigures fig,
  ) {
    // Phase 8 — row-level natural-balance signing routes through the
    // [TrialBalanceItem.naturalBalanceCents] SoT helper (Phase 7).
    List<BalanceSheetLineItem> toAssetLineItems(List<TrialBalanceItem> items) {
      return items
          .where((i) => i.debitCents > 0 || i.creditCents > 0)
          .map(
            (i) => BalanceSheetLineItem(
              code: i.accountCode,
              name: i.accountName,
              amountCents: i.naturalBalanceCents,
            ),
          )
          .toList();
    }

    List<BalanceSheetLineItem> toCreditLineItems(List<TrialBalanceItem> items) {
      return items
          .where((i) => i.debitCents > 0 || i.creditCents > 0)
          .map(
            (i) => BalanceSheetLineItem(
              code: i.accountCode,
              name: i.accountName,
              amountCents: i.naturalBalanceCents,
            ),
          )
          .toList();
    }

    // Build equity items including net income
    final equityLineItems = toCreditLineItems(fig.equityItems);
    if (fig.netIncome != 0) {
      equityLineItems.add(
        BalanceSheetLineItem(
          code: '',
          name: 'reports.net_income'.tr(),
          amountCents: fig.netIncome,
        ),
      );
    }

    return [
      BalanceSheetSection(
        title: 'reports.assets'.tr(),
        items: toAssetLineItems(fig.assetItems),
        totalCents: fig.totalAssets,
      ),
      BalanceSheetSection(
        title: 'reports.liabilities'.tr(),
        items: toCreditLineItems(fig.liabilityItems),
        totalCents: fig.totalLiabilities,
      ),
      BalanceSheetSection(
        title: 'reports.equity'.tr(),
        items: equityLineItems,
        totalCents: fig.totalEquity,
      ),
    ];
  }
}

/// Holds all computed balance sheet figures
class _BalanceSheetFigures {
  final List<TrialBalanceItem> assetItems;
  final List<TrialBalanceItem> liabilityItems;
  final List<TrialBalanceItem> equityItems;
  final int totalAssets;
  final int totalLiabilities;
  final int ownerCapital;
  final int netIncome;
  final int totalEquity;
  final int totalLiabilitiesAndEquity;
  final bool isBalanced;
  final int difference;

  const _BalanceSheetFigures({
    required this.assetItems,
    required this.liabilityItems,
    required this.equityItems,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.ownerCapital,
    required this.netIncome,
    required this.totalEquity,
    required this.totalLiabilitiesAndEquity,
    required this.isBalanced,
    required this.difference,
  });
}

/// Diagnostic panel showing intelligent hints about balance sheet imbalance
class _DiagnosticPanel extends StatelessWidget {
  final List<BalanceSheetDiagnostic> diagnostics;
  final int differenceCents;
  final CurrencyService cs;

  const _DiagnosticPanel({
    required this.diagnostics,
    required this.differenceCents,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.lightbulb,
                  size: 18,
                  color: colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'reports.diag_panel_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.tertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...diagnostics.map((diag) => _DiagnosticTile(diagnostic: diag)),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticTile extends StatelessWidget {
  final BalanceSheetDiagnostic diagnostic;

  const _DiagnosticTile({required this.diagnostic});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color iconColor;
    final IconData iconData;
    switch (diagnostic.severity) {
      case DiagnosticSeverity.error:
        iconColor = colorScheme.error;
        iconData = LucideIcons.alertCircle;
        break;
      case DiagnosticSeverity.warning:
        iconColor = Colors.orange;
        iconData = LucideIcons.alertTriangle;
        break;
      case DiagnosticSeverity.info:
        iconColor = colorScheme.primary;
        iconData = LucideIcons.info;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diagnostic.hintTitleKey.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  diagnostic.hintDescriptionKey.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      LucideIcons.wrench,
                      size: 12,
                      color: colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        diagnostic.suggestedActionKey.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.tertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<TrialBalanceItem> items;
  final int total;
  final CurrencyService cs;
  final Color color;

  const _BalanceSection({
    required this.title,
    this.subtitle,
    required this.items,
    required this.total,
    required this.cs,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nonZero = items
        .where((i) => i.debitCents > 0 || i.creditCents > 0)
        .toList();

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
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        ...nonZero.map((item) {
          // Phase 8 — natural-balance routing via the SoT helper.
          final amount = item.naturalBalanceCents;
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
                  cs.formatCents(amount),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: amount < 0
                        ? theme.colorScheme.error
                        : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Equity section with Owner's Capital + Net Income
class _EquitySection extends StatelessWidget {
  final List<TrialBalanceItem> equityItems;
  final int ownerCapital;
  final int netIncome;
  final int totalEquity;
  final CurrencyService cs;
  final Color color;

  const _EquitySection({
    required this.equityItems,
    required this.ownerCapital,
    required this.netIncome,
    required this.totalEquity,
    required this.cs,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nonZero = equityItems
        .where((i) => i.debitCents > 0 || i.creditCents > 0)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'reports.equity'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              cs.formatCents(totalEquity),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'financial_management.type_equity_desc'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        // Owner's Capital accounts
        ...nonZero.map((item) {
          // Phase 8 — equity is credit-natural; route via the SoT helper.
          final amount = item.naturalBalanceCents;
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
                  cs.formatCents(amount),
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: amount < 0
                        ? theme.colorScheme.error
                        : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          );
        }),
        // Net Income line
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            children: [
              const SizedBox(width: 60),
              Expanded(
                child: Text(
                  'reports.net_income'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                cs.formatCents(netIncome),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: netIncome >= 0 ? Colors.teal : theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final bool isError;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = isBold
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyLarge;

    final style = isError
        ? baseStyle?.copyWith(color: Theme.of(context).colorScheme.error)
        : baseStyle;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
