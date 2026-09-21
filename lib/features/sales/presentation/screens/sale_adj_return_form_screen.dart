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
import '../../../employees/domain/repositories/employee_repository.dart';
import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/payments/checkout_settlement.dart';
import '../../../../core/payments/return_cheque_settlement_dialog.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/services/commissions/commission_service.dart';
import '../../../../core/services/loyalty/loyalty_points_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../../../core/widgets/pin_verification_dialog.dart';
import '../../../../core/widgets/action_confirmation_dialog.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../../settings/data/services/app_settings_service.dart';
import '../../../purchases/presentation/bloc/purchase_adj_return_form_bloc.dart'
    show AdjReturnLineItem, AdjReturnPaymentMethod, AdjReturnReasonCode;
import '../bloc/sale_adj_return_form_bloc.dart';

class SaleAdjReturnFormScreen extends StatelessWidget {
  final int? customerId;
  final String? customerName;
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

  const SaleAdjReturnFormScreen({
    super.key,
    this.customerId,
    this.customerName,
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
        final bloc = SaleAdjReturnFormBloc(
          sl<AdjustmentReturnDao>(),
          sl<JournalEntryService>(),
          sl<CommissionService>(),
          sl<LoyaltyPointsService>(),
          sl<SessionService>(),
          lan: sl<LanNetworkService>(),
          settings: sl<AppSettingsService>(),
        );
        if (customerId != null && customerName != null) {
          bloc.add(SaleAdjReturnCustomerSelected(customerId!, customerName!));
        }
        if (productId != null && productName != null) {
          bloc.add(
            SaleAdjReturnItemAdded(
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
    final state = context.read<SaleAdjReturnFormBloc>().state;
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

    return BlocConsumer<SaleAdjReturnFormBloc, SaleAdjReturnFormState>(
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
          router.go('/sales/returns');
          final lan = sl<LanNetworkService>();
          if (createdId != null && lan.snapshot.mode != LanMode.client) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              router.push('/sales/returns/adj/$createdId');
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
              title: Text('returns.sale_adjustment_return'.tr()),
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
                            _SaleFraudWarnings(
                              customerId: state.customerId,
                              employeeId: state.employeeId,
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
                  'returns.sale_adjustment_return_warning_body'.tr(),
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
    SaleAdjReturnFormState state,
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
                  context.read<SaleAdjReturnFormBloc>().add(
                    SaleAdjReturnDateChanged(date),
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
    SaleAdjReturnFormState state,
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
                      onQuantityChanged: (qty) => context
                          .read<SaleAdjReturnFormBloc>()
                          .add(SaleAdjReturnItemQuantityChanged(index, qty)),
                      onPriceChanged: (price) => context
                          .read<SaleAdjReturnFormBloc>()
                          .add(SaleAdjReturnItemPriceChanged(index, price)),
                      onDiscountChanged: (disc, bps) =>
                          context.read<SaleAdjReturnFormBloc>().add(
                            SaleAdjReturnItemDiscountChanged(
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
                        context.read<SaleAdjReturnFormBloc>().add(
                          SaleAdjReturnItemRemoved(index),
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
    final isRemote =
        lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession;

    final result = await showModalBottomSheet<AdjReturnLineItem>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => isRemote
          ? _RemoteProductPickerSheet(lan: lan)
          : _ProductPickerSheet(db: sl<AppDatabase>(), isSale: true),
    );

    if (result != null && context.mounted) {
      context.read<SaleAdjReturnFormBloc>().add(SaleAdjReturnItemAdded(result));
    }
  }

  // ═══════════════════════════════════════════════════════
  // DISCOUNT MODE TOGGLE
  // ═══════════════════════════════════════════════════════
  Widget _buildDiscountToggle(
    BuildContext context,
    SaleAdjReturnFormState state,
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
                  context.read<SaleAdjReturnFormBloc>().add(
                    SaleAdjReturnDiscountModeChanged(v.first),
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
    SaleAdjReturnFormState state,
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
                    'sales.total'.tr(),
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
                    '${state.items.length} ${'sales.items_count'.tr()}  •  $quantitySummary',
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
    SaleAdjReturnFormState state,
    CurrencyService cs,
  ) {
    // Capture bloc reference BEFORE showing the sheet to avoid
    // accessing a deactivated widget's ancestor if the parent navigates away.
    final bloc = context.read<SaleAdjReturnFormBloc>();
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
// CHECKOUT BOTTOM SHEET — customer, notes, financial summary, confirm
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
    final state = context.read<SaleAdjReturnFormBloc>().state;
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
        .read<SaleAdjReturnFormBloc>()
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
        .read<SaleAdjReturnFormBloc>()
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
    context.read<SaleAdjReturnFormBloc>().add(
      SaleAdjReturnOverallDiscountChanged(cents, false),
    );
  }

  void _showCustomerPicker(BuildContext context) async {
    final lan = sl<LanNetworkService>();
    if (lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession) {
      final customers = await lan.fetchRemoteCustomers(limit: 200);
      if (!context.mounted) return;
      final selected = await showModalBottomSheet<LanCustomerSummary>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _PartyPickerSheet<LanCustomerSummary>(
          title: 'returns.select_customer'.tr(),
          items: customers,
          getName: (customer) => customer.name,
          getInitial: (customer) =>
              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
        ),
      );
      if (selected != null && context.mounted) {
        context.read<SaleAdjReturnFormBloc>().add(
          SaleAdjReturnCustomerSelected(selected.id, selected.name),
        );
      }
      return;
    }

    final db = sl<AppDatabase>();
    final customers = await db.select(db.customers).get();
    customers.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (!context.mounted) return;

    final selected = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PartyPickerSheet<Customer>(
        title: 'returns.select_customer'.tr(),
        items: customers,
        getName: (c) => c.name,
        getInitial: (c) => c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
      ),
    );

    if (selected != null && context.mounted) {
      context.read<SaleAdjReturnFormBloc>().add(
        SaleAdjReturnCustomerSelected(selected.id, selected.name),
      );
    }
  }

  void _showEmployeePicker(BuildContext context) async {
    final lan = sl<LanNetworkService>();
    if (lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession) {
      final employees = await lan.fetchRemoteSalespeople(limit: 200);
      if (!context.mounted) return;
      final selected = await showModalBottomSheet<LanEmployeeSummary>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _PartyPickerSheet<LanEmployeeSummary>(
          title: 'sales.select_salesperson'.tr(),
          items: employees,
          getName: (employee) => employee.name,
          getInitial: (employee) =>
              employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
        ),
      );
      if (selected != null && context.mounted) {
        context.read<SaleAdjReturnFormBloc>().add(
          SaleAdjReturnEmployeeChanged(
            employeeId: selected.id,
            employeeName: selected.name,
          ),
        );
      }
      return;
    }

    final repo = sl<EmployeeRepository>();
    final employees = await repo.searchEmployees('', isActive: true);

    // Fetch roles to identify salesperson & manager role IDs.
    final allRoles = await repo.watchAllRoles(isActive: true).first;
    final salespersonRoleIds = <int>{};
    final managerRoleIds = <int>{};
    for (final role in allRoles) {
      final rn = role.name.toLowerCase();
      if (rn == 'salesperson') {
        salespersonRoleIds.add(role.id);
      } else if (rn == 'manager') {
        managerRoleIds.add(role.id);
      }
    }

    // Collect manager IDs of salespeople.
    final salespersonManagerIds = <int>{};
    for (final e in employees) {
      if (e.roleId != null && salespersonRoleIds.contains(e.roleId)) {
        if (e.managerId != null) {
          salespersonManagerIds.add(e.managerId!);
        }
      }
    }

    // Filter: keep salespeople, managers, and managers-of-salespeople.
    final filteredEmployees = employees.where((e) {
      if (e.roleId != null && salespersonRoleIds.contains(e.roleId)) {
        return true;
      }
      if (e.roleId != null && managerRoleIds.contains(e.roleId)) {
        return true;
      }
      if (salespersonManagerIds.contains(e.id)) {
        return true;
      }
      return false;
    }).toList();

    if (!context.mounted) return;

    final selected = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PartyPickerSheet<Employee>(
        title: 'sales.select_salesperson'.tr(),
        items: filteredEmployees,
        getName: (e) => e.name,
        getInitial: (e) => e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
      ),
    );

    if (selected != null && context.mounted) {
      context.read<SaleAdjReturnFormBloc>().add(
        SaleAdjReturnEmployeeChanged(
          employeeId: selected.id,
          employeeName: selected.name,
        ),
      );
    }
  }

  Future<void> _onConfirm(BuildContext context) async {
    final bloc = context.read<SaleAdjReturnFormBloc>();
    final state = bloc.state;
    final requirePin = context
        .read<AppSettingsBloc>()
        .state
        .settings
        .requirePinForVoidRefund;
    if (requirePin) {
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
      SaleAdjReturnSubmitted(
        settlementAllocations:
            state.paymentMethod == AdjReturnPaymentMethod.cheque
            ? allocations
            : const [],
      ),
    );
  }

  Future<void> _configureChequeSettlement(
    BuildContext context,
    SaleAdjReturnFormState state,
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
    context.read<SaleAdjReturnFormBloc>().add(
      SaleAdjReturnDueDateChanged(returnChequePrimaryDueDate(allocations)),
    );
  }

  Future<void> _changePaymentMethod(
    BuildContext context,
    SaleAdjReturnFormState state,
    AdjReturnPaymentMethod method,
  ) async {
    context.read<SaleAdjReturnFormBloc>().add(
      SaleAdjReturnPaymentMethodChanged(method),
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

    return BlocListener<SaleAdjReturnFormBloc, SaleAdjReturnFormState>(
      listenWhen: (prev, curr) => prev.isSuccess != curr.isSuccess,
      listener: (context, state) {
        // Success navigation is handled by the main screen's BlocConsumer.
        // Errors are shown inline in the sheet.
      },
      child: BlocBuilder<SaleAdjReturnFormBloc, SaleAdjReturnFormState>(
        builder: (context, state) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (context, scrollCtrl) => Column(
              children: [
                // Handle
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
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
                      // ── Customer Selection ──
                      _sectionHeader(
                        theme,
                        cs,
                        LucideIcons.users,
                        'sales.customer'.tr(),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showCustomerPicker(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: state.customerId == null
                                  ? cs.error.withValues(alpha: 0.5)
                                  : cs.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              if (state.customerName != null) ...[
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: cs.primaryContainer,
                                  child: Text(
                                    state.customerName![0].toUpperCase(),
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
                                  state.customerName ??
                                      'returns.select_customer'.tr(),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: state.customerName != null
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                    color: state.customerName != null
                                        ? null
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (state.customerId != null)
                                GestureDetector(
                                  onTap: () =>
                                      context.read<SaleAdjReturnFormBloc>().add(
                                        const SaleAdjReturnCustomerSelected(),
                                      ),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 4,
                                    ),
                                    child: Icon(
                                      LucideIcons.x,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
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
                      if (state.customerId == null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.tertiaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: cs.tertiary.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.info,
                                size: 14,
                                color: cs.tertiary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'returns.walk_in_customer'.tr(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.tertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Credit/cheque requires customer
                      if (state.customerId == null &&
                          (state.paymentMethod ==
                                  AdjReturnPaymentMethod.credit ||
                              state.paymentMethod ==
                                  AdjReturnPaymentMethod.cheque)) ...[
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
                                  'sales.customer_required_for_credit'.tr(),
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

                      // ── Salesperson ──
                      _sectionHeader(
                        theme,
                        cs,
                        LucideIcons.userCheck,
                        'sales.salesperson'.tr(),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showEmployeePicker(context),
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
                              if (state.employeeName != null) ...[
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: cs.tertiaryContainer,
                                  child: Text(
                                    state.employeeName![0].toUpperCase(),
                                    style: TextStyle(
                                      color: cs.onTertiaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Text(
                                  state.employeeName ??
                                      'sales.select_salesperson'.tr(),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: state.employeeName != null
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                    color: state.employeeName != null
                                        ? null
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (state.employeeId != null)
                                GestureDetector(
                                  onTap: () =>
                                      context.read<SaleAdjReturnFormBloc>().add(
                                        const SaleAdjReturnEmployeeChanged(),
                                      ),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 4,
                                    ),
                                    child: Icon(
                                      LucideIcons.x,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
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
                      const SizedBox(height: 20),

                      // ── Payment Method ──
                      _sectionHeader(
                        theme,
                        cs,
                        LucideIcons.wallet,
                        'sales.payment_method'.tr(),
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
                            .read<SaleAdjReturnFormBloc>()
                            .add(SaleAdjReturnReasonChanged(r)),
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
                            .read<SaleAdjReturnFormBloc>()
                            .add(SaleAdjReturnNotesChanged(v)),
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
                              'sales.subtotal'.tr(),
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
                                (state.taxInclusivePricing
                                        ? 'returns.tax_included'
                                        : 'sales.tax')
                                    .tr(),
                                '${state.taxInclusivePricing ? '' : '+ '}${curr.format(state.totalAdjustedTaxCents)}',
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
                              'returns.total_refund'.tr(),
                              curr.format(state.totalCents),
                              isBold: true,
                              valueColor: cs.error,
                            ),
                            // ── Loyalty points deduction (req 3 + 4) ──
                            // Shown only for a credit return with a selected
                            // customer: the points that will be deducted plus
                            // their monetary value in cents and the selected
                            // currency.
                            if (state.loyaltyEnabled &&
                                state.loyaltyPointsToDeduct > 0) ...[
                              const SizedBox(height: 8),
                              _summaryRow(
                                theme,
                                'returns.loyalty_points_deducted'.tr(),
                                '- ${state.loyaltyPointsToDeduct} ${'sales.points'.tr()}',
                                valueColor: cs.tertiary,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'returns.loyalty_points_value'.tr(),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    'returns.loyalty_points_value_detail'.tr(
                                      namedArgs: {
                                        'points':
                                            '${state.loyaltyPointsToDeduct}',
                                        'cents':
                                            '${state.loyaltyDeductionValueCents}',
                                        'amount': curr.format(
                                          state.loyaltyDeductionValueCents,
                                        ),
                                      },
                                    ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Fraud-prevention warnings (shown inline so the user
                      //    sees them right before confirming the refund) ──
                      _SaleFraudWarnings(
                        customerId: state.customerId,
                        employeeId: state.employeeId,
                        items: state.items,
                      ),

                      // ── Warning ──
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

                // Bottom actions
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
                                'returns.total_refund'.tr(),
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
                              final customerRequiredButMissing =
                                  (state.paymentMethod ==
                                          AdjReturnPaymentMethod.credit ||
                                      state.paymentMethod ==
                                          AdjReturnPaymentMethod.cheque) &&
                                  state.customerId == null;
                              final reasonMissing = state.reasonCode == null;
                              final canConfirm =
                                  !state.isSubmitting &&
                                  !chequeNoDueDate &&
                                  !customerRequiredButMissing &&
                                  !reasonMissing;
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
      Expanded(
        child: Text(
          l,
          style: (isBold ? t.textTheme.titleSmall : t.textTheme.bodyMedium)
              ?.copyWith(color: isBold ? null : t.colorScheme.onSurfaceVariant),
        ),
      ),
      const SizedBox(width: 8),
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
    AdjReturnPaymentMethod.cash => 'sales.payment_cash'.tr(),
    AdjReturnPaymentMethod.card => 'sales.payment_card'.tr(),
    AdjReturnPaymentMethod.credit => 'sales.payment_credit'.tr(),
    AdjReturnPaymentMethod.cheque => 'sales.payment_cheque'.tr(),
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
// Price/discount/tax editing lives in a bottom sheet.
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
        .read<SaleAdjReturnFormBloc>()
        .state
        .discountPerItem;
    final db = sl<AppDatabase>();
    int stockQty = 0;
    // Resolve live retail + wholesale reference prices so the edit sheet can
    // offer the retail/wholesale tier shortcuts regardless of how the line was
    // originally added (picker, external navigation, or a pre-existing item).
    int? retailCents = widget.item.retailPriceCents;
    int? wholesaleCents = widget.item.wholesalePriceCents;
    try {
      if (widget.item.variantId != null) {
        final v = await (db.select(
          db.productVariants,
        )..where((t) => t.id.equals(widget.item.variantId!))).getSingleOrNull();
        stockQty = v?.stockQuantity ?? 0;
        retailCents = v?.priceCents.toBigInt().toInt() ?? retailCents;
        wholesaleCents =
            v?.wholesalePriceCents?.toBigInt().toInt() ?? wholesaleCents;
      } else {
        final p = await (db.select(
          db.products,
        )..where((t) => t.id.equals(widget.item.productId))).getSingleOrNull();
        stockQty = p?.stockQuantity ?? 0;
        retailCents = p?.priceCents.toBigInt().toInt() ?? retailCents;
        wholesaleCents =
            p?.wholesalePriceCents?.toBigInt().toInt() ?? wholesaleCents;
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
        retailPriceCents: retailCents,
        wholesalePriceCents: wholesaleCents,
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
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.error,
                      ),
                      onTap: () => selectAllText(_qtyCtrl),
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
            // Name + details
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
            // Total
            Text(
              curr.format(item.totalCents),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.error,
              ),
            ),
            // Edit icon
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _showEditSheet(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(LucideIcons.pencil, size: 14, color: cs.primary),
              ),
            ),
            // Delete icon
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

  /// Live retail selling price resolved from the DB at open time. Falls back to
  /// the value captured on the line item when null. Drives the "retail" tier
  /// shortcut so it works regardless of how the line was originally added.
  final int? retailPriceCents;

  /// Live wholesale selling price resolved from the DB at open time (nullable
  /// when the product/variant has none). Drives the "wholesale" tier shortcut.
  final int? wholesalePriceCents;

  const _ItemEditSheet({
    required this.item,
    required this.currencyService,
    required this.onPriceChanged,
    required this.onDiscountChanged,
    this.showDiscount = true,
    this.stockQuantity = 0,
    this.retailPriceCents,
    this.wholesalePriceCents,
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

  /// A tappable price shortcut (retail / wholesale). Tapping snaps the unit
  /// price field to [priceCents] and re-applies it to the line.
  Widget _priceTierBtn(
    ColorScheme cs,
    ThemeData theme,
    String tier,
    int priceCents,
    CurrencyService curr,
  ) {
    final priceStr = (priceCents / 100).toStringAsFixed(2);
    final isActive = _priceCtrl.text == priceStr;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        _priceCtrl.text = priceStr;
        _applyPrice();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tier,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              curr.format(priceCents),
              style: theme.textTheme.labelSmall?.copyWith(
                color: isActive ? cs.onPrimary : cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
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
  AdjReturnLineItem get _liveItem => widget.item.copyWith(
    unitPriceCents: _livePriceCents,
    discountCents: _liveDiscount,
    discountPercentBps: 0,
  );
  int get _liveTax => _liveItem.taxCents;
  int get _liveTotal => _liveItem.totalCents;

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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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
            // Title
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
                    localizedQuantity(
                      widget.stockQuantity,
                      item.measurementType,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: widget.stockQuantity > 0 ? cs.primary : cs.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Unit price
            Text(
              'sales.unit_price'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            // Price tier shortcuts — let the user return at the regular retail
            // price or the customer's wholesale price. Prices are resolved live
            // from the DB when the sheet opens, falling back to whatever was
            // captured on the line item, so the shortcut works regardless of how
            // the line was originally added.
            Builder(
              builder: (context) {
                final retail = widget.retailPriceCents ?? item.retailPriceCents;
                final wholesale =
                    widget.wholesalePriceCents ?? item.wholesalePriceCents;
                if (retail == null && wholesale == null) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (retail != null)
                          _priceTierBtn(
                            cs,
                            theme,
                            'sales.retail_price'.tr(),
                            retail,
                            curr,
                          ),
                        if (wholesale != null) ...[
                          const SizedBox(width: 6),
                          _priceTierBtn(
                            cs,
                            theme,
                            'sales.wholesale_price'.tr(),
                            wholesale,
                            curr,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
            TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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

            // Discount with $/% toggle
            if (widget.showDiscount) ...[
              Row(
                children: [
                  Text(
                    'sales.item_discount'.tr(),
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

            // Tax info (read-only) — uses live values
            if (item.taxRateBps > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
                      (item.taxInclusivePricing
                              ? 'returns.tax_included'
                              : 'sales.tax')
                          .tr(),
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

            // Summary — uses live computed values
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
                        'sales.subtotal'.tr(),
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
                          'sales.discount'.tr(),
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
                          (item.taxInclusivePricing
                                  ? 'returns.tax_included'
                                  : 'sales.tax')
                              .tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${item.taxInclusivePricing ? '' : '+'}${curr.format(_liveTax)}',
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
                        'sales.total'.tr(),
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PARTY PICKER SHEET
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

  /// Wholesale selling price (nullable when the product/variant has none).
  final int? wholesalePriceCents;
  final int costCents;
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
    this.wholesalePriceCents,
    required this.costCents,
    required this.stockQuantity,
    required this.measurementType,
    required this.taxRateBps,
    required this.hasVariants,
  });

  String get displayName {
    if (variantLabel != null && variantLabel!.isNotEmpty) {
      return '$productName ($variantLabel)';
    }
    return productName;
  }
}

class _RemoteProductPickerSheet extends StatefulWidget {
  final LanNetworkService lan;

  const _RemoteProductPickerSheet({required this.lan});

  @override
  State<_RemoteProductPickerSheet> createState() =>
      _RemoteProductPickerSheetState();
}

class _RemoteProductPickerSheetState extends State<_RemoteProductPickerSheet> {
  final _searchController = TextEditingController();
  List<_PickerRow> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load([String query = '']) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.lan.fetchRemoteCatalog(
        query: query,
        limit: 200,
      );
      final rows = <_PickerRow>[];
      for (final product in page.products) {
        if (product.hasVariants) {
          for (final variant in product.variants) {
            rows.add(
              _PickerRow(
                productId: product.id,
                variantId: variant.id,
                productName: product.name,
                variantLabel: variant.label,
                sku: variant.sku,
                priceCents: variant.priceCents,
                wholesalePriceCents: variant.wholesalePriceCents,
                costCents: 0,
                stockQuantity: variant.stockQuantity,
                measurementType: product.measurementType,
                taxRateBps: product.salesTaxRateBps,
                hasVariants: true,
              ),
            );
          }
        } else {
          final defaultVariant = product.variants.isEmpty
              ? null
              : product.variants.first;
          final label = defaultVariant?.label;
          rows.add(
            _PickerRow(
              productId: product.id,
              variantId: defaultVariant?.id,
              productName: product.name,
              variantLabel: label == 'Default' ? null : label,
              sku: product.sku ?? defaultVariant?.sku,
              priceCents: product.priceCents,
              wholesalePriceCents: product.wholesalePriceCents,
              costCents: 0,
              stockQuantity: product.stockQuantity,
              measurementType: product.measurementType,
              taxRateBps: product.salesTaxRateBps,
              hasVariants: false,
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currency = sl<CurrencyService>();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
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
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'products_search_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: IconButton(
                  onPressed: () => _load(_searchController.text.trim()),
                  icon: const Icon(LucideIcons.arrowRight, size: 18),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onSubmitted: (value) => _load(value.trim()),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!)))
          else if (_rows.isEmpty)
            Expanded(child: Center(child: Text('common.no_results'.tr())))
          else
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _rows.length,
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return ListTile(
                    leading: Icon(
                      row.hasVariants
                          ? LucideIcons.layers
                          : LucideIcons.package,
                    ),
                    title: Text(row.productName),
                    subtitle: Text(
                      [row.variantLabel, row.sku]
                          .whereType<String>()
                          .where((value) => value.trim().isNotEmpty)
                          .join(' • '),
                    ),
                    trailing: Text(currency.format(row.priceCents)),
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
                        unitPriceCents: row.priceCents,
                        retailPriceCents: row.priceCents,
                        wholesalePriceCents: row.wholesalePriceCents,
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
    // products render "Color / Size" — the discrepancy the user sees in the
    // picker and in the item card downstream.
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
              wholesalePriceCents: vr.readNullable<int>(
                'wholesale_price_cents',
              ),
              costCents: vr.read<int>('cost_cents'),
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
            wholesalePriceCents: product.wholesalePriceCents
                ?.toBigInt()
                .toInt(),
            costCents: product.costCents.toBigInt().toInt(),
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
                        Text(
                          curr.format(row.priceCents),
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
                        unitPriceCents: row.priceCents,
                        unitCostCents: row.costCents,
                        retailPriceCents: row.priceCents,
                        wholesalePriceCents: row.wholesalePriceCents,
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
// For each line item, checks the selected customer's historical
// purchase quantity of that (product, variant) and warns when:
//   1. the customer never bought this product, or
//   2. the return quantity exceeds the historical purchased qty.
// If no customer is selected, shows a hint to pick one.
// ═══════════════════════════════════════════════════════════
class _SaleFraudWarnings extends StatelessWidget {
  final int? customerId;
  final int? employeeId;
  final List<AdjReturnLineItem> items;

  const _SaleFraudWarnings({
    required this.customerId,
    this.employeeId,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final lan = sl<LanNetworkService>();
    if (lan.snapshot.mode == LanMode.client) {
      return const SizedBox.shrink();
    }
    // Nothing attributed (no customer AND no salesperson) or no items:
    // nothing to verify.
    if (items.isEmpty || (customerId == null && employeeId == null)) {
      return const SizedBox.shrink();
    }

    final dao = sl<AdjustmentReturnDao>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<List<_ItemWarning>>(
        future: Future.wait(
          items.map((it) async {
            final custQty = customerId == null
                ? -1 // sentinel: customer check skipped (walk-in)
                : await dao.getCustomerProductPurchasedQty(
                    customerId: customerId,
                    productId: it.productId,
                    variantId: it.variantId,
                  );
            final empQty = employeeId == null
                ? -1 // sentinel: salesperson check skipped
                : await dao.getEmployeeProductSoldQty(
                    employeeId: employeeId,
                    productId: it.productId,
                    variantId: it.variantId,
                  );
            return _ItemWarning(
              item: it,
              historyQty: custQty,
              employeeSoldQty: empQty,
            );
          }),
        ),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          final warnings = snap.data!
              .where(
                (w) =>
                    (w.historyQty >= 0 &&
                        (w.historyQty == 0 ||
                            w.item.quantity > w.historyQty)) ||
                    (w.employeeSoldQty == 0),
              )
              .toList();
          if (warnings.isEmpty) return const SizedBox.shrink();
          return _buildWarningsCard(context, warnings);
        },
      ),
    );
  }

  Widget _buildWarningsCard(BuildContext context, List<_ItemWarning> warnings) {
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
          ...warnings.expand((w) {
            final lines = <String>[];
            // Customer-history messages (skipped when historyQty == -1).
            if (w.historyQty == 0) {
              lines.add(
                '${w.item.displayName} — ${'returns.warning_never_bought'.tr()}',
              );
            } else if (w.historyQty > 0 && w.item.quantity > w.historyQty) {
              lines.add(
                '${w.item.displayName} — ${'returns.warning_qty_exceeds_history'.tr(namedArgs: {'qty': '${w.item.quantity}', 'history': '${w.historyQty}'})}',
              );
            }
            // Salesperson-attribution message (skipped when empQty == -1).
            if (w.employeeSoldQty == 0) {
              lines.add(
                '${w.item.displayName} — ${'returns.warning_employee_never_sold'.tr()}',
              );
            }
            return lines.map(
              (text) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.dot,
                      size: 16,
                      color: Colors.amber.shade700,
                    ),
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
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ItemWarning {
  final AdjReturnLineItem item;

  /// Customer historical purchased qty. `-1` = check skipped (walk-in).
  final int historyQty;

  /// Quantity the attributed salesperson has sold. `-1` = check skipped
  /// (no salesperson selected); `0` = salesperson never sold this product.
  final int employeeSoldQty;

  const _ItemWarning({
    required this.item,
    required this.historyQty,
    this.employeeSoldQty = -1,
  });
}
