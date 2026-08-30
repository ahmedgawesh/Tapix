import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/unified_return_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../bloc/purchase_returns_bloc.dart';
import '../../../shared/widgets/unified_return_search_sheet.dart';
import '../../../shared/widgets/date_range_filter_sheet.dart';

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
  String? _datePresetLabel;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PurchaseReturnEntity> _applyDateFilter(
    List<PurchaseReturnEntity> returns,
  ) {
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showUnifiedReturnSearchSheet(context, side: ReturnSide.purchase),
        icon: const Icon(LucideIcons.plus),
        label: Text('returns.create_purchase_return'.tr()),
      ),
      body: SafeArea(
        child:
            BlocBuilder<
              PurchaseReturnsBloc,
              RealtimeState<List<PurchaseReturnEntity>>
            >(
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
                        Icon(
                          LucideIcons.alertCircle,
                          size: 64,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'common.error'.tr(),
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () =>
                              context.read<PurchaseReturnsBloc>().refresh(),
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
                } else if (state
                    is RealtimeLoading<List<PurchaseReturnEntity>>) {
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
                                          context.read<PurchaseReturnsBloc>().add(
                                            const PurchaseReturnsSearchRequested(
                                              '',
                                            ),
                                          );
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                isDense: true,
                              ),
                              onChanged: (value) {
                                context.read<PurchaseReturnsBloc>().add(
                                  PurchaseReturnsSearchRequested(value),
                                );
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
                            avatar: Icon(
                              LucideIcons.calendar,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            label: Text(
                              _datePresetLabel ??
                                  '${DateFormat.MMMd().format(_dateRange!.start)} – ${DateFormat.MMMd().format(_dateRange!.end)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            deleteIcon: const Icon(LucideIcons.x, size: 14),
                            onDeleted: () => setState(() {
                              _dateRange = null;
                              _datePresetLabel = null;
                            }),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(
                              color: colorScheme.primary.withValues(alpha: 0.3),
                            ),
                            backgroundColor: colorScheme.primaryContainer
                                .withValues(alpha: 0.3),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
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
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            LucideIcons.calendarRange,
            size: 20,
            color: hasFilter ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBar(
    BuildContext context,
    List<PurchaseReturnEntity> returns,
    CurrencyService cs,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totalRefund = returns.fold<int>(
      0,
      (sum, r) => sum + r.totalCents.toBigInt().toInt(),
    );

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
                colors: [
                  colorScheme.error,
                  colorScheme.error.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.undo2, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${returns.length} ${'purchases.returns'.tr().toLowerCase()}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'purchases.return_total'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            cs.format(totalRefund),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.error,
            ),
          ),
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
            child: Icon(
              LucideIcons.undo2,
              size: 48,
              color: cs.error.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'purchases.no_returns'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'purchases.no_returns_hint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
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
    final supplierInitial =
        returnEntity.supplierName != null &&
            returnEntity.supplierName!.isNotEmpty
        ? returnEntity.supplierName![0].toUpperCase()
        : '?';

    return Padding(
      key: ValueKey(returnEntity.unifiedId),
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (returnEntity.isAdjustment) {
              context.push('/purchases/returns/adj/${returnEntity.id}');
            } else {
              context.push('/purchases/returns/${returnEntity.id}');
            }
          },
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
                      color: returnEntity.status == 'voided'
                          ? cs.outlineVariant
                          : returnEntity.isAdjustment
                          ? cs.tertiary
                          : cs.error,
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
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: returnEntity.isAdjustment
                                    ? [
                                        cs.tertiaryContainer,
                                        cs.tertiaryContainer.withValues(
                                          alpha: 0.5,
                                        ),
                                      ]
                                    : [
                                        cs.errorContainer,
                                        cs.errorContainer.withValues(
                                          alpha: 0.5,
                                        ),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: returnEntity.isAdjustment
                                ? Icon(
                                    LucideIcons.rotateCcw,
                                    color: cs.onTertiaryContainer,
                                    size: 16,
                                  )
                                : Text(
                                    supplierInitial,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: cs.error,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        returnEntity.returnNumber,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (returnEntity.isAdjustment) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.tertiaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          'returns.adjustment'.tr(),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: cs.onTertiaryContainer,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 9,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    if (returnEntity.supplierName != null) ...[
                                      Icon(
                                        LucideIcons.building2,
                                        size: 11,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          returnEntity.supplierName!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                                fontSize: 11,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Icon(
                                      LucideIcons.calendar,
                                      size: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      DateFormat.yMMMd().format(
                                        returnEntity.returnDate,
                                      ),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                    ),
                                  ],
                                ),
                                if (returnEntity.reason != null &&
                                    returnEntity.reason!.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.messageSquare,
                                        size: 11,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          returnEntity.reason!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                                fontStyle: FontStyle.italic,
                                                fontSize: 11,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currencyService.format(
                                  returnEntity.totalCents.toBigInt().toInt(),
                                ),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: cs.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: returnEntity.status == 'voided'
                                      ? cs.error.withValues(alpha: 0.1)
                                      : Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: returnEntity.status == 'voided'
                                        ? cs.error.withValues(alpha: 0.3)
                                        : Colors.green.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  returnEntity.status == 'voided'
                                      ? 'purchases.status_voided'.tr()
                                      : 'purchases.status_posted'.tr(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: returnEntity.status == 'voided'
                                        ? cs.error
                                        : Colors.green,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 9,
                                  ),
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
