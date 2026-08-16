import 'dart:ui' as ui;
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
import '../../../../core/services/pricing/discount_converter.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/database/app_database.dart' show Supplier;
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';
import '../../../products/domain/repositories/product_color_repository.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../../products/domain/repositories/size_repository.dart';
import '../../../products/domain/repositories/product_variant_repository.dart';
import '../../../products/domain/services/product_barcode_resolver.dart';
import '../../../products/domain/entities/category_entity.dart';
import '../../../products/presentation/bloc/categories_bloc.dart';
import '../../../products/presentation/bloc/categories_event.dart';
import '../../../products/presentation/bloc/products_bloc.dart';
import '../../../products/presentation/bloc/product_variants_bloc.dart';
import '../../../products/presentation/bloc/variant_previews_bloc.dart';
import '../../../suppliers/domain/repositories/supplier_repository.dart';
import '../../../barcode/data/models/invoice_print_data.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../bloc/purchase_form_bloc.dart';
import '../services/purchase_pdf_service.dart';

class PurchaseFormScreen extends StatelessWidget {
  final int? purchaseId;
  final bool isEditingPosted;

  const PurchaseFormScreen({
    super.key,
    this.purchaseId,
    this.isEditingPosted = false,
  });

  @override
  Widget build(BuildContext context) {
    // Get tax settings from AppSettingsBloc
    final appSettingsState = context.read<AppSettingsBloc>().state;
    final settings = appSettingsState.settings;
    final enableTax = settings.enableTaxCalculations;
    // Convert percentage to basis points (e.g., 15% -> 1500 bps)
    final taxRateBps = (settings.defaultPurchaseTaxRate * 100).round();

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => sl<PurchaseFormBloc>()
            ..add(
              PurchaseFormInitialized(
                purchaseId: purchaseId,
                currencyId: 1,
                enableTaxCalculations: enableTax,
                defaultPurchaseTaxRateBps: taxRateBps,
                taxInclusivePricing: settings.taxInclusivePricing,
                isEditingPosted: isEditingPosted,
              ),
            ),
        ),
        BlocProvider(create: (context) => sl<ProductsBloc>()),
      ],
      child: const _PurchaseFormView(),
    );
  }
}

class _PurchaseFormView extends StatelessWidget {
  const _PurchaseFormView();

