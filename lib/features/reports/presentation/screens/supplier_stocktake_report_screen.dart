import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/supplier_stocktake_pdf_service.dart';
import '../bloc/supplier_stocktake_report_bloc.dart';
import '../widgets/date_range_selector.dart';

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
          BlocBuilder<SupplierStocktakeReportBloc,
              RealtimeState<SupplierStocktakeReportData>>(
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
      body: BlocBuilder<SupplierStocktakeReportBloc,
          RealtimeState<SupplierStocktakeReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<SupplierStocktakeReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<SupplierStocktakeReportData>) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.error.toString(),
                      style: theme.textTheme.bodyLarge),
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
                    onChanged: (range) => context
                        .read<SupplierStocktakeReportBloc>()
                        .add(SupplierStocktakeReportDateRangeChanged(range)),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.search,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('reports.select_supplier_prompt'.tr(),
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text('reports.select_supplier_stocktake_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, SupplierStocktakeReportData data) async {
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
      BuildContext context, SupplierStocktakeReportData data) async {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return DropdownButtonFormField<int>(
      // ignore: deprecated_member_use
      value: selectedId,
      decoration: InputDecoration(
        labelText: 'reports.select_supplier'.tr(),
        prefixIcon: Icon(LucideIcons.truck, color: colorScheme.primary),
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      isExpanded: true,
      items: suppliers.map((s) {
        return DropdownMenuItem<int>(
          value: s.id,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                cs.formatCents(s.balanceCents),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: s.balanceCents > 0
                      ? colorScheme.error
                      : colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) => onChanged(value),
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

class _StocktakeContent extends StatelessWidget {
  final SupplierStocktakeReportData data;
  const _StocktakeContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary cards
        _buildSummaryCards(context, data, cs),
        const SizedBox(height: 12),

        // Sort selector
        _buildSortSelector(context, data),
        const SizedBox(height: 12),

        // Products header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('reports.stocktake_items'.tr(),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              'reports.stocktake_products'.tr(
                  args: ['${data.totalProducts}']),
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
      BuildContext context, SupplierStocktakeReportData data, CurrencyService cs) {
    final colorScheme = Theme.of(context).colorScheme;

    final cards = [
      _SummaryCard(
        label: 'reports.total_purchased'.tr(),
        value: '${data.totalPurchasedQuantity}',
        icon: LucideIcons.shoppingCart,
        color: colorScheme.primary,
      ),
      _SummaryCard(
        label: 'reports.total_sold'.tr(),
        value: '${data.totalSoldQuantity}',
        icon: LucideIcons.trendingUp,
        color: colorScheme.error,
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
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        if (isWide) {
          return Row(
            children: cards
                .map((c) => Expanded(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: c,
                    )))
                .toList(),
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: cards[0],
                )),
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: cards[1],
                )),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: cards[2],
                )),
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: cards[3],
                )),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSortSelector(
      BuildContext context, SupplierStocktakeReportData data) {
    final theme = Theme.of(context);

    return Row(
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
                  selected:
                      data.sort == SupplierStocktakeSortType.valueDesc ||
                          data.sort == SupplierStocktakeSortType.valueAsc,
                  onTap: () {
                    final next =
                        data.sort == SupplierStocktakeSortType.valueDesc
                            ? SupplierStocktakeSortType.valueAsc
                            : SupplierStocktakeSortType.valueDesc;
                    context
                        .read<SupplierStocktakeReportBloc>()
                        .add(SupplierStocktakeReportSortChanged(next));
                  },
                  ascending:
                      data.sort == SupplierStocktakeSortType.valueAsc,
                ),
                _SortChip(
                  label: 'reports.sort_name'.tr(),
                  selected:
                      data.sort == SupplierStocktakeSortType.nameAsc ||
                          data.sort == SupplierStocktakeSortType.nameDesc,
                  onTap: () {
                    final next =
                        data.sort == SupplierStocktakeSortType.nameAsc
                            ? SupplierStocktakeSortType.nameDesc
                            : SupplierStocktakeSortType.nameAsc;
                    context
                        .read<SupplierStocktakeReportBloc>()
                        .add(SupplierStocktakeReportSortChanged(next));
                  },
                  ascending:
                      data.sort == SupplierStocktakeSortType.nameAsc,
                ),
                _SortChip(
                  label: 'reports.sort_remaining'.tr(),
                  selected:
                      data.sort == SupplierStocktakeSortType.stockDesc ||
                          data.sort == SupplierStocktakeSortType.stockAsc,
                  onTap: () {
                    final next =
                        data.sort == SupplierStocktakeSortType.stockDesc
                            ? SupplierStocktakeSortType.stockAsc
                            : SupplierStocktakeSortType.stockDesc;
                    context
                        .read<SupplierStocktakeReportBloc>()
                        .add(SupplierStocktakeReportSortChanged(next));
                  },
                  ascending:
                      data.sort == SupplierStocktakeSortType.stockAsc,
                ),
                _SortChip(
                  label: 'reports.sort_sold'.tr(),
                  selected:
                      data.sort == SupplierStocktakeSortType.soldDesc,
                  onTap: () {
                    context.read<SupplierStocktakeReportBloc>().add(
                        const SupplierStocktakeReportSortChanged(
                            SupplierStocktakeSortType.soldDesc));
                  },
                ),
                _SortChip(
                  label: 'reports.sort_purchased'.tr(),
                  selected:
                      data.sort == SupplierStocktakeSortType.purchasedDesc,
                  onTap: () {
                    context.read<SupplierStocktakeReportBloc>().add(
                        const SupplierStocktakeReportSortChanged(
                            SupplierStocktakeSortType.purchasedDesc));
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyProducts(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.warehouse,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('reports.no_supplier_stocktake'.tr(),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('reports.no_supplier_stocktake_desc'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildProductTable(BuildContext context, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        horizontalMargin: 8,
        columns: [
          const DataColumn(label: Text('#')),
          DataColumn(label: Text('reports.product'.tr())),
          DataColumn(label: Text('reports.variant'.tr())),
          DataColumn(
            label: Text('reports.purchased'.tr()),
            numeric: true,
          ),
          DataColumn(
            label: Text('reports.sold'.tr()),
            numeric: true,
          ),
          DataColumn(
            label: Text('reports.remaining'.tr()),
            numeric: true,
          ),
          DataColumn(
            label: Text('reports.unit_cost'.tr()),
            numeric: true,
          ),
          DataColumn(
            label: Text('reports.remaining_value'.tr()),
            numeric: true,
          ),
        ],
        rows: data.products.asMap().entries.map((entry) {
          final idx = entry.key + 1;
          final item = entry.value;
          return DataRow(cells: [
            DataCell(Text('$idx',
                style: theme.textTheme.bodySmall)),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.productName,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w500),
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
                  ],
                ),
              ),
            ),
            DataCell(Text(
              item.variantLabel.isNotEmpty ? item.variantLabel : '-',
              style: theme.textTheme.bodySmall,
            )),
            DataCell(Text(
              '${item.purchasedQuantity}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            )),
            DataCell(Text(
              '${item.soldQuantity}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: item.soldQuantity > 0
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            )),
            DataCell(Text(
              '${item.remainingQuantity}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.tertiary,
                fontWeight: FontWeight.bold,
              ),
            )),
            DataCell(Text(
              cs.formatCents(item.costCents),
              style: theme.textTheme.bodySmall,
            )),
            DataCell(Text(
              cs.formatCents(item.remainingValueCents),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            )),
          ]);
        }).toList(),
      ),
    );
  }
}
