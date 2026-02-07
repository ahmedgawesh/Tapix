import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../bloc/purchase_returns_bloc.dart';

class PurchaseReturnsScreen extends StatelessWidget {
  const PurchaseReturnsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<PurchaseReturnsBloc>(),
      child: const _PurchaseReturnsView(),
    );
  }
}

class _PurchaseReturnsView extends StatefulWidget {
  const _PurchaseReturnsView();

  @override
  State<_PurchaseReturnsView> createState() => _PurchaseReturnsViewState();
}

class _PurchaseReturnsViewState extends State<_PurchaseReturnsView> {
  final _searchController = TextEditingController();
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PurchaseReturnEntity> _applyDateFilter(List<PurchaseReturnEntity> returns) {
    if (_dateRange == null) return returns;
    return returns.where((r) {
      return !r.returnDate.isBefore(_dateRange!.start) &&
          !r.returnDate.isAfter(_dateRange!.end.add(const Duration(days: 1)));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

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
        title: Text('purchases.returns'.tr()),
      ),
      body: SafeArea(
        child: BlocBuilder<PurchaseReturnsBloc,
            RealtimeState<List<PurchaseReturnEntity>>>(
          builder: (context, state) {
            if (state is RealtimeLoading<List<PurchaseReturnEntity>> &&
                state.previousData == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is RealtimeError<List<PurchaseReturnEntity>> &&
                state.previousData == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.alertCircle, size: 64, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text('common.error'.tr(), style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => context.read<PurchaseReturnsBloc>().refresh(),
                      icon: const Icon(LucideIcons.rotateCcw),
                      label: Text('common.retry'.tr()),
                    ),
                  ],
                ),
              );
            }

            List<PurchaseReturnEntity>? returns;
            if (state is RealtimeSuccess<List<PurchaseReturnEntity>>) {
              returns = state.data;
            } else if (state is RealtimeLoading<List<PurchaseReturnEntity>>) {
              returns = state.previousData;
            } else if (state is RealtimeError<List<PurchaseReturnEntity>>) {
              returns = state.previousData;
            }

            final displayReturns = _applyDateFilter(returns ?? []);

            return Column(
              children: [
                // Search + Date filter
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'purchases.search_returns'.tr(),
                            prefixIcon: const Icon(LucideIcons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(LucideIcons.x),
                                    onPressed: () {
                                      _searchController.clear();
                                      context.read<PurchaseReturnsBloc>()
                                          .add(const PurchaseReturnsSearchRequested(''));
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            isDense: true,
                          ),
                          onChanged: (value) {
                            context.read<PurchaseReturnsBloc>()
                                .add(PurchaseReturnsSearchRequested(value));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildDateFilterButton(context),
                    ],
                  ),
                ),

                // Active date filter chip
                if (_dateRange != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Chip(
                        avatar: const Icon(LucideIcons.calendar, size: 14),
                        label: Text(
                          '${DateFormat.MMMd().format(_dateRange!.start)} – ${DateFormat.MMMd().format(_dateRange!.end)}',
                          style: theme.textTheme.labelSmall,
                        ),
                        deleteIcon: const Icon(LucideIcons.x, size: 14),
                        onDeleted: () => setState(() => _dateRange = null),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),

                // Summary bar
                if (displayReturns.isNotEmpty)
                  _buildSummaryBar(context, displayReturns, cs),

                // List
                Expanded(
                  child: displayReturns.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: displayReturns.length,
                          itemBuilder: (context, index) {
                            final ret = displayReturns[index];
                            return _ReturnTile(
                              returnEntity: ret,
                              currencyService: cs,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
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

  Widget _buildSummaryBar(BuildContext context, List<PurchaseReturnEntity> returns,
      CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalRefund = returns.fold<int>(
        0, (sum, r) => sum + r.totalCents.toBigInt().toInt());

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.15)),
      ),
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
            child: const Icon(LucideIcons.undo2, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${returns.length} ${'purchases.returns'.tr().toLowerCase()}',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant)),
              Text('purchases.return_total'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          Text(cs.format(totalRefund),
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold, color: colorScheme.error)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.undo2, size: 48,
                color: cs.error.withValues(alpha: 0.3)),
          ),
          const SizedBox(height: 20),
          Text('purchases.no_returns'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text('purchases.no_returns_hint'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ReturnTile extends StatelessWidget {
  final PurchaseReturnEntity returnEntity;
  final CurrencyService currencyService;

  const _ReturnTile({
    required this.returnEntity,
    required this.currencyService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final supplierInitial = returnEntity.supplierName != null &&
            returnEntity.supplierName!.isNotEmpty
        ? returnEntity.supplierName![0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Red accent bar
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(14),
                      bottomStart: Radius.circular(14),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // Supplier avatar
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [cs.errorContainer, cs.errorContainer.withValues(alpha: 0.5)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(supplierInitial,
                              style: theme.textTheme.titleSmall?.copyWith(
                                  color: cs.error, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(returnEntity.returnNumber,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (returnEntity.supplierName != null) ...[
                                    Icon(LucideIcons.building2, size: 11,
                                        color: cs.onSurfaceVariant),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(returnEntity.supplierName!,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant, fontSize: 11),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Icon(LucideIcons.calendar, size: 11,
                                      color: cs.onSurfaceVariant),
                                  const SizedBox(width: 3),
                                  Text(DateFormat.yMMMd().format(returnEntity.returnDate),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant, fontSize: 11)),
                                ],
                              ),
                              if (returnEntity.reason != null &&
                                  returnEntity.reason!.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(LucideIcons.messageSquare, size: 11,
                                        color: cs.onSurfaceVariant),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(returnEntity.reason!,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontStyle: FontStyle.italic,
                                              fontSize: 11),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          currencyService.format(returnEntity.totalCents.toBigInt().toInt()),
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: cs.error, fontWeight: FontWeight.bold),
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
    );
  }
}