  InvoicePrintData _buildInvoicePrintDataFromPurchaseFormState(
    PurchaseFormState state,
  ) {
    final lines = state.items
        .where(
          (i) =>
              (i.variant?.barcode ?? i.product.barcode ?? '').trim().isNotEmpty,
        )
        .map((i) {
          final barcode = (i.variant?.barcode ?? i.product.barcode)!.trim();
          final skuValue = (i.variant?.sku ?? i.product.sku ?? '').trim();
          return InvoiceLinePrintData(
            variantId: i.variant?.id ?? i.product.id,
            quantity: i.quantity,
            productName: i.product.name,
            colorName: i.colorName,
            sizeName: i.sizeName,
            barcode: barcode,
            sku: skuValue.isEmpty
                ? '${i.variant?.id ?? i.product.id}'
                : skuValue,
            unitPriceCents: i.unitCostCents.toBigInt().toInt(),
            sellingPriceCents: (i.variant?.priceCents ?? i.product.priceCents)
                .toBigInt()
                .toInt(),
            wholesalePriceCents:
                (i.variant?.wholesalePriceCents ??
                        i.product.wholesalePriceCents)
                    ?.toBigInt()
                    .toInt(),
            isActive: true,
          );
        })
        .toList();

    return InvoicePrintData(
      lines: lines,
      invoiceType: 'purchase',
      invoiceId: state.purchaseId ?? 0,
      invoiceNumber: state.purchaseNumber ?? 'draft',
      invoiceDate: state.purchaseDate,
    );
  }

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
          // Capture state snapshot before navigating away
          final stateSnapshot = state;
          // Navigate back immediately to prevent duplicate submissions
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/purchases');
          }
          // Show print/share dialog after navigation completes
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final nav = Navigator.of(context, rootNavigator: true);
            if (nav.context.mounted) {
              _showSaveConfirmationOverlay(nav.context, stateSnapshot);
            }
          });
        }
        if (state.error != null) {
          final key = state.error!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(key.tr() == key ? key : key.tr()),
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
              title: Text(
                state.purchaseId == null
                    ? 'purchases.title'.tr()
                    : 'purchases.edit'.tr(),
              ),
              actions: [
                if (state.purchaseId != null)
                  TextButton.icon(
                    icon: const Icon(LucideIcons.checkCircle, size: 18),
                    label: Text('purchases.post'.tr()),
                    onPressed: state.isSubmitting
                        ? null
                        : () => context.read<PurchaseFormBloc>().add(
                            const PurchaseFormPosted(),
                          ),
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
  Widget _buildWideLayout(
    BuildContext context,
    PurchaseFormState state,
    CurrencyService cs,
  ) {
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
              _buildDueDateCard(context, state),
              const SizedBox(height: 12),
              _buildRefCard(context, state),
              const SizedBox(height: 12),
              _buildDiscountModeCard(context, state, cs),
              const SizedBox(height: 12),
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
  Widget _buildNarrowLayout(
    BuildContext context,
    PurchaseFormState state,
    CurrencyService cs,
  ) {
    return Column(
      children: [
        // Fixed top section: invoice header, discount mode + supplier ref row,
        // and the product search bar. This stays pinned and does NOT scroll
        // away when new items are added.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              _buildInvoiceHeaderCard(context, state),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildDiscountModeCard(
                        context,
                        state,
                        cs,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _buildRefCard(context, state)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildSearchBarWithScan(context),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _buildItemsCard(context, state, cs),
              const SizedBox(height: 12),
              _buildDueDateCard(context, state),
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
  Widget _buildInvoiceHeaderCard(
    BuildContext context,
    PurchaseFormState state,
  ) {
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
                Text(
                  'purchases.invoice_number'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    state.purchaseNumber ?? '—',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
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
                  context.read<PurchaseFormBloc>().add(
                    PurchaseDateChanged(date),
                  );
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'purchases.invoice_date'.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                              fontWeight: FontWeight.w500,
                            ),
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
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.search,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'purchases.search_or_scan'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
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
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(
              LucideIcons.scanLine,
              size: 22,
              color: cs.onSurfaceVariant,
            ),
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
              child: Text(
                'purchases.menu'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(LucideIcons.plusCircle, color: cs.primary),
              title: Text('purchases.add_new_product'.tr()),
              onTap: () {
                Navigator.pop(context);
                context.push('/products/new');
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
              onTap: state.purchaseId != null
                  ? () {
                      Navigator.pop(context);
                      context.push('/purchases/${state.purchaseId}/edit');
                    }
                  : null,
            ),
            ListTile(
              leading: Icon(LucideIcons.fileInput, color: cs.primary),
              title: Text('purchases.import_from_po'.tr()),
              onTap: () {
                Navigator.pop(context);
                _showImportFromPurchaseDialog(context, isPO: true);
              },
            ),
            ListTile(
              leading: Icon(LucideIcons.fileOutput, color: cs.primary),
              title: Text('purchases.import_from_dispatch'.tr()),
              onTap: () {
                Navigator.pop(context);
                _showImportFromPurchaseDialog(context, isPO: false);
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
              Text(
                'purchases.enter_invoice_number'.tr(),
                style: theme.textTheme.bodyMedium,
              ),
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
  // IMPORT FROM PO / DISPATCH DIALOG
  // ═══════════════════════════════════════════════════════
  void _showImportFromPurchaseDialog(
    BuildContext context, {
    required bool isPO,
  }) async {
    final repo = sl<PurchaseRepository>();
    final cs = sl<CurrencyService>();

    // Load existing purchases to import from
    final purchases = await repo.watchAllPurchases().first;
    if (!context.mounted) return;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = isPO
        ? 'purchases.select_po'.tr()
        : 'purchases.select_dispatch'.tr();
    final emptyMsg = isPO
        ? 'purchases.no_po_found'.tr()
        : 'purchases.no_dispatch_found'.tr();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (_, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isPO ? LucideIcons.fileInput : LucideIcons.fileOutput,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(LucideIcons.x),
                        onPressed: () => Navigator.pop(sheetCtx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (purchases.isEmpty)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.fileX,
                            size: 48,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            emptyMsg,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: purchases.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final purchase = purchases[index];
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              LucideIcons.fileText,
                              size: 18,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            purchase.purchaseNumber.isNotEmpty
                                ? purchase.purchaseNumber
                                : '#${purchase.id}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${DateFormat.yMMMd().format(purchase.purchaseDate)} • ${cs.format(purchase.totalCents.toBigInt().toInt())}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: FilledButton.tonal(
                            onPressed: () async {
                              Navigator.pop(sheetCtx);
                              await _importItemsFromPurchase(
                                context,
                                purchase.id,
                              );
                            },
                            child: Text('purchases.import_items'.tr()),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _importItemsFromPurchase(
    BuildContext context,
    int purchaseId,
  ) async {
    final repo = sl<PurchaseRepository>();
    final productRepo = sl<ProductRepository>();

    try {
      final items = await repo.getPurchaseItems(purchaseId);
      if (!context.mounted) return;

      final bloc = context.read<PurchaseFormBloc>();
      for (final item in items) {
        final product = await productRepo.watchProduct(item.productId).first;
        if (product != null) {
          ProductVariant? variant;
          if (item.variantId != null) {
            final variantRepo = sl<ProductVariantRepository>();
            variant = await variantRepo.getVariantById(item.variantId!);
          }
          bloc.add(
            PurchaseLineItemAdded(
              product: product,
              variant: variant,
              quantity: item.quantity,
              unitCostCents: item.unitCostCents,
            ),
          );
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('purchases.import_success'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // SAVE CONFIRMATION OVERLAY (Print / Barcode / Finish)
  // Shown AFTER navigating back to the purchases list.
  // ═══════════════════════════════════════════════════════
  void _showSaveConfirmationOverlay(
    BuildContext context,
    PurchaseFormState state,
  ) {
    final theme = Theme.of(context);
    final invoiceNumber = state.purchaseNumber ?? '${state.purchaseId ?? ''}';

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
                'purchases.invoice_saved_message'.tr(args: [invoiceNumber]),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
                try {
                  await PurchasePdfService.printFromFormState(
                    context: context,
                    state: state,
                  );
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
              },
            ),
            TextButton.icon(
              icon: const Icon(LucideIcons.share2, size: 18),
              label: Text('common.share'.tr()),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await PurchasePdfService.shareFromFormState(
                    context: context,
                    state: state,
                  );
                } catch (_) {
                  // Keep silent; sharing is best-effort.
                }
              },
            ),
            TextButton.icon(
              icon: const Icon(LucideIcons.scan, size: 18),
              label: Text('purchases.generate_barcode'.tr()),
              onPressed: () {
                Navigator.pop(ctx);
                final invoiceData = _buildInvoicePrintDataFromPurchaseFormState(
                  state,
                );
                final products = state.items.map((i) => i.product).toList();
                context.push(
                  '/products/barcode-design',
                  extra: {'products': products, 'invoiceData': invoiceData},
                );
              },
            ),
            FilledButton.icon(
              icon: const Icon(LucideIcons.checkCircle, size: 18),
              label: Text('purchases.finish'.tr()),
              onPressed: () {
                Navigator.pop(ctx);
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
    final result = await context.push<String>(
      '/barcode-scanner',
      extra: {'returnOnScan': true},
    );
    if (result != null && result.isNotEmpty && context.mounted) {
      final resolver = ProductBarcodeResolver(
        productRepository: sl<ProductRepository>(),
        variantRepository: sl<ProductVariantRepository>(),
      );

      try {
        final resolution = await resolver.resolve(result);
        if (!context.mounted) return;

        switch (resolution.type) {
          case ProductBarcodeResolutionType.variant:
            final product = resolution.product!;
            final variant = resolution.variant!;
            context.read<PurchaseFormBloc>().add(
              PurchaseLineItemAdded(
                product: product,
                variant: variant,
                quantity: product.quantityScale,
                // GROSS supplier reference price (with NET fallback for
                // legacy variants pre-migration 10055). Same convention as
                // VariantEditDialog so the form value the user sees here
                // matches what they typed on the last purchase — removes
                // the variant-vs-no-variant asymmetry where the cost field
                // silently dropped to the post-discount IAS-2 net basis.
                unitCostCents:
                    variant.lastPurchasePriceCents ?? variant.costCents,
              ),
            );
            return;
          case ProductBarcodeResolutionType.simpleProduct:
            final product = resolution.product!;
            context.read<PurchaseFormBloc>().add(
              PurchaseLineItemAdded(
                product: product,
                quantity: product.quantityScale,
                unitCostCents:
                    product.lastPurchasePriceCents ?? product.costCents,
              ),
            );
            return;
          case ProductBarcodeResolutionType.variantParent:
            _showAddItemSheet(context, initialProduct: resolution.product!);
            return;
          case ProductBarcodeResolutionType.ambiguous:
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('products.barcode_ambiguous'.tr()),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          case ProductBarcodeResolutionType.notFound:
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('purchases.no_products_found'.tr()),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
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
  // DUE DATE CARD (Purchase date is in invoice header)
  // ═══════════════════════════════════════════════════════
  Widget _buildDueDateCard(BuildContext context, PurchaseFormState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate:
                state.dueDate ??
                state.purchaseDate.add(const Duration(days: 30)),
            firstDate: state.purchaseDate,
            lastDate: state.purchaseDate.add(const Duration(days: 365)),
          );
          if (date != null && context.mounted) {
            context.read<PurchaseFormBloc>().add(PurchaseDueDateChanged(date));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                child: Icon(
                  LucideIcons.calendarClock,
                  size: 16,
                  color: state.dueDate != null
                      ? cs.tertiary
                      : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'purchases.due_date'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      state.dueDate != null
                          ? DateFormat.yMMMd().format(state.dueDate!)
                          : 'purchases.set_due_date'.tr(),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: state.dueDate != null
                            ? FontWeight.w500
                            : FontWeight.normal,
                        color: state.dueDate != null
                            ? null
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.edit3, size: 14, color: cs.onSurfaceVariant),
            ],
          ),
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
              child: Icon(
                LucideIcons.fileText,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
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
                onChanged: (v) => context.read<PurchaseFormBloc>().add(
                  PurchaseSupplierRefChanged(v),
                ),
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
  Widget _buildDiscountModeCard(
    BuildContext context,
    PurchaseFormState state,
    CurrencyService cs, {
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final segmentedButton = SegmentedButton<DiscountMode>(
      segments: [
        ButtonSegment(
          value: DiscountMode.perItem,
          label: Text('purchases.discount_per_item'.tr()),
          icon: compact ? null : const Icon(LucideIcons.list, size: 16),
        ),
        ButtonSegment(
          value: DiscountMode.invoice,
          label: Text('purchases.discount_on_invoice'.tr()),
          icon: compact ? null : const Icon(LucideIcons.receipt, size: 16),
        ),
      ],
      selected: {state.discountMode},
      showSelectedIcon: !compact,
      onSelectionChanged: (v) => context.read<PurchaseFormBloc>().add(
        PurchaseDiscountModeChanged(v.first),
      ),
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );

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
                Icon(
                  LucideIcons.percent,
                  size: 20,
                  color: colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'purchases.discount'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Toggle — in compact (side-by-side) mode scale down to avoid
            // horizontal overflow inside the half-width column.
            compact
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: segmentedButton,
                  )
                : segmentedButton,
            if (state.discountMode == DiscountMode.invoice) ...[
              const SizedBox(height: 8),
              state.effectiveInvoiceDiscountCents > Decimal.zero
                  ? Text(
                      cs.format(
                        state.effectiveInvoiceDiscountCents.toBigInt().toInt(),
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Text(
                      'purchases.invoice_discount_checkout_hint'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ],
            if (state.discountMode == DiscountMode.perItem &&
                state.itemDiscountCents > Decimal.zero) ...[
              const SizedBox(height: 8),
              Text(
                '${'purchases.total_item_discounts'.tr()}: ${cs.format(state.itemDiscountCents.toBigInt().toInt())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.tertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ITEMS CARD (Premium)
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsCard(
    BuildContext context,
    PurchaseFormState state,
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
                        colorScheme.primary,
                        colorScheme.primary.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    LucideIcons.shoppingCart,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'purchases.items'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (state.items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${state.items.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showAddItemSheet(context),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: Text('purchases.add_item'.tr()),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.2,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.packageOpen,
                        size: 36,
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'purchases.no_items'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'purchases.add_items_hint'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.items.length,
                separatorBuilder: (_, idx) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  return _PurchaseItemTile(
                    item: item,
                    index: index,
                    currencyService: cs,
                    showItemDiscount:
                        state.discountMode == DiscountMode.perItem,
                    onTap: () => _showEditItemDialog(context, item),
                    onRemove: () => context.read<PurchaseFormBloc>().add(
                      PurchaseLineItemRemoved(item.tempId),
                    ),
                    onQuantityChanged: (qty) =>
                        context.read<PurchaseFormBloc>().add(
                          PurchaseLineItemUpdated(
                            tempId: item.tempId,
                            quantity: qty,
                          ),
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
  // TOTALS CARD (Invoice footer style)
  // ═══════════════════════════════════════════════════════
  Widget _buildTotalsCard(
    BuildContext context,
    PurchaseFormState state,
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              children: [
                _summaryRow(
                  theme,
                  'purchases.subtotal'.tr(),
                  cs.format(state.subtotalCents.toBigInt().toInt()),
                ),
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
                _summaryRow(
                  theme,
                  'purchases.tax'.tr(),
                  cs.format(state.taxCents.toBigInt().toInt()),
                ),
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
                top: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'purchases.total'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  cs.format(state.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    ThemeData theme,
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
    TextStyle? labelStyle,
  }) {
    final cs = theme.colorScheme;
    final style = labelStyle ?? theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: style?.copyWith(color: isBold ? null : cs.onSurfaceVariant),
        ),
        Text(
          value,
          style:
              (isBold
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    color: valueColor,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // BOTTOM BAR (Premium)
  // ═══════════════════════════════════════════════════════
  Widget _buildBottomBar(
    BuildContext context,
    PurchaseFormState state,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                      LucideIcons.shoppingCart,
                      size: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${state.items.length} ${'purchases.items_count'.tr()}  •  ${state.totalQuantity} ${'purchases.pieces_count'.tr()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  cs.format(state.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: state.isSubmitting
                  ? null
                  : () {
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
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
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

  void _showAddItemSheet(BuildContext context, {Product? initialProduct}) {
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
          BlocProvider(
            create: (_) => sl<CategoriesBloc>()..add(const LoadCategories()),
          ),
        ],
        child: _AddItemSheet(
          initialProduct: initialProduct,
          onItemAdded: (product, variant, quantity, unitCost) {
            context.read<PurchaseFormBloc>().add(
              PurchaseLineItemAdded(
                product: product,
                variant: variant,
                quantity: quantity,
                unitCostCents: unitCost,
              ),
            );
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
        onSave:
            (
              qty,
              cost,
              discount,
              expiry,
              clearExpiry,
              sellPriceCents,
              wholesalePriceCents,
            ) {
              context.read<PurchaseFormBloc>().add(
                PurchaseLineItemUpdated(
                  tempId: item.tempId,
                  quantity: qty,
                  unitCostCents: cost,
                  discountCents: discount,
                  expiryDate: expiry,
                  clearExpiry: clearExpiry,
                  newSellPriceCents: sellPriceCents,
                  newWholesalePriceCents: wholesalePriceCents,
                ),
              );
              Navigator.pop(sheetCtx);
            },
      ),
    );
  }

  void _showCheckoutDialog(
    BuildContext context,
    PurchaseFormState state,
  ) async {
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'suppliers.empty'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
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
                                color: colorScheme.onPrimaryContainer,
                              ),
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
    final hasVariantInfo =
        item.colorName != null ||
        item.sizeName != null ||
        item.variant?.sku != null;

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
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${index + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color:
                                          _parseHexColor(item.colorHex) ??
                                          cs.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: cs.outline.withValues(
                                          alpha: 0.3,
                                        ),
                                        width: 0.5,
                                      ),
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
                    '${currencyService.format(item.unitCostCents.toBigInt().toInt())} × ${localizedQuantity(item.quantity, item.product.measurementType)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (showItemDiscount && item.discountCents > Decimal.zero)
                    Text(
                      '${'purchases.discount'.tr()}: -${currencyService.format(item.discountCents.toBigInt().toInt())}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.tertiary,
                      ),
                    ),
                  if (item.expiryDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.clock,
                            size: 12,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat.yMMMd().format(item.expiryDate!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange,
                              fontSize: 11,
                            ),
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
                    onTap: item.quantity > item.product.quantityScale
                        ? () => onQuantityChanged(
                            item.quantity - item.product.quantityScale,
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        LucideIcons.minus,
                        size: 14,
                        color: item.quantity > item.product.quantityScale
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      localizedQuantity(
                        item.quantity,
                        item.product.measurementType,
                      ),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onQuantityChanged(
                      item.quantity + item.product.quantityScale,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        LucideIcons.plus,
                        size: 14,
                        color: cs.onSurface,
                      ),
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
                    fontWeight: FontWeight.bold,
                  ),
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
          if (icon != null) ...[icon!, const SizedBox(width: 4)],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w500,
              fontSize: 10,
            ),
          ),
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
  final void Function(
    int qty,
    Decimal cost,
    Decimal? discount,
    DateTime? expiry,
    bool clearExpiry,
    Decimal? sellPriceCents,
    Decimal? wholesalePriceCents,
  )
  onSave;

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
  late MeasurementUnit _quantityUnit;
  late final TextEditingController _costCtrl;
  late final TextEditingController _sellPriceCtrl;
  late final TextEditingController _wholesalePriceCtrl;
  late final TextEditingController _discountPercentCtrl;
  late final TextEditingController _discountFixedCtrl;
  DateTime? _expiryDate;
  bool _updatingDiscount = false;
  bool _saving = false;

  /// Trigger a rebuild so the totals preview stays in sync.
  void _rebuildTotals() {
    if (mounted) setState(() {});
  }

  void _onSubtotalChanged() {
    if (_updatingDiscount) return;

    // If user entered a percent, fixed amount should track subtotal.
    if (_discountPercentCtrl.text.trim().isNotEmpty) {
      _syncFromPercent();
      return;
    }

    // If user entered a fixed amount, percent should track subtotal.
    if (_discountFixedCtrl.text.trim().isNotEmpty) {
      _syncFromFixed();
    }
  }

  @override
  void initState() {
    super.initState();
    _quantityUnit = widget.item.product.measurement.majorUnit;
    _qtyCtrl = TextEditingController(
      text: MeasuredQuantity.editableValue(widget.item.quantity, _quantityUnit),
    );
    _costCtrl = TextEditingController(
      text: (widget.item.unitCostCents.toBigInt().toInt() / 100)
          .toStringAsFixed(2),
    );

    // Use previously-set new prices if available, otherwise fall back to variant/product prices
    final sellPriceCents =
        widget.item.newSellPriceCents?.toBigInt().toInt() ??
        widget.item.variant?.priceCents.toBigInt().toInt() ??
        widget.item.product.priceCents.toBigInt().toInt();
    final wholesaleCents =
        widget.item.newWholesalePriceCents?.toBigInt().toInt() ??
        widget.item.variant?.wholesalePriceCents?.toBigInt().toInt() ??
        widget.item.product.wholesalePriceCents?.toBigInt().toInt();
    _sellPriceCtrl = TextEditingController(
      text: (sellPriceCents / 100).toStringAsFixed(2),
    );
    _wholesalePriceCtrl = TextEditingController(
      text: wholesaleCents == null
          ? ''
          : (wholesaleCents / 100).toStringAsFixed(2),
    );

    final discCents = widget.item.discountCents.toBigInt().toInt();
    final subtotalCents = MeasuredAmount.cents(
      unitCents: widget.item.unitCostCents.toBigInt().toInt(),
      quantity: widget.item.quantity,
      quantityScale: widget.item.product.quantityScale,
    );
    _discountFixedCtrl = TextEditingController(
      text: discCents > 0 ? (discCents / 100).toStringAsFixed(2) : '',
    );
    _discountPercentCtrl = TextEditingController(
      text: discCents > 0 && subtotalCents > 0
          ? ((discCents / subtotalCents) * 100).toStringAsFixed(2)
          : '',
    );

    _expiryDate = widget.item.expiryDate;

    _discountPercentCtrl.addListener(_syncFromPercent);
    _discountFixedCtrl.addListener(_syncFromFixed);

    // Keep discount values reactive when subtotal changes.
    _qtyCtrl.addListener(_onSubtotalChanged);
    _costCtrl.addListener(_onSubtotalChanged);

    // Rebuild totals preview whenever any input changes.
    _qtyCtrl.addListener(_rebuildTotals);
    _costCtrl.addListener(_rebuildTotals);
    _discountPercentCtrl.addListener(_rebuildTotals);
    _discountFixedCtrl.addListener(_rebuildTotals);
    // Keep below-cost warning reactive to sell/wholesale price changes.
    _sellPriceCtrl.addListener(_rebuildTotals);
    _wholesalePriceCtrl.addListener(_rebuildTotals);
  }

  int get _currentSubtotalCents {
    final costVal = double.tryParse(_costCtrl.text) ?? 0;
    return MeasuredAmount.cents(
      unitCents: (costVal * 100).round(),
      quantity: _storedQuantity,
      quantityScale: widget.item.product.quantityScale,
    );
  }

  int get _storedQuantity {
    try {
      final parsed = MeasuredQuantity.parseToStored(
        _qtyCtrl.text,
        _quantityUnit,
      );
      return parsed > 0 ? parsed : _quantityUnit.internalFactor;
    } on FormatException {
      return _quantityUnit.internalFactor;
    }
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
    _qtyCtrl.removeListener(_onSubtotalChanged);
    _costCtrl.removeListener(_onSubtotalChanged);
    _qtyCtrl.removeListener(_rebuildTotals);
    _costCtrl.removeListener(_rebuildTotals);
    _discountPercentCtrl.removeListener(_rebuildTotals);
    _discountFixedCtrl.removeListener(_rebuildTotals);
    _sellPriceCtrl.removeListener(_rebuildTotals);
    _wholesalePriceCtrl.removeListener(_rebuildTotals);
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
    final oldCostCents = item.originalCostCents;
    final sellPriceCents = item.originalPriceCents;
    final oldWholesaleCents = item.originalWholesalePriceCents;
    final currentStock =
        item.variant?.stockQuantity ?? item.product.stockQuantity;

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
                  width: 40,
                  height: 4,
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
                    child: const Icon(
                      LucideIcons.edit3,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.product.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color:
                                              _parseHexColor(item.colorHex) ??
                                              cs.tertiary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        item.colorName!,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                if (item.sizeName != null)
                                  Text(
                                    item.sizeName!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
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
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Wrap(
                        spacing: 0,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _InfoCell(
                                    icon: LucideIcons.warehouse,
                                    label: 'purchases.current_stock'.tr(),
                                    value: localizedQuantity(
                                      currentStock,
                                      item.product.measurementType,
                                    ),
                                    iconColor: cs.primary,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 36,
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                Expanded(
                                  child: _InfoCell(
                                    icon: LucideIcons.history,
                                    label: 'purchases.old_cost'.tr(),
                                    value: widget.currencyService.format(
                                      oldCostCents,
                                    ),
                                    iconColor: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _InfoCell(
                                    icon: LucideIcons.tag,
                                    label: 'purchases.old_sell_price'.tr(),
                                    value: widget.currencyService.format(
                                      sellPriceCents,
                                    ),
                                    iconColor: cs.tertiary,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 36,
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                                Expanded(
                                  child: _InfoCell(
                                    icon: LucideIcons.badgePercent,
                                    label: 'purchases.old_wholesale_price'.tr(),
                                    value: oldWholesaleCents != null
                                        ? widget.currencyService.format(
                                            oldWholesaleCents,
                                          )
                                        : '-',
                                    iconColor: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Purchase Tax Rate (read-only info) ──
                    if (item.product.isTaxable &&
                        item.product.purchaseTaxRateBps > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: cs.tertiary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.percent,
                              size: 16,
                              color: cs.tertiary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'purchases.product_tax_rate'.tr(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${(item.product.purchaseTaxRateBps / 100).toStringAsFixed(2)}%',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.tertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // ── Quantity + New Cost ──
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.,]'),
                              ),
                            ],
                            onTap: () => selectAllText(_qtyCtrl),
                            decoration: InputDecoration(
                              labelText: 'purchases.quantity'.tr(),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(
                                LucideIcons.hash,
                                size: 18,
                              ),
                              suffixIcon:
                                  item.product.measurement.minorUnit == null
                                  ? null
                                  : DropdownButtonHideUnderline(
                                      child: DropdownButton<MeasurementUnit>(
                                        value: _quantityUnit,
                                        isDense: true,
                                        items: item
                                            .product
                                            .measurement
                                            .inputUnits
                                            .map(
                                              (unit) => DropdownMenuItem(
                                                value: unit,
                                                child: Text(
                                                  'measurement.units.${unit.dbValue}'
                                                      .tr(),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (unit) {
                                          if (unit == null) return;
                                          final stored = _storedQuantity;
                                          setState(() {
                                            _quantityUnit = unit;
                                            _qtyCtrl.text =
                                                MeasuredQuantity.editableValue(
                                                  stored,
                                                  unit,
                                                );
                                          });
                                        },
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _costCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.]'),
                              ),
                            ],
                            onTap: () => selectAllText(_costCtrl),
                            decoration: InputDecoration(
                              labelText: 'purchases.new_cost'.tr(),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(
                                LucideIcons.coins,
                                size: 18,
                              ),
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
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.]'),
                              ),
                            ],
                            onTap: () => selectAllText(_sellPriceCtrl),
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
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.]'),
                              ),
                            ],
                            onTap: () => selectAllText(_wholesalePriceCtrl),
                            decoration: InputDecoration(
                              labelText: 'purchases.new_wholesale_price'.tr(),
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(
                                LucideIcons.badgePercent,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // ── Below-cost warning (sell or wholesale price < cost) ──
                    Builder(
                      builder: (context) {
                        final costVal = double.tryParse(_costCtrl.text) ?? 0;
                        final sellVal =
                            double.tryParse(_sellPriceCtrl.text) ?? 0;
                        final wholesaleVal =
                            double.tryParse(_wholesalePriceCtrl.text) ?? 0;
                        final sellBelow =
                            sellVal > 0 && costVal > 0 && sellVal < costVal;
                        final wholesaleBelow =
                            wholesaleVal > 0 &&
                            costVal > 0 &&
                            wholesaleVal < costVal;
                        if (!sellBelow && !wholesaleBelow) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer.withValues(
                                alpha: 0.35,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: cs.tertiary.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.alertTriangle,
                                  size: 16,
                                  color: cs.tertiary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'products.warning_price_below_cost'.tr(),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.tertiary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // ── Discount (% and fixed, auto-sync) ──
                    if (widget.discountMode == DiscountMode.perItem) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _discountPercentCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d.]'),
                                ),
                              ],
                              onTap: () => selectAllText(_discountPercentCtrl),
                              decoration: InputDecoration(
                                labelText: 'purchases.discount_percent'.tr(),
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(
                                  LucideIcons.percent,
                                  size: 18,
                                ),
                                suffixText: '%',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _discountFixedCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[\d.]'),
                                ),
                              ],
                              onTap: () => selectAllText(_discountFixedCtrl),
                              decoration: InputDecoration(
                                labelText: 'purchases.discount_fixed'.tr(),
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(
                                  LucideIcons.coins,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // ── Expiry Date ──
                    // Required when the product is batch_expiry-tracked
                    // (Phase C — two-layer inventory architecture). The
                    // border, icon, label and a help row below switch to the
                    // error palette until the user picks a date, and the
                    // Save button is disabled in the same condition.
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final requiresExpiry =
                            widget.item.product.inventoryTrackingType ==
                            'batch_expiry';
                        final missingRequired =
                            requiresExpiry && _expiryDate == null;
                        final borderColor = missingRequired
                            ? cs.error
                            : (_expiryDate != null
                                  ? Colors.orange
                                  : cs.outline);
                        final iconColor = missingRequired
                            ? cs.error
                            : (_expiryDate != null
                                  ? Colors.orange
                                  : cs.onSurfaceVariant);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _expiryDate ??
                                      DateTime.now().add(
                                        const Duration(days: 180),
                                      ),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 3650),
                                  ),
                                );
                                if (date != null) {
                                  setState(() => _expiryDate = date);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: borderColor),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      LucideIcons.calendarClock,
                                      size: 18,
                                      color: iconColor,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _expiryDate != null
                                            ? '${'purchases.expiry'.tr()}: ${DateFormat.yMMMd().format(_expiryDate!)}'
                                            : (requiresExpiry
                                                  ? 'purchases.expiry_required'
                                                        .tr()
                                                  : 'purchases.set_expiry'
                                                        .tr()),
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: missingRequired
                                                  ? cs.error
                                                  : (_expiryDate != null
                                                        ? null
                                                        : cs.onSurfaceVariant),
                                              fontWeight: missingRequired
                                                  ? FontWeight.w600
                                                  : null,
                                            ),
                                      ),
                                    ),
                                    if (_expiryDate != null && !requiresExpiry)
                                      InkWell(
                                        onTap: () =>
                                            setState(() => _expiryDate = null),
                                        child: Icon(
                                          LucideIcons.x,
                                          size: 16,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (missingRequired) ...[
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    LucideIcons.alertTriangle,
                                    size: 14,
                                    color: cs.error,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'purchases.expiry_required_help'.tr(),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: cs.error),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ── Totals Preview (before & after tax) ──
              Builder(
                builder: (context) {
                  final qty = _storedQuantity;
                  final costVal = double.tryParse(_costCtrl.text) ?? 0;
                  final costCents = (costVal * 100).round();
                  final subtotalCents = MeasuredAmount.cents(
                    unitCents: costCents,
                    quantity: qty,
                    quantityScale: item.product.quantityScale,
                  );
                  final discVal = double.tryParse(_discountFixedCtrl.text) ?? 0;
                  final discCents = (discVal * 100).round();
                  final netCents = subtotalCents - discCents;
                  final product = widget.item.product;
                  final taxBps = product.isTaxable
                      ? product.purchaseTaxRateBps
                      : 0;
                  final taxCents = taxBps > 0 && netCents > 0
                      ? ((netCents * taxBps) / 10000).round()
                      : 0;
                  final totalAfterTax = netCents + taxCents;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'purchases.subtotal'.tr(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              widget.currencyService.format(
                                subtotalCents > 0 ? subtotalCents : 0,
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (discCents > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'purchases.discount'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '- ${widget.currencyService.format(discCents)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (taxCents > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'purchases.tax'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '+${widget.currencyService.format(taxCents)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'purchases.total'.tr(),
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              widget.currencyService.format(
                                totalAfterTax > 0 ? totalAfterTax : 0,
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
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
                    child: Builder(
                      builder: (context) {
                        final requiresExpiry =
                            widget.item.product.inventoryTrackingType ==
                            'batch_expiry';
                        final missingRequired =
                            requiresExpiry && _expiryDate == null;
                        return FilledButton.icon(
                          icon: const Icon(LucideIcons.check, size: 18),
                          label: Text('common.save'.tr()),
                          onPressed: _saving || missingRequired
                              ? null
                              : () {
                                  setState(() => _saving = true);
                                  try {
                                    final qty = _storedQuantity;
                                    final costVal =
                                        double.tryParse(_costCtrl.text) ?? 0;
                                    final costCents = Decimal.fromInt(
                                      (costVal * 100).round(),
                                    );
                                    Decimal? discountCents;
                                    if (widget.discountMode ==
                                        DiscountMode.perItem) {
                                      final discVal =
                                          double.tryParse(
                                            _discountFixedCtrl.text,
                                          ) ??
                                          0;
                                      discountCents = Decimal.fromInt(
                                        (discVal * 100).round(),
                                      );
                                    }

                                    final sellVal =
                                        double.tryParse(_sellPriceCtrl.text) ??
                                        0;
                                    final sellCents = Decimal.fromInt(
                                      (sellVal * 100).round(),
                                    );
                                    final wholesaleVal = double.tryParse(
                                      _wholesalePriceCtrl.text,
                                    );
                                    final wholesaleCents = wholesaleVal == null
                                        ? null
                                        : Decimal.fromInt(
                                            (wholesaleVal * 100).round(),
                                          );

                                    widget.onSave(
                                      qty,
                                      costCents,
                                      discountCents,
                                      _expiryDate,
                                      _expiryDate == null &&
                                          widget.item.expiryDate != null,
                                      sellCents,
                                      wholesaleCents,
                                    );
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(e.toString()),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _saving = false);
                                    }
                                  }
                                },
                        );
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
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
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
  late final TextEditingController _paidCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _discountPercentCtrl;
  late final TextEditingController _discountFixedCtrl;
  bool _updatingDiscount = false;
  bool _hasHydratedFromBloc = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<PurchaseFormBloc>().state;
    _paidCtrl = TextEditingController(
      text: state.paidAmountCents > Decimal.zero
          ? (state.paidAmountCents.toBigInt().toInt() / 100).toStringAsFixed(2)
          : '',
    );
    _notesCtrl = TextEditingController(text: state.notes ?? '');

    final discCents = state.invoiceDiscountCents.toBigInt().toInt();
    final subtotalCents = state.subtotalCents.toBigInt().toInt();
    _discountFixedCtrl = TextEditingController(
      text: discCents > 0 ? (discCents / 100).toStringAsFixed(2) : '',
    );
    _discountPercentCtrl = TextEditingController(
      text: discCents > 0 && subtotalCents > 0
          ? ((discCents / subtotalCents) * 100).toStringAsFixed(2)
          : '',
    );

    _discountPercentCtrl.addListener(_syncDiscountFromPercent);
    _discountFixedCtrl.addListener(_syncDiscountFromFixed);
  }

  void _hydrateControllersIfNeeded(PurchaseFormState state) {
    // If user is currently typing, don't overwrite.
    final focused = FocusManager.instance.primaryFocus;
    final isEditingText = focused?.context?.widget is EditableText;
    if (isEditingText) return;

    // Initial hydration for edit flow: once bloc loads async data.
    if (!_hasHydratedFromBloc) {
      final paidText = state.paidAmountCents > Decimal.zero
          ? (state.paidAmountCents.toBigInt().toInt() / 100).toStringAsFixed(2)
          : '';
      final notesText = state.notes ?? '';

      if (_paidCtrl.text != paidText) _paidCtrl.text = paidText;
      if (_notesCtrl.text != notesText) _notesCtrl.text = notesText;

      // Fixed cents is the single source of truth; the percent shown is a
      // pure display helper derived from it via the central converter.
      final discCents = state.effectiveInvoiceDiscountCents.toBigInt().toInt();
      final subtotalCents = state.subtotalCents.toBigInt().toInt();
      final fixedText = discCents > 0
          ? (discCents / 100).toStringAsFixed(2)
          : '';
      final pct = sl<DiscountConverter>().percentFromFixed(
        subtotalCents: subtotalCents,
        fixedCents: discCents,
      );
      final pctText = pct == Decimal.zero ? '' : pct.toString();

      if (_discountFixedCtrl.text != fixedText) {
        _discountFixedCtrl.text = fixedText;
      }
      if (_discountPercentCtrl.text != pctText) {
        _discountPercentCtrl.text = pctText;
      }

      _hasHydratedFromBloc = true;
    }
  }

  void _syncDiscountFromPercent() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    // Percent → fixed handled by the central converter so this screen can
    // never drift from the sales/line-edit discount helpers.
    final pct =
        Decimal.tryParse(_discountPercentCtrl.text.trim()) ?? Decimal.zero;
    final sub = context
        .read<PurchaseFormBloc>()
        .state
        .subtotalCents
        .toBigInt()
        .toInt();
    final cents = sl<DiscountConverter>().fixedFromPercent(
      subtotalCents: sub,
      percent: pct,
    );
    _discountFixedCtrl.text = cents > 0 ? (cents / 100).toStringAsFixed(2) : '';
    _applyInvoiceDiscount();
    _updatingDiscount = false;
  }

  void _syncDiscountFromFixed() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    final fixedVal =
        Decimal.tryParse(_discountFixedCtrl.text.trim()) ?? Decimal.zero;
    final fixedCents = (fixedVal * Decimal.fromInt(100))
        .round()
        .toBigInt()
        .toInt();
    final sub = context
        .read<PurchaseFormBloc>()
        .state
        .subtotalCents
        .toBigInt()
        .toInt();
    final pct = sl<DiscountConverter>().percentFromFixed(
      subtotalCents: sub,
      fixedCents: fixedCents,
    );
    _discountPercentCtrl.text = pct == Decimal.zero ? '' : pct.toString();
    _applyInvoiceDiscount();
    _updatingDiscount = false;
  }

  void _applyInvoiceDiscount() {
    // The fixed-cents amount is the single source of truth that reaches the
    // bloc. The percent field is display-only and never re-derives the
    // amount, so a fixed `405.00` input stays `405.00` (no `405.31` drift).
    final fixedVal = double.tryParse(_discountFixedCtrl.text) ?? 0;
    final cents = (fixedVal * 100).round();
    context.read<PurchaseFormBloc>().add(
      PurchaseInvoiceDiscountChanged(Decimal.fromInt(cents)),
    );
  }

  @override
  void dispose() {
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
        _hydrateControllersIfNeeded(state);
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
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
                          width: 40,
                          height: 4,
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
                                colors: [
                                  cs.primary,
                                  cs.primary.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              LucideIcons.shoppingBag,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'purchases.checkout_title'.tr(),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
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
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: Text(
                                    state.supplierName ??
                                        'purchases.select_supplier'.tr(),
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: state.supplierName != null
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                      color: state.supplierName != null
                                          ? null
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Icon(
                                  LucideIcons.chevronDown,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // ── Supplier Balance Info ──
                      if (state.supplierId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 8),
                          child: _SupplierBalanceInfo(
                            supplierId: state.supplierId!,
                            invoiceTotalCents: state.totalCents
                                .toBigInt()
                                .toInt(),
                            paidAmountCents: state.paidAmountCents
                                .toBigInt()
                                .toInt(),
                            paymentMethod: state.paymentMethod,
                            currencyService: widget.currencyService,
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
                              avatar: Icon(
                                _paymentMethodIcon(method),
                                size: 16,
                              ),
                              selectedColor: cs.primaryContainer,
                              showCheckmark: false,
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── Cheque due date (only for cheque) ──
                      if (state.paymentMethod ==
                          PurchasePaymentMethod.cheque) ...[
                        _buildCheckoutSection(
                          theme: theme,
                          cs: cs,
                          icon: LucideIcons.calendar,
                          title: 'purchases.cheque_due_date'.tr(),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    state.dueDate ??
                                    DateTime.now().add(
                                      const Duration(days: 30),
                                    ),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                              if (picked != null && context.mounted) {
                                context.read<PurchaseFormBloc>().add(
                                  PurchaseDueDateChanged(picked),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: cs.outlineVariant),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.calendar,
                                    size: 18,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      state.dueDate != null
                                          ? '${state.dueDate!.year}-${state.dueDate!.month.toString().padLeft(2, '0')}-${state.dueDate!.day.toString().padLeft(2, '0')}'
                                          : 'purchases.select_due_date'.tr(),
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            color: state.dueDate != null
                                                ? null
                                                : cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  Icon(
                                    LucideIcons.chevronDown,
                                    size: 18,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // ── Payment method info message ──
                      Builder(
                        builder: (_) {
                          final infoKey = switch (state.paymentMethod) {
                            PurchasePaymentMethod.cash =>
                              'purchases.balance_explain_cash',
                            PurchasePaymentMethod.card =>
                              'purchases.balance_explain_card',
                            PurchasePaymentMethod.credit =>
                              'purchases.balance_explain_credit',
                            PurchasePaymentMethod.cheque =>
                              'purchases.balance_explain_cheque',
                            PurchasePaymentMethod.purchaseOrder =>
                              'purchases.balance_explain_po',
                          };
                          final isPo =
                              state.paymentMethod ==
                              PurchasePaymentMethod.purchaseOrder;
                          final isCredit =
                              state.paymentMethod ==
                              PurchasePaymentMethod.credit;
                          final containerColor = isPo
                              ? cs.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                )
                              : cs.tertiaryContainer.withValues(alpha: 0.3);
                          final borderColor = isPo
                              ? cs.outlineVariant.withValues(alpha: 0.3)
                              : cs.tertiary.withValues(alpha: 0.3);
                          final iconColor = isPo
                              ? cs.onSurfaceVariant
                              : cs.tertiary;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: containerColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        LucideIcons.info,
                                        size: 16,
                                        color: iconColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          infoKey.tr(),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                                height: 1.4,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Add Payment button for credit purchases
                                if (isCredit && state.supplierId != null) ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        // Navigate to supplier profile screen where payment can be made
                                        context.push(
                                          '/suppliers/${state.supplierId}',
                                        );
                                      },
                                      icon: const Icon(
                                        LucideIcons.banknote,
                                        size: 18,
                                      ),
                                      label: Text('purchases.add_payment'.tr()),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        side: BorderSide(color: cs.primary),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      // ── Tax (read-only, sum of line item taxes) ──
                      if (state.taxCents > Decimal.zero)
                        _buildCheckoutSection(
                          theme: theme,
                          cs: cs,
                          icon: LucideIcons.percent,
                          title: 'purchases.tax'.tr(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.receipt,
                                  size: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.currencyService.format(
                                    state.taxCents.toBigInt().toInt(),
                                  ),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'purchases.tax_from_products'.tr(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // ── Invoice Discount (% and fixed) ──
                      if (state.discountMode == DiscountMode.invoice) ...[
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d.]'),
                                    ),
                                  ],
                                  onTap: () =>
                                      selectAllText(_discountPercentCtrl),
                                  decoration: InputDecoration(
                                    labelText: 'purchases.discount_percent'
                                        .tr(),
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[\d.]'),
                                    ),
                                  ],
                                  onTap: () =>
                                      selectAllText(_discountFixedCtrl),
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
                      // ── Paid Amount (only for cash) ──
                      if (state.paymentMethod ==
                          PurchasePaymentMethod.cash) ...[
                        _buildCheckoutSection(
                          theme: theme,
                          cs: cs,
                          icon: LucideIcons.banknote,
                          title: 'purchases.paid_amount'.tr(),
                          child: TextField(
                            controller: _paidCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d.]'),
                              ),
                            ],
                            onTap: () => selectAllText(_paidCtrl),
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText:
                                  (state.totalCents.toBigInt().toInt() / 100)
                                      .toStringAsFixed(2),
                              isDense: true,
                            ),
                            onChanged: (v) {
                              final val = double.tryParse(v) ?? 0;
                              context.read<PurchaseFormBloc>().add(
                                PurchasePaidAmountChanged(
                                  Decimal.fromInt((val * 100).round()),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        // ── Remaining / Change display ──
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: state.changeCents > Decimal.zero
                                ? Colors.green.withValues(alpha: 0.08)
                                : state.remainingCents > Decimal.zero
                                ? cs.errorContainer.withValues(alpha: 0.3)
                                : cs.primaryContainer.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: state.changeCents > Decimal.zero
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : state.remainingCents > Decimal.zero
                                  ? cs.error.withValues(alpha: 0.2)
                                  : cs.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              // Underpayment warning (cash with supplier selected)
                              if (state.remainingCents > Decimal.zero &&
                                  state.supplierId != null)
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          LucideIcons.alertTriangle,
                                          size: 16,
                                          color: cs.error,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'purchases.underpayment_warning'
                                                .tr(),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: cs.error),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _checkoutRow(
                                      theme,
                                      'purchases.remaining'.tr(),
                                      widget.currencyService.format(
                                        state.remainingCents.toBigInt().toInt(),
                                      ),
                                      isBold: true,
                                      valueColor: cs.error,
                                    ),
                                  ],
                                )
                              // Underpayment without supplier (walk-in)
                              else if (state.remainingCents > Decimal.zero)
                                _checkoutRow(
                                  theme,
                                  'purchases.remaining'.tr(),
                                  widget.currencyService.format(
                                    state.remainingCents.toBigInt().toInt(),
                                  ),
                                  isBold: true,
                                  valueColor: cs.error,
                                ),
                              // Overpayment with supplier - show options
                              if (state.changeCents > Decimal.zero &&
                                  state.supplierId != null) ...[
                                _checkoutRow(
                                  theme,
                                  'purchases.overpayment_amount'.tr(),
                                  widget.currencyService.format(
                                    state.changeCents.toBigInt().toInt(),
                                  ),
                                  isBold: true,
                                  valueColor: Colors.green,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'purchases.overpayment_handling'.tr(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ChoiceChip(
                                        label: Text(
                                          'purchases.return_change'.tr(),
                                        ),
                                        selected:
                                            state.overpaymentHandling ==
                                            OverpaymentHandling.returnChange,
                                        onSelected: (_) => context
                                            .read<PurchaseFormBloc>()
                                            .add(
                                              const PurchaseOverpaymentHandlingChanged(
                                                OverpaymentHandling
                                                    .returnChange,
                                              ),
                                            ),
                                        avatar: const Icon(
                                          LucideIcons.banknote,
                                          size: 16,
                                        ),
                                        selectedColor: cs.primaryContainer,
                                        showCheckmark: false,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ChoiceChip(
                                        label: Text(
                                          'purchases.add_to_balance'.tr(),
                                        ),
                                        selected:
                                            state.overpaymentHandling ==
                                            OverpaymentHandling.addToBalance,
                                        onSelected: (_) => context
                                            .read<PurchaseFormBloc>()
                                            .add(
                                              const PurchaseOverpaymentHandlingChanged(
                                                OverpaymentHandling
                                                    .addToBalance,
                                              ),
                                            ),
                                        avatar: const Icon(
                                          LucideIcons.wallet,
                                          size: 16,
                                        ),
                                        selectedColor: cs.primaryContainer,
                                        showCheckmark: false,
                                      ),
                                    ),
                                  ],
                                ),
                              ]
                              // Overpayment without supplier (walk-in) - just show change
                              else if (state.changeCents > Decimal.zero)
                                _checkoutRow(
                                  theme,
                                  'purchases.change'.tr(),
                                  widget.currencyService.format(
                                    state.changeCents.toBigInt().toInt(),
                                  ),
                                  isBold: true,
                                  valueColor: Colors.green,
                                ),
                              if (state.remainingCents == Decimal.zero &&
                                  state.changeCents == Decimal.zero)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      LucideIcons.checkCircle,
                                      size: 16,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'purchases.fully_paid'.tr(),
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            color: cs.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
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
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
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
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            _checkoutRow(
                              theme,
                              'purchases.subtotal'.tr(),
                              widget.currencyService.format(
                                state.subtotalCents.toBigInt().toInt(),
                              ),
                            ),
                            if (state.totalDiscountCents > Decimal.zero) ...[
                              const SizedBox(height: 8),
                              _checkoutRow(
                                theme,
                                'purchases.discount'.tr(),
                                '- ${widget.currencyService.format(state.totalDiscountCents.toBigInt().toInt())}',
                                valueColor: cs.tertiary,
                              ),
                            ],
                            if (state.taxCents > Decimal.zero) ...[
                              const SizedBox(height: 8),
                              _checkoutRow(
                                theme,
                                'purchases.tax'.tr(),
                                widget.currencyService.format(
                                  state.taxCents.toBigInt().toInt(),
                                ),
                              ),
                            ],
                            Divider(
                              height: 20,
                              color: cs.outlineVariant.withValues(alpha: 0.5),
                            ),
                            _checkoutRow(
                              theme,
                              'purchases.total'.tr(),
                              widget.currencyService.format(
                                state.totalCents.toBigInt().toInt(),
                              ),
                              isBold: true,
                              valueColor: cs.primary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
                // ── Bottom Actions ──
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: Border(
                      top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
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
                          child: Builder(
                            builder: (ctx) {
                              final cashInsufficient =
                                  state.paymentMethod ==
                                      PurchasePaymentMethod.cash &&
                                  state.paidAmountCents < state.totalCents;
                              final chequeNoDueDate =
                                  state.paymentMethod ==
                                      PurchasePaymentMethod.cheque &&
                                  state.dueDate == null;
                              final canConfirm =
                                  state.supplierId != null &&
                                  !state.isSubmitting &&
                                  !cashInsufficient &&
                                  !chequeNoDueDate;
                              return FilledButton.icon(
                                onPressed: canConfirm ? widget.onConfirm : null,
                                icon: state.isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(LucideIcons.check, size: 18),
                                label: Text('purchases.confirm_save'.tr()),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              );
                            },
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
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _checkoutRow(
    ThemeData theme,
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style:
              (isBold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    color: isBold ? null : theme.colorScheme.onSurfaceVariant,
                  ),
        ),
        Text(
          value,
          style:
              (isBold
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    color: valueColor,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                  ),
        ),
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
// SUPPLIER BALANCE INFO (inline widget in checkout)
// ═══════════════════════════════════════════════════════
class _SupplierBalanceInfo extends StatelessWidget {
  final int supplierId;
  final int invoiceTotalCents;
  final int paidAmountCents;
  final PurchasePaymentMethod paymentMethod;
  final CurrencyService currencyService;

  const _SupplierBalanceInfo({
    required this.supplierId,
    required this.invoiceTotalCents,
    required this.paidAmountCents,
    required this.paymentMethod,
    required this.currencyService,
  });

  /// Calculate the balance delta based on payment method.
  /// - Cash: balance += (total - paidAmount)  [partial payment possible]
  /// - Card: balance unchanged (fully paid immediately)
  /// - Credit: balance += total (full amount owed to supplier)
  /// - Cheque: balance += total (owed until cheque clears)
  /// - Purchase Order: balance unchanged (just a reminder, no financial impact)
  int _computeBalanceDelta() {
    switch (paymentMethod) {
      case PurchasePaymentMethod.cash:
        return invoiceTotalCents - paidAmountCents;
      case PurchasePaymentMethod.card:
        return 0; // Fully paid immediately
      case PurchasePaymentMethod.credit:
      case PurchasePaymentMethod.cheque:
        return invoiceTotalCents; // Full amount goes to supplier balance
      case PurchasePaymentMethod.purchaseOrder:
        return 0; // No financial impact, just a reminder
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<Supplier?>(
      stream: sl<SupplierRepository>().watchSupplier(supplierId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final supplier = snapshot.data!;
        final currentBalanceCents = supplier.balanceCents.toBigInt().toInt();
        final balanceDelta = _computeBalanceDelta();
        final projectedBalanceCents = currentBalanceCents + balanceDelta;

        final isCurrentPayable = currentBalanceCents > 0;
        final isProjectedPayable = projectedBalanceCents > 0;

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showBalanceDetailDialog(
            context,
            supplier: supplier,
            currentBalanceCents: currentBalanceCents,
            projectedBalanceCents: projectedBalanceCents,
            balanceDelta: balanceDelta,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'purchases.supplier_balance'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currencyService.format(currentBalanceCents),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isCurrentPayable ? cs.error : Colors.green,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.arrowRight,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        currencyService.format(projectedBalanceCents),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isProjectedPayable ? cs.error : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _paymentMethodExplanation() {
    switch (paymentMethod) {
      case PurchasePaymentMethod.cash:
        return 'purchases.balance_explain_cash'.tr();
      case PurchasePaymentMethod.card:
        return 'purchases.balance_explain_card'.tr();
      case PurchasePaymentMethod.credit:
        return 'purchases.balance_explain_credit'.tr();
      case PurchasePaymentMethod.cheque:
        return 'purchases.balance_explain_cheque'.tr();
      case PurchasePaymentMethod.purchaseOrder:
        return 'purchases.balance_explain_po'.tr();
    }
  }

  void _showBalanceDetailDialog(
    BuildContext context, {
    required Supplier supplier,
    required int currentBalanceCents,
    required int projectedBalanceCents,
    required int balanceDelta,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isCurrentPayable = currentBalanceCents > 0;
    final isProjectedPayable = projectedBalanceCents > 0;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.wallet, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'purchases.supplier_account'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Supplier name
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      supplier.name.isNotEmpty
                          ? supplier.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      supplier.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Current balance
            _balanceRow(
              theme: theme,
              cs: cs,
              icon: LucideIcons.wallet,
              label: 'purchases.current_balance'.tr(),
              amount: currencyService.format(currentBalanceCents),
              amountColor: isCurrentPayable ? cs.error : Colors.green,
              subtitle: isCurrentPayable
                  ? 'purchases.balance_you_owe'.tr()
                  : 'purchases.balance_credit'.tr(),
            ),
            const SizedBox(height: 12),
            // Invoice impact
            _balanceRow(
              theme: theme,
              cs: cs,
              icon: LucideIcons.fileText,
              label: 'purchases.this_invoice'.tr(),
              amount: balanceDelta == 0
                  ? currencyService.format(0)
                  : '+ ${currencyService.format(balanceDelta)}',
              amountColor: balanceDelta > 0 ? cs.error : Colors.green,
            ),
            const SizedBox(height: 8),
            // Payment method explanation
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.tertiary.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.info, size: 14, color: cs.tertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _paymentMethodExplanation(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 24,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            // Projected balance
            _balanceRow(
              theme: theme,
              cs: cs,
              icon: LucideIcons.trendingUp,
              label: 'purchases.projected_balance'.tr(),
              amount: currencyService.format(projectedBalanceCents),
              amountColor: isProjectedPayable ? cs.error : Colors.green,
              subtitle: isProjectedPayable
                  ? 'purchases.balance_you_owe'.tr()
                  : 'purchases.balance_credit'.tr(),
              isBold: true,
            ),
          ],
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

  Widget _balanceRow({
    required ThemeData theme,
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required String amount,
    required Color amountColor,
    String? subtitle,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
        Text(
          amount,
          style:
              (isBold
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    color: amountColor,
                  ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// ADD ITEM SHEET (Story 6.6 - Product Selection Dialog)
// ═══════════════════════════════════════════════════════
class _AddItemSheet extends StatefulWidget {
  final Product? initialProduct;
  final void Function(
    Product product,
    ProductVariant? variant,
    int quantity,
    Decimal unitCost,
  )
  onItemAdded;

  const _AddItemSheet({this.initialProduct, required this.onItemAdded});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  Product? _selectedProduct;
  final _searchController = TextEditingController();
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
  }

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
            child:
                FutureBuilder<
                  ({
                    List<ProductVariant> variants,
                    Map<int, String> sizeNameById,
                    Map<int, String?> colorHexById,
                  })
                >(
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
                      sizeNameById[(s as dynamic).id as int] =
                          (s as dynamic).name as String;
                    }
                    final colorHexById = <int, String?>{};
                    for (final c in colors) {
                      colorHexById[(c as dynamic).id as int] =
                          (c as dynamic).hexCode as String?;
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
                      final hex = v.colorId == null
                          ? null
                          : colorHexById[v.colorId!];
                      if (hex != null && hex.trim().isNotEmpty) {
                        distinctColorHexes.add(hex.trim());
                      }
                      final sizeName = v.sizeId == null
                          ? null
                          : sizeNameById[v.sizeId!];
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
                          Text(
                            'colors.title'.tr(),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
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
                                    border: Border.all(
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (sizeList.isNotEmpty) ...[
                          Text(
                            'sizes.title'.tr(),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
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
                        Text(
                          'variants.title'.tr(),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 220,
                          child: ListView.separated(
                            itemCount: variants.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final v = variants[index];
                              final sizeName = v.sizeId == null
                                  ? null
                                  : sizeNameById[v.sizeId!];
                              final hex = v.colorId == null
                                  ? null
                                  : colorHexById[v.colorId!];
                              final shade = _tryParseHexColor(hex);

                              final title = v.sku?.isNotEmpty == true
                                  ? v.sku!
                                  : 'product_form.variant_item_title'.tr(
                                      args: ['${v.id}'],
                                    );

                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (sizeName != null &&
                                        sizeName.trim().isNotEmpty)
                                      Flexible(
                                        child: Text(
                                          sizeName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    if (sizeName != null &&
                                        sizeName.trim().isNotEmpty &&
                                        shade != null)
                                      const SizedBox(width: 8),
                                    if (shade != null)
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: shade,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: colorScheme.outline,
                                          ),
                                        ),
                                      ),
                                    const Spacer(),
                                    Text(
                                      '${'variants.stock'.tr()}: ${localizedQuantity(v.stockQuantity, product.measurementType)}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
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
                width: 40,
                height: 4,
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
                        fontWeight: FontWeight.w600,
                      ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                            onSelected: (_) =>
                                setState(() => _selectedCategoryId = null),
                            showCheckmark: false,
                            selectedColor: cs.primaryContainer,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        ...categories.map(
                          (cat) => Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(
                              label: Text(cat.name),
                              selected: _selectedCategoryId == cat.id,
                              onSelected: (_) => setState(() {
                                _selectedCategoryId =
                                    _selectedCategoryId == cat.id
                                    ? null
                                    : cat.id;
                              }),
                              showCheckmark: false,
                              selectedColor: cs.primaryContainer,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'purchases.select_variant'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
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

    return BlocBuilder<
      VariantPreviewsBloc,
      RealtimeState<Map<int, VariantPreview>>
    >(
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
              if (_selectedCategoryId != null &&
                  p.categoryId != _selectedCategoryId) {
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
                    Icon(
                      LucideIcons.searchX,
                      size: 48,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'purchases.no_products_found'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
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
                final sizeName = (!product.hasVariants
                    ? preview?.sizeName?.trim()
                    : null);
                final colorHex = (!product.hasVariants
                    ? preview?.colorHex?.trim()
                    : null);

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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      product.hasVariants
                          ? LucideIcons.layers
                          : LucideIcons.package,
                      size: 20,
                      color: cs.primary,
                    ),
                  ),
                  title: Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Row(
                    children: [
                      // Identifier group takes the available space so the SKU is
                      // never truncated just to make room for a color dot.
                      Expanded(
                        child: Row(
                          children: [
                            if (product.sku != null) ...[
                              Flexible(
                                child: Text(
                                  'SKU: ${product.sku}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
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
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
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
                          ],
                        ),
                      ),
                      if (!product.hasVariants) ...[
                        const SizedBox(width: 8),
                        Icon(
                          LucideIcons.warehouse,
                          size: 12,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          localizedQuantity(
                            product.stockQuantity,
                            product.measurementType,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          // Display the GROSS supplier reference price so the
                          // picker and the line item start from the same
                          // number as the user-entered cost on the last
                          // purchase. Mirrors the rule used at
                          // `onItemAdded` below and in `_buildVariantSelection`.
                          currencyService.format(
                            (product.lastPurchasePriceCents ??
                                    product.costCents)
                                .toBigInt()
                                .toInt(),
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
                            Icon(
                              LucideIcons.chevronRight,
                              size: 20,
                              color: cs.primary,
                            ),
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
                      // GROSS supplier reference price (see variant branch
                      // below for the rationale).
                      widget.onItemAdded(
                        product,
                        null,
                        product.quantityScale,
                        product.lastPurchasePriceCents ?? product.costCents,
                      );
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
      create: (context) =>
          sl<ProductVariantsBloc>()
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

          return FutureBuilder<
            ({Map<int, String> sizeNameById, Map<int, String?> colorHexById})
          >(
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
                sizeNameById[(s as dynamic).id as int] =
                    (s as dynamic).name as String;
              }

              final colorHexById = <int, String?>{};
              for (final c in colors) {
                colorHexById[(c as dynamic).id as int] =
                    (c as dynamic).hexCode as String?;
              }

              return (sizeNameById: sizeNameById, colorHexById: colorHexById);
            }(),
            builder: (context, snapshot) {
              final sizeNameById =
                  snapshot.data?.sizeNameById ?? const <int, String>{};
              final colorHexById =
                  snapshot.data?.colorHexById ?? const <int, String?>{};

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
                  final sizeName = variant.sizeId == null
                      ? null
                      : sizeNameById[variant.sizeId!];
                  final colorHex = variant.colorId == null
                      ? null
                      : colorHexById[variant.colorId!];
                  final shade = _tryParseHexColor(colorHex);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        LucideIcons.tag,
                        size: 18,
                        color: cs.tertiary,
                      ),
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
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
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
                        Icon(
                          LucideIcons.warehouse,
                          size: 12,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          localizedQuantity(
                            variant.stockQuantity,
                            _selectedProduct!.measurementType,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(LucideIcons.coins, size: 12, color: cs.primary),
                        const SizedBox(width: 4),
                        Text(
                          // Display the GROSS supplier reference price —
                          // see _buildProductList above for the full
                          // rationale. Keeps the picker and the line item
                          // consistent and removes the variant-vs-no-variant
                          // asymmetry the user reported.
                          currencyService.format(
                            (variant.lastPurchasePriceCents ??
                                    variant.costCents)
                                .toBigInt()
                                .toInt(),
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    trailing: Icon(
                      LucideIcons.plusCircle,
                      size: 20,
                      color: cs.primary,
                    ),
                    onTap: () {
                      // GROSS supplier reference price (see picker text above).
                      widget.onItemAdded(
                        _selectedProduct!,
                        variant,
                        _selectedProduct!.quantityScale,
                        variant.lastPurchasePriceCents ?? variant.costCents,
                      );
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
