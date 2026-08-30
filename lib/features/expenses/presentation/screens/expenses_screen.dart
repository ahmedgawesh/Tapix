import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/expense_repository.dart';
import '../bloc/expenses_bloc.dart';
import '../bloc/expense_categories_bloc.dart';

/// Main expenses screen with search, filter, and expense list
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => ExpensesBloc(sl<ExpenseRepository>()),
        ),
        BlocProvider(
          create: (context) => ExpenseCategoriesBloc(sl<ExpenseRepository>()),
        ),
      ],
      child: const _ExpensesContent(),
    );
  }
}

class _ExpensesContent extends StatefulWidget {
  const _ExpensesContent();

  @override
  State<_ExpensesContent> createState() => _ExpensesContentState();
}

class _ExpensesContentState extends State<_ExpensesContent> {
  final _searchController = TextEditingController();
  int? _selectedCategoryId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cs = sl<CurrencyService>();

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
        title: Text('expenses.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.listFilter),
            tooltip: 'expenses.categories'.tr(),
            onPressed: () => context.push('/expenses/categories'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/expenses/new'),
        tooltip: 'expenses.add'.tr(),
        child: const Icon(LucideIcons.plus),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'expenses.search_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x),
                        onPressed: () {
                          _searchController.clear();
                          context.read<ExpensesBloc>().add(
                                const ExpensesSearchRequested(''),
                              );
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              onChanged: (query) {
                context.read<ExpensesBloc>().add(ExpensesSearchRequested(query));
                setState(() {});
              },
            ),
          ),

          // Category filter chips
          BlocBuilder<ExpenseCategoriesBloc, RealtimeState<List<ExpenseCategory>>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<List<ExpenseCategory>>) {
                return const SizedBox.shrink();
              }
              final categories = state.data;
              if (categories.isEmpty) return const SizedBox.shrink();

              return SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    FilterChip(
                      label: Text('common.all'.tr()),
                      selected: _selectedCategoryId == null,
                      onSelected: (_) {
                        setState(() => _selectedCategoryId = null);
                        context.read<ExpensesBloc>().add(
                              const ExpensesFilterByCategoryRequested(null),
                            );
                      },
                    ),
                    const SizedBox(width: 8),
                    ...categories.map((cat) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(cat.name),
                            selected: _selectedCategoryId == cat.id,
                            onSelected: (_) {
                              setState(() => _selectedCategoryId =
                                  _selectedCategoryId == cat.id ? null : cat.id);
                              context.read<ExpensesBloc>().add(
                                    ExpensesFilterByCategoryRequested(
                                      _selectedCategoryId,
                                    ),
                                  );
                            },
                          ),
                        )),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 4),

          // Expense list
          Expanded(
            child: BlocBuilder<ExpensesBloc, RealtimeState<ExpensesData>>(
              builder: (context, state) {
                if (state is RealtimeLoading<ExpensesData>) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is RealtimeError<ExpensesData>) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.alertTriangle,
                            size: 48, color: colorScheme.error),
                        const SizedBox(height: 16),
                        Text(
                          'common.error'.tr(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context
                              .read<ExpensesBloc>()
                              .add(const RealtimeRefreshRequested()),
                          child: Text('common.retry'.tr()),
                        ),
                      ],
                    ),
                  );
                }

                if (state is RealtimeSuccess<ExpensesData>) {
                  final expenses = state.data.expenses;

                  if (expenses.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.receipt,
                                size: 64,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text(
                              'expenses.empty'.tr(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'expenses.empty_hint'.tr(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return BlocBuilder<ExpenseCategoriesBloc,
                      RealtimeState<List<ExpenseCategory>>>(
                    builder: (context, catState) {
                      final categories =
                          catState is RealtimeSuccess<List<ExpenseCategory>>
                              ? catState.data
                              : <ExpenseCategory>[];
                      final categoryMap = {
                        for (final c in categories) c.id: c.name
                      };

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: expenses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final expense = expenses[index];
                          return _ExpenseCard(
                            expense: expense,
                            categoryName: categoryMap[expense.categoryId] ??
                                'expenses.unknown_category'.tr(),
                            currencyService: cs,
                            onTap: () =>
                                context.push('/expenses/${expense.id}/edit'),
                            onDelete: () {
                              context.read<ExpensesBloc>().add(
                                    ExpenseDeleteRequested(expense.id),
                                  );
                            },
                          );
                        },
                      );
                    },
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final Expense expense;
  final String categoryName;
  final CurrencyService currencyService;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ExpenseCard({
    required this.expense,
    required this.categoryName,
    required this.currencyService,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final amountDisplay = currencyService.formatCents(expense.amountCents.toBigInt().toInt());
    final dateStr = _formatDate(expense.expenseDate);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.receipt,
                  color: colorScheme.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.description,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            categoryName,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colorScheme.onSecondaryContainer,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            dateStr,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Amount
              Text(
                amountDisplay,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              // Delete menu
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') {
                    _confirmDelete(context);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(LucideIcons.trash2, size: 18, color: colorScheme.error),
                        const SizedBox(width: 8),
                        Text('common.delete'.tr()),
                      ],
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

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('expenses.delete_confirm_title'.tr()),
        content: Text('expenses.delete_confirm_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              onDelete();
            },
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
