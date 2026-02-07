import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/sale_entity.dart';
import '../bloc/sale_return_form_bloc.dart';

class SaleReturnFormScreen extends StatelessWidget {
  final int saleId;

  const SaleReturnFormScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = sl<SaleReturnFormBloc>();
        bloc.add(SaleReturnFormInitialized(saleId));
        return bloc;
      },
      child: const _SaleReturnFormView(),
    );
  }
}

class _SaleReturnFormView extends StatelessWidget {
  const _SaleReturnFormView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return BlocConsumer<SaleReturnFormBloc, SaleReturnFormState>(
      listenWhen: (prev, curr) =>
          prev.isSuccess != curr.isSuccess || prev.error != curr.error,
      listener: (context, state) {
        if (state.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('sales.return_created'.tr())),
          );
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/sales');
          }
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: colorScheme.error,
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
                  context.go('/sales');
                }
              },
            ),
            title: Text('sales.create_return'.tr()),
            actions: [
              if (state.isSubmitting)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                FilledButton.icon(
                  onPressed: state.returnItems.isEmpty
                      ? null
                      : () => context
                          .read<SaleReturnFormBloc>()
                          .add(const SaleReturnFormSubmitted()),
                  icon: const Icon(LucideIcons.check, size: 16),
                  label: Text('common.save'.tr()),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Sale info
                          if (state.sale != null)
                            _buildSaleInfoCard(context, state.sale!, cs),
                          const SizedBox(height: 12),

                          // Disposition type
                          _buildDispositionCard(context, state),
                          const SizedBox(height: 12),

                          // Items to return
                          _buildItemsSelectionCard(context, state, cs),
                          const SizedBox(height: 12),

                          // Reason
                          _buildReasonCard(context, state),
                          const SizedBox(height: 12),

                          // Total refund
                          if (state.returnItems.isNotEmpty)
                            _buildFinancialImpactCard(context, state, cs),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                    _buildBottomBar(context, state, cs),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSaleInfoCard(BuildContext context, SaleEntity sale, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customerInitial = sale.customerName != null && sale.customerName!.isNotEmpty
        ? sale.customerName![0].toUpperCase()
        : '?';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.25)),
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
                      colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.fileText, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('sales.return_from_sale'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
                      Text(sale.invoiceNumber,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 24, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primaryContainer, colorScheme.primaryContainer.withValues(alpha: 0.6)],
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(customerInitial,
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('sales.customer'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant)),
                      Text(sale.customerName ?? 'sales.walk_in'.tr(),
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('sales.date'.tr(), style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant)),
                Text(DateFormat.yMMMd().format(sale.saleDate),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('sales.total'.tr(), style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant)),
                Text(cs.format(sale.totalCents.toBigInt().toInt()),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDispositionCard(BuildContext context, SaleReturnFormState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    const dispositions = [
      ('restock', LucideIcons.package),
      ('exchange', LucideIcons.repeat),
      ('store_credit', LucideIcons.wallet),
      ('refund', LucideIcons.banknote),
      ('write_off', LucideIcons.trash2),
    ];

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
                  child: Icon(LucideIcons.settings2, size: 16, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text('sales.disposition_type'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: dispositions.map((d) {
                final isSelected = state.dispositionType == d.$1;
                return ChoiceChip(
                  avatar: Icon(d.$2, size: 16,
                      color: isSelected ? cs.onPrimary : cs.onSurfaceVariant),
                  label: Text('sales.disposition_${d.$1}'.tr()),
                  selected: isSelected,
                  selectedColor: cs.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? cs.onPrimary : cs.onSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  onSelected: (_) => context
                      .read<SaleReturnFormBloc>()
                      .add(SaleReturnDispositionChanged(d.$1)),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsSelectionCard(
      BuildContext context, SaleReturnFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                      colors: [colorScheme.error, colorScheme.error.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.undo2, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('sales.select_items_to_return'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                if (state.returnItems.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${state.returnItems.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onErrorContainer, fontWeight: FontWeight.bold)),
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(LucideIcons.packageX, size: 36,
                          color: colorScheme.error.withValues(alpha: 0.3)),
                    ),
                    const SizedBox(height: 12),
                    Text('sales.no_items_to_return'.tr(),
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
                separatorBuilder: (context2, idx) => Divider(
                    height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                itemBuilder: (context, index) {
                  final item = state.availableItems[index];
                  final returnItem = state.returnItems
                      .where((r) => r.originalItem.id == item.id)
                      .toList();
                  final isSelected = returnItem.isNotEmpty;
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
                              onChanged: (_) => context
                                  .read<SaleReturnFormBloc>()
                                  .add(SaleReturnItemToggled(item)),
                              activeColor: colorScheme.error,
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
                                    '${cs.format(item.unitPriceCents.toBigInt().toInt())} × ${item.quantity}  •  ${cs.format(item.totalCents.toBigInt().toInt())}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (isSelected && returnItem.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 48),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Text('sales.return_qty'.tr(),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant)),
                                    const SizedBox(width: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: returnItem.first.returnQuantity > 1
                                                ? () => context
                                                    .read<SaleReturnFormBloc>()
                                                    .add(SaleReturnItemQuantityChanged(
                                                        item.id, returnItem.first.returnQuantity - 1))
                                                : null,
                                            child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: Icon(LucideIcons.minus, size: 14,
                                                  color: returnItem.first.returnQuantity > 1
                                                      ? colorScheme.onSurface
                                                      : colorScheme.onSurface.withValues(alpha: 0.3)),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            child: Text('${returnItem.first.returnQuantity}',
                                                style: theme.textTheme.labelLarge?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.error)),
                                          ),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: returnItem.first.returnQuantity < item.quantity
                                                ? () => context
                                                    .read<SaleReturnFormBloc>()
                                                    .add(SaleReturnItemQuantityChanged(
                                                        item.id, returnItem.first.returnQuantity + 1))
                                                : null,
                                            child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: Icon(LucideIcons.plus, size: 14,
                                                  color: returnItem.first.returnQuantity < item.quantity
                                                      ? colorScheme.onSurface
                                                      : colorScheme.onSurface.withValues(alpha: 0.3)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('/ ${item.quantity}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant)),
                                    const Spacer(),
                                    Text(
                                      cs.format(returnItem.first.refundCents.toBigInt().toInt()),
                                      style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold, color: colorScheme.error),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  decoration: InputDecoration(
                                    hintText: 'sales.item_reason_hint'.tr(),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                          color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                  style: theme.textTheme.bodySmall,
                                  onChanged: (v) => context
                                      .read<SaleReturnFormBloc>()
                                      .add(SaleReturnItemReasonChanged(item.id, v)),
                                ),
                              ],
                            ),
                          ),
                        ],
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

  Widget _buildReasonCard(BuildContext context, SaleReturnFormState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(LucideIcons.messageSquare, size: 16, color: Colors.amber.shade700),
                ),
                const SizedBox(width: 10),
                Text('sales.return_reason'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                hintText: 'sales.return_reason_hint'.tr(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                isDense: true,
              ),
              maxLines: 3,
              onChanged: (v) => context
                  .read<SaleReturnFormBloc>()
                  .add(SaleReturnReasonChanged(v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialImpactCard(
      BuildContext context, SaleReturnFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(LucideIcons.alertCircle, size: 16, color: colorScheme.error),
                    ),
                    const SizedBox(width: 10),
                    Text('sales.financial_impact'.tr(),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(LucideIcons.package, size: 14, color: Colors.green),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('sales.items_returned'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant)),
                    ),
                    Text('+${state.totalReturnQuantity} ${'sales.items_count'.tr()}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.green, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(LucideIcons.coins, size: 14, color: colorScheme.error),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('sales.customer_refund'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant)),
                    ),
                    Text(cs.format(state.totalRefundCents.toBigInt().toInt()),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.error, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.error.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border(
                top: BorderSide(color: colorScheme.error.withValues(alpha: 0.15)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('sales.total_refund'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(cs.format(state.totalRefundCents.toBigInt().toInt()),
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold, color: colorScheme.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
      BuildContext context, SaleReturnFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.undo2, size: 12, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '${state.totalReturnQuantity} ${'sales.items_count'.tr()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
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
                      .read<SaleReturnFormBloc>()
                      .add(const SaleReturnFormSubmitted()),
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              icon: state.isSubmitting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.undo2, size: 18),
              label: Text('sales.process_return'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
