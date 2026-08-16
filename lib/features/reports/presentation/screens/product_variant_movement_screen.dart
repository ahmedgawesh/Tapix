import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/product_variant_movement_pdf_service.dart';
import '../bloc/product_variant_movement_bloc.dart';
import '../widgets/date_range_selector.dart';

class ProductVariantMovementScreen extends StatelessWidget {
  const ProductVariantMovementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ProductVariantMovementBloc>(),
      child: const _VariantMovementView(),
    );
  }
}

class _VariantMovementView extends StatefulWidget {
  const _VariantMovementView();

  @override
  State<_VariantMovementView> createState() => _VariantMovementViewState();
}

class _VariantMovementViewState extends State<_VariantMovementView> {
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
        title: Text('reports.variant_movement_report'.tr()),
        actions: [
          BlocBuilder<
            ProductVariantMovementBloc,
            RealtimeState<ProductVariantMovementData>
          >(
            builder: (context, state) {
              if (state is! RealtimeSuccess<ProductVariantMovementData>) {
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
            ProductVariantMovementBloc,
            RealtimeState<ProductVariantMovementData>
          >(
            builder: (context, state) {
              if (state is RealtimeLoading<ProductVariantMovementData>) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is RealtimeError<ProductVariantMovementData>) {
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
                        onPressed: () => context
                            .read<ProductVariantMovementBloc>()
                            .refresh(),
                        icon: const Icon(LucideIcons.refreshCw),
                        label: Text('reports.retry'.tr()),
                      ),
                    ],
                  ),
                );
              }

              if (state is RealtimeSuccess<ProductVariantMovementData>) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: DateRangeSelector(
                        dateRange: state.data.dateRange,
                        onChanged: (range) => context
                            .read<ProductVariantMovementBloc>()
                            .add(VariantMovementDateRangeChanged(range)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSearchBar(context, state.data),
                    Expanded(
                      child: state.data.selectedProductId == null
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

  // ═══════════════════════════════════════════════════════
  // SEARCH BAR
  // ═══════════════════════════════════════════════════════

  Widget _buildSearchBar(
    BuildContext context,
    ProductVariantMovementData data,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.selectedProductId != null)
            _buildSelectedProductChip(context, data, theme, colorScheme)
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
                          context.read<ProductVariantMovementBloc>().add(
                            const VariantMovementSearchChanged(''),
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
              onChanged: (value) => context
                  .read<ProductVariantMovementBloc>()
                  .add(VariantMovementSearchChanged(value)),
            ),

          // Search results dropdown
          if (data.searchResults.isNotEmpty && data.selectedProductId == null)
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
                  final result = data.searchResults[index];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      result.hasVariants
                          ? LucideIcons.layers
                          : LucideIcons.package,
                      size: 20,
                      color: result.hasVariants
                          ? colorScheme.tertiary
                          : colorScheme.primary,
                    ),
                    title: Text(
                      result.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        if (result.sku != null) ...[
                          Text(result.sku!, style: theme.textTheme.bodySmall),
                          const SizedBox(width: 8),
                        ],
                        if (result.categoryName != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              result.categoryName!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        if (result.hasVariants) ...[
                          const SizedBox(width: 6),
                          Icon(
                            LucideIcons.layers,
                            size: 12,
                            color: colorScheme.tertiary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'reports.has_variants_label'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                      context.read<ProductVariantMovementBloc>().add(
                        VariantMovementProductSelected(result.productId),
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

  Widget _buildSelectedProductChip(
    BuildContext context,
    ProductVariantMovementData data,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            data.selectedProductHasVariants
                ? LucideIcons.layers
                : LucideIcons.package,
            size: 18,
            color: colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.selectedProductName ?? '',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (data.selectedProductCategory != null ||
                    data.selectedProductHasVariants)
                  Row(
                    children: [
                      if (data.selectedProductCategory != null) ...[
                        Icon(
                          LucideIcons.tag,
                          size: 12,
                          color: colorScheme.onPrimaryContainer.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          data.selectedProductCategory!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                      if (data.selectedProductCategory != null &&
                          data.selectedProductHasVariants)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '•',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ),
                      if (data.selectedProductHasVariants)
                        Text(
                          'reports.has_variants_label'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onPrimaryContainer.withValues(
                              alpha: 0.7,
                            ),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
              ],
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
              context.read<ProductVariantMovementBloc>().add(
                const VariantMovementProductCleared(),
              );
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════════════════════

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.layers,
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
              'reports.variant_movement_prompt_desc'.tr(),
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

  // ═══════════════════════════════════════════════════════
  // MAIN CONTENT
  // ═══════════════════════════════════════════════════════

  Widget _buildContent(BuildContext context, ProductVariantMovementData data) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.movements.isEmpty) {
      return Center(
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
        // Grand totals
        _buildTotalsSection(context, data.totals, cs),
        const SizedBox(height: 16),

        // Group-by selector (only for products with variants)
        if (data.selectedProductHasVariants) ...[
          _buildGroupBySelector(context, data.groupBy),
          const SizedBox(height: 12),

          // Variant breakdown cards
          Text(
            'reports.variant_breakdown'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...data.variantSummaries.map(
            (s) => _VariantBreakdownCard(summary: s, cs: cs),
          ),
          const SizedBox(height: 16),
        ],

        // Movement timeline
        Text(
          'reports.movement_timeline'.tr(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...data.movements.map(
          (entry) => _VariantMovementCard(
            entry: entry,
            cs: cs,
            showVariant: data.selectedProductHasVariants,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // TOTALS SECTION
  // ═══════════════════════════════════════════════════════

  Widget _buildTotalsSection(
    BuildContext context,
    VariantMovementTotals totals,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _TotalCard(
                icon: LucideIcons.shoppingCart,
                label: 'reports.total_purchased'.tr(),
                value: localizedQuantity(
                  totals.totalPurchased,
                  totals.measurementType,
                ),
                subValue: cs.formatCents(totals.totalPurchaseCents),
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TotalCard(
                icon: LucideIcons.receipt,
                label: 'reports.total_sold'.tr(),
                value: localizedQuantity(
                  totals.totalSold,
                  totals.measurementType,
                ),
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
                value: localizedQuantity(
                  totals.totalSaleReturned,
                  totals.measurementType,
                ),
                subValue: cs.formatCents(totals.totalSaleReturnCents),
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TotalCard(
                icon: LucideIcons.redo2,
                label: 'reports.purchase_returns_qty'.tr(),
                value: localizedQuantity(
                  totals.totalPurchaseReturned,
                  totals.measurementType,
                ),
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
                localizedSignedQuantity(
                  totals.netQuantity,
                  totals.measurementType,
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

  // ═══════════════════════════════════════════════════════
  // GROUP-BY SELECTOR
  // ═══════════════════════════════════════════════════════

  Widget _buildGroupBySelector(BuildContext context, VariantGroupBy current) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'reports.group_by'.tr(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _GroupChip(
                label: 'reports.group_variant'.tr(),
                icon: LucideIcons.layers,
                isSelected: current == VariantGroupBy.variant,
                onTap: () => context.read<ProductVariantMovementBloc>().add(
                  const VariantMovementGroupByChanged(VariantGroupBy.variant),
                ),
              ),
              const SizedBox(width: 6),
              _GroupChip(
                label: 'reports.group_color'.tr(),
                icon: LucideIcons.palette,
                isSelected: current == VariantGroupBy.color,
                onTap: () => context.read<ProductVariantMovementBloc>().add(
                  const VariantMovementGroupByChanged(VariantGroupBy.color),
                ),
              ),
              const SizedBox(width: 6),
              _GroupChip(
                label: 'reports.group_size'.tr(),
                icon: LucideIcons.ruler,
                isSelected: current == VariantGroupBy.size,
                onTap: () => context.read<ProductVariantMovementBloc>().add(
                  const VariantMovementGroupByChanged(VariantGroupBy.size),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // PRINT / SHARE
  // ═══════════════════════════════════════════════════════

  Future<void> _printReport(
    BuildContext context,
    ProductVariantMovementData data,
  ) async {
    await ProductVariantMovementPdfService.printReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_variant_movement',
    );
  }

  Future<void> _shareReport(
    BuildContext context,
    ProductVariantMovementData data,
  ) async {
    await ProductVariantMovementPdfService.shareReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_variant_movement',
    );
  }
}

// ═══════════════════════════════════════════════════════
// GROUP CHIP
// ═══════════════════════════════════════════════════════

class _GroupChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _GroupChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
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

// ═══════════════════════════════════════════════════════
// TOTAL CARD
// ═══════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════
// VARIANT BREAKDOWN CARD
// ═══════════════════════════════════════════════════════

class _VariantBreakdownCard extends StatelessWidget {
  final VariantSummaryItem summary;
  final CurrencyService cs;

  const _VariantBreakdownCard({required this.summary, required this.cs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color? swatchColor;
    if (summary.colorHex != null && summary.colorHex!.isNotEmpty) {
      try {
        final hex = summary.colorHex!.replaceFirst('#', '');
        swatchColor = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {
        // ignore invalid hex
      }
    }

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
            // Header row with variant label + color swatch
            Row(
              children: [
                if (swatchColor != null) ...[
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: swatchColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    summary.label,
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

            // Movement bars
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
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// MINI STAT (inside breakdown card)
// ═══════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════
// VARIANT MOVEMENT CARD (TIMELINE STYLE)
// ═══════════════════════════════════════════════════════

class _VariantMovementCard extends StatelessWidget {
  final VariantMovementEntry entry;
  final CurrencyService cs;
  final bool showVariant;

  const _VariantMovementCard({
    required this.entry,
    required this.cs,
    this.showVariant = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, color, typeLabel, sign) = _movementMeta(entry.type);

    Color? swatchColor;
    if (entry.colorHex != null && entry.colorHex!.isNotEmpty) {
      try {
        final hex = entry.colorHex!.replaceFirst('#', '');
        swatchColor = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {
        // ignore
      }
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
                  // Type badge + date
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
                        DateFormat.yMMMd().format(entry.date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Reference
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

                  // Counterparty
                  if (entry.counterpartyName != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          entry.type == VariantMovementType.purchase ||
                                  entry.type ==
                                      VariantMovementType.purchaseReturn
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

                  // Variant info (color swatch + size)
                  if (showVariant && entry.variantLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (swatchColor != null) ...[
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: swatchColor,
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

                  // Quantity + amount
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

  (IconData, Color, String, String) _movementMeta(VariantMovementType type) {
    switch (type) {
      case VariantMovementType.purchase:
        return (
          LucideIcons.shoppingCart,
          Colors.blue,
          'reports.movement_purchase',
          '+',
        );
      case VariantMovementType.sale:
        return (
          LucideIcons.receipt,
          Colors.green,
          'reports.movement_sale',
          '-',
        );
      case VariantMovementType.saleReturn:
        return (
          LucideIcons.undo2,
          Colors.orange,
          'reports.movement_sale_return',
          '+',
        );
      case VariantMovementType.purchaseReturn:
        return (
          LucideIcons.redo2,
          Colors.red,
          'reports.movement_purchase_return',
          '-',
        );
    }
  }
}
