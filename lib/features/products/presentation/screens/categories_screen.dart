import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/category_entity.dart';
import '../bloc/categories_bloc.dart';
import '../bloc/categories_event.dart';

class CategoriesScreen extends StatelessWidget {
  final bool isPicker;

  const CategoriesScreen({
    super.key,
    this.isPicker = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<CategoriesBloc>()..add(const LoadCategories()),
      child: _CategoriesView(isPicker: isPicker),
    );
  }
}

class _CategoriesView extends StatefulWidget {
  final bool isPicker;

  const _CategoriesView({required this.isPicker});

  @override
  State<_CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<_CategoriesView> {
  final TextEditingController _searchController = TextEditingController();
  Map<int, int> _productCounts = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<CategoriesBloc>().add(SearchCategories(query));
  }

  Future<void> _loadProductCounts(List<Category> categories) async {
    final bloc = context.read<CategoriesBloc>();
    final counts = await bloc.getProductCounts(categories);
    if (mounted) {
      setState(() {
        _productCounts = counts;
      });
    }
  }

  void _showDeleteDialog(BuildContext context, Category category) {
    final productCount = _productCounts[category.id] ?? 0;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('categories.delete_confirm_title'.tr()),
        content: productCount > 0
            ? Text('categories.delete_with_products'.tr(args: [productCount.toString()]))
            : Text('categories.delete_confirm_message'.tr(args: [category.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('common.cancel'.tr()),
          ),
          if (productCount == 0)
            TextButton(
              onPressed: () {
                context.read<CategoriesBloc>().add(DeleteCategory(category.id));
                Navigator.of(dialogContext).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text('common.delete'.tr()),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final isTablet = MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width < 1024;

    return Scaffold(
      appBar: AppBar(
        title: Text('categories.title'.tr()),
        centerTitle: !isDesktop,
        actions: [
          if (!widget.isPicker)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              onPressed: () => context.push('/products/categories/new'),
              tooltip: 'categories.add_category'.tr(),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'categories.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Expanded(
              child: BlocConsumer<CategoriesBloc, RealtimeState<List<Category>>>(
                listener: (context, state) {
                  if (state is RealtimeError<List<Category>>) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(state.error.toString()),
                        backgroundColor: colorScheme.error,
                      ),
                    );
                  }
                },
                builder: (context, state) {
                  if (state is RealtimeLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is RealtimeError<List<Category>>) {
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
                            'categories.error_loading'.tr(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.error.toString(),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                          ),
                        ],
                      ),
                    );
                  }

                  List<Category>? categories;
                  if (state is RealtimeSuccess<List<Category>>) {
                    categories = state.data;
                  } else if (state is RealtimeOptimistic<List<Category>>) {
                    categories = state.optimisticData;
                  }

                  if (categories == null || categories.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.folderOpen,
                            size: 64,
                            color: colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'categories.no_categories'.tr(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'categories.add_first_category'.tr(),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => context.push('/products/categories/new'),
                            icon: const Icon(LucideIcons.plus),
                            label: Text('categories.add_category'.tr()),
                          ),
                        ],
                      ),
                    );
                  }

                  _loadProductCounts(categories);

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (isDesktop) {
                        return _buildDesktopGrid(context, categories!);
                      } else if (isTablet) {
                        return _buildTabletGrid(context, categories!);
                      } else {
                        return _buildMobileList(context, categories!);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileList(BuildContext context, List<Category> categories) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _buildCategoryCard(context, category);
      },
    );
  }

  Widget _buildTabletGrid(BuildContext context, List<Category> categories) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _buildCategoryCard(context, category);
      },
    );
  }

  Widget _buildDesktopGrid(BuildContext context, List<Category> categories) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 3,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return _buildCategoryCard(context, category);
      },
    );
  }

  Widget _buildCategoryCard(BuildContext context, Category category) {
    final colorScheme = Theme.of(context).colorScheme;
    final productCount = _productCounts[category.id] ?? 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: () {
          if (widget.isPicker) {
            context.pop(category.id);
            return;
          }
          context.push('/products/categories/${category.id}/edit');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.folder,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MarqueeText(
                      text: category.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                    ),
                    if (category.description != null && category.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _MarqueeText(
                        text: category.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                        maxLines: 1,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'categories.product_count'.tr(args: [productCount.toString()]),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical),
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(LucideIcons.edit, size: 18),
                        const SizedBox(width: 12),
                        Text('common.edit'.tr()),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(LucideIcons.trash2, size: 18, color: colorScheme.error),
                        const SizedBox(width: 12),
                        Text(
                          'common.delete'.tr(),
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (widget.isPicker) return;
                  if (value == 'edit') {
                    context.push('/products/categories/${category.id}/edit');
                  } else if (value == 'delete') {
                    _showDeleteDialog(context, category);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;

  const _MarqueeText({
    required this.text,
    this.style,
    this.maxLines = 1,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final ScrollController _controller = ScrollController();
  bool _isDisposed = false;
  double _lastMaxScrollExtent = 0;

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _animateIfNeeded() async {
    if (_isDisposed) return;
    if (!_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) return;
    if (_lastMaxScrollExtent == max) return;
    _lastMaxScrollExtent = max;

    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_isDisposed) return;
    if (!_controller.hasClients) return;

    while (!_isDisposed && _controller.hasClients) {
      final maxScroll = _controller.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      final durationMs = (maxScroll * 25).clamp(900, 6000).toInt();
      await _controller.animateTo(
        maxScroll,
        duration: Duration(milliseconds: durationMs),
        curve: Curves.linear,
      );
      if (_isDisposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_isDisposed) return;
      await _controller.animateTo(
        0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
      );
      if (_isDisposed) return;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animateIfNeeded();
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: widget.maxLines,
              overflow: TextOverflow.visible,
              softWrap: false,
            ),
          ),
        );
      },
    );
  }
}
