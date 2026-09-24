import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/promotions/promotion_sale_snapshot.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/services/lan/lan_error_localizer.dart';

/// Read-only sale-return details loaded from the authenticated LAN master.
///
/// Mutating actions deliberately remain on the master until their audit and
/// PIN policies have dedicated remote endpoints.
class LanSaleReturnDetailScreen extends StatefulWidget {
  final int returnId;
  final bool adjustment;

  const LanSaleReturnDetailScreen({
    super.key,
    required this.returnId,
    required this.adjustment,
  });

  @override
  State<LanSaleReturnDetailScreen> createState() =>
      _LanSaleReturnDetailScreenState();
}

class _LanSaleReturnDetailScreenState extends State<LanSaleReturnDetailScreen> {
  LanSaleReturnDetails? _details;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final details = await sl<LanNetworkService>()
          .fetchRemoteSaleReturnDetails(
            returnId: widget.returnId,
            adjustment: widget.adjustment,
          );
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is LanBusinessException
            ? localizeLanBusinessError(error)
            : 'settings.network.request_failed'.tr();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.adjustment
        ? 'returns.adjustment_detail'.tr()
        : 'sales.return_detail'.tr();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/sales/returns'),
        ),
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'common.refresh'.tr(),
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _details == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.alertCircle,
                size: 56,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                _error ?? 'sales.not_found'.tr(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw),
                label: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    final details = _details!;
    final summary = details.summary;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(context, details),
          const SizedBox(height: 12),
          if (!summary.isAdjustment && summary.saleId > 0) ...[
            _originalSaleCard(context, summary),
            const SizedBox(height: 12),
          ],
          _partyAndMethodCard(context, details),
          const SizedBox(height: 12),
          _itemsCard(context, details),
          const SizedBox(height: 12),
          _totalsCard(context, details),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _summaryCard(BuildContext context, LanSaleReturnDetails details) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final summary = details.summary;
    final voided = summary.status == 'voided';
    final cleanReason = _cleanNotes(summary.reason);

    return _card(
      context,
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.errorContainer,
                foregroundColor: colors.onErrorContainer,
                child: const Icon(LucideIcons.undo2, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'sales.return_number'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      summary.returnNumber,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(_statusLabel(summary.status)),
                side: BorderSide.none,
                backgroundColor: voided
                    ? colors.errorContainer
                    : colors.primaryContainer,
              ),
            ],
          ),
          const Divider(height: 24),
          _infoRow(
            context,
            'sales.date'.tr(),
            DateFormat(
              'dd/MM/yyyy',
            ).add_jm().format(summary.returnDate.toLocal()),
          ),
          if (cleanReason != null) ...[
            const SizedBox(height: 8),
            _infoRow(context, 'sales.return_reason'.tr(), cleanReason),
          ],
        ],
      ),
    );
  }

  Widget _originalSaleCard(BuildContext context, LanSaleReturnSummary summary) {
    final colors = Theme.of(context).colorScheme;
    return _card(
      context,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/sales/${summary.saleId}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(LucideIcons.fileText, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('sales.return_from_sale'.tr()),
                    Text(
                      summary.saleInvoiceNumber ?? '#${summary.saleId}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronRight, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _partyAndMethodCard(
    BuildContext context,
    LanSaleReturnDetails details,
  ) {
    final summary = details.summary;
    final customer = summary.customerName?.trim();
    final employee = details.employeeName?.trim();
    return _card(
      context,
      child: Column(
        children: [
          _infoRow(
            context,
            'sales.customer'.tr(),
            customer == null || customer.isEmpty
                ? 'returns.walk_in_customer'.tr()
                : customer,
          ),
          if (employee != null && employee.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(context, 'sales.salesperson'.tr(), employee),
          ],
          const SizedBox(height: 8),
          _infoRow(
            context,
            'sales.refund_method'.tr(),
            _translatedOrRaw(
              'sales.refund_method_${summary.refundMethod}',
              summary.refundMethod,
            ),
          ),
          const SizedBox(height: 8),
          _infoRow(
            context,
            'sales.disposition_type'.tr(),
            _translatedOrRaw(
              'sales.disposition_${summary.dispositionType}',
              summary.dispositionType,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemsCard(BuildContext context, LanSaleReturnDetails details) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.package, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'sales.return_items'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text('${details.lines.length}'),
            ],
          ),
          const SizedBox(height: 10),
          if (details.lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('sales.no_items'.tr())),
            )
          else
            ...details.lines.indexed.map((entry) {
              final index = entry.$1;
              final line = entry.$2;
              return Column(
                children: [
                  if (index > 0) const Divider(height: 22),
                  _lineTile(context, details, line),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _lineTile(
    BuildContext context,
    LanSaleReturnDetails details,
    LanSaleReturnDetailLine line,
  ) {
    final theme = Theme.of(context);
    final attributes = <String>[
      if (line.colorName?.trim().isNotEmpty == true) line.colorName!.trim(),
      if (line.sizeName?.trim().isNotEmpty == true) line.sizeName!.trim(),
      if ((line.variantSku ?? line.productSku)?.trim().isNotEmpty == true)
        'SKU: ${(line.variantSku ?? line.productSku)!.trim()}',
    ];
    final offers = line.saleItemId == null
        ? const <SalePromotionSnapshot>[]
        : details.promotionApplications
              .where(
                (offer) => offer.allocations.any(
                  (allocation) => allocation.saleItemId == line.saleItemId,
                ),
              )
              .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.productName.isEmpty
                        ? '#${line.productId}'
                        : line.productName,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (attributes.isNotEmpty)
                    Text(
                      attributes.join(' • '),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (offers.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: offers
                          .map((offer) {
                            final allocation = offer.allocations.firstWhere(
                              (row) => row.saleItemId == line.saleItemId,
                            );
                            return Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(
                                LucideIcons.badgePercent,
                                size: 14,
                              ),
                              label: Text(
                                '${offer.name}  -${_money(context, details, allocation.discountCents)}',
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    localizedQuantity(line.quantity, line.measurementType),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _money(context, details, line.totalCents),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (line.unitPriceCents != null) ...[
          const SizedBox(height: 4),
          _infoRow(
            context,
            'returns.unit_price'.tr(),
            _money(context, details, line.unitPriceCents!),
          ),
        ],
        if (line.reason?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          _infoRow(context, 'returns.reason'.tr(), line.reason!.trim()),
        ],
      ],
    );
  }

  Widget _totalsCard(BuildContext context, LanSaleReturnDetails details) {
    final summary = details.summary;
    return _card(
      context,
      child: Column(
        children: [
          _moneyRow(
            context,
            'sales.subtotal'.tr(),
            _money(context, details, summary.subtotalCents),
          ),
          if (summary.discountCents != 0) ...[
            const SizedBox(height: 8),
            _moneyRow(
              context,
              'sales.discount'.tr(),
              _money(context, details, summary.discountCents),
            ),
          ],
          if (summary.taxCents != 0) ...[
            const SizedBox(height: 8),
            _moneyRow(
              context,
              'sales.tax'.tr(),
              _money(context, details, summary.taxCents),
            ),
          ],
          const Divider(height: 24),
          _moneyRow(
            context,
            'returns.total_refund'.tr(),
            _money(context, details, summary.totalCents),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _moneyRow(
    BuildContext context,
    String label,
    String value, {
    bool emphasized = false,
  }) {
    final style = emphasized
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }

  String _money(BuildContext context, LanSaleReturnDetails details, int cents) {
    final digits = details.currencyDecimalDigits.clamp(0, 6);
    final value = cents / math.pow(10, digits);
    final formatted = NumberFormat.decimalPatternDigits(
      locale: context.locale.toString(),
      decimalDigits: digits,
    ).format(value);
    final symbol = details.currencySymbol.trim().isEmpty
        ? details.currencyCode
        : details.currencySymbol;
    return details.currencySymbolAfter
        ? '$formatted $symbol'
        : '$symbol $formatted';
  }

  String _statusLabel(String status) {
    return _translatedOrRaw('sales.status_$status', status);
  }

  String _translatedOrRaw(String key, String raw) {
    final translated = key.tr();
    return translated == key ? raw.replaceAll('_', ' ') : translated;
  }

  String? _cleanNotes(String? value) {
    final clean = value
        ?.replaceFirst(RegExp(r'^\[REASON:[^\]]+\]\s*'), '')
        .trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
