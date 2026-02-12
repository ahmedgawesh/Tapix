import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../bloc/purchase_return_form_bloc.dart';
import '../services/purchase_pdf_service.dart';

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

  Future<bool> _onWillPop(BuildContext context) async {
    final state = context.read<PurchaseReturnFormBloc>().state;
    if (!state.hasUnsavedChanges) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('purchases.unsaved_changes_title'.tr()),
        content: Text('purchases.unsaved_changes_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('purchases.discard'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('purchases.stay'.tr()),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _navigateBack(BuildContext context) async {
    final shouldPop = await _onWillPop(context);
    if (shouldPop && context.mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/purchases');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = sl<CurrencyService>();
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<PurchaseReturnFormBloc, PurchaseReturnFormState>(
      listenWhen: (prev, curr) =>
          prev.isSuccess != curr.isSuccess || prev.error != curr.error,
      listener: (context, state) {
        if (state.isSuccess) {
          _showReturnSavedDialog(context);
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
        return PopScope(
          canPop: state.isSuccess || !state.hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            _navigateBack(context);
          },
          child: Scaffold(
            endDrawer: _buildSideDrawer(context, state),
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => _navigateBack(context),
              ),
              title: Text('purchases.create_return'.tr()),
              actions: [
                Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(LucideIcons.menu),
                    tooltip: 'purchases.menu'.tr(),
                    onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                  ),
                ),
              ],
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
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // SIDE DRAWER MENU
  // ═══════════════════════════════════════════════════════
  Widget _buildSideDrawer(BuildContext context, PurchaseReturnFormState state) {
    final theme = Theme.of(context);
    final csColor = theme.colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('purchases.menu'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold)),
            ),
            const Divider(),
            ListTile(
              leading: Icon(LucideIcons.printer, color: csColor.primary),
              title: Text('purchases.reprint_invoice'.tr()),
              onTap: () {
                Navigator.pop(context);
                _showReprintDialog(context);
              },
            ),
            if (state.purchaseId != null)
              ListTile(
                leading: Icon(LucideIcons.fileText, color: csColor.primary),
                title: Text('purchases.details'.tr()),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/purchases/${state.purchaseId}');
                },
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // REPRINT DIALOG
  // ═══════════════════════════════════════════════════════
  void _showReprintDialog(BuildContext context) {
    final controller = TextEditingController(text: '0');

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text('purchases.reprint_invoice_title'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('purchases.enter_invoice_number'.tr(),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(
                  border: UnderlineInputBorder(),
                ),
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                final invoiceNum = controller.text.trim();
                Navigator.pop(ctx);
                if (invoiceNum.isNotEmpty && invoiceNum != '0') {
                  final id = int.tryParse(invoiceNum);
                  if (id != null) {
                    context.push('/purchases/$id');
                  }
                }
              },
              child: Text('purchases.continue_btn'.tr()),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // RETURN SAVED DIALOG
  // ═══════════════════════════════════════════════════════
  void _showReturnSavedDialog(BuildContext context) {
    final theme = Theme.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.checkCircle2, size: 48, color: Colors.green),
              ),
              const SizedBox(height: 16),
              Text(
                'purchases.return_saved'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton.icon(
              icon: const Icon(LucideIcons.printer, size: 18),
              label: Text('purchases.print_invoice'.tr()),
              onPressed: () async {
                Navigator.pop(ctx);
                await _printOrShareReturn(context, share: false);
                if (context.mounted) context.pop();
              },
            ),
            TextButton.icon(
              icon: const Icon(LucideIcons.share2, size: 18),
              label: Text('purchases.share_pdf'.tr()),
              onPressed: () async {
                Navigator.pop(ctx);
                await _printOrShareReturn(context, share: true);
                if (context.mounted) context.pop();
              },
            ),
            FilledButton.icon(
              icon: const Icon(LucideIcons.checkCircle, size: 18),
              label: Text('purchases.finish'.tr()),
              onPressed: () {
                Navigator.pop(ctx);
                context.pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _printOrShareReturn(BuildContext context, {required bool share}) async {
    final state = context.read<PurchaseReturnFormBloc>().state;
    try {
      if (state.purchaseId != null && state.purchase != null) {
        final repo = sl<PurchaseRepository>();
        final returns = await repo.watchPurchaseReturnsByPurchase(state.purchaseId!).first;
        if (returns.isNotEmpty && context.mounted) {
          final latestReturn = returns.first;
          final returnItems = await repo.watchPurchaseReturnItemsWithDetails(latestReturn.id).first;
          if (context.mounted) {
            if (share) {
              await PurchasePdfService.sharePurchaseReturn(
                context: context,
                originalPurchase: state.purchase!,
                returnEntity: latestReturn,
                returnItems: returnItems,
              );
            } else {
              await PurchasePdfService.printPurchaseReturn(
                context: context,
                originalPurchase: state.purchase!,
                returnEntity: latestReturn,
                returnItems: returnItems,
              );
            }
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('purchases.print_error'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
              _buildDispositionCard(context, state),
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
              _buildDispositionCard(context, state),
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
  // PURCHASE INFO CARD (Premium)
  // ═══════════════════════════════════════════════════════
  Widget _buildPurchaseInfoCard(
      BuildContext context, PurchaseReturnFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final purchase = state.purchase;
    final supplierInitial = purchase?.supplierName != null &&
            purchase!.supplierName!.isNotEmpty
        ? purchase.supplierName![0].toUpperCase()
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
            if (purchase?.paymentMethod == 'cheque' && purchase?.dueDate != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.error.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.alertTriangle, size: 18, color: colorScheme.error),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'purchases.cheque_warning_title'.tr(),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'purchases.cheque_warning_message'
                                .tr(args: [DateFormat.yMMMd().format(purchase!.dueDate!)]),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                      Text('purchases.return_from_purchase'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              letterSpacing: 0.5)),
                      Text(purchase?.purchaseNumber ?? '—',
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            if (purchase != null) ...[
              Divider(height: 24, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
              if (purchase.supplierName != null) ...[
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
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              _infoRow(theme, 'purchases.date'.tr(),
                  DateFormat.yMMMd().format(purchase.purchaseDate)),
              const SizedBox(height: 8),
              _infoRow(theme, 'purchases.total'.tr(),
                  cs.format(purchase.totalCents.toBigInt().toInt())),
            ],
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
              child: Icon(label.contains('Date') || label.contains('تاريخ')
                  ? LucideIcons.calendar : LucideIcons.coins,
                  size: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant)),
          ],
        ),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // ITEMS SELECTION CARD (Premium)
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsSelectionCard(
      BuildContext context, PurchaseReturnFormState state, CurrencyService cs) {
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
                Text('purchases.select_items_to_return'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
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

                  final alreadyReturned = state.alreadyReturnedQty[item.id] ?? 0;
                  final maxReturnable = state.maxReturnableQty(item.id, item.quantity);

                  return _ReturnItemTile(
                    item: item,
                    returnItem: isSelected ? returnItem.first : null,
                    isSelected: isSelected,
                    currencyService: cs,
                    maxReturnableQty: maxReturnable,
                    alreadyReturnedQty: alreadyReturned,
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
  // REFUND METHOD CARD (Primary – how money comes back)
  // ═══════════════════════════════════════════════════════
  Widget _buildDispositionCard(BuildContext context, PurchaseReturnFormState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    const refundMethods = [
      ('cash', LucideIcons.banknote),
      ('credit', LucideIcons.wallet),
      ('cheque', LucideIcons.fileCheck),
    ];

    const dispositions = [
      ('restock', LucideIcons.package),
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
            // ── Refund Method ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(LucideIcons.creditCard, size: 16, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text('purchases.refund_method'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            ...refundMethods.map((m) {
              final isSelected = state.refundMethod == m.$1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: isSelected
                      ? cs.primaryContainer.withValues(alpha: 0.5)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => context
                        .read<PurchaseReturnFormBloc>()
                        .add(ReturnRefundMethodChanged(m.$1)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(m.$2, size: 18,
                              color: isSelected ? cs.primary : cs.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('purchases.refund_method_${m.$1}'.tr(),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                                Text('purchases.refund_method_${m.$1}_desc'.tr(),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        color: cs.onSurfaceVariant, fontSize: 10)),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(LucideIcons.checkCircle2, size: 18, color: cs.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            Divider(height: 20, color: cs.outlineVariant.withValues(alpha: 0.4)),
            // ── Disposition (what happens to the goods) ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(LucideIcons.package, size: 16, color: Colors.amber.shade700),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('purchases.disposition_type'.tr(),
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600)),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showDispositionInfoDialog(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.info, size: 14, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: dispositions.map((d) {
                final isSelected = state.dispositionType == d.$1;
                return ChoiceChip(
                  avatar: Icon(d.$2, size: 16,
                      color: isSelected ? cs.onPrimary : cs.onSurfaceVariant),
                  label: Text('purchases.disposition_${d.$1}'.tr()),
                  selected: isSelected,
                  selectedColor: cs.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? cs.onPrimary : cs.onSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  onSelected: (_) => context
                      .read<PurchaseReturnFormBloc>()
                      .add(ReturnDispositionChanged(d.$1)),
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
            Text('purchases.disposition_hint'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  void _showDispositionInfoDialog(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(LucideIcons.info, size: 20, color: cs.primary),
            const SizedBox(width: 10),
            Text('purchases.disposition_type'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dispositionInfoTile(
              context,
              icon: LucideIcons.package,
              title: 'purchases.disposition_restock'.tr(),
              description: 'purchases.disposition_restock_info'.tr(),
              color: Colors.green,
            ),
            const SizedBox(height: 10),
            _dispositionInfoTile(
              context,
              icon: LucideIcons.trash2,
              title: 'purchases.disposition_write_off'.tr(),
              description: 'purchases.disposition_write_off_info'.tr(),
              color: Colors.red,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('purchases.finish'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _dispositionInfoTile(BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(description, style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // REASON CARD (Enhanced)
  // ═══════════════════════════════════════════════════════
  Widget _buildReasonCard(BuildContext context, PurchaseReturnFormState state) {
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
                Text('purchases.return_reason'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                hintText: 'purchases.return_reason_hint'.tr(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
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
  // FINANCIAL IMPACT CARD (Premium)
  // ═══════════════════════════════════════════════════════
  Widget _buildFinancialImpactCard(
      BuildContext context, PurchaseReturnFormState state, CurrencyService cs) {
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
                    Text('purchases.financial_impact'.tr(),
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 14),
                _impactRow(theme, LucideIcons.package,
                    'purchases.inventory_restored'.tr(),
                    '+${state.totalReturnQuantity} ${'purchases.items_count'.tr()}',
                    Colors.green),
                const SizedBox(height: 10),
                _impactRow(theme, LucideIcons.receipt,
                    'purchases.subtotal'.tr(),
                    cs.format(state.totalSubtotalCents.toBigInt().toInt()),
                    colorScheme.onSurfaceVariant),
                if (state.totalDiscountCents > Decimal.zero) ...[
                  const SizedBox(height: 10),
                  _impactRow(theme, LucideIcons.tag,
                      'purchases.discount'.tr(),
                      '- ${cs.format(state.totalDiscountCents.toBigInt().toInt())}',
                      Colors.orange),
                ],
                if (state.totalTaxCents > Decimal.zero) ...[
                  const SizedBox(height: 10),
                  _impactRow(theme, LucideIcons.percent,
                      'purchases.tax'.tr(),
                      '+ ${cs.format(state.totalTaxCents.toBigInt().toInt())}',
                      colorScheme.tertiary),
                ],
                const SizedBox(height: 10),
                _impactRow(theme, LucideIcons.coins,
                    'purchases.supplier_credit'.tr(),
                    cs.format(state.totalRefundCents.toBigInt().toInt()),
                    colorScheme.error),
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
                Text('purchases.return_total'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold)),
                Text(cs.format(state.totalRefundCents.toBigInt().toInt()),
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _impactRow(ThemeData theme, IconData icon, String label, String value,
      Color valueColor) {
    final cs = theme.colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: valueColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant)),
        ),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(
            color: valueColor, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // BOTTOM BAR (Premium)
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
                      '${state.totalReturnQuantity} ${'purchases.items_count'.tr()}',
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
              onPressed: state.isSubmitting || state.isSuccess || state.returnItems.isEmpty
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
class _ReturnItemTile extends StatefulWidget {
  final PurchaseItemEntity item;
  final ReturnLineItem? returnItem;
  final bool isSelected;
  final CurrencyService currencyService;
  final VoidCallback onToggle;
  final ValueChanged<int> onQuantityChanged;
  final int maxReturnableQty;
  final int alreadyReturnedQty;

  const _ReturnItemTile({
    required this.item,
    this.returnItem,
    required this.isSelected,
    required this.currencyService,
    required this.onToggle,
    required this.onQuantityChanged,
    required this.maxReturnableQty,
    this.alreadyReturnedQty = 0,
  });

  @override
  State<_ReturnItemTile> createState() => _ReturnItemTileState();
}

class _ReturnItemTileState extends State<_ReturnItemTile> {
  late TextEditingController _qtyCtrl;
  bool _isEditing = false;
  final FocusNode _qtyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(
        text: '${widget.returnItem?.returnQuantity ?? 1}');
    _qtyFocus.addListener(() {
      if (_qtyFocus.hasFocus) {
        _isEditing = true;
        _qtyCtrl.selection = TextSelection(
            baseOffset: 0, extentOffset: _qtyCtrl.text.length);
      } else {
        _isEditing = false;
        _applyQty(_qtyCtrl.text);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ReturnItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing) {
      final newQty = widget.returnItem?.returnQuantity ?? 1;
      if (_qtyCtrl.text != '$newQty') {
        _qtyCtrl.text = '$newQty';
      }
    }
  }

  @override
  void dispose() {
    _qtyFocus.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _applyQty(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1) {
      widget.onQuantityChanged(1);
    } else if (parsed > widget.maxReturnableQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('purchases.max_return_qty_exceeded'.tr(
              args: ['${widget.maxReturnableQty}'])),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onQuantityChanged(widget.maxReturnableQty);
    } else {
      widget.onQuantityChanged(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final displayName = widget.item.variantSku != null
        ? '${widget.item.productName ?? 'Product'} (${widget.item.variantSku})'
        : widget.item.productName ?? 'Product #${widget.item.productId}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: widget.isSelected,
                onChanged: (_) => widget.onToggle(),
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
                      '${widget.currencyService.format(widget.item.unitCostCents.toBigInt().toInt())} × ${widget.item.quantity}  •  ${widget.currencyService.format(widget.item.totalCents.toBigInt().toInt())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant),
                    ),
                    if (widget.alreadyReturnedQty > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${'purchases.already_returned'.tr()}: ${widget.alreadyReturnedQty} / ${widget.item.quantity}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.isSelected && widget.returnItem != null) ...[
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
                          onTap: widget.returnItem!.returnQuantity > 1
                              ? () => widget.onQuantityChanged(
                                  widget.returnItem!.returnQuantity - 1)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(LucideIcons.minus, size: 14,
                                color: widget.returnItem!.returnQuantity > 1
                                    ? cs.onSurface
                                    : cs.onSurface.withValues(alpha: 0.3)),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: TextField(
                            controller: _qtyCtrl,
                            focusNode: _qtyFocus,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.error),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                            ),
                            onSubmitted: (v) {
                              _applyQty(v);
                              _qtyFocus.unfocus();
                            },
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: widget.returnItem!.returnQuantity < widget.maxReturnableQty
                              ? () => widget.onQuantityChanged(
                                  widget.returnItem!.returnQuantity + 1)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(LucideIcons.plus, size: 14,
                                color: widget.returnItem!.returnQuantity < widget.maxReturnableQty
                                    ? cs.onSurface
                                    : cs.onSurface.withValues(alpha: 0.3)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '/ ${widget.maxReturnableQty}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    widget.currencyService.format(
                        widget.returnItem!.refundCents.toBigInt().toInt()),
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
