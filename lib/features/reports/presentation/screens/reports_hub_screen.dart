import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../bloc/reports_bloc.dart';

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ReportsBloc>()
        ..add(const ReportsReconciliationRequested()),
      child: const _ReportsHubView(),
    );
  }
}

class _ReportsHubView extends StatelessWidget {
  const _ReportsHubView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'settings.title'.tr(),
          ),
        ],
      ),
      body: BlocBuilder<ReportsBloc, RealtimeState<ReportsData>>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Health check banner
              _buildHealthBanner(context, state, theme, colorScheme),
              const SizedBox(height: 16),

              // Financial Reports Section
              _SectionHeader(title: 'reports.financial_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: Icons.balance,
                title: 'reports.trial_balance'.tr(),
                subtitle: 'reports.trial_balance_desc'.tr(),
                onTap: () => context.push('/reports/trial-balance'),
              ),
              _ReportTile(
                icon: Icons.trending_up,
                title: 'reports.profit_loss'.tr(),
                subtitle: 'reports.profit_loss_desc'.tr(),
                onTap: () => context.push('/reports/profit-loss'),
              ),
              _ReportTile(
                icon: Icons.account_balance,
                title: 'reports.balance_sheet'.tr(),
                subtitle: 'reports.balance_sheet_desc'.tr(),
                onTap: () => context.push('/reports/balance-sheet'),
              ),
              _ReportTile(
                icon: Icons.menu_book,
                title: 'reports.general_ledger'.tr(),
                subtitle: 'reports.general_ledger_desc'.tr(),
                onTap: () => context.push('/reports/general-ledger'),
              ),
              const SizedBox(height: 24),

              // Inventory Reports Section
              _SectionHeader(title: 'reports.inventory_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.warehouse,
                title: 'reports.inventory_reports'.tr(),
                subtitle: 'reports.inventory_reports_desc'.tr(),
                onTap: () => context.push('/reports/inventory'),
              ),
              const SizedBox(height: 24),

              // Customer Reports Section
              _SectionHeader(title: 'reports.customer_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.users,
                title: 'reports.customer_reports'.tr(),
                subtitle: 'reports.customer_reports_desc'.tr(),
                onTap: () => context.push('/reports/customers'),
              ),
              _ReportTile(
                icon: LucideIcons.undo2,
                title: 'reports.customer_returns'.tr(),
                subtitle: 'reports.customer_returns_desc'.tr(),
                onTap: () => context.push('/reports/customer-returns'),
              ),
              _ReportTile(
                icon: LucideIcons.trophy,
                title: 'reports.top_customers'.tr(),
                subtitle: 'reports.top_customers_desc'.tr(),
                onTap: () => context.push('/reports/top-customers'),
              ),
              _ReportTile(
                icon: LucideIcons.banknote,
                title: 'reports.customer_payments'.tr(),
                subtitle: 'reports.customer_payments_desc'.tr(),
                onTap: () => context.push('/reports/customer-payments'),
              ),
              _ReportTile(
                icon: LucideIcons.shoppingCart,
                title: 'reports.customer_sales'.tr(),
                subtitle: 'reports.customer_sales_desc'.tr(),
                onTap: () => context.push('/reports/customer-sales'),
              ),
              _ReportTile(
                icon: LucideIcons.clock,
                title: 'reports.customer_aging_report'.tr(),
                subtitle: 'reports.customer_aging_report_desc'.tr(),
                onTap: () => context.push('/reports/customer-aging'),
              ),
              const SizedBox(height: 24),

              // Diagnostics Section
              _SectionHeader(title: 'reports.diagnostics'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: Icons.health_and_safety,
                title: 'reports.reconciliation'.tr(),
                subtitle: 'reports.reconciliation_desc'.tr(),
                onTap: () => context.push('/reports/health'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHealthBanner(
    BuildContext context,
    RealtimeState<ReportsData> state,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (state is RealtimeLoading<ReportsData>) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('reports.checking_health'.tr()),
            ],
          ),
        ),
      );
    }

    if (state is RealtimeSuccess<ReportsData>) {
      final data = state.data;
      final healthy = data.isHealthy;
      return Card(
        color: healthy
            ? colorScheme.primaryContainer
            : colorScheme.errorContainer,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/reports/health'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  healthy ? Icons.check_circle : Icons.warning,
                  color: healthy ? colorScheme.primary : colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        healthy
                            ? 'reports.system_healthy'.tr()
                            : 'reports.issues_found'.tr(
                                args: ['${data.issueCount}']),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'reports.tap_for_details'.tr(),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
