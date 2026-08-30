import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/currency_service.dart'
    as currency_model
    show Currency, SymbolPosition;
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/services/cashier_shift_service.dart';
import '../../../../core/services/void_impact_analyzer.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/pin_verification_dialog.dart';
import '../../../../core/widgets/void_impact_dialog.dart';
import '../../../auth/auth.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';
import '../services/sale_pdf_service.dart';
import '../../../inventory/presentation/widgets/batch_flow_widget.dart';

class SaleDetailScreen extends StatefulWidget {
  final int saleId;

  const SaleDetailScreen({super.key, required this.saleId});

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  SaleEntity? _sale;
  List<SaleItemEntity> _items = [];
  List<SaleReturnEntity> _returns = [];
  CashierShiftView? _cashierShift;
  LanSaleDetails? _remoteDetails;
  Object? _loadError;
  bool _loading = true;
  StreamSubscription<List<SaleReturnEntity>>? _returnsSub;

  @override
  void initState() {
    super.initState();
    _loadSale();
  }

  @override
  void dispose() {
    _returnsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSale() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    if (sl<LanNetworkService>().snapshot.mode == LanMode.client) {
      await _loadRemoteSale();
      return;
    }
    final repo = sl<SaleRepository>();
    final sale = await repo.getSaleById(widget.saleId);
    final items = await repo.getSaleItems(widget.saleId);
    final cashierShift = await sl<CashierShiftService>().getSaleShift(
      widget.saleId,
    );

    _returnsSub?.cancel();
    _returnsSub = repo.watchSaleReturnsBySale(widget.saleId).listen((returns) {
      if (mounted) setState(() => _returns = returns);
    });

    if (mounted) {
      setState(() {
        _sale = sale;
        _items = items;
        _cashierShift = cashierShift;
        _loading = false;
      });
    }
  }

  Future<void> _loadRemoteSale() async {
    try {
      final details = await sl<LanNetworkService>().fetchRemoteSaleDetails(
        widget.saleId,
      );
      await _applyRemoteCurrency(details);
      final source = details.sale;
      final sale = SaleEntity(
        id: source.id,
        invoiceNumber: source.invoiceNumber,
        customerId: source.customerId,
        customerName: source.customerName,
        customerPhone: source.customerPhone,
        employeeId: source.employeeId,
        employeeName: source.employeeName,
        subtotalCents: Decimal.fromInt(source.subtotalCents),
        taxCents: Decimal.fromInt(source.taxCents),
        discountCents: Decimal.fromInt(source.discountCents),
        totalCents: Decimal.fromInt(source.totalCents),
        paidAmountCents: Decimal.fromInt(source.paidAmountCents),
        currencyId: source.currencyId,
        paymentMethod: source.paymentMethod,
        status: source.status,
        notes: source.notes,
        saleDate: source.saleDate,
        dueDate: source.dueDate,
        taxInclusiveAtPost: source.taxInclusiveAtPost,
        createdAt: source.createdAt,
        updatedAt: source.updatedAt,
      );
      final items = details.lines
          .map(
            (line) => SaleItemEntity(
              id: line.id,
              saleId: line.saleId,
              productId: line.productId,
              productName: line.productName,
              productSku: line.productSku,
              variantId: line.variantId,
              variantSku: line.variantSku,
              colorName: line.colorName,
              colorHex: line.colorHex,
              sizeName: line.sizeName,
              quantity: line.quantity,
              quantityScale: line.quantityScale,
              measurementType: line.measurementType,
              unitPriceCents: Decimal.fromInt(line.unitPriceCents),
              subtotalCents: Decimal.fromInt(line.subtotalCents),
              discountCents: Decimal.fromInt(line.discountCents),
              taxCents: Decimal.fromInt(line.taxCents),
              totalCents: Decimal.fromInt(line.totalCents),
              employeeId: line.employeeId,
              employeeName: line.employeeName,
              createdAt: line.createdAt,
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _remoteDetails = details;
        _sale = sale;
        _items = items;
        _returns = const [];
        _cashierShift = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _sale = null;
        _items = const [];
        _loading = false;
      });
    }
  }

