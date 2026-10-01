import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../data/company_branch_monitor_service.dart';
import '../services/company_document_pdf_service.dart';

class CompanyDocumentDetailScreen extends StatelessWidget {
  const CompanyDocumentDetailScreen({required this.document, super.key});

  final CompanyDocumentSnapshot document;

  Future<void> _export(BuildContext context, {required bool share}) async {
    try {
      if (share) {
        await CompanyDocumentPdfService.shareDocument(
          document: document,
          languageCode: context.locale.languageCode,
        );
      } else {
        await CompanyDocumentPdfService.printDocument(
          document: document,
          languageCode: context.locale.languageCode,
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('company_monitor.details.export_failed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('company_monitor.details.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'company_monitor.details.print'.tr(),
            onPressed: () => _export(context, share: false),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'company_monitor.details.share'.tr(),
            onPressed: () => _export(context, share: true),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _Header(document: document),
                const SizedBox(height: 12),
                _LocationAndParty(document: document),
                const SizedBox(height: 12),
                _MoneySummary(document: document),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'company_monitor.details.items'.tr(
                          namedArgs: {'count': '${document.itemCount}'},
                        ),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (document.lines.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        'company_monitor.details.legacy_summary'.tr(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      if (!wide) {
                        return Column(
                          children: [
                            for (var i = 0; i < document.lines.length; i++) ...[
                              _LineCard(
                                index: i + 1,
                                line: document.lines[i],
                                currency: document.currencyCode,
                              ),
                              if (i != document.lines.length - 1)
                                const SizedBox(height: 10),
                            ],
                          ],
                        );
                      }
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (var i = 0; i < document.lines.length; i++)
                            SizedBox(
                              width: (constraints.maxWidth - 12) / 2,
                              child: _LineCard(
                                index: i + 1,
                                line: document.lines[i],
                                currency: document.currencyCode,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                if (document.originalDocumentId != null) ...[
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.link,
                    title: 'company_monitor.details.original_document'.tr(),
                    value: document.originalDocumentId!,
                  ),
                ],
                if (document.notes?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.notes_outlined,
                    title: 'company_monitor.details.notes'.tr(),
                    value: document.notes!.trim(),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  color: theme.colorScheme.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.verified_user_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            document.isRemote
                                ? 'company_monitor.details.remote_evidence'.tr()
                                : 'company_monitor.details.local_evidence'.tr(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.document});
  final CompanyDocumentSnapshot document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = document.isVoided
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return Card(
      color: statusColor.withValues(alpha: 0.09),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.14),
                  child: Icon(_kindIcon(document.kind), color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kindLabel(document.kind),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        document.number,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Chip(
                avatar: Icon(
                  document.isVoided
                      ? Icons.cancel_outlined
                      : Icons.check_circle_outline,
                  size: 18,
                ),
                label: Text(
                  document.isVoided
                      ? 'company_monitor.voided'.tr()
                      : 'company_monitor.details.posted'.tr(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _SmallFact(
                  icon: Icons.event_outlined,
                  text: DateFormat.yMd().add_Hm().format(
                    document.documentDate.toLocal(),
                  ),
                ),
                _SmallFact(
                  icon: document.isRemote
                      ? Icons.cloud_done_outlined
                      : Icons.computer,
                  text: document.isRemote
                      ? 'company_monitor.remote'.tr()
                      : 'company_monitor.local'.tr(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationAndParty extends StatelessWidget {
  const _LocationAndParty({required this.document});
  final CompanyDocumentSnapshot document;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 24,
        runSpacing: 14,
        children: [
          _LabeledFact(
            icon: Icons.store_outlined,
            label: 'company_monitor.branch'.tr(),
            value: document.branchName,
          ),
          _LabeledFact(
            icon: Icons.warehouse_outlined,
            label: 'company_monitor.warehouse'.tr(),
            value: document.warehouseName,
          ),
          if (document.partyName != null)
            _LabeledFact(
              icon: document.isPurchase
                  ? Icons.local_shipping_outlined
                  : Icons.person_outline,
              label: document.isPurchase
                  ? 'company_monitor.details.supplier'.tr()
                  : 'company_monitor.details.customer'.tr(),
              value: document.partyName!,
            ),
          if (document.paymentMethod != null)
            _LabeledFact(
              icon: Icons.payments_outlined,
              label: 'company_monitor.details.payment_method'.tr(),
              value: _paymentLabel(document.paymentMethod!),
            ),
        ],
      ),
    ),
  );
}

class _MoneySummary extends StatelessWidget {
  const _MoneySummary({required this.document});
  final CompanyDocumentSnapshot document;

  @override
  Widget build(BuildContext context) {
    final values = [
      (
        'company_monitor.details.subtotal'.tr(),
        document.subtotalMinor,
        document.hasFinancialBreakdown,
      ),
      (
        'company_monitor.details.discount'.tr(),
        document.discountMinor,
        document.hasFinancialBreakdown,
      ),
      (
        'company_monitor.details.tax'.tr(),
        document.taxMinor,
        document.hasFinancialBreakdown,
      ),
      (
        'company_monitor.details.paid'.tr(),
        document.paidMinor,
        document.hasFinancialBreakdown,
      ),
      ('company_monitor.details.total'.tr(), document.totalMinor, true),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 5 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value.$3
                              ? _money(document.currencyCode, value.$2)
                              : 'company_monitor.details.unavailable'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.index,
    required this.line,
    required this.currency,
  });

  final int index;
  final CompanyDocumentLineSnapshot line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 17, child: Text('$index')),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.productName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (line.variantName?.isNotEmpty == true)
                        Text(
                          line.variantName!,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _CompactValue(
                  label: 'company_monitor.details.quantity'.tr(),
                  value: _quantity(line),
                ),
                _CompactValue(
                  label: 'company_monitor.details.unit_price'.tr(),
                  value: _money(currency, line.unitMinor),
                ),
                _CompactValue(
                  label: 'company_monitor.details.discount'.tr(),
                  value: _money(currency, line.discountMinor),
                ),
                _CompactValue(
                  label: 'company_monitor.details.tax'.tr(),
                  value: _money(currency, line.taxMinor),
                ),
                _CompactValue(
                  label: 'company_monitor.details.total'.tr(),
                  value: _money(currency, line.totalMinor),
                ),
              ],
            ),
            if (line.batches.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'company_monitor.details.batches'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              for (final batch in line.batches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_2, size: 17),
                      const SizedBox(width: 6),
                      Expanded(child: Text(batch.number)),
                      if (batch.expiryDate != null)
                        Text(
                          DateFormat.yMd().format(batch.expiryDate!.toLocal()),
                        ),
                    ],
                  ),
                ),
            ],
            if (line.reason?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('${'company_monitor.details.reason'.tr()}: ${line.reason}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
  });
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                SelectableText(value),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SmallFact extends StatelessWidget {
  const _SmallFact({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17),
      const SizedBox(width: 5),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ],
  );
}

class _LabeledFact extends StatelessWidget {
  const _LabeledFact({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 190, maxWidth: 360),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CompactValue extends StatelessWidget {
  const _CompactValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );
}

String _money(String currency, int minor) =>
    '$currency ${(minor / 100).toStringAsFixed(2)}';

String _quantity(CompanyDocumentLineSnapshot line) {
  final value = line.quantityScaled / line.quantityScale;
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  final unit = switch (line.measurementType) {
    'weight' => 'company_monitor.details.units.weight'.tr(),
    'length' => 'company_monitor.details.units.length'.tr(),
    'volume' => 'company_monitor.details.units.volume'.tr(),
    _ => 'company_monitor.details.units.piece'.tr(),
  };
  return '$text $unit';
}

String _paymentLabel(String method) => switch (method) {
  'cash' => 'company_monitor.details.payments.cash'.tr(),
  'card' => 'company_monitor.details.payments.card'.tr(),
  'credit' => 'company_monitor.details.payments.credit'.tr(),
  'cheque' => 'company_monitor.details.payments.cheque'.tr(),
  _ => method,
};

String _kindLabel(CompanyDocumentKind kind) => switch (kind) {
  CompanyDocumentKind.purchase => 'company_monitor.kinds.purchase'.tr(),
  CompanyDocumentKind.sale => 'company_monitor.kinds.sale'.tr(),
  CompanyDocumentKind.purchaseReturn =>
    'company_monitor.kinds.purchase_return'.tr(),
  CompanyDocumentKind.saleReturn => 'company_monitor.kinds.sale_return'.tr(),
  CompanyDocumentKind.purchaseAdjustmentReturn =>
    'company_monitor.kinds.purchase_adjustment_return'.tr(),
  CompanyDocumentKind.saleAdjustmentReturn =>
    'company_monitor.kinds.sale_adjustment_return'.tr(),
};

IconData _kindIcon(CompanyDocumentKind kind) => switch (kind) {
  CompanyDocumentKind.purchase => Icons.local_shipping_outlined,
  CompanyDocumentKind.sale => Icons.receipt_long_outlined,
  CompanyDocumentKind.purchaseReturn => Icons.keyboard_return_outlined,
  CompanyDocumentKind.saleReturn => Icons.assignment_return_outlined,
  CompanyDocumentKind.purchaseAdjustmentReturn => Icons.rule_outlined,
  CompanyDocumentKind.saleAdjustmentReturn => Icons.fact_check_outlined,
};
