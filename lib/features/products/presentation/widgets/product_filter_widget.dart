import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../bloc/products_bloc.dart';

class ProductFilterWidget extends StatelessWidget {
  final VoidCallback onClearAll;
  final int activeFiltersCount;
  final int? selectedCategoryId;
  final String? selectedStockStatus;
  final bool? selectedIsActive;

  const ProductFilterWidget({
    super.key,
    required this.onClearAll,
    required this.activeFiltersCount,
    this.selectedCategoryId,
    this.selectedStockStatus,
    this.selectedIsActive,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (activeFiltersCount > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ActionChip(
                avatar: const Icon(LucideIcons.x, size: 16),
                label: Text('products_clear_all_filters'.tr()),
                onPressed: onClearAll,
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          FilterChip(
            label: Text('products_filter_category'.tr()),
            selected: selectedCategoryId != null,
            onSelected: (bool selected) {
              _showCategoryFilter(context);
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text('products_filter_stockStatus'.tr()),
            selected: selectedStockStatus != null,
            onSelected: (bool selected) {
              _showStockStatusFilter(context);
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text('products_filter_status'.tr()),
            selected: selectedIsActive != true,
            onSelected: (bool selected) {
              _showStatusFilter(context);
            },
          ),
        ],
      ),
    );
  }

  void _showCategoryFilter(BuildContext context) {
    () async {
      final selectedId = await context.push<int?>('/products/categories/pick');
      if (!context.mounted) return;
      context.read<ProductsBloc>().add(
        ProductFilterRequested(categoryId: selectedId),
      );
    }();
  }

  void _showStockStatusFilter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => BlocProvider.value(
        value: context.read<ProductsBloc>(),
        child: _StockStatusFilterSheet(
          selectedStockStatus: selectedStockStatus,
        ),
      ),
    );
  }

  void _showStatusFilter(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => BlocProvider.value(
        value: context.read<ProductsBloc>(),
        child: _StatusFilterSheet(selectedIsActive: selectedIsActive),
      ),
    );
  }
}

class _CustomRadioTile<T> extends StatelessWidget {
  final Widget title;
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;

  const _CustomRadioTile({
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged?.call(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _CustomRadio<T>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
            ),
            const SizedBox(width: 16),
            Expanded(child: title),
          ],
        ),
      ),
    );
  }
}

class _CustomRadio<T> extends StatelessWidget {
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;

  const _CustomRadio({
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    final color = Theme.of(context).primaryColor;
    final unselectedColor = Theme.of(context).unselectedWidgetColor;

    return GestureDetector(
      onTap: () => onChanged?.call(value),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? color : unselectedColor,
            width: 2,
          ),
        ),
        child: isSelected
            ? Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _StatusFilterSheet extends StatelessWidget {
  final bool? selectedIsActive;

  const _StatusFilterSheet({this.selectedIsActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'products_filter_status'.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _CustomRadioTile<bool?>(
            title: Text('products_status_all'.tr()),
            value: null,
            groupValue: selectedIsActive,
            onChanged: (value) {
              context.read<ProductsBloc>().add(
                const ProductFilterRequested(isActive: null),
              );
              Navigator.pop(context);
            },
          ),
          _CustomRadioTile<bool?>(
            title: Text('products_status_active'.tr()),
            value: true,
            groupValue: selectedIsActive,
            onChanged: (value) {
              context.read<ProductsBloc>().add(
                const ProductFilterRequested(isActive: true),
              );
              Navigator.pop(context);
            },
          ),
          _CustomRadioTile<bool?>(
            title: Text('products_status_inactive'.tr()),
            value: false,
            groupValue: selectedIsActive,
            onChanged: (value) {
              context.read<ProductsBloc>().add(
                const ProductFilterRequested(isActive: false),
              );
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _StockStatusFilterSheet extends StatelessWidget {
  final String? selectedStockStatus;

  const _StockStatusFilterSheet({this.selectedStockStatus});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'products_filter_stockStatus'.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _CustomRadioTile<String?>(
            title: Text('products_all_stock'.tr()),
            value: null,
            groupValue: selectedStockStatus,
            onChanged: (value) {
              context.read<ProductsBloc>().add(
                const ProductFilterRequested(stockStatus: null),
              );
              Navigator.pop(context);
            },
          ),
          _CustomRadioTile<String?>(
            title: Text('products_out_of_stock'.tr()),
            value: 'out_of_stock',
            groupValue: selectedStockStatus,
            onChanged: (value) {
              context.read<ProductsBloc>().add(
                const ProductFilterRequested(stockStatus: 'out_of_stock'),
              );
              Navigator.pop(context);
            },
          ),
          _CustomRadioTile<String?>(
            title: Text('products_low_stock'.tr()),
            value: 'low_stock',
            groupValue: selectedStockStatus,
            onChanged: (value) {
              context.read<ProductsBloc>().add(
                const ProductFilterRequested(stockStatus: 'low_stock'),
              );
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
