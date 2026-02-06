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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.undo2, size: 16, color: colorScheme.error),
          const SizedBox(width: 8),
          Text('${returns.length} ${'purchases.returns'.tr().toLowerCase()}',
              style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant)),
          const Spacer(),
          Text(cs.format(totalRefund),
              style: theme.textTheme.titleSmall?.copyWith(
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
          Icon(LucideIcons.undo2, size: 64,
              color: cs.onSurface.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text('purchases.no_returns'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(LucideIcons.undo2, size: 20, color: cs.error),
            ),
            const SizedBox(width: 14),
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
                        Icon(LucideIcons.building2, size: 12,
                            color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(returnEntity.supplierName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(LucideIcons.calendar, size: 12,
                          color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(DateFormat.yMMMd().format(returnEntity.returnDate),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant)),
                    ],
                  ),
                  if (returnEntity.reason != null &&
                      returnEntity.reason!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(LucideIcons.messageSquare, size: 12,
                            color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(returnEntity.reason!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant),
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
    );
  }
}
