import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../core/di/injection_container.dart';
import '../../../../core/database/app_database.dart' hide Size;
import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/payments/checkout_settlement.dart';
import '../../../../core/payments/return_cheque_settlement_dialog.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../../../core/widgets/pin_verification_dialog.dart';
import '../../../../core/widgets/action_confirmation_dialog.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../bloc/purchase_adj_return_form_bloc.dart';

class PurchaseAdjReturnFormScreen extends StatelessWidget {
  final int? supplierId;
  final String? supplierName;
  final int? productId;
  final int? variantId;
  final String? productName;
  final String? productSku;

  /// Optional variant label (e.g. "Red / L") rendered as a colored chip
  /// below the product name in the item card.
  final String? variantLabel;
  final int? productPrice;
  final String measurementType;
  final int? taxRateBps;

  const PurchaseAdjReturnFormScreen({
    super.key,
    this.supplierId,
    this.supplierName,
    this.productId,
    this.variantId,
    this.productName,
    this.productSku,
    this.variantLabel,
    this.productPrice,
    this.measurementType = 'piece',
    this.taxRateBps,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = PurchaseAdjReturnFormBloc(
          sl<AdjustmentReturnDao>(),
          sl<JournalEntryService>(),
          lan: sl<LanNetworkService>(),
        );
        if (supplierId != null && supplierName != null) {
          bloc.add(
            PurchaseAdjReturnSupplierSelected(supplierId!, supplierName!),
          );
        }
        if (productId != null && productName != null) {
          bloc.add(
            PurchaseAdjReturnItemAdded(
              AdjReturnLineItem(
                productId: productId!,
                variantId: variantId,
                productName: productName!,
                variantSku: productSku,
                variantLabel: variantLabel,
                quantity: measurementType == 'piece' ? 1 : 1000,
                quantityScale: measurementType == 'piece' ? 1 : 1000,
                measurementType: measurementType,
                unitPriceCents: productPrice ?? 0,
                taxRateBps: taxRateBps ?? 0,
              ),
            ),
          );
        }
        return bloc;
      },
      child: const _FormView(),
    );
  }
}

class _FormView extends StatelessWidget {
  const _FormView();

