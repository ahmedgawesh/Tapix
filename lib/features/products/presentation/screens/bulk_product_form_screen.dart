import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection_container.dart';
import '../bloc/bulk_product_bloc.dart';
import '../bloc/categories_bloc.dart';
import '../bloc/categories_event.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/colors_event.dart';
import '../bloc/sizes_bloc.dart';
import '../bloc/sizes_event.dart';
import '../widgets/bulk_product_row.dart';

class BulkProductFormScreen extends StatelessWidget {
  const BulkProductFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => sl<BulkProductBloc>()..add(const BulkProductRowAdded()),
        ),
        BlocProvider(
          create: (context) => sl<ColorsBloc>()..add(const LoadColors()),
        ),
        BlocProvider(
          create: (context) => sl<SizesBloc>()..add(const LoadSizes()),
        ),
        BlocProvider(
          create: (context) => sl<CategoriesBloc>()..add(const LoadCategories()),
        ),
      ],
      child: const _BulkProductFormView(),
    );
  }
}

class _BulkProductFormView extends StatelessWidget {
  const _BulkProductFormView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/products');
            }
          },
          tooltip: 'common.back'.tr(),
        ),
        title: Text('bulk_product.title'.tr()),
        actions: [
          BlocBuilder<BulkProductBloc, BulkProductState>(
            builder: (context, state) {
              if (state is BulkProductEditing) {
                return TextButton.icon(
                  onPressed: () {
                    context.read<BulkProductBloc>().add(const BulkProductReset());
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text('bulk_product.reset'.tr()),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: BlocConsumer<BulkProductBloc, BulkProductState>(
        listener: (context, state) {
          if (state is BulkProductSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'bulk_product.success_message'.tr(args: [
                    state.successCount.toString(),
                    state.totalCount.toString(),
                  ]),
                ),
                backgroundColor: colorScheme.primary,
              ),
            );
            context.go('/products');
          } else if (state is BulkProductError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'bulk_product.error_message'.tr(args: [
                    state.successCount.toString(),
                    state.totalCount.toString(),
                  ]),
                ),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is BulkProductSubmitting) {
            return _buildSubmittingView(context, state);
          }

          if (state is BulkProductEditing) {
            return _buildEditingView(context, state);
          }

          if (state is BulkProductInitial) {
            return Center(
              child: CircularProgressIndicator(
                color: colorScheme.primary,
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: BlocBuilder<BulkProductBloc, BulkProductState>(
        builder: (context, state) {
          if (state is BulkProductEditing) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'add_row',
                  onPressed: () {
                    context.read<BulkProductBloc>().add(const BulkProductRowAdded());
                  },
                  tooltip: 'bulk_product.add_row'.tr(),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 16),
                FloatingActionButton.extended(
                  heroTag: 'submit',
                  onPressed: state.hasValidationErrors
                      ? null
                      : () {
                          context.read<BulkProductBloc>().add(
                                const BulkProductSubmitRequested(),
                              );
                        },
                  icon: const Icon(Icons.save),
                  label: Text('bulk_product.submit'.tr()),
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSubmittingView(BuildContext context, BulkProductSubmitting state) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              value: state.progress,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'bulk_product.submitting'.tr(args: [
                (state.currentIndex + 1).toString(),
                state.totalCount.toString(),
              ]),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: state.progress,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              '${(state.progress * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditingView(BuildContext context, BulkProductEditing state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        final isTablet = constraints.maxWidth >= 768 && constraints.maxWidth < 1024;

        return Column(
          children: [
            _buildHeader(context, state, isDesktop),
            Expanded(
              child: _buildProductList(context, state, isDesktop, isTablet),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, BulkProductEditing state, bool isDesktop) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'bulk_product.products_count'.tr(args: [state.rows.length.toString()]),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (state.hasValidationErrors)
                  Text(
                    'bulk_product.validation_errors'.tr(
                      args: [state.validationErrors.length.toString()],
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                  ),
              ],
            ),
          ),
          if (isDesktop)
            FilledButton.icon(
              onPressed: () {
                context.read<BulkProductBloc>().add(const BulkProductRowAdded());
              },
              icon: const Icon(Icons.add),
              label: Text('bulk_product.add_row'.tr()),
            ),
        ],
      ),
    );
  }

  Widget _buildProductList(
    BuildContext context,
    BulkProductEditing state,
    bool isDesktop,
    bool isTablet,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 100, // Space for FAB
      ),
      itemCount: state.rows.length,
      itemBuilder: (context, index) {
        final row = state.rows[index];
        final errors = state.getErrorsForRow(index);

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: BulkProductRow(
            rowData: row,
            errors: errors,
            isDesktop: isDesktop,
            isTablet: isTablet,
            canRemove: state.rows.length > 1,
            onUpdate: (updates) {
              context.read<BulkProductBloc>().add(
                    BulkProductRowUpdated(
                      rowIndex: index,
                      name: updates['name'] as String?,
                      nameAr: updates['nameAr'] as String?,
                      nameFr: updates['nameFr'] as String?,
                      sku: updates['sku'] as String?,
                      barcode: updates['barcode'] as String?,
                      costCents: updates['costCents'] as Decimal?,
                      priceCents: updates['priceCents'] as Decimal?,
                      wholesalePriceCents: updates['wholesalePriceCents'] as Decimal?,
                      stockQuantity: updates['stockQuantity'] as int?,
                      minQuantity: updates['minQuantity'] as int?,
                      categoryId: updates['categoryId'] as int?,
                      colorId: updates['colorId'] as int?,
                      sizeId: updates['sizeId'] as int?,
                      hasVariants: updates['hasVariants'] as bool?,
                      isTaxable: updates['isTaxable'] as bool?,
                      taxRateBps: updates['taxRateBps'] as int?,
                    ),
                  );
            },
            onRemove: () {
              context.read<BulkProductBloc>().add(BulkProductRowRemoved(index));
            },
          ),
        );
      },
    );
  }
}
