import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../services/purchase_pdf_service.dart';

class PurchaseReturnDetailScreen extends StatefulWidget {
  final int returnId;

  const PurchaseReturnDetailScreen({super.key, required this.returnId});

  @override
  State<PurchaseReturnDetailScreen> createState() =>
      _PurchaseReturnDetailScreenState();
}

class _PurchaseReturnDetailScreenState
    extends State<PurchaseReturnDetailScreen> {
  PurchaseReturnEntity? _returnEntity;
  PurchaseEntity? _purchase;
  List<PurchaseReturnItemEntity> _returnItems = [];
  bool _loading = true;
  StreamSubscription<List<PurchaseReturnItemEntity>>? _itemsSub;

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
    final repo = sl<PurchaseRepository>();
    final ret = await repo.getPurchaseReturnById(widget.returnId);
    if (ret == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final purchase = await repo.getPurchaseById(ret.purchaseId);

    // Subscribe to realtime updates for return items
    _itemsSub?.cancel();
    _itemsSub = repo.watchPurchaseReturnItemsWithDetails(widget.returnId).listen((items) {
      if (mounted) {
        setState(() {
          _returnItems = items;
        });
      }
    });

    if (mounted) {
      setState(() {
        _returnEntity = ret;
        _purchase = purchase;
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
        appBar: AppBar(title: Text('purchases.return_detail'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_returnEntity == null) {
      return Scaffold(
        appBar: AppBar(title: Text('purchases.return_detail'.tr())),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.alertCircle,
                  size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('purchases.not_found'.tr(),
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
              context.go('/purchases/returns');
            }
          },
        ),
        title: Text('purchases.return_detail'.tr()),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.printer),
            tooltip: 'purchases.print_invoice'.tr(),
            onPressed: () => _printOrShare(share: false),
          ),
          IconButton(
            icon: const Icon(LucideIcons.share2),
            tooltip: 'purchases.share_pdf'.tr(),
            onPressed: () => _printOrShare(share: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildReturnInfoCard(context, ret, cs),
          const SizedBox(height: 12),
          if (_purchase != null)
            _buildOriginalPurchaseCard(context, _purchase!, cs),
          if (_purchase != null) const SizedBox(height: 12),
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
    if (_returnEntity == null || _purchase == null) return;
    try {
      if (share) {
        await PurchasePdfService.sharePurchaseReturn(
          context: context,
          originalPurchase: _purchase!,
          returnEntity: _returnEntity!,
          returnItems: _returnItems,
        );
      } else {
        await PurchasePdfService.printPurchaseReturn(
          context: context,
          originalPurchase: _purchase!,
          returnEntity: _returnEntity!,
          returnItems: _returnItems,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('purchases.print_error'.tr()),
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
      BuildContext context, PurchaseReturnEntity ret, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final statusColor = ret.isVoided ? colorScheme.error : Colors.green;
    final statusLabel = ret.isVoided
        ? 'purchases.status_voided'.tr()
        : 'purchases.status_posted'.tr();

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
                      Text('purchases.return_number'.tr(),
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
            _infoRow(theme, 'purchases.return_date'.tr(),
                DateFormat.yMMMd().format(ret.returnDate)),
            const SizedBox(height: 8),
            if (ret.reason != null && ret.reason!.isNotEmpty) ...[
              _infoRow(theme, 'purchases.return_reason'.tr(), ret.reason!),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ORIGINAL PURCHASE CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildOriginalPurchaseCard(
      BuildContext context, PurchaseEntity purchase, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final supplierInitial = purchase.supplierName != null &&
            purchase.supplierName!.isNotEmpty
        ? purchase.supplierName![0].toUpperCase()
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
        onTap: () => context.push('/purchases/${purchase.id}'),
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
                        Text('purchases.return_from_purchase'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                letterSpacing: 0.5)),
                        Text(purchase.purchaseNumber,
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
              if (purchase.supplierName != null) ...[
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
                      child: Text(supplierInitial,
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('purchases.supplier'.tr(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant)),
                          Text(purchase.supplierName!,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              _infoRow(theme, 'purchases.total'.tr(),
                  cs.format(purchase.totalCents.toBigInt().toInt())),
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
      BuildContext context, PurchaseReturnEntity ret) {
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
                Text('purchases.refund_method'.tr(),
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
                            'purchases.refund_method_${ret.refundMethod}'.tr(),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                            'purchases.refund_method_${ret.refundMethod}_desc'
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
                Text('purchases.disposition_type'.tr(),
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
                          'purchases.disposition_${ret.dispositionType}'.tr(),
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
      List<PurchaseReturnItemEntity> items, CurrencyService cs) {
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
                Text('purchases.return_items'.tr(),
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
                  child: Text('purchases.no_items_to_return'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (context2, idx2) => Divider(
                    height: 1,
                    color:
                        colorScheme.outlineVariant.withValues(alpha: 0.5)),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final productName = item.productName ?? 'Item #${item.purchaseItemId}';

                  // Build variant details line (color · size · SKU)
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
                        // Color swatch or index number
                        if (item.colorHex != null && item.colorHex!.isNotEmpty)
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(int.parse('FF${item.colorHex!.replaceAll('#', '')}', radix: 16)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colorScheme.outlineVariant),
                            ),
                            alignment: Alignment.center,
                            child: Text('${index + 1}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    shadows: [const Shadow(blurRadius: 2, color: Colors.black54)])),
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
                                  '${'purchases.qty'.tr()}: ${item.quantity}',
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
      BuildContext context, PurchaseReturnEntity ret, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final subtotal = ret.subtotalCents.toBigInt().toInt();
    final discount = ret.discountCents.toBigInt().toInt();
    final tax = ret.taxCents.toBigInt().toInt();
    final total = ret.totalCents.toBigInt().toInt();

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
        child: Column(
          children: [
            if (subtotal != 0 || discount != 0 || tax != 0) ...[
              _totalRow(theme, 'purchases.subtotal'.tr(), cs.format(subtotal)),
              if (discount != 0)
                _totalRow(theme, 'purchases.discount'.tr(), '- ${cs.format(discount)}',
                    valueColor: Colors.green),
              if (tax != 0)
                _totalRow(theme, 'purchases.tax'.tr(), cs.format(tax)),
              Divider(height: 16, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('purchases.return_total'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(cs.format(total),
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold, color: colorScheme.error)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(ThemeData theme, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: valueColor)),
        ],
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
