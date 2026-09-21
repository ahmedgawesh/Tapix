import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class PurchaseReportsHubScreen extends StatelessWidget {
  const PurchaseReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('reports.purchase_reports'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Period & Payment Method Reports
          _SectionHeader(title: 'reports.purchase_period_reports'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.calendarDays,
            title: 'reports.purchases_report'.tr(),
            subtitle: 'reports.purchases_report_desc'.tr(),
            onTap: () => context.push('/reports/purchases/all'),
          ),
          _ReportTile(
            icon: LucideIcons.banknote,
            title: 'reports.cash_purchases'.tr(),
            subtitle: 'reports.cash_purchases_desc'.tr(),
            onTap: () => context.push('/reports/purchases/cash'),
          ),
          _ReportTile(
            icon: LucideIcons.clock,
            title: 'reports.credit_purchases'.tr(),
            subtitle: 'reports.credit_purchases_desc'.tr(),
            onTap: () => context.push('/reports/purchases/credit'),
          ),
          _ReportTile(
            icon: LucideIcons.creditCard,
            title: 'reports.card_purchases'.tr(),
            subtitle: 'reports.card_purchases_desc'.tr(),
            onTap: () => context.push('/reports/purchases/card'),
          ),
          _ReportTile(
            icon: LucideIcons.fileText,
            title: 'reports.cheque_purchases'.tr(),
            subtitle: 'reports.cheque_purchases_desc'.tr(),
            onTap: () => context.push('/reports/purchases/cheque'),
          ),
          const SizedBox(height: 24),

          // Product & Category Reports
          _SectionHeader(title: 'reports.purchase_product_reports'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.package2,
            title: 'reports.purchases_by_product'.tr(),
            subtitle: 'reports.purchases_by_product_desc'.tr(),
            onTap: () => context.push('/reports/purchases/by-product'),
          ),
          _ReportTile(
            icon: LucideIcons.folderOpen,
            title: 'reports.purchases_by_category'.tr(),
            subtitle: 'reports.purchases_by_category_desc'.tr(),
            onTap: () => context.push('/reports/purchases/by-category'),
          ),
          const SizedBox(height: 24),

          // Supplier Reports
          _SectionHeader(title: 'reports.purchase_supplier_reports'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.truck,
            title: 'reports.purchases_by_supplier'.tr(),
            subtitle: 'reports.purchases_by_supplier_desc'.tr(),
            onTap: () => context.push('/reports/purchases/by-supplier'),
          ),
          const SizedBox(height: 24),

          // Cancelled & Orders
          _SectionHeader(title: 'reports.purchase_other_reports'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.ban,
            title: 'reports.cancelled_purchases'.tr(),
            subtitle: 'reports.cancelled_purchases_desc'.tr(),
            onTap: () => context.push('/reports/purchases/cancelled'),
          ),
          _ReportTile(
            icon: LucideIcons.clipboardList,
            title: 'reports.purchase_orders'.tr(),
            subtitle: 'reports.purchase_orders_desc'.tr(),
            onTap: () => context.push('/reports/purchases/orders'),
          ),
          const SizedBox(height: 24),

          // Excel Export
          _SectionHeader(title: 'reports.purchase_export'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.fileSpreadsheet,
            title: 'reports.purchases_excel'.tr(),
            subtitle: 'reports.purchases_excel_desc'.tr(),
            onTap: () => context.push('/reports/purchases/excel'),
          ),
          _ReportTile(
            icon: LucideIcons.fileSpreadsheet,
            title: 'reports.purchases_excel_products'.tr(),
            subtitle: 'reports.purchases_excel_products_desc'.tr(),
            onTap: () => context.push('/reports/purchases/excel-products'),
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
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          LucideIcons.chevronRight,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}
