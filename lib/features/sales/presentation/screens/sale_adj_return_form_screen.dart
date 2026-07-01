import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../core/di/injection_container.dart';
import '../../../../core/database/app_database.dart' hide Size;
import '../../../employees/domain/repositories/employee_repository.dart';
import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
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
    this.taxRateBps,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final bloc = SaleAdjReturnFormBloc(
          sl<AdjustmentReturnDao>(),
          sl<JournalEntryService>(),
        );
        if (customerId != null && customerName != null) {
          bloc.add(SaleAdjReturnCustomerSelected(customerId!, customerName!));
        }
        if (productId != null && productName != null) {
          bloc.add(SaleAdjReturnItemAdded(AdjReturnLineItem(
            productId: productId!,
            variantId: variantId,
            productName: productName!,
            variantSku: productSku,
            variantLabel: variantLabel,
            quantity: 1,
            unitPriceCents: productPrice ?? 0,
            taxRateBps: taxRateBps ?? 0,
          )));
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
      listenWhen: (prev, curr) =>
          prev.isSuccess != curr.isSuccess,
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
          Navigator.of(context).popUntil((route) => !route.isActive || route is! PopupRoute);
          final createdId = state.createdReturnId;
          // Replace form with returns list, then push detail on top
          // so that Back from detail returns to the list.
          router.go('/sales/returns');
          if (createdId != null) {
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
          Icon(LucideIcons.alertTriangle, size: 18, color: Colors.amber.shade700),
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
  Widget _buildReturnHeaderCard(BuildContext context, SaleAdjReturnFormState state) {
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
                Text('returns.return_number_label'.tr(),
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
                    state.returnNumber ?? '—',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: cs.primary),
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
                  context.read<SaleAdjReturnFormBloc>().add(SaleAdjReturnDateChanged(date));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('returns.return_date'.tr(),
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
                            intl.DateFormat.yMd().format(state.returnDate),
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
  // ITEMS CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsCard(
      BuildContext context, SaleAdjReturnFormState state, CurrencyService cs) {
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
                      colors: [
                        colorScheme.error,
                        colorScheme.error.withValues(alpha: 0.7)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.package, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('returns.return_items'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (state.items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${state.items.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold)),
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
                          color:
                              colorScheme.errorContainer.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(LucideIcons.packageX,
                            size: 36,
                            color: colorScheme.error.withValues(alpha: 0.3)),
                      ),
                      const SizedBox(height: 12),
                      Text('returns.no_items_yet'.tr(),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant)),
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
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                      onDiscountChanged: (disc, bps) => context
                          .read<SaleAdjReturnFormBloc>()
                          .add(SaleAdjReturnItemDiscountChanged(
                            index,
                            disc,
                            discountPercentBps: bps,
                          )),
                      onRemove: () => context
                          .read<SaleAdjReturnFormBloc>()
                          .add(SaleAdjReturnItemRemoved(index)),
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
    final db = sl<AppDatabase>();

    final result = await showModalBottomSheet<AdjReturnLineItem>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ProductPickerSheet(db: db, isSale: true),
    );

    if (result != null && context.mounted) {
      context
          .read<SaleAdjReturnFormBloc>()
          .add(SaleAdjReturnItemAdded(result));
    }
  }

  // ═══════════════════════════════════════════════════════
  // DISCOUNT MODE TOGGLE
  // ═══════════════════════════════════════════════════════
  Widget _buildDiscountToggle(BuildContext context, SaleAdjReturnFormState state) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Icon(LucideIcons.tag, size: 16, color: cs.primary), const SizedBox(width: 8),
        Flexible(
          child: Text('returns.discount_mode'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  ButtonSegment(value: true, label: Text('returns.discount_per_item'.tr(), style: const TextStyle(fontSize: 12))),
                  ButtonSegment(value: false, label: Text('returns.discount_overall'.tr(), style: const TextStyle(fontSize: 12))),
                ],
                selected: {state.discountPerItem},
                onSelectionChanged: (v) {
                  context.read<SaleAdjReturnFormBloc>().add(
                      SaleAdjReturnDiscountModeChanged(v.first));
                },
                style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
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
      BuildContext context, SaleAdjReturnFormState state, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
            top: BorderSide(
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('sales.total'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant)),
                  Text(cs.format(state.totalCents),
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold, color: colorScheme.error)),
                  Text(
                    '${state.items.length} ${'sales.items_count'.tr()}  •  ${state.totalQuantity} ${'sales.pieces'.tr().toLowerCase()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant)),
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

  void _showCheckoutSheet(BuildContext context,
      SaleAdjReturnFormState state, CurrencyService cs) {
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

  @override
  void initState() {
    super.initState();
    final state = context.read<SaleAdjReturnFormBloc>().state;
    _notesCtrl.text = state.notes ?? '';
    if (state.overallDiscountCents > 0) {
      _discountFixedCtrl.text = (state.overallDiscountCents / 100).toStringAsFixed(2);
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
        SaleAdjReturnOverallDiscountChanged(cents, false));
  }

  void _showCustomerPicker(BuildContext context) async {
    final db = sl<AppDatabase>();
    final customers = await db.select(db.customers).get();
    customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
      context.read<SaleAdjReturnFormBloc>()
          .add(SaleAdjReturnCustomerSelected(selected.id, selected.name));
    }
  }

  void _showEmployeePicker(BuildContext context) async {
    final employees = await sl<EmployeeRepository>().searchEmployees('', isActive: true);
    if (!context.mounted) return;

    final selected = await showModalBottomSheet<Employee>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PartyPickerSheet<Employee>(
        title: 'sales.select_salesperson'.tr(),
        items: employees,
        getName: (e) => e.name,
        getInitial: (e) => e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
      ),
    );

    if (selected != null && context.mounted) {
      context.read<SaleAdjReturnFormBloc>()
          .add(SaleAdjReturnEmployeeChanged(
              employeeId: selected.id, employeeName: selected.name));
    }
  }

  void _onConfirm(BuildContext context) {
    context.read<SaleAdjReturnFormBloc>().add(const SaleAdjReturnSubmitted());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = widget.currencyService;

    return BlocListener<SaleAdjReturnFormBloc, SaleAdjReturnFormState>(
      listenWhen: (prev, curr) =>
          prev.isSuccess != curr.isSuccess,
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
          builder: (context, scrollCtrl) => Column(children: [
            // Handle
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(LucideIcons.shoppingBag, size: 20, color: cs.error),
                const SizedBox(width: 8),
                Text('returns.checkout'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('common.cancel'.tr())),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // ── Customer Selection ──
                  _sectionHeader(theme, cs, LucideIcons.users, 'sales.customer'.tr()),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showCustomerPicker(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: state.customerId == null
                            ? cs.error.withValues(alpha: 0.5)
                            : cs.outlineVariant),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        if (state.customerName != null) ...[
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: cs.primaryContainer,
                            child: Text(
                                state.customerName![0].toUpperCase(),
                                style: TextStyle(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(child: Text(
                          state.customerName ?? 'returns.select_customer'.tr(),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: state.customerName != null
                                ? FontWeight.w500
                                : FontWeight.normal,
                            color: state.customerName != null
                                ? null
                                : cs.onSurfaceVariant),
                        )),
                        if (state.customerId != null)
                          GestureDetector(
                            onTap: () => context.read<SaleAdjReturnFormBloc>()
                                .add(const SaleAdjReturnCustomerSelected()),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant),
                            ),
                          ),
                        Icon(LucideIcons.chevronDown, size: 18, color: cs.onSurfaceVariant),
                      ]),
                    ),
                  ),
                  if (state.customerId == null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.tertiary.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        Icon(LucideIcons.info, size: 14, color: cs.tertiary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('returns.walk_in_customer'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.tertiary))),
                      ]),
                    ),
                  ],
                  // Credit/cheque requires customer
                  if (state.customerId == null &&
                      (state.paymentMethod == AdjReturnPaymentMethod.credit ||
                       state.paymentMethod == AdjReturnPaymentMethod.cheque)) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.error.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        Icon(LucideIcons.alertTriangle, size: 14, color: cs.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text('sales.customer_required_for_credit'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.error))),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // ── Salesperson ──
                  _sectionHeader(theme, cs, LucideIcons.userCheck, 'sales.salesperson'.tr()),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showEmployeePicker(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        if (state.employeeName != null) ...[
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: cs.tertiaryContainer,
                            child: Text(
                                state.employeeName![0].toUpperCase(),
                                style: TextStyle(
                                    color: cs.onTertiaryContainer,
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(child: Text(
                          state.employeeName ?? 'sales.select_salesperson'.tr(),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: state.employeeName != null
                                ? FontWeight.w500
                                : FontWeight.normal,
                            color: state.employeeName != null
                                ? null
                                : cs.onSurfaceVariant),
                        )),
                        if (state.employeeId != null)
                          GestureDetector(
                            onTap: () => context.read<SaleAdjReturnFormBloc>()
                                .add(const SaleAdjReturnEmployeeChanged()),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(end: 4),
                              child: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant),
                            ),
                          ),
                        Icon(LucideIcons.chevronDown, size: 18, color: cs.onSurfaceVariant),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Payment Method ──
                  _sectionHeader(theme, cs, LucideIcons.wallet, 'sales.payment_method'.tr()),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8,
                    children: AdjReturnPaymentMethod.values.map((m) {
                      final sel = state.paymentMethod == m;
                      return ChoiceChip(
                        label: Text(_pmLabel(m)), selected: sel,
                        onSelected: (_) => context.read<SaleAdjReturnFormBloc>()
                            .add(SaleAdjReturnPaymentMethodChanged(m)),
                        avatar: Icon(_pmIcon(m), size: 16),
                        selectedColor: cs.primaryContainer, showCheckmark: false,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // ── Cheque due date ──
                  if (state.paymentMethod == AdjReturnPaymentMethod.cheque) ...[
                    _sectionHeader(theme, cs, LucideIcons.calendar, 'sales.cheque_due_date'.tr()),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: state.dueDate ?? DateTime.now().add(const Duration(days: 30)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null && context.mounted) {
                          context.read<SaleAdjReturnFormBloc>().add(SaleAdjReturnDueDateChanged(picked));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: state.dueDate == null
                              ? cs.error.withValues(alpha: 0.5)
                              : cs.outlineVariant),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Icon(LucideIcons.calendar, size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            state.dueDate != null
                                ? '${state.dueDate!.year}-${state.dueDate!.month.toString().padLeft(2, '0')}-${state.dueDate!.day.toString().padLeft(2, '0')}'
                                : 'sales.select_due_date'.tr(),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: state.dueDate != null ? null : cs.onSurfaceVariant),
                          )),
                          Icon(LucideIcons.chevronDown, size: 18, color: cs.onSurfaceVariant),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Reason (required) ──
                  _sectionHeader(theme, cs, LucideIcons.listChecks, 'returns.reason_label'.tr()),
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
                  _sectionHeader(theme, cs, LucideIcons.stickyNote, 'returns.notes'.tr()),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'returns.notes_hint'.tr(),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true),
                    onChanged: (v) => context.read<SaleAdjReturnFormBloc>()
                        .add(SaleAdjReturnNotesChanged(v)),
                  ),
                  const SizedBox(height: 20),

                  // ── Overall Discount (when mode is not per-item) ──
                  if (!state.discountPerItem) ...[
                    _sectionHeader(theme, cs, LucideIcons.tag, 'returns.overall_discount'.tr()),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _discountFixedCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
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
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                            onTap: () => selectAllText(_discountPercentCtrl),
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
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Column(children: [
                      _summaryRow(theme, 'sales.subtotal'.tr(),
                          curr.format(state.totalSubtotalCents)),
                      if (state.totalItemDiscountCents > 0) ...[
                        const SizedBox(height: 8),
                        _summaryRow(theme, 'returns.item_discounts'.tr(),
                            '- ${curr.format(state.totalItemDiscountCents)}',
                            valueColor: Colors.orange),
                      ],
                      if (state.totalAdjustedTaxCents > 0) ...[
                        const SizedBox(height: 8),
                        _summaryRow(theme, 'sales.tax'.tr(),
                            '+ ${curr.format(state.totalAdjustedTaxCents)}',
                            valueColor: cs.tertiary),
                      ],
                      if (state.effectiveOverallDiscountCents > 0) ...[
                        const SizedBox(height: 8),
                        _summaryRow(theme, 'returns.overall_discount'.tr(),
                            '- ${curr.format(state.effectiveOverallDiscountCents)}',
                            valueColor: Colors.deepOrange),
                      ],
                      Divider(height: 20, color: cs.outlineVariant.withValues(alpha: 0.5)),
                      _summaryRow(theme, 'returns.total_refund'.tr(),
                          curr.format(state.totalCents),
                          isBold: true, valueColor: cs.error),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // ── Fraud-prevention warnings (shown inline so the user
                  //    sees them right before confirming the refund) ──
                  _SaleFraudWarnings(
                    customerId: state.customerId,
                    items: state.items,
                  ),

                  // ── Warning ──
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(LucideIcons.alertTriangle, size: 14, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Text('returns.confirm_post_warning'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.amber.shade800))),
                    ]),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),

            // ── Inline error banner (above bottom bar) ──
            if (state.error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: cs.errorContainer,
                child: Row(
                  children: [
                    Icon(LucideIcons.alertCircle, size: 16, color: cs.error),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
                boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.05),
                    blurRadius: 8, offset: const Offset(0, -2))],
              ),
              child: SafeArea(child: Row(children: [
                Expanded(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('returns.total_refund'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant)),
                      Text(curr.format(state.totalCents),
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold, color: cs.error)),
                    ])),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Builder(builder: (ctx) {
                    final chequeNoDueDate = state.paymentMethod == AdjReturnPaymentMethod.cheque &&
                        state.dueDate == null;
                    final customerRequiredButMissing =
                        (state.paymentMethod == AdjReturnPaymentMethod.credit ||
                         state.paymentMethod == AdjReturnPaymentMethod.cheque) &&
                        state.customerId == null;
                    final reasonMissing = state.reasonCode == null;
                    final canConfirm = !state.isSubmitting && !chequeNoDueDate && !customerRequiredButMissing && !reasonMissing;
                    return FilledButton.icon(
                    onPressed: canConfirm
                        ? () => _onConfirm(context)
                        : null,
                    icon: state.isSubmitting
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.check, size: 18),
                    label: Text('returns.confirm_save'.tr()),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: cs.error),
                  );
                  }),
                ),
              ])),
            ),
          ]),
        );
      },
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, ColorScheme cs, IconData icon, String title) =>
      Row(children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      ]);

  Widget _summaryRow(ThemeData t, String l, String v,
      {bool isBold = false, Color? valueColor}) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: (isBold ? t.textTheme.titleSmall : t.textTheme.bodyMedium)?.copyWith(
            color: isBold ? null : t.colorScheme.onSurfaceVariant)),
        Text(v, style: (isBold ? t.textTheme.titleMedium : t.textTheme.bodyMedium)?.copyWith(
            color: valueColor, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
      ]);

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

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.item.quantity}');
  }

  @override
  void didUpdateWidget(covariant _AdjReturnItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.quantity != oldWidget.item.quantity &&
        _qtyCtrl.text != '${widget.item.quantity}') {
      _qtyCtrl.text = '${widget.item.quantity}';
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _showEditSheet(BuildContext context) async {
    final discountPerItem = context.read<SaleAdjReturnFormBloc>().state.discountPerItem;
    final db = sl<AppDatabase>();
    int stockQty = 0;
    try {
      if (widget.item.variantId != null) {
        final v = await (db.select(db.productVariants)..where((t) => t.id.equals(widget.item.variantId!))).getSingleOrNull();
        stockQty = v?.stockQuantity ?? 0;
      } else {
        final p = await (db.select(db.products)..where((t) => t.id.equals(widget.item.productId))).getSingleOrNull();
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
                  borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: item.quantity > 1
                      ? () => widget.onQuantityChanged(item.quantity - 1)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(LucideIcons.minus, size: 12,
                        color: item.quantity > 1
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.3)),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold, color: cs.error),
                    onTap: () => selectAllText(_qtyCtrl),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null && parsed > 0) {
                        widget.onQuantityChanged(parsed);
                      }
                    },
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.onQuantityChanged(item.quantity + 1),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(LucideIcons.plus, size: 12, color: cs.onSurface),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            // Name + details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Wrap(spacing: 6, runSpacing: 2, children: [
                    if (item.variantLabel != null && item.variantLabel!.isNotEmpty)
                      Text(item.variantLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.primary, fontWeight: FontWeight.w500)),
                    if (item.variantSku != null && item.variantSku!.isNotEmpty)
                      Text('#${item.variantSku!}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
                    Text('${curr.format(item.unitPriceCents)} × ${item.quantity}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant)),
                    if (item.discountCents > 0)
                      Text('-${curr.format(item.discountCents)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.orange)),
                    if (item.taxRateBps > 0)
                      Text('+${(item.taxRateBps / 100).toStringAsFixed(1)}%',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.tertiary)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Total
            Text(curr.format(item.totalCents),
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: cs.error)),
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
        text: (widget.item.unitPriceCents / 100).toStringAsFixed(2));
    // Pre-populate the sheet using whichever discount form was previously
    // saved on the line. A percent (basis-points) value takes precedence so
    // the user keeps editing the same semantic value they entered before.
    if (widget.item.discountPercentBps > 0) {
      _discountIsPercent = true;
      _discountCtrl = TextEditingController(
          text: (widget.item.discountPercentBps / 100).toStringAsFixed(2));
    } else {
      _discountIsPercent = false;
      _discountCtrl = TextEditingController(
          text: widget.item.discountCents > 0
              ? (widget.item.discountCents / 100).toStringAsFixed(2)
              : '');
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
      final subtotal = (price * 100).round() * widget.item.quantity;
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
  int get _livePriceCents => ((double.tryParse(_priceCtrl.text) ?? 0) * 100).round();
  int get _liveSubtotal => _livePriceCents * widget.item.quantity;
  int get _liveDiscount => _computeDiscountCents();
  int get _liveNet => (_liveSubtotal - _liveDiscount).clamp(0, 999999999);
  int get _liveTax => widget.item.taxRateBps > 0 ? (_liveNet * widget.item.taxRateBps / 10000).round() : 0;
  int get _liveTotal => _liveNet + _liveTax;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = widget.currencyService;
    final item = widget.item;

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),
          // Title
          Row(children: [
            Icon(LucideIcons.pencil, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(item.displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold))),
            Text(curr.format(_liveTotal),
                style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: cs.error)),
          ]),
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
            child: Row(children: [
              Icon(LucideIcons.warehouse, size: 16,
                  color: widget.stockQuantity > 0 ? cs.primary : cs.error),
              const SizedBox(width: 8),
              Text('returns.stock'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const Spacer(),
              Text('${widget.stockQuantity}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: widget.stockQuantity > 0 ? cs.primary : cs.error)),
            ]),
          ),
          const SizedBox(height: 14),

          // Unit price
          Text('sales.unit_price'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            onTap: () => selectAllText(_priceCtrl),
            decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true, isDense: true,
                prefixIcon: const Icon(LucideIcons.dollarSign, size: 18)),
            onChanged: (_) => _applyPrice(),
          ),
          const SizedBox(height: 14),

          // Discount with $/% toggle
          if (widget.showDiscount) ...[
            Row(children: [
              Text('sales.item_discount'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              const Spacer(),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(curr.currencySymbol, style: const TextStyle(fontSize: 11))),
                  const ButtonSegment(value: true, label: Text('%', style: TextStyle(fontSize: 11))),
                ],
                selected: {_discountIsPercent},
                onSelectionChanged: (v) => setState(() {
                  _discountIsPercent = v.first;
                  _discountCtrl.clear();
                  widget.onDiscountChanged(0, 0);
                }),
                style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ]),
            const SizedBox(height: 6),
            TextField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              onTap: () => selectAllText(_discountCtrl),
              decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true, isDense: true,
                  hintText: _discountIsPercent ? '0 %' : '0.00',
                  prefixIcon: Icon(_discountIsPercent ? LucideIcons.percent : LucideIcons.tag, size: 18)),
              onChanged: (_) => _applyDiscount(),
            ),
          ],

          // Tax info (read-only) — uses live values
          if (item.taxRateBps > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.tertiary.withValues(alpha: 0.3))),
              child: Row(children: [
                Icon(LucideIcons.percent, size: 16, color: cs.tertiary),
                const SizedBox(width: 8),
                Text('sales.tax'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const Spacer(),
                Text('${(item.taxRateBps / 100).toStringAsFixed(2)}%  =  ${curr.format(_liveTax)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: cs.tertiary)),
              ]),
            ),
          ],

          // Summary — uses live computed values
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('sales.subtotal'.tr(), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                Text(curr.format(_liveSubtotal), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
              ]),
              if (_liveDiscount > 0) ...[
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('sales.discount'.tr(), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  Text('-${curr.format(_liveDiscount)}', style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange)),
                ]),
              ],
              if (_liveTax > 0) ...[
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('sales.tax'.tr(), style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  Text('+${curr.format(_liveTax)}', style: theme.textTheme.bodySmall?.copyWith(color: cs.tertiary)),
                ]),
              ],
              const Divider(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('sales.total'.tr(), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                Text(curr.format(_liveTotal), style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: cs.error)),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
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
          ]),
        ],
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
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(widget.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'common.search'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    child: Text(widget.getInitial(item),
                        style: TextStyle(color: cs.onPrimaryContainer)),
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
  final int stockQuantity;
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
    required this.stockQuantity,
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
    final products = await (db.select(db.products)
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
    final defaultVariantRows = await db.customSelect(
      'SELECT pv.id AS variant_id, pv.product_id AS product_id, '
      '  pc.name AS color_name, sz.name AS size_name '
      'FROM product_variants pv '
      'JOIN products p ON p.id = pv.product_id '
      'LEFT JOIN product_colors pc ON pc.id = pv.color_id '
      'LEFT JOIN sizes sz ON sz.id = pv.size_id '
      'WHERE p.is_active = 1 AND p.has_variants = 0 AND pv.is_active = 1 '
      '  AND pv.id = (SELECT MIN(pv2.id) FROM product_variants pv2 '
      '               WHERE pv2.product_id = pv.product_id AND pv2.is_active = 1)',
    ).get();
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
      final parts = <String>[
        ?colorName,
        ?sizeName,
      ];
      final productId = r.read<int>('product_id');
      defaultVariantLabels[productId] =
          parts.isNotEmpty ? parts.join(' / ') : null;
      defaultVariantIds[productId] = r.read<int>('variant_id');
    }

    final rows = <_PickerRow>[];
    for (final product in products) {
      final taxBps = widget.isSale
          ? product.salesTaxRateBps
          : product.purchaseTaxRateBps;

      if (product.hasVariants) {
        final variantRows = await db.customSelect(
          'SELECT pv.*, pc.name AS color_name, sz.name AS size_name '
          'FROM product_variants pv '
          'LEFT JOIN product_colors pc ON pc.id = pv.color_id '
          'LEFT JOIN sizes sz ON sz.id = pv.size_id '
          'WHERE pv.product_id = ? AND pv.is_active = 1 '
          'ORDER BY pc.name ASC, sz.name ASC',
          variables: [drift.Variable.withInt(product.id)],
        ).get();

        for (final vr in variantRows) {
          final colorName = vr.readNullable<String>('color_name');
          final sizeName = vr.readNullable<String>('size_name');
          final parts = <String>[
            ?colorName,
            ?sizeName,
          ];
          rows.add(_PickerRow(
            productId: product.id,
            variantId: vr.read<int>('id'),
            productName: product.name,
            variantLabel: parts.isNotEmpty ? parts.join(' / ') : null,
            sku: vr.readNullable<String>('sku'),
            priceCents: vr.read<int>('price_cents'),
            costCents: vr.read<int>('cost_cents'),
            stockQuantity: vr.read<int>('stock_quantity'),
            taxRateBps: taxBps,
            hasVariants: true,
          ));
        }
      } else {
        rows.add(_PickerRow(
          productId: product.id,
          variantId: defaultVariantIds[product.id],
          productName: product.name,
          variantLabel: defaultVariantLabels[product.id],
          sku: product.sku,
          priceCents: product.priceCents.toBigInt().toInt(),
          costCents: product.costCents.toBigInt().toInt(),
          stockQuantity: product.stockQuantity,
          taxRateBps: taxBps,
          hasVariants: false,
        ));
      }
    }

    if (mounted) setState(() { _rows = rows; _isLoading = false; });
  }

  List<_PickerRow> get _filtered {
    if (_query.isEmpty) return _rows;
    final q = _query.toLowerCase();
    return _rows.where((r) =>
        r.displayName.toLowerCase().contains(q) ||
        (r.sku?.toLowerCase().contains(q) ?? false)).toList();
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
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('returns.select_product'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'products_search_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: (isVariant ? cs.secondaryContainer : cs.primaryContainer)
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isVariant ? LucideIcons.layers : LucideIcons.package,
                        size: 18,
                        color: isVariant ? cs.onSecondaryContainer : cs.onPrimaryContainer),
                    ),
                    title: Text(row.productName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (row.variantLabel != null)
                          Text(row.variantLabel!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.primary, fontWeight: FontWeight.w500)),
                        if (row.sku != null)
                          Text(row.sku!,
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(curr.format(row.priceCents),
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        Text('${'returns.stock'.tr()}: ${row.stockQuantity}',
                            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, AdjReturnLineItem(
                      productId: row.productId,
                      variantId: row.variantId,
                      productName: row.productName,
                      variantLabel: row.variantLabel,
                      variantSku: row.sku,
                      quantity: 1,
                      unitPriceCents: row.priceCents,
                      unitCostCents: row.costCents,
                      taxRateBps: row.taxRateBps,
                    )),
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
          .map((r) => DropdownMenuItem(
                value: r,
                child: Text(_label(r)),
              ))
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
  final List<AdjReturnLineItem> items;

  const _SaleFraudWarnings({required this.customerId, required this.items});

  @override
  Widget build(BuildContext context) {
    // Walk-in (no customer) or no items: nothing to verify.
    if (items.isEmpty || customerId == null) return const SizedBox.shrink();

    final dao = sl<AdjustmentReturnDao>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FutureBuilder<List<_ItemWarning>>(
        future: Future.wait(items.map((it) async {
          final qty = await dao.getCustomerProductPurchasedQty(
            customerId: customerId,
            productId: it.productId,
            variantId: it.variantId,
          );
          return _ItemWarning(item: it, historyQty: qty);
        })),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          final warnings = snap.data!
              .where((w) => w.historyQty == 0 || w.item.quantity > w.historyQty)
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
          Row(children: [
            Icon(LucideIcons.shieldAlert,
                size: 16, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            Text('returns.fraud_warnings_title'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.amber.shade800)),
          ]),
          const SizedBox(height: 8),
          ...warnings.map((w) {
            final neverBought = w.historyQty == 0;
            final text = neverBought
                ? '${w.item.displayName} — ${'returns.warning_never_bought'.tr()}'
                : '${w.item.displayName} — ${'returns.warning_qty_exceeds_history'.tr(namedArgs: {
                    'qty': '${w.item.quantity}',
                    'history': '${w.historyQty}',
                  })}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.dot,
                      size: 16, color: Colors.amber.shade700),
                  Expanded(
                    child: Text(text,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.amber.shade900, height: 1.35)),
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

class _ItemWarning {
  final AdjReturnLineItem item;
  final int historyQty;
  const _ItemWarning({required this.item, required this.historyQty});
}
