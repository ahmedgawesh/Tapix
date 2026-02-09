import 'package:drift/drift.dart' show Value;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/expense_repository.dart';
import '../bloc/expense_categories_bloc.dart';

/// Screen for managing expense categories
class ExpenseCategoriesScreen extends StatelessWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ExpenseCategoriesBloc(sl<ExpenseRepository>()),
      child: const _CategoriesContent(),
    );
  }
}

class _CategoriesContent extends StatelessWidget {
  const _CategoriesContent();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/expenses');
            }
          },
        ),
        title: Text('expenses.categories'.tr()),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCategoryDialog(context),
        tooltip: 'expenses.add_category'.tr(),
        child: const Icon(LucideIcons.plus),
      ),
      body: BlocBuilder<ExpenseCategoriesBloc,
          RealtimeState<List<ExpenseCategory>>>(
        builder: (context, state) {
          if (state is RealtimeLoading<List<ExpenseCategory>>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<List<ExpenseCategory>>) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text('common.error'.tr()),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context
                        .read<ExpenseCategoriesBloc>()
                        .add(const RealtimeRefreshRequested()),
                    child: Text('common.retry'.tr()),
                  ),
                ],
              ),
            );
          }

          if (state is RealtimeSuccess<List<ExpenseCategory>>) {
            final categories = state.data;

            if (categories.isEmpty) {
              return Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.tag,
                          size: 64,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text(
                        'expenses.no_categories'.tr(),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'expenses.no_categories_hint'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final category = categories[index];
                return _CategoryCard(
                  category: category,
                  onEdit: () =>
                      _showCategoryDialog(context, category: category),
                  onToggleActive: () {
                    context.read<ExpenseCategoriesBloc>().add(
                          ExpenseCategoryToggleActiveRequested(category),
                        );
                  },
                  onDelete: () => _confirmDelete(context, category),
                );
              },
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  void _showCategoryDialog(BuildContext context,
      {ExpenseCategory? category}) {
    final nameController = TextEditingController(text: category?.name ?? '');
    final descController =
        TextEditingController(text: category?.description ?? '');
    final formKey = GlobalKey<FormState>();
    final isEdit = category != null;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            isEdit
                ? 'expenses.edit_category'.tr()
                : 'expenses.add_category'.tr(),
          ),
          content: SizedBox(
            width: 400,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'expenses.category_name'.tr(),
                      prefixIcon: const Icon(LucideIcons.tag),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    autofocus: true,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'expenses.category_name_required'.tr();
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descController,
                    decoration: InputDecoration(
                      labelText: 'expenses.category_description'.tr(),
                      prefixIcon: const Icon(LucideIcons.fileText),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                if (isEdit) {
                  final updated = category.copyWith(
                    name: nameController.text.trim(),
                    description: Value(descController.text.trim().isEmpty
                        ? null
                        : descController.text.trim()),
                    updatedAt: DateTime.now(),
                  );
                  context.read<ExpenseCategoriesBloc>().add(
                        ExpenseCategoryUpdateRequested(updated),
                      );
                } else {
                  context.read<ExpenseCategoriesBloc>().add(
                        ExpenseCategoryCreateRequested(
                          name: nameController.text.trim(),
                          description: descController.text.trim().isEmpty
                              ? null
                              : descController.text.trim(),
                        ),
                      );
                }
                Navigator.pop(dialogContext);
              },
              child: Text(isEdit ? 'common.save'.tr() : 'common.add'.tr()),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, ExpenseCategory category) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('expenses.delete_category_title'.tr()),
        content: Text('expenses.delete_category_message'.tr(args: [category.name])),
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
              context.read<ExpenseCategoriesBloc>().add(
                    ExpenseCategoryDeleteRequested(category.id),
                  );
            },
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final ExpenseCategory category;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            LucideIcons.tag,
            color: colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: Text(
          category.name,
          style: Theme.of(context).textTheme.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: category.description != null
            ? Text(
                category.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              )
            : null,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
              case 'toggle':
                onToggleActive();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  const Icon(LucideIcons.pencil, size: 18),
                  const SizedBox(width: 8),
                  Text('common.edit'.tr()),
                ],
              ),
            ),
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
      ),
    );
  }
}
