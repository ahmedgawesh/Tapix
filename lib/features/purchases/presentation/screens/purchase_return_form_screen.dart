import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../bloc/purchase_return_form_bloc.dart';

class PurchaseReturnFormScreen extends StatelessWidget {
  final int purchaseId;

  const PurchaseReturnFormScreen({super.key, required this.purchaseId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PurchaseReturnFormBloc>()
        ..add(PurchaseReturnFormInitialized(purchaseId)),
      child: const _ReturnFormView(),
    );
  }
}

class _ReturnFormView extends StatelessWidget {
  const _ReturnFormView();

  @override
  Widget build(BuildContext context) {
    final cs = sl<CurrencyService>();
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<PurchaseReturnFormBloc, PurchaseReturnFormState>(
      listener: (context, state) {
        if (state.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('purchases.return_saved'.tr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.pop();
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/purchases');
                }
              },
            ),
            title: Text('purchases.create_return'.tr()),
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 900;
                    if (isWide) {
                      return _buildWideLayout(context, state, cs);
                    }
                    return _buildNarrowLayout(context, state, cs);
                  },
                ),
        );
      },
    );
  }

  Widget _buildWideLayout(
      BuildContext context, PurchaseReturnFormState state, CurrencyService cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 360,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildPurchaseInfoCard(context, state, cs),
              const SizedBox(height: 12),
              _buildReasonCard(context, state),
              const SizedBox(height: 12),
              _buildFinancialImpactCard(context, state, cs),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildItemsSelectionCard(context, state, cs),
                  ],
                ),
              ),
              _buildBottomBar(context, state, cs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(
      BuildContext context, PurchaseReturnFormState state, CurrencyService cs) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildPurchaseInfoCard(context, state, cs),
              const SizedBox(height: 12),
              _buildItemsSelectionCard(context, state, cs),
              const SizedBox(height: 12),
              _buildReasonCard(context, state),
              const SizedBox(height: 12),
              _buildFinancialImpactCard(context, state, cs),
              const SizedBox(height: 80),
            ],
          ),
        ),
        _buildBottomBar(context, state, cs),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // PURCHASE INFO CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildPurchaseInfoCard(
      BuildContext context, PurchaseReturnFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final purchase = state.purchase;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
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
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(LucideIcons.fileText, size: 20, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('purchases.return_from_purchase'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant)),
                      Text(purchase?.purchaseNumber ?? '—',
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            if (purchase != null) ...[
              const Divider(height: 24),
              _infoRow(theme, 'purchases.supplier'.tr(),
                  purchase.supplierName ?? '—'),
              const SizedBox(height: 6),
              _infoRow(theme, 'purchases.date'.tr(),
                  DateFormat.yMMMd().format(purchase.purchaseDate)),
              const SizedBox(height: 6),
              _infoRow(theme, 'purchases.total'.tr(),
                  cs.format(purchase.totalCents.toBigInt().toInt())),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // ITEMS SELECTION CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsSelectionCard(
      BuildContext context, PurchaseReturnFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.undo2, size: 20, color: colorScheme.error),
                const SizedBox(width: 8),
                Text('purchases.select_items_to_return'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
                if (state.returnItems.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${state.returnItems.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (state.availableItems.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(LucideIcons.packageX, size: 48,
                        color: colorScheme.onSurface.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),
                    Text('purchases.no_items_to_return'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.availableItems.length,
                separatorBuilder: (_, idx) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                itemBuilder: (context, index) {
                  final item = state.availableItems[index];
                  final returnItem = state.returnItems
                      .where((r) => r.originalItem.id == item.id)
                      .toList();
                  final isSelected = returnItem.isNotEmpty;

                  return _ReturnItemTile(
                    item: item,
                    returnItem: isSelected ? returnItem.first : null,
                    isSelected: isSelected,
                    currencyService: cs,
                    onToggle: () => context
                        .read<PurchaseReturnFormBloc>()
                        .add(ReturnItemToggled(item)),
                    onQuantityChanged: (qty) => context
                        .read<PurchaseReturnFormBloc>()
                        .add(ReturnItemQuantityChanged(item.id, qty)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // REASON CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildReasonCard(BuildContext context, PurchaseReturnFormState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.messageSquare, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('purchases.return_reason'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'purchases.return_reason_hint'.tr(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              maxLines: 3,
              onChanged: (v) => context
                  .read<PurchaseReturnFormBloc>()
                  .add(ReturnReasonChanged(v)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // FINANCIAL IMPACT CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildFinancialImpactCard(
      BuildContext context, PurchaseReturnFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.errorContainer.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.alertCircle, size: 20, color: colorScheme.error),
                const SizedBox(width: 8),
                Text('purchases.financial_impact'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            _impactRow(theme, LucideIcons.package,
                'purchases.inventory_restored'.tr(),
                '+${state.totalReturnQuantity} ${'purchases.items_count'.tr()}',
                Colors.green),
            const SizedBox(height: 8),
            _impactRow(theme, LucideIcons.coins,
                'purchases.supplier_credit'.tr(),
                cs.format(state.totalRefundCents.toBigInt().toInt()),
                colorScheme.error),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('purchases.return_total'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold)),
                Text(cs.format(state.totalRefundCents.toBigInt().toInt()),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _impactRow(ThemeData theme, IconData icon, String label, String value,
      Color valueColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant)),
        ),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(
            color: valueColor, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // BOTTOM BAR
  // ═══════════════════════════════════════════════════════
  Widget _buildBottomBar(
      BuildContext context, PurchaseReturnFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${state.totalReturnQuantity} ${'purchases.items_count'.tr()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  cs.format(state.totalRefundCents.toBigInt().toInt()),
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold, color: colorScheme.error),
                ),
              ],
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: state.isSubmitting ? null : () {
                if (context.canPop()) context.pop();
              },
              child: Text('common.cancel'.tr()),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: state.isSubmitting || state.returnItems.isEmpty
                  ? null
                  : () => context
                      .read<PurchaseReturnFormBloc>()
                      .add(const PurchaseReturnFormSubmitted()),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
              ),
              icon: state.isSubmitting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.undo2, size: 18),
              label: Text('purchases.process_return'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// RETURN ITEM TILE
// ═══════════════════════════════════════════════════════
class _ReturnItemTile extends StatelessWidget {
  final PurchaseItemEntity item;
  final ReturnLineItem? returnItem;
  final bool isSelected;
  final CurrencyService currencyService;
  final VoidCallback onToggle;
  final ValueChanged<int> onQuantityChanged;

  const _ReturnItemTile({
    required this.item,
    this.returnItem,
    required this.isSelected,
    required this.currencyService,
    required this.onToggle,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final displayName = item.variantSku != null
        ? '${item.productName ?? 'Product'} (${item.variantSku})'
        : item.productName ?? 'Product #${item.productId}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => onToggle(),
                activeColor: cs.error,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${currencyService.format(item.unitCostCents.toBigInt().toInt())} × ${item.quantity}  •  ${currencyService.format(item.totalCents.toBigInt().toInt())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isSelected && returnItem != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Row(
                children: [
                  Text('purchases.return_quantity'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: returnItem!.returnQuantity > 1
                              ? () => onQuantityChanged(
                                  returnItem!.returnQuantity - 1)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(LucideIcons.minus, size: 14,
                                color: returnItem!.returnQuantity > 1
                                    ? cs.onSurface
                                    : cs.onSurface.withValues(alpha: 0.3)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('${returnItem!.returnQuantity}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.error)),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: returnItem!.returnQuantity < item.quantity
                              ? () => onQuantityChanged(
                                  returnItem!.returnQuantity + 1)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(LucideIcons.plus, size: 14,
                                color: returnItem!.returnQuantity < item.quantity
                                    ? cs.onSurface
                                    : cs.onSurface.withValues(alpha: 0.3)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '/ ${item.quantity}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    currencyService.format(
                        returnItem!.refundCents.toBigInt().toInt()),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold, color: cs.error),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
