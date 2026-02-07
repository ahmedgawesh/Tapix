import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../bloc/purchases_bloc.dart';

class PurchaseListScreen extends StatelessWidget {
  const PurchaseListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<PurchasesBloc>(),
      child: const _PurchaseHubView(),
    );
  }
}

class _PurchaseHubView extends StatefulWidget {
  const _PurchaseHubView();

  @override
  State<_PurchaseHubView> createState() => _PurchaseHubViewState();
}

class _PurchaseHubViewState extends State<_PurchaseHubView> {
  final _searchController = TextEditingController();
  String? _selectedStatus;
  DateTimeRange? _dateRange;

  @override
  void dispose() {
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
        title: Text('purchases.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.undo2),
            onPressed: () => context.push('/purchases/returns'),
            tooltip: 'purchases.returns'.tr(),
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'settings.title'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<PurchasesBloc, RealtimeState<PurchasesHubData>>(
          builder: (context, state) {
            if (state is RealtimeLoading<PurchasesHubData> &&
                state.previousData == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is RealtimeError<PurchasesHubData> &&
                state.previousData == null) {
              return _buildErrorState(context, state);
            }

            PurchasesHubData? data;
            if (state is RealtimeSuccess<PurchasesHubData>) {
              data = state.data;
            } else if (state is RealtimeLoading<PurchasesHubData>) {
              data = state.previousData;
            } else if (state is RealtimeError<PurchasesHubData>) {
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
        onPressed: () => context.push('/purchases/new'),
        icon: const Icon(LucideIcons.plus),
        label: Text('purchases.new'.tr()),
        elevation: 2,
      ),
    );
  }

  Widget _buildErrorState(
      BuildContext context, RealtimeError<PurchasesHubData> state) {
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
            onPressed: () => context.read<PurchasesBloc>().refresh(),
            icon: const Icon(LucideIcons.rotateCcw),
            label: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, PurchasesHubData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = sl<CurrencyService>();

    return RefreshIndicator(
      onRefresh: () async => context.read<PurchasesBloc>().refresh(),
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
                      icon: LucideIcons.shoppingCart,
                      iconColor: colorScheme.primary,
                      gradientColors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.7)],
                      label: 'purchases.total_purchases'.tr(),
                      value: '${data.stats.totalCount}',
                    ),
                    _StatCard(
                      icon: LucideIcons.fileEdit,
                      iconColor: Colors.orange,
                      gradientColors: [Colors.orange, Colors.orange.shade300],
                      label: 'purchases.drafts'.tr(),
                      value: '${data.stats.draftCount}',
                    ),
                    _StatCard(
                      icon: LucideIcons.checkCircle,
                      iconColor: Colors.green,
                      gradientColors: [Colors.green, Colors.green.shade300],
                      label: 'purchases.posted_count'.tr(),
                      value: '${data.stats.postedCount}',
                    ),
                    _StatCard(
                      icon: LucideIcons.wallet,
                      iconColor: colorScheme.secondary,
                      gradientColors: [colorScheme.secondary, colorScheme.secondary.withValues(alpha: 0.7)],
                      label: 'purchases.total_payables'.tr(),
                      value: currencyService
                          .format(data.stats.totalPayableCents),
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
                        hintText: 'purchases.search_hint'.tr(),
                        prefixIcon: const Icon(LucideIcons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(LucideIcons.x, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                  context
                                      .read<PurchasesBloc>()
                                      .add(const PurchasesSearchRequested(''));
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
                      onChanged: (value) {
                        setState(() {});
                        context
                            .read<PurchasesBloc>()
                            .add(PurchasesSearchRequested(value));
                      },
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
                      '${DateFormat.MMMd().format(_dateRange!.start)} – ${DateFormat.MMMd().format(_dateRange!.end)}',
                      style: theme.textTheme.labelSmall,
                    ),
                    deleteIcon: const Icon(LucideIcons.x, size: 14),
                    onDeleted: () => setState(() => _dateRange = null),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
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
                    'purchases.all_purchases'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  _FilterChip(
                    label: 'purchases.filter_all'.tr(),
                    isSelected: _selectedStatus == null,
                    onSelected: () {
                      setState(() => _selectedStatus = null);
                      context
                          .read<PurchasesBloc>()
                          .add(const PurchasesStatusFilterChanged(null));
                    },
                  ),
                  const SizedBox(width: 4),
                  _FilterChip(
                    label: 'purchases.filter_draft'.tr(),
                    isSelected: _selectedStatus == 'draft',
                    color: Colors.orange,
                    onSelected: () {
                      setState(() => _selectedStatus = 'draft');
                      context
                          .read<PurchasesBloc>()
                          .add(const PurchasesStatusFilterChanged('draft'));
                    },
                  ),
                  const SizedBox(width: 4),
                  _FilterChip(
                    label: 'purchases.filter_posted'.tr(),
                    isSelected: _selectedStatus == 'posted',
                    color: Colors.green,
                    onSelected: () {
                      setState(() => _selectedStatus = 'posted');
                      context
                          .read<PurchasesBloc>()
                          .add(const PurchasesStatusFilterChanged('posted'));
                    },
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 4)),

          // ─── Purchase List ───
          if (data.filteredPurchases.isEmpty)
            SliverFillRemaining(child: _buildEmptyState(context))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final purchase = data.filteredPurchases[index];
                  // Apply date filter client-side
                  if (_dateRange != null) {
                    if (purchase.purchaseDate.isBefore(_dateRange!.start) ||
                        purchase.purchaseDate.isAfter(
                            _dateRange!.end.add(const Duration(days: 1)))) {
                      return const SizedBox.shrink();
                    }
                  }
                  return _PurchaseTile(
                    purchase: purchase,
                    currencyService: currencyService,
                    onTap: () =>
                        context.push('/purchases/${purchase.id}'),
                  );
                },
                childCount: data.filteredPurchases.length,
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
        onTap: () async {
          final range = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 30)),
            initialDateRange: _dateRange,
          );
          if (range != null) {
            setState(() => _dateRange = range);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(LucideIcons.calendarRange, size: 20,
              color: hasFilter ? cs.onPrimaryContainer : cs.onSurfaceVariant),
        ),
      ),
    );
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
              child: Icon(LucideIcons.shoppingCart,
                  size: 56, color: cs.primary.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            Text('purchases.empty'.tr(),
                style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'purchases.empty_hint'.tr(),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context.push('/purchases/new'),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: Text('purchases.add_first'.tr()),
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

// ─── Stat Card (Premium) ───
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

// ─── Filter Chip (Enhanced) ───
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

// ─── Purchase Tile (Premium with status accent) ───
class _PurchaseTile extends StatelessWidget {
  final PurchaseEntity purchase;
  final CurrencyService currencyService;
  final VoidCallback onTap;

  const _PurchaseTile({
    required this.purchase,
    required this.currencyService,
    required this.onTap,
  });

  Color _statusColor(BuildContext context) {
    switch (purchase.status) {
      case 'draft':
      case 'pending':
        return Colors.orange;
      case 'posted':
        return Colors.green;
      case 'voided':
        return Theme.of(context).colorScheme.error;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon() {
    switch (purchase.status) {
      case 'draft':
      case 'pending':
        return LucideIcons.fileEdit;
      case 'posted':
        return LucideIcons.checkCircle;
      case 'voided':
        return LucideIcons.ban;
      default:
        return LucideIcons.file;
    }
  }

  String _statusLabel() {
    switch (purchase.status) {
      case 'draft':
      case 'pending':
        return 'purchases.status_draft'.tr();
      case 'posted':
        return 'purchases.status_posted'.tr();
      case 'voided':
        return 'purchases.status_voided'.tr();
      default:
        return purchase.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusClr = _statusColor(context);
    final supplierInitial = purchase.supplierName != null &&
            purchase.supplierName!.isNotEmpty
        ? purchase.supplierName![0].toUpperCase()
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
                  // Status accent bar
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
                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Supplier avatar
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
                                  supplierInitial,
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
                                    Text(
                                      purchase.purchaseNumber,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    if (purchase.supplierName != null)
                                      Text(
                                        purchase.supplierName!,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              // Status badge
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
                              Icon(LucideIcons.calendar,
                                  size: 13, color: cs.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat.yMMMd().format(purchase.purchaseDate),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                              const Spacer(),
                              Text(
                                currencyService
                                    .format(purchase.totalCents.toBigInt().toInt()),
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