  Future<void> _applyRemoteCurrency(LanSaleDetails details) async {
    final service = sl<CurrencyService>();
    final current = service.getCurrency();
    if (current.code != details.currencyCode ||
        current.symbol != details.currencySymbol ||
        current.decimalDigits != details.currencyDecimalDigits ||
        (current.symbolPosition == SymbolPosition.after) !=
            details.currencySymbolAfter) {
      await service.addCustomCurrency(
        currency_model.Currency(
          code: details.currencyCode,
          symbol: details.currencySymbol,
          name: details.currencyCode,
          decimalDigits: details.currencyDecimalDigits,
          symbolPosition: details.currencySymbolAfter
              ? currency_model.SymbolPosition.after
              : currency_model.SymbolPosition.before,
          isCustom: true,
        ),
      );
    }
    await service.setCurrency(details.currencyCode);
  }

  bool get _isRemoteClient =>
      sl<LanNetworkService>().snapshot.mode == LanMode.client;

  bool get _canReturnRemote =>
      !_isRemoteClient ||
      sl<LanNetworkService>().remoteUser?.permissions.any(
            const ['handle_returns', 'manage_sales'].contains,
          ) ==
          true;

  bool get _canVoidRemote =>
      !_isRemoteClient ||
      sl<LanNetworkService>().remoteUser?.permissions.contains(
            'void_transactions',
          ) ==
          true;

  String? get _cashierName =>
      _cashierShift?.cashierName ?? _remoteDetails?.cashierName;

