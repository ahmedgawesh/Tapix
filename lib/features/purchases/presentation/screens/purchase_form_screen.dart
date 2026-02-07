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
import '../../../products/domain/repositories/product_color_repository.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../../products/domain/repositories/size_repository.dart';
import '../../../products/domain/repositories/product_variant_repository.dart';
import '../../../products/domain/entities/category_entity.dart';
import '../../../products/presentation/bloc/categories_bloc.dart';
import '../../../products/presentation/bloc/categories_event.dart';
import '../../../products/presentation/bloc/products_bloc.dart';
import '../../../products/presentation/bloc/product_variants_bloc.dart';
import '../../../products/presentation/bloc/variant_previews_bloc.dart';
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

  Future<bool> _onWillPop(BuildContext context) async {
    final state = context.read<PurchaseFormBloc>().state;
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
    final colorScheme = Theme.of(context).colorScheme;
    final currencyService = sl<CurrencyService>();

    return BlocConsumer<PurchaseFormBloc, PurchaseFormState>(
      listener: (context, state) {
        if (state.isSuccess) {
          _showSaveConfirmationDialog(context, state);
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
          canPop: !state.hasUnsavedChanges,
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
              title: Text(state.purchaseId == null
                  ? 'purchases.title'.tr()
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
                Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(LucideIcons.menu),
                    tooltip: 'purchases.menu'.tr(),
                    onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                  ),
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
              _buildInvoiceHeaderCard(context, state),
              const SizedBox(height: 12),
              _buildSearchBarWithScan(context),
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
              _buildInvoiceHeaderCard(context, state),
              const SizedBox(height: 12),
              _buildSearchBarWithScan(context),
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
  // INVOICE HEADER CARD (Invoice # + Date)
  // ═══════════════════════════════════════════════════════
  Widget _buildInvoiceHeaderCard(BuildContext context, PurchaseFormState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Invoice Number
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('purchases.invoice_number'.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    state.purchaseNumber ?? '—',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: cs.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Invoice Date
          Expanded(
            child: InkWell(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('purchases.invoice_date'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.calendar, size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            DateFormat.yMd().format(state.purchaseDate),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // SEARCH BAR WITH BARCODE SCAN BUTTON
  // ═══════════════════════════════════════════════════════
  Widget _buildSearchBarWithScan(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAddItemSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.search, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'purchases.search_or_scan'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openBarcodeScanner(context),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Icon(LucideIcons.scanLine, size: 22, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // SIDE DRAWER MENU
  // ═══════════════════════════════════════════════════════
  Widget _buildSideDrawer(BuildContext context, PurchaseFormState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
              leading: Icon(LucideIcons.plusCircle, color: cs.primary),
              title: Text('purchases.add_new_product'.tr()),
              onTap: () {
                Navigator.pop(context);
                context.push('/products/add');
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.printer, color: cs.primary),
              title: Text('purchases.reprint_invoice'.tr()),
              onTap: () {
                Navigator.pop(context);
                _showReprintInvoiceDialog(context);
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.fileEdit, color: cs.primary),
              title: Text('purchases.edit_purchase'.tr()),
              enabled: state.purchaseId != null,
              onTap: state.purchaseId != null ? () {
                Navigator.pop(context);
                context.push('/purchases/${state.purchaseId}/edit');
              } : null,
            ),
            ListTile(
              leading: Icon(LucideIcons.fileInput, color: cs.primary),
              title: Text('purchases.import_from_po'.tr()),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement import from PO
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.fileOutput, color: cs.primary),
              title: Text('purchases.import_from_dispatch'.tr()),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement import from dispatch
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // REPRINT INVOICE DIALOG
  // ═══════════════════════════════════════════════════════
  void _showReprintInvoiceDialog(BuildContext context) {
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
                  // Navigate to purchase detail for reprinting
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
  // SAVE CONFIRMATION DIALOG (Print / Barcode / Finish)
  // ═══════════════════════════════════════════════════════
  void _showSaveConfirmationDialog(BuildContext context, PurchaseFormState state) {
    final theme = Theme.of(context);
    final invoiceNumber = state.purchaseNumber ?? '${state.purchaseId ?? ''}';

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
                'purchases.invoice_saved_message'.tr(args: [invoiceNumber]),
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
              onPressed: () {
                Navigator.pop(ctx);
                // TODO: Implement print functionality
                context.pop();
              },
            ),
            TextButton.icon(
              icon: const Icon(LucideIcons.scan, size: 18),
              label: Text('purchases.generate_barcode'.tr()),
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/barcode');
                // Navigate back after barcode
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

  // ═══════════════════════════════════════════════════════
  // BARCODE SCANNER
  // ═══════════════════════════════════════════════════════
  void _openBarcodeScanner(BuildContext context) async {
    final result = await context.push<String>('/barcode-scanner', extra: {'returnOnScan': true});
    if (result != null && result.isNotEmpty && context.mounted) {
      final productRepo = sl<ProductRepository>();
      final variantRepo = sl<ProductVariantRepository>();

      try {
        // Try to find variant by barcode first
        final variant = await variantRepo.getVariantByBarcode(result);
        if (variant != null && context.mounted) {
          final product = await productRepo.watchProduct(variant.productId).first;
          if (product != null && context.mounted) {
            context.read<PurchaseFormBloc>().add(PurchaseLineItemAdded(
                  product: product,
                  variant: variant,
                  quantity: 1,
                  unitCostCents: variant.costCents,
                ));
            return;
          }
        }

        // Try product barcode
        final product = await productRepo.findByBarcode(result);
        if (product != null && context.mounted) {
          context.read<PurchaseFormBloc>().add(PurchaseLineItemAdded(
                product: product,
                quantity: 1,
                unitCostCents: product.costCents,
              ));
          return;
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('purchases.no_products_found'.tr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('purchases.no_products_found'.tr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // DATES CARD (Premium)
  // ═══════════════════════════════════════════════════════
  Widget _buildDatesCard(BuildContext context, PurchaseFormState state) {
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(LucideIcons.calendar, size: 16, color: Colors.white),
                  ),
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
                  Icon(LucideIcons.edit3, size: 14, color: cs.onSurfaceVariant),
                ],
              ),
            ),
            Divider(height: 24, color: cs.outlineVariant.withValues(alpha: 0.3)),
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: state.dueDate != null
                          ? cs.tertiary.withValues(alpha: 0.12)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(LucideIcons.calendarClock, size: 16,
                        color: state.dueDate != null ? cs.tertiary : cs.onSurfaceVariant),
                  ),
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
                  Icon(LucideIcons.edit3, size: 14, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // SUPPLIER INVOICE REF CARD (Enhanced)
  // ═══════════════════════════════════════════════════════
  Widget _buildRefCard(BuildContext context, PurchaseFormState state) {
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
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(LucideIcons.fileText, size: 16, color: cs.onSurfaceVariant),
            ),
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
  // ITEMS CARD (Premium)
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsCard(BuildContext context, PurchaseFormState state, CurrencyService cs) {
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
                      colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.shoppingCart, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('purchases.items'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
                if (state.items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
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
                padding: const EdgeInsets.symmetric(vertical: 36),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(LucideIcons.packageOpen, size: 36,
                          color: colorScheme.primary.withValues(alpha: 0.3)),
                    ),
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
                    height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
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
  // TOTALS CARD (Invoice footer style)
  // ═══════════════════════════════════════════════════════
  Widget _buildTotalsCard(BuildContext context, PurchaseFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              children: [
                _summaryRow(theme, 'purchases.subtotal'.tr(),
                    cs.format(state.subtotalCents.toBigInt().toInt())),
                if (state.totalDiscountCents > Decimal.zero) ...[
                  const SizedBox(height: 8),
                  _summaryRow(
                    theme,
                    'purchases.discount'.tr(),
                    '- ${cs.format(state.totalDiscountCents.toBigInt().toInt())}',
                    valueColor: colorScheme.tertiary,
                  ),
                ],
                const SizedBox(height: 8),
                _summaryRow(theme, 'purchases.tax'.tr(),
                    cs.format(state.taxCents.toBigInt().toInt())),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border(
                top: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('purchases.total'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold)),
                Text(
                  cs.format(state.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(ThemeData theme, String label, String value,
      {bool isBold = false, Color? valueColor, TextStyle? labelStyle}) {
    final cs = theme.colorScheme;
    final style = labelStyle ?? theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style?.copyWith(
            color: isBold ? null : cs.onSurfaceVariant)),
        Text(value,
            style: (isBold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
                ?.copyWith(
                    color: valueColor,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // BOTTOM BAR (Premium)
  // ═══════════════════════════════════════════════════════
  Widget _buildBottomBar(BuildContext context, PurchaseFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
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
                    Icon(LucideIcons.shoppingCart, size: 12, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '${state.totalQuantity} ${'purchases.items_count'.tr()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
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
                  : () => _showCheckoutDialog(context, state),
              icon: state.isSubmitting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.shoppingBag, size: 18),
              label: Text('purchases.checkout'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // DIALOGS & SHEETS
  // ═══════════════════════════════════════════════════════

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
      builder: (sheetContext) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ProductsBloc>()),
          BlocProvider(create: (_) => sl<VariantPreviewsBloc>()),
          BlocProvider(create: (_) => sl<CategoriesBloc>()..add(const LoadCategories())),
        ],
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

  void _showCheckoutDialog(BuildContext context, PurchaseFormState state) async {
    final suppliers = await sl<SupplierRepository>().searchSuppliers('');
    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => BlocProvider.value(
        value: context.read<PurchaseFormBloc>(),
        child: _CheckoutSheet(
          suppliers: suppliers,
          currencyService: sl<CurrencyService>(),
          onConfirm: () {
            Navigator.pop(sheetCtx);
            context.read<PurchaseFormBloc>().add(const PurchaseFormSubmitted());
          },
        ),
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

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final h = hex.replaceFirst('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    if (h.length == 8) return Color(int.parse(h, radix: 16));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasVariantInfo = item.colorName != null || item.sizeName != null || item.variant?.sku != null;

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
                  Text(item.product.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (hasVariantInfo) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.colorName != null)
                          _VariantChip(
                            icon: item.colorHex != null
                                ? Container(
                                    width: 10, height: 10,
                                    decoration: BoxDecoration(
                                      color: _parseHexColor(item.colorHex) ?? cs.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: cs.outline.withValues(alpha: 0.3), width: 0.5),
                                    ),
                                  )
                                : null,
                            label: item.colorName!,
                            color: cs.tertiaryContainer,
                            textColor: cs.onTertiaryContainer,
                          ),
                        if (item.sizeName != null)
                          _VariantChip(
                            label: item.sizeName!,
                            color: cs.secondaryContainer,
                            textColor: cs.onSecondaryContainer,
                          ),
                        if (item.variant?.sku != null)
                          _VariantChip(
                            label: item.variant!.sku!,
                            color: cs.surfaceContainerHighest,
                            textColor: cs.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
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

// ─── Variant Chip (compact tag for color/size/sku) ───
class _VariantChip extends StatelessWidget {
  final Widget? icon;
  final String label;
  final Color color;
  final Color textColor;

  const _VariantChip({
    this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 4),
          ],
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor, fontWeight: FontWeight.w500, fontSize: 10)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// EDIT ITEM SHEET (Enhanced - Product Edit Dialog)
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
  late final TextEditingController _sellPriceCtrl;
  late final TextEditingController _wholesalePriceCtrl;
  late final TextEditingController _discountPercentCtrl;
  late final TextEditingController _discountFixedCtrl;
  DateTime? _expiryDate;
  bool _updatingDiscount = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.item.quantity}');
    _costCtrl = TextEditingController(
        text: (widget.item.unitCostCents.toBigInt().toInt() / 100).toStringAsFixed(2));

    final sellPriceCents = widget.item.variant?.priceCents.toBigInt().toInt() ??
        widget.item.product.priceCents.toBigInt().toInt();
    final wholesaleCents = widget.item.variant?.wholesalePriceCents?.toBigInt().toInt() ??
        widget.item.product.wholesalePriceCents?.toBigInt().toInt();
    _sellPriceCtrl = TextEditingController(
        text: (sellPriceCents / 100).toStringAsFixed(2));
    _wholesalePriceCtrl = TextEditingController(
        text: wholesaleCents == null ? '' : (wholesaleCents / 100).toStringAsFixed(2));

    final discCents = widget.item.discountCents.toBigInt().toInt();
    final subtotalCents = widget.item.unitCostCents.toBigInt().toInt() * widget.item.quantity;
    _discountFixedCtrl = TextEditingController(
        text: discCents > 0 ? (discCents / 100).toStringAsFixed(2) : '');
    _discountPercentCtrl = TextEditingController(
        text: discCents > 0 && subtotalCents > 0
            ? ((discCents / subtotalCents) * 100).toStringAsFixed(2)
            : '');

    _expiryDate = widget.item.expiryDate;

    _discountPercentCtrl.addListener(_syncFromPercent);
    _discountFixedCtrl.addListener(_syncFromFixed);
  }

  int get _currentSubtotalCents {
    final costVal = double.tryParse(_costCtrl.text) ?? 0;
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    return (costVal * 100).round() * (qty < 1 ? 1 : qty);
  }

  void _syncFromPercent() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    final pct = double.tryParse(_discountPercentCtrl.text) ?? 0;
    final sub = _currentSubtotalCents;
    if (sub > 0 && pct > 0) {
      final cents = (sub * (pct / 100)).round().clamp(0, sub);
      _discountFixedCtrl.text = (cents / 100).toStringAsFixed(2);
    } else {
      _discountFixedCtrl.text = '';
    }
    _updatingDiscount = false;
  }

  void _syncFromFixed() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    final fixedVal = double.tryParse(_discountFixedCtrl.text) ?? 0;
    final fixedCents = (fixedVal * 100).round();
    final sub = _currentSubtotalCents;
    if (sub > 0 && fixedCents > 0) {
      final pct = (fixedCents / sub) * 100;
      _discountPercentCtrl.text = pct.toStringAsFixed(2);
    } else {
      _discountPercentCtrl.text = '';
    }
    _updatingDiscount = false;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _sellPriceCtrl.dispose();
    _wholesalePriceCtrl.dispose();
    _discountPercentCtrl.dispose();
    _discountFixedCtrl.dispose();
    super.dispose();
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final h = hex.replaceFirst('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    if (h.length == 8) return Color(int.parse(h, radix: 16));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final item = widget.item;
    final oldCostCents = item.product.costCents.toBigInt().toInt();
    final sellPriceCents = item.variant?.priceCents.toBigInt().toInt() ?? item.product.priceCents.toBigInt().toInt();
    final currentStock = item.variant?.stockQuantity ?? item.product.stockQuantity;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title with variant info
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.edit3, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.product.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (item.colorName != null || item.sizeName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Wrap(
                              spacing: 6,
                              children: [
                                if (item.colorName != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 10, height: 10,
                                        decoration: BoxDecoration(
                                          color: _parseHexColor(item.colorHex) ?? cs.tertiary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(item.colorName!,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant)),
                                    ],
                                  ),
                                if (item.sizeName != null)
                                  Text(item.sizeName!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Scrollable content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // ── Info Row: Current Stock + Old Cost + Sell Price ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _InfoCell(
                              icon: LucideIcons.warehouse,
                              label: 'purchases.current_stock'.tr(),
                              value: '$currentStock',
                              iconColor: cs.primary,
                            ),
                          ),
                          Container(width: 1, height: 36, color: cs.outlineVariant.withValues(alpha: 0.3)),
                          Expanded(
                            child: _InfoCell(
                              icon: LucideIcons.history,
                              label: 'purchases.old_cost'.tr(),
                              value: widget.currencyService.format(oldCostCents),
                              iconColor: cs.onSurfaceVariant,
                            ),
                          ),
                          Container(width: 1, height: 36, color: cs.outlineVariant.withValues(alpha: 0.3)),
                          Expanded(
                            child: _InfoCell(
                              icon: LucideIcons.tag,
                              label: 'purchases.sell_price'.tr(),
                              value: widget.currencyService.format(sellPriceCents),
                              iconColor: cs.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // ── Quantity + New Cost ──
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
                              labelText: 'purchases.new_cost'.tr(),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(LucideIcons.coins, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sellPriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                            decoration: InputDecoration(
                              labelText: 'purchases.new_sell_price'.tr(),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(LucideIcons.tag, size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _wholesalePriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                            decoration: InputDecoration(
                              labelText: 'purchases.new_wholesale_price'.tr(),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(LucideIcons.badgePercent, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // ── Discount (% and fixed, auto-sync) ──
                    if (widget.discountMode == DiscountMode.perItem) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _discountPercentCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                              decoration: InputDecoration(
                                labelText: 'purchases.discount_percent'.tr(),
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(LucideIcons.percent, size: 18),
                                suffixText: '%',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _discountFixedCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                              decoration: InputDecoration(
                                labelText: 'purchases.discount_fixed'.tr(),
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(LucideIcons.coins, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // ── Expiry Date ──
                    const SizedBox(height: 16),
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
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ── Actions ──
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
                      onPressed: _saving
                          ? null
                          : () async {
                              setState(() => _saving = true);
                              try {
                                final qty = int.tryParse(_qtyCtrl.text) ?? 1;
                                final costVal = double.tryParse(_costCtrl.text) ?? 0;
                                final costCents = Decimal.fromInt((costVal * 100).round());
                                Decimal? discountCents;
                                if (widget.discountMode == DiscountMode.perItem) {
                                  final discVal = double.tryParse(_discountFixedCtrl.text) ?? 0;
                                  discountCents = Decimal.fromInt((discVal * 100).round());
                                }

                                final sellVal = double.tryParse(_sellPriceCtrl.text) ?? 0;
                                final sellCents = Decimal.fromInt((sellVal * 100).round());
                                final wholesaleVal = double.tryParse(_wholesalePriceCtrl.text);
                                final wholesaleCents = wholesaleVal == null
                                    ? null
                                    : Decimal.fromInt((wholesaleVal * 100).round());

                                if (item.variant != null) {
                                  final updatedVariant = item.variant!.copyWith(
                                    priceCents: sellCents,
                                    wholesalePriceCents: wholesaleCents,
                                  );
                                  await sl<ProductVariantRepository>().updateVariant(updatedVariant);
                                } else {
                                  final updatedProduct = item.product.copyWith(
                                    priceCents: sellCents,
                                    wholesalePriceCents: wholesaleCents,
                                  );
                                  await sl<ProductRepository>().updateProduct(updatedProduct);
                                }

                                widget.onSave(
                                  qty < 1 ? 1 : qty,
                                  costCents,
                                  discountCents,
                                  _expiryDate,
                                  _expiryDate == null && widget.item.expiryDate != null,
                                );
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e.toString()),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Info Cell (for edit dialog info row) ───
class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant, fontSize: 9)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// CHECKOUT SHEET (Pre-save dialog)
// ═══════════════════════════════════════════════════════
class _CheckoutSheet extends StatefulWidget {
  final List<Supplier> suppliers;
  final CurrencyService currencyService;
  final VoidCallback onConfirm;

  const _CheckoutSheet({
    required this.suppliers,
    required this.currencyService,
    required this.onConfirm,
  });

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late final TextEditingController _taxCtrl;
  late final TextEditingController _paidCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _discountPercentCtrl;
  late final TextEditingController _discountFixedCtrl;
  bool _updatingDiscount = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<PurchaseFormBloc>().state;
    _taxCtrl = TextEditingController(
        text: state.taxRatePercent > Decimal.zero
            ? state.taxRatePercent.toString()
            : '');
    _paidCtrl = TextEditingController(
        text: state.paidAmountCents > Decimal.zero
            ? (state.paidAmountCents.toBigInt().toInt() / 100).toStringAsFixed(2)
            : '');
    _notesCtrl = TextEditingController(text: state.notes ?? '');

    final discCents = state.invoiceDiscountCents.toBigInt().toInt();
    final subtotalCents = state.subtotalCents.toBigInt().toInt();
    _discountFixedCtrl = TextEditingController(
        text: discCents > 0 ? (discCents / 100).toStringAsFixed(2) : '');
    _discountPercentCtrl = TextEditingController(
        text: discCents > 0 && subtotalCents > 0
            ? ((discCents / subtotalCents) * 100).toStringAsFixed(2)
            : '');

    _discountPercentCtrl.addListener(_syncDiscountFromPercent);
    _discountFixedCtrl.addListener(_syncDiscountFromFixed);
  }

  void _syncDiscountFromPercent() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    final pct = double.tryParse(_discountPercentCtrl.text) ?? 0;
    final sub = context.read<PurchaseFormBloc>().state.subtotalCents.toBigInt().toInt();
    if (sub > 0 && pct > 0) {
      final cents = (sub * (pct / 100)).round().clamp(0, sub);
      _discountFixedCtrl.text = (cents / 100).toStringAsFixed(2);
    } else {
      _discountFixedCtrl.text = '';
    }
    _applyInvoiceDiscount();
    _updatingDiscount = false;
  }

  void _syncDiscountFromFixed() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    final fixedVal = double.tryParse(_discountFixedCtrl.text) ?? 0;
    final fixedCents = (fixedVal * 100).round();
    final sub = context.read<PurchaseFormBloc>().state.subtotalCents.toBigInt().toInt();
    if (sub > 0 && fixedCents > 0) {
      final pct = (fixedCents / sub) * 100;
      _discountPercentCtrl.text = pct.toStringAsFixed(2);
    } else {
      _discountPercentCtrl.text = '';
    }
    _applyInvoiceDiscount();
    _updatingDiscount = false;
  }

  void _applyInvoiceDiscount() {
    final fixedVal = double.tryParse(_discountFixedCtrl.text) ?? 0;
    final cents = (fixedVal * 100).round();
    context.read<PurchaseFormBloc>().add(
          PurchaseInvoiceDiscountChanged(Decimal.fromInt(cents)),
        );
  }

  @override
  void dispose() {
    _taxCtrl.dispose();
    _paidCtrl.dispose();
    _notesCtrl.dispose();
    _discountPercentCtrl.dispose();
    _discountFixedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BlocBuilder<PurchaseFormBloc, PurchaseFormState>(
      builder: (context, state) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle + Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(LucideIcons.shoppingBag, size: 20, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text('purchases.checkout_title'.tr(),
                              style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                // Scrollable content
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(20),
                    children: [
                      // ── Supplier Selection ──
                      _buildCheckoutSection(
                        theme: theme,
                        cs: cs,
                        icon: LucideIcons.building2,
                        title: 'purchases.supplier'.tr(),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _showSupplierPickerInCheckout(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: cs.outlineVariant),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                if (state.supplierName != null) ...[
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: cs.primaryContainer,
                                    child: Text(
                                      state.supplierName![0].toUpperCase(),
                                      style: TextStyle(
                                          color: cs.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    state.supplierName ?? 'purchases.select_supplier'.tr(),
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: state.supplierName != null ? FontWeight.w500 : FontWeight.normal,
                                      color: state.supplierName != null ? null : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Icon(LucideIcons.chevronDown, size: 18, color: cs.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── Payment Method ──
                      _buildCheckoutSection(
                        theme: theme,
                        cs: cs,
                        icon: LucideIcons.wallet,
                        title: 'purchases.payment_method'.tr(),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: PurchasePaymentMethod.values.map((method) {
                            final isSelected = state.paymentMethod == method;
                            return ChoiceChip(
                              label: Text(_paymentMethodLabel(method)),
                              selected: isSelected,
                              onSelected: (_) => context
                                  .read<PurchaseFormBloc>()
                                  .add(PurchasePaymentMethodChanged(method)),
                              avatar: Icon(_paymentMethodIcon(method), size: 16),
                              selectedColor: cs.primaryContainer,
                              showCheckmark: false,
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── Tax Rate ──
                      _buildCheckoutSection(
                        theme: theme,
                        cs: cs,
                        icon: LucideIcons.percent,
                        title: 'purchases.tax_rate'.tr(),
                        child: TextField(
                          controller: _taxCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            suffixText: '%',
                            hintText: '0',
                            isDense: true,
                          ),
                          onChanged: (v) {
                            final pct = double.tryParse(v) ?? 0;
                            context.read<PurchaseFormBloc>().add(
                                  PurchaseTaxRateChanged(Decimal.parse(pct.toStringAsFixed(2))),
                                );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── Invoice Discount (% and fixed) ──
                      if (state.discountMode == DiscountMode.invoice)
                        ...[
                          _buildCheckoutSection(
                            theme: theme,
                            cs: cs,
                            icon: LucideIcons.tag,
                            title: 'purchases.invoice_discount'.tr(),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _discountPercentCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                                    decoration: InputDecoration(
                                      labelText: 'purchases.discount_percent'.tr(),
                                      border: const OutlineInputBorder(),
                                      suffixText: '%',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _discountFixedCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                                    decoration: InputDecoration(
                                      labelText: 'purchases.discount_fixed'.tr(),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      // ── Paid Amount ──
                      _buildCheckoutSection(
                        theme: theme,
                        cs: cs,
                        icon: LucideIcons.banknote,
                        title: 'purchases.paid_amount'.tr(),
                        child: TextField(
                          controller: _paidCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: '0.00',
                            isDense: true,
                          ),
                          onChanged: (v) {
                            final val = double.tryParse(v) ?? 0;
                            context.read<PurchaseFormBloc>().add(
                                  PurchasePaidAmountChanged(Decimal.fromInt((val * 100).round())),
                                );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── Notes ──
                      _buildCheckoutSection(
                        theme: theme,
                        cs: cs,
                        icon: LucideIcons.stickyNote,
                        title: 'purchases.notes'.tr(),
                        child: TextField(
                          controller: _notesCtrl,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'purchases.notes_hint'.tr(),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                          onChanged: (v) => context
                              .read<PurchaseFormBloc>()
                              .add(PurchaseNotesChanged(v)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // ── Financial Summary ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            _checkoutRow(theme, 'purchases.subtotal'.tr(),
                                widget.currencyService.format(state.subtotalCents.toBigInt().toInt())),
                            if (state.totalDiscountCents > Decimal.zero) ...[
                              const SizedBox(height: 8),
                              _checkoutRow(theme, 'purchases.discount'.tr(),
                                  '- ${widget.currencyService.format(state.totalDiscountCents.toBigInt().toInt())}',
                                  valueColor: cs.tertiary),
                            ],
                            if (state.taxCents > Decimal.zero) ...[
                              const SizedBox(height: 8),
                              _checkoutRow(theme, 'purchases.tax'.tr(),
                                  widget.currencyService.format(state.taxCents.toBigInt().toInt())),
                            ],
                            Divider(height: 20, color: cs.outlineVariant.withValues(alpha: 0.5)),
                            _checkoutRow(theme, 'purchases.total'.tr(),
                                widget.currencyService.format(state.totalCents.toBigInt().toInt()),
                                isBold: true, valueColor: cs.primary),
                            if (state.paidAmountCents > Decimal.zero) ...[
                              const SizedBox(height: 8),
                              _checkoutRow(theme, 'purchases.paid_amount'.tr(),
                                  widget.currencyService.format(state.paidAmountCents.toBigInt().toInt()),
                                  valueColor: Colors.green),
                              const SizedBox(height: 4),
                              _checkoutRow(theme, 'purchases.remaining'.tr(),
                                  widget.currencyService.format(state.remainingCents.toBigInt().toInt()),
                                  isBold: true,
                                  valueColor: state.remainingCents > Decimal.zero ? cs.error : Colors.green),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
                // ── Bottom Actions ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('common.cancel'.tr()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: state.supplierId == null
                                ? null
                                : widget.onConfirm,
                            icon: const Icon(LucideIcons.check, size: 18),
                            label: Text('purchases.confirm_save'.tr()),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCheckoutSection({
    required ThemeData theme,
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _checkoutRow(ThemeData theme, String label, String value,
      {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: (isBold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
            ?.copyWith(color: isBold ? null : theme.colorScheme.onSurfaceVariant)),
        Text(value, style: (isBold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
            ?.copyWith(
                color: valueColor,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }

  String _paymentMethodLabel(PurchasePaymentMethod method) {
    switch (method) {
      case PurchasePaymentMethod.cash:
        return 'purchases.payment_cash'.tr();
      case PurchasePaymentMethod.credit:
        return 'purchases.payment_credit'.tr();
      case PurchasePaymentMethod.card:
        return 'purchases.payment_card'.tr();
      case PurchasePaymentMethod.cheque:
        return 'purchases.payment_cheque'.tr();
      case PurchasePaymentMethod.purchaseOrder:
        return 'purchases.payment_po'.tr();
    }
  }

  IconData _paymentMethodIcon(PurchasePaymentMethod method) {
    switch (method) {
      case PurchasePaymentMethod.cash:
        return LucideIcons.banknote;
      case PurchasePaymentMethod.credit:
        return LucideIcons.clock;
      case PurchasePaymentMethod.card:
        return LucideIcons.creditCard;
      case PurchasePaymentMethod.cheque:
        return LucideIcons.fileText;
      case PurchasePaymentMethod.purchaseOrder:
        return LucideIcons.clipboardList;
    }
  }

  void _showSupplierPickerInCheckout(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _SupplierPickerSheet(
        suppliers: widget.suppliers,
        onSelected: (supplier) {
          context.read<PurchaseFormBloc>().add(
                PurchaseSupplierChanged(supplier.id, supplierName: supplier.name),
              );
          Navigator.pop(sheetCtx);
        },
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
  int? _selectedCategoryId;

  Color? _tryParseHexColor(String? hex) {
    if (hex == null) return null;
    final cleaned = hex.trim().replaceFirst('#', '');
    if (cleaned.isEmpty) return null;
    final buffer = StringBuffer();
    if (cleaned.length == 6) buffer.write('FF');
    buffer.write(cleaned);
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  Future<void> _showVariantsInfoDialog(Product product) async {
    final colorScheme = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          title: Text(product.name),
          content: SizedBox(
            width: 520,
            child: FutureBuilder<({
              List<ProductVariant> variants,
              Map<int, String> sizeNameById,
              Map<int, String?> colorHexById,
            })>(
              future: () async {
                final variantRepo = sl<ProductVariantRepository>();
                final colorRepo = sl<ProductColorRepository>();
                final sizeRepo = sl<SizeRepository>();

                final results = await Future.wait([
                  variantRepo.getVariantsByProduct(product.id),
                  colorRepo.getAllColors(),
                  sizeRepo.getAllSizes(),
                ]);

                final variants = results[0] as List<ProductVariant>;
                final colors = results[1] as List<dynamic>;
                final sizes = results[2] as List<dynamic>;

                final sizeNameById = <int, String>{};
                for (final s in sizes) {
                  sizeNameById[(s as dynamic).id as int] = (s as dynamic).name as String;
                }
                final colorHexById = <int, String?>{};
                for (final c in colors) {
                  colorHexById[(c as dynamic).id as int] = (c as dynamic).hexCode as String?;
                }

                return (
                  variants: variants,
                  sizeNameById: sizeNameById,
                  colorHexById: colorHexById,
                );
              }(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final variants = snapshot.data!.variants;
                final sizeNameById = snapshot.data!.sizeNameById;
                final colorHexById = snapshot.data!.colorHexById;

                final distinctColorHexes = <String>{};
                final distinctSizeNames = <String>{};
                for (final v in variants.where((x) => x.isActive)) {
                  final hex = v.colorId == null ? null : colorHexById[v.colorId!];
                  if (hex != null && hex.trim().isNotEmpty) {
                    distinctColorHexes.add(hex.trim());
                  }
                  final sizeName = v.sizeId == null ? null : sizeNameById[v.sizeId!];
                  if (sizeName != null && sizeName.trim().isNotEmpty) {
                    distinctSizeNames.add(sizeName.trim());
                  }
                }

                final dots = distinctColorHexes
                    .map(_tryParseHexColor)
                    .whereType<Color>()
                    .toList();
                final sizeList = distinctSizeNames.toList()..sort();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dots.isNotEmpty) ...[
                      Text('colors.title'.tr(), style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in dots)
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(color: colorScheme.outline),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (sizeList.isNotEmpty) ...[
                      Text('sizes.title'.tr(), style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in sizeList) Chip(label: Text(s)),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('variants.title'.tr(), style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 220,
                      child: ListView.separated(
                        itemCount: variants.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final v = variants[index];
                          final sizeName = v.sizeId == null ? null : sizeNameById[v.sizeId!];
                          final hex = v.colorId == null ? null : colorHexById[v.colorId!];
                          final shade = _tryParseHexColor(hex);

                          final title = v.sku?.isNotEmpty == true
                              ? v.sku!
                              : 'product_form.variant_item_title'.tr(args: ['${v.id}']);

                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (sizeName != null && sizeName.trim().isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      sizeName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (sizeName != null && sizeName.trim().isNotEmpty && shade != null)
                                  const SizedBox(width: 8),
                                if (shade != null)
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: shade,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: colorScheme.outline),
                                    ),
                                  ),
                                const Spacer(),
                                Text(
                                  '${'variants.stock'.tr()}: ${v.stockQuantity}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('common.close'.tr()),
            ),
          ],
        );
      },
    );
  }

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
            // Search + Category Filter
            if (_selectedProduct == null) ...[
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
              ),
              // Category filter chips
              BlocBuilder<CategoriesBloc, RealtimeState<List<Category>>>(
                builder: (context, catState) {
                  List<Category> categories = const [];
                  if (catState is RealtimeSuccess<List<Category>>) {
                    categories = catState.data;
                  } else if (catState is RealtimeLoading<List<Category>>) {
                    categories = catState.previousData ?? const [];
                  }
                  if (categories.isEmpty) return const SizedBox.shrink();

                  return SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: Text('purchases.all_categories'.tr()),
                            selected: _selectedCategoryId == null,
                            onSelected: (_) => setState(() => _selectedCategoryId = null),
                            showCheckmark: false,
                            selectedColor: cs.primaryContainer,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        ...categories.map((cat) => Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: ChoiceChip(
                                label: Text(cat.name),
                                selected: _selectedCategoryId == cat.id,
                                onSelected: (_) => setState(() {
                                  _selectedCategoryId = _selectedCategoryId == cat.id ? null : cat.id;
                                }),
                                showCheckmark: false,
                                selectedColor: cs.primaryContainer,
                                visualDensity: VisualDensity.compact,
                              ),
                            )),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ] else
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

    return BlocBuilder<VariantPreviewsBloc, RealtimeState<Map<int, VariantPreview>>>(
      builder: (context, previewState) {
        Map<int, VariantPreview> previews = const {};
        if (previewState is RealtimeSuccess<Map<int, VariantPreview>>) {
          previews = previewState.data;
        } else if (previewState is RealtimeLoading<Map<int, VariantPreview>>) {
          previews = previewState.previousData ?? const {};
        }

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
              // Category filter
              if (_selectedCategoryId != null && p.categoryId != _selectedCategoryId) {
                return false;
              }
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
                    Icon(LucideIcons.searchX,
                        size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text('purchases.no_products_found'.tr(),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              );
            }

            return ListView.separated(
              controller: scrollController,
              itemCount: filtered.length,
              separatorBuilder: (_, idx) => Divider(
                height: 1,
                indent: 56,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              itemBuilder: (context, index) {
                final product = filtered[index];
                final preview = previews[product.id];
                final sizeName = (!product.hasVariants ? preview?.sizeName?.trim() : null);
                final colorHex = (!product.hasVariants ? preview?.colorHex?.trim() : null);

                Color? shade;
                if (colorHex != null && colorHex.isNotEmpty) {
                  final cleaned = colorHex.replaceFirst('#', '');
                  if (cleaned.length == 6 || cleaned.length == 8) {
                    final argb = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
                    try {
                      shade = Color(int.parse(argb, radix: 16));
                    } catch (_) {}
                  }
                }

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      product.hasVariants ? LucideIcons.layers : LucideIcons.package,
                      size: 20,
                      color: cs.primary,
                    ),
                  ),
                  title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Row(
                    children: [
                      if (product.sku != null) ...[
                        Flexible(
                          child: Text(
                            'SKU: ${product.sku}',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (sizeName != null && sizeName.isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            sizeName,
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (shade != null) const SizedBox(width: 6),
                      ],
                      if (shade != null)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: shade,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.outline),
                          ),
                        ),
                      const Spacer(),
                      if (!product.hasVariants)
                        Text(
                          currencyService.format(product.costCents.toBigInt().toInt()),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  trailing: product.hasVariants
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.info, size: 18),
                              onPressed: () => _showVariantsInfoDialog(product),
                            ),
                            Icon(LucideIcons.chevronRight, size: 20, color: cs.primary),
                          ],
                        )
                      : Icon(
                          LucideIcons.plusCircle,
                          size: 20,
                          color: cs.primary,
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

          return FutureBuilder<({Map<int, String> sizeNameById, Map<int, String?> colorHexById})>(
            future: () async {
              final colorRepo = sl<ProductColorRepository>();
              final sizeRepo = sl<SizeRepository>();

              final results = await Future.wait([
                colorRepo.getAllColors(),
                sizeRepo.getAllSizes(),
              ]);

              final colors = results[0] as List<dynamic>;
              final sizes = results[1] as List<dynamic>;

              final sizeNameById = <int, String>{};
              for (final s in sizes) {
                sizeNameById[(s as dynamic).id as int] = (s as dynamic).name as String;
              }

              final colorHexById = <int, String?>{};
              for (final c in colors) {
                colorHexById[(c as dynamic).id as int] = (c as dynamic).hexCode as String?;
              }

              return (sizeNameById: sizeNameById, colorHexById: colorHexById);
            }(),
            builder: (context, snapshot) {
              final sizeNameById = snapshot.data?.sizeNameById ?? const <int, String>{};
              final colorHexById = snapshot.data?.colorHexById ?? const <int, String?>{};

              final variantsList = variants;
              if (variantsList == null) {
                return const Center(child: CircularProgressIndicator());
              }

              return ListView.separated(
                itemCount: variantsList.length,
                separatorBuilder: (_, idx) => Divider(
                  height: 1,
                  indent: 56,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final variant = variantsList[index];
                  final sizeName = variant.sizeId == null ? null : sizeNameById[variant.sizeId!];
                  final colorHex = variant.colorId == null ? null : colorHexById[variant.colorId!];
                  final shade = _tryParseHexColor(colorHex);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(LucideIcons.tag, size: 18, color: cs.tertiary),
                    ),
                    title: Text(
                      variant.sku ?? 'Variant ${variant.id}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Row(
                      children: [
                        if (sizeName != null && sizeName.trim().isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              sizeName,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (shade != null) const SizedBox(width: 6),
                        ],
                        if (shade != null) ...[
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: shade,
                              shape: BoxShape.circle,
                              border: Border.all(color: cs.outline),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Icon(LucideIcons.warehouse, size: 12, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '${variant.stockQuantity}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(width: 12),
                        Icon(LucideIcons.coins, size: 12, color: cs.primary),
                        const SizedBox(width: 4),
                        Text(
                          currencyService.format(variant.costCents.toBigInt().toInt()),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
          );
        },
      ),
    );
  }
}
