import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SalesReportsHubScreen extends StatelessWidget {
  const SalesReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('reports.sales_reports'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Period & Payment Method Reports
          _SectionHeader(title: 'reports.sales_period_reports'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.calendarDays,
            title: 'reports.sales_by_period'.tr(),
            subtitle: 'reports.sales_by_period_desc'.tr(),
            onTap: () => context.push('/reports/sales/by-period'),
          ),
          _ReportTile(
            icon: LucideIcons.banknote,
            title: 'reports.cash_sales'.tr(),
            subtitle: 'reports.cash_sales_desc'.tr(),
            onTap: () => context.push('/reports/sales/cash'),
          ),
          _ReportTile(
            icon: LucideIcons.clock,
            title: 'reports.credit_sales'.tr(),
            subtitle: 'reports.credit_sales_desc'.tr(),
            onTap: () => context.push('/reports/sales/credit'),
          ),
          _ReportTile(
            icon: LucideIcons.creditCard,
            title: 'reports.card_sales'.tr(),
            subtitle: 'reports.card_sales_desc'.tr(),
            onTap: () => context.push('/reports/sales/card'),
          ),
          _ReportTile(
            icon: LucideIcons.fileText,
            title: 'reports.cheque_sales'.tr(),
            subtitle: 'reports.cheque_sales_desc'.tr(),
            onTap: () => context.push('/reports/sales/cheque'),
          ),
          _ReportTile(
            icon: LucideIcons.listOrdered,
            title: 'reports.all_sales'.tr(),
            subtitle: 'reports.all_sales_desc'.tr(),
            onTap: () => context.push('/reports/sales/all'),
          ),
          const SizedBox(height: 24),

          // Product & Category Reports
          _SectionHeader(title: 'reports.sales_product_reports'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.package2,
            title: 'reports.sales_by_product'.tr(),
            subtitle: 'reports.sales_by_product_desc'.tr(),
            onTap: () => context.push('/reports/sales/by-product'),
          ),
          _ReportTile(
            icon: LucideIcons.folderOpen,
            title: 'reports.sales_by_category'.tr(),
            subtitle: 'reports.sales_by_category_desc'.tr(),
            onTap: () => context.push('/reports/sales/by-category'),
          ),
          const SizedBox(height: 24),

          // Customer Reports
          _SectionHeader(title: 'reports.sales_customer_reports'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.users,
            title: 'reports.sales_by_customer'.tr(),
            subtitle: 'reports.sales_by_customer_desc'.tr(),
            onTap: () => context.push('/reports/sales/by-customer'),
          ),
          const SizedBox(height: 24),

          // Cancelled & Tax Reports
          _SectionHeader(title: 'reports.sales_other_reports'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.ban,
            title: 'reports.cancelled_invoices'.tr(),
            subtitle: 'reports.cancelled_invoices_desc'.tr(),
            onTap: () => context.push('/reports/sales/cancelled'),
          ),
          _ReportTile(
            icon: LucideIcons.receipt,
            title: 'reports.tax_by_product'.tr(),
            subtitle: 'reports.tax_by_product_desc'.tr(),
            onTap: () => context.push('/reports/sales/tax-by-product'),
          ),
          _ReportTile(
            icon: LucideIcons.userCheck,
            title: 'reports.tax_by_customer'.tr(),
            subtitle: 'reports.tax_by_customer_desc'.tr(),
            onTap: () => context.push('/reports/sales/tax-by-customer'),
          ),
          const SizedBox(height: 24),

          // Excel Export
          _SectionHeader(title: 'reports.sales_export'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.fileSpreadsheet,
            title: 'reports.sales_excel'.tr(),
            subtitle: 'reports.sales_excel_desc'.tr(),
            onTap: () => context.push('/reports/sales/excel'),
          ),
          _ReportTile(
            icon: LucideIcons.fileSpreadsheet,
            title: 'reports.sales_excel_products'.tr(),
            subtitle: 'reports.sales_excel_products_desc'.tr(),
            onTap: () => context.push('/reports/sales/excel-products'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
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
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: colorScheme.primary),
        ),
        title: Text(title, style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        )),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        )),
        trailing: Icon(LucideIcons.chevronRight, size: 18, color: colorScheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}
