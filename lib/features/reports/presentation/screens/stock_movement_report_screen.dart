import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/stock_movement_pdf_service.dart';
import '../bloc/stock_movement_report_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/report_scrollable_center.dart';

class StockMovementReportScreen extends StatelessWidget {
  const StockMovementReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<StockMovementReportBloc>(),
      child: const _StockMovementReportView(),
    );
  }
}

class _StockMovementReportView extends StatefulWidget {
  const _StockMovementReportView();

  @override
  State<_StockMovementReportView> createState() =>
      _StockMovementReportViewState();
}

class _StockMovementReportViewState extends State<_StockMovementReportView> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.stock_movement_report'.tr()),
        actions: [
          BlocBuilder<
            StockMovementReportBloc,
            RealtimeState<StockMovementReportData>
          >(
            builder: (context, state) {
              if (state is! RealtimeSuccess<StockMovementReportData>) {
                return const SizedBox.shrink();
              }
              if (state.data.selectedProductId == null) {
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
            StockMovementReportBloc,
            RealtimeState<StockMovementReportData>
          >(
            builder: (context, state) {
              if (state is RealtimeLoading<StockMovementReportData>) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is RealtimeError<StockMovementReportData>) {
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
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () =>
                            context.read<StockMovementReportBloc>().refresh(),
                        icon: const Icon(LucideIcons.refreshCw),
                        label: Text('reports.retry'.tr()),
                      ),
                    ],
                  ),
                );
              }

              if (state is RealtimeSuccess<StockMovementReportData>) {
                return Column(
                  children: [
                    // Date range selector
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: DateRangeSelector(
                        dateRange: state.data.dateRange,
                        onChanged: (range) => context
                            .read<StockMovementReportBloc>()
                            .add(StockMovementDateRangeChanged(range)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Search bar
                    _buildSearchBar(context, state.data),

                    // Content
                    Expanded(
                      child: state.data.selectedProductId == null
                          ? _buildEmptyState(context, state.data)
                          : _buildMovementContent(context, state.data),
                    ),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),
    );
  }

  Widget _buildSearchBar(BuildContext context, StockMovementReportData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected product chip or search field
          if (data.selectedProductId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.package,
                    size: 18,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.selectedProductName ?? '',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      context.read<StockMovementReportBloc>().add(
                        const StockMovementProductCleared(),
                      );
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            )
          else
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'reports.search_product_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          context.read<StockMovementReportBloc>().add(
                            const StockMovementSearchChanged(''),
                          );
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) => context.read<StockMovementReportBloc>().add(
                StockMovementSearchChanged(value),
              ),
            ),

          // Search results dropdown
          if (data.searchResults.isNotEmpty && data.selectedProductId == null)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: data.searchResults.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final result = data.searchResults[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      LucideIcons.package,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    title: Text(
                      result.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: result.sku != null
                        ? Text(result.sku!, style: theme.textTheme.bodySmall)
                        : null,
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                      context.read<StockMovementReportBloc>().add(
                        StockMovementProductSelected(result.productId),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, StockMovementReportData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ReportScrollableCenter(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.search,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'reports.search_product_prompt'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.stock_movement_report_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementContent(
    BuildContext context,
    StockMovementReportData data,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();
    final filtered = data.filteredMovements;

    if (data.movements.isEmpty) {
      return ReportScrollableCenter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.packageOpen,
                size: 64,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                'reports.no_movements'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Summary cards
        _buildSummaryCards(context, data.summary, cs),
        const SizedBox(height: 16),

        // Movement type filter chips
        _buildTypeFilter(context, data),
        const SizedBox(height: 16),

        // Movement timeline
        Row(
          children: [
            Text(
              'reports.movement_timeline'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '${filtered.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'reports.no_movements'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ...filtered.map((entry) => _MovementCard(entry: entry, cs: cs)),
      ],
    );
  }

  Widget _buildSummaryCards(
    BuildContext context,
    StockMovementSummary summary,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Row 1: Purchases + Sales
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: LucideIcons.shoppingCart,
                label: 'reports.total_purchased'.tr(),
                value: localizedQuantity(
                  summary.totalPurchased,
                  summary.measurementType,
                ),
                subValue: cs.formatCents(summary.totalPurchaseCents),
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                icon: LucideIcons.receipt,
                label: 'reports.total_sold'.tr(),
                value: localizedQuantity(
                  summary.totalSold,
                  summary.measurementType,
                ),
                subValue: cs.formatCents(summary.totalSalesCents),
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Row 2: Sale Returns (linked) + Sale Returns (unlinked)
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: LucideIcons.undo2,
                label: 'reports.sale_returns_qty'.tr(),
                value: localizedQuantity(
                  summary.totalSaleReturned,
                  summary.measurementType,
                ),
                subValue: cs.formatCents(summary.totalSaleReturnCents),
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                icon: LucideIcons.undo,
                label: 'reports.total_sale_return_adj'.tr(),
                value: localizedQuantity(
                  summary.totalSaleReturnAdj,
                  summary.measurementType,
                ),
                subValue: cs.formatCents(summary.totalSaleReturnAdjCents),
                color: Colors.amber.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Row 3: Purchase Returns (linked) + Purchase Returns (unlinked)
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: LucideIcons.redo2,
                label: 'reports.purchase_returns_qty'.tr(),
                value: localizedQuantity(
                  summary.totalPurchaseReturned,
                  summary.measurementType,
                ),
                subValue: cs.formatCents(summary.totalPurchaseReturnCents),
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SummaryCard(
                icon: LucideIcons.redo,
                label: 'reports.total_purchase_return_adj'.tr(),
                value: localizedQuantity(
                  summary.totalPurchaseReturnAdj,
                  summary.measurementType,
                ),
                subValue: cs.formatCents(summary.totalPurchaseReturnAdjCents),
                color: Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Net movement bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.arrowLeftRight,
                size: 18,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                '${'reports.net_movement'.tr()}: ',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              Text(
                localizedSignedQuantity(
                  summary.netQuantity,
                  summary.measurementType,
                  showPositiveSign: true,
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeFilter(BuildContext context, StockMovementReportData data) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChipItem(
            label: 'reports.filter_all'.tr(),
            selected: data.movementTypeFilter == null,
            onSelected: () => context.read<StockMovementReportBloc>().add(
              const StockMovementTypeFilterChanged(null),
            ),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'reports.filter_purchases'.tr(),
            selected: data.movementTypeFilter == StockMovementType.purchase,
            color: Colors.blue,
            onSelected: () => context.read<StockMovementReportBloc>().add(
              const StockMovementTypeFilterChanged(StockMovementType.purchase),
            ),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'reports.filter_sales'.tr(),
            selected: data.movementTypeFilter == StockMovementType.sale,
            color: Colors.green,
            onSelected: () => context.read<StockMovementReportBloc>().add(
              const StockMovementTypeFilterChanged(StockMovementType.sale),
            ),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'reports.filter_sale_return_linked'.tr(),
            selected: data.movementTypeFilter == StockMovementType.saleReturn,
            color: Colors.orange,
            onSelected: () => context.read<StockMovementReportBloc>().add(
              const StockMovementTypeFilterChanged(
                StockMovementType.saleReturn,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'reports.filter_sale_return_adjustment'.tr(),
            selected:
                data.movementTypeFilter ==
                StockMovementType.saleReturnAdjustment,
            color: Colors.amber.shade700,
            onSelected: () => context.read<StockMovementReportBloc>().add(
              const StockMovementTypeFilterChanged(
                StockMovementType.saleReturnAdjustment,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'reports.filter_purchase_return_linked'.tr(),
            selected:
                data.movementTypeFilter == StockMovementType.purchaseReturn,
            color: Colors.red,
            onSelected: () => context.read<StockMovementReportBloc>().add(
              const StockMovementTypeFilterChanged(
                StockMovementType.purchaseReturn,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _FilterChipItem(
            label: 'reports.filter_purchase_return_adjustment'.tr(),
            selected:
                data.movementTypeFilter ==
                StockMovementType.purchaseReturnAdjustment,
            color: Colors.purple,
            onSelected: () => context.read<StockMovementReportBloc>().add(
              const StockMovementTypeFilterChanged(
                StockMovementType.purchaseReturnAdjustment,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printReport(
    BuildContext context,
    StockMovementReportData data,
  ) async {
    await StockMovementPdfService.printReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_stock_movement_report',
    );
  }

  Future<void> _shareReport(
    BuildContext context,
    StockMovementReportData data,
  ) async {
    await StockMovementPdfService.shareReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_stock_movement_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// FILTER CHIP
// ═══════════════════════════════════════════════════════

class _FilterChipItem extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onSelected;

  const _FilterChipItem({
    required this.label,
    required this.selected,
    this.color,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.primary;

    return FilterChip(
      label: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: selected ? Colors.white : effectiveColor,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      selected: selected,
      selectedColor: effectiveColor,
      backgroundColor: effectiveColor.withValues(alpha: 0.08),
      side: BorderSide(
        color: selected
            ? effectiveColor
            : effectiveColor.withValues(alpha: 0.3),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUMMARY CARD
// ═══════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subValue;
  final Color color;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
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
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subValue,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// MOVEMENT CARD (TIMELINE STYLE)
// ═══════════════════════════════════════════════════════

class _MovementCard extends StatelessWidget {
  final StockMovementEntry entry;
  final CurrencyService cs;

  const _MovementCard({required this.entry, required this.cs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, color, typeLabel, sign) = _movementMeta(entry.type);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          typeLabel.tr(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('dd/MM/yyyy').format(entry.date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.fileText,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entry.reference,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (entry.counterpartyName != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          _isSupplierRelated(entry.type)
                              ? LucideIcons.truck
                              : LucideIcons.user,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            entry.counterpartyName!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Quantity badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$sign${localizedQuantity(entry.quantity, entry.measurementType)}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        cs.formatCents(entry.totalCents),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSupplierRelated(StockMovementType type) {
    return type == StockMovementType.purchase ||
        type == StockMovementType.purchaseReturn ||
        type == StockMovementType.purchaseReturnAdjustment;
  }

  (IconData, Color, String, String) _movementMeta(StockMovementType type) {
    switch (type) {
      case StockMovementType.purchase:
        return (
          LucideIcons.shoppingCart,
          Colors.blue,
          'reports.movement_purchase',
          '+',
        );
      case StockMovementType.sale:
        return (
          LucideIcons.receipt,
          Colors.green,
          'reports.movement_sale',
          '-',
        );
      case StockMovementType.saleReturn:
        return (
          LucideIcons.undo2,
          Colors.orange,
          'reports.movement_sale_return',
          '+',
        );
      case StockMovementType.saleReturnAdjustment:
        return (
          LucideIcons.undo,
          Colors.amber.shade700,
          'reports.movement_sale_return_adjustment',
          '+',
        );
      case StockMovementType.purchaseReturn:
        return (
          LucideIcons.redo2,
          Colors.red,
          'reports.movement_purchase_return',
          '-',
        );
      case StockMovementType.purchaseReturnAdjustment:
        return (
          LucideIcons.redo,
          Colors.purple,
          'reports.movement_purchase_return_adjustment',
          '-',
        );
    }
  }
}
