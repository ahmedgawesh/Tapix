import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../bloc/customer_invoices_report_bloc.dart' show InvoiceLineItem;

/// Localize a payment method machine code into the active locale.
String localizePaymentMethod(String? method) {
  if (method == null || method.isEmpty) return '-';
  switch (method) {
    case 'cash':
      return 'reports.pm_cash'.tr();
    case 'card':
      return 'reports.pm_card'.tr();
    case 'credit':
      return 'reports.pm_credit'.tr();
    case 'cheque':
      return 'reports.pm_cheque'.tr();
    case 'bank_transfer':
      return 'reports.pm_bank_transfer'.tr();
    case 'mobile':
      return 'reports.pm_mobile'.tr();
    default:
      return method;
  }
}

// ═══════════════════════════════════════════════════════
// PARTY INFO CARD
// ═══════════════════════════════════════════════════════

class InvoicePartyInfoCard extends StatelessWidget {
  final String name;
  final String? phone;
  final String? address;
  final IconData icon;

  const InvoicePartyInfoCard({
    super.key,
    required this.name,
    this.phone,
    this.address,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(icon, color: colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (phone != null && phone!.isNotEmpty)
                    Text(
                      phone!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (address != null && address!.isNotEmpty)
                    Text(
                      address!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUMMARY CARDS ROW
// ═══════════════════════════════════════════════════════

class InvoiceSummaryCardsRow extends StatelessWidget {
  final int invoiceCount;
  final String totalQuantityText;
  final int totalAmountCents;
  final int totalDiscountCents;
  final int totalPaidCents;
  final CurrencyService cs;

  const InvoiceSummaryCardsRow({
    super.key,
    required this.invoiceCount,
    required this.totalQuantityText,
    required this.totalAmountCents,
    required this.totalDiscountCents,
    required this.totalPaidCents,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SummaryCard(
            label: 'reports.invoices_count'.tr(),
            value: invoiceCount.toString(),
            icon: LucideIcons.fileText,
            color: Colors.indigo.shade600,
          ),
          const SizedBox(width: 8),
          _SummaryCard(
            label: 'reports.total_quantity'.tr(),
            value: totalQuantityText,
            icon: LucideIcons.package,
            color: Colors.teal.shade600,
          ),
          const SizedBox(width: 8),
          _SummaryCard(
            label: 'reports.total_amount'.tr(),
            value: cs.formatCents(totalAmountCents),
            icon: LucideIcons.receipt,
            color: Colors.red.shade600,
          ),
          const SizedBox(width: 8),
          _SummaryCard(
            label: 'reports.total_discount'.tr(),
            value: cs.formatCents(totalDiscountCents),
            icon: LucideIcons.badgePercent,
            color: Colors.purple.shade600,
          ),
          const SizedBox(width: 8),
          _SummaryCard(
            label: 'reports.total_paid'.tr(),
            value: cs.formatCents(totalPaidCents),
            icon: LucideIcons.banknote,
            color: Colors.green.shade600,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// INVOICE CARD (header + items table + totals)
// ═══════════════════════════════════════════════════════

class InvoiceCard extends StatelessWidget {
  final String invoiceNumber;
  final String? referenceLabel;
  final DateTime date;
  final List<InvoiceLineItem> items;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int paidAmountCents;
  final String? paymentMethod;
  final CurrencyService cs;

  const InvoiceCard({
    super.key,
    required this.invoiceNumber,
    this.referenceLabel,
    required this.date,
    required this.items,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidAmountCents,
    required this.paymentMethod,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dueCents = totalCents - paidAmountCents;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Container(
            width: double.infinity,
            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(LucideIcons.receipt, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoiceNumber,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (referenceLabel != null && referenceLabel!.isNotEmpty)
                        Text(
                          referenceLabel!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat('dd/MM/yyyy').format(date),
                      style: theme.textTheme.bodySmall,
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        localizePaymentMethod(paymentMethod),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Items table ──
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(4),
                  1: FlexColumnWidth(1.2),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    children: [
                      _cellHeader(context, 'reports.product'.tr()),
                      _cellHeader(
                        context,
                        'reports.qty'.tr(),
                        align: TextAlign.center,
                      ),
                      _cellHeader(
                        context,
                        'reports.unit_price'.tr(),
                        align: TextAlign.end,
                      ),
                      _cellHeader(
                        context,
                        'reports.line_total'.tr(),
                        align: TextAlign.end,
                      ),
                    ],
                  ),
                  ...items.map(
                    (item) => TableRow(
                      children: [
                        _cellProduct(context, item),
                        _cellText(
                          context,
                          localizedQuantity(
                            item.quantity,
                            item.measurementType,
                          ),
                          align: TextAlign.center,
                        ),
                        _cellText(
                          context,
                          cs.formatCents(item.unitPriceCents),
                          align: TextAlign.end,
                        ),
                        _cellText(
                          context,
                          cs.formatCents(item.totalCents),
                          align: TextAlign.end,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // ── Totals ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                _totalRow(
                  context,
                  'reports.subtotal'.tr(),
                  cs.formatCents(subtotalCents),
                ),
                if (discountCents > 0)
                  _totalRow(
                    context,
                    'reports.discount'.tr(),
                    '- ${cs.formatCents(discountCents)}',
                    color: Colors.purple.shade700,
                  ),
                if (taxCents > 0)
                  _totalRow(
                    context,
                    'reports.tax'.tr(),
                    cs.formatCents(taxCents),
                  ),
                _totalRow(
                  context,
                  'reports.total'.tr(),
                  cs.formatCents(totalCents),
                  isBold: true,
                ),
                _totalRow(
                  context,
                  'reports.paid'.tr(),
                  cs.formatCents(paidAmountCents),
                  color: Colors.green.shade700,
                ),
                if (dueCents > 0)
                  _totalRow(
                    context,
                    'reports.due'.tr(),
                    cs.formatCents(dueCents),
                    color: colorScheme.error,
                    isBold: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cellHeader(
    BuildContext context,
    String text, {
    TextAlign align = TextAlign.start,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        textAlign: align,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _cellText(
    BuildContext context,
    String text, {
    TextAlign align = TextAlign.start,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(text, textAlign: align, style: theme.textTheme.bodySmall),
    );
  }

  Widget _cellProduct(BuildContext context, InvoiceLineItem item) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.productName, style: theme.textTheme.bodySmall, maxLines: 2),
          if (item.variantLabel != null)
            Text(
              item.variantLabel!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (item.sku != null && item.sku!.isNotEmpty)
            Text(
              item.sku!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalRow(
    BuildContext context,
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final style =
        (isBold
                ? theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  )
                : theme.textTheme.bodySmall)
            ?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
