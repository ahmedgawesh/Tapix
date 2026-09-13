import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/widgets/pin_verification_dialog.dart';
import '../../../auth/auth.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../services/purchase_pdf_service.dart';

class PurchaseReturnDetailScreen extends StatefulWidget {
  final int returnId;
  final bool adjustment;

  const PurchaseReturnDetailScreen({
    super.key,
    required this.returnId,
    this.adjustment = false,
  });

  @override
  State<PurchaseReturnDetailScreen> createState() =>
      _PurchaseReturnDetailScreenState();
}

class _PurchaseReturnDetailScreenState
    extends State<PurchaseReturnDetailScreen> {
  PurchaseReturnEntity? _returnEntity;
  PurchaseEntity? _purchase;
  LanPurchaseReturnDetails? _remoteDetails;
  List<PurchaseReturnItemEntity> _returnItems = [];
  bool _loading = true;
  StreamSubscription<List<PurchaseReturnItemEntity>>? _itemsSub;

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
    final lan = sl<LanNetworkService>();
    if (lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession) {
      await _loadRemoteData(lan);
      return;
    }
    final repo = sl<PurchaseRepository>();
    final ret = await repo.getPurchaseReturnById(widget.returnId);
    if (ret == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final purchase = await repo.getPurchaseById(ret.purchaseId);

    // Subscribe to realtime updates for return items
    _itemsSub?.cancel();
    _itemsSub = repo
        .watchPurchaseReturnItemsWithDetails(widget.returnId)
        .listen((items) {
          if (mounted) {
            setState(() {
              _returnItems = items;
            });
          }
        });

    if (mounted) {
      setState(() {
        _returnEntity = ret;
        _purchase = purchase;
        _loading = false;
      });
    }
  }

  Future<void> _loadRemoteData(LanNetworkService lan) async {
    try {
      final details = await lan.fetchRemotePurchaseReturnDetails(
        returnId: widget.returnId,
        adjustment: widget.adjustment,
      );
      final value = details.summary;
      final now = DateTime.now();
      final ret = PurchaseReturnEntity(
        id: value.id,
        purchaseId: value.purchaseId,
        returnNumber: value.returnNumber,
        supplierName: value.supplierName,
        supplierPhone: value.supplierPhone,
        supplierId: value.supplierId,
        subtotalCents: Decimal.fromInt(value.subtotalCents),
        discountCents: Decimal.fromInt(value.discountCents),
        taxCents: Decimal.fromInt(value.taxCents),
        totalCents: Decimal.fromInt(value.totalCents),
        currencyId: value.currencyId,
        status: value.status,
        dispositionType: value.dispositionType,
        refundMethod: value.refundMethod,
        reason: value.reason,
        returnDate: value.returnDate,
        createdAt: value.createdAt,
        isAdjustment: value.isAdjustment,
        unifiedId: value.unifiedId,
      );
      final original = details.originalPurchase;
      final purchase = value.isAdjustment
          ? null
          : PurchaseEntity(
              id: value.purchaseId,
              purchaseNumber: value.purchaseNumber ?? '',
              supplierId: value.supplierId ?? 0,
              supplierName: value.supplierName,
              supplierPhone: value.supplierPhone,
              subtotalCents: Decimal.fromInt(
                original?.totalCents ?? value.totalCents,
              ),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(
                original?.totalCents ?? value.totalCents,
              ),
              currencyId: value.currencyId,
              status: 'posted',
              paymentMethod: original?.paymentMethod,
              purchaseDate: original?.purchaseDate ?? value.returnDate,
              taxInclusiveAtPost: original?.taxInclusiveAtPost ?? false,
              createdAt: original?.purchaseDate ?? value.createdAt,
              updatedAt: now,
            );
      final items = details.lines
          .map(
            (line) => PurchaseReturnItemEntity(
              id: line.id,
              returnId: line.returnId,
              purchaseItemId: line.purchaseItemId ?? 0,
              quantity: line.quantity,
              quantityScale: line.quantityScale,
              measurementType: line.measurementType,
              subtotalCents: Decimal.fromInt(line.subtotalCents),
              discountCents: Decimal.fromInt(line.discountCents),
              taxCents: Decimal.fromInt(line.taxCents),
              refundCents: Decimal.fromInt(line.totalCents),
              reason: line.reason,
              productName: line.productName,
              variantSku: line.variantSku,
              variantBarcode: line.variantBarcode,
              colorName: line.colorName,
              colorHex: line.colorHex,
              sizeName: line.sizeName,
              createdAt: line.createdAt,
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _returnEntity = ret;
        _purchase = purchase;
        _remoteDetails = details;
        _returnItems = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('purchases.return_detail'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_returnEntity == null) {
      return Scaffold(
        appBar: AppBar(title: Text('purchases.return_detail'.tr())),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.alertCircle, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'purchases.not_found'.tr(),
                style: theme.textTheme.titleLarge,
              ),
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
              context.go('/purchases/returns');
            }
          },
        ),
        title: Text('purchases.return_detail'.tr()),
        actions: [
          if (!ret.isVoided) ...[
            IconButton(
              icon: const Icon(LucideIcons.printer),
              tooltip: 'purchases.print_invoice'.tr(),
              onPressed: () => _printOrShare(share: false),
            ),
            IconButton(
              icon: const Icon(LucideIcons.share2),
              tooltip: 'purchases.share_pdf'.tr(),
              onPressed: () => _printOrShare(share: true),
            ),
            Builder(
              builder: (context) {
                final authState = context.read<AuthBloc>().state;
                final lan = sl<LanNetworkService>();
                final remote =
                    lan.snapshot.mode == LanMode.client &&
                    lan.hasRemoteUserSession;
                final permissions = lan.remoteUser?.permissions;
                final canVoid = remote
                    ? (permissions?.contains(Permissions.managePurchases) ==
                              true &&
                          permissions?.contains(Permissions.voidTransactions) ==
                              true)
                    : authState is AuthAuthenticated &&
                          sl<PermissionService>().hasPermission(
                            authState.user,
                            Permissions.editTransactions,
                          );
                if (!canVoid) return const SizedBox.shrink();
                return IconButton(
                  icon: Icon(LucideIcons.ban, color: colorScheme.error),
                  tooltip: 'purchases.void_purchase'.tr(),
                  onPressed: () => _voidReturn(context),
                );
              },
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildReturnInfoCard(context, ret, cs),
          const SizedBox(height: 12),
          if (_purchase != null)
            _buildOriginalPurchaseCard(context, _purchase!, cs),
          if (_purchase != null) const SizedBox(height: 12),
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

  Future<void> _voidReturn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    // Check if PIN is required for void/refund
    final settings = context.read<AppSettingsBloc>().state.settings;
    if (settings.requirePinForVoidRefund) {
      final pinOk = await showPinVerificationDialog(context);
      if (!pinOk || !context.mounted) return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('purchases.void_confirm_title'.tr()),
        content: Text('purchases.void_return_confirm_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: errorColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('purchases.void_purchase'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final lan = sl<LanNetworkService>();
      if (lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession) {
        await lan.voidRemotePurchaseReturn(
          returnId: widget.returnId,
          adjustment: widget.adjustment,
        );
      } else {
        final repo = sl<PurchaseRepository>();
        await repo.voidPurchaseReturn(widget.returnId);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('purchases.void_success'.tr()),
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

  Future<void> _printOrShare({required bool share}) async {
    if (_returnEntity == null) return;
    try {
      final lan = sl<LanNetworkService>();
      final remoteDetails = _remoteDetails;
      final isRemote =
          lan.snapshot.mode == LanMode.client && remoteDetails != null;
      if (_returnEntity!.isAdjustment && isRemote) {
        if (share) {
          await PurchasePdfService.shareRemotePurchaseAdjReturn(
            context: context,
            details: remoteDetails,
          );
        } else {
          await PurchasePdfService.printRemotePurchaseAdjReturn(
            context: context,
            details: remoteDetails,
          );
        }
        return;
      }
      if (_purchase == null) return;
      if (share) {
        await PurchasePdfService.sharePurchaseReturn(
          context: context,
          originalPurchase: _purchase!,
          returnEntity: _returnEntity!,
          returnItems: _returnItems,
          loadLocalSupplierBalance: !isRemote,
        );
      } else {
        await PurchasePdfService.printPurchaseReturn(
          context: context,
          originalPurchase: _purchase!,
          returnEntity: _returnEntity!,
          returnItems: _returnItems,
          loadLocalSupplierBalance: !isRemote,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('purchases.print_error'.tr()),
            behavior: SnackBarBehavior.floating,
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
    PurchaseReturnEntity ret,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final statusColor = ret.isVoided ? colorScheme.error : Colors.green;
    final statusLabel = ret.isVoided
        ? 'purchases.status_voided'.tr()
        : 'purchases.status_posted'.tr();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.25)),
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
                        colorScheme.error,
                        colorScheme.error.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.undo2,
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
                        'purchases.return_number'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
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
              'purchases.return_date'.tr(),
              DateFormat('dd/MM/yyyy').format(ret.returnDate),
            ),
            const SizedBox(height: 8),
            if (ret.reason != null && ret.reason!.isNotEmpty) ...[
              _infoRow(theme, 'purchases.return_reason'.tr(), ret.reason!),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ORIGINAL PURCHASE CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildOriginalPurchaseCard(
    BuildContext context,
    PurchaseEntity purchase,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lan = sl<LanNetworkService>();
    final isRemote =
        lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession;
    final supplierInitial =
        purchase.supplierName != null && purchase.supplierName!.isNotEmpty
        ? purchase.supplierName![0].toUpperCase()
        : '?';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isRemote
            ? null
            : () => context.push('/purchases/${purchase.id}'),
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
                          'purchases.return_from_purchase'.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          purchase.purchaseNumber,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              Divider(
                height: 24,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              if (purchase.supplierName != null) ...[
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        supplierInitial,
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
                            'purchases.supplier'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            purchase.supplierName!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              _infoRow(
                theme,
                'purchases.total'.tr(),
                cs.format(purchase.totalCents.toBigInt().toInt()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // REFUND METHOD CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildRefundMethodCard(
    BuildContext context,
    PurchaseReturnEntity ret,
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

    IconData dispositionIcon;
    switch (ret.dispositionType) {
      case 'write_off':
        dispositionIcon = LucideIcons.trash2;
        break;
      default:
        dispositionIcon = LucideIcons.package;
    }

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
                  'purchases.refund_method'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(methodIcon, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'purchases.refund_method_${ret.refundMethod}'.tr(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'purchases.refund_method_${ret.refundMethod}_desc'
                              .tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.checkCircle2, size: 18, color: cs.primary),
                ],
              ),
            ),
            Divider(
              height: 20,
              color: cs.outlineVariant.withValues(alpha: 0.4),
            ),
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
                Text(
                  'purchases.disposition_type'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(dispositionIcon, size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        'purchases.disposition_${ret.dispositionType}'.tr(),
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
    List<PurchaseReturnItemEntity> items,
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
                  'purchases.return_items'.tr(),
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
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${items.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onErrorContainer,
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
                    'purchases.no_items_to_return'.tr(),
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
                separatorBuilder: (context2, idx2) => Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final productName =
                      item.productName ?? 'Item #${item.purchaseItemId}';

                  // Build variant details line (color · size · SKU)
                  final variantParts = <String>[];
                  if (item.colorName != null && item.colorName!.isNotEmpty) {
                    variantParts.add(item.colorName!);
                  }
                  if (item.sizeName != null && item.sizeName!.isNotEmpty) {
                    variantParts.add(item.sizeName!);
                  }
                  if (item.variantSku != null && item.variantSku!.isNotEmpty) {
                    variantParts.add(item.variantSku!);
                  }
                  final variantLine = variantParts.isNotEmpty
                      ? variantParts.join(' · ')
                      : null;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        // Color swatch or index number
                        if (item.colorHex != null && item.colorHex!.isNotEmpty)
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(
                                int.parse(
                                  'FF${item.colorHex!.replaceAll('#', '')}',
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
                              color: colorScheme.errorContainer.withValues(
                                alpha: 0.3,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.error,
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
                                '${'purchases.qty'.tr()}: ${localizedQuantity(item.quantity, item.measurementType)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              if (item.reason != null &&
                                  item.reason!.isNotEmpty)
                                Text(
                                  item.reason!,
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
                          cs.format(item.refundCents.toBigInt().toInt()),
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
    PurchaseReturnEntity ret,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final subtotal = ret.subtotalCents.toBigInt().toInt();
    final discount = ret.discountCents.toBigInt().toInt();
    final tax = ret.taxCents.toBigInt().toInt();
    final total = ret.totalCents.toBigInt().toInt();
    final totalItems = _returnItems.length;
    final quantitySummary = localizedQuantitySummary(
      _returnItems,
      quantityOf: (item) => item.quantity,
      measurementTypeOf: (item) => item.measurementType,
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
            _totalRow(theme, 'purchases.total_items_count'.tr(), '$totalItems'),
            _totalRow(
              theme,
              'measurement.total_quantity'.tr(),
              quantitySummary,
            ),
            if (subtotal != 0 || discount != 0 || tax != 0) ...[
              Divider(
                height: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              _totalRow(theme, 'purchases.subtotal'.tr(), cs.format(subtotal)),
              if (discount != 0)
                _totalRow(
                  theme,
                  'purchases.discount'.tr(),
                  '- ${cs.format(discount)}',
                  valueColor: Colors.green,
                ),
              if (tax != 0)
                _totalRow(theme, 'purchases.tax'.tr(), cs.format(tax)),
              Divider(
                height: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'purchases.return_total'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  cs.format(total),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.error,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
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
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
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
              child: Icon(
                label.contains('Date') || label.contains('تاريخ')
                    ? LucideIcons.calendar
                    : LucideIcons.info,
                size: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
