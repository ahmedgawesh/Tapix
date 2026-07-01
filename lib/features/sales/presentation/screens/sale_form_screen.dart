import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';

import '../../../../core/database/app_database.dart' show Customer, Employee;
import '../../../../core/di/injection_container.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/services/below_cost_sale_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/pricing/discount_converter.dart';
import '../../../../core/services/parties/party_balance_classifier.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../../../core/money/money.dart';
import '../../../../core/pricing/discount.dart';
import '../../../../core/pricing/line_item_pricing_engine.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';
import '../../../products/domain/entities/category_entity.dart';
import '../../../products/domain/repositories/product_color_repository.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../../products/domain/repositories/product_variant_repository.dart';
import '../../../products/domain/repositories/size_repository.dart';
import '../../../products/presentation/bloc/categories_bloc.dart';
import '../../../products/presentation/bloc/categories_event.dart';
import '../../../products/presentation/bloc/products_bloc.dart';
import '../../../products/presentation/bloc/variant_previews_bloc.dart';
import '../../../products/presentation/bloc/product_variants_bloc.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../../customers/presentation/bloc/customers_bloc.dart';
import '../../../employees/domain/repositories/employee_repository.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../bloc/sale_form_bloc.dart';
import '../services/sale_pdf_service.dart';

part 'sale_form_dialogs.dart';

class SaleFormScreen extends StatefulWidget {
  final int? saleId;
  final bool isEditingPosted;
  const SaleFormScreen({super.key, this.saleId, this.isEditingPosted = false});

  @override
  State<SaleFormScreen> createState() => _SaleFormScreenState();
}

class _SaleFormScreenState extends State<SaleFormScreen> {
  final List<SaleFormBloc> _tabs = [];
  final List<TextEditingController> _notesControllers = [];
  int _activeTab = 0;
  late final UserRole _userRole;
  late final int? _userId;

  @override
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    _userRole = (authState is AuthAuthenticated) ? authState.user.role : UserRole.cashier;
    _userId = (authState is AuthAuthenticated) ? authState.user.id : null;
    _addTab(saleId: widget.saleId, isEditingPosted: widget.isEditingPosted);
  }

  SaleFormBloc _createBloc({int? saleId, bool isEditingPosted = false}) {
    final bloc = sl<SaleFormBloc>();
    bloc.currentUserRole = _userRole;
    bloc.currentUserId = _userId;
    
    // Get global settings from AppSettingsBloc
    final appSettingsState = context.read<AppSettingsBloc>().state;
    final settings = appSettingsState.settings;
    final enableTax = settings.enableTaxCalculations;
    // Convert percentage to basis points (e.g., 15% -> 1500 bps)
    final taxRateBps = (settings.defaultSalesTaxRate * 100).round();
    
    bloc.add(SaleFormInitialized(
      saleId: saleId,
      currencyId: 1,
      enableTaxCalculations: enableTax,
      defaultSalesTaxRateBps: taxRateBps,
      allowNegativeStock: settings.allowNegativeStock,
      allowPartialPayments: settings.allowPartialPayments,
      allowDiscounts: settings.allowDiscounts,
      maxDiscountPercent: settings.maxDiscountPercent,
      requireCustomerForSales: settings.requireCustomerForSales,
      enableLoyaltyPoints: settings.enableLoyaltyPoints,
      defaultPaymentMethodStr: settings.defaultPaymentMethod,
      isEditingPosted: isEditingPosted,
    ));
    return bloc;
  }

  void _addTab({int? saleId, bool isEditingPosted = false}) {
    setState(() {
      _tabs.add(_createBloc(saleId: saleId, isEditingPosted: isEditingPosted));
      _notesControllers.add(TextEditingController());
      _activeTab = _tabs.length - 1;
    });
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    setState(() {
      _tabs[index].close();
      _tabs.removeAt(index);
      _notesControllers[index].dispose();
      _notesControllers.removeAt(index);
      if (_activeTab >= _tabs.length) _activeTab = _tabs.length - 1;
    });
  }

  void _switchTab(int index) {
    if (index != _activeTab) setState(() => _activeTab = index);
  }

  bool get _isEditMode => widget.saleId != null;

  @override
  void dispose() {
    for (final bloc in _tabs) { bloc.close(); }
    for (final ctrl in _notesControllers) { ctrl.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _tabs[_activeTab],
      child: _SaleFormView(
        notesCtrl: _notesControllers[_activeTab],
        isEditMode: _isEditMode,
        tabCount: _tabs.length,
        activeTab: _activeTab,
        onAddTab: _isEditMode ? null : () => _addTab(),
        onCloseTab: _isEditMode ? null : _closeTab,
        onSwitchTab: _switchTab,
      ),
    );
  }
}

