import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/inventory_pdf_service.dart';
import '../bloc/inventory_reports_bloc.dart';
import '../widgets/date_range_selector.dart';

class InventoryReportsScreen extends StatelessWidget {
  const InventoryReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<InventoryReportsBloc>(),
      child: const _InventoryReportsView(),
    );
  }
}

class _InventoryReportsView extends StatelessWidget {
  const _InventoryReportsView();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('reports.inventory_reports'.tr()),
          actions: [
            BlocBuilder<InventoryReportsBloc,
                RealtimeState<InventoryReportsData>>(
              builder: (context, state) {
                if (state is! RealtimeSuccess<InventoryReportsData>) {
                  return const SizedBox.shrink();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<PriceDisplayType>(
                      icon: const Icon(LucideIcons.tag),
                      tooltip: 'reports.price_type'.tr(),
                      onSelected: (type) => context
                          .read<InventoryReportsBloc>()
                          .add(InventoryReportsPriceTypeChanged(type)),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: PriceDisplayType.cost,
                          child: Row(
                            children: [
                              if (state.data.priceType == PriceDisplayType.cost)
                                Icon(LucideIcons.check, size: 16, color: Theme.of(context).colorScheme.primary)
                              else
                                const SizedBox(width: 16),
                              const SizedBox(width: 8),
                              Text('reports.cost_price'.tr()),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: PriceDisplayType.sale,
                          child: Row(
                            children: [
                              if (state.data.priceType == PriceDisplayType.sale)
                                Icon(LucideIcons.check, size: 16, color: Theme.of(context).colorScheme.primary)
                              else
                                const SizedBox(width: 16),
                              const SizedBox(width: 8),
                              Text('reports.sale_price'.tr()),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: PriceDisplayType.wholesale,
                          child: Row(
                            children: [
                              if (state.data.priceType == PriceDisplayType.wholesale)
                                Icon(LucideIcons.check, size: 16, color: Theme.of(context).colorScheme.primary)
                              else
                                const SizedBox(width: 16),
                              const SizedBox(width: 8),
                              Text('reports.wholesale_price'.tr()),
                            ],
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.printer),
                      tooltip: 'common.print'.tr(),
                      onPressed: () => _printReport(context, state.data),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.share2),
                      tooltip: 'common.share'.tr(),
                      onPressed: () => _shareReport(context, state.data),
                    ),
                  ],
                );
              },
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                icon: const Icon(LucideIcons.warehouse),
                text: 'reports.stock_valuation'.tr(),
              ),
              Tab(
                icon: const Icon(LucideIcons.alertTriangle),
                text: 'reports.low_stock'.tr(),
              ),
              Tab(
                icon: const Icon(LucideIcons.arrowLeftRight),
                text: 'reports.product_movement'.tr(),
              ),
            ],
          ),
        ),
        body: BlocBuilder<InventoryReportsBloc,
            RealtimeState<InventoryReportsData>>(
          builder: (context, state) {
            if (state is RealtimeLoading<InventoryReportsData>) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is RealtimeError<InventoryReportsData>) {
              final colorScheme = Theme.of(context).colorScheme;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline,
                        size: 48, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text(state.error.toString(),
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context
                          .read<InventoryReportsBloc>()
                          .refresh(),
                      icon: const Icon(LucideIcons.refreshCw),
                      label: Text('reports.retry'.tr()),
                    ),
                  ],
                ),
              );
            }

            if (state is RealtimeSuccess<InventoryReportsData>) {
              final data = state.data;
              return Column(
                children: [
                  // Date range selector
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: DateRangeSelector(
                      dateRange: data.dateRange,
                      onChanged: (range) => context
                          .read<InventoryReportsBloc>()
                          .add(InventoryReportsDateRangeChanged(range)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Tab content
                  Expanded(
                    child: TabBarView(
                      children: [
                        _StockValuationTab(data: data),
                        _LowStockTab(items: data.lowStockItems),
                        _ProductMovementTab(items: data.productMovement),
                      ],
                    ),
                  ),
                ],
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, InventoryReportsData data) async {
    await InventoryPdfService.printInventoryReport(
      context: context,
      data: data,
      priceType: data.priceType,
    );
  }

  Future<void> _shareReport(
      BuildContext context, InventoryReportsData data) async {
    await InventoryPdfService.shareInventoryReport(
      context: context,
      data: data,
      priceType: data.priceType,
    );
  }
}

// ==================== STOCK VALUATION TAB ====================

class _StockValuationTab extends StatelessWidget {
  final InventoryReportsData data;
  const _StockValuationTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    // Compute total valuation based on selected price type
    int totalValuation = 0;
    for (final item in data.stockValuation) {
      totalValuation += item.valuationByType(data.priceType);
    }

    return Column(
      children: [
        // Summary cards
        Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 500;
              return isWide
                  ? Row(
                      children: [
                        Expanded(
                          child: _SummaryCard(
                            icon: LucideIcons.dollarSign,
                            label: 'reports.total_valuation'.tr(),
                            value: cs.formatCents(totalValuation),
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            icon: LucideIcons.package,
                            label: 'reports.total_stock_units'.tr(),
                            value: '${data.totalStockUnits}',
                            color: colorScheme.tertiary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SummaryCard(
                            icon: LucideIcons.layers,
                            label: 'reports.products_count'.tr(),
                            value: '${data.stockValuation.length}',
                            color: colorScheme.secondary,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                icon: LucideIcons.dollarSign,
                                label: 'reports.total_valuation'.tr(),
                                value: cs.formatCents(totalValuation),
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                icon: LucideIcons.package,
                                label: 'reports.total_stock_units'.tr(),
                                value: '${data.totalStockUnits}',
                                color: colorScheme.tertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SummaryCard(
                          icon: LucideIcons.layers,
                          label: 'reports.products_count'.tr(),
                          value: '${data.stockValuation.length}',
                          color: colorScheme.secondary,
                        ),
                      ],
                    );
            },
          ),
        ),

        // Sort selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'reports.sort_by'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _SortChip(
                        label: 'reports.sort_value'.tr(),
                        selected: data.sort == StockValuationSort.valueDesc ||
                            data.sort == StockValuationSort.valueAsc,
                        onTap: () {
                          final next =
                              data.sort == StockValuationSort.valueDesc
                                  ? StockValuationSort.valueAsc
                                  : StockValuationSort.valueDesc;
                          context
                              .read<InventoryReportsBloc>()
                              .add(InventoryReportsSortChanged(next));
                        },
                        ascending: data.sort == StockValuationSort.valueAsc,
                      ),
                      _SortChip(
                        label: 'reports.sort_name'.tr(),
                        selected: data.sort == StockValuationSort.nameAsc ||
                            data.sort == StockValuationSort.nameDesc,
                        onTap: () {
                          final next =
                              data.sort == StockValuationSort.nameAsc
                                  ? StockValuationSort.nameDesc
                                  : StockValuationSort.nameAsc;
                          context
                              .read<InventoryReportsBloc>()
                              .add(InventoryReportsSortChanged(next));
                        },
                        ascending: data.sort == StockValuationSort.nameAsc,
                      ),
                      _SortChip(
                        label: 'reports.sort_stock'.tr(),
                        selected: data.sort == StockValuationSort.stockDesc ||
                            data.sort == StockValuationSort.stockAsc,
                        onTap: () {
                          final next =
                              data.sort == StockValuationSort.stockDesc
                                  ? StockValuationSort.stockAsc
                                  : StockValuationSort.stockDesc;
                          context
                              .read<InventoryReportsBloc>()
                              .add(InventoryReportsSortChanged(next));
                        },
                        ascending: data.sort == StockValuationSort.stockAsc,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // List
        Expanded(
          child: data.stockValuation.isEmpty
              ? Center(child: Text('reports.no_data'.tr()))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: data.stockValuation.length,
                  itemBuilder: (context, index) {
                    final item = data.stockValuation[index];
                    return _StockValuationCard(item: item, priceType: data.priceType);
                  },
                ),
        ),
      ],
    );
  }
}

