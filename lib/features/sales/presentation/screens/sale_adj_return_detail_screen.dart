import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/cashier_shift_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/commissions/commission_service.dart';
import '../../../../core/services/loyalty/loyalty_points_service.dart';
import '../../../../core/widgets/pin_verification_dialog.dart';
import '../../../auth/auth.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../../purchases/presentation/bloc/purchase_adj_return_form_bloc.dart'
    show parseAdjReturnNotes, adjReturnReasonLabel;
import '../services/sale_pdf_service.dart';

class SaleAdjReturnDetailScreen extends StatefulWidget {
  final int returnId;

  const SaleAdjReturnDetailScreen({super.key, required this.returnId});

  @override
  State<SaleAdjReturnDetailScreen> createState() =>
      _SaleAdjReturnDetailScreenState();
}

class _SaleAdjReturnDetailScreenState extends State<SaleAdjReturnDetailScreen> {
  SaleReturnAdjustment? _returnEntity;
  String? _customerName;
  String? _employeeName;
  CashierShiftView? _cashierShift;
  List<SaleAdjReturnItemWithDetails> _returnItems = [];
  bool _loading = true;
  StreamSubscription<List<SaleAdjReturnItemWithDetails>>? _itemsSub;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _itemsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final dao = sl<AdjustmentReturnDao>();
    final ret = await dao.getSaleAdjReturnById(widget.returnId);
    if (ret == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // Fetch customer name
    String? customerName;
    if (ret.customerId != null) {
      try {
        final db = sl<AppDatabase>();
        final customer = await (db.select(
          db.customers,
        )..where((c) => c.id.equals(ret.customerId!))).getSingleOrNull();
        customerName = customer?.name;
      } catch (_) {}
    }

    // Fetch employee name
    String? employeeName;
    if (ret.employeeId != null) {
      try {
        final db = sl<AppDatabase>();
        final employee = await (db.select(
          db.employees,
        )..where((e) => e.id.equals(ret.employeeId!))).getSingleOrNull();
        employeeName = employee?.name;
      } catch (_) {}
    }

    final cashierShift = await sl<CashierShiftService>()
        .getSaleAdjustmentReturnShift(widget.returnId);

    _itemsSub?.cancel();
    _itemsSub = dao.watchSaleAdjReturnItemsWithDetails(widget.returnId).listen((
      items,
    ) {
      if (mounted) {
        setState(() {
          _returnItems = items;
        });
      }
    });

    if (mounted) {
      setState(() {
        _returnEntity = ret;
        _customerName = customerName;
        _employeeName = employeeName;
        _cashierShift = cashierShift;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('returns.adjustment_detail'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_returnEntity == null) {
      return Scaffold(
        appBar: AppBar(title: Text('returns.adjustment_detail'.tr())),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.alertCircle, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('sales.not_found'.tr(), style: theme.textTheme.titleLarge),
            ],
          ),
        ),
      );
    }

    final ret = _returnEntity!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/sales/returns');
            }
          },
        ),
        title: Text('returns.adjustment_detail'.tr()),
        actions: [
          if (ret.status != 'voided')
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (v) => _handleAction(v, context),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: const Icon(LucideIcons.printer),
                    title: Text('sales.print_invoice'.tr()),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: const Icon(LucideIcons.share2),
                    title: Text('sales.share_invoice'.tr()),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'void',
                  child: Builder(
                    builder: (context) {
                      final authState = context.read<AuthBloc>().state;
                      final canVoid =
                          authState is AuthAuthenticated &&
                          sl<PermissionService>().hasPermission(
                            authState.user,
                            Permissions.editTransactions,
                          );
                      if (!canVoid) return const SizedBox.shrink();
                      return ListTile(
                        leading: Icon(
                          LucideIcons.ban,
                          color: colorScheme.error,
                        ),
                        title: Text(
                          'sales.void_return'.tr(),
                          style: TextStyle(color: colorScheme.error),
                        ),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildReturnInfoCard(context, ret, cs),
          const SizedBox(height: 12),
          _buildCustomerCard(context, ret),
          if (_employeeName != null) ...[
            const SizedBox(height: 12),
            _buildSalespersonCard(context),
          ],
          const SizedBox(height: 12),
          _buildRefundMethodCard(context, ret),
          const SizedBox(height: 12),
          _buildReturnItemsCard(context, _returnItems, cs),
          const SizedBox(height: 12),
          _buildTotalCard(context, ret, cs),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _handleAction(String action, BuildContext context) {
    switch (action) {
      case 'print':
        _printPdf(context);
        break;
      case 'share':
        _sharePdf(context);
        break;
      case 'void':
        _voidReturn(context);
        break;
    }
  }

  Future<void> _printPdf(BuildContext context) async {
    final ret = _returnEntity;
    if (ret == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SalePdfService.printSaleAdjReturn(
        context: context,
        returnEntity: ret,
        returnItems: _returnItems,
        customerName: _customerName,
        employeeName: _employeeName,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _sharePdf(BuildContext context) async {
    final ret = _returnEntity;
    if (ret == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SalePdfService.shareSaleAdjReturn(
        context: context,
        returnEntity: ret,
        returnItems: _returnItems,
        customerName: _customerName,
        employeeName: _employeeName,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _voidReturn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final settings = context.read<AppSettingsBloc>().state.settings;
    // Capture policy BEFORE any async gap to avoid using context after await.
    final allowNegativeStock = settings.allowNegativeStock;
    if (settings.requirePinForVoidRefund) {
      final pinOk = await showPinVerificationDialog(context);
      if (!pinOk || !context.mounted) return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('sales.void_confirm_title'.tr()),
        content: Text('sales.void_return_confirm_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('sales.void_return'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final dao = sl<AdjustmentReturnDao>();
      await dao.voidSaleAdjReturn(
        widget.returnId,
        journalEntryService: sl<JournalEntryService>(),
        allowNegativeStock: allowNegativeStock,
        commissionService: sl<CommissionService>(),
        loyaltyPointsService: sl<LoyaltyPointsService>(),
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('sales.void_success'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            behavior: SnackBarBehavior.floating,
            backgroundColor: errorColor,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // RETURN INFO CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildReturnInfoCard(
    BuildContext context,
    SaleReturnAdjustment ret,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final statusColor = ret.status == 'voided'
        ? colorScheme.error
        : Colors.green;
    final statusLabel = ret.status == 'voided'
        ? 'sales.status_voided'.tr()
        : 'sales.status_posted'.tr();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.tertiary.withValues(alpha: 0.25)),
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
                      colors: [
                        colorScheme.tertiary,
                        colorScheme.tertiary.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.rotateCcw,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'sales.return_number'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'returns.adjustment'.tr(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        ret.returnNumber,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Divider(
              height: 24,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            _infoRow(
              theme,
              'sales.date'.tr(),
              DateFormat.yMMMd().format(ret.returnDate),
            ),
            if (_cashierShift != null) ...[
              const SizedBox(height: 8),
              _infoRow(
                theme,
                'cashier_shifts.cashier'.tr(),
                _cashierShift!.cashierName,
              ),
              const SizedBox(height: 8),
              _infoRow(
                theme,
                'cashier_shifts.shift_number'.tr(),
                _cashierShift!.shift.shiftNumber,
              ),
            ],
            const SizedBox(height: 8),
            if (ret.returnMode != null) ...[
              _infoRow(
                theme,
                'returns.mode'.tr(),
                'returns.mode_${ret.returnMode}'.tr(),
              ),
              const SizedBox(height: 8),
            ],
            // Parse reason tag out of notes (stored as `[REASON:code] notes`).
            if (ret.notes != null && ret.notes!.isNotEmpty) ...[
              Builder(
                builder: (_) {
                  final parsed = parseAdjReturnNotes(ret.notes);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (parsed.reasonCode != null) ...[
                        _infoRow(
                          theme,
                          'returns.reason_label'.tr(),
                          adjReturnReasonLabel(parsed.reasonCode),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (parsed.userNotes != null) ...[
                        _infoRow(theme, 'common.notes'.tr(), parsed.userNotes!),
                        const SizedBox(height: 8),
                      ],
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // CUSTOMER CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildCustomerCard(BuildContext context, SaleReturnAdjustment ret) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWalkIn = ret.customerId == null;
    final displayName = isWalkIn
        ? 'returns.walk_in_customer'.tr()
        : (_customerName ?? 'ID: ${ret.customerId}');
    final initial = isWalkIn
        ? '?'
        : (displayName.isNotEmpty ? displayName[0].toUpperCase() : '?');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
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
                    displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isWalkIn ? colorScheme.onSurfaceVariant : null,
                      fontStyle: isWalkIn ? FontStyle.italic : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // SALESPERSON CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildSalespersonCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initial = _employeeName!.isNotEmpty
        ? _employeeName![0].toUpperCase()
        : '?';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.tertiary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'sales.salesperson'.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    _employeeName!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // REFUND METHOD CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildRefundMethodCard(
    BuildContext context,
    SaleReturnAdjustment ret,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    IconData methodIcon;
    switch (ret.refundMethod) {
      case 'cash':
        methodIcon = LucideIcons.banknote;
        break;
      case 'cheque':
        methodIcon = LucideIcons.fileCheck;
        break;
      default:
        methodIcon = LucideIcons.wallet;
    }

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
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(LucideIcons.creditCard, size: 16, color: cs.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'sales.refund_method'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(methodIcon, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    'sales.refund_method_${ret.refundMethod}'.tr(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // RETURN ITEMS CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildReturnItemsCard(
    BuildContext context,
    List<SaleAdjReturnItemWithDetails> items,
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
                        colorScheme.tertiary,
                        colorScheme.tertiary.withValues(alpha: 0.7),
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
                  'sales.return_items'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${items.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'sales.no_items_to_return'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (context2, index2) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final d = items[index];
                  final productName = d.product.name;
                  final variantSku = d.variant?.sku;

                  // Build variant label parts (color · size · sku)
                  final variantParts = <String>[];
                  if (d.colorName != null && d.colorName!.isNotEmpty) {
                    variantParts.add(d.colorName!);
                  }
                  if (variantSku != null && variantSku.isNotEmpty) {
                    variantParts.add(variantSku);
                  }
                  final variantLine = variantParts.isNotEmpty
                      ? variantParts.join(' · ')
                      : null;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        if (d.colorHex != null && d.colorHex!.isNotEmpty)
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(
                                  'FF${d.colorHex!.replaceAll('#', '')}',
                                  radix: 16,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  const Shadow(
                                    blurRadius: 2,
                                    color: Colors.black54,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.tertiary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                productName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (variantLine != null)
                                Text(
                                  variantLine,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontSize: 11,
                                  ),
                                ),
                              Text(
                                '${'sales.return_qty'.tr()}: ${localizedQuantity(d.item.quantity, d.item.measurementType)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              if (d.item.reason != null &&
                                  d.item.reason!.isNotEmpty)
                                Text(
                                  d.item.reason!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 10,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          cs.format(d.item.totalCents.toBigInt().toInt()),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

  // ═══════════════════════════════════════════════════════
  // TOTAL CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildTotalCard(
    BuildContext context,
    SaleReturnAdjustment ret,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final subtotal = ret.subtotalCents.toBigInt().toInt();
    final discount = ret.discountCents.toBigInt().toInt();
    final tax = ret.taxCents.toBigInt().toInt();
    final total = ret.totalCents.toBigInt().toInt();
    final totalItems = _returnItems.length;
    final totalPieces = _returnItems.fold<int>(
      0,
      (sum, d) => sum + d.item.quantity,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.2)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            _totalRow(theme, 'sales.total_items_count'.tr(), '$totalItems'),
            _totalRow(theme, 'sales.total_pieces_count'.tr(), '$totalPieces'),
            Divider(
              height: 16,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            if (subtotal > 0)
              _totalRow(theme, 'sales.subtotal'.tr(), cs.format(subtotal)),
            if (discount > 0)
              _totalRow(
                theme,
                'sales.discount'.tr(),
                '-${cs.format(discount)}',
                valueColor: Colors.orange,
              ),
            if (tax > 0)
              _totalRow(
                theme,
                'sales.tax'.tr(),
                '+${cs.format(tax)}',
                valueColor: colorScheme.tertiary,
              ),
            if (subtotal > 0 || discount > 0 || tax > 0)
              Divider(
                height: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'common.total'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  cs.format(total),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