class _SaleFormView extends StatelessWidget {
  final TextEditingController notesCtrl;
  final bool isEditMode;
  final int tabCount;
  final int activeTab;
  final VoidCallback? onAddTab;
  final void Function(int)? onCloseTab;
  final void Function(int) onSwitchTab;

  const _SaleFormView({
    required this.notesCtrl,
    required this.isEditMode,
    required this.tabCount,
    required this.activeTab,
    this.onAddTab,
    this.onCloseTab,
    required this.onSwitchTab,
  });

  Future<bool> _onWillPop(BuildContext context) async {
    final state = context.read<SaleFormBloc>().state;
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = sl<CurrencyService>();

    return BlocConsumer<SaleFormBloc, SaleFormState>(
      listenWhen: (p, c) =>
          p.isSuccess != c.isSuccess ||
          p.error != c.error ||
          p.belowCostWarning != c.belowCostWarning,
      listener: (context, state) {
        if (state.isSuccess) {
          // Capture state snapshot before navigating away
          final stateSnapshot = state;
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
              final autoPrint = nav.context.read<AppSettingsBloc>().state.settings.autoPrintReceipt;
              if (autoPrint) {
                SalePdfService.printFromFormState(
                  context: nav.context,
                  state: stateSnapshot,
                ).catchError((_) => null);
              }
              _showSaveConfirmationOverlay(nav.context, stateSnapshot);
            }
          });
        }
        if (state.error != null) {
          final quota = parseQuotaError(state.error);
          if (quota != null) {
            showQuotaExceededDialog(
              context,
              isProducts: quota.isProducts,
              limit: quota.limit,
            );
          } else {
            final key = state.error!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(key.tr() == key ? key : key.tr()),
                backgroundColor: cs.error,
              ),
            );
          }
        }
        if (state.belowCostWarning != null && state.belowCostWarning!.isBelowCost) {
          _showBelowCostWarningDialog(context, state.belowCostWarning!);
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
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => _navigateBack(context),
              ),
            title: Text(state.saleId == null ? 'sales.new'.tr() : 'sales.edit'.tr()),
            actions: [
              if (!isEditMode)
                _SaleTabBar(
                  tabCount: tabCount,
                  activeTab: activeTab,
                  onSwitchTab: onSwitchTab,
                  onAddTab: onAddTab,
                  onCloseTab: onCloseTab,
                ),
            ],
          ),
          body: Column(
            children: [
              // Fixed (non-scrolling) top section keeps the product
              // search/scan bar always visible while many items are added.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _invoiceHeaderCard(context, state, theme, cs),
                    const SizedBox(height: 12),
                    _searchBarWithScan(context, theme, cs),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _customerEmployeeRow(context, state, theme, cs),
                    const SizedBox(height: 8),
                    _salespersonModeToggle(context, state, theme, cs),
                    const SizedBox(height: 12),
                    if (state.allowDiscounts) ...[
                      _discountToggle(context, state, theme, cs),
                      const SizedBox(height: 16),
                    ],
                    _itemsHeader(context, state, theme, cs),
                    const SizedBox(height: 8),
                    if (state.items.isEmpty) _emptyHint(theme, cs),
                    ...state.items.map((i) => _itemTile(context, i, state, theme, cs, curr)),
                    const SizedBox(height: 16),
                    _totalsCard(state, theme, cs, curr),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
              _bottomBar(context, state, theme, cs, curr),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _customerEmployeeRow(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) {
    final hasEmp = s.employeeId != null && s.employeeId != 0;
    final isPerInvoice = s.salespersonMode == SalespersonMode.perInvoice;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _compactPickerCard(cs, t,
            bgColor: cs.primaryContainer, icon: LucideIcons.user,
            iconColor: cs.onPrimaryContainer, label: 'sales.customer'.tr(),
            value: s.customerName ?? 'sales.walk_in'.tr(), hasValue: s.customerId != null,
            onClear: s.customerId != null ? () => ctx.read<SaleFormBloc>().add(const SaleCustomerChanged()) : null,
            onTap: () => _showCustomerPicker(ctx)),
        ),
        // Only show invoice-level salesperson when mode is per-invoice
        if (isPerInvoice) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _compactPickerCard(cs, t,
              bgColor: cs.tertiaryContainer, icon: LucideIcons.userCheck,
              iconColor: cs.onTertiaryContainer, label: 'sales.salesperson'.tr(),
              value: hasEmp ? (s.employeeName ?? '') : 'sales.select_salesperson'.tr(), hasValue: hasEmp,
              onClear: hasEmp ? () => ctx.read<SaleFormBloc>().add(const SaleEmployeeChanged()) : null,
              onTap: () => _showEmployeePicker(ctx)),
          ),
        ],
      ],
    );
  }

  Widget _compactPickerCard(ColorScheme cs, ThemeData theme, {
    required Color bgColor, required IconData icon, required Color iconColor,
    required String label, required String value, bool hasValue = false,
    VoidCallback? onClear, required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(width: 32, height: 32,
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: iconColor, size: 16)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant, fontSize: 10)),
              Text(value, style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                color: hasValue ? null : cs.onSurfaceVariant),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(LucideIcons.x, size: 14, color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  Widget _salespersonModeToggle(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) => Row(
    children: [
      Icon(LucideIcons.userCheck, size: 16, color: cs.tertiary), const SizedBox(width: 8),
      Text('sales.salesperson_mode'.tr(), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      const Spacer(),
      SegmentedButton<SalespersonMode>(
        segments: [
          ButtonSegment(value: SalespersonMode.perInvoice, label: Text('sales.per_invoice'.tr(), style: const TextStyle(fontSize: 12))),
          ButtonSegment(value: SalespersonMode.perItem, label: Text('sales.per_item'.tr(), style: const TextStyle(fontSize: 12))),
        ],
        selected: {s.salespersonMode},
        onSelectionChanged: (v) => ctx.read<SaleFormBloc>().add(SaleSalespersonModeChanged(v.first)),
        style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ),
    ],
  );

  // ═══════════════════════════════════════════════════════
  // INVOICE HEADER CARD (Invoice # + Date)
  // ═══════════════════════════════════════════════════════
  Widget _invoiceHeaderCard(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) {
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
                Text('sales.invoice_number'.tr(),
                    style: t.textTheme.labelSmall?.copyWith(
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
                    s.saleNumber ?? '—',
                    style: t.textTheme.titleMedium?.copyWith(
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
                  context: ctx,
                  initialDate: s.saleDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                );
                if (date != null && ctx.mounted) {
                  ctx.read<SaleFormBloc>().add(SaleDateChanged(date));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('sales.invoice_date'.tr(),
                      style: t.textTheme.labelSmall?.copyWith(
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
                            DateFormat.yMd().format(s.saleDate),
                            style: t.textTheme.bodyMedium?.copyWith(
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
  Widget _searchBarWithScan(BuildContext ctx, ThemeData t, ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAddItemSheet(ctx),
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
                      'sales.search_or_scan'.tr(),
                      style: t.textTheme.bodyMedium?.copyWith(
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
          onTap: () => _openBarcodeScanner(ctx),
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
            context.read<SaleFormBloc>().add(SaleLineItemAdded(
                  product: product,
                  variant: variant,
                  quantity: 1,
                  unitPriceCents: variant.priceCents,
                ));
            return;
          }
        }

        // Try product barcode
        final product = await productRepo.findByBarcode(result);
        if (product != null && context.mounted) {
          context.read<SaleFormBloc>().add(SaleLineItemAdded(
                product: product,
                quantity: 1,
                unitPriceCents: product.priceCents,
              ));
          return;
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('sales.no_products'.tr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('sales.no_products'.tr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Widget _discountToggle(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) => Row(
    children: [
      Icon(LucideIcons.tag, size: 16, color: cs.primary), const SizedBox(width: 8),
      Text('sales.discount_mode'.tr(), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      const Spacer(),
      SegmentedButton<SaleDiscountMode>(
        segments: [
          ButtonSegment(value: SaleDiscountMode.perItem, label: Text('sales.per_item'.tr(), style: const TextStyle(fontSize: 12))),
          ButtonSegment(value: SaleDiscountMode.invoice, label: Text('sales.invoice'.tr(), style: const TextStyle(fontSize: 12))),
        ],
        selected: {s.discountMode},
        onSelectionChanged: (v) => ctx.read<SaleFormBloc>().add(SaleDiscountModeChanged(v.first)),
        style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ),
    ],
  );

  Widget _itemsHeader(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs) => Row(
    children: [
      Icon(LucideIcons.shoppingCart, size: 18, color: cs.primary), const SizedBox(width: 8),
      Text('sales.items'.tr(), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      if (s.items.isNotEmpty) ...[const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
          child: Text('${s.items.length}', style: t.textTheme.labelSmall?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)))],
    ],
  );

  Widget _emptyHint(ThemeData t, ColorScheme cs) => Container(
    padding: const EdgeInsets.all(32), margin: const EdgeInsets.only(top: 8),
    decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3))),
    child: Center(child: Column(children: [
      Icon(LucideIcons.packageOpen, size: 40, color: cs.onSurface.withValues(alpha: 0.15)),
      const SizedBox(height: 8),
      Text('sales.no_items_hint'.tr(), style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
    ])),
  );

  Widget _itemTile(BuildContext ctx, SaleLineItem item, SaleFormState state, ThemeData t, ColorScheme cs, CurrencyService curr) {
    final hasImage = item.product.imagePath != null && item.product.imagePath!.isNotEmpty;
    final itemTaxCents = item.taxCentsWithSettings(
      enableTaxCalculations: state.enableTaxCalculations,
      defaultTaxRateBps: state.defaultSalesTaxRateBps,
    );
    return Card(
      elevation: 0, margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEditItemSheet(ctx, item),
        child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              image: hasImage
                  ? DecorationImage(
                      image: FileImage(File(item.product.imagePath!)),
                      fit: BoxFit.cover,
                      onError: (exception, stackTrace) {},
                    )
                  : null,
            ),
            child: !hasImage
                ? Icon(LucideIcons.package, size: 20, color: cs.onSurfaceVariant)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.displayName, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            if (item.colorHex != null || item.sizeName != null) _variantChips(item, cs),
            Row(children: [
              Text('${item.quantity} × ${curr.format(item.unitPriceCents.toBigInt().toInt())}',
                style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              if (item.discountCents > Decimal.zero) ...[const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(6)),
                  child: Text('-${curr.format(item.discountCents.toBigInt().toInt())}',
                    style: t.textTheme.labelSmall?.copyWith(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)))],
              if (itemTaxCents > Decimal.zero) ...[const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(6)),
                  child: Text('+${curr.format(itemTaxCents.toBigInt().toInt())}',
                    style: t.textTheme.labelSmall?.copyWith(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600)))],
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(curr.format(item.totalCents.toBigInt().toInt()),
              style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
            if (item.employeeName != null && item.employeeName!.isNotEmpty) ...[const SizedBox(height: 2),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(6)),
                child: Text(item.employeeName!, style: t.textTheme.labelSmall?.copyWith(
                  color: cs.onTertiaryContainer, fontSize: 9)))],
            if (item.itemNote != null && item.itemNote!.isNotEmpty) ...[const SizedBox(height: 2),
              Icon(LucideIcons.stickyNote, size: 12, color: cs.onSurfaceVariant)],
            const SizedBox(height: 4),
            InkWell(onTap: () => ctx.read<SaleFormBloc>().add(SaleLineItemRemoved(item.tempId)),
              borderRadius: BorderRadius.circular(8),
              child: Padding(padding: const EdgeInsets.all(4),
                child: Icon(LucideIcons.trash2, size: 16, color: cs.error))),
          ]),
        ])),
      ),
    );
  }

  Widget _variantChips(SaleLineItem item, ColorScheme cs) {
    final colorHex = item.colorHex?.trim();
    final shade = _tryParseHexColor(colorHex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (shade != null) _colorDotChip(cs, shade),
          if (item.sizeName != null && item.sizeName!.isNotEmpty) _chip(cs, item.sizeName!),
        ],
      ),
    );
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

  Widget _colorDotChip(ColorScheme cs, Color shade) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: shade,
            shape: BoxShape.circle,
            border: Border.all(color: cs.outline.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  Widget _chip(ColorScheme cs, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
    child: Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)));

  Widget _totalsCard(SaleFormState s, ThemeData t, ColorScheme cs, CurrencyService curr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3))),
      child: Column(children: [
        _row(t, 'sales.subtotal'.tr(), curr.format(s.subtotalCents.toBigInt().toInt())),
        if (s.totalDiscountCents > Decimal.zero) ...[const SizedBox(height: 8),
          _row(t, 'sales.discount'.tr(), '- ${curr.format(s.totalDiscountCents.toBigInt().toInt())}', valueColor: cs.tertiary)],
        if (s.taxCents > Decimal.zero) ...[const SizedBox(height: 8),
          _row(t, 'sales.tax'.tr(), curr.format(s.taxCents.toBigInt().toInt()))],
        Divider(height: 20, color: cs.outlineVariant.withValues(alpha: 0.5)),
        _row(t, 'sales.total'.tr(), curr.format(s.totalCents.toBigInt().toInt()), isBold: true, valueColor: cs.primary),
      ]),
    );
  }

  Widget _row(ThemeData t, String l, String v, {bool isBold = false, Color? valueColor}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(l, style: (isBold ? t.textTheme.titleSmall : t.textTheme.bodyMedium)?.copyWith(
        color: isBold ? null : t.colorScheme.onSurfaceVariant)),
      Text(v, style: (isBold ? t.textTheme.titleMedium : t.textTheme.bodyMedium)?.copyWith(
        color: valueColor, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
    ]);

  Widget _bottomBar(BuildContext ctx, SaleFormState s, ThemeData t, ColorScheme cs, CurrencyService curr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
        boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))]),
      child: SafeArea(child: Row(children: [
        Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('sales.total'.tr(), style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          Text(curr.format(s.totalCents.toBigInt().toInt()),
            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
          Text('${s.items.length} ${'sales.items'.tr().toLowerCase()}  •  ${s.totalQuantity} ${'sales.pieces'.tr().toLowerCase()}',
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ])),
        const SizedBox(width: 12),
        Expanded(child: FilledButton.icon(
          onPressed: s.items.isEmpty ? null : () => _showCheckoutDialog(ctx, s, curr),
          icon: const Icon(LucideIcons.shoppingBag, size: 18),
          label: Text('sales.checkout'.tr()),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
      ])),
    );
  }

  // Dialog launchers
  void _showCustomerPicker(BuildContext ctx) {
    final bloc = ctx.read<SaleFormBloc>();
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) => _CustomerPickerSheet(onSelected: (c) {
        bloc.add(SaleCustomerChanged(customerId: c.id, customerName: c.name));
        Navigator.pop(sc);
      }));
  }

  void _showEmployeePicker(BuildContext ctx) {
    final bloc = ctx.read<SaleFormBloc>();
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) => _EmployeePickerSheet(onSelected: (e) {
        bloc.add(SaleEmployeeChanged(employeeId: e.id, employeeName: e.name));
        Navigator.pop(sc);
      }));
  }

  void _showAddItemSheet(BuildContext ctx) {
    final bloc = ctx.read<SaleFormBloc>();
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) => MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => sl<ProductsBloc>()..add(const ProductSearchRequested(''))),
          BlocProvider(create: (_) => sl<VariantPreviewsBloc>()),
          BlocProvider(create: (_) => sl<CategoriesBloc>()..add(const LoadCategories())),
        ],
        child: _AddItemSheet(onItemAdded: (product, variant, qty, price) {
          bloc.add(SaleLineItemAdded(product: product, variant: variant, quantity: qty, unitPriceCents: price));
          Navigator.pop(sc);
        })));
  }

  void _showEditItemSheet(BuildContext ctx, SaleLineItem item) {
    final bloc = ctx.read<SaleFormBloc>();
    final isPerItem = bloc.state.salespersonMode == SalespersonMode.perItem;
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      // BlocProvider.value re-exposes the SaleFormBloc inside the
      // modal route — without this the sheet's `context.read<SaleFormBloc>()`
      // (used to source live tax flags for the live total preview)
      // walks an empty element tree and throws ProviderNotFoundError.
      // Mirrors the _CheckoutSheet pattern below.
      builder: (sc) => BlocProvider.value(value: bloc,
        child: _EditItemSheet(item: item,
          showSalesperson: isPerItem,
          allowDiscounts: bloc.state.allowDiscounts,
          onUpdated: (qty, price, discount, {int? employeeId, String? employeeName, String? itemNote, bool clearEmployee = false}) {
            bloc.add(SaleLineItemUpdated(
              tempId: item.tempId, quantity: qty, unitPriceCents: price, discountCents: discount,
              employeeId: employeeId, employeeName: employeeName, itemNote: itemNote, clearEmployee: clearEmployee));
            Navigator.pop(sc);
          },
          onRemoved: () { bloc.add(SaleLineItemRemoved(item.tempId)); Navigator.pop(sc); })));
  }

  // ═══════════════════════════════════════════════════════
  // BELOW-COST WARNING DIALOG
  // ═══════════════════════════════════════════════════════
  void _showBelowCostWarningDialog(BuildContext context, BelowCostCheckResult warning) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = sl<CurrencyService>();
    final bloc = context.read<SaleFormBloc>();
    final reasonCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                warning.canOverride ? LucideIcons.alertTriangle : LucideIcons.ban,
                color: warning.canOverride ? Colors.deepOrange : cs.error,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'sales.below_cost_title'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: warning.canOverride ? Colors.deepOrange : cs.error,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (warning.canOverride ? Colors.deepOrange : cs.error).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(warning.productName,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _belowCostInfoRow(theme, 'sales.below_cost_cost'.tr(),
                        curr.formatCents(warning.costCents.toBigInt().toInt())),
                      _belowCostInfoRow(theme, 'sales.below_cost_price'.tr(),
                        curr.formatCents(warning.sellingPriceCents.toBigInt().toInt())),
                      const Divider(height: 16),
                      _belowCostInfoRow(theme, 'sales.below_cost_loss'.tr(),
                        curr.formatCents(warning.lossCents.toBigInt().toInt()),
                        valueColor: cs.error),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Threshold exceeded warning
                if (warning.exceedsThreshold) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.shieldAlert, color: cs.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'sales.below_cost_threshold_exceeded'.tr(args: [warning.lossPercent.toStringAsFixed(1)]),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Message
                Text(
                  warning.canOverride
                      ? 'sales.below_cost_override_hint'.tr()
                      : 'sales.below_cost_blocked'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                // Override reason input (only for Manager/Owner)
                if (warning.canOverride) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                      labelText: 'sales.below_cost_reason'.tr(),
                      hintText: 'sales.below_cost_reason_hint'.tr(),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(LucideIcons.messageSquare, size: 18),
                    ),
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            // Cancel / Remove item
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                bloc.add(const SaleBelowCostWarningDismissed());
              },
              child: Text(
                warning.canOverride
                    ? 'sales.below_cost_remove'.tr()
                    : 'common.ok'.tr(),
                style: TextStyle(color: cs.error),
              ),
            ),
            // Override button (only for Manager/Owner)
            if (warning.canOverride)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                ),
                onPressed: () {
                  final reason = reasonCtrl.text.trim();
                  if (reason.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('sales.below_cost_reason_required'.tr()),
                        backgroundColor: cs.error,
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  bloc.add(SaleBelowCostOverrideApproved(reason));
                },
                child: Text('sales.below_cost_override'.tr()),
              ),
          ],
        );
      },
    ).then((_) => reasonCtrl.dispose());
  }

  Widget _belowCostInfoRow(ThemeData theme, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // SAVE CONFIRMATION OVERLAY (Print / Share / Finish)
  // Shown AFTER navigating back to the sales list.
  // ═══════════════════════════════════════════════════════
  void _showSaveConfirmationOverlay(BuildContext context, SaleFormState state) {
    final theme = Theme.of(context);
    final invoiceNumber = state.saleNumber ?? '${state.saleId ?? ''}';

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
                child: const Icon(LucideIcons.checkCircle2, size: 48, color: Colors.green),
              ),
              const SizedBox(height: 16),
              Text(
                'sales.invoice_saved_message'.tr(args: [invoiceNumber]),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton.icon(
              icon: const Icon(LucideIcons.printer, size: 18),
              label: Text('sales.print_invoice'.tr()),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await SalePdfService.printFromFormState(
                    context: context,
                    state: state,
                  );
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
              },
            ),
            TextButton.icon(
              icon: const Icon(LucideIcons.share2, size: 18),
              label: Text('sales.share_invoice'.tr()),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await SalePdfService.shareFromFormState(
                    context: context,
                    state: state,
                  );
                } catch (_) {}
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

  void _showCheckoutDialog(BuildContext ctx, SaleFormState s, CurrencyService curr) {
    final bloc = ctx.read<SaleFormBloc>();
    showModalBottomSheet<void>(context: ctx, isScrollControlled: true, useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sc) => BlocProvider.value(value: bloc,
        child: _CheckoutSheet(currencyService: curr, notesCtrl: notesCtrl,
          onConfirm: () { bloc.add(const SaleFormSubmitted()); Navigator.pop(sc); })));
  }
}

