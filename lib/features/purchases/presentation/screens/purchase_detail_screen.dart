import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';

class PurchaseDetailScreen extends StatefulWidget {
  final int purchaseId;

  const PurchaseDetailScreen({super.key, required this.purchaseId});

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  PurchaseEntity? _purchase;
  List<PurchaseItemEntity> _items = [];
  List<PurchaseReturnEntity> _returns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPurchase();
  }

  Future<void> _loadPurchase() async {
    final repo = sl<PurchaseRepository>();
    final purchase = await repo.getPurchaseById(widget.purchaseId);
    final items = await repo.getPurchaseItems(widget.purchaseId);
    final returns = await repo.getPurchaseReturns(widget.purchaseId);
    if (mounted) {
      setState(() {
        _purchase = purchase;
        _items = items;
        _returns = returns;
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
        appBar: AppBar(title: Text('purchases.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_purchase == null) {
      return Scaffold(
        appBar: AppBar(title: Text('purchases.title'.tr())),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.alertCircle, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text('purchases.not_found'.tr(), style: theme.textTheme.titleLarge),
            ],
          ),
        ),
      );
    }

    final purchase = _purchase!;

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
        title: Text(purchase.purchaseNumber),
        actions: _buildActions(purchase, colorScheme),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPurchase,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            if (isWide) {
              return _buildWideLayout(context, purchase, cs);
            }
            return _buildNarrowLayout(context, purchase, cs);
          },
        ),
      ),
    );
  }

  List<Widget> _buildActions(PurchaseEntity purchase, ColorScheme colorScheme) {
    final actions = <Widget>[];

    if (purchase.isDraft) {
      actions.add(
        FilledButton.tonalIcon(
          onPressed: () => _handleAction('post', context),
          icon: const Icon(LucideIcons.checkCircle, size: 16),
          label: Text('purchases.post'.tr()),
        ),
      );
      actions.add(const SizedBox(width: 4));
      actions.add(
        PopupMenuButton<String>(
          icon: const Icon(LucideIcons.moreVertical),
          onSelected: (v) => _handleAction(v, context),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: const Icon(LucideIcons.edit3),
                title: Text('purchases.edit'.tr()),
                dense: true, contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(LucideIcons.trash2, color: colorScheme.error),
                title: Text('purchases.delete'.tr(),
                    style: TextStyle(color: colorScheme.error)),
                dense: true, contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      );
    }

    if (purchase.isPosted) {
      actions.add(
        FilledButton.tonalIcon(
          onPressed: () => _handleAction('return', context),
          icon: const Icon(LucideIcons.undo2, size: 16),
          label: Text('purchases.create_return'.tr()),
        ),
      );
      actions.add(const SizedBox(width: 4));
      actions.add(
        PopupMenuButton<String>(
          icon: const Icon(LucideIcons.moreVertical),
          onSelected: (v) => _handleAction(v, context),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'void',
              child: ListTile(
                leading: Icon(LucideIcons.ban, color: colorScheme.error),
                title: Text('purchases.void_purchase'.tr(),
                    style: TextStyle(color: colorScheme.error)),
                dense: true, contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      );
    }

    return actions;
  }

  // ═══════════════════════════════════════════════════════
  // WIDE LAYOUT
  // ═══════════════════════════════════════════════════════
  Widget _buildWideLayout(BuildContext context, PurchaseEntity purchase, CurrencyService cs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 380,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStatusTimeline(context, purchase),
              const SizedBox(height: 16),
              _buildInfoCard(context, purchase, cs),
              const SizedBox(height: 16),
              _buildTotalsCard(context, purchase, cs),
              const SizedBox(height: 16),
              if (purchase.notes != null && purchase.notes!.isNotEmpty)
                _buildNotesCard(context, purchase),
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
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // NARROW LAYOUT
  // ═══════════════════════════════════════════════════════
  Widget _buildNarrowLayout(BuildContext context, PurchaseEntity purchase, CurrencyService cs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusTimeline(context, purchase),
        const SizedBox(height: 16),
        _buildInfoCard(context, purchase, cs),
        const SizedBox(height: 16),
        _buildItemsCard(context, cs),
        const SizedBox(height: 16),
        _buildTotalsCard(context, purchase, cs),
        const SizedBox(height: 16),
        if (purchase.notes != null && purchase.notes!.isNotEmpty) ...[
          _buildNotesCard(context, purchase),
          const SizedBox(height: 16),
        ],
        if (_returns.isNotEmpty)
          _buildReturnsCard(context, cs),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // STATUS TIMELINE
  // ═══════════════════════════════════════════════════════
  Widget _buildStatusTimeline(BuildContext context, PurchaseEntity purchase) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final steps = <_TimelineStep>[
      _TimelineStep(
        label: 'purchases.status_draft'.tr(),
        icon: LucideIcons.fileEdit,
        isActive: true,
        isCompleted: purchase.status != 'draft' && purchase.status != 'pending',
      ),
      _TimelineStep(
        label: 'purchases.status_posted'.tr(),
        icon: LucideIcons.checkCircle,
        isActive: purchase.isPosted || purchase.isVoided,
        isCompleted: purchase.isPosted,
      ),
    ];

    if (purchase.isVoided) {
      steps.add(_TimelineStep(
        label: 'purchases.status_voided'.tr(),
        icon: LucideIcons.ban,
        isActive: true,
        isCompleted: false,
        isError: true,
      ));
    }

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
            for (int i = 0; i < steps.length; i++) ...[
              _buildTimelineNode(theme, steps[i]),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: steps[i].isCompleted
                        ? Colors.green
                        : cs.outlineVariant,
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
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(step.icon, size: 16, color: color),
        ),
        const SizedBox(height: 4),
        Text(step.label,
            style: theme.textTheme.labelSmall?.copyWith(
                color: color, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // INFO CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildInfoCard(BuildContext context, PurchaseEntity purchase, CurrencyService cs) {
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
                Icon(LucideIcons.info, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('purchases.details'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            _detailRow(theme, LucideIcons.hash, 'purchases.number'.tr(),
                purchase.purchaseNumber),
            const SizedBox(height: 8),
            if (purchase.supplierName != null) ...[
              _detailRow(theme, LucideIcons.building2, 'purchases.supplier'.tr(),
                  purchase.supplierName!),
              const SizedBox(height: 8),
            ],
            _detailRow(theme, LucideIcons.calendar, 'purchases.date'.tr(),
                DateFormat.yMMMd().format(purchase.purchaseDate)),
            const SizedBox(height: 8),
            _detailRow(theme, LucideIcons.clock, 'purchases.created_at'.tr(),
                DateFormat.yMMMd().add_jm().format(purchase.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant)),
        const Spacer(),
        Flexible(
          child: Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // ITEMS CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsCard(BuildContext context, CurrencyService cs) {
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
                if (_items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${_items.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('purchases.no_items'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (_, idx) => Divider(
                    height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28, height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${index + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName ?? 'Product #${item.productId}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600),
                              ),
                              if (item.variantSku != null)
                                Text('SKU: ${item.variantSku}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant)),
                              Text(
                                '${cs.format(item.unitCostCents.toBigInt().toInt())} × ${item.quantity}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant),
                              ),
                              if (item.discountCents > Decimal.zero)
                                Text(
                                  '${'purchases.discount'.tr()}: -${cs.format(item.discountCents.toBigInt().toInt())}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.tertiary),
                                ),
                              if (item.expiryDate != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(LucideIcons.clock,
                                        size: 12, color: Colors.orange),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat.yMMMd().format(item.expiryDate!),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.orange, fontSize: 11),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        Text(
                          cs.format(item.totalCents.toBigInt().toInt()),
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold),
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
  // TOTALS CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildTotalsCard(BuildContext context, PurchaseEntity purchase, CurrencyService cs) {
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
                cs.format(purchase.subtotalCents.toBigInt().toInt())),
            if (purchase.discountCents > Decimal.zero) ...[
              const SizedBox(height: 6),
              _summaryRow(theme, 'purchases.discount'.tr(),
                  '- ${cs.format(purchase.discountCents.toBigInt().toInt())}',
                  valueColor: colorScheme.tertiary),
            ],
            const SizedBox(height: 6),
            _summaryRow(theme, 'purchases.tax'.tr(),
                cs.format(purchase.taxCents.toBigInt().toInt())),
            Divider(height: 24, color: colorScheme.outlineVariant),
            _summaryRow(theme, 'purchases.total'.tr(),
                cs.format(purchase.totalCents.toBigInt().toInt()),
                isBold: true, valueColor: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(ThemeData theme, String label, String value,
      {bool isBold = false, Color? valueColor}) {
    final style = isBold
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: (isBold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
            ?.copyWith(color: valueColor, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // NOTES CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildNotesCard(BuildContext context, PurchaseEntity purchase) {
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
            Text(purchase.notes!, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // RETURNS HISTORY CARD
  // ═══════════════════════════════════════════════════════
  Widget _buildReturnsCard(BuildContext context, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.undo2, size: 20, color: colorScheme.error),
                const SizedBox(width: 8),
                Text('purchases.returns'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${_returns.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _returns.length,
              separatorBuilder: (_, idx) => Divider(
                  height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              itemBuilder: (context, index) {
                final ret = _returns[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(LucideIcons.undo2, size: 16, color: colorScheme.error),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ret.returnNumber,
                                style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600)),
                            Text(DateFormat.yMMMd().format(ret.returnDate),
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant)),
                            if (ret.reason != null && ret.reason!.isNotEmpty)
                              Text(ret.reason!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      Text(
                        cs.format(ret.totalCents.toBigInt().toInt()),
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold, color: colorScheme.error),
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
  // ACTIONS
  // ═══════════════════════════════════════════════════════
  void _handleAction(String action, BuildContext context) async {
    final repo = sl<PurchaseRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final router = GoRouter.of(context);

    switch (action) {
      case 'post':
        try {
          await repo.postPurchase(widget.purchaseId);
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text('purchases.posted_success'.tr()),
                behavior: SnackBarBehavior.floating),
          );
          _loadPurchase();
        } catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text(e.toString()),
                backgroundColor: errorColor, behavior: SnackBarBehavior.floating),
          );
        }
        break;
      case 'edit':
        router.push('/purchases/${widget.purchaseId}/edit');
        break;
      case 'void':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('purchases.void_confirm_title'.tr()),
            content: Text('purchases.void_confirm_message'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common.cancel'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: errorColor),
                child: Text('purchases.void_purchase'.tr()),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          try {
            await repo.voidPurchase(widget.purchaseId);
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text('purchases.voided_success'.tr()),
                  behavior: SnackBarBehavior.floating),
            );
            _loadPurchase();
          } catch (e) {
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(e.toString()),
                  backgroundColor: errorColor, behavior: SnackBarBehavior.floating),
            );
          }
        }
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('purchases.delete_confirm_title'.tr()),
            content: Text('purchases.delete_confirm_message'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('common.cancel'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: errorColor),
                child: Text('purchases.delete'.tr()),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          try {
            await repo.deletePurchase(widget.purchaseId);
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text('purchases.deleted_success'.tr()),
                  behavior: SnackBarBehavior.floating),
            );
            router.pop();
          } catch (e) {
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(e.toString()),
                  backgroundColor: errorColor, behavior: SnackBarBehavior.floating),
            );
          }
        }
        break;
      case 'return':
        router.push('/purchases/returns/new?purchaseId=${widget.purchaseId}');
        break;
    }
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
    required this.isActive,
    required this.isCompleted,
    this.isError = false,
  });
}
