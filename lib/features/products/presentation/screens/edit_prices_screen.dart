import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../bloc/edit_prices_bloc.dart';
import '../bloc/edit_prices_event.dart';
import '../bloc/edit_prices_state.dart';
import '../widgets/price_edit_row.dart';

class EditPricesScreen extends StatelessWidget {
  const EditPricesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => EditPricesBloc(sl()),
      child: const _EditPricesView(),
    );
  }
}

class _EditPricesView extends StatefulWidget {
  const _EditPricesView();

  @override
  State<_EditPricesView> createState() => _EditPricesViewState();
}

class _EditPricesViewState extends State<_EditPricesView> {
  final _searchController = TextEditingController();
  int? _selectedCategoryId;
  String? _selectedStockStatus;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    context.read<EditPricesBloc>().add(EditPricesFilterChanged(
      categoryId: _selectedCategoryId,
      stockStatus: _selectedStockStatus,
      searchQuery: _searchController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currencyService = sl<CurrencyService>();

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
        title: BlocBuilder<EditPricesBloc, RealtimeState<EditPricesStateData>>(
          builder: (context, state) {
            if (state is RealtimeSuccess<EditPricesStateData>) {
              final selectedCount = state.data.selectedProductIds.length;
              if (selectedCount > 0) {
                return Text('$selectedCount ${'edit_prices.selected'.tr()}');
              }
            }
            return Text('edit_prices.title'.tr());
          },
        ),
        centerTitle: true,
        actions: [
          BlocBuilder<EditPricesBloc, RealtimeState<EditPricesStateData>>(
            builder: (context, state) {
              final bloc = context.read<EditPricesBloc>();
              final hasUnsaved = state is RealtimeSuccess<EditPricesStateData> 
                  ? state.data.hasUnsavedChanges 
                  : false;
              
              return Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.undo),
                    onPressed: bloc.canUndo
                        ? () => bloc.add(const EditPricesUndoRequested())
                        : null,
                    tooltip: 'edit_prices.undo'.tr(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo),
                    onPressed: bloc.canRedo
                        ? () => bloc.add(const EditPricesRedoRequested())
                        : null,
                    tooltip: 'edit_prices.redo'.tr(),
                  ),
                  BlocBuilder<EditPricesBloc, RealtimeState<EditPricesStateData>>(
                    builder: (context, state) {
                      if (state is RealtimeSuccess<EditPricesStateData>) {
                        final allSelected = state.data.selectedProductIds.length == state.data.products.length && state.data.products.isNotEmpty;
                        return IconButton(
                          icon: Icon(allSelected ? Icons.check_box : Icons.check_box_outline_blank),
                          onPressed: () => bloc.add(EditPricesSelectAllToggled(selectAll: !allSelected)),
                          tooltip: allSelected ? 'edit_prices.deselect_all'.tr() : 'edit_prices.select_all'.tr(),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  if (hasUnsaved) ...[
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _showDiscardDialog(context),
                      tooltip: 'edit_prices.discard'.tr(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.save),
                      onPressed: () => bloc.add(const EditPricesSaveChanges()),
                      tooltip: 'edit_prices.save'.tr(),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              children: [
                // Search field
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'edit_prices.search_hint'.tr(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _onFilterChanged();
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (_) => _onFilterChanged(),
                ),
                const SizedBox(height: 12),
                // Filter chips
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'edit_prices.filter_stock'.tr(),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text('edit_prices.all_stock'.tr()),
                          ),
                          DropdownMenuItem(
                            value: 'in_stock',
                            child: Text('edit_prices.in_stock'.tr()),
                          ),
                          DropdownMenuItem(
                            value: 'low_stock',
                            child: Text('edit_prices.low_stock'.tr()),
                          ),
                          DropdownMenuItem(
                            value: 'out_of_stock',
                            child: Text('edit_prices.out_of_stock'.tr()),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedStockStatus = value);
                          _onFilterChanged();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Product list
          Expanded(
            child: BlocBuilder<EditPricesBloc, RealtimeState<EditPricesStateData>>(
              builder: (context, state) {
                if (state is RealtimeLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is RealtimeError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                        const SizedBox(height: 16),
                        Text(
                          'edit_prices.error_loading'.tr(),
                          style: TextStyle(color: colorScheme.error),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            context.read<EditPricesBloc>().add(const EditPricesLoadProducts());
                          },
                          child: Text('common.retry'.tr()),
                        ),
                      ],
                    ),
                  );
                }

                if (state is RealtimeSuccess<EditPricesStateData>) {
                  final products = state.data.products;

                  if (products.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'edit_prices.no_products'.tr(),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final isSelected = state.data.selectedProductIds.contains(product.id);
                      return PriceEditRow(
                        key: ValueKey(product.id),
                        product: product,
                        currencyService: currencyService,
                        isSelected: isSelected,
                        onSelectionChanged: (selected) {
                          context.read<EditPricesBloc>().add(
                            EditPricesProductSelectionToggled(
                              productId: product.id,
                              isSelected: selected ?? false,
                            ),
                          );
                        },
                        onPriceChanged: (newPrice, isWholesale) {
                          context.read<EditPricesBloc>().add(
                            EditPricesPriceUpdated(
                              productId: product.id,
                              newPrice: newPrice,
                              isWholesale: isWholesale,
                            ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBulkAdjustmentDialog(context),
        icon: const Icon(Icons.edit),
        label: Text('edit_prices.bulk_adjust'.tr()),
      ),
    );
  }

  void _showBulkAdjustmentDialog(BuildContext context) {
    final bloc = context.read<EditPricesBloc>();
    final valueController = TextEditingController();
    String selectedType = 'percentage_increase';
    String selectedPriceType = 'selling';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('edit_prices.bulk_adjust'.tr()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedPriceType,
                decoration: InputDecoration(
                  labelText: 'edit_prices.price_type'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'cost',
                    child: Text('edit_prices.cost_price'.tr()),
                  ),
                  DropdownMenuItem(
                    value: 'selling',
                    child: Text('edit_prices.selling_price'.tr()),
                  ),
                  DropdownMenuItem(
                    value: 'wholesale',
                    child: Text('edit_prices.wholesale_price'.tr()),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) selectedPriceType = value;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: InputDecoration(
                  labelText: 'edit_prices.adjustment_type'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'percentage_increase',
                    child: Text('edit_prices.percentage_increase'.tr()),
                  ),
                  DropdownMenuItem(
                    value: 'percentage_decrease',
                    child: Text('edit_prices.percentage_decrease'.tr()),
                  ),
                  DropdownMenuItem(
                    value: 'fixed_increase',
                    child: Text('edit_prices.fixed_increase'.tr()),
                  ),
                  DropdownMenuItem(
                    value: 'fixed_decrease',
                    child: Text('edit_prices.fixed_decrease'.tr()),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) selectedType = value;
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: valueController,
                decoration: InputDecoration(
                  labelText: 'edit_prices.value'.tr(),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              final value = Decimal.tryParse(valueController.text);
              if (value != null && value > Decimal.zero) {
                final currentState = bloc.state;
                final hasSelection = currentState is RealtimeSuccess<EditPricesStateData> && 
                    currentState.data.selectedProductIds.isNotEmpty;
                
                bloc.add(EditPricesBulkAdjustRequested(
                  adjustmentType: selectedType,
                  value: value,
                  priceType: selectedPriceType,
                  applyToAll: !hasSelection,
                  selectedProductIds: hasSelection ? 
                      currentState.data.selectedProductIds.toList() : 
                      null,
                ));
                Navigator.of(dialogContext).pop();
              }
            },
            child: Text('edit_prices.apply'.tr()),
          ),
        ],
      ),
    );
  }

  void _showDiscardDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('edit_prices.discard_title'.tr()),
        content: Text('edit_prices.discard_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              context.read<EditPricesBloc>().add(const EditPricesDiscardChanges());
              Navigator.of(dialogContext).pop();
            },
            child: Text('edit_prices.discard'.tr()),
          ),
        ],
      ),
    );
  }
}
