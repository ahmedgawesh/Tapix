import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/category_movement_pdf_service.dart';
import '../bloc/category_movement_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/report_scrollable_center.dart';

class CategoryMovementScreen extends StatelessWidget {
  const CategoryMovementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CategoryMovementBloc>(),
      child: const _CategoryMovementView(),
    );
  }
}

class _CategoryMovementView extends StatefulWidget {
  const _CategoryMovementView();
  @override
  State<_CategoryMovementView> createState() => _CategoryMovementViewState();
}

class _CategoryMovementViewState extends State<_CategoryMovementView> {
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
        title: Text('reports.category_movement_report'.tr()),
        actions: [
          BlocBuilder<
            CategoryMovementBloc,
            RealtimeState<CategoryMovementData>
          >(
            builder: (context, state) {
              if (state is! RealtimeSuccess<CategoryMovementData>) {
                return const SizedBox.shrink();
              }
              if (state.data.selectedCategoryId == null) {
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
            CategoryMovementBloc,
            RealtimeState<CategoryMovementData>
          >(
            builder: (context, state) {
              if (state is RealtimeLoading<CategoryMovementData>) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is RealtimeError<CategoryMovementData>) {
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
                            context.read<CategoryMovementBloc>().refresh(),
                        icon: const Icon(LucideIcons.refreshCw),
                        label: Text('reports.retry'.tr()),
                      ),
                    ],
                  ),
                );
              }
              if (state is RealtimeSuccess<CategoryMovementData>) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: DateRangeSelector(
                        dateRange: state.data.dateRange,
                        onChanged: (range) => context
                            .read<CategoryMovementBloc>()
                            .add(CategoryMovementDateRangeChanged(range)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSearchBar(context, state.data),
                    Expanded(
                      child: state.data.selectedCategoryId == null
                          ? _buildEmptyState(context)
                          : _buildContent(context, state.data),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
    );
  }

  Widget _buildSearchBar(BuildContext context, CategoryMovementData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.selectedCategoryId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.folderOpen,
                    size: 20,
                    color: colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.selectedCategoryName ?? '',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (data.totals.productCount > 0)
                          Text(
                            '${data.totals.productCount} ${'reports.active_products'.tr()}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onTertiaryContainer.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: colorScheme.onTertiaryContainer,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      context.read<CategoryMovementBloc>().add(
                        const CategoryMovementCategoryCleared(),
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
                hintText: 'reports.search_category_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          context.read<CategoryMovementBloc>().add(
                            const CategoryMovementSearchChanged(''),
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
              onChanged: (v) => context.read<CategoryMovementBloc>().add(
                CategoryMovementSearchChanged(v),
              ),
            ),
          if (data.searchResults.isNotEmpty && data.selectedCategoryId == null)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 240),
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
                  final r = data.searchResults[index];
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        LucideIcons.folderOpen,
                        size: 18,
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                    title: Text(
                      r.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${r.productCount} ${'reports.products_count'.tr()}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                      context.read<CategoryMovementBloc>().add(
                        CategoryMovementCategorySelected(r.categoryId),
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

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ReportScrollableCenter(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.folderSearch,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'reports.search_category_prompt'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.search_category_prompt_desc'.tr(),
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

  Widget _buildContent(BuildContext context, CategoryMovementData data) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();
    if (data.productSummaries.isEmpty && data.movements.isEmpty) {
      return ReportScrollableCenter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.packageOpen,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'reports.no_movements'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
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
        _buildTotalsSection(context, data.totals, cs),
        const SizedBox(height: 16),
        _buildSortSelector(context, data.sort),
        const SizedBox(height: 12),
        Text(
          'reports.products_in_category'.tr(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...data.productSummaries.map(
          (ps) => _ProductBreakdownCard(summary: ps, cs: cs),
        ),
        const SizedBox(height: 16),
        Text(
          'reports.movement_timeline'.tr(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...data.movements.map((e) => _CatMovementCard(entry: e, cs: cs)),
      ],
    );
  }

  Widget _buildTotalsSection(
    BuildContext context,
    CategoryMovementTotals totals,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final measurementType = totals.measurementType;
    String quantityText(int quantity, {bool signed = false}) =>
        measurementType == null
        ? 'measurement.mixed_units'.tr()
        : localizedSignedQuantity(
            quantity,
            measurementType,
            showPositiveSign: signed,
          );
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TotalCard(
                icon: LucideIcons.shoppingCart,
                label: 'reports.total_purchased'.tr(),
                value: quantityText(totals.totalPurchased),
                subValue: cs.formatCents(totals.totalPurchaseCents),
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TotalCard(
                icon: LucideIcons.receipt,
                label: 'reports.total_sold'.tr(),
                value: quantityText(totals.totalSold),
                subValue: cs.formatCents(totals.totalSalesCents),
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _TotalCard(
                icon: LucideIcons.undo2,
                label: 'reports.sale_returns_qty'.tr(),
                value: quantityText(totals.totalSaleReturned),
                subValue: cs.formatCents(totals.totalSaleReturnCents),
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TotalCard(
                icon: LucideIcons.redo2,
                label: 'reports.purchase_returns_qty'.tr(),
                value: quantityText(totals.totalPurchaseReturned),
                subValue: cs.formatCents(totals.totalPurchaseReturnCents),
                color: Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                quantityText(totals.netQuantity, signed: true),
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

  Widget _buildSortSelector(
    BuildContext context,
    CategoryMovementSort current,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'reports.sort_products'.tr(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _SortChip(
                label: 'reports.sort_most_active'.tr(),
                icon: LucideIcons.trendingUp,
                isSelected: current == CategoryMovementSort.mostActive,
                onTap: () => context.read<CategoryMovementBloc>().add(
                  const CategoryMovementSortChanged(
                    CategoryMovementSort.mostActive,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _SortChip(
                label: 'reports.sort_by_name'.tr(),
                icon: LucideIcons.arrowDownAZ,
                isSelected: current == CategoryMovementSort.name,
                onTap: () => context.read<CategoryMovementBloc>().add(
                  const CategoryMovementSortChanged(CategoryMovementSort.name),
                ),
              ),
              const SizedBox(width: 6),
              _SortChip(
                label: 'reports.sort_net_movement'.tr(),
                icon: LucideIcons.arrowLeftRight,
                isSelected: current == CategoryMovementSort.netMovement,
                onTap: () => context.read<CategoryMovementBloc>().add(
                  const CategoryMovementSortChanged(
                    CategoryMovementSort.netMovement,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _printReport(
    BuildContext context,
    CategoryMovementData data,
  ) async {
    await CategoryMovementPdfService.printReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_category_movement',
    );
  }

  Future<void> _shareReport(
    BuildContext context,
    CategoryMovementData data,
  ) async {
    await CategoryMovementPdfService.shareReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_category_movement',
    );
  }
}

// ═══════════════════════════════════════════════════════
class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  const _SortChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
    );
  }
}

class _TotalCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subValue;
  final Color color;
  const _TotalCard({
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

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String amount;
  const _MiniStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.amount,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            amount,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ProductBreakdownCard extends StatelessWidget {
  final CategoryProductSummary summary;
  final CurrencyService cs;
  const _ProductBreakdownCard({required this.summary, required this.cs});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  summary.hasVariants
                      ? LucideIcons.layers
                      : LucideIcons.package,
                  size: 18,
                  color: summary.hasVariants
                      ? colorScheme.tertiary
                      : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary.productName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: summary.netQty >= 0
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${'reports.net_movement'.tr()}: '
                    '${localizedSignedQuantity(summary.netQty, summary.measurementType, showPositiveSign: true)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: summary.netQty >= 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _MiniStat(
                  icon: LucideIcons.shoppingCart,
                  color: Colors.blue,
                  label: localizedSignedQuantity(
                    summary.purchasedQty,
                    summary.measurementType,
                    showPositiveSign: true,
                  ),
                  amount: cs.formatCents(summary.purchaseCents),
                ),
                const SizedBox(width: 12),
                _MiniStat(
                  icon: LucideIcons.receipt,
                  color: Colors.green,
                  label: localizedSignedQuantity(
                    -summary.soldQty,
                    summary.measurementType,
                  ),
                  amount: cs.formatCents(summary.salesCents),
                ),
                const SizedBox(width: 12),
                _MiniStat(
                  icon: LucideIcons.undo2,
                  color: Colors.orange,
                  label: localizedSignedQuantity(
                    summary.saleReturnedQty,
                    summary.measurementType,
                    showPositiveSign: true,
                  ),
                  amount: cs.formatCents(summary.saleReturnCents),
                ),
                const SizedBox(width: 12),
                _MiniStat(
                  icon: LucideIcons.redo2,
                  color: Colors.red,
                  label: localizedSignedQuantity(
                    -summary.purchaseReturnedQty,
                    summary.measurementType,
                  ),
                  amount: cs.formatCents(summary.purchaseReturnCents),
                ),
              ],
            ),
            if (summary.hasVariants && summary.variants.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...summary.variants.map((v) => _buildVariantRow(context, v)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVariantRow(BuildContext context, CatVariantSummary variant) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    Color? swatch;
    if (variant.colorHex != null && variant.colorHex!.isNotEmpty) {
      try {
        swatch = Color(
          int.parse('FF${variant.colorHex!.replaceFirst('#', '')}', radix: 16),
        );
      } catch (_) {}
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (swatch != null) ...[
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            flex: 3,
            child: Text(
              variant.label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _VBadge(
            label: localizedSignedQuantity(
              variant.purchasedQty,
              variant.measurementType,
              showPositiveSign: true,
            ),
            color: Colors.blue,
          ),
          const SizedBox(width: 4),
          _VBadge(
            label: localizedSignedQuantity(
              -variant.soldQty,
              variant.measurementType,
            ),
            color: Colors.green,
          ),
          const SizedBox(width: 4),
          _VBadge(
            label: localizedSignedQuantity(
              variant.saleReturnedQty,
              variant.measurementType,
              showPositiveSign: true,
            ),
            color: Colors.orange,
          ),
          const SizedBox(width: 4),
          _VBadge(
            label: localizedSignedQuantity(
              -variant.purchaseReturnedQty,
              variant.measurementType,
            ),
            color: Colors.red,
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: variant.netQty >= 0
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              localizedSignedQuantity(
                variant.netQty,
                variant.measurementType,
                showPositiveSign: true,
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: variant.netQty >= 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _VBadge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _CatMovementCard extends StatelessWidget {
  final CatMovementEntry entry;
  final CurrencyService cs;
  const _CatMovementCard({required this.entry, required this.cs});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (icon, color, typeLabel, sign) = _meta(entry.type);
    Color? swatch;
    if (entry.colorHex != null && entry.colorHex!.isNotEmpty) {
      try {
        swatch = Color(
          int.parse('FF${entry.colorHex!.replaceFirst('#', '')}', radix: 16),
        );
      } catch (_) {}
    }
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
                  const SizedBox(height: 4),
                  Text(
                    entry.productName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
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
                          style: theme.textTheme.bodySmall?.copyWith(
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
                          entry.type == CatMovementType.purchase ||
                                  entry.type == CatMovementType.purchaseReturn
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
                  if (entry.variantLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (swatch != null) ...[
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: swatch,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                                width: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Icon(
                          LucideIcons.layers,
                          size: 13,
                          color: colorScheme.tertiary,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            entry.variantLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.tertiary,
                              fontWeight: FontWeight.w500,
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

  (IconData, Color, String, String) _meta(CatMovementType type) {
    switch (type) {
      case CatMovementType.purchase:
        return (
          LucideIcons.shoppingCart,
          Colors.blue,
          'reports.movement_purchase',
          '+',
        );
      case CatMovementType.sale:
        return (
          LucideIcons.receipt,
          Colors.green,
          'reports.movement_sale',
          '-',
        );
      case CatMovementType.saleReturn:
        return (
          LucideIcons.undo2,
          Colors.orange,
          'reports.movement_sale_return',
          '+',
        );
      case CatMovementType.purchaseReturn:
        return (
          LucideIcons.redo2,
          Colors.red,
          'reports.movement_purchase_return',
          '-',
        );
    }
  }
}