// ==================== LOW STOCK TAB ====================

class _LowStockTab extends StatelessWidget {
  final List<LowStockItem> items;
  const _LowStockTab({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.checkCircle, size: 64, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'reports.no_low_stock'.tr(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.no_low_stock_desc'.tr(),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Alert banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: colorScheme.errorContainer,
          child: Row(
            children: [
              Icon(LucideIcons.alertTriangle, color: colorScheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'reports.low_stock_alert'.tr(args: ['${items.length}']),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _LowStockCard(item: item);
            },
          ),
        ),
      ],
    );
  }
}

// ==================== PRODUCT MOVEMENT TAB ====================

class _ProductMovementTab extends StatelessWidget {
  final List<ProductMovementItem> items;
  const _ProductMovementTab({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text('reports.no_movement_data'.tr()));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _ProductMovementCard(item: items[index]);
      },
    );
  }
}

// ==================== SHARED WIDGETS ====================

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StockValuationCard extends StatelessWidget {
  final StockValuationItem item;
  final PriceDisplayType priceType;
  const _StockValuationCard({required this.item, required this.priceType});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    String priceLabel;
    switch (priceType) {
      case PriceDisplayType.cost:
        priceLabel = 'reports.unit_cost'.tr();
      case PriceDisplayType.sale:
        priceLabel = 'reports.sale_price'.tr();
      case PriceDisplayType.wholesale:
        priceLabel = 'reports.wholesale_price'.tr();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (item.sku != null)
                        Text(
                          item.sku!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      if (item.categoryName != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.categoryName!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSecondaryContainer,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (item.variantLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.variantLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onTertiaryContainer,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'reports.stock_qty_variants'.tr(args: [
                      '${item.totalStock}',
                      '${item.variantCount}',
                    ]),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  cs.formatCents(item.valuationByType(priceType)),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$priceLabel: ${cs.formatCents(item.priceByType(priceType))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

class _LowStockCard extends StatelessWidget {
  final LowStockItem item;
  const _LowStockCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOutOfStock = item.currentStock <= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isOutOfStock
          ? colorScheme.errorContainer.withValues(alpha: 0.3)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isOutOfStock
                    ? colorScheme.error.withValues(alpha: 0.1)
                    : colorScheme.tertiary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isOutOfStock ? LucideIcons.xCircle : LucideIcons.alertTriangle,
                color: isOutOfStock ? colorScheme.error : colorScheme.tertiary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (item.sku != null)
                        Text(
                          item.sku!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      if (item.categoryName != null)
                        Text(
                          item.categoryName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (item.variantLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.variantLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.currentStock} / ${item.reorderLevel}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isOutOfStock ? colorScheme.error : colorScheme.tertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'reports.need_to_order'.tr(args: ['${item.deficit}']),
                  style: theme.textTheme.bodySmall?.copyWith(
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
}

class _ProductMovementCard extends StatelessWidget {
  final ProductMovementItem item;
  const _ProductMovementCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.sku != null || item.variantLabel.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (item.sku != null)
                              Text(
                                item.sku!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            if (item.variantLabel.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.variantLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  item.netMovement >= 0
                      ? '+${item.netMovement}'
                      : '${item.netMovement}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: item.netMovement >= 0
                        ? colorScheme.primary
                        : colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MovementChip(
                  label: 'reports.purchased'.tr(),
                  value: '+${item.purchasedQty}',
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _MovementChip(
                  label: 'reports.sold'.tr(),
                  value: '-${item.soldQty}',
                  color: colorScheme.error,
                ),
                const SizedBox(width: 8),
                _MovementChip(
                  label: 'reports.returned'.tr(),
                  value: '${item.returnedQty}',
                  color: colorScheme.tertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MovementChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool ascending;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.ascending = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(
                ascending ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                size: 14,
              ),
            ],
          ],
        ),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
