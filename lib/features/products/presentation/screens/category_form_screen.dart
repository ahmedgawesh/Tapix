import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../../data/models/category_model.dart';
import '../bloc/categories_bloc.dart';
import '../bloc/categories_event.dart';

class CategoryFormScreen extends StatefulWidget {
  final int? categoryId;

  const CategoryFormScreen({super.key, this.categoryId});

  @override
  State<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends State<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  Category? _category;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasAttemptedSave = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final repository = sl<CategoryRepository>();

    try {
      if (widget.categoryId != null) {
        _category = await repository.getCategoryById(widget.categoryId!);
        if (_category != null) {
          _nameController.text = _category!.name;
          _descriptionController.text = _category!.description ?? '';
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('CategoryFormScreen _loadData failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('categories.error_loading_category'.tr()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveCategory() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _hasAttemptedSave = true;
    });

    try {
      final bloc = context.read<CategoriesBloc>();
      debugPrint(
        'CategoryFormScreen save tapped. isEdit=${widget.categoryId != null}',
      );

      if (widget.categoryId == null) {
        bloc.add(
          CreateCategory(
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            parentId: null,
          ),
        );
      } else {
        final updatedCategory = CategoryModel(
          id: widget.categoryId!,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          parentId: null,
          isActive: _category?.isActive ?? true,
          createdAt: _category?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        );

        bloc.add(UpdateCategory(updatedCategory));
      }
    } catch (e) {
      debugPrint('CategoryFormScreen save failed (exception): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('categories.error_saving'.tr()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final isEdit = widget.categoryId != null;

    return BlocListener<CategoriesBloc, RealtimeState<List<Category>>>(
      listener: (context, state) {
        if (!_hasAttemptedSave) return;
        if (state is RealtimeError<List<Category>>) {
          debugPrint('CategoryFormScreen observed save error: ${state.error}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error.toString()),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }

        // We don't have an explicit "save success" event/state. Heuristic:
        // after save attempt, once we see a success state from stream, pop.
        if (state is RealtimeSuccess<List<Category>> && mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            isEdit
                ? 'categories.edit_category'.tr()
                : 'categories.add_category'.tr(),
          ),
          centerTitle: !isDesktop,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = isDesktop ? 600.0 : double.infinity;

                    return Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: colorScheme.outline.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'categories.basic_info'.tr(),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _nameController,
                                          decoration: InputDecoration(
                                            labelText: 'categories.name'.tr(),
                                            hintText: 'categories.name_hint'
                                                .tr(),
                                            prefixIcon: const Icon(
                                              LucideIcons.tag,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return 'categories.name_required'
                                                  .tr();
                                            }
                                            return null;
                                          },
                                          textInputAction: TextInputAction.next,
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _descriptionController,
                                          decoration: InputDecoration(
                                            labelText: 'categories.description'
                                                .tr(),
                                            hintText:
                                                'categories.description_hint'
                                                    .tr(),
                                            prefixIcon: const Icon(
                                              LucideIcons.alignLeft,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          maxLines: 3,
                                          textInputAction:
                                              TextInputAction.newline,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _isSaving
                                            ? null
                                            : () => context.pop(),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: Text('common.cancel'.tr()),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: _isSaving
                                            ? null
                                            : _saveCategory,
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: _isSaving
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : Text('common.save'.tr()),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
