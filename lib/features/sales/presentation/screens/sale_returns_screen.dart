import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/services/unified_return_service.dart';
import '../../domain/entities/sale_entity.dart';
import '../bloc/sale_returns_bloc.dart';
import '../../../shared/widgets/unified_return_search_sheet.dart';
import '../../../shared/widgets/date_range_filter_sheet.dart';

class SaleReturnsScreen extends StatelessWidget {
  const SaleReturnsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SaleReturnsBloc>(),
      child: const _SaleReturnsView(),
    );
  }
}

class _SaleReturnsView extends StatefulWidget {
  const _SaleReturnsView();

  @override
  State<_SaleReturnsView> createState() => _SaleReturnsViewState();
}

class _SaleReturnsViewState extends State<_SaleReturnsView> {
  final _searchController = TextEditingController();
  DateTimeRange? _dateRange;
  String? _datePresetLabel;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Removes the internal `[REASON:xxx]` tag that the adjustment-return form
  /// prepends to the `reason`/`notes` column so list cards show only the
  /// user-authored text.
  static String _stripReasonTag(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'\[REASON:[^\]]*\]'), '').trim();
  }

  List<SaleReturnEntity> _applyDateFilter(List<SaleReturnEntity> returns) {
    if (_dateRange == null) return returns;
    return returns.where((r) {
      return !r.returnDate.isBefore(_dateRange!.start) &&
          !r.returnDate.isAfter(_dateRange!.end.add(const Duration(days: 1)));
    }).toList();
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
              context.go('/sales');
            }
          },
        ),
        title: Text('sales.returns'.tr()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            showUnifiedReturnSearchSheet(context, side: ReturnSide.sale),
        icon: const Icon(LucideIcons.plus),
        label: Text('returns.create_sale_return'.tr()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'sales.search_returns'.tr(),
                        prefixIcon: const Icon(LucideIcons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(LucideIcons.x, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                  context.read<SaleReturnsBloc>().add(
                                    const SaleReturnsSearchRequested(''),
                                  );
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {});
                        context.read<SaleReturnsBloc>().add(
                          SaleReturnsSearchRequested(value),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildDateFilterButton(context),
                ],
              ),
            ),
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
                    backgroundColor: colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: BlocBuilder<SaleReturnsBloc, RealtimeState<List<SaleReturnEntity>>>(
                builder: (context, state) {
                  if (state is RealtimeLoading<List<SaleReturnEntity>> &&
                      state.previousData == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is RealtimeError<List<SaleReturnEntity>> &&
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
                                context.read<SaleReturnsBloc>().refresh(),
                            icon: const Icon(LucideIcons.rotateCcw),
                            label: Text('common.retry'.tr()),
                          ),
                        ],
                      ),
                    );
                  }

                  List<SaleReturnEntity>? returns;
                  if (state is RealtimeSuccess<List<SaleReturnEntity>>) {
                    returns = state.data;
                  } else if (state is RealtimeLoading<List<SaleReturnEntity>>) {
                    returns = state.previousData;
                  } else if (state is RealtimeError<List<SaleReturnEntity>>) {
                    returns = state.previousData;
                  }

                  final displayReturns = _applyDateFilter(returns ?? []);

                  if (displayReturns.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.undo2,
                            size: 56,
                            color: colorScheme.primary.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'sales.no_returns'.tr(),
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async =>
                        context.read<SaleReturnsBloc>().refresh(),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: displayReturns.length,
                      itemBuilder: (context, index) {
                        final ret = displayReturns[index];
                        final accentColor = ret.isVoided
                            ? colorScheme.outlineVariant
                            : ret.isAdjustment
                            ? colorScheme.tertiary
                            : colorScheme.error;
                        final cleanReason = _stripReasonTag(ret.reason);
                        return Padding(
                          key: ValueKey(ret.unifiedId),
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap:
                                  sl<LanNetworkService>().snapshot.mode ==
                                      LanMode.client
                                  ? null
                                  : () {
                                      if (ret.isAdjustment) {
                                        context.push(
                                          '/sales/returns/adj/${ret.id}',
                                        );
                                      } else {
                                        context.push(
                                          '/sales/returns/${ret.id}',
                                        );
                                      }
                                    },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: IntrinsicHeight(
                                  child: Row(
                                    children: [
                                      // Status accent bar
                                      Container(
                                        width: 4,
                                        decoration: BoxDecoration(
                                          color: accentColor,
                                          borderRadius:
                                              const BorderRadiusDirectional.only(
                                                topStart: Radius.circular(14),
                                                bottomStart: Radius.circular(
                                                  14,
                                                ),
                                              ),
                                        ),
                                      ),
                                      Expanded(
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 4,
                                              ),
                                          leading: Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: ret.isAdjustment
                                                  ? colorScheme
                                                        .tertiaryContainer
                                                  : colorScheme.errorContainer,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              ret.isAdjustment
                                                  ? LucideIcons.rotateCcw
                                                  : LucideIcons.undo2,
                                              color: ret.isAdjustment
                                                  ? colorScheme
                                                        .onTertiaryContainer
                                                  : colorScheme
                                                        .onErrorContainer,
                                              size: 18,
                                            ),
                                          ),
                                          title: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  ret.returnNumber,
                                                  style: theme
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (ret.isAdjustment) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme
                                                        .tertiaryContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'returns.adjustment'.tr(),
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: colorScheme
                                                              .onTertiaryContainer,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 9,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                DateFormat.yMMMd().format(
                                                  ret.returnDate,
                                                ),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                              if (cleanReason.isNotEmpty)
                                                Text(
                                                  cleanReason,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                          trailing: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                cs.format(
                                                  ret.totalCents
                                                      .toBigInt()
                                                      .toInt(),
                                                ),
                                                style: theme
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      color: colorScheme.error,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                              if (ret.isVoided) ...[
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme
                                                        .surfaceContainerHighest,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'purchases.status_voided'
                                                        .tr(),
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color: colorScheme
                                                              .onSurfaceVariant,
                                                          fontSize: 9,
                                                        ),
                                                  ),
                                                ),
                                              ],
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
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
