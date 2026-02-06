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
    if (mounted) {
      setState(() {
        _purchase = purchase;
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = sl<CurrencyService>();

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
              Text('purchases.not_found'.tr(),
                  style: theme.textTheme.titleLarge),
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
        actions: [
          if (purchase.isDraft)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (value) => _handleAction(value, context),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'post',
                  child: ListTile(
                    leading: const Icon(LucideIcons.checkCircle),
                    title: Text('purchases.post'.tr()),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(LucideIcons.trash2, color: colorScheme.error),
                    title: Text('purchases.delete'.tr(),
                        style: TextStyle(color: colorScheme.error)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          if (purchase.isPosted)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (value) => _handleAction(value, context),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'return',
                  child: ListTile(
                    leading: const Icon(LucideIcons.undo2),
                    title: Text('purchases.create_return'.tr()),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'void',
                  child: ListTile(
                    leading: Icon(LucideIcons.ban, color: colorScheme.error),
                    title: Text('purchases.void_purchase'.tr(),
                        style: TextStyle(color: colorScheme.error)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPurchase,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── Status Badge ───
            _buildStatusBanner(context, purchase),
            const SizedBox(height: 16),

            // ─── Purchase Info ───
            _buildInfoCard(context, purchase, currencyService),
            const SizedBox(height: 16),

            // ─── Items ───
            _buildItemsCard(context, currencyService),
            const SizedBox(height: 16),

            // ─── Totals ───
            _buildTotalsCard(context, purchase, currencyService),
            const SizedBox(height: 16),

            // ─── Notes ───
            if (purchase.notes != null && purchase.notes!.isNotEmpty)
              _buildNotesCard(context, purchase),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, PurchaseEntity purchase) {
    final theme = Theme.of(context);
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (purchase.status) {
      case 'draft':
      case 'pending':
        bgColor = Colors.orange.withValues(alpha: 0.12);
        textColor = Colors.orange;
        icon = LucideIcons.fileEdit;
        label = 'purchases.status_draft'.tr();
        break;
      case 'posted':
        bgColor = Colors.green.withValues(alpha: 0.12);
        textColor = Colors.green;
        icon = LucideIcons.checkCircle;
        label = 'purchases.status_posted'.tr();
        break;
      case 'voided':
        bgColor = theme.colorScheme.error.withValues(alpha: 0.12);
        textColor = theme.colorScheme.error;
        icon = LucideIcons.ban;
        label = 'purchases.status_voided'.tr();
        break;
      default:
        bgColor = Colors.grey.withValues(alpha: 0.12);
        textColor = Colors.grey;
        icon = LucideIcons.helpCircle;
        label = purchase.status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor),
          const SizedBox(width: 12),
          Text(label,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: textColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, PurchaseEntity purchase,
      CurrencyService currencyService) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('purchases.details'.tr(),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _infoRow(context, LucideIcons.hash, 'purchases.number'.tr(),
                purchase.purchaseNumber),
            const SizedBox(height: 8),
            if (purchase.supplierName != null)
              _infoRow(context, LucideIcons.truck, 'purchases.supplier'.tr(),
                  purchase.supplierName!),
            const SizedBox(height: 8),
            _infoRow(context, LucideIcons.calendar, 'purchases.date'.tr(),
                DateFormat.yMMMd().format(purchase.purchaseDate)),
            const SizedBox(height: 8),
            _infoRow(context, LucideIcons.clock, 'purchases.created_at'.tr(),
                DateFormat.yMMMd().add_jm().format(purchase.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const Spacer(),
        Text(value,
            style:
                theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildItemsCard(
      BuildContext context, CurrencyService currencyService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.package, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text('purchases.items'.tr(),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${_items.length} ${'purchases.items_count'.tr()}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant)),
              ],
            ),
            const Divider(height: 24),
            if (_items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('purchases.no_items'.tr(),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colorScheme.onSurfaceVariant)),
                ),
              )
            else
              ...List.generate(_items.length, (index) {
                final item = _items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Text('${index + 1}',
                            style: theme.textTheme.bodySmall?.copyWith(
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
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (item.variantSku != null)
                              Text('SKU: ${item.variantSku}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant)),
                            Text(
                              '${currencyService.format(item.unitCostCents.toBigInt().toInt())} × ${item.quantity}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                            if (item.expiryDate != null)
                              Row(
                                children: [
                                  const Icon(LucideIcons.alertTriangle,
                                      size: 12, color: Colors.orange),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${'purchases.expiry'.tr()}: ${DateFormat.yMMMd().format(item.expiryDate!)}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: Colors.orange),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      Text(
                        currencyService.format(item.totalCents.toBigInt().toInt()),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsCard(BuildContext context, PurchaseEntity purchase,
      CurrencyService currencyService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _totalRow(context, 'purchases.subtotal'.tr(),
                currencyService.format(purchase.subtotalCents.toBigInt().toInt())),
            if (purchase.discountCents > Decimal.zero) ...[
              const SizedBox(height: 8),
              _totalRow(
                context,
                'purchases.discount'.tr(),
                '- ${currencyService.format(purchase.discountCents.toBigInt().toInt())}',
                valueColor: colorScheme.tertiary,
              ),
            ],
            const SizedBox(height: 8),
            _totalRow(context, 'purchases.tax'.tr(),
                currencyService.format(purchase.taxCents.toBigInt().toInt())),
            const Divider(height: 24),
            _totalRow(
              context,
              'purchases.total'.tr(),
              currencyService.format(purchase.totalCents.toBigInt().toInt()),
              isBold: true,
              valueColor: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(BuildContext context, String label, String value,
      {bool isBold = false, Color? valueColor}) {
    final theme = Theme.of(context);
    final style = isBold
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value,
            style: style?.copyWith(
                color: valueColor,
                fontWeight: isBold ? FontWeight.bold : null)),
      ],
    );
  }

  Widget _buildNotesCard(BuildContext context, PurchaseEntity purchase) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.stickyNote,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('purchases.notes'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(purchase.notes!,
                style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

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
            SnackBar(content: Text('purchases.posted_success'.tr())),
          );
          _loadPurchase();
        } catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text(e.toString()),
                backgroundColor: errorColor),
          );
        }
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
              SnackBar(content: Text('purchases.voided_success'.tr())),
            );
            _loadPurchase();
          } catch (e) {
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(e.toString()),
                  backgroundColor: errorColor),
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
              SnackBar(content: Text('purchases.deleted_success'.tr())),
            );
            router.pop();
          } catch (e) {
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(e.toString()),
                  backgroundColor: errorColor),
            );
          }
        }
        break;
      case 'return':
        context.push('/purchases/returns/new?purchaseId=${widget.purchaseId}');
        break;
    }
  }
}