  Future<bool> _onWillPop(BuildContext context) async {
    final state = context.read<PurchaseAdjReturnFormBloc>().state;
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
        final lan = sl<LanNetworkService>();
        context.go(
          lan.snapshot.mode == LanMode.client
              ? '/purchases/returns'
              : '/purchases',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = sl<CurrencyService>();

    return BlocConsumer<PurchaseAdjReturnFormBloc, PurchaseAdjReturnFormState>(
      listenWhen: (prev, curr) => prev.isSuccess != curr.isSuccess,
      listener: (context, state) {
        if (state.isSuccess) {
          // Capture router BEFORE navigation destroys this context.
          final router = GoRouter.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('returns.adjustment_return_created'.tr()),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Close any open bottom sheet first.
          Navigator.of(
            context,
          ).popUntil((route) => !route.isActive || route is! PopupRoute);
          final createdId = state.createdReturnId;
          // Replace form with returns list, then push detail on top
          // so that Back from detail returns to the list.
          router.go('/purchases/returns');
          if (createdId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              router.push('/purchases/returns/adj/$createdId');
            });
          }
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
              title: Text('returns.purchase_adjustment_return'.tr()),
            ),
            body: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // ── Fixed top section (does not scroll) ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Column(
                          children: [
                            _buildReturnHeaderCard(context, state),
                            const SizedBox(height: 12),
                            _buildWarningBanner(context),
                            const SizedBox(height: 12),
                            _buildDiscountToggle(context, state),
                            const SizedBox(height: 12),
                            _PurchaseFraudWarnings(
                              supplierId: state.supplierId,
                              items: state.items,
                            ),
                          ],
                        ),
                      ),
                      // ── Items card: fixed header + scrollable list ──
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _buildItemsCard(context, state, cs),
                        ),
                      ),
                      _buildBottomBar(context, state, cs),
                    ],
                  ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // WARNING BANNER
  // ═══════════════════════════════════════════════════════
  Widget _buildWarningBanner(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.alertTriangle,
            size: 18,
            color: Colors.amber.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'returns.adjustment_return_warning_title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'returns.adjustment_return_warning_body'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // RETURN HEADER CARD (Return # + Date)
  // ═══════════════════════════════════════════════════════
  Widget _buildReturnHeaderCard(
    BuildContext context,
    PurchaseAdjReturnFormState state,
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
          // Return Number
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'returns.return_number_label'.tr(),
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
                    state.returnNumber ?? '—',
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
          // Return Date
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: state.returnDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (date != null && context.mounted) {
                  context.read<PurchaseAdjReturnFormBloc>().add(
                    PurchaseAdjReturnDateChanged(date),
                  );
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'returns.return_date'.tr(),
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
                            intl.DateFormat(
                              'dd/MM/yyyy',
                            ).format(state.returnDate),
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
  // ITEMS CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsCard(
    BuildContext context,
    PurchaseAdjReturnFormState state,
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
                    LucideIcons.package,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'returns.return_items'.tr(),
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
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${state.items.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => _showProductPicker(context),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: Text('returns.add_product'.tr()),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Only the added items scroll; the header above stays fixed.
            if (state.items.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                        'returns.no_items_yet'.tr(),
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
                  padding: EdgeInsets.zero,
                  itemCount: state.items.length,
                  separatorBuilder: (context2, index2) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    return _AdjReturnItemTile(
                      item: item,
                      index: index,
                      currencyService: cs,
                      onQuantityChanged: (qty) =>
                          context.read<PurchaseAdjReturnFormBloc>().add(
                            PurchaseAdjReturnItemQuantityChanged(index, qty),
                          ),
                      onPriceChanged: (price) => context
                          .read<PurchaseAdjReturnFormBloc>()
                          .add(PurchaseAdjReturnItemPriceChanged(index, price)),
                      onDiscountChanged: (disc, bps) =>
                          context.read<PurchaseAdjReturnFormBloc>().add(
                            PurchaseAdjReturnItemDiscountChanged(
                              index,
                              disc,
                              discountPercentBps: bps,
                            ),
                          ),
                      onRemove: () async {
                        final confirmed = await confirmInvoiceLineRemoval(
                          context,
                          itemName: item.productName,
                        );
                        if (!confirmed || !context.mounted) return;
                        context.read<PurchaseAdjReturnFormBloc>().add(
                          PurchaseAdjReturnItemRemoved(index),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showProductPicker(BuildContext context) async {
    final lan = sl<LanNetworkService>();
    if (lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession) {
      final page = await lan.fetchRemoteCatalog(limit: 200, management: true);
      final rows = <AdjReturnLineItem>[];
      for (final product in page.products) {
        final referencePrice =
            product.lastPurchasePriceCents ??
            product.costCents ??
            product.priceCents;
        if (product.hasVariants) {
          for (final variant in product.variants) {
            final variantReferencePrice =
                variant.lastPurchasePriceCents ??
                variant.costCents ??
                referencePrice;
            rows.add(
              AdjReturnLineItem(
                productId: product.id,
                variantId: variant.id,
                productName: product.name,
                variantSku: variant.sku,
                variantLabel: variant.label,
                quantity: product.quantityScale,
                quantityScale: product.quantityScale,
                measurementType: product.measurementType,
                unitPriceCents: variantReferencePrice,
                taxRateBps: product.purchaseTaxRateBps,
              ),
            );
          }
        } else {
          final variant = product.variants.isEmpty
              ? null
              : product.variants.first;
          rows.add(
            AdjReturnLineItem(
              productId: product.id,
              variantId: variant?.id,
              productName: product.name,
              variantSku: product.sku ?? variant?.sku,
              quantity: product.quantityScale,
              quantityScale: product.quantityScale,
              measurementType: product.measurementType,
              unitPriceCents: referencePrice,
              taxRateBps: product.purchaseTaxRateBps,
            ),
          );
        }
      }
      if (!context.mounted) return;
      final selected = await showModalBottomSheet<AdjReturnLineItem>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _PartyPickerSheet<AdjReturnLineItem>(
          title: 'returns.select_product'.tr(),
          items: rows,
          getName: (item) => item.displayName,
          getInitial: (item) => item.productName.isEmpty
              ? '?'
              : item.productName[0].toUpperCase(),
        ),
      );
      if (selected != null && context.mounted) {
        context.read<PurchaseAdjReturnFormBloc>().add(
          PurchaseAdjReturnItemAdded(selected),
        );
      }
      return;
    }
    final db = sl<AppDatabase>();

    final result = await showModalBottomSheet<AdjReturnLineItem>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ProductPickerSheet(db: db, isSale: false),
    );

    if (result != null && context.mounted) {
      context.read<PurchaseAdjReturnFormBloc>().add(
        PurchaseAdjReturnItemAdded(result),
      );
    }
  }

  // ═══════════════════════════════════════════════════════
  // DISCOUNT MODE TOGGLE
  // ═══════════════════════════════════════════════════════
  Widget _buildDiscountToggle(
    BuildContext context,
    PurchaseAdjReturnFormState state,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Icon(LucideIcons.tag, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'returns.discount_mode'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(
                      'returns.discount_per_item'.tr(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(
                      'returns.discount_overall'.tr(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                selected: {state.discountPerItem},
                onSelectionChanged: (v) {
                  context.read<PurchaseAdjReturnFormBloc>().add(
                    PurchaseAdjReturnDiscountModeChanged(v.first),
                  );
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // BOTTOM BAR
  // ═══════════════════════════════════════════════════════
  Widget _buildBottomBar(
    BuildContext context,
    PurchaseAdjReturnFormState state,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final quantitySummary = localizedQuantitySummary(
      state.items,
      quantityOf: (item) => item.quantity,
      measurementTypeOf: (item) => item.measurementType,
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'purchases.total'.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    cs.format(state.totalCents),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.error,
                    ),
                  ),
                  Text(
                    '${state.items.length} ${'purchases.items_count'.tr()}  •  $quantitySummary',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: state.items.isEmpty
                    ? null
                    : () => _showCheckoutSheet(context, state, cs),
                icon: const Icon(LucideIcons.shoppingBag, size: 18),
                label: Text('returns.checkout'.tr()),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckoutSheet(
    BuildContext context,
    PurchaseAdjReturnFormState state,
    CurrencyService cs,
  ) {
    // Capture bloc reference BEFORE showing the sheet to avoid
    // accessing a deactivated widget's ancestor if the parent navigates away.
    final bloc = context.read<PurchaseAdjReturnFormBloc>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: _CheckoutSheet(currencyService: cs),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CHECKOUT BOTTOM SHEET — supplier, notes, financial summary, confirm
// ═══════════════════════════════════════════════════════════

class _CheckoutSheet extends StatefulWidget {
  final CurrencyService currencyService;
  const _CheckoutSheet({required this.currencyService});

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _discountFixedCtrl = TextEditingController();
  final TextEditingController _discountPercentCtrl = TextEditingController();
  bool _updatingDiscount = false;
  List<CheckoutPaymentAllocation> _settlementAllocations = const [];

  @override
  void initState() {
    super.initState();
    final state = context.read<PurchaseAdjReturnFormBloc>().state;
    _notesCtrl.text = state.notes ?? '';
    if (state.overallDiscountCents > 0) {
      _discountFixedCtrl.text = (state.overallDiscountCents / 100)
          .toStringAsFixed(2);
      final base = state.totalNetBeforeOverallDiscountCents;
      if (base > 0) {
        final pct = (state.overallDiscountCents / base) * 100;
        _discountPercentCtrl.text = pct.toStringAsFixed(2);
      }
    }
    _discountFixedCtrl.addListener(_syncDiscountFromFixed);
    _discountPercentCtrl.addListener(_syncDiscountFromPercent);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _discountFixedCtrl.dispose();
    _discountPercentCtrl.dispose();
    super.dispose();
  }

  void _syncDiscountFromFixed() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    final fixedVal = double.tryParse(_discountFixedCtrl.text) ?? 0;
    final fixedCents = (fixedVal * 100).round();
    // Percent base is net before tax — same base used per-item — so a 1%
    // overall discount produces the same total as 1% applied to every line.
    final sub = context
        .read<PurchaseAdjReturnFormBloc>()
        .state
        .totalNetBeforeOverallDiscountCents;
    if (sub > 0 && fixedCents > 0) {
      _discountPercentCtrl.text = ((fixedCents / sub) * 100).toStringAsFixed(2);
    } else {
      _discountPercentCtrl.text = '';
    }
    _applyOverallDiscount();
    _updatingDiscount = false;
  }

  void _syncDiscountFromPercent() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    final pct = double.tryParse(_discountPercentCtrl.text) ?? 0;
    final sub = context
        .read<PurchaseAdjReturnFormBloc>()
        .state
        .totalNetBeforeOverallDiscountCents;
    if (sub > 0 && pct > 0) {
      final cents = (sub * (pct / 100)).round().clamp(0, sub);
      _discountFixedCtrl.text = (cents / 100).toStringAsFixed(2);
    } else {
      _discountFixedCtrl.text = '';
    }
    _applyOverallDiscount();
    _updatingDiscount = false;
  }

  void _applyOverallDiscount() {
    final fixedVal = double.tryParse(_discountFixedCtrl.text) ?? 0;
    final cents = (fixedVal * 100).round();
    context.read<PurchaseAdjReturnFormBloc>().add(
      PurchaseAdjReturnOverallDiscountChanged(cents, false),
    );
  }

  void _showSupplierPicker(BuildContext context) async {
    final lan = sl<LanNetworkService>();
    if (lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession) {
      final suppliers = await lan.fetchRemoteSuppliers(limit: 200);
      if (!context.mounted) return;
      final selected = await showModalBottomSheet<LanSupplierSummary>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _PartyPickerSheet<LanSupplierSummary>(
          title: 'returns.select_supplier'.tr(),
          items: suppliers,
          getName: (supplier) => supplier.name,
          getInitial: (supplier) =>
              supplier.name.isEmpty ? '?' : supplier.name[0].toUpperCase(),
        ),
      );
      if (selected != null && context.mounted) {
        context.read<PurchaseAdjReturnFormBloc>().add(
          PurchaseAdjReturnSupplierSelected(selected.id, selected.name),
        );
      }
      return;
    }
    final db = sl<AppDatabase>();
    final suppliers = await db.select(db.suppliers).get();
    suppliers.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (!context.mounted) return;

    final selected = await showModalBottomSheet<Supplier>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PartyPickerSheet<Supplier>(
        title: 'returns.select_supplier'.tr(),
        items: suppliers,
        getName: (s) => s.name,
        getInitial: (s) => s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
      ),
    );

    if (selected != null && context.mounted) {
      context.read<PurchaseAdjReturnFormBloc>().add(
        PurchaseAdjReturnSupplierSelected(selected.id, selected.name),
      );
    }
  }

  Future<void> _onConfirm(BuildContext context) async {
    final bloc = context.read<PurchaseAdjReturnFormBloc>();
    final state = bloc.state;
    final settings = context.read<AppSettingsBloc>().state.settings;
    if (settings.requirePinForVoidRefund) {
      final pinOk = await showPinVerificationDialog(context);
      if (!pinOk || !context.mounted) return;
    }
    if (!context.mounted) return;
    var allocations = _settlementAllocations;
    if (state.paymentMethod == AdjReturnPaymentMethod.cheque &&
        !isReturnChequeSettlementValid(
          allocations,
          totalCents: state.totalCents,
        )) {
      await _configureChequeSettlement(context, state);
      allocations = _settlementAllocations;
      if (!isReturnChequeSettlementValid(
        allocations,
        totalCents: state.totalCents,
      )) {
        return;
      }
    }
    if (!context.mounted) return;
    bloc.add(
      PurchaseAdjReturnSubmitted(
        allowNegativeStock: settings.allowNegativeStock,
        settlementAllocations:
            state.paymentMethod == AdjReturnPaymentMethod.cheque
            ? allocations
            : const [],
      ),
    );
  }

  Future<void> _configureChequeSettlement(
    BuildContext context,
    PurchaseAdjReturnFormState state,
  ) async {
    if (state.totalCents <= 0) return;
    final allocations = await showReturnChequeSettlementDialog(
      context,
      totalCents: state.totalCents,
      formattedTotal: widget.currencyService.format(state.totalCents),
      initialDueDate: state.dueDate,
      documentDate: state.returnDate,
      initialAllocations: _settlementAllocations,
    );
    if (allocations == null || !context.mounted) return;
    setState(() => _settlementAllocations = allocations);
    context.read<PurchaseAdjReturnFormBloc>().add(
      PurchaseAdjReturnDueDateChanged(returnChequePrimaryDueDate(allocations)),
    );
  }

  Future<void> _changePaymentMethod(
    BuildContext context,
    PurchaseAdjReturnFormState state,
    AdjReturnPaymentMethod method,
  ) async {
    context.read<PurchaseAdjReturnFormBloc>().add(
      PurchaseAdjReturnPaymentMethodChanged(method),
    );
    if (method == AdjReturnPaymentMethod.cheque) {
      await _configureChequeSettlement(context, state);
    } else if (mounted) {
      setState(() => _settlementAllocations = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = widget.currencyService;

    return BlocListener<PurchaseAdjReturnFormBloc, PurchaseAdjReturnFormState>(
      listenWhen: (prev, curr) => prev.isSuccess != curr.isSuccess,
      listener: (context, state) {
        // Success navigation is handled by the main screen's BlocConsumer.
        // Errors are shown inline in the sheet.
      },
      child: BlocBuilder<PurchaseAdjReturnFormBloc, PurchaseAdjReturnFormState>(
        builder: (context, state) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (context, scrollCtrl) => Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(LucideIcons.shoppingBag, size: 20, color: cs.error),
                      const SizedBox(width: 8),
                      Text(
                        'returns.checkout'.tr(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('common.cancel'.tr()),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      // ── Supplier Selection ──
                      _sectionHeader(
                        theme,
                        cs,
                        LucideIcons.building2,
                        'purchases.supplier'.tr(),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showSupplierPicker(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: state.supplierId == null
                                  ? cs.error.withValues(alpha: 0.5)
                                  : cs.outlineVariant,
                            ),
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
                                      'returns.select_supplier'.tr(),
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
                      if (state.supplierId == null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.errorContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: cs.error.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.alertTriangle,
                                size: 14,
                                color: cs.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'returns.select_supplier'.tr(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // ── Payment Method ──
                      _sectionHeader(
                        theme,
                        cs,
                        LucideIcons.wallet,
                        'purchases.payment_method'.tr(),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: AdjReturnPaymentMethod.values.map((m) {
                          final sel = state.paymentMethod == m;
                          return ChoiceChip(
                            label: Text(_pmLabel(m)),
                            selected: sel,
                            onSelected: (_) =>
                                _changePaymentMethod(context, state, m),
                            avatar: Icon(_pmIcon(m), size: 16),
                            selectedColor: cs.primaryContainer,
                            showCheckmark: false,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // ── Cheque details and partial settlement ──
                      if (state.paymentMethod ==
                          AdjReturnPaymentMethod.cheque) ...[
                        ReturnChequeSettlementSummary(
                          allocations: _settlementAllocations,
                          totalCents: state.totalCents,
                          formatAmount: widget.currencyService.format,
                          onEdit: () =>
                              _configureChequeSettlement(context, state),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Reason (required) ──
                      _sectionHeader(
                        theme,
                        cs,
                        LucideIcons.listChecks,
                        'returns.reason_label'.tr(),
                      ),
                      const SizedBox(height: 8),
                      _ReasonDropdown(
                        value: state.reasonCode,
                        isRequired: state.reasonCode == null,
                        onChanged: (r) => context
                            .read<PurchaseAdjReturnFormBloc>()
                            .add(PurchaseAdjReturnReasonChanged(r)),
                      ),
                      const SizedBox(height: 20),

                      // ── Notes ──
                      _sectionHeader(
                        theme,
                        cs,
                        LucideIcons.stickyNote,
                        'returns.notes'.tr(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'returns.notes_hint'.tr(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          isDense: true,
                        ),
                        onChanged: (v) => context
                            .read<PurchaseAdjReturnFormBloc>()
                            .add(PurchaseAdjReturnNotesChanged(v)),
                      ),
                      const SizedBox(height: 20),

                      // ── Overall Discount (when mode is not per-item) ──
                      if (!state.discountPerItem) ...[
                        _sectionHeader(
                          theme,
                          cs,
                          LucideIcons.tag,
                          'returns.overall_discount'.tr(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
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
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
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
                                  labelText: 'purchases.discount_percent'.tr(),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],

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
                            _summaryRow(
                              theme,
                              'purchases.subtotal'.tr(),
                              curr.format(state.totalSubtotalCents),
                            ),
                            if (state.totalItemDiscountCents > 0) ...[
                              const SizedBox(height: 8),
                              _summaryRow(
                                theme,
                                'returns.item_discounts'.tr(),
                                '- ${curr.format(state.totalItemDiscountCents)}',
                                valueColor: Colors.orange,
                              ),
                            ],
                            if (state.totalAdjustedTaxCents > 0) ...[
                              const SizedBox(height: 8),
                              _summaryRow(
                                theme,
                                'purchases.tax'.tr(),
                                '+ ${curr.format(state.totalAdjustedTaxCents)}',
                                valueColor: cs.tertiary,
                              ),
                            ],
                            if (state.effectiveOverallDiscountCents > 0) ...[
                              const SizedBox(height: 8),
                              _summaryRow(
                                theme,
                                'returns.overall_discount'.tr(),
                                '- ${curr.format(state.effectiveOverallDiscountCents)}',
                                valueColor: Colors.deepOrange,
                              ),
                            ],
                            Divider(
                              height: 20,
                              color: cs.outlineVariant.withValues(alpha: 0.5),
                            ),
                            _summaryRow(
                              theme,
                              'returns.supplier_credit_total'.tr(),
                              curr.format(state.totalCents),
                              isBold: true,
                              valueColor: cs.error,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Fraud-prevention warnings (shown inline so the user
                      // sees them right before confirming the return).
                      _PurchaseFraudWarnings(
                        supplierId: state.supplierId,
                        items: state.items,
                      ),

                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              LucideIcons.alertTriangle,
                              size: 14,
                              color: Colors.amber.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'returns.confirm_post_warning'.tr(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.amber.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),

                // ── Inline error banner (above bottom bar) ──
                if (state.error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: cs.errorContainer,
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.alertCircle,
                          size: 16,
                          color: cs.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'returns.supplier_credit_total'.tr(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                curr.format(state.totalCents),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Builder(
                            builder: (ctx) {
                              final chequeNoDueDate =
                                  state.paymentMethod ==
                                      AdjReturnPaymentMethod.cheque &&
                                  state.dueDate == null;
                              final canConfirm =
                                  state.supplierId != null &&
                                  state.reasonCode != null &&
                                  !state.isSubmitting &&
                                  !chequeNoDueDate;
                              return FilledButton.icon(
                                onPressed: canConfirm
                                    ? () => _onConfirm(context)
                                    : null,
                                icon: state.isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(LucideIcons.check, size: 18),
                                label: Text('returns.confirm_save'.tr()),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  backgroundColor: cs.error,
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
          );
        },
      ),
    );
  }

  Widget _sectionHeader(
    ThemeData theme,
    ColorScheme cs,
    IconData icon,
    String title,
  ) => Row(
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
  );

  Widget _summaryRow(
    ThemeData t,
    String l,
    String v, {
    bool isBold = false,
    Color? valueColor,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        l,
        style: (isBold ? t.textTheme.titleSmall : t.textTheme.bodyMedium)
            ?.copyWith(color: isBold ? null : t.colorScheme.onSurfaceVariant),
      ),
      Text(
        v,
        style: (isBold ? t.textTheme.titleMedium : t.textTheme.bodyMedium)
            ?.copyWith(
              color: valueColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            ),
      ),
    ],
  );

  String _pmLabel(AdjReturnPaymentMethod m) => switch (m) {
    AdjReturnPaymentMethod.cash => 'purchases.payment_cash'.tr(),
    AdjReturnPaymentMethod.card => 'purchases.payment_card'.tr(),
    AdjReturnPaymentMethod.credit => 'purchases.payment_credit'.tr(),
    AdjReturnPaymentMethod.cheque => 'purchases.payment_cheque'.tr(),
  };

  IconData _pmIcon(AdjReturnPaymentMethod m) => switch (m) {
    AdjReturnPaymentMethod.cash => LucideIcons.banknote,
    AdjReturnPaymentMethod.card => LucideIcons.creditCard,
    AdjReturnPaymentMethod.credit => LucideIcons.clock,
    AdjReturnPaymentMethod.cheque => LucideIcons.fileText,
  };
}

// ═══════════════════════════════════════════════════════════
// COMPACT ITEM TILE — shows name, qty stepper, total, edit & delete
// ═══════════════════════════════════════════════════════════

class _AdjReturnItemTile extends StatefulWidget {
  final AdjReturnLineItem item;
  final int index;
  final CurrencyService currencyService;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<int> onPriceChanged;

  /// Receives `(discountCents, discountPercentBps)`. When `discountPercentBps`
  /// is non-zero the discount is treated as a live percent and recomputed
  /// against quantity changes; otherwise it is a fixed-cent discount.
  final void Function(int cents, int percentBps) onDiscountChanged;
  final VoidCallback onRemove;

  const _AdjReturnItemTile({
    required this.item,
    required this.index,
    required this.currencyService,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onDiscountChanged,
    required this.onRemove,
  });

  @override
  State<_AdjReturnItemTile> createState() => _AdjReturnItemTileState();
}

class _AdjReturnItemTileState extends State<_AdjReturnItemTile> {
  late TextEditingController _qtyCtrl;
  late MeasurementUnit _quantityUnit;

  @override
  void initState() {
    super.initState();
    _quantityUnit = MeasurementType.fromDb(
      widget.item.measurementType,
    ).majorUnit;
    _qtyCtrl = TextEditingController(
      text: MeasuredQuantity.editableValue(widget.item.quantity, _quantityUnit),
    );
  }

  @override
  void didUpdateWidget(covariant _AdjReturnItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = MeasuredQuantity.editableValue(
      widget.item.quantity,
      _quantityUnit,
    );
    if (widget.item.quantity != oldWidget.item.quantity &&
        _qtyCtrl.text != text) {
      _qtyCtrl.text = text;
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _showEditSheet(BuildContext context) async {
    final discountPerItem = context
        .read<PurchaseAdjReturnFormBloc>()
        .state
        .discountPerItem;
    final db = sl<AppDatabase>();
    int stockQty = 0;
    try {
      if (widget.item.variantId != null) {
        final v = await (db.select(
          db.productVariants,
        )..where((t) => t.id.equals(widget.item.variantId!))).getSingleOrNull();
        stockQty = v?.stockQuantity ?? 0;
      } else {
        final p = await (db.select(
          db.products,
        )..where((t) => t.id.equals(widget.item.productId))).getSingleOrNull();
        stockQty = p?.stockQuantity ?? 0;
      }
    } catch (_) {}
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ItemEditSheet(
        item: widget.item,
        currencyService: widget.currencyService,
        onPriceChanged: widget.onPriceChanged,
        onDiscountChanged: widget.onDiscountChanged,
        showDiscount: discountPerItem,
        stockQuantity: stockQty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = widget.currencyService;
    final item = widget.item;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showEditSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            // Qty stepper with editable text field
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
                    onTap: item.quantity > _quantityUnit.internalFactor
                        ? () => widget.onQuantityChanged(
                            item.quantity - _quantityUnit.internalFactor,
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        LucideIcons.minus,
                        size: 12,
                        color: item.quantity > _quantityUnit.internalFactor
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                      ],
                      onTap: () => selectAllText(_qtyCtrl),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.error,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                      onChanged: (v) {
                        try {
                          final parsed = MeasuredQuantity.parseToStored(
                            v,
                            _quantityUnit,
                          );
                          if (parsed > 0) widget.onQuantityChanged(parsed);
                        } on FormatException {
                          // Keep partial decimal input until it becomes valid.
                        }
                      },
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => widget.onQuantityChanged(
                      item.quantity + _quantityUnit.internalFactor,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        LucideIcons.plus,
                        size: 12,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (MeasurementType.fromDb(item.measurementType).minorUnit != null)
              PopupMenuButton<MeasurementUnit>(
                tooltip: 'measurement.select_unit'.tr(),
                initialValue: _quantityUnit,
                icon: const Icon(LucideIcons.ruler, size: 16),
                itemBuilder: (_) => MeasurementType.fromDb(item.measurementType)
                    .inputUnits
                    .map((unit) {
                      return PopupMenuItem(
                        value: unit,
                        child: Text('measurement.units.${unit.dbValue}'.tr()),
                      );
                    })
                    .toList(),
                onSelected: (unit) {
                  setState(() {
                    _quantityUnit = unit;
                    _qtyCtrl.text = MeasuredQuantity.editableValue(
                      item.quantity,
                      unit,
                    );
                  });
                },
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      if (item.variantLabel != null &&
                          item.variantLabel!.isNotEmpty)
                        Text(
                          item.variantLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (item.variantSku != null &&
                          item.variantSku!.isNotEmpty)
                        Text(
                          '#${item.variantSku!}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      Text(
                        '${curr.format(item.unitPriceCents)} × ${localizedQuantity(item.quantity, item.measurementType)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (item.discountCents > 0)
                        Text(
                          '-${curr.format(item.discountCents)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.orange,
                          ),
                        ),
                      if (item.taxRateBps > 0)
                        Text(
                          '+${(item.taxRateBps / 100).toStringAsFixed(1)}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.tertiary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              curr.format(item.totalCents),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.error,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _showEditSheet(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(LucideIcons.pencil, size: 14, color: cs.primary),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: widget.onRemove,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(LucideIcons.trash2, size: 14, color: cs.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// ITEM EDIT BOTTOM SHEET — full price/discount/tax controls
// ═══════════════════════════════════════════════════════════

class _ItemEditSheet extends StatefulWidget {
  final AdjReturnLineItem item;
  final CurrencyService currencyService;
  final ValueChanged<int> onPriceChanged;

  /// Receives `(discountCents, discountPercentBps)`.
  final void Function(int cents, int percentBps) onDiscountChanged;
  final bool showDiscount;
  final int stockQuantity;

  const _ItemEditSheet({
    required this.item,
    required this.currencyService,
    required this.onPriceChanged,
    required this.onDiscountChanged,
    this.showDiscount = true,
    this.stockQuantity = 0,
  });

  @override
  State<_ItemEditSheet> createState() => _ItemEditSheetState();
}

class _ItemEditSheetState extends State<_ItemEditSheet> {
  late TextEditingController _priceCtrl;
  late TextEditingController _discountCtrl;
  late bool _discountIsPercent;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: (widget.item.unitPriceCents / 100).toStringAsFixed(2),
    );
    // Pre-populate the sheet using whichever discount form was previously
    // saved on the line. A percent (basis-points) value takes precedence so
    // the user keeps editing the same semantic value they entered before.
    if (widget.item.discountPercentBps > 0) {
      _discountIsPercent = true;
      _discountCtrl = TextEditingController(
        text: (widget.item.discountPercentBps / 100).toStringAsFixed(2),
      );
    } else {
      _discountIsPercent = false;
      _discountCtrl = TextEditingController(
        text: widget.item.discountCents > 0
            ? (widget.item.discountCents / 100).toStringAsFixed(2)
            : '',
      );
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  /// Resolved cents from the current sheet inputs (used for live preview).
  int _computeDiscountCents() {
    final val = double.tryParse(_discountCtrl.text) ?? 0;
    if (_discountIsPercent) {
      final price = double.tryParse(_priceCtrl.text) ?? 0;
      final subtotal = MeasuredAmount.cents(
        unitCents: (price * 100).round(),
        quantity: widget.item.quantity,
        quantityScale: widget.item.quantityScale,
      );
      return (subtotal * val / 100).round();
    }
    return (val * 100).round();
  }

  /// Push the current sheet state to the bloc. In percent mode we send the
  /// basis-points value so quantity changes from outside the sheet keep the
  /// discount proportional; in absolute mode we send fixed cents.
  void _pushDiscount() {
    final val = double.tryParse(_discountCtrl.text) ?? 0;
    if (_discountIsPercent) {
      final bps = (val * 100).round();
      widget.onDiscountChanged(_computeDiscountCents(), bps);
    } else {
      widget.onDiscountChanged((val * 100).round(), 0);
    }
  }

  void _applyPrice() {
    final parsed = double.tryParse(_priceCtrl.text);
    if (parsed != null) {
      widget.onPriceChanged((parsed * 100).round());
      _pushDiscount();
    }
    setState(() {});
  }

  void _applyDiscount() {
    _pushDiscount();
    setState(() {});
  }

  // ─── live computed values from controllers ───
  int get _livePriceCents =>
      ((double.tryParse(_priceCtrl.text) ?? 0) * 100).round();
  int get _liveSubtotal => MeasuredAmount.cents(
    unitCents: _livePriceCents,
    quantity: widget.item.quantity,
    quantityScale: widget.item.quantityScale,
  );
  int get _liveDiscount => _computeDiscountCents();
  int get _liveNet => (_liveSubtotal - _liveDiscount).clamp(0, 999999999);
  int get _liveTax => widget.item.taxRateBps > 0
      ? (_liveNet * widget.item.taxRateBps / 10000).round()
      : 0;
  int get _liveTotal => _liveNet + _liveTax;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = widget.currencyService;
    final item = widget.item;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(LucideIcons.pencil, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                curr.format(_liveTotal),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stock quantity info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.stockQuantity > 0
                  ? cs.primaryContainer.withValues(alpha: 0.3)
                  : cs.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.stockQuantity > 0
                    ? cs.primary.withValues(alpha: 0.3)
                    : cs.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.warehouse,
                  size: 16,
                  color: widget.stockQuantity > 0 ? cs.primary : cs.error,
                ),
                const SizedBox(width: 8),
                Text(
                  'returns.stock'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  localizedQuantity(widget.stockQuantity, item.measurementType),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: widget.stockQuantity > 0 ? cs.primary : cs.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Text(
            'purchases.unit_cost'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            ],
            onTap: () => selectAllText(_priceCtrl),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              isDense: true,
              prefixIcon: const Icon(LucideIcons.dollarSign, size: 18),
            ),
            onChanged: (_) => _applyPrice(),
          ),
          const SizedBox(height: 14),

          if (widget.showDiscount) ...[
            Row(
              children: [
                Text(
                  'purchases.item_discount'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(
                        curr.currencySymbol,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    const ButtonSegment(
                      value: true,
                      label: Text('%', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {_discountIsPercent},
                  onSelectionChanged: (v) => setState(() {
                    _discountIsPercent = v.first;
                    _discountCtrl.clear();
                    widget.onDiscountChanged(0, 0);
                  }),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              onTap: () => selectAllText(_discountCtrl),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                isDense: true,
                hintText: _discountIsPercent ? '0 %' : '0.00',
                prefixIcon: Icon(
                  _discountIsPercent ? LucideIcons.percent : LucideIcons.tag,
                  size: 18,
                ),
              ),
              onChanged: (_) => _applyDiscount(),
            ),
          ],

          if (item.taxRateBps > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.tertiary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.percent, size: 16, color: cs.tertiary),
                  const SizedBox(width: 8),
                  Text(
                    'purchases.tax'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(item.taxRateBps / 100).toStringAsFixed(2)}%  =  ${curr.format(_liveTax)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.tertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'purchases.subtotal'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      curr.format(_liveSubtotal),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (_liveDiscount > 0) ...[
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
                        '-${curr.format(_liveDiscount)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_liveTax > 0) ...[
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
                        '+${curr.format(_liveTax)}',
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      curr.format(_liveTotal),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PARTY PICKER SHEET (generic for supplier/customer)
// ═══════════════════════════════════════════════════════════

class _PartyPickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final String Function(T) getName;
  final String Function(T) getInitial;

  const _PartyPickerSheet({
    super.key,
    required this.title,
    required this.items,
    required this.getName,
    required this.getInitial,
  });

  @override
  State<_PartyPickerSheet<T>> createState() => _PartyPickerSheetState<T>();
}

class _PartyPickerSheetState<T> extends State<_PartyPickerSheet<T>> {
  String _query = '';

  List<T> get _filtered {
    if (_query.isEmpty) return widget.items;
    final q = _query.toLowerCase();
    return widget.items
        .where((i) => widget.getName(i).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'common.search'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: _filtered.length,
              itemBuilder: (ctx, i) {
                final item = _filtered[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      widget.getInitial(item),
                      style: TextStyle(color: cs.onPrimaryContainer),
                    ),
                  ),
                  title: Text(widget.getName(item)),
                  onTap: () => Navigator.pop(context, item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PRODUCT PICKER SHEET — flat list with variant color/size
// ═══════════════════════════════════════════════════════════

class _PickerRow {
  final int productId;
  final int? variantId;
  final String productName;
  final String? variantLabel;
  final String? sku;
  final int priceCents;
  final int costCents;

  /// GROSS supplier reference price (last unit cost the user typed on a
  /// purchase line, before per-line trade discounts). Nullable because rows
  /// created before migration 10055 — or never touched by a purchase post —
  /// have NULL here. Callers MUST resolve `lastPurchasePriceCents ?? costCents`
  /// to obtain the user-facing supplier reference (the same convention used
  /// by `VariantEditDialog` and `purchase_form_screen.dart` per Phase 15.1).
  /// This is the single piece of data that makes the purchase adjustment
  /// return show the cost basis (not the customer sell price).
  final int? lastPurchasePriceCents;
  final int stockQuantity;
  final String measurementType;
  final int taxRateBps;

  /// Whether the underlying product is a variant product (`products.has_variants = 1`).
  /// Used for the picker icon so non-variant products that happen to carry a
  /// default variant id don't get the `layers` icon — matching the rest of the
  /// app (e.g. `purchase_form_screen.dart`, `category_movement_screen.dart`).
  final bool hasVariants;

  const _PickerRow({
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantLabel,
    this.sku,
    required this.priceCents,
    required this.costCents,
    this.lastPurchasePriceCents,
    required this.stockQuantity,
    required this.measurementType,
    required this.taxRateBps,
    required this.hasVariants,
  });

  /// Money to display and seed into the new line item.
  /// • Sale context  → customer sell price.
  /// • Purchase context → GROSS supplier reference
  ///   `lastPurchasePriceCents ?? costCents` (Phase 15.1 SoT). Using
  ///   `priceCents` here was the variant-vs-no-variant asymmetry bug fixed
  ///   in Phase 15.2 — variants surfaced the sell price ($150) while the
  ///   IAS-2 NET cost was hidden, and no-variant rows surfaced the sell
  ///   price ($99) too, making the picker useless for a supplier return.
  int unitMoneyCents({required bool isSale}) {
    if (isSale) return priceCents;
    return lastPurchasePriceCents ?? costCents;
  }

  String get displayName {
    if (variantLabel != null && variantLabel!.isNotEmpty) {
      return '$productName ($variantLabel)';
    }
    return productName;
  }
}

class _ProductPickerSheet extends StatefulWidget {
  final AppDatabase db;
  final bool isSale;

  const _ProductPickerSheet({required this.db, this.isSale = true});

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _query = '';
  List<_PickerRow> _rows = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = widget.db;
    final products =
        await (db.select(db.products)
              ..where((p) => p.isActive.equals(true))
              ..orderBy([(p) => drift.OrderingTerm.asc(p.name)]))
            .get();

    // Pre-fetch the default variant's color/size for every non-variant
    // product. The default variant exists in `product_variants` even when
    // `products.has_variants = 0`, and may carry color/size if the product
    // was previously a variant product or had its default variant tagged.
    // Without this, non-variant products render an empty chip while variant
    // products render "Color / Size" — which is exactly the discrepancy the
    // user sees in the picker and in the item card downstream.
    final defaultVariantRows = await db
        .customSelect(
          'SELECT pv.id AS variant_id, pv.product_id AS product_id, '
          '  pc.name AS color_name, sz.name AS size_name '
          'FROM product_variants pv '
          'JOIN products p ON p.id = pv.product_id '
          'LEFT JOIN product_colors pc ON pc.id = pv.color_id '
          'LEFT JOIN sizes sz ON sz.id = pv.size_id '
          'WHERE p.is_active = 1 AND p.has_variants = 0 AND pv.is_active = 1 '
          '  AND pv.id = (SELECT MIN(pv2.id) FROM product_variants pv2 '
          '               WHERE pv2.product_id = pv.product_id AND pv2.is_active = 1)',
        )
        .get();
    final defaultVariantLabels = <int, String?>{};
    // Resolve the actual default variant id for each non-variant product so
    // downstream stock adjustments hit the correct (color/size) row instead
    // of a non-existent NULL/NULL default — which would throw a StateError
    // inside StockService.adjustStock and surface to the user as a generic
    // "return failed" toast.
    final defaultVariantIds = <int, int>{};
    for (final r in defaultVariantRows) {
      final colorName = r.readNullable<String>('color_name');
      final sizeName = r.readNullable<String>('size_name');
      final parts = <String>[?colorName, ?sizeName];
      final productId = r.read<int>('product_id');
      defaultVariantLabels[productId] = parts.isNotEmpty
          ? parts.join(' / ')
          : null;
      defaultVariantIds[productId] = r.read<int>('variant_id');
    }

    final rows = <_PickerRow>[];
    for (final product in products) {
      final taxBps = widget.isSale
          ? product.salesTaxRateBps
          : product.purchaseTaxRateBps;

      if (product.hasVariants) {
        // `pv.*` already includes the nullable `last_purchase_price_cents`
        // column added in migration 10055 — read it explicitly below so the
        // purchase-adjustment-return picker can resolve the GROSS supplier
        // reference (Phase 15.2).
        final variantRows = await db
            .customSelect(
              'SELECT pv.*, pc.name AS color_name, sz.name AS size_name '
              'FROM product_variants pv '
              'LEFT JOIN product_colors pc ON pc.id = pv.color_id '
              'LEFT JOIN sizes sz ON sz.id = pv.size_id '
              'WHERE pv.product_id = ? AND pv.is_active = 1 '
              'ORDER BY pc.name ASC, sz.name ASC',
              variables: [drift.Variable.withInt(product.id)],
            )
            .get();

        for (final vr in variantRows) {
          final colorName = vr.readNullable<String>('color_name');
          final sizeName = vr.readNullable<String>('size_name');
          final parts = <String>[?colorName, ?sizeName];
          rows.add(
            _PickerRow(
              productId: product.id,
              variantId: vr.read<int>('id'),
              productName: product.name,
              variantLabel: parts.isNotEmpty ? parts.join(' / ') : null,
              sku: vr.readNullable<String>('sku'),
              priceCents: vr.read<int>('price_cents'),
              costCents: vr.read<int>('cost_cents'),
              lastPurchasePriceCents: vr.readNullable<int>(
                'last_purchase_price_cents',
              ),
              stockQuantity: vr.read<int>('stock_quantity'),
              measurementType: product.measurementType,
              taxRateBps: taxBps,
              hasVariants: true,
            ),
          );
        }
      } else {
        rows.add(
          _PickerRow(
            productId: product.id,
            variantId: defaultVariantIds[product.id],
            productName: product.name,
            variantLabel: defaultVariantLabels[product.id],
            sku: product.sku,
            priceCents: product.priceCents.toBigInt().toInt(),
            costCents: product.costCents.toBigInt().toInt(),
            lastPurchasePriceCents: product.lastPurchasePriceCents
                ?.toBigInt()
                .toInt(),
            stockQuantity: product.stockQuantity,
            measurementType: product.measurementType,
            taxRateBps: taxBps,
            hasVariants: false,
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    }
  }

  List<_PickerRow> get _filtered {
    if (_query.isEmpty) return _rows;
    final q = _query.toLowerCase();
    return _rows
        .where(
          (r) =>
              r.displayName.toLowerCase().contains(q) ||
              (r.sku?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = sl<CurrencyService>();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'returns.select_product'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'products_search_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final row = _filtered[i];
                  // Use the product-level flag so non-variant products that
                  // carry a default variant id still render the `package` icon,
                  // matching the rest of the app's product pickers/lists.
                  final isVariant = row.hasVariants;
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            (isVariant
                                    ? cs.secondaryContainer
                                    : cs.primaryContainer)
                                .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isVariant ? LucideIcons.layers : LucideIcons.package,
                        size: 18,
                        color: isVariant
                            ? cs.onSecondaryContainer
                            : cs.onPrimaryContainer,
                      ),
                    ),
                    title: Text(row.productName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (row.variantLabel != null)
                          Text(
                            row.variantLabel!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (row.sku != null)
                          Text(
                            row.sku!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Purchase-side picker MUST surface the supplier
                        // reference (GROSS cost), never the customer sell
                        // price. Phase 15.2 fix — `unitMoneyCents` collapses
                        // variant + no-variant to the same convention used
                        // by `purchase_form_screen.dart` (Phase 15.1).
                        Text(
                          curr.format(
                            row.unitMoneyCents(isSale: widget.isSale),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${'returns.stock'.tr()}: ${localizedQuantity(row.stockQuantity, row.measurementType)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    onTap: () => Navigator.pop(
                      context,
                      AdjReturnLineItem(
                        productId: row.productId,
                        variantId: row.variantId,
                        productName: row.productName,
                        variantLabel: row.variantLabel,
                        variantSku: row.sku,
                        quantity: row.measurementType == 'piece' ? 1 : 1000,
                        quantityScale: row.measurementType == 'piece'
                            ? 1
                            : 1000,
                        measurementType: row.measurementType,
                        // Auto-fill the new line with the side-correct money.
                        // Variant + no-variant resolve identically (Phase 15.2)
                        // — both fall through `lastPurchasePriceCents ?? costCents`
                        // for the purchase form, never the sell price.
                        unitPriceCents: row.unitMoneyCents(
                          isSale: widget.isSale,
                        ),
                        unitCostCents: row.costCents,
                        taxRateBps: row.taxRateBps,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// REASON CODE DROPDOWN
// Mandatory selector shown in the checkout sheet.
// ═══════════════════════════════════════════════════════════
class _ReasonDropdown extends StatelessWidget {
  final AdjReturnReasonCode? value;
  final bool isRequired;
  final ValueChanged<AdjReturnReasonCode> onChanged;

  const _ReasonDropdown({
    required this.value,
    required this.isRequired,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DropdownButtonFormField<AdjReturnReasonCode>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        hintText: 'returns.reason_hint'.tr(),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isRequired
                ? cs.error.withValues(alpha: 0.5)
                : cs.outlineVariant,
          ),
        ),
        isDense: true,
        prefixIcon: const Icon(LucideIcons.listChecks, size: 18),
      ),
      items: AdjReturnReasonCode.values
          .map((r) => DropdownMenuItem(value: r, child: Text(_label(r))))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  static String _label(AdjReturnReasonCode r) => switch (r) {
    AdjReturnReasonCode.damaged => 'returns.reason_damaged'.tr(),
    AdjReturnReasonCode.defective => 'returns.reason_defective'.tr(),
    AdjReturnReasonCode.wrongItem => 'returns.reason_wrong_item'.tr(),
    AdjReturnReasonCode.gift => 'returns.reason_gift'.tr(),
    AdjReturnReasonCode.goodwill => 'returns.reason_goodwill'.tr(),
    AdjReturnReasonCode.noReceipt => 'returns.reason_no_receipt'.tr(),
    AdjReturnReasonCode.other => 'returns.reason_other'.tr(),
  };
}

// ═══════════════════════════════════════════════════════════
// FRAUD-PREVENTION WARNINGS (soft, non-blocking)
// Shown after the items card. Queries `supplierId`'s historical
// supplied qty of each (product, variant) and warns when the
// supplier has never supplied it or the return qty exceeds history.
// ═══════════════════════════════════════════════════════════
class _PurchaseFraudWarnings extends StatelessWidget {
  final int? supplierId;
  final List<AdjReturnLineItem> items;

  const _PurchaseFraudWarnings({required this.supplierId, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty || supplierId == null) return const SizedBox.shrink();

    final dao = sl<AdjustmentReturnDao>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<List<_PurchaseItemWarning>>(
        future: Future.wait(
          items.map((it) async {
            final qty = await dao.getSupplierProductSuppliedQty(
              supplierId: supplierId!,
              productId: it.productId,
              variantId: it.variantId,
            );
            return _PurchaseItemWarning(item: it, historyQty: qty);
          }),
        ),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          final warnings = snap.data!
              .where((w) => w.historyQty == 0 || w.item.quantity > w.historyQty)
              .toList();
          if (warnings.isEmpty) return const SizedBox.shrink();
          return _buildCard(context, warnings);
        },
      ),
    );
  }

  Widget _buildCard(BuildContext context, List<_PurchaseItemWarning> warnings) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.shieldAlert,
                size: 16,
                color: Colors.amber.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                'returns.fraud_warnings_title'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.amber.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...warnings.map((w) {
            final never = w.historyQty == 0;
            final text = never
                ? '${w.item.displayName} — ${'returns.warning_never_supplied'.tr()}'
                : '${w.item.displayName} — ${'returns.warning_qty_exceeds_history'.tr(namedArgs: {'qty': '${w.item.quantity}', 'history': '${w.historyQty}'})}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.dot, size: 16, color: Colors.amber.shade700),
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.amber.shade900,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PurchaseItemWarning {
  final AdjReturnLineItem item;
  final int historyQty;
  const _PurchaseItemWarning({required this.item, required this.historyQty});
}
