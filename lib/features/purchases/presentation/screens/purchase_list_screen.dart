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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'purchases.quick_stats'.tr(),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 700;
                      final cards = [
                        _StatCard(
                          icon: LucideIcons.shoppingCart,
                          iconColor: colorScheme.primary,
                          backgroundColor: colorScheme.primaryContainer
                              .withValues(alpha: 0.5),
                          label: 'purchases.total_purchases'.tr(),
                          value: '${data.stats.totalCount}',
                        ),
                        _StatCard(
                          icon: LucideIcons.fileEdit,
                          iconColor: Colors.orange,
                          backgroundColor:
                              Colors.orange.withValues(alpha: 0.12),
                          label: 'purchases.drafts'.tr(),
                          value: '${data.stats.draftCount}',
                        ),
                        _StatCard(
                          icon: LucideIcons.checkCircle,
                          iconColor: Colors.green,
                          backgroundColor:
                              Colors.green.withValues(alpha: 0.12),
                          label: 'purchases.posted_count'.tr(),
                          value: '${data.stats.postedCount}',
                        ),
                        _StatCard(
                          icon: LucideIcons.wallet,
                          iconColor: colorScheme.secondary,
                          backgroundColor: colorScheme.secondaryContainer
                              .withValues(alpha: 0.5),
                          label: 'purchases.total_payables'.tr(),
                          value: currencyService
                              .format(data.stats.totalPayableCents),
                        ),
                      ];

                      if (!isNarrow) {
                        return Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[1]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[2]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[3]),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Row(children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[1]),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: cards[2]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[3]),
                          ]),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // ─── Search Bar ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'purchases.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () {
                            _searchController.clear();
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
                ),
                onChanged: (value) {
                  context
                      .read<PurchasesBloc>()
                      .add(PurchasesSearchRequested(value));
                },
              ),
            ),
          ),

          // ─── Quick Actions ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(LucideIcons.plus, size: 18),
                    label: Text('purchases.new'.tr()),
                    onPressed: () => context.push('/purchases/new'),
                  ),
                  ActionChip(
                    avatar: const Icon(LucideIcons.undo2, size: 18),
                    label: Text('purchases.returns'.tr()),
                    onPressed: () => context.push('/purchases/returns'),
                  ),
                ],
              ),
            ),
          ),

          // ─── Status Filter Chips ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'purchases.all_purchases'.tr(),
                    style: theme.textTheme.titleMedium
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

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ─── Purchase List ───
          if (data.filteredPurchases.isEmpty)
            SliverFillRemaining(child: _buildEmptyState(context))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final purchase = data.filteredPurchases[index];
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

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.shoppingCart,
                size: 80, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('purchases.empty'.tr(),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'purchases.empty_hint'.tr(),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/purchases/new'),
              icon: const Icon(LucideIcons.plus),
              label: Text('purchases.add_first'.tr()),
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
  final Color backgroundColor;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Purchase Tile ───
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

  Color _statusBgColor(BuildContext context) {
    return _statusColor(context).withValues(alpha: 0.12);
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
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(LucideIcons.shoppingCart,
                        size: 20, color: colorScheme.onPrimaryContainer),
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
                                color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusBgColor(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusLabel(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _statusColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(LucideIcons.calendar,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat.yMMMd().format(purchase.purchaseDate),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    currencyService
                        .format(purchase.totalCents.toBigInt().toInt()),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
