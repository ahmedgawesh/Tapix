import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/size_entity.dart';
import '../bloc/sizes_bloc.dart';
import '../bloc/sizes_event.dart';

class SizesScreen extends StatelessWidget {
  final SizesBloc? bloc;

  const SizesScreen({super.key, this.bloc});

  @override
  Widget build(BuildContext context) {
    final providedBloc = bloc;
    if (providedBloc != null) {
      providedBloc.add(const LoadSizes());
      return BlocProvider.value(
        value: providedBloc,
        child: const _SizesView(),
      );
    }

    return BlocProvider(
      create: (context) => sl<SizesBloc>()..add(const LoadSizes()),
      child: const _SizesView(),
    );
  }
}

class _SizesView extends StatefulWidget {
  const _SizesView();

  @override
  State<_SizesView> createState() => _SizesViewState();
}

class _SizesViewState extends State<_SizesView> {
  final TextEditingController _searchController = TextEditingController();
  Map<int, int> _productCounts = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<SizesBloc>().add(SearchSizes(query));
  }

  Future<void> _loadProductCounts(List<Size> sizes) async {
    final bloc = context.read<SizesBloc>();
    final counts = await bloc.getProductCounts(sizes);
    if (mounted) {
      setState(() {
        _productCounts = counts;
      });
    }
  }

  void _showDeleteDialog(BuildContext context, Size size) {
    final productCount = _productCounts[size.id] ?? 0;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('sizes.delete_confirm_title'.tr()),
        content: productCount > 0
            ? Text('sizes.delete_with_products'.tr(args: [size.name, productCount.toString()]))
            : Text('sizes.delete_confirm_message'.tr(args: [size.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('sizes.cancel'.tr()),
          ),
          if (productCount == 0)
            TextButton(
              onPressed: () {
                context.read<SizesBloc>().add(DeleteSize(size.id));
                Navigator.of(dialogContext).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text('sizes.delete'.tr()),
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
        title: Text('sizes.title'.tr()),
        centerTitle: !isDesktop,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => context.push('/products/sizes/new'),
            tooltip: 'sizes.add_size'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'sizes.search_hint'.tr(),
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
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: BlocConsumer<SizesBloc, RealtimeState<List<Size>>>(
                listener: (context, state) {
                  if (state is RealtimeError<List<Size>>) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(state.error.toString()),
                        backgroundColor: colorScheme.error,
                      ),
                    );
                  }
                  if (state is RealtimeSuccess<List<Size>>) {
                    _loadProductCounts(state.data);
                  }
                },
                builder: (context, state) {
                  if (state is RealtimeLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is RealtimeSuccess<List<Size>>) {
                    final sizes = state.data;

                    if (sizes.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.ruler,
                              size: 64,
                              color: colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty
                                  ? 'sizes.no_sizes'.tr()
                                  : 'sizes.no_sizes'.tr(),
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            if (_searchController.text.isEmpty)
                              TextButton.icon(
                                onPressed: () => context.push('/products/sizes/new'),
                                icon: const Icon(LucideIcons.plus),
                                label: Text('sizes.add_first_size'.tr()),
                              ),
                          ],
                        ),
                      );
                    }

                    if (isDesktop) {
                      return _buildDesktopGrid(sizes, colorScheme);
                    } else if (isTablet) {
                      return _buildTabletGrid(sizes, colorScheme);
                    } else {
                      return _buildMobileList(sizes, colorScheme);
                    }
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileList(List<Size> sizes, ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: sizes.length,
      itemBuilder: (context, index) {
        final size = sizes[index];
        final productCount = _productCounts[size.id] ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                LucideIcons.ruler,
                color: colorScheme.onPrimaryContainer,
                size: 20,
              ),
            ),
            title: Text(
              size.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (size.description != null && size.description!.isNotEmpty)
                  Text(size.description!),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: size.isActive
                            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                            : colorScheme.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        size.isActive ? 'sizes.active'.tr() : 'sizes.inactive'.tr(),
                        style: TextStyle(
                          fontSize: 12,
                          color: size.isActive
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'sizes.product_count'.tr(args: [productCount.toString()]),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (value) {
                if (value == 'edit') {
                  context.push('/products/sizes/${size.id}/edit');
                } else if (value == 'delete') {
                  _showDeleteDialog(context, size);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(LucideIcons.edit, size: 18),
                      const SizedBox(width: 8),
                      Text('sizes.edit_size'.tr()),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(LucideIcons.trash2, size: 18, color: colorScheme.error),
                      const SizedBox(width: 8),
                      Text(
                        'sizes.delete'.tr(),
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () => context.push('/products/sizes/${size.id}/edit'),
          ),
        );
      },
    );
  }

  Widget _buildTabletGrid(List<Size> sizes, ColorScheme colorScheme) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.5,
      ),
      itemCount: sizes.length,
      itemBuilder: (context, index) {
        final size = sizes[index];
        final productCount = _productCounts[size.id] ?? 0;

        return _buildSizeCard(size, productCount, colorScheme);
      },
    );
  }

  Widget _buildDesktopGrid(List<Size> sizes, ColorScheme colorScheme) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
        childAspectRatio: 2.5,
      ),
      itemCount: sizes.length,
      itemBuilder: (context, index) {
        final size = sizes[index];
        final productCount = _productCounts[size.id] ?? 0;

        return _buildSizeCard(size, productCount, colorScheme);
      },
    );
  }

  Widget _buildSizeCard(Size size, int productCount, ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => context.push('/products/sizes/${size.id}/edit'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    child: Icon(
                      LucideIcons.ruler,
                      color: colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          size.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (size.description != null && size.description!.isNotEmpty)
                          Text(
                            size.description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(LucideIcons.moreVertical),
                    onSelected: (value) {
                      if (value == 'edit') {
                        context.push('/products/sizes/${size.id}/edit');
                      } else if (value == 'delete') {
                        _showDeleteDialog(context, size);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(LucideIcons.edit, size: 18),
                            const SizedBox(width: 8),
                            Text('sizes.edit_size'.tr()),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(LucideIcons.trash2, size: 18, color: colorScheme.error),
                            const SizedBox(width: 8),
                            Text(
                              'sizes.delete'.tr(),
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: size.isActive
                          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                          : colorScheme.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      size.isActive ? 'sizes.active'.tr() : 'sizes.inactive'.tr(),
                      style: TextStyle(
                        fontSize: 12,
                        color: size.isActive
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'sizes.product_count'.tr(args: [productCount.toString()]),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
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
