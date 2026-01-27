import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../bloc/product_variants_bloc.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/colors_event.dart';
import '../bloc/sizes_bloc.dart';
import '../bloc/sizes_event.dart';

class VariantsScreen extends StatelessWidget {
  const VariantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => sl<ProductVariantsBloc>()..add(const AllVariantsInitialized()),
        ),
        BlocProvider(
          create: (context) => sl<ColorsBloc>()..add(const LoadColors()),
        ),
        BlocProvider(
          create: (context) => sl<SizesBloc>()..add(const LoadSizes()),
        ),
      ],
      child: const _VariantsView(),
    );
  }
}

class _VariantsView extends StatefulWidget {
  const _VariantsView();

  @override
  State<_VariantsView> createState() => _VariantsViewState();
}

class _VariantsViewState extends State<_VariantsView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    final isTablet = width >= 600 && width < 1024;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/products');
            }
          },
          tooltip: 'common.back'.tr(),
        ),
        title: Text('variants.title'.tr()),
        centerTitle: !isDesktop,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'variants.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
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
              child: BlocBuilder<ProductVariantsBloc, RealtimeState<List<ProductVariant>>>(
                builder: (context, variantsState) {
                  return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
                    builder: (context, colorsState) {
                      return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
                        builder: (context, sizesState) {
                          List<ProductVariant>? variants;
                          if (variantsState is RealtimeSuccess<List<ProductVariant>>) {
                            variants = variantsState.data;
                          } else if (variantsState is RealtimeLoading<List<ProductVariant>>) {
                            variants = variantsState.previousData;
                          } else if (variantsState is RealtimeError<List<ProductVariant>>) {
                            variants = variantsState.previousData;
                          } else if (variantsState is RealtimeOptimistic<List<ProductVariant>>) {
                            variants = variantsState.optimisticData;
                          }

                          if (variantsState is RealtimeLoading<List<ProductVariant>> && variants == null) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final colors = colorsState is RealtimeSuccess<List<ProductColor>>
                              ? colorsState.data
                              : <ProductColor>[];
                          final sizes = sizesState is RealtimeSuccess<List<Size>> ? sizesState.data : <Size>[];

                          final colorNameById = {for (final c in colors) c.id: c.name};
                          final sizeNameById = {for (final s in sizes) s.id: s.name};

                          final query = _searchController.text.trim().toLowerCase();
                          final items = (variants ?? <ProductVariant>[]).where((v) {
                            if (query.isEmpty) return true;
                            final barcode = (v.barcode ?? '').toLowerCase();
                            final sku = (v.sku ?? '').toLowerCase();
                            final color = v.colorId == null
                                ? ''
                                : (colorNameById[v.colorId!] ?? '').toLowerCase();
                            final size = v.sizeId == null
                                ? ''
                                : (sizeNameById[v.sizeId!] ?? '').toLowerCase();
                            return barcode.contains(query) ||
                                sku.contains(query) ||
                                color.contains(query) ||
                                size.contains(query);
                          }).toList();

                          if (items.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.layers,
                                    size: 64,
                                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    query.isEmpty ? 'variants.empty'.tr() : 'variants.no_results'.tr(),
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                                        ),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (isDesktop) {
                            return _buildGrid(
                              items,
                              colorNameById: colorNameById,
                              sizeNameById: sizeNameById,
                              columns: 3,
                            );
                          }
                          if (isTablet) {
                            return _buildGrid(
                              items,
                              colorNameById: colorNameById,
                              sizeNameById: sizeNameById,
                              columns: 2,
                            );
                          }
                          return _buildList(
                            items,
                            colorNameById: colorNameById,
                            sizeNameById: sizeNameById,
                          );
                        },
                      );
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

  Widget _buildList(
    List<ProductVariant> variants, {
    required Map<int, String> colorNameById,
    required Map<int, String> sizeNameById,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: variants.length,
      itemBuilder: (context, index) {
        final v = variants[index];
        final colorName = v.colorId == null ? null : colorNameById[v.colorId!];
        final sizeName = v.sizeId == null ? null : sizeNameById[v.sizeId!];

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              LucideIcons.layers,
              color: colorScheme.onSurfaceVariant,
            ),
            title: Text(
              v.sku?.isNotEmpty == true ? v.sku! : 'product_form.variant_item_title'.tr(args: ['${v.id}']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('product_form.variant_item_stock'.tr(args: ['${v.stockQuantity}'])),
                if (v.barcode?.isNotEmpty == true)
                  Text('product_form.variant_item_barcode'.tr(args: [v.barcode!])),
                if (colorName != null || sizeName != null)
                  Text(
                    'variants.color_size'.tr(args: [colorName ?? '—', sizeName ?? '—']),
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid(
    List<ProductVariant> variants, {
    required Map<int, String> colorNameById,
    required Map<int, String> sizeNameById,
    required int columns,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.8,
      ),
      itemCount: variants.length,
      itemBuilder: (context, index) {
        final v = variants[index];
        final colorName = v.colorId == null ? null : colorNameById[v.colorId!];
        final sizeName = v.sizeId == null ? null : sizeNameById[v.sizeId!];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(LucideIcons.layers, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        v.sku?.isNotEmpty == true ? v.sku! : 'product_form.variant_item_title'.tr(args: ['${v.id}']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'product_form.variant_item_stock'.tr(args: ['${v.stockQuantity}']),
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      if (v.barcode?.isNotEmpty == true)
                        Text(
                          'product_form.variant_item_barcode'.tr(args: [v.barcode!]),
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (colorName != null || sizeName != null)
                        Text(
                          'variants.color_size'.tr(args: [colorName ?? '—', sizeName ?? '—']),
                          style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