// ═══════════════════════════════════════════════════════
// SALE TAB BAR — Multi-session POS tabs in the app bar
// ═══════════════════════════════════════════════════════
class _SaleTabBar extends StatelessWidget {
  final int tabCount;
  final int activeTab;
  final void Function(int) onSwitchTab;
  final VoidCallback? onAddTab;
  final void Function(int)? onCloseTab;

  const _SaleTabBar({
    required this.tabCount,
    required this.activeTab,
    required this.onSwitchTab,
    this.onAddTab,
    this.onCloseTab,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tab chips
        for (int i = 0; i < tabCount; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 2),
            child: GestureDetector(
              onTap: () => onSwitchTab(i),
              onLongPress: tabCount > 1 && onCloseTab != null
                  ? () => _showCloseConfirm(context, i)
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: i == activeTab
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: i == activeTab
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.5),
                    width: i == activeTab ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: i == activeTab ? FontWeight.bold : FontWeight.w500,
                        color: i == activeTab ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      ),
                    ),
                    if (i == activeTab && tabCount > 1 && onCloseTab != null) ...[
                      const SizedBox(width: 2),
                      GestureDetector(
                        onTap: () => _showCloseConfirm(context, i),
                        child: Icon(LucideIcons.x, size: 12, color: cs.onPrimaryContainer),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        // Add tab button
        if (onAddTab != null)
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: Icon(LucideIcons.plus, color: cs.primary),
              onPressed: onAddTab,
              tooltip: 'sales.add_tab'.tr(),
              style: IconButton.styleFrom(
                backgroundColor: cs.primaryContainer.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _showCloseConfirm(BuildContext context, int index) {
    final cs = Theme.of(context).colorScheme;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('sales.close_tab_title'.tr()),
        content: Text('sales.close_tab_message'.tr(args: ['${index + 1}'])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) onCloseTab?.call(index);
    });
  }
}
