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

              // Sales Reports Section
              _SectionHeader(title: 'reports.sales_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.shoppingCart,
                title: 'reports.sales_reports'.tr(),
                subtitle: 'reports.sales_reports_desc'.tr(),
                onTap: () => context.push('/reports/sales'),
              ),
              const SizedBox(height: 24),

              // Purchase Reports Section
              _SectionHeader(title: 'reports.purchase_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.shoppingBag,
                title: 'reports.purchase_reports'.tr(),
                subtitle: 'reports.purchase_reports_desc'.tr(),
                onTap: () => context.push('/reports/purchases'),
              ),
              const SizedBox(height: 24),

              // Discount Reports Section
              _SectionHeader(title: 'reports.discount_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.tag,
                title: 'reports.discount_reports'.tr(),
                subtitle: 'reports.discount_reports_desc'.tr(),
                onTap: () => context.push('/reports/discounts'),
              ),
              const SizedBox(height: 24),

              // Profit Reports Section
              _SectionHeader(title: 'reports.profit_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.trendingUp,
                title: 'reports.profit_reports'.tr(),
                subtitle: 'reports.profit_reports_desc'.tr(),
                onTap: () => context.push('/reports/profits'),
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
              _ReportTile(
                icon: LucideIcons.gitBranch,
                title: 'reports.product_movement_detail'.tr(),
                subtitle: 'reports.product_movement_detail_desc'.tr(),
                onTap: () => context.push('/reports/product-movement-detail'),
              ),
              _ReportTile(
                icon: LucideIcons.layers,
                title: 'reports.variant_movement_report'.tr(),
                subtitle: 'reports.variant_movement_report_desc'.tr(),
                onTap: () => context.push('/reports/product-variant-movement'),
              ),
              _ReportTile(
                icon: LucideIcons.folderOpen,
                title: 'reports.category_movement_report'.tr(),
                subtitle: 'reports.category_movement_report_desc'.tr(),
                onTap: () => context.push('/reports/category-movement'),
              ),
              _ReportTile(
                icon: LucideIcons.calendarClock,
                title: 'reports.expiry_report_title'.tr(),
                subtitle: 'reports.expiry_report_subtitle'.tr(),
                onTap: () => context.push('/reports/expiry'),
              ),
              _ReportTile(
                icon: LucideIcons.package,
                title: 'batch_management.title'.tr(),
                subtitle: 'batch_management.subtitle'.tr(),
                onTap: () => context.push('/reports/batches'),
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
              _ReportTile(
                icon: LucideIcons.fileText,
                title: 'reports.customer_statement_report'.tr(),
                subtitle: 'reports.customer_statement_report_desc'.tr(),
                onTap: () => context.push('/reports/customer-statement'),
              ),
              _ReportTile(
                icon: LucideIcons.barChart3,
                title: 'reports.customer_analysis'.tr(),
                subtitle: 'reports.customer_analysis_desc'.tr(),
                onTap: () => context.push('/reports/customer-analysis'),
              ),
              _ReportTile(
                icon: LucideIcons.bookOpen,
                title: 'reports.customer_ledger_report'.tr(),
                subtitle: 'reports.customer_ledger_report_desc'.tr(),
                onTap: () => context.push('/reports/customer-ledger'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.receipt,
                title: 'reports.customer_invoices_report'.tr(),
                subtitle: 'reports.customer_invoices_report_desc'.tr(),
                onTap: () => context.push('/reports/customer-invoices'),
              ),
              const SizedBox(height: 24),

              // Supplier Reports Section
              _SectionHeader(title: 'reports.supplier_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.truck,
                title: 'reports.supplier_balance'.tr(),
                subtitle: 'reports.supplier_balance_desc'.tr(),
                onTap: () => context.push('/reports/supplier-balance'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.arrowUpRight,
                title: 'reports.supplier_debit_balance'.tr(),
                subtitle: 'reports.supplier_debit_balance_desc'.tr(),
                onTap: () => context.push('/reports/supplier-debit-balance'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.arrowDownLeft,
                title: 'reports.supplier_credit_balance'.tr(),
                subtitle: 'reports.supplier_credit_balance_desc'.tr(),
                onTap: () => context.push('/reports/supplier-credit-balance'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.barChart3,
                title: 'reports.supplier_analysis'.tr(),
                subtitle: 'reports.supplier_analysis_desc'.tr(),
                onTap: () => context.push('/reports/supplier-analysis'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.clock,
                title: 'reports.supplier_aging_report'.tr(),
                subtitle: 'reports.supplier_aging_report_desc'.tr(),
                onTap: () => context.push('/reports/supplier-aging'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.fileText,
                title: 'reports.supplier_statement_report'.tr(),
                subtitle: 'reports.supplier_statement_report_desc'.tr(),
                onTap: () => context.push('/reports/supplier-statement'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.bookOpen,
                title: 'reports.supplier_ledger_report'.tr(),
                subtitle: 'reports.supplier_ledger_report_desc'.tr(),
                onTap: () => context.push('/reports/supplier-ledger'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.receipt,
                title: 'reports.supplier_invoices_report'.tr(),
                subtitle: 'reports.supplier_invoices_report_desc'.tr(),
                onTap: () => context.push('/reports/supplier-invoices'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.undo2,
                title: 'reports.supplier_returns_report'.tr(),
                subtitle: 'reports.supplier_returns_report_desc'.tr(),
                onTap: () => context.push('/reports/supplier-returns'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.warehouse,
                title: 'reports.supplier_stocktake'.tr(),
                subtitle: 'reports.supplier_stocktake_desc'.tr(),
                onTap: () => context.push('/reports/supplier-stocktake'),
              ),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.searchCode,
                title: 'reports.supplier_balance_drilldown'.tr(),
                subtitle: 'reports.supplier_balance_drilldown_desc'.tr(),
                onTap: () => context.push('/reports/supplier-balance-drilldown'),
              ),
              const SizedBox(height: 24),

              // Tax Reports Section
              _SectionHeader(title: 'reports.tax_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.receipt,
                title: 'reports.sales_tax_report'.tr(),
                subtitle: 'reports.sales_tax_report_desc'.tr(),
                onTap: () => context.push('/reports/sales-tax'),
              ),
              _ReportTile(
                icon: LucideIcons.fileInput,
                title: 'reports.purchase_tax_report'.tr(),
                subtitle: 'reports.purchase_tax_report_desc'.tr(),
                onTap: () => context.push('/reports/purchase-tax'),
              ),
              const SizedBox(height: 24),

              // Salespeople Reports Section
              _SectionHeader(title: 'reports.salespeople_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.userCheck,
                title: 'reports.salespeople_commission'.tr(),
                subtitle: 'reports.salespeople_commission_desc'.tr(),
                onTap: () => context.push('/reports/salespeople-commission'),
              ),
              const SizedBox(height: 24),

              // Expense Reports Section
              _SectionHeader(title: 'reports.expense_reports'.tr()),
              const SizedBox(height: 8),
              _ReportTile(
                icon: LucideIcons.receipt,
                title: 'reports.expense_report'.tr(),
                subtitle: 'reports.expense_report_desc'.tr(),
                onTap: () => context.push('/reports/expense-report'),
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
