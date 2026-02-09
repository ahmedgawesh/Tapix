import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/sale_entity.dart';
import '../bloc/sale_returns_bloc.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                                const SaleReturnsSearchRequested(''));
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
                  context.read<SaleReturnsBloc>().add(
                      SaleReturnsSearchRequested(value));
                },
              ),
            ),
            Expanded(
              child: BlocBuilder<SaleReturnsBloc,
                  RealtimeState<List<SaleReturnEntity>>>(
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
                          Icon(LucideIcons.alertCircle,
                              size: 64, color: colorScheme.error),
                          const SizedBox(height: 16),
                          Text('common.error'.tr(),
                              style: theme.textTheme.titleLarge),
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
                  } else if (state
                      is RealtimeLoading<List<SaleReturnEntity>>) {
                    returns = state.previousData;
                  } else if (state
                      is RealtimeError<List<SaleReturnEntity>>) {
                    returns = state.previousData;
                  }

                  if (returns == null || returns.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.undo2,
                              size: 56,
                              color: colorScheme.primary.withValues(alpha: 0.3)),
                          const SizedBox(height: 16),
                          Text('sales.no_returns'.tr(),
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async =>
                        context.read<SaleReturnsBloc>().refresh(),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: returns.length,
                      itemBuilder: (context, index) {
                        final ret = returns![index];
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: colorScheme.outlineVariant
                                    .withValues(alpha: 0.4)),
                          ),
                          child: ListTile(
                            onTap: () => context.push('/sales/returns/${ret.id}'),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(LucideIcons.undo2,
                                  color: colorScheme.onErrorContainer,
                                  size: 18),
                            ),
                            title: Text(ret.returnNumber,
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat.yMMMd().format(ret.returnDate),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant),
                                ),
                                if (ret.reason != null &&
                                    ret.reason!.isNotEmpty)
                                  Text(
                                    ret.reason!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Text(
                              cs.format(
                                  ret.totalCents.toBigInt().toInt()),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: colorScheme.error,
                                fontWeight: FontWeight.bold,
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
