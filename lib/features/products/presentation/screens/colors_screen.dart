import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/product_color_entity.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/colors_event.dart';

class ColorsScreen extends StatelessWidget {
  const ColorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<ColorsBloc>()..add(const LoadColors()),
      child: const _ColorsView(),
    );
  }
}

class _ColorsView extends StatefulWidget {
  const _ColorsView();

  @override
  State<_ColorsView> createState() => _ColorsViewState();
}

class _ColorsViewState extends State<_ColorsView> {
  final TextEditingController _searchController = TextEditingController();
  Map<int, int> _productCounts = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<ColorsBloc>().add(SearchColors(query));
  }

  Future<void> _loadProductCounts(List<ProductColor> colors) async {
    final bloc = context.read<ColorsBloc>();
    final counts = await bloc.getProductCounts(colors);
    if (mounted) {
      setState(() {
        _productCounts = counts;
      });
    }
  }

  void _showDeleteDialog(BuildContext context, ProductColor color) {
    final productCount = _productCounts[color.id] ?? 0;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('colors.delete_confirm_title'.tr()),
        content: productCount > 0
            ? Text(
                'colors.delete_with_products'.tr(
                  args: [color.name, productCount.toString()],
                ),
              )
            : Text('colors.delete_confirm_message'.tr(args: [color.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('colors.cancel'.tr()),
          ),
          if (productCount == 0)
            TextButton(
              onPressed: () {
                context.read<ColorsBloc>().add(DeleteColor(color.id));
                Navigator.of(dialogContext).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text('colors.delete'.tr()),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final isTablet =
        MediaQuery.of(context).size.width >= 600 &&
        MediaQuery.of(context).size.width < 1024;

    return Scaffold(
      appBar: AppBar(
        title: Text('colors.title'.tr()),
        centerTitle: !isDesktop,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => context.push('/products/colors/new'),
            tooltip: 'colors.add_color'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'colors.search_hint'.tr(),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.push('/products/colors/magazine'),
                      icon: const Icon(LucideIcons.palette),
                      label: Text('colors.magazine.open'.tr()),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child:
                  BlocConsumer<ColorsBloc, RealtimeState<List<ProductColor>>>(
                    listener: (context, state) {
                      if (state is RealtimeError<List<ProductColor>>) {
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

                      if (state is RealtimeError<List<ProductColor>>) {
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
                                'colors.error_loading'.tr(),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                state.error.toString(),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        );
                      }

                      List<ProductColor>? colors;
                      if (state is RealtimeSuccess<List<ProductColor>>) {
                        colors = state.data;
                      } else if (state
                          is RealtimeOptimistic<List<ProductColor>>) {
                        colors = state.optimisticData;
                      }

                      if (colors == null || colors.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.palette,
                                size: 64,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'colors.no_colors'.tr(),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'colors.add_first_color'.tr(),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: () =>
                                    context.push('/products/colors/new'),
                                icon: const Icon(LucideIcons.plus),
                                label: Text('colors.add_color'.tr()),
                              ),
                            ],
                          ),
                        );
                      }

                      _loadProductCounts(colors);

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          if (isDesktop) {
                            return _buildDesktopGrid(context, colors!);
                          } else if (isTablet) {
                            return _buildTabletGrid(context, colors!);
                          } else {
                            return _buildMobileList(context, colors!);
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

  Widget _buildMobileList(BuildContext context, List<ProductColor> colors) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: colors.length,
      itemBuilder: (context, index) {
        final color = colors[index];
        return _buildColorCard(context, color);
      },
    );
  }

  Widget _buildTabletGrid(BuildContext context, List<ProductColor> colors) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: colors.length,
      itemBuilder: (context, index) {
        final color = colors[index];
        return _buildColorCard(context, color);
      },
    );
  }

  Widget _buildDesktopGrid(BuildContext context, List<ProductColor> colors) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 3,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: colors.length,
      itemBuilder: (context, index) {
        final color = colors[index];
        return _buildColorCard(context, color);
      },
    );
  }

  Widget _buildColorCard(BuildContext context, ProductColor color) {
    final colorScheme = Theme.of(context).colorScheme;
    final productCount = _productCounts[color.id] ?? 0;

    Color? displayColor;
    if (color.hexCode != null && color.hexCode!.isNotEmpty) {
      try {
        final hexString = color.hexCode!.replaceAll('#', '');
        displayColor = Color(int.parse('FF$hexString', radix: 16));
      } catch (e) {
        displayColor = null;
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: () => context.push('/products/colors/${color.id}/edit'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: displayColor ?? colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: displayColor == null
                    ? Icon(
                        LucideIcons.palette,
                        color: colorScheme.onPrimaryContainer,
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      color.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (color.hexCode != null && color.hexCode!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        color.hexCode!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'colors.product_count'.tr(
                        args: [productCount.toString()],
                      ),
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
                        Icon(
                          LucideIcons.trash2,
                          size: 18,
                          color: colorScheme.error,
                        ),
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
                  if (value == 'edit') {
                    context.push('/products/colors/${color.id}/edit');
                  } else if (value == 'delete') {
                    _showDeleteDialog(context, color);
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
