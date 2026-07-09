import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/sale_entity.dart';
import '../bloc/sales_bloc.dart';
import '../../../shared/widgets/date_range_filter_sheet.dart';

class SaleListScreen extends StatelessWidget {
  const SaleListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<SalesBloc>(),
      child: const _SaleHubView(),
    );
  }
}

class _SaleHubView extends StatefulWidget {
  const _SaleHubView();

  @override
  State<_SaleHubView> createState() => _SaleHubViewState();
}

class _SaleHubViewState extends State<_SaleHubView> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  String? _selectedStatus;
  DateTimeRange? _dateRange;
  String? _datePresetLabel;

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        context.read<SalesBloc>().add(SalesSearchRequested(value));
      }
    });
    setState(() {});
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text('sales.title'.tr()),
        actions: [
          Tooltip(
            message: 'sales.returns'.tr(),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => context.push('/sales/returns'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.undo2, size: 22),
                    const SizedBox(height: 2),
                    Text(
                      'sales.returns'.tr(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'settings.title'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<SalesBloc, RealtimeState<SalesHubData>>(
          builder: (context, state) {
            if (state is RealtimeLoading<SalesHubData> &&
                state.previousData == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is RealtimeError<SalesHubData> &&
                state.previousData == null) {
              return _buildErrorState(context, state);
            }

            SalesHubData? data;
            if (state is RealtimeSuccess<SalesHubData>) {
              data = state.data;
            } else if (state is RealtimeLoading<SalesHubData>) {
              data = state.previousData;
            } else if (state is RealtimeError<SalesHubData>) {
              data = state.previousData;
            }

            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }

            return _buildContent(context, data);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/sales/new'),
        icon: const Icon(LucideIcons.plus),
        label: Text('sales.new'.tr()),
        elevation: 2,
      ),
    );
  }

  Widget _buildErrorState(
      BuildContext context, RealtimeError<SalesHubData> state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.alertCircle,
              size: 64, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text('common.error'.tr(),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => context.read<SalesBloc>().refresh(),
            icon: const Icon(LucideIcons.rotateCcw),
            label: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SalesHubData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = sl<CurrencyService>();

    return RefreshIndicator(
      onRefresh: () async => context.read<SalesBloc>().refresh(),
      child: CustomScrollView(
        slivers: [
          // ─── Dashboard Stats ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 700;
                  final cards = [
                    _StatCard(
                      icon: LucideIcons.receipt,
                      iconColor: colorScheme.primary,
                      gradientColors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.7)],
                      label: 'sales.total_revenue'.tr(),
                      value: currencyService.format(data.stats.totalSalesCents),
                    ),
                    _StatCard(
                      icon: LucideIcons.trendingUp,
                      iconColor: Colors.green,
                      gradientColors: [Colors.green, Colors.green.shade300],
                      label: 'sales.today_sales'.tr(),
                      value: currencyService.format(data.stats.todaySalesCents),
                    ),
                    _StatCard(
                      icon: LucideIcons.checkCircle,
                      iconColor: colorScheme.tertiary,
                      gradientColors: [colorScheme.tertiary, colorScheme.tertiary.withValues(alpha: 0.7)],
                      label: 'sales.completed'.tr(),
                      value: '${data.stats.completedCount}',
                    ),
                    _StatCard(
                      icon: LucideIcons.shoppingCart,
                      iconColor: colorScheme.secondary,
                      gradientColors: [colorScheme.secondary, colorScheme.secondary.withValues(alpha: 0.7)],
                      label: 'sales.total_sales'.tr(),
                      value: '${data.stats.totalCount}',
                    ),
                  ];

                  if (!isNarrow) {
                    return Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 10),
                        Expanded(child: cards[1]),
                        const SizedBox(width: 10),
                        Expanded(child: cards[2]),
                        const SizedBox(width: 10),
                        Expanded(child: cards[3]),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 10),
                        Expanded(child: cards[1]),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: cards[2]),
                        const SizedBox(width: 10),
                        Expanded(child: cards[3]),
                      ]),
                    ],
                  );
                },
              ),
            ),
          ),

          // ─── Search + Date Filter Row ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'sales.search_hint'.tr(),
                        prefixIcon: const Icon(LucideIcons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(LucideIcons.x, size: 18),
                                onPressed: () {
                                  _debounceTimer?.cancel();
                                  _searchController.clear();
                                  setState(() {});
                                  context
                                      .read<SalesBloc>()
                                      .add(const SalesSearchRequested(''));
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildDateFilterButton(context),
                ],
              ),
            ),
          ),

          // ─── Active Date Filter Chip ───
          if (_dateRange != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Chip(
                    avatar: Icon(LucideIcons.calendar, size: 14, color: colorScheme.primary),
                    label: Text(
                      _datePresetLabel ??
                          '${DateFormat.MMMd().format(_dateRange!.start)} – ${DateFormat.MMMd().format(_dateRange!.end)}',
                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    deleteIcon: const Icon(LucideIcons.x, size: 14),
                    onDeleted: () => setState(() {
                      _dateRange = null;
                      _datePresetLabel = null;
                    }),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
                    backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),

          // ─── Status Filter Chips ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    'sales.recent_sales'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  _FilterChip(
                    label: 'sales.filter_all'.tr(),
                    isSelected: _selectedStatus == null,
                    onSelected: () {
                      setState(() => _selectedStatus = null);
                      context
                          .read<SalesBloc>()
                          .add(const SalesStatusFilterChanged(null));
                    },
                  ),
                  const SizedBox(width: 4),
                  _FilterChip(
                    label: 'sales.filter_completed'.tr(),
                    isSelected: _selectedStatus == 'completed',
                    color: Colors.green,
                    onSelected: () {
                      setState(() => _selectedStatus = 'completed');
                      context
                          .read<SalesBloc>()
                          .add(const SalesStatusFilterChanged('completed'));
                    },
                  ),
                  const SizedBox(width: 4),
                  _FilterChip(
                    label: 'sales.filter_voided'.tr(),
                    isSelected: _selectedStatus == 'voided',
                    color: Colors.red,
                    onSelected: () {
                      setState(() => _selectedStatus = 'voided');
                      context
                          .read<SalesBloc>()
                          .add(const SalesStatusFilterChanged('voided'));
                    },
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 4)),

          // ─── Sale List ───
          if (data.filteredSales.isEmpty)
            SliverFillRemaining(child: _buildEmptyState(context))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final sale = data.filteredSales[index];
                  if (_dateRange != null) {
                    if (sale.saleDate.isBefore(_dateRange!.start) ||
                        sale.saleDate.isAfter(
                            _dateRange!.end.add(const Duration(days: 1)))) {
                      return const SizedBox.shrink();
                    }
                  }
                  return _SaleTile(
                    sale: sale,
                    currencyService: currencyService,
                    hasReturn: data.saleIdsWithReturns.contains(sale.id),
                    searchQuery: data.searchQuery,
                    isProductMatch: data.productMatchedSaleIds.contains(sale.id),
                    onTap: () => context.push('/sales/${sale.id}'),
                  );
                },
                childCount: data.filteredSales.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildDateFilterButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFilter = _dateRange != null;

    return Material(
      color: hasFilter ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDateRangeDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(LucideIcons.calendarRange, size: 20,
              color: hasFilter ? cs.onPrimaryContainer : cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Future<void> _showDateRangeDialog(BuildContext context) async {
    final result = await showDateRangeFilterSheet(
      context,
      currentRange: _dateRange,
      currentLabel: _datePresetLabel,
    );
    if (result == null || !mounted) return;
    setState(() {
      _dateRange = result.range;
      _datePresetLabel = result.label;
    });
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.receipt,
                  size: 56, color: cs.primary.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            Text('sales.empty'.tr(),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'sales.empty_hint'.tr(),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context.push('/sales/new'),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: Text('sales.add_first'.tr()),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stat Card ───
class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final List<Color> gradientColors;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.gradientColors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: iconColor.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Filter Chip ───
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    this.color,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = color ?? colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: isSelected
            ? activeColor.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: isSelected
                  ? Border.all(color: activeColor.withValues(alpha: 0.4))
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? activeColor
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sale Tile ───
class _SaleTile extends StatelessWidget {
  final SaleEntity sale;
  final CurrencyService currencyService;
  final bool hasReturn;
  final String? searchQuery;
  final bool isProductMatch;
  final VoidCallback onTap;

  const _SaleTile({
    required this.sale,
    required this.currencyService,
    this.hasReturn = false,
    this.searchQuery,
    this.isProductMatch = false,
    required this.onTap,
  });

  Color _statusColor(BuildContext context) {
    switch (sale.status) {
      case 'completed':
        return Colors.green;
      case 'voided':
        return Theme.of(context).colorScheme.error;
      case 'draft':
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon() {
    switch (sale.status) {
      case 'completed':
        return LucideIcons.checkCircle;
      case 'voided':
        return LucideIcons.ban;
      case 'draft':
      case 'pending':
        return LucideIcons.fileEdit;
      default:
        return LucideIcons.file;
    }
  }

  String _statusLabel() {
    switch (sale.status) {
      case 'completed':
        return 'sales.status_completed'.tr();
      case 'voided':
        return 'sales.status_voided'.tr();
      case 'draft':
      case 'pending':
        return 'sales.status_draft'.tr();
      default:
        return sale.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusClr = _statusColor(context);
    final customerInitial = sale.customerName != null &&
            sale.customerName!.isNotEmpty
        ? sale.customerName![0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: statusClr,
                      borderRadius: const BorderRadiusDirectional.only(
                        topStart: Radius.circular(14),
                        bottomStart: Radius.circular(14),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      cs.primaryContainer,
                                      cs.primaryContainer.withValues(alpha: 0.6),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  customerInitial,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _HighlightedText(
                                      text: sale.invoiceNumber,
                                      query: searchQuery,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w600) ?? const TextStyle(),
                                      highlightColor: cs.primary.withValues(alpha: 0.2),
                                    ),
                                    _HighlightedText(
                                      text: sale.customerName ?? 'sales.walk_in'.tr(),
                                      query: searchQuery,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant) ?? const TextStyle(),
                                      highlightColor: cs.primary.withValues(alpha: 0.2),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusClr.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: statusClr.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_statusIcon(), size: 12, color: statusClr),
                                    const SizedBox(width: 4),
                                    Text(
                                      _statusLabel(),
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: statusClr,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                              Icon(LucideIcons.calendar,
                                  size: 13, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat.yMMMd().format(sale.saleDate),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              if (sale.paymentMethod.isNotEmpty) ...[
                                const SizedBox(width: 12),
                                Icon(LucideIcons.creditCard,
                                    size: 13, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  sale.paymentMethod,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                              if (isProductMatch) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.tertiary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: cs.tertiary.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.package,
                                          size: 10, color: cs.tertiary),
                                      const SizedBox(width: 3),
                                      Text(
                                        'sales.contains_product'.tr(),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: cs.tertiary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (hasReturn) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.error.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: cs.error.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(LucideIcons.undo2,
                                          size: 10, color: cs.error),
                                      const SizedBox(width: 3),
                                      Text(
                                        'sales.has_returns'.tr(),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: cs.error,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                currencyService
                                    .format(sale.totalCents.toBigInt().toInt()),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Highlighted Text ───
class _HighlightedText extends StatelessWidget {
  final String text;
  final String? query;
  final TextStyle style;
  final Color highlightColor;
  final int? maxLines;
  final TextOverflow? overflow;

  const _HighlightedText({
    required this.text,
    this.query,
    required this.style,
    required this.highlightColor,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    if (query == null || query!.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final q = query!.toLowerCase();
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    int start = 0;

    while (start < text.length) {
      final index = lowerText.indexOf(q, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query!.length),
        style: TextStyle(
          backgroundColor: highlightColor,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = index + query!.length;
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
