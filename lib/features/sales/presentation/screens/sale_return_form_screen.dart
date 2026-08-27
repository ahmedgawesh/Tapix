import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../../../core/widgets/pin_verification_dialog.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';
import '../bloc/sale_return_form_bloc.dart';
import '../services/sale_pdf_service.dart';

class SaleReturnFormScreen extends StatelessWidget {
  final int saleId;

  const SaleReturnFormScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<SaleReturnFormBloc>()..add(SaleReturnFormInitialized(saleId)),
      child: const _SaleReturnFormView(),
    );
  }
}

class _SaleReturnFormView extends StatelessWidget {
  const _SaleReturnFormView();

  Future<bool> _onWillPop(BuildContext context) async {
    final state = context.read<SaleReturnFormBloc>().state;
    if (!state.hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('sales.unsaved_changes_title'.tr()),
        content: Text('sales.unsaved_changes_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('sales.discard'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('sales.stay'.tr()),
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
        context.go('/sales');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = sl<CurrencyService>();
    final colorScheme = Theme.of(context).colorScheme;

    return BlocConsumer<SaleReturnFormBloc, SaleReturnFormState>(
      listenWhen: (prev, curr) =>
          prev.isSuccess != curr.isSuccess || prev.error != curr.error,
      listener: (context, state) {
        if (state.isSuccess) {
          // Capture bloc state before navigating away
          final stateSnapshot = context.read<SaleReturnFormBloc>().state;
          // Navigate back immediately to prevent duplicate submissions
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/sales');
          }
          // Show print/share dialog after navigation completes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final nav = Navigator.of(context, rootNavigator: true);
            if (nav.context.mounted) {
              _showReturnSavedOverlay(nav.context, stateSnapshot);
            }
          });
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
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => _navigateBack(context),
              ),
              title: Text('sales.create_return'.tr()),
            ),
            body: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 900;
                      if (isWide) return _buildWideLayout(context, state, cs);
                      return _buildNarrowLayout(context, state, cs);
                    },
                  ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // RETURN SAVED OVERLAY (Print / Share / Finish)
  // Shown AFTER navigating back to the sales list.
  // ═══════════════════════════════════════════════════════
  bool get _isRemoteClient =>
      sl<LanNetworkService>().snapshot.mode == LanMode.client;

