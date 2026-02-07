import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/database/app_database.dart' show Supplier;
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';
import '../../../products/presentation/bloc/products_bloc.dart';
import '../../../products/presentation/bloc/product_variants_bloc.dart';
import '../../../suppliers/domain/repositories/supplier_repository.dart';
import '../bloc/purchase_form_bloc.dart';

class PurchaseFormScreen extends StatelessWidget {
  final int? purchaseId;

  const PurchaseFormScreen({super.key, this.purchaseId});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => sl<PurchaseFormBloc>()
          ..add(PurchaseFormInitialized(purchaseId: purchaseId, currencyId: 1))),
        BlocProvider(create: (context) => sl<ProductsBloc>()),
      ],
      child: const _PurchaseFormView(),
    );
  }
}

class _PurchaseFormView extends StatelessWidget {
  const _PurchaseFormView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currencyService = sl<CurrencyService>();

    return BlocConsumer<PurchaseFormBloc, PurchaseFormState>(
      listener: (context, state) {
        if (state.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('purchases.saved_success'.tr()),
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
            title: Text(state.purchaseId == null
                ? 'purchases.new'.tr()
                : 'purchases.edit'.tr()),
            actions: [
              if (state.purchaseId != null)
                TextButton.icon(
                  icon: const Icon(LucideIcons.checkCircle, size: 18),
                  label: Text('purchases.post'.tr()),
                  onPressed: state.isSubmitting
                      ? null
                      : () => context.read<PurchaseFormBloc>().add(const PurchaseFormPosted()),
                ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              if (isWide) {
                return _buildWideLayout(context, state, currencyService);
              }
              return _buildNarrowLayout(context, state, currencyService);
            },
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // WIDE LAYOUT (Desktop/Tablet split-pane)
  // ═══════════════════════════════════════════════════════
  Widget _buildWideLayout(BuildContext context, PurchaseFormState state, CurrencyService cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left pane: Header info
        SizedBox(
          width: 360,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSupplierCard(context, state),
              const SizedBox(height: 12),
              _buildDatesCard(context, state),
              const SizedBox(height: 12),
              _buildRefCard(context, state),
              const SizedBox(height: 12),
              _buildDiscountModeCard(context, state, cs),
              const SizedBox(height: 12),
              _buildNotesCard(context, state),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Right pane: Items + Totals + Save
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildItemsCard(context, state, cs),
                    const SizedBox(height: 16),
                    _buildTotalsCard(context, state, cs),
                    const SizedBox(height: 80),
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

  // ═══════════════════════════════════════════════════════
  // NARROW LAYOUT (Mobile stacked)
  // ═══════════════════════════════════════════════════════
  Widget _buildNarrowLayout(BuildContext context, PurchaseFormState state, CurrencyService cs) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSupplierCard(context, state),
              const SizedBox(height: 12),
              _buildDatesCard(context, state),
              const SizedBox(height: 12),
              _buildRefCard(context, state),
              const SizedBox(height: 12),
              _buildItemsCard(context, state, cs),
              const SizedBox(height: 12),
              _buildDiscountModeCard(context, state, cs),
              const SizedBox(height: 12),
              _buildNotesCard(context, state),
              const SizedBox(height: 12),
              _buildTotalsCard(context, state, cs),
              const SizedBox(height: 80),
            ],
          ),
        ),
        _buildBottomBar(context, state, cs),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // SUPPLIER CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildSupplierCard(BuildContext context, PurchaseFormState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasSupplier = state.supplierName != null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasSupplier ? cs.primary.withValues(alpha: 0.3) : cs.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showSupplierPicker(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: hasSupplier
                      ? cs.primary.withValues(alpha: 0.1)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.building2,
                  color: hasSupplier ? cs.primary : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('purchases.supplier'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 2),
                    Text(
                      hasSupplier ? state.supplierName! : 'purchases.select_supplier'.tr(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: hasSupplier ? FontWeight.w600 : FontWeight.normal,
                        color: hasSupplier ? null : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // DATES CARD (Purchase Date + Due Date)
  // ═══════════════════════════════════════════════════════
  Widget _buildDatesCard(BuildContext context, PurchaseFormState state) {
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
          children: [
            // Purchase Date
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: state.purchaseDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null && context.mounted) {
                  context.read<PurchaseFormBloc>().add(PurchaseDateChanged(date));
                }
              },
              child: Row(
                children: [
                  Icon(LucideIcons.calendar, size: 20, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('purchases.date'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant)),
                        Text(DateFormat.yMMMd().format(state.purchaseDate),
                            style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.edit3, size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ),
            const Divider(height: 24),
            // Due Date
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: state.dueDate ?? state.purchaseDate.add(const Duration(days: 30)),
                  firstDate: state.purchaseDate,
                  lastDate: state.purchaseDate.add(const Duration(days: 365)),
                );
                if (date != null && context.mounted) {
                  context.read<PurchaseFormBloc>().add(PurchaseDueDateChanged(date));
                }
              },
              child: Row(
                children: [
                  Icon(LucideIcons.calendarClock, size: 20,
                      color: state.dueDate != null ? cs.tertiary : cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('purchases.due_date'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant)),
                        Text(
                          state.dueDate != null
                              ? DateFormat.yMMMd().format(state.dueDate!)
                              : 'purchases.set_due_date'.tr(),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: state.dueDate != null ? FontWeight.w500 : FontWeight.normal,
                            color: state.dueDate != null ? null : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.edit3, size: 16, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // SUPPLIER INVOICE REF CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildRefCard(BuildContext context, PurchaseFormState state) {
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
        child: Row(
          children: [
            Icon(LucideIcons.fileText, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'purchases.supplier_ref'.tr(),
                  hintText: 'purchases.supplier_ref_hint'.tr(),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: theme.textTheme.bodyLarge,
                onChanged: (v) => context
                    .read<PurchaseFormBloc>()
                    .add(PurchaseSupplierRefChanged(v)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // DISCOUNT MODE CARD (Toggle per-item vs invoice)
  // ═══════════════════════════════════════════════════════
  Widget _buildDiscountModeCard(BuildContext context, PurchaseFormState state, CurrencyService cs) {
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
                Icon(LucideIcons.percent, size: 20, color: colorScheme.tertiary),
                const SizedBox(width: 8),
                Text('purchases.discount'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            // Toggle
            SegmentedButton<DiscountMode>(
              segments: [
                ButtonSegment(
                  value: DiscountMode.perItem,
                  label: Text('purchases.discount_per_item'.tr()),
                  icon: const Icon(LucideIcons.list, size: 16),
                ),
                ButtonSegment(
                  value: DiscountMode.invoice,
                  label: Text('purchases.discount_on_invoice'.tr()),
                  icon: const Icon(LucideIcons.receipt, size: 16),
                ),
              ],
              selected: {state.discountMode},
              onSelectionChanged: (v) => context
                  .read<PurchaseFormBloc>()
                  .add(PurchaseDiscountModeChanged(v.first)),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (state.discountMode == DiscountMode.invoice) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: state.invoiceDiscountCents > Decimal.zero
                        ? Text(
                            cs.format(state.invoiceDiscountCents.toBigInt().toInt()),
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.tertiary,
                                fontWeight: FontWeight.w600),
                          )
                        : Text('purchases.no_discount'.tr(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant)),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _showInvoiceDiscountDialog(context, state),
                    icon: const Icon(LucideIcons.edit3, size: 16),
                    label: Text('purchases.set_discount'.tr()),
                  ),
                ],
              ),
            ],
            if (state.discountMode == DiscountMode.perItem &&
                state.itemDiscountCents > Decimal.zero) ...[
              const SizedBox(height: 8),
              Text(
                '${'purchases.total_item_discounts'.tr()}: ${cs.format(state.itemDiscountCents.toBigInt().toInt())}',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.tertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // NOTES CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildNotesCard(BuildContext context, PurchaseFormState state) {
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
                Icon(LucideIcons.stickyNote, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('purchases.notes'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'purchases.notes_hint'.tr(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              maxLines: 3,
              onChanged: (v) => context
                  .read<PurchaseFormBloc>()
                  .add(PurchaseNotesChanged(v)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ITEMS CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsCard(BuildContext context, PurchaseFormState state, CurrencyService cs) {
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
                Icon(LucideIcons.shoppingCart, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('purchases.items'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
                if (state.items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${state.items.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showAddItemSheet(context),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: Text('purchases.add_item'.tr()),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    textStyle: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.items.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(LucideIcons.packageOpen, size: 48,
                        color: colorScheme.onSurface.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),
                    Text('purchases.no_items'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('purchases.add_items_hint'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.items.length,
                separatorBuilder: (_, idx) => Divider(
                    height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  return _PurchaseItemTile(
                    item: item,
                    index: index,
                    currencyService: cs,
                    showItemDiscount: state.discountMode == DiscountMode.perItem,
                    onTap: () => _showEditItemDialog(context, item),
                    onRemove: () => context
                        .read<PurchaseFormBloc>()
                        .add(PurchaseLineItemRemoved(item.tempId)),
                    onQuantityChanged: (qty) => context
                        .read<PurchaseFormBloc>()
                        .add(PurchaseLineItemUpdated(
                            tempId: item.tempId, quantity: qty)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TOTALS CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildTotalsCard(BuildContext context, PurchaseFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _summaryRow(theme, 'purchases.subtotal'.tr(),
                cs.format(state.subtotalCents.toBigInt().toInt())),
            if (state.totalDiscountCents > Decimal.zero) ...[
              const SizedBox(height: 6),
              _summaryRow(
                theme,
                'purchases.discount'.tr(),
                '- ${cs.format(state.totalDiscountCents.toBigInt().toInt())}',
                valueColor: colorScheme.tertiary,
              ),
            ],
            const SizedBox(height: 6),
            _summaryRow(theme, 'purchases.tax'.tr(),
                cs.format(state.taxCents.toBigInt().toInt())),
            Divider(height: 24, color: colorScheme.outlineVariant),
            _summaryRow(
              theme,
              'purchases.total'.tr(),
              cs.format(state.totalCents.toBigInt().toInt()),
              isBold: true,
              valueColor: colorScheme.primary,
              labelStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(ThemeData theme, String label, String value,
      {bool isBold = false, Color? valueColor, TextStyle? labelStyle}) {
    final style = labelStyle ?? theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value,
            style: (isBold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
                ?.copyWith(
                    color: valueColor,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // BOTTOM BAR
  // ═══════════════════════════════════════════════════════
  Widget _buildBottomBar(BuildContext context, PurchaseFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${state.totalQuantity} ${'purchases.items_count'.tr()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  cs.format(state.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold, color: colorScheme.primary),
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
              onPressed: state.isSubmitting || state.items.isEmpty
                  ? null
                  : () => context
                      .read<PurchaseFormBloc>()
                      .add(const PurchaseFormSubmitted()),
              icon: state.isSubmitting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.save, size: 18),
              label: Text('purchases.save_draft'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // DIALOGS & SHEETS
  // ═══════════════════════════════════════════════════════

  void _showSupplierPicker(BuildContext context) async {
    final suppliers = await sl<SupplierRepository>().searchSuppliers('');
    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _SupplierPickerSheet(
        suppliers: suppliers,
        onSelected: (supplier) {
          context.read<PurchaseFormBloc>().add(
                PurchaseSupplierChanged(supplier.id, supplierName: supplier.name),
              );
          Navigator.pop(sheetCtx);
        },
      ),
    );
  }

  void _showInvoiceDiscountDialog(BuildContext context, PurchaseFormState state) {
    final subtotalCents = state.subtotalCents;
    final subtotalIntCents = subtotalCents.toBigInt().toInt();
    final initialDiscountCents = state.invoiceDiscountCents.toBigInt().toInt();

    final initialDiscountAmount = initialDiscountCents > 0
        ? (initialDiscountCents / 100).toStringAsFixed(2)
        : '';
    final initialDiscountPercent = (subtotalIntCents > 0 && initialDiscountCents > 0)
        ? ((initialDiscountCents / subtotalIntCents) * 100).toStringAsFixed(2)
        : '';

    final amountController = TextEditingController(text: initialDiscountAmount);
    final percentController = TextEditingController(text: initialDiscountPercent);

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        bool updating = false;

        int clampDiscountCents(int cents) {
          if (cents < 0) return 0;
          if (subtotalIntCents <= 0) return 0;
          return cents > subtotalIntCents ? subtotalIntCents : cents;
        }

        int amountTextToCents(String text) {
          final value = double.tryParse(text) ?? 0;
          return (value * 100).round();
        }

        double percentTextToPercent(String text) {
          return double.tryParse(text) ?? 0;
        }

        void syncFromAmount() {
          if (updating) return;
          updating = true;
          final cents = clampDiscountCents(amountTextToCents(amountController.text));

          if (subtotalIntCents > 0) {
            final pct = (cents / subtotalIntCents) * 100;
            percentController.text = cents == 0 ? '' : pct.toStringAsFixed(2);
          } else {
            percentController.text = '';
          }
          updating = false;
        }

        void syncFromPercent() {
          if (updating) return;
          updating = true;
          final pct = percentTextToPercent(percentController.text);

          if (subtotalIntCents > 0) {
            final raw = (subtotalIntCents * (pct / 100));
            final cents = clampDiscountCents(raw.round());
            amountController.text = cents == 0 ? '' : (cents / 100).toStringAsFixed(2);
          } else {
            amountController.text = '';
          }
          updating = false;
        }

        amountController.addListener(syncFromAmount);
        percentController.addListener(syncFromPercent);

        return AlertDialog(
          title: Row(
            children: [
              const Icon(LucideIcons.percent, size: 20),
              const SizedBox(width: 8),
              Text('purchases.invoice_discount'.tr()),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: percentController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'purchases.discount'.tr(),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(LucideIcons.percent),
                  suffixText: '%',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'purchases.discount_amount'.tr(),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(LucideIcons.coins),
                ),
              ),
              if (subtotalIntCents <= 0) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'purchases.no_items'.tr(),
                    style: Theme.of(dialogCtx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(dialogCtx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                final cents = clampDiscountCents(amountTextToCents(amountController.text));
                context.read<PurchaseFormBloc>().add(
                      PurchaseInvoiceDiscountChanged(Decimal.fromInt(cents)),
                    );
                Navigator.pop(dialogCtx);
              },
              child: Text('common.apply'.tr()),
            ),
          ],
        );
      },
    );
  }

  void _showAddItemSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => BlocProvider.value(
        value: context.read<ProductsBloc>(),
        child: _AddItemSheet(
          onItemAdded: (product, variant, quantity, unitCost) {
            context.read<PurchaseFormBloc>().add(PurchaseLineItemAdded(
                  product: product,
                  variant: variant,
                  quantity: quantity,
                  unitCostCents: unitCost,
                ));
            Navigator.pop(sheetContext);
          },
        ),
      ),
    );
  }

  void _showEditItemDialog(BuildContext context, PurchaseLineItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _EditItemSheet(
        item: item,
        currencyService: sl<CurrencyService>(),
        discountMode: context.read<PurchaseFormBloc>().state.discountMode,
        onSave: (qty, cost, discount, expiry, clearExpiry) {
          context.read<PurchaseFormBloc>().add(PurchaseLineItemUpdated(
                tempId: item.tempId,
                quantity: qty,
                unitCostCents: cost,
                discountCents: discount,
                expiryDate: expiry,
                clearExpiry: clearExpiry,
              ));
          Navigator.pop(sheetCtx);
        },
      ),
    );
  }
}

// ─── Supplier Picker Sheet ───
class _SupplierPickerSheet extends StatefulWidget {
  final List<Supplier> suppliers;
  final ValueChanged<Supplier> onSelected;

  const _SupplierPickerSheet({
    required this.suppliers,
    required this.onSelected,
  });

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = _searchController.text.toLowerCase();
    final filtered = widget.suppliers.where((s) {
      if (query.isEmpty) return true;
      return s.name.toLowerCase().contains(query) ||
          (s.phone?.toLowerCase().contains(query) ?? false);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'suppliers.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('suppliers.empty'.tr(),
                          style: Theme.of(context).textTheme.bodyMedium))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final supplier = filtered[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              supplier.name.isNotEmpty
                                  ? supplier.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                  color: colorScheme.onPrimaryContainer),
                            ),
                          ),
                          title: Text(supplier.name),
                          subtitle: supplier.phone != null
                              ? Text(supplier.phone!)
                              : null,
                          onTap: () => widget.onSelected(supplier),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// PURCHASE ITEM TILE (Enhanced with tap-to-edit)
// ═══════════════════════════════════════════════════════
class _PurchaseItemTile extends StatelessWidget {
  final PurchaseLineItem item;
  final int index;
  final CurrencyService currencyService;
  final bool showItemDiscount;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantityChanged;

  const _PurchaseItemTile({
    required this.item,
    required this.index,
    required this.currencyService,
    required this.showItemDiscount,
    required this.onTap,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Index badge
            Container(
              width: 28, height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${currencyService.format(item.unitCostCents.toBigInt().toInt())} × ${item.quantity}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant),
                  ),
                  if (showItemDiscount && item.discountCents > Decimal.zero)
                    Text(
                      '${'purchases.discount'.tr()}: -${currencyService.format(item.discountCents.toBigInt().toInt())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.tertiary),
                    ),
                  if (item.expiryDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.clock, size: 12, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat.yMMMd().format(item.expiryDate!),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.orange, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Quantity controls
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
                    onTap: item.quantity > 1
                        ? () => onQuantityChanged(item.quantity - 1)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(LucideIcons.minus, size: 14,
                          color: item.quantity > 1 ? cs.onSurface : cs.onSurface.withValues(alpha: 0.3)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${item.quantity}',
                        style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold)),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onQuantityChanged(item.quantity + 1),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(LucideIcons.plus, size: 14, color: cs.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Total + remove
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  currencyService.format(item.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(LucideIcons.trash2, size: 14, color: cs.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// EDIT ITEM SHEET (Story 6.7 - Product Edit Dialog)
// ═══════════════════════════════════════════════════════
class _EditItemSheet extends StatefulWidget {
  final PurchaseLineItem item;
  final CurrencyService currencyService;
  final DiscountMode discountMode;
  final void Function(int qty, Decimal cost, Decimal? discount, DateTime? expiry, bool clearExpiry) onSave;

  const _EditItemSheet({
    required this.item,
    required this.currencyService,
    required this.discountMode,
    required this.onSave,
  });

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _discountCtrl;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.item.quantity}');
    _costCtrl = TextEditingController(
        text: (widget.item.unitCostCents.toBigInt().toInt() / 100).toStringAsFixed(2));
    _discountCtrl = TextEditingController(
        text: widget.item.discountCents > Decimal.zero
            ? (widget.item.discountCents.toBigInt().toInt() / 100).toStringAsFixed(2)
            : '');
    _expiryDate = widget.item.expiryDate;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Row(
              children: [
                Icon(LucideIcons.edit3, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.item.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Quantity + Cost row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'purchases.quantity'.tr(),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(LucideIcons.hash, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                    decoration: InputDecoration(
                      labelText: 'purchases.unit_cost'.tr(),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(LucideIcons.coins, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            // Discount (only if per-item mode)
            if (widget.discountMode == DiscountMode.perItem) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _discountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                decoration: InputDecoration(
                  labelText: 'purchases.item_discount'.tr(),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(LucideIcons.percent, size: 18),
                ),
              ),
            ],
            // Expiry date
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _expiryDate ?? DateTime.now().add(const Duration(days: 180)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (date != null) {
                  setState(() => _expiryDate = date);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outline),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.calendarClock, size: 18,
                        color: _expiryDate != null ? Colors.orange : cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _expiryDate != null
                            ? '${'purchases.expiry'.tr()}: ${DateFormat.yMMMd().format(_expiryDate!)}'
                            : 'purchases.set_expiry'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: _expiryDate != null ? null : cs.onSurfaceVariant),
                      ),
                    ),
                    if (_expiryDate != null)
                      InkWell(
                        onTap: () => setState(() => _expiryDate = null),
                        child: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('common.cancel'.tr()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(LucideIcons.check, size: 18),
                    label: Text('common.save'.tr()),
                    onPressed: () {
                      final qty = int.tryParse(_qtyCtrl.text) ?? 1;
                      final costVal = double.tryParse(_costCtrl.text) ?? 0;
                      final costCents = Decimal.fromInt((costVal * 100).round());
                      Decimal? discountCents;
                      if (widget.discountMode == DiscountMode.perItem) {
                        final discVal = double.tryParse(_discountCtrl.text) ?? 0;
                        discountCents = Decimal.fromInt((discVal * 100).round());
                      }
                      widget.onSave(
                        qty < 1 ? 1 : qty,
                        costCents,
                        discountCents,
                        _expiryDate,
                        _expiryDate == null && widget.item.expiryDate != null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ADD ITEM SHEET (Story 6.6 - Product Selection Dialog)
// ═══════════════════════════════════════════════════════
class _AddItemSheet extends StatefulWidget {
  final void Function(
      Product product, ProductVariant? variant, int quantity, Decimal unitCost)
      onItemAdded;

  const _AddItemSheet({required this.onItemAdded});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  Product? _selectedProduct;
  final int _quantity = 1;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (_selectedProduct != null)
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      onPressed: () => setState(() => _selectedProduct = null),
                    ),
                  Expanded(
                    child: Text(
                      _selectedProduct != null
                          ? _selectedProduct!.name
                          : 'purchases.add_item'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            // Search
            if (_selectedProduct == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'purchases.search_product'.tr(),
                    prefixIcon: const Icon(LucideIcons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('purchases.select_variant'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant)),
              ),
            const Divider(height: 1),
            Expanded(
              child: _selectedProduct == null
                  ? _buildProductList(scrollController)
                  : _buildVariantSelection(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProductList(ScrollController scrollController) {
    final cs = Theme.of(context).colorScheme;
    final currencyService = sl<CurrencyService>();

    return BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
      builder: (context, state) {
        List<Product>? products;
        if (state is RealtimeSuccess<List<Product>>) {
          products = state.data;
        } else if (state is RealtimeLoading<List<Product>>) {
          products = state.previousData;
        }

        if (products == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final query = _searchController.text.toLowerCase();
        final filtered = products.where((p) {
          if (query.isEmpty) return true;
          return p.name.toLowerCase().contains(query) ||
              (p.sku?.toLowerCase().contains(query) ?? false) ||
              (p.barcode?.toLowerCase().contains(query) ?? false);
        }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.searchX, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text('purchases.no_products_found'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant)),
              ],
            ),
          );
        }

        return ListView.separated(
          controller: scrollController,
          itemCount: filtered.length,
          separatorBuilder: (_, idx) => Divider(height: 1, indent: 56,
              color: cs.outlineVariant.withValues(alpha: 0.5)),
          itemBuilder: (context, index) {
            final product = filtered[index];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  product.hasVariants ? LucideIcons.layers : LucideIcons.package,
                  size: 20, color: cs.primary,
                ),
              ),
              title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Row(
                children: [
                  if (product.sku != null) ...[
                    Text('SKU: ${product.sku}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(width: 8),
                  ],
                  if (!product.hasVariants)
                    Text(currencyService.format(product.costCents.toBigInt().toInt()),
                        style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w500)),
                ],
              ),
              trailing: Icon(
                product.hasVariants ? LucideIcons.chevronRight : LucideIcons.plusCircle,
                size: 20, color: cs.primary,
              ),
              onTap: () {
                if (product.hasVariants) {
                  setState(() => _selectedProduct = product);
                } else {
                  widget.onItemAdded(product, null, _quantity, product.costCents);
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildVariantSelection() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currencyService = sl<CurrencyService>();

    return BlocProvider(
      create: (context) => sl<ProductVariantsBloc>()
        ..add(ProductVariantsInitialized(_selectedProduct!.id)),
      child: BlocBuilder<ProductVariantsBloc, RealtimeState<List<ProductVariant>>>(
        builder: (context, state) {
          List<ProductVariant>? variants;
          if (state is RealtimeSuccess<List<ProductVariant>>) {
            variants = state.data;
          } else if (state is RealtimeLoading<List<ProductVariant>>) {
            variants = state.previousData;
          }

          if (variants == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView.separated(
            itemCount: variants.length,
            separatorBuilder: (_, idx) => Divider(height: 1, indent: 56,
                color: cs.outlineVariant.withValues(alpha: 0.5)),
            itemBuilder: (context, index) {
              final variant = variants![index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(LucideIcons.tag, size: 18, color: cs.tertiary),
                ),
                title: Text(variant.sku ?? 'Variant ${variant.id}',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Row(
                  children: [
                    Icon(LucideIcons.warehouse, size: 12, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('${variant.stockQuantity}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(width: 12),
                    Icon(LucideIcons.coins, size: 12, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(currencyService.format(variant.costCents.toBigInt().toInt()),
                        style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w500)),
                  ],
                ),
                trailing: Icon(LucideIcons.plusCircle, size: 20, color: cs.primary),
                onTap: () {
                  widget.onItemAdded(_selectedProduct!, variant, _quantity, variant.costCents);
                },
              );
            },
          );
        },
      ),
    );
  }
}
