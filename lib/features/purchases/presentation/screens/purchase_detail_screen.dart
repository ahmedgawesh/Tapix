import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../../../products/domain/repositories/product_variant_repository.dart';

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
  // STATUS TIMELINE (Premium)
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
                      gradient: steps[i].isCompleted
                          ? const LinearGradient(colors: [Colors.green, Colors.green])
                          : LinearGradient(colors: [
                              cs.outlineVariant.withValues(alpha: 0.5),
                              cs.outlineVariant.withValues(alpha: 0.3),
                            ]),
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
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: (step.isCompleted || step.isActive)
                ? LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: (step.isCompleted || step.isActive) ? null : cs.surfaceContainerHighest,
            shape: BoxShape.circle,
            boxShadow: (step.isCompleted || step.isActive)
                ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Icon(step.icon, size: 18,
              color: (step.isCompleted || step.isActive) ? Colors.white : cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(step.label,
            style: theme.textTheme.labelSmall?.copyWith(
                color: (step.isCompleted || step.isActive) ? color : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600),
            textAlign: TextAlign.center),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // INFO CARD (Invoice-style header)
  // ═══════════════════════════════════════════════════════
  Widget _buildInfoCard(BuildContext context, PurchaseEntity purchase, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final supplierInitial = purchase.supplierName != null &&
            purchase.supplierName!.isNotEmpty
        ? purchase.supplierName![0].toUpperCase()
        : '?';

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
            // Supplier section
            if (purchase.supplierName != null) ...[
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(supplierInitial,
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('purchases.supplier'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                letterSpacing: 0.5)),
                        Text(purchase.supplierName!,
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              Divider(height: 24, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ],
            // Details grid
            _detailRow(theme, LucideIcons.hash, 'purchases.number'.tr(),
                purchase.purchaseNumber),
            const SizedBox(height: 10),
            _detailRow(theme, LucideIcons.calendar, 'purchases.date'.tr(),
                DateFormat.yMMMd().format(purchase.purchaseDate)),
            if (purchase.dueDate != null) ...[              const SizedBox(height: 10),
              _detailRow(theme, LucideIcons.calendarClock, 'purchases.due_date'.tr(),
                  DateFormat.yMMMd().format(purchase.dueDate!),
                  valueColor: purchase.isOverdue ? colorScheme.error : null),
            ],
            if (purchase.paymentMethod != null && purchase.paymentMethod!.isNotEmpty) ...[              const SizedBox(height: 10),
              _detailRow(theme, LucideIcons.creditCard, 'purchases.payment_method'.tr(),
                  purchase.paymentMethod!),
            ],
            if (purchase.supplierInvoiceRef != null && purchase.supplierInvoiceRef!.isNotEmpty) ...[              const SizedBox(height: 10),
              _detailRow(theme, LucideIcons.fileText, 'purchases.supplier_ref'.tr(),
                  purchase.supplierInvoiceRef!),
            ],
            const SizedBox(height: 10),
            _detailRow(theme, LucideIcons.clock, 'purchases.created_at'.tr(),
                DateFormat.yMMMd().add_jm().format(purchase.createdAt)),
            if (purchase.isOverdue) ...[              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.alertTriangle, size: 16, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Text('purchases.overdue'.tr(),
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.error, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(ThemeData theme, IconData icon, String label, String value,
      {Color? valueColor}) {
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
        Text(label, style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant)),
        const Spacer(),
        Flexible(
          child: Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500, color: valueColor),
              textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // ITEMS CARD (Professional table-style)
  // ═══════════════════════════════════════════════════════
  Widget _buildItemsCard(BuildContext context, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color? tryParseHexColor(String? hex) {
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

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.shoppingCart, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('purchases.items'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
                if (_items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${_items.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold)),
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
                    Icon(LucideIcons.packageOpen, size: 40,
                        color: colorScheme.onSurface.withValues(alpha: 0.15)),
                    const SizedBox(height: 8),
                    Text('purchases.no_items'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else ...[
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                  bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 3,
                    child: Text('purchases.product_col'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5)),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text('purchases.qty_col'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5),
                        textAlign: TextAlign.center),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('purchases.total'.tr(),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5),
                        textAlign: TextAlign.end),
                  ),
                ],
              ),
            ),
            // Items
            StreamBuilder<Map<int, ({String? sizeName, String? colorHex})>>(
              stream: sl<ProductVariantRepository>().watchVariantPreviews(),
              builder: (context, snapshot) {
                final previews = snapshot.data ?? const {};
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isEven = index % 2 == 0;
                    final preview = previews[item.productId];
                    final sizeName = preview?.sizeName?.trim();
                    final shade = tryParseHexColor(preview?.colorHex);

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: isEven
                          ? Colors.transparent
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer.withValues(alpha: 0.6),
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
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w500),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if ((sizeName != null && sizeName.isNotEmpty) || shade != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (sizeName != null && sizeName.isNotEmpty)
                                          Flexible(
                                            child: Text(
                                              sizeName,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: colorScheme.onSurfaceVariant,
                                                fontSize: 11,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        if (sizeName != null && sizeName.isNotEmpty && shade != null)
                                          const SizedBox(width: 6),
                                        if (shade != null)
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: shade,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: colorScheme.outline),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                if (item.variantSku != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: colorScheme.tertiaryContainer.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.variantSku!,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onTertiaryContainer,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                Text(
                                  cs.format(item.unitCostCents.toBigInt().toInt()),
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
                                if (item.expiryDate != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          LucideIcons.calendarClock,
                                          size: 10,
                                          color: Colors.orange.shade700,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${'purchases.expiry_date'.tr()}: ${item.expiryDate!.toLocal().toString().split(' ').first}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 50,
                            child: Text(
                              '${item.quantity}',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  cs.format(item.totalCents.toBigInt().toInt()),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                Text(
                                  cs.format(item.subtotalCents.toBigInt().toInt()),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TOTALS CARD (Invoice footer style)
  // ═══════════════════════════════════════════════════════
  Widget _buildTotalsCard(BuildContext context, PurchaseEntity purchase, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Summary rows
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              children: [
                _summaryRow(theme, 'purchases.subtotal'.tr(),
                    cs.format(purchase.subtotalCents.toBigInt().toInt())),
                if (purchase.discountCents > Decimal.zero) ...[
                  const SizedBox(height: 8),
                  _summaryRow(theme, 'purchases.discount'.tr(),
                      '- ${cs.format(purchase.discountCents.toBigInt().toInt())}',
                      valueColor: colorScheme.tertiary,
                      icon: LucideIcons.percent),
                ],
                const SizedBox(height: 8),
                _summaryRow(theme, 'purchases.tax'.tr(),
                    cs.format(purchase.taxCents.toBigInt().toInt())),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Grand total
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.06),
              border: Border(
                top: BorderSide(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('purchases.total'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold)),
                Text(
                  cs.format(purchase.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // Payment tracking section
          if (purchase.totalCents > Decimal.zero)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: purchase.isFullyPaid
                    ? Colors.green.withValues(alpha: 0.06)
                    : purchase.isOverdue
                        ? colorScheme.error.withValues(alpha: 0.06)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                            purchase.isFullyPaid ? LucideIcons.checkCircle : LucideIcons.wallet,
                            size: 14,
                            color: purchase.isFullyPaid ? Colors.green : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text('purchases.paid'.tr(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: purchase.isFullyPaid ? Colors.green : colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      Text(
                        cs.format(purchase.paidAmountCents.toBigInt().toInt()),
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: purchase.isFullyPaid ? Colors.green : null),
                      ),
                    ],
                  ),
                  if (!purchase.isFullyPaid) ...[                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.arrowRight, size: 14,
                                color: purchase.isOverdue ? colorScheme.error : colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text('purchases.remaining'.tr(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: purchase.isOverdue ? colorScheme.error : colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        Text(
                          cs.format(purchase.remainingCents.toBigInt().toInt()),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: purchase.isOverdue ? colorScheme.error : null),
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

  Widget _summaryRow(ThemeData theme, String label, String value,
      {bool isBold = false, Color? valueColor, IconData? icon}) {
    final cs = theme.colorScheme;
    final style = isBold
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: valueColor ?? cs.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
            Text(label, style: style?.copyWith(
                color: isBold ? null : cs.onSurfaceVariant)),
          ],
        ),
        Text(value, style: (isBold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
            ?.copyWith(color: valueColor, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // NOTES CARD (Enhanced)
  // ═══════════════════════════════════════════════════════
  Widget _buildNotesCard(BuildContext context, PurchaseEntity purchase) {
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
                  child: Icon(LucideIcons.stickyNote, size: 16, color: Colors.amber.shade700),
                ),
                const SizedBox(width: 10),
                Text('purchases.notes'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
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
              child: Text(purchase.notes!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // RETURNS HISTORY CARD (Enhanced)
  // ═══════════════════════════════════════════════════════
  Widget _buildReturnsCard(BuildContext context, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalRefund = _returns.fold<int>(
        0, (sum, r) => sum + r.totalCents.toBigInt().toInt());

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.error.withValues(alpha: 0.25)),
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
                      colors: [colorScheme.error, colorScheme.error.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(LucideIcons.undo2, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('purchases.returns'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${_returns.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Text(cs.format(totalRefund),
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.error, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _returns.length,
            separatorBuilder: (_, idx) => Divider(
                height: 1, indent: 16, endIndent: 16,
                color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            itemBuilder: (context, index) {
              final ret = _returns[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
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
                          Row(
                            children: [
                              Icon(LucideIcons.calendar, size: 11,
                                  color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(DateFormat.yMMMd().format(ret.returnDate),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant, fontSize: 11)),
                            ],
                          ),
                          if (ret.reason != null && ret.reason!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(ret.reason!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
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
          const SizedBox(height: 8),
        ],
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
          debugPrint('[PurchaseDetailScreen] postPurchase failed: $e');
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
            debugPrint('[PurchaseDetailScreen] voidPurchase failed: $e');
            if (!mounted) return;
            final errorMsg = e.toString().replaceFirst('Exception: ', '');
            if (!context.mounted) return;
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                icon: Icon(LucideIcons.alertTriangle, color: errorColor, size: 32),
                title: Text('purchases.void_failed_title'.tr()),
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