  void _showReturnSavedOverlay(
    BuildContext context,
    SaleReturnFormState returnState,
  ) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: true,
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
                child: const Icon(
                  LucideIcons.checkCircle2,
                  size: 48,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'sales.return_saved'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            if (!_isRemoteClient)
              TextButton.icon(
                icon: const Icon(LucideIcons.printer, size: 18),
                label: Text('sales.print_invoice'.tr()),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _printOrShareReturnFromState(
                    context,
                    returnState,
                    share: false,
                  );
                },
              ),
            if (!_isRemoteClient)
              TextButton.icon(
                icon: const Icon(LucideIcons.share2, size: 18),
                label: Text('sales.share_invoice'.tr()),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _printOrShareReturnFromState(
                    context,
                    returnState,
                    share: true,
                  );
                },
              ),
            FilledButton.icon(
              icon: const Icon(LucideIcons.checkCircle, size: 18),
              label: Text('sales.finish'.tr()),
              onPressed: () {
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _printOrShareReturnFromState(
    BuildContext context,
    SaleReturnFormState state, {
    required bool share,
  }) async {
    try {
      if (state.saleId != null && state.sale != null) {
        final repo = sl<SaleRepository>();
        final returns = await repo.watchAllSaleReturns().first;
        final saleReturns = returns
            .where((r) => r.saleId == state.saleId)
            .toList();
        if (saleReturns.isNotEmpty && context.mounted) {
          final latestReturn = saleReturns.first;
          final returnItems = state.returnItems
              .map(
                (ri) => SaleReturnItemEntity(
                  id: 0,
                  returnId: 0,
                  saleItemId: ri.originalItem.id,
                  quantity: ri.returnQuantity,
                  quantityScale: ri.originalItem.quantityScale,
                  measurementType: ri.originalItem.measurementType,
                  subtotalCents: ri.subtotalCents,
                  discountCents: ri.discountCents,
                  taxCents: ri.taxCents,
                  refundCents: ri.refundCents,
                  reason: ri.reason,
                  productName: ri.originalItem.productName,
                  variantSku: ri.originalItem.variantSku,
                  variantBarcode: null,
                  colorName: ri.originalItem.colorName,
                  colorHex: ri.originalItem.colorHex,
                  sizeName: ri.originalItem.sizeName,
                  createdAt: DateTime.now(),
                ),
              )
              .toList();
          if (context.mounted) {
            if (share) {
              await SalePdfService.shareSaleReturn(
                context: context,
                originalSale: state.sale!,
                returnEntity: latestReturn,
                returnItems: returnItems,
              );
            } else {
              await SalePdfService.printSaleReturn(
                context: context,
                originalSale: state.sale!,
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
            content: Text('sales.print_error'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // LAYOUTS
  // ═══════════════════════════════════════════════════════
  Widget _buildWideLayout(
    BuildContext context,
    SaleReturnFormState state,
    CurrencyService cs,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 360,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSaleInfoCard(context, state, cs),
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
                  children: [_buildItemsSelectionCard(context, state, cs)],
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
    BuildContext context,
    SaleReturnFormState state,
    CurrencyService cs,
  ) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSaleInfoCard(context, state, cs),
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

  Widget _buildSaleInfoCard(
    BuildContext context,
    SaleReturnFormState state,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sale = state.sale;
    if (sale == null) return const SizedBox.shrink();
    final customerInitial =
        sale.customerName != null && sale.customerName!.isNotEmpty
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
            if (sale.paymentMethod == 'cheque' && sale.dueDate != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      size: 18,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'sales.cheque_warning_title'.tr(),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'sales.cheque_warning_message'.tr(
                              args: [DateFormat.yMMMd().format(sale.dueDate!)],
                            ),
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
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.fileText,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'sales.return_from_sale'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        sale.invoiceNumber,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(
              height: 24,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primaryContainer,
                        colorScheme.primaryContainer.withValues(alpha: 0.6),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    customerInitial,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'sales.customer'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        sale.customerName ?? 'sales.walk_in'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'sales.date'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  DateFormat.yMMMd().format(sale.saleDate),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'sales.total'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  cs.format(sale.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDispositionCard(
    BuildContext context,
    SaleReturnFormState state,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    const refundMethods = [
      ('cash', LucideIcons.banknote),
      ('card', LucideIcons.creditCard),
      ('credit', LucideIcons.wallet),
      ('cheque', LucideIcons.fileCheck),
    ];

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
            // ── Refund Method ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    LucideIcons.creditCard,
                    size: 16,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'sales.refund_method'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                    onTap: () => context.read<SaleReturnFormBloc>().add(
                      SaleReturnRefundMethodChanged(m.$1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            m.$2,
                            size: 18,
                            color: isSelected
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'sales.refund_method_${m.$1}'.tr(),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                Text(
                                  'sales.refund_method_${m.$1}_desc'.tr(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              LucideIcons.checkCircle2,
                              size: 18,
                              color: cs.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            // ── Phase 14.0 — cheque due date (only shown for cheque) ──
            if (state.refundMethod == 'cheque') ...[
              const SizedBox(height: 6),
              _buildChequeDueDatePicker(context, state, theme, cs),
            ],
            Divider(
              height: 20,
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
            // ── Disposition Type ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    LucideIcons.package,
                    size: 16,
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'sales.disposition_type'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showDispositionInfoDialog(context),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      LucideIcons.info,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: dispositions.map((d) {
                final isSelected = state.dispositionType == d.$1;
                return ChoiceChip(
                  avatar: Icon(
                    d.$2,
                    size: 16,
                    color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                  label: Text('sales.disposition_${d.$1}'.tr()),
                  selected: isSelected,
                  selectedColor: cs.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? cs.onPrimary : cs.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  onSelected: (_) => context.read<SaleReturnFormBloc>().add(
                    SaleReturnDispositionChanged(d.$1),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showDispositionInfoDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.info, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('sales.disposition_type'.tr()),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dispositionInfoItem(
                theme,
                LucideIcons.package,
                'sales.disposition_restock'.tr(),
                'sales.disposition_restock_desc'.tr(),
              ),
              const SizedBox(height: 12),
              _dispositionInfoItem(
                theme,
                LucideIcons.repeat,
                'sales.disposition_exchange'.tr(),
                'sales.disposition_exchange_desc'.tr(),
              ),
              const SizedBox(height: 12),
              _dispositionInfoItem(
                theme,
                LucideIcons.wallet,
                'sales.disposition_store_credit'.tr(),
                'sales.disposition_store_credit_desc'.tr(),
              ),
              const SizedBox(height: 12),
              _dispositionInfoItem(
                theme,
                LucideIcons.banknote,
                'sales.disposition_refund'.tr(),
                'sales.disposition_refund_desc'.tr(),
              ),
              const SizedBox(height: 12),
              _dispositionInfoItem(
                theme,
                LucideIcons.trash2,
                'sales.disposition_write_off'.tr(),
                'sales.disposition_write_off_desc'.tr(),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }

  /// Phase 14.0 — cheque due-date picker shown when refund method is cheque.
  /// Required-to-submit; an error border highlights the field until set.
  Widget _buildChequeDueDatePicker(
    BuildContext context,
    SaleReturnFormState state,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final missing = state.dueDate == null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate:
              state.dueDate ?? DateTime.now().add(const Duration(days: 30)),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null && context.mounted) {
          context.read<SaleReturnFormBloc>().add(
            SaleReturnDueDateChanged(picked),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: missing
              ? cs.errorContainer.withValues(alpha: 0.18)
              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: missing
                ? cs.error.withValues(alpha: 0.5)
                : cs.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.calendar,
              size: 18,
              color: missing ? cs.error : cs.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'sales.cheque_due_date'.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: missing ? cs.error : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.dueDate != null
                        ? '${state.dueDate!.year}-'
                              '${state.dueDate!.month.toString().padLeft(2, '0')}-'
                              '${state.dueDate!.day.toString().padLeft(2, '0')}'
                        : 'sales.select_due_date'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: state.dueDate != null ? null : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _dispositionInfoItem(
    ThemeData theme,
    IconData icon,
    String title,
    String desc,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemsSelectionCard(
    BuildContext context,
    SaleReturnFormState state,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
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
                        colorScheme.error.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    LucideIcons.undo2,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'sales.select_items_to_return'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (state.returnItems.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${state.returnItems.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                        color: colorScheme.errorContainer.withValues(
                          alpha: 0.15,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.packageX,
                        size: 36,
                        color: colorScheme.error.withValues(alpha: 0.3),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'sales.no_items_to_return'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
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
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final item = state.availableItems[index];
                  final returnItem = state.returnItems
                      .where((r) => r.originalItem.id == item.id)
                      .toList();
                  final isSelected = returnItem.isNotEmpty;
                  final alreadyReturned =
                      state.alreadyReturnedQty[item.id] ?? 0;
                  final maxReturnable = state.maxReturnableQty(
                    item.id,
                    item.quantity,
                  );

                  return _ReturnItemTile(
                    item: item,
                    returnItem: isSelected ? returnItem.first : null,
                    isSelected: isSelected,
                    currencyService: cs,
                    maxReturnableQty: maxReturnable,
                    alreadyReturnedQty: alreadyReturned,
                    onToggle: maxReturnable > 0
                        ? () => context.read<SaleReturnFormBloc>().add(
                            SaleReturnItemToggled(item),
                          )
                        : null,
                    onQuantityChanged: (qty) => context
                        .read<SaleReturnFormBloc>()
                        .add(SaleReturnItemQuantityChanged(item.id, qty)),
                    onReasonChanged: (reason) => context
                        .read<SaleReturnFormBloc>()
                        .add(SaleReturnItemReasonChanged(item.id, reason)),
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
                  child: Icon(
                    LucideIcons.messageSquare,
                    size: 16,
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'sales.return_reason'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                hintText: 'sales.return_reason_hint'.tr(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                isDense: true,
              ),
              maxLines: 3,
              onChanged: (v) => context.read<SaleReturnFormBloc>().add(
                SaleReturnReasonChanged(v),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialImpactCard(
    BuildContext context,
    SaleReturnFormState state,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final returnedQuantity = localizedQuantityTotals(
      aggregateQuantityTotals(
        state.returnItems,
        quantityOf: (item) => item.returnQuantity,
        measurementTypeOf: (item) => item.originalItem.measurementType,
      ),
    );

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
                      child: Icon(
                        LucideIcons.alertCircle,
                        size: 16,
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'sales.financial_impact'.tr(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _impactRow(
                  theme,
                  LucideIcons.package,
                  'sales.items_returned'.tr(),
                  '+$returnedQuantity',
                  Colors.green,
                ),
                const SizedBox(height: 10),
                _impactRow(
                  theme,
                  LucideIcons.receipt,
                  'sales.subtotal'.tr(),
                  cs.format(state.totalSubtotalCents.toBigInt().toInt()),
                  colorScheme.onSurfaceVariant,
                ),
                if (state.totalDiscountCents > Decimal.zero) ...[
                  const SizedBox(height: 10),
                  _impactRow(
                    theme,
                    LucideIcons.tag,
                    'sales.discount'.tr(),
                    '- ${cs.format(state.totalDiscountCents.toBigInt().toInt())}',
                    Colors.orange,
                  ),
                ],
                if (state.totalTaxCents > Decimal.zero) ...[
                  const SizedBox(height: 10),
                  _impactRow(
                    theme,
                    LucideIcons.percent,
                    'sales.tax'.tr(),
                    '+ ${cs.format(state.totalTaxCents.toBigInt().toInt())}',
                    colorScheme.tertiary,
                  ),
                ],
                const SizedBox(height: 10),
                _impactRow(
                  theme,
                  LucideIcons.coins,
                  'sales.customer_refund'.tr(),
                  cs.format(state.totalRefundCents.toBigInt().toInt()),
                  colorScheme.error,
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
                top: BorderSide(
                  color: colorScheme.error.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'sales.total_refund'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  cs.format(state.totalRefundCents.toBigInt().toInt()),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _impactRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
    Color valueColor,
  ) {
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
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    SaleReturnFormState state,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final returnedQuantity = localizedQuantityTotals(
      aggregateQuantityTotals(
        state.returnItems,
        quantityOf: (item) => item.returnQuantity,
        measurementTypeOf: (item) => item.originalItem.measurementType,
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
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
                    Icon(
                      LucideIcons.undo2,
                      size: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      returnedQuantity,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  cs.format(state.totalRefundCents.toBigInt().toInt()),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: state.isSubmitting
                  ? null
                  : () => _navigateBack(context),
              child: Text('common.cancel'.tr()),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed:
                  state.isSubmitting ||
                      state.isSuccess ||
                      state.returnItems.isEmpty ||
                      state.isChequeMissingDueDate
                  ? null
                  : () async {
                      final requirePin = context
                          .read<AppSettingsBloc>()
                          .state
                          .settings
                          .requirePinForVoidRefund;
                      if (requirePin) {
                        final pinOk = await showPinVerificationDialog(context);
                        if (!pinOk || !context.mounted) return;
                      }
                      context.read<SaleReturnFormBloc>().add(
                        const SaleReturnFormSubmitted(),
                      );
                    },
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              icon: state.isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.undo2, size: 18),
              label: Text('sales.process_return'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// RETURN ITEM TILE (extracted widget)
// ═══════════════════════════════════════════════════════
class _ReturnItemTile extends StatefulWidget {
  final SaleItemEntity item;
  final SaleReturnLineItem? returnItem;
  final bool isSelected;
  final CurrencyService currencyService;
  final int maxReturnableQty;
  final int alreadyReturnedQty;
  final VoidCallback? onToggle;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<String> onReasonChanged;

  const _ReturnItemTile({
    required this.item,
    this.returnItem,
    required this.isSelected,
    required this.currencyService,
    required this.maxReturnableQty,
    required this.alreadyReturnedQty,
    this.onToggle,
    required this.onQuantityChanged,
    required this.onReasonChanged,
  });

  @override
  State<_ReturnItemTile> createState() => _ReturnItemTileState();
}

class _ReturnItemTileState extends State<_ReturnItemTile> {
  late TextEditingController _qtyCtrl;
  late MeasurementUnit _quantityUnit;
  bool _isEditing = false;
  final FocusNode _qtyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _quantityUnit = MeasurementType.fromDb(
      widget.item.measurementType,
    ).majorUnit;
    _qtyCtrl = TextEditingController(
      text: MeasuredQuantity.editableValue(
        widget.returnItem?.returnQuantity ?? widget.item.quantityScale,
        _quantityUnit,
      ),
    );
    _qtyFocus.addListener(() {
      if (_qtyFocus.hasFocus) {
        _isEditing = true;
        _qtyCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _qtyCtrl.text.length,
        );
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
      final newQty =
          widget.returnItem?.returnQuantity ?? widget.item.quantityScale;
      final newText = MeasuredQuantity.editableValue(newQty, _quantityUnit);
      if (_qtyCtrl.text != newText) {
        _qtyCtrl.text = newText;
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
    int parsed;
    try {
      parsed = MeasuredQuantity.parseToStored(value, _quantityUnit);
    } on FormatException {
      // Don't update if empty or invalid - wait for valid input
      if (value.isEmpty) return;
      return;
    }
    if (parsed < 1) return;
    if (parsed > widget.maxReturnableQty) {
      // Show error immediately when quantity exceeds max
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'sales.max_return_qty_exceeded'.tr(
              args: [
                localizedQuantity(
                  widget.maxReturnableQty,
                  widget.item.measurementType,
                ),
              ],
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      // Reset the text field to max allowed and update state
      _qtyCtrl.text = MeasuredQuantity.editableValue(
        widget.maxReturnableQty,
        _quantityUnit,
      );
      _qtyCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _qtyCtrl.text.length),
      );
      widget.onQuantityChanged(widget.maxReturnableQty);
      return;
    }
    widget.onQuantityChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = widget.currencyService;

    final displayName = widget.item.variantSku != null
        ? '${widget.item.productName ?? 'Product'} (${widget.item.variantSku})'
        : widget.item.productName ?? 'Product #${widget.item.productId}';
    final fullyReturned = widget.maxReturnableQty <= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                value: widget.isSelected,
                onChanged: fullyReturned
                    ? null
                    : (_) => widget.onToggle?.call(),
                activeColor: colorScheme.error,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: fullyReturned
                            ? colorScheme.onSurface.withValues(alpha: 0.5)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cs.format(widget.item.unitPriceCents.toBigInt().toInt())} × ${localizedQuantity(widget.item.quantity, widget.item.measurementType)}  •  ${cs.format(widget.item.totalCents.toBigInt().toInt())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (widget.alreadyReturnedQty > 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'sales.already_returned'.tr(
                            args: [
                              localizedQuantity(
                                widget.alreadyReturnedQty,
                                widget.item.measurementType,
                              ),
                            ],
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    if (fullyReturned) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'sales.fully_returned'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (widget.isSelected && widget.returnItem != null) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;

                Widget quantityEditor() => Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap:
                            widget.returnItem!.returnQuantity >
                                _quantityUnit.internalFactor
                            ? () => widget.onQuantityChanged(
                                widget.returnItem!.returnQuantity -
                                    _quantityUnit.internalFactor,
                              )
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            LucideIcons.minus,
                            size: 14,
                            color:
                                widget.returnItem!.returnQuantity >
                                    _quantityUnit.internalFactor
                                ? colorScheme.onSurface
                                : colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: _qtyCtrl,
                          focusNode: _qtyFocus,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d.,]'),
                            ),
                          ],
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.error,
                          ),
                          onTap: () => selectAllText(_qtyCtrl),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                          ),
                          onChanged: _applyQty,
                          onSubmitted: (value) {
                            _applyQty(value);
                            _qtyFocus.unfocus();
                          },
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap:
                            widget.returnItem!.returnQuantity +
                                    _quantityUnit.internalFactor <=
                                widget.maxReturnableQty
                            ? () => widget.onQuantityChanged(
                                widget.returnItem!.returnQuantity +
                                    _quantityUnit.internalFactor,
                              )
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            LucideIcons.plus,
                            size: 14,
                            color:
                                widget.returnItem!.returnQuantity +
                                        _quantityUnit.internalFactor <=
                                    widget.maxReturnableQty
                                ? colorScheme.onSurface
                                : colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                Widget quantityInputs() => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    quantityEditor(),
                    const SizedBox(width: 8),
                    if (MeasurementType.fromDb(
                          widget.item.measurementType,
                        ).minorUnit !=
                        null) ...[
                      DropdownButton<MeasurementUnit>(
                        value: _quantityUnit,
                        isDense: true,
                        items:
                            MeasurementType.fromDb(
                              widget.item.measurementType,
                            ).inputUnits.map((unit) {
                              return DropdownMenuItem(
                                value: unit,
                                child: Text(
                                  'measurement.units.${unit.dbValue}'.tr(),
                                  style: theme.textTheme.bodySmall,
                                ),
                              );
                            }).toList(),
                        onChanged: (unit) {
                          if (unit == null) return;
                          final stored = widget.returnItem!.returnQuantity;
                          setState(() {
                            _quantityUnit = unit;
                            _qtyCtrl.text = MeasuredQuantity.editableValue(
                              stored,
                              unit,
                            );
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '/ ${localizedQuantity(widget.maxReturnableQty, widget.item.measurementType)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );

                final quantityLabel = Text(
                  'sales.return_qty'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
                final refundLabel = Text(
                  cs.format(widget.returnItem!.refundCents.toBigInt().toInt()),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
                  ),
                );

                return Padding(
                  padding: EdgeInsetsDirectional.only(start: compact ? 0 : 48),
                  child: Column(
                    children: [
                      if (compact) ...[
                        Row(
                          children: [
                            quantityLabel,
                            const Spacer(),
                            refundLabel,
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: quantityInputs(),
                          ),
                        ),
                      ] else
                        Row(
                          children: [
                            quantityLabel,
                            const SizedBox(width: 8),
                            quantityInputs(),
                            const Spacer(),
                            refundLabel,
                          ],
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'sales.item_reason_hint'.tr(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        style: theme.textTheme.bodySmall,
                        onChanged: widget.onReasonChanged,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
