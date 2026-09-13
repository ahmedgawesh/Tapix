import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/supplier_stocktake_pdf_service.dart';
import '../bloc/supplier_stocktake_report_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/report_scrollable_center.dart';
import '../widgets/searchable_party_selector.dart';

class SupplierStocktakeReportScreen extends StatelessWidget {
  const SupplierStocktakeReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SupplierStocktakeReportBloc>(),
      child: const _SupplierStocktakeReportView(),
    );
  }
}

class _SupplierStocktakeReportView extends StatelessWidget {
  const _SupplierStocktakeReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.supplier_stocktake'.tr()),
        actions: [
          BlocBuilder<
            SupplierStocktakeReportBloc,
            RealtimeState<SupplierStocktakeReportData>
          >(
            builder: (context, state) {
              if (state is! RealtimeSuccess<SupplierStocktakeReportData>) {
                return const SizedBox.shrink();
              }
              if (state.data.supplierId == null) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
      ),
      body:
          BlocBuilder<
            SupplierStocktakeReportBloc,
            RealtimeState<SupplierStocktakeReportData>
          >(
            builder: (context, state) {
              if (state is RealtimeLoading<SupplierStocktakeReportData>) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is RealtimeError<SupplierStocktakeReportData>) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        state.error.toString(),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              }

              if (state is RealtimeSuccess<SupplierStocktakeReportData>) {
                return Column(
                  children: [
                    // Supplier selector
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _SupplierSelector(
                        suppliers: state.data.suppliers,
                        selectedId: state.data.supplierId,
                        onChanged: (id) => context
                            .read<SupplierStocktakeReportBloc>()
                            .add(SupplierStocktakeReportSupplierChanged(id)),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Date range selector
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DateRangeSelector(
                        dateRange: state.data.dateRange,
                        onChanged: (range) =>
                            context.read<SupplierStocktakeReportBloc>().add(
                              SupplierStocktakeReportDateRangeChanged(range),
                            ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Content
                    Expanded(
                      child: state.data.supplierId == null
                          ? _buildSelectSupplierPrompt(context)
                          : _StocktakeContent(data: state.data),
                    ),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),
    );
  }

  Widget _buildSelectSupplierPrompt(BuildContext context) {
    final theme = Theme.of(context);
    return ReportScrollableCenter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.search, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'reports.select_supplier_prompt'.tr(),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'reports.select_supplier_stocktake_desc'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printReport(
    BuildContext context,
    SupplierStocktakeReportData data,
  ) async {
    await SupplierStocktakePdfService.printSupplierStocktakeReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_supplier_stocktake_report',
    );
  }

  Future<void> _shareReport(
    BuildContext context,
    SupplierStocktakeReportData data,
  ) async {
    await SupplierStocktakePdfService.shareSupplierStocktakeReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_supplier_stocktake_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUPPLIER SELECTOR
// ═══════════════════════════════════════════════════════

class _SupplierSelector extends StatelessWidget {
  final List<SupplierOption> suppliers;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  const _SupplierSelector({
    required this.suppliers,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SearchablePartySelector(
      labelText: 'reports.select_supplier'.tr(),
      prefixIcon: LucideIcons.truck,
      selectedId: selectedId,
      onChanged: onChanged,
      options: suppliers
          .map(
            (s) => SearchablePartyOption(
              id: s.id,
              name: s.name,
              phone: s.phone,
              balanceCents: s.balanceCents,
            ),
          )
          .toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUMMARY CARD
// ═══════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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

// ═══════════════════════════════════════════════════════
// SORT CHIP
// ═══════════════════════════════════════════════════════

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
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(
                ascending ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                size: 12,
              ),
            ],
          ],
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// STOCKTAKE CONTENT (after supplier selected)
// ═══════════════════════════════════════════════════════

class _StocktakeContent extends StatefulWidget {
  final SupplierStocktakeReportData data;
  const _StocktakeContent({required this.data});

  @override
  State<_StocktakeContent> createState() => _StocktakeContentState();
}

class _StocktakeContentState extends State<_StocktakeContent> {
  late final TextEditingController _searchController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.data.searchQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      context.read<SupplierStocktakeReportBloc>().add(
        SupplierStocktakeSearchChanged(query),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Search bar
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'reports.search_product_hint'.tr(),
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
          ),
          onChanged: (q) {
            setState(() {});
            _onSearchChanged(q);
          },
        ),
        const SizedBox(height: 8),

        // Category filter + sort chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Category filter chip
              _CategoryFilterChip(
                label:
                    data.filterCategoryName ?? 'reports.filter_category'.tr(),
                sheetTitle: 'reports.filter_category'.tr(),
                isActive: data.filterCategoryId != null,
                options: data.availableCategories,
                onSelected: (opt) =>
                    context.read<SupplierStocktakeReportBloc>().add(
                      SupplierStocktakeCategoryFilterChanged(
                        opt?.id,
                        opt?.name,
                      ),
                    ),
              ),
              const SizedBox(width: 8),
              // Sort chips
              _SortChip(
                label: 'reports.sort_value'.tr(),
                selected:
                    data.sort == SupplierStocktakeSortType.valueDesc ||
                    data.sort == SupplierStocktakeSortType.valueAsc,
                onTap: () {
                  final next = data.sort == SupplierStocktakeSortType.valueDesc
                      ? SupplierStocktakeSortType.valueAsc
                      : SupplierStocktakeSortType.valueDesc;
                  context.read<SupplierStocktakeReportBloc>().add(
                    SupplierStocktakeReportSortChanged(next),
                  );
                },
                ascending: data.sort == SupplierStocktakeSortType.valueAsc,
              ),
              _SortChip(
                label: 'reports.sort_name'.tr(),
                selected:
                    data.sort == SupplierStocktakeSortType.nameAsc ||
                    data.sort == SupplierStocktakeSortType.nameDesc,
                onTap: () {
                  final next = data.sort == SupplierStocktakeSortType.nameAsc
                      ? SupplierStocktakeSortType.nameDesc
                      : SupplierStocktakeSortType.nameAsc;
                  context.read<SupplierStocktakeReportBloc>().add(
                    SupplierStocktakeReportSortChanged(next),
                  );
                },
                ascending: data.sort == SupplierStocktakeSortType.nameAsc,
              ),
              _SortChip(
                label: 'reports.sort_remaining'.tr(),
                selected:
                    data.sort == SupplierStocktakeSortType.stockDesc ||
                    data.sort == SupplierStocktakeSortType.stockAsc,
                onTap: () {
                  final next = data.sort == SupplierStocktakeSortType.stockDesc
                      ? SupplierStocktakeSortType.stockAsc
                      : SupplierStocktakeSortType.stockDesc;
                  context.read<SupplierStocktakeReportBloc>().add(
                    SupplierStocktakeReportSortChanged(next),
                  );
                },
                ascending: data.sort == SupplierStocktakeSortType.stockAsc,
              ),
              _SortChip(
                label: 'reports.sort_sold'.tr(),
                selected: data.sort == SupplierStocktakeSortType.soldDesc,
                onTap: () => context.read<SupplierStocktakeReportBloc>().add(
                  const SupplierStocktakeReportSortChanged(
                    SupplierStocktakeSortType.soldDesc,
                  ),
                ),
              ),
              _SortChip(
                label: 'reports.sort_purchased'.tr(),
                selected: data.sort == SupplierStocktakeSortType.purchasedDesc,
                onTap: () => context.read<SupplierStocktakeReportBloc>().add(
                  const SupplierStocktakeReportSortChanged(
                    SupplierStocktakeSortType.purchasedDesc,
                  ),
                ),
              ),
              _SortChip(
                label: 'reports.sort_profit'.tr(),
                selected: data.sort == SupplierStocktakeSortType.profitDesc,
                onTap: () => context.read<SupplierStocktakeReportBloc>().add(
                  const SupplierStocktakeReportSortChanged(
                    SupplierStocktakeSortType.profitDesc,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Summary cards - 3 rows of 2
        _buildSummaryCards(context, data, cs),
        const SizedBox(height: 12),

        // Products header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'reports.stocktake_items'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'reports.stocktake_products'.tr(args: ['${data.totalProducts}']),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (data.products.isEmpty)
          _buildEmptyProducts(context)
        else
          _buildProductTable(context, cs),
      ],
    );
  }

  Widget _buildSummaryCards(
    BuildContext context,
    SupplierStocktakeReportData data,
    CurrencyService cs,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    String totalOf(int Function(SupplierStocktakeProductItem item) selector) {
      final totals = <String, int>{};
      for (final item in data.products) {
        totals.update(
          item.measurementType,
          (value) => value + selector(item),
          ifAbsent: () => selector(item),
        );
      }
      return localizedQuantityTotals(totals);
    }

    final cards = [
      _SummaryCard(
        label: 'reports.total_purchased'.tr(),
        value: totalOf((item) => item.purchasedQuantity),
        icon: LucideIcons.shoppingCart,
        color: colorScheme.primary,
      ),
      _SummaryCard(
        label: 'reports.total_sold'.tr(),
        value: totalOf((item) => item.soldQuantity),
        icon: LucideIcons.trendingUp,
        color: colorScheme.error,
      ),
      _SummaryCard(
        label: 'reports.stocktake_sale_returned'.tr(),
        value: totalOf((item) => item.saleReturnedQuantity),
        icon: LucideIcons.undo2,
        color: Colors.orange,
      ),
      _SummaryCard(
        label: 'reports.stocktake_purchase_returned'.tr(),
        value: totalOf((item) => item.purchaseReturnedQuantity),
        icon: LucideIcons.redo2,
        color: Colors.deepPurple,
      ),
      _SummaryCard(
        label: 'reports.total_remaining'.tr(),
        value: '${data.totalRemainingQuantity}',
        icon: LucideIcons.package,
        color: colorScheme.tertiary,
      ),
      _SummaryCard(
        label: 'reports.remaining_value'.tr(),
        value: cs.formatCents(data.totalRemainingValueCents),
        icon: LucideIcons.dollarSign,
        color: colorScheme.secondary,
      ),
      _SummaryCard(
        label: 'reports.total_profit'.tr(),
        value: cs.formatCents(data.totalProfitCents),
        icon: LucideIcons.trendingUp,
        color: data.totalProfitCents >= 0 ? Colors.teal : colorScheme.error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        if (isWide) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cards
                .map(
                  (c) => SizedBox(
                    width: (constraints.maxWidth - 24) / 4,
                    child: c,
                  ),
                )
                .toList(),
          );
        }

        // 2 columns layout
        final rows = <Widget>[];
        for (int i = 0; i < cards.length; i += 2) {
          if (i + 1 < cards.length) {
            rows.add(
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: cards[i],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: cards[i + 1],
                    ),
                  ),
                ],
              ),
            );
          } else {
            rows.add(cards[i]);
          }
          if (i + 2 < cards.length) rows.add(const SizedBox(height: 8));
        }
        return Column(children: rows);
      },
    );
  }

  Widget _buildEmptyProducts(BuildContext context) {
    final theme = Theme.of(context);
    return ReportScrollableCenter(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.warehouse,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'reports.no_supplier_stocktake'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.no_supplier_stocktake_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductTable(BuildContext context, CurrencyService cs) {
    final data = widget.data;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 14,
        horizontalMargin: 8,
        columns: [
          const DataColumn(label: Text('#')),
          DataColumn(label: Text('reports.product'.tr())),
          DataColumn(label: Text('reports.variant'.tr())),
          DataColumn(label: Text('reports.purchased'.tr()), numeric: true),
          DataColumn(label: Text('reports.sold'.tr()), numeric: true),
          DataColumn(
            label: Text('reports.stocktake_sale_ret_short'.tr()),
            numeric: true,
          ),
          DataColumn(
            label: Text('reports.stocktake_purch_ret_short'.tr()),
            numeric: true,
          ),
          DataColumn(label: Text('reports.remaining'.tr()), numeric: true),
          DataColumn(label: Text('reports.unit_cost'.tr()), numeric: true),
          DataColumn(
            label: Text('reports.remaining_value'.tr()),
            numeric: true,
          ),
          DataColumn(label: Text('reports.profit'.tr()), numeric: true),
        ],
        rows: data.products.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final item = entry.value;
          return DataRow(
            cells: [
              DataCell(Text('$idx', style: theme.textTheme.bodySmall)),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.productName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.sku != null)
                        Text(
                          item.sku!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      if (item.categoryName != null)
                        Text(
                          item.categoryName!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.tertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              DataCell(
                Text(
                  item.variantLabel.isNotEmpty ? item.variantLabel : '-',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              DataCell(
                Text(
                  localizedQuantity(
                    item.purchasedQuantity,
                    item.measurementType,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataCell(
                Text(
                  localizedQuantity(item.soldQuantity, item.measurementType),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: item.soldQuantity > 0
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataCell(
                Text(
                  localizedQuantity(
                    item.saleReturnedQuantity,
                    item.measurementType,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: item.saleReturnedQuantity > 0
                        ? Colors.orange
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataCell(
                Text(
                  localizedQuantity(
                    item.purchaseReturnedQuantity,
                    item.measurementType,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: item.purchaseReturnedQuantity > 0
                        ? Colors.deepPurple
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataCell(
                Text(
                  localizedQuantity(
                    item.remainingQuantity,
                    item.measurementType,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.tertiary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              DataCell(
                Text(
                  cs.formatCents(item.costCents),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              DataCell(
                Text(
                  cs.formatCents(item.remainingValueCents),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  cs.formatCents(item.profitCents),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: item.profitCents >= 0
                        ? Colors.teal
                        : colorScheme.error,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CATEGORY FILTER CHIP WITH BOTTOM SHEET
// ═══════════════════════════════════════════════════════

class _CategoryFilterChip extends StatelessWidget {
  final String label;
  final String sheetTitle;
  final bool isActive;
  final List<SupplierStocktakeCategoryOption> options;
  final ValueChanged<SupplierStocktakeCategoryOption?> onSelected;

  const _CategoryFilterChip({
    required this.label,
    required this.sheetTitle,
    required this.isActive,
    required this.options,
    required this.onSelected,
  });

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet<SupplierStocktakeCategoryOption?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CategorySearchSheet(
        title: sheetTitle,
        options: options,
        isActive: isActive,
      ),
    ).then((result) {
      if (result != null) {
        if (result.id == -1) {
          onSelected(null);
        } else {
          onSelected(result);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showFilterSheet(context),
      child: Chip(
        avatar: const Icon(LucideIcons.folderOpen, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        backgroundColor: isActive ? colorScheme.primaryContainer : null,
        side: isActive
            ? BorderSide(color: colorScheme.primary.withValues(alpha: 0.5))
            : null,
        visualDensity: VisualDensity.compact,
        deleteIcon: isActive ? const Icon(LucideIcons.x, size: 14) : null,
        onDeleted: isActive ? () => onSelected(null) : null,
      ),
    );
  }
}

class _CategorySearchSheet extends StatefulWidget {
  final String title;
  final List<SupplierStocktakeCategoryOption> options;
  final bool isActive;

  const _CategorySearchSheet({
    required this.title,
    required this.options,
    required this.isActive,
  });

  @override
  State<_CategorySearchSheet> createState() => _CategorySearchSheetState();
}

class _CategorySearchSheetState extends State<_CategorySearchSheet> {
  String _query = '';

  List<SupplierStocktakeCategoryOption> get _filtered {
    if (_query.isEmpty) return widget.options;
    final q = _query.toLowerCase();
    return widget.options
        .where((o) => o.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
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
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.3,
                  ),
                ),
                onChanged: (q) => setState(() => _query = q),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                LucideIcons.layers,
                color: !widget.isActive ? colorScheme.primary : null,
              ),
              title: Text(
                'reports.all'.tr(),
                style: TextStyle(
                  fontWeight: !widget.isActive
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: !widget.isActive ? colorScheme.primary : null,
                ),
              ),
              dense: true,
              onTap: () => Navigator.pop(
                context,
                const SupplierStocktakeCategoryOption(id: -1, name: ''),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'common.no_results'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final opt = filtered[index];
                        return ListTile(
                          title: Text(opt.name),
                          dense: true,
                          onTap: () => Navigator.pop(context, opt),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
