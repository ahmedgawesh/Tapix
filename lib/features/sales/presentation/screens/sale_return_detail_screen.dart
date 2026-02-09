import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';
import '../services/sale_pdf_service.dart';

class SaleReturnDetailScreen extends StatefulWidget {
  final int returnId;

  const SaleReturnDetailScreen({super.key, required this.returnId});

  @override
  State<SaleReturnDetailScreen> createState() =>
      _SaleReturnDetailScreenState();
}

class _SaleReturnDetailScreenState extends State<SaleReturnDetailScreen> {
  SaleReturnEntity? _returnEntity;
  SaleEntity? _sale;
  List<SaleReturnItemEntity> _returnItems = [];
  bool _loading = true;
  StreamSubscription<List<SaleReturnItemEntity>>? _itemsSub;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final repo = sl<SaleRepository>();
    final ret = await repo.getSaleReturnById(widget.returnId);
    if (ret == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final sale = await repo.getSaleById(ret.saleId);

    _itemsSub?.cancel();
    _itemsSub =
        repo.watchSaleReturnItemsWithDetails(widget.returnId).listen((items) {
      if (mounted) {
        setState(() {
          _returnItems = items;
        });
      }
    });

    if (mounted) {
      setState(() {
        _returnEntity = ret;
        _sale = sale;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('sales.return_detail'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_returnEntity == null) {
      return Scaffold(
        appBar: AppBar(title: Text('sales.return_detail'.tr())),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.alertCircle,
                  size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('sales.not_found'.tr(),
                  style: theme.textTheme.titleLarge),
            ],
          ),
        ),
      );
    }

    final ret = _returnEntity!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/sales/returns');
            }
          },
        ),
        title: Text('sales.return_detail'.tr()),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.printer),
            tooltip: 'sales.print_invoice'.tr(),
            onPressed: () => _printOrShare(share: false),
          ),
          IconButton(
            icon: const Icon(LucideIcons.share2),
            tooltip: 'sales.share_invoice'.tr(),
            onPressed: () => _printOrShare(share: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildReturnInfoCard(context, ret, cs),
          const SizedBox(height: 12),
          if (_sale != null) _buildOriginalSaleCard(context, _sale!, cs),
          if (_sale != null) const SizedBox(height: 12),
          _buildRefundMethodCard(context, ret),
          const SizedBox(height: 12),
          _buildReturnItemsCard(context, _returnItems, cs),
          const SizedBox(height: 12),
          _buildTotalCard(context, ret, cs),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _printOrShare({required bool share}) async {
    if (_returnEntity == null || _sale == null) return;
    try {
      if (share) {
        await SalePdfService.shareSaleReturn(
          context: context,
          originalSale: _sale!,
          returnEntity: _returnEntity!,
          returnItems: _returnItems,
        );
      } else {
        await SalePdfService.printSaleReturn(
          context: context,
          originalSale: _sale!,
          returnEntity: _returnEntity!,
          returnItems: _returnItems,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('sales.print_error'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // RETURN INFO CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildReturnInfoCard(
      BuildContext context, SaleReturnEntity ret, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final statusColor = ret.isVoided ? colorScheme.error : Colors.green;
    final statusLabel = ret.isVoided
        ? 'sales.status_voided'.tr()
        : 'sales.status_posted'.tr();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.error,
                        colorScheme.error.withValues(alpha: 0.7)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.undo2,
                      size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('sales.return_number'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              letterSpacing: 0.5)),
                      Text(ret.returnNumber,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Divider(
                height: 24,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            _infoRow(theme, 'sales.date'.tr(),
                DateFormat.yMMMd().format(ret.returnDate)),
            const SizedBox(height: 8),
            if (ret.reason != null && ret.reason!.isNotEmpty) ...[
              _infoRow(theme, 'sales.return_reason'.tr(), ret.reason!),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ORIGINAL SALE CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildOriginalSaleCard(
      BuildContext context, SaleEntity sale, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customerInitial = sale.customerName != null &&
            sale.customerName!.isNotEmpty
        ? sale.customerName![0].toUpperCase()
        : '?';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side:
            BorderSide(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/sales/${sale.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.primary.withValues(alpha: 0.7)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.fileText,
                        size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('sales.return_from_sale'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                letterSpacing: 0.5)),
                        Text(sale.invoiceNumber,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronRight,
                      size: 18, color: colorScheme.onSurfaceVariant),
                ],
              ),
              Divider(
                  height: 24,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              if (sale.customerName != null) ...[
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(customerInitial,
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('sales.customer'.tr(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant)),
                          Text(sale.customerName!,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              _infoRow(theme, 'sales.total'.tr(),
                  cs.format(sale.totalCents.toBigInt().toInt())),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // REFUND METHOD CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildRefundMethodCard(
      BuildContext context, SaleReturnEntity ret) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    IconData methodIcon;
    switch (ret.refundMethod) {
      case 'cash':
        methodIcon = LucideIcons.banknote;
        break;
      case 'cheque':
        methodIcon = LucideIcons.fileCheck;
        break;
      default:
        methodIcon = LucideIcons.wallet;
    }

    IconData dispositionIcon;
    switch (ret.dispositionType) {
      case 'write_off':
        dispositionIcon = LucideIcons.trash2;
        break;
      case 'exchange':
        dispositionIcon = LucideIcons.repeat;
        break;
      case 'store_credit':
        dispositionIcon = LucideIcons.wallet;
        break;
      case 'refund':
        dispositionIcon = LucideIcons.banknote;
        break;
      default:
        dispositionIcon = LucideIcons.package;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Icon(LucideIcons.creditCard, size: 16, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text('sales.refund_method'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(methodIcon, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'sales.refund_method_${ret.refundMethod}'.tr(),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                            'sales.refund_method_${ret.refundMethod}_desc'
                                .tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant, fontSize: 10)),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.checkCircle2, size: 18, color: cs.primary),
                ],
              ),
            ),
            Divider(
                height: 20,
                color: cs.outlineVariant.withValues(alpha: 0.4)),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(LucideIcons.package,
                      size: 16, color: Colors.amber.shade700),
                ),
                const SizedBox(width: 10),
                Text('sales.disposition_type'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(dispositionIcon, size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                          'sales.disposition_${ret.dispositionType}'.tr(),
                          style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // RETURN ITEMS CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildReturnItemsCard(BuildContext context,
      List<SaleReturnItemEntity> items, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.error,
                        colorScheme.error.withValues(alpha: 0.7)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.undo2,
                      size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('sales.return_items'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${items.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('sales.no_items_to_return'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color:
                        colorScheme.outlineVariant.withValues(alpha: 0.5)),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final productName =
                      item.productName ?? 'Item #${item.saleItemId}';

                  final variantParts = <String>[];
                  if (item.colorName != null && item.colorName!.isNotEmpty) {
                    variantParts.add(item.colorName!);
                  }
                  if (item.sizeName != null && item.sizeName!.isNotEmpty) {
                    variantParts.add(item.sizeName!);
                  }
                  if (item.variantSku != null && item.variantSku!.isNotEmpty) {
                    variantParts.add(item.variantSku!);
                  }
                  final variantLine = variantParts.isNotEmpty
                      ? variantParts.join(' · ')
                      : null;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        if (item.colorHex != null &&
                            item.colorHex!.isNotEmpty)
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(int.parse(
                                  'FF${item.colorHex!.replaceAll('#', '')}',
                                  radix: 16)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: colorScheme.outlineVariant),
                            ),
                            alignment: Alignment.center,
                            child: Text('${index + 1}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      const Shadow(
                                          blurRadius: 2,
                                          color: Colors.black54)
                                    ])),
                          )
                        else
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text('${index + 1}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: colorScheme.error,
                                    fontWeight: FontWeight.bold)),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(productName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500)),
                              if (variantLine != null)
                                Text(variantLine,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.primary,
                                        fontSize: 11)),
                              Text(
                                  '${'sales.return_qty'.tr()}: ${item.quantity}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 11)),
                              if (item.reason != null &&
                                  item.reason!.isNotEmpty)
                                Text(item.reason!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontStyle: FontStyle.italic,
                                        fontSize: 10)),
                            ],
                          ),
                        ),
                        Text(
                            cs.format(
                                item.refundCents.toBigInt().toInt()),
                            style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.error,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TOTAL CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildTotalCard(
      BuildContext context, SaleReturnEntity ret, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.2)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('sales.total_refund'.tr(),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(cs.format(ret.totalCents.toBigInt().toInt()),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold, color: colorScheme.error)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    final cs = theme.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(
                  label.contains('Date') || label.contains('تاريخ')
                      ? LucideIcons.calendar
                      : LucideIcons.info,
                  size: 12,
                  color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
        Flexible(
          child: Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
