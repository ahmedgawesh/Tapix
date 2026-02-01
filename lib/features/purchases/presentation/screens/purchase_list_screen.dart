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
      child: const _PurchaseListView(),
    );
  }
}

class _PurchaseListView extends StatefulWidget {
  const _PurchaseListView();

  @override
  State<_PurchaseListView> createState() => _PurchaseListViewState();
}

class _PurchaseListViewState extends State<_PurchaseListView> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = context.read<CurrencyService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          tooltip: 'common.back'.tr(),
        ),
        title: Text('purchases.title'.tr()),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.filter),
            tooltip: 'common.filter'.tr(),
            onSelected: (value) {
              if (value == 'all') {
                context.read<PurchasesBloc>().add(const PurchasesInitialized());
              } else {
                context.read<PurchasesBloc>().add(PurchasesByStatusRequested(value));
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Text('purchases.filter_all'.tr()),
              ),
              PopupMenuItem(
                value: 'pending',
                child: Text('purchases.filter_pending'.tr()),
              ),
              PopupMenuItem(
                value: 'posted',
                child: Text('purchases.filter_posted'.tr()),
              ),
            ],
          ),
        ],
      ),
      body: BlocBuilder<PurchasesBloc, RealtimeState<List<PurchaseEntity>>>(
        builder: (context, state) {
          List<PurchaseEntity>? purchases;
          if (state is RealtimeSuccess<List<PurchaseEntity>>) {
            purchases = state.data;
          } else if (state is RealtimeLoading<List<PurchaseEntity>>) {
            purchases = state.previousData;
          } else if (state is RealtimeError<List<PurchaseEntity>>) {
            purchases = state.previousData;
          }

          if (state is RealtimeLoading<List<PurchaseEntity>> && purchases == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<List<PurchaseEntity>> && purchases == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.alertCircle, size: 64, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text('common.error'.tr()),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.read<PurchasesBloc>().refresh(),
                    child: Text('common.retry'.tr()),
                  ),
                ],
              ),
            );
          }

          final displayPurchases = purchases ?? [];

          if (displayPurchases.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.shoppingCart,
                    size: 64,
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'purchases.empty'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: displayPurchases.length,
            itemBuilder: (context, index) {
              final purchase = displayPurchases[index];
              return _PurchaseTile(
                purchase: purchase,
                currencyService: currencyService,
                onTap: () => context.push('/purchases/${purchase.id}'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/purchases/new'),
        icon: const Icon(LucideIcons.plus),
        label: Text('purchases.new'.tr()),
      ),
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  final PurchaseEntity purchase;
  final CurrencyService currencyService;
  final VoidCallback onTap;

  const _PurchaseTile({
    required this.purchase,
    required this.currencyService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final statusColor = purchase.isPending
        ? colorScheme.tertiary
        : colorScheme.primary;
    final statusBgColor = purchase.isPending
        ? colorScheme.tertiaryContainer
        : colorScheme.primaryContainer;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                  Expanded(
                    child: Text(
                      purchase.purchaseNumber,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      purchase.isPending
                          ? 'purchases.status_pending'.tr()
                          : 'purchases.status_posted'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    LucideIcons.calendar,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat.yMMMd().format(purchase.purchaseDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    currencyService.format(purchase.totalCents.toBigInt().toInt()),
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
