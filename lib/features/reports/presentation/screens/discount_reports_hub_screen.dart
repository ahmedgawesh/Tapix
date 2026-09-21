import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DiscountReportsHubScreen extends StatelessWidget {
  const DiscountReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('reports.discount_reports'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'reports.discount_breakdown'.tr()),
          const SizedBox(height: 8),
          _ReportTile(
            icon: LucideIcons.package2,
            title: 'reports.discount_by_product'.tr(),
            subtitle: 'reports.discount_by_product_desc'.tr(),
            onTap: () => context.push('/reports/discounts/by-product'),
          ),
          _ReportTile(
            icon: LucideIcons.layoutGrid,
            title: 'reports.discount_by_category'.tr(),
            subtitle: 'reports.discount_by_category_desc'.tr(),
            onTap: () => context.push('/reports/discounts/by-category'),
          ),
          _ReportTile(
            icon: LucideIcons.users,
            title: 'reports.discount_by_customer'.tr(),
            subtitle: 'reports.discount_by_customer_desc'.tr(),
            onTap: () => context.push('/reports/discounts/by-customer'),
          ),
          _ReportTile(
            icon: LucideIcons.receipt,
            title: 'reports.discount_by_invoice'.tr(),
            subtitle: 'reports.discount_by_invoice_desc'.tr(),
            onTap: () => context.push('/reports/discounts/by-invoice'),
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
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
