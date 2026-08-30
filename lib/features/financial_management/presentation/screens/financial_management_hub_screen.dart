import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../accounting/presentation/bloc/accounts_bloc.dart';
import '../../../reports/presentation/bloc/reports_bloc.dart';

class FinancialManagementHubScreen extends StatelessWidget {
  const FinancialManagementHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) =>
              sl<ReportsBloc>()..add(const ReportsReconciliationRequested()),
        ),
        BlocProvider(create: (_) => sl<AccountsBloc>()),
      ],
      child: const _HubView(),
    );
  }
}

class _HubView extends StatelessWidget {
  const _HubView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('financial_management.title'.tr()),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ═══ FINANCIAL HEALTH BANNER ═══
          _FinancialHealthBanner(cs: cs),
          const SizedBox(height: 20),

          // ═══ CORE ACCOUNTING ═══
          _SectionHeader(
            icon: LucideIcons.landmark,
            title: 'financial_management.core_accounting'.tr(),
          ),
          const SizedBox(height: 8),
          _NavTile(
            icon: LucideIcons.bookOpen,
            title: 'financial_management.chart_of_accounts'.tr(),
            subtitle: 'financial_management.chart_of_accounts_desc'.tr(),
            color: colorScheme.primary,
            onTap: () =>
                context.push('/financial-management/chart-of-accounts'),
          ),
          _NavTile(
            icon: LucideIcons.fileEdit,
            title: 'financial_management.journal_entries'.tr(),
            subtitle: 'financial_management.journal_entries_desc'.tr(),
            color: colorScheme.secondary,
            onTap: () => context.push('/financial-management/journal-entries'),
          ),
          _NavTile(
            icon: LucideIcons.calendarCheck,
            title: 'financial_management.accounting_periods'.tr(),
            subtitle: 'financial_management.accounting_periods_desc'.tr(),
            color: colorScheme.tertiary,
            onTap: () => context.push('/financial-management/periods'),
          ),
          const SizedBox(height: 20),

          // ═══ OWNER EQUITY & LONG-TERM ASSETS ═══
          _SectionHeader(
            icon: LucideIcons.coins,
            title: 'financial_management.owner_assets_section'.tr(),
          ),
          const SizedBox(height: 8),
          _NavTile(
            icon: LucideIcons.banknote,
            title: 'financial_management.owner_finance'.tr(),
            subtitle: 'financial_management.owner_finance_desc'.tr(),
            color: Colors.amber.shade800,
            onTap: () => context.push('/financial-management/owner-finance'),
          ),
          _NavTile(
            icon: LucideIcons.building2,
            title: 'financial_management.fixed_assets'.tr(),
            subtitle: 'financial_management.fixed_assets_desc'.tr(),
            color: Colors.blueGrey,
            onTap: () => context.push('/financial-management/fixed-assets'),
          ),
          const SizedBox(height: 20),

          // ═══ FINANCIAL REPORTS ═══
          _SectionHeader(
            icon: LucideIcons.barChart3,
            title: 'financial_management.financial_reports'.tr(),
          ),
          const SizedBox(height: 8),
          _NavTile(
            icon: LucideIcons.scale,
            title: 'financial_management.trial_balance'.tr(),
            subtitle: 'financial_management.trial_balance_desc'.tr(),
            color: Colors.teal,
            onTap: () => context.push('/reports/trial-balance'),
          ),
          _NavTile(
            icon: LucideIcons.trendingUp,
            title: 'financial_management.profit_loss'.tr(),
            subtitle: 'financial_management.profit_loss_desc'.tr(),
            color: Colors.green,
            onTap: () => context.push('/reports/profit-loss'),
          ),
          _NavTile(
            icon: LucideIcons.building2,
            title: 'financial_management.balance_sheet'.tr(),
            subtitle: 'financial_management.balance_sheet_desc'.tr(),
            color: Colors.indigo,
            onTap: () => context.push('/reports/balance-sheet'),
          ),
          _NavTile(
            icon: LucideIcons.bookOpenCheck,
            title: 'financial_management.general_ledger'.tr(),
            subtitle: 'financial_management.general_ledger_desc'.tr(),
            color: Colors.deepPurple,
            onTap: () => context.push('/reports/general-ledger'),
          ),
          const SizedBox(height: 20),

          // ═══ SYSTEM HEALTH & TOOLS ═══
          _SectionHeader(
            icon: LucideIcons.shield,
            title: 'financial_management.system_tools'.tr(),
          ),
          const SizedBox(height: 8),
          _NavTile(
            icon: LucideIcons.heartPulse,
            title: 'financial_management.accounting_health'.tr(),
            subtitle: 'financial_management.accounting_health_desc'.tr(),
            color: Colors.red,
            onTap: () => context.push('/reports/health'),
          ),
          _NavTile(
            icon: LucideIcons.clipboardList,
            title: 'financial_management.audit_trail'.tr(),
            subtitle: 'financial_management.audit_trail_desc'.tr(),
            color: Colors.blueGrey,
            onTap: () => context.push('/audit'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _FinancialHealthBanner extends StatelessWidget {
  final CurrencyService cs;
  const _FinancialHealthBanner({required this.cs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocBuilder<ReportsBloc, RealtimeState<ReportsData>>(
      builder: (context, state) {
        if (state is RealtimeLoading<ReportsData>) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text('financial_management.loading_overview'.tr()),
                ],
              ),
            ),
          );
        }

        if (state is RealtimeSuccess<ReportsData>) {
          final data = state.data;
          final cumulativeTb = data.trialBalance;
          final periodTb = data.periodTrialBalance;
          final healthy = data.isHealthy;

          // Balance-sheet KPIs are cumulative; performance KPIs are period-only.
          final totalAssets = cumulativeTb.totalForType('asset');
          final totalLiabilities = cumulativeTb.totalForType('liability');
          final totalRevenue = periodTb.totalForType('revenue');
          final totalExpenses = periodTb.totalForType('expense');
          final netIncome = totalRevenue - totalExpenses;

          return Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        healthy
                            ? LucideIcons.shieldCheck
                            : LucideIcons.shieldAlert,
                        color: healthy ? Colors.green : colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'financial_management.financial_overview'.tr(),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: healthy
                              ? Colors.green.withValues(alpha: 0.15)
                              : colorScheme.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          healthy
                              ? 'financial_management.status_healthy'.tr()
                              : 'financial_management.status_issues'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: healthy ? Colors.green : colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // KPI Grid
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          label: 'financial_management.kpi_assets'.tr(),
                          value: cs.formatCents(totalAssets),
                          icon: LucideIcons.wallet,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _KpiCard(
                          label: 'financial_management.kpi_liabilities'.tr(),
                          value: cs.formatCents(totalLiabilities),
                          icon: LucideIcons.creditCard,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          label: 'financial_management.kpi_revenue'.tr(),
                          value: cs.formatCents(totalRevenue),
                          icon: LucideIcons.trendingUp,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _KpiCard(
                          label: 'financial_management.kpi_net_income'.tr(),
                          value: cs.formatCents(netIncome),
                          icon: netIncome >= 0
                              ? LucideIcons.arrowUpRight
                              : LucideIcons.arrowDownRight,
                          color: netIncome >= 0
                              ? Colors.green
                              : colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
