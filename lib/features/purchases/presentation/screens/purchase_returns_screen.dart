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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = sl<CurrencyService>();

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
                    Icon(LucideIcons.alertCircle,
                        size: 64, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text('common.error'.tr(),
                        style: theme.textTheme.titleLarge),
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
            } else if (state is RealtimeLoading<List<PurchaseReturnEntity>>) {
              returns = state.previousData;
            } else if (state is RealtimeError<List<PurchaseReturnEntity>>) {
              returns = state.previousData;
            }

            final displayReturns = returns ?? [];

            return Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16),
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
                                context
                                    .read<PurchaseReturnsBloc>()
                                    .add(const PurchaseReturnsSearchRequested(
                                        ''));
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    onChanged: (value) {
                      context
                          .read<PurchaseReturnsBloc>()
                          .add(PurchaseReturnsSearchRequested(value));
                    },
                  ),
                ),

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
                              currencyService: currencyService,
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

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.undo2, size: 80, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('purchases.no_returns'.tr(),
              style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'purchases.no_returns_hint'.tr(),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline),
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
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: colorScheme.errorContainer,
                  child: Icon(LucideIcons.undo2,
                      size: 20, color: colorScheme.onErrorContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(returnEntity.returnNumber,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (returnEntity.supplierName != null)
                        Text(returnEntity.supplierName!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Text(
                  currencyService
                      .format(returnEntity.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.error, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.calendar,
                    size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  DateFormat.yMMMd().format(returnEntity.returnDate),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                if (returnEntity.reason != null &&
                    returnEntity.reason!.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Icon(LucideIcons.messageSquare,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      returnEntity.reason!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