  String? get _cashierShiftNumber =>
      _cashierShift?.shift.shiftNumber ?? _remoteDetails?.cashierShiftNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('sales.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_sale == null) {
      return Scaffold(
        appBar: AppBar(title: Text('sales.title'.tr())),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.alertCircle, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _loadError == null
                    ? 'sales.not_found'.tr()
                    : _loadError.toString(),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadSale,
                icon: const Icon(LucideIcons.refreshCw),
                label: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    final sale = _sale!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/sales');
            }
          },
        ),
        title: Text(sale.invoiceNumber),
        actions: _buildActions(sale, colorScheme),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSale,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            if (isWide) {
              return _buildWideLayout(context, sale, cs);
            }
            return _buildNarrowLayout(context, sale, cs);
          },
        ),
      ),
    );
  }

  List<Widget> _buildActions(SaleEntity sale, ColorScheme colorScheme) {
    final actions = <Widget>[];

    // Check if user has edit permission
    final authState = context.read<AuthBloc>().state;
    final canEdit =
        authState is AuthAuthenticated &&
        sl<PermissionService>().hasPermission(
          authState.user,
          Permissions.editTransactions,
        );

    if (sale.isCompleted) {
      if (_canReturnRemote) {
        actions.add(
          FilledButton.tonalIcon(
            onPressed: () {
              // In-invoice button always creates a LINKED return for this invoice.
              // Adjustment (unlinked) returns are created from the Returns list.
              context.push('/sales/returns/new?saleId=${sale.id}');
            },
            icon: const Icon(LucideIcons.undo2, size: 16),
            label: Text('sales.create_return'.tr()),
          ),
        );
        actions.add(const SizedBox(width: 4));
      }
      actions.add(
        PopupMenuButton<String>(
          icon: const Icon(LucideIcons.moreVertical),
          onSelected: (v) => _handleAction(v, context),
          itemBuilder: (_) => [
            if (canEdit && !_isRemoteClient)
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: const Icon(LucideIcons.pencil),
                  title: Text('sales.edit_sale'.tr()),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
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
            if (_canVoidRemote) ...[
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'void',
                child: ListTile(
                  leading: Icon(LucideIcons.ban, color: colorScheme.error),
                  title: Text(
                    'sales.void_sale'.tr(),
                    style: TextStyle(color: colorScheme.error),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return actions;
  }

  Future<void> _handleAction(String action, BuildContext context) async {
    final repo = sl<SaleRepository>();
    switch (action) {
      case 'print':
        if (_sale != null) {
          try {
            await SalePdfService.printSaleInvoice(
              context: context,
              sale: _sale!,
              items: _items,
              cashierName: _cashierName,
              cashierShiftNumber: _cashierShiftNumber,
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
        }
        break;
      case 'share':
        if (_sale != null) {
          try {
            await SalePdfService.shareSaleInvoice(
              context: context,
              sale: _sale!,
              items: _items,
              cashierName: _cashierName,
              cashierShiftNumber: _cashierShiftNumber,
            );
          } catch (_) {}
        }
        break;
      case 'edit':
        // Navigate to sale form with the sale ID for editing posted sale
        context.push('/sales/${widget.saleId}/edit?posted=true');
        break;
      case 'void':
        if (_isRemoteClient) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: Icon(
                LucideIcons.alertTriangle,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text('sales.void_confirm_title'.tr()),
              content: Text('sales.void_confirm_message'.tr()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('common.cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('sales.void_sale'.tr()),
                ),
              ],
            ),
          );
          if (confirmed != true || !context.mounted) return;
          final messenger = ScaffoldMessenger.of(context);
          try {
            await sl<LanNetworkService>().voidRemoteSale(widget.saleId);
            await _loadSale();
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text('sales.void_success'.tr())),
            );
          } on LanBusinessException catch (error) {
            if (!context.mounted) return;
            final message = error.code == 'remote_pin_required'
                ? 'settings.network.remote_void_pin_required'.tr()
                : error.message;
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                icon: Icon(
                  LucideIcons.alertTriangle,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text('sales.void_failed_title'.tr()),
                content: Text(message),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('common.ok'.tr()),
                  ),
                ],
              ),
            );
          }
          return;
        }
        // Check if PIN is required for void/refund
        final settings = context.read<AppSettingsBloc>().state.settings;
        if (settings.requirePinForVoidRefund) {
          final pinOk = await showPinVerificationDialog(context);
          if (!pinOk || !context.mounted) return;
        }
        if (!context.mounted) return;
        // 2026-05-13 — pre-flight integrity check via VoidImpactAnalyzer.
        // Surfaces entangled adjustment returns, projected negative stock,
        // and estimated GL impact (AR/Inventory) BEFORE the void runs.
        final report = await VoidImpactAnalyzer(
          sl<AppDatabase>(),
        ).analyzeSaleVoid(widget.saleId);
        if (!context.mounted) return;
        final confirmed = await VoidImpactDialog.show(context, report);
        if (!confirmed) break;
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        try {
          await repo.voidSale(widget.saleId);
          await _loadSale();
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(
              content: Text('sales.void_success'.tr()),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } on VoidBlockedByImpactException catch (e) {
          // Defensive: blocker added between analyze and confirm.
          if (!context.mounted) return;
          await VoidImpactDialog.show(context, e.report);
        } catch (e) {
          if (!context.mounted) return;
          final errorMsg = e.toString().replaceFirst('Exception: ', '');
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: Icon(
                LucideIcons.alertTriangle,
                color: Theme.of(ctx).colorScheme.error,
                size: 32,
              ),
              title: Text('sales.void_failed_title'.tr()),
              content: Text(errorMsg),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('common.ok'.tr()),
                ),
              ],
            ),
          );
        }
        break;
    }
  }

  Widget _buildWideLayout(
    BuildContext context,
    SaleEntity sale,
    CurrencyService cs,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 380,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatusTimeline(context, sale),
              const SizedBox(height: 16),
              _buildInfoCard(context, sale, cs),
              const SizedBox(height: 16),
              _buildTotalsCard(context, sale, cs),
              if (sale.notes != null && sale.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildNotesCard(context, sale),
              ],
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildItemsCard(context, cs),
              if (_returns.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildReturnsCard(context, cs),
              ],
              const SizedBox(height: 16),
              if (!_isRemoteClient) BatchFlowWidget(saleId: widget.saleId),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(
    BuildContext context,
    SaleEntity sale,
    CurrencyService cs,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusTimeline(context, sale),
        const SizedBox(height: 16),
        _buildInfoCard(context, sale, cs),
        const SizedBox(height: 16),
        _buildItemsCard(context, cs),
        if (_returns.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildReturnsCard(context, cs),
        ],
        const SizedBox(height: 16),
        if (!_isRemoteClient) ...[
          BatchFlowWidget(saleId: widget.saleId),
          const SizedBox(height: 16),
        ],
        _buildTotalsCard(context, sale, cs),
        if (sale.notes != null && sale.notes!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildNotesCard(context, sale),
        ],
      ],
    );
  }

  Widget _buildStatusTimeline(BuildContext context, SaleEntity sale) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final steps = <_TimelineStep>[
      _TimelineStep(
        label: 'sales.status_completed'.tr(),
        icon: LucideIcons.checkCircle,
        isActive: sale.isCompleted || sale.isVoided,
        isCompleted: sale.isCompleted,
      ),
    ];

    if (sale.isVoided) {
      steps.add(
        _TimelineStep(
          label: 'sales.status_voided'.tr(),
          icon: LucideIcons.ban,
          isActive: true,
          isCompleted: false,
          isError: true,
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              _buildTimelineNode(theme, steps[i]),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineNode(ThemeData theme, _TimelineStep step) {
    final cs = theme.colorScheme;
    Color color;
    if (step.isError) {
      color = cs.error;
    } else if (step.isCompleted) {
      color = Colors.green;
    } else if (step.isActive) {
      color = cs.primary;
    } else {
      color = cs.outlineVariant;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: (step.isCompleted || step.isActive)
                ? LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: (step.isCompleted || step.isActive)
                ? null
                : cs.surfaceContainerHighest,
            shape: BoxShape.circle,
            boxShadow: (step.isCompleted || step.isActive)
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            step.icon,
            size: 18,
            color: (step.isCompleted || step.isActive)
                ? Colors.white
                : cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          step.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: (step.isCompleted || step.isActive)
                ? color
                : cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    SaleEntity sale,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customerInitial =
        sale.customerName != null && sale.customerName!.isNotEmpty
        ? sale.customerName![0].toUpperCase()
        : '?';

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
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    customerInitial,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'sales.customer'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        sale.customerName ?? 'sales.walk_in'.tr(),
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
            _detailRow(
              theme,
              LucideIcons.hash,
              'sales.invoice_number'.tr(),
              sale.invoiceNumber,
            ),
            const SizedBox(height: 10),
            _detailRow(
              theme,
              LucideIcons.calendar,
              'sales.date'.tr(),
              DateFormat.yMMMd().format(sale.saleDate),
            ),
            if (sale.dueDate != null) ...[
              const SizedBox(height: 10),
              _detailRow(
                theme,
                LucideIcons.calendarClock,
                'sales.due_date'.tr(),
                DateFormat.yMMMd().format(sale.dueDate!),
                valueColor: sale.isOverdue ? colorScheme.error : null,
              ),
            ],
            const SizedBox(height: 10),
            _detailRow(
              theme,
              LucideIcons.creditCard,
              'sales.payment_method'.tr(),
              sale.paymentMethod,
            ),
            if (sale.employeeName != null && sale.employeeName!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _detailRow(
                theme,
                LucideIcons.userCheck,
                'sales.salesperson'.tr(),
                sale.employeeName!,
              ),
            ],
            if (_cashierName != null && _cashierName!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _detailRow(
                theme,
                LucideIcons.userCheck,
                'cashier_shifts.cashier'.tr(),
                _cashierName!,
              ),
              const SizedBox(height: 10),
              _detailRow(
                theme,
                LucideIcons.hash,
                'cashier_shifts.shift_number'.tr(),
                _cashierShiftNumber ?? '',
              ),
            ],
            const SizedBox(height: 10),
            _detailRow(
              theme,
              LucideIcons.clock,
              'sales.created_at'.tr(),
              DateFormat.yMMMd().add_jm().format(sale.createdAt),
            ),
            if (sale.isOverdue) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      size: 16,
                      color: colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'sales.overdue'.tr(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    final cs = theme.colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildItemsCard(BuildContext context, CurrencyService cs) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
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
                  'sales.items'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_items.isNotEmpty) ...[
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
                      '${_items.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.packageOpen,
                      size: 40,
                      color: colorScheme.onSurface.withValues(alpha: 0.15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'sales.no_items'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'sales.product_col'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text(
                      'sales.qty_col'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'sales.total'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                final isEven = index % 2 == 0;

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: isEven
                      ? Colors.transparent
                      : colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.2,
                        ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName ?? 'Product #${item.productId}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if ((item.variantSku ?? item.productSku) != null &&
                                (item.variantSku ?? item.productSku)!
                                    .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 2,
                                  bottom: 2,
                                ),
                                child: Text(
                                  'SKU: ${item.variantSku ?? item.productSku}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            if (item.colorName != null || item.sizeName != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 2,
                                  children: [
                                    if (item.colorName != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.tertiaryContainer
                                              .withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          item.colorName!,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onTertiaryContainer,
                                                fontSize: 10,
                                              ),
                                        ),
                                      ),
                                    if (item.sizeName != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.secondaryContainer
                                              .withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          item.sizeName!,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSecondaryContainer,
                                                fontSize: 10,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            Text(
                              cs.format(item.unitPriceCents.toBigInt().toInt()),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            if (item.discountCents > Decimal.zero)
                              Text(
                                '-${cs.format(item.discountCents.toBigInt().toInt())}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.tertiary,
                                  fontSize: 11,
                                ),
                              ),
                            if (item.taxCents > Decimal.zero)
                              Text(
                                '+${cs.format(item.taxCents.toBigInt().toInt())}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.secondary,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 50,
                        child: Text(
                          localizedQuantity(
                            item.quantity,
                            item.measurementType,
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          cs.format(item.totalCents.toBigInt().toInt()),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                          textAlign: TextAlign.end,
                        ),
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

  Widget _buildTotalsCard(
    BuildContext context,
    SaleEntity sale,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalItems = _items.length;
    final allPieceItems = _items.every(
      (item) => item.measurementType == 'piece',
    );
    final totalPieces = _items.fold<int>(0, (sum, item) => sum + item.quantity);

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
                _totalRow(theme, 'sales.total_items_count'.tr(), '$totalItems'),
                if (allPieceItems) ...[
                  const SizedBox(height: 8),
                  _totalRow(
                    theme,
                    'sales.total_pieces_count'.tr(),
                    '$totalPieces',
                  ),
                ],
                const SizedBox(height: 8),
                _totalRow(
                  theme,
                  'sales.subtotal'.tr(),
                  cs.format(sale.subtotalCents.toBigInt().toInt()),
                ),
                if (sale.discountCents > Decimal.zero) ...[
                  const SizedBox(height: 8),
                  _totalRow(
                    theme,
                    'sales.discount'.tr(),
                    '-${cs.format(sale.discountCents.toBigInt().toInt())}',
                    valueColor: colorScheme.tertiary,
                  ),
                ],
                if (sale.taxCents > Decimal.zero) ...[
                  const SizedBox(height: 8),
                  _totalRow(
                    theme,
                    'sales.tax'.tr(),
                    cs.format(sale.taxCents.toBigInt().toInt()),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.06),
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
                  'sales.total'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  cs.format(sale.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          // Payment tracking section
          if (sale.totalCents > Decimal.zero)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: sale.isFullyPaid
                    ? Colors.green.withValues(alpha: 0.06)
                    : sale.isOverdue
                    ? colorScheme.error.withValues(alpha: 0.06)
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.3,
                      ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            sale.isFullyPaid
                                ? LucideIcons.checkCircle
                                : LucideIcons.wallet,
                            size: 14,
                            color: sale.isFullyPaid
                                ? Colors.green
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'sales.paid'.tr(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: sale.isFullyPaid
                                  ? Colors.green
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        cs.format(sale.paidAmountCents.toBigInt().toInt()),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: sale.isFullyPaid ? Colors.green : null,
                        ),
                      ),
                    ],
                  ),
                  if (!sale.isFullyPaid) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.arrowRight,
                              size: 14,
                              color: sale.isOverdue
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'sales.remaining'.tr(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: sale.isOverdue
                                    ? colorScheme.error
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          cs.format(sale.remainingCents.toBigInt().toInt()),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: sale.isOverdue ? colorScheme.error : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotesCard(BuildContext context, SaleEntity sale) {
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
                    LucideIcons.stickyNote,
                    size: 16,
                    color: Colors.amber.shade700,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'sales.notes'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                sale.notes!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReturnsCard(BuildContext context, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                  'sales.returns'.tr(),
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
                    '${_returns.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _returns.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              itemBuilder: (context, index) {
                final ret = _returns[index];
                final statusColor = ret.isVoided
                    ? colorScheme.error
                    : Colors.green;
                final statusLabel = ret.isVoided
                    ? 'sales.status_voided'.tr()
                    : 'sales.status_posted'.tr();

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => context.push('/sales/returns/${ret.id}'),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.undo2,
                      size: 16,
                      color: colorScheme.error,
                    ),
                  ),
                  title: Text(
                    ret.returnNumber,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      Text(
                        DateFormat.yMMMd().format(ret.returnDate),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: Text(
                    cs.format(ret.totalCents.toBigInt().toInt()),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
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

  Widget _totalRow(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _TimelineStep {
  final String label;
  final IconData icon;
  final bool isActive;
  final bool isCompleted;
  final bool isError;

  const _TimelineStep({
    required this.label,
    required this.icon,
    this.isActive = false,
    this.isCompleted = false,
    this.isError = false,
  });
}
