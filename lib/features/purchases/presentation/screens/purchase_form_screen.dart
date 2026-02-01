import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';
import '../../../products/presentation/bloc/products_bloc.dart';
import '../../../products/presentation/bloc/product_variants_bloc.dart';
import '../../../barcode/domain/usecases/get_invoice_print_data.dart';
import '../bloc/purchase_form_bloc.dart';

class PurchaseFormScreen extends StatelessWidget {
  final int? purchaseId;

  const PurchaseFormScreen({super.key, this.purchaseId});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => sl<PurchaseFormBloc>()
          ..add(PurchaseFormInitialized(purchaseId: purchaseId, currencyId: 1))),
        BlocProvider(create: (context) => sl<ProductsBloc>()),
      ],
      child: const _PurchaseFormView(),
    );
  }
}

class _PurchaseFormView extends StatelessWidget {
  const _PurchaseFormView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = context.read<CurrencyService>();

    return BlocConsumer<PurchaseFormBloc, PurchaseFormState>(
      listener: (context, state) {
        if (state.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('purchases.saved_success'.tr())),
          );
          context.pop();
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/purchases');
                }
              },
              tooltip: 'common.back'.tr(),
            ),
            title: Text(state.purchaseId == null
                ? 'purchases.new'.tr()
                : 'purchases.edit'.tr()),
            actions: [
              if (state.items.isNotEmpty && state.purchaseId != null)
                IconButton(
                  icon: const Icon(LucideIcons.printer),
                  tooltip: 'purchases.print_labels'.tr(),
                  onPressed: () => _printLabelsFromPurchase(context, state),
                ),
              if (state.purchaseId != null)
                IconButton(
                  icon: const Icon(LucideIcons.checkCircle),
                  tooltip: 'purchases.post'.tr(),
                  onPressed: state.isSubmitting
                      ? null
                      : () => context.read<PurchaseFormBloc>().add(const PurchaseFormPosted()),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildDateSection(context, state),
                    const SizedBox(height: 16),
                    _buildItemsSection(context, state, currencyService),
                    const SizedBox(height: 16),
                    _buildTotalsSection(context, state, currencyService),
                  ],
                ),
              ),
              _buildBottomBar(context, state, currencyService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateSection(BuildContext context, PurchaseFormState state) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(LucideIcons.calendar, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'purchases.date'.tr(),
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    DateFormat.yMMMd().format(state.purchaseDate),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.edit),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: state.purchaseDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null && context.mounted) {
                  context.read<PurchaseFormBloc>().add(PurchaseDateChanged(date));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsSection(
    BuildContext context,
    PurchaseFormState state,
    CurrencyService currencyService,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.package, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'purchases.items'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showAddItemDialog(context),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: Text('purchases.add_item'.tr()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (state.items.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.packageOpen,
                      size: 48,
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'purchases.no_items'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.items.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  return _PurchaseItemTile(
                    item: item,
                    currencyService: currencyService,
                    onRemove: () => context
                        .read<PurchaseFormBloc>()
                        .add(PurchaseLineItemRemoved(item.tempId)),
                    onQuantityChanged: (qty) => context
                        .read<PurchaseFormBloc>()
                        .add(PurchaseLineItemUpdated(tempId: item.tempId, quantity: qty)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalsSection(
    BuildContext context,
    PurchaseFormState state,
    CurrencyService currencyService,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('purchases.subtotal'.tr()),
                Text(currencyService.format(state.subtotalCents.toBigInt().toInt())),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('purchases.tax'.tr()),
                Text(currencyService.format(state.taxCents.toBigInt().toInt())),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'purchases.total'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  currencyService.format(state.totalCents.toBigInt().toInt()),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    PurchaseFormState state,
    CurrencyService currencyService,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${state.items.length} ${'purchases.items_count'.tr()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    currencyService.format(state.totalCents.toBigInt().toInt()),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: state.isSubmitting || state.items.isEmpty
                  ? null
                  : () => context.read<PurchaseFormBloc>().add(const PurchaseFormSubmitted()),
              child: state.isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  void _printLabelsFromPurchase(BuildContext context, PurchaseFormState state) async {
    if (state.purchaseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('purchases.save_before_printing'.tr()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    try {
      final invoiceData = await sl<GetInvoicePrintData>().forPurchase(state.purchaseId!);

      // Navigate to barcode design screen with invoice data
      if (context.mounted) {
        context.push('/products/barcode-design', extra: {
          'invoiceData': invoiceData,
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('purchases.error_loading_invoice'.tr()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showAddItemDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => BlocProvider.value(
        value: context.read<ProductsBloc>(),
        child: _AddItemSheet(
          onItemAdded: (product, variant, quantity, unitCost) {
            context.read<PurchaseFormBloc>().add(PurchaseLineItemAdded(
                  product: product,
                  variant: variant,
                  quantity: quantity,
                  unitCostCents: unitCost,
                ));
            Navigator.pop(sheetContext);
          },
        ),
      ),
    );
  }
}

class _PurchaseItemTile extends StatelessWidget {
  final PurchaseLineItem item;
  final CurrencyService currencyService;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantityChanged;

  const _PurchaseItemTile({
    required this.item,
    required this.currencyService,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${currencyService.format(item.unitCostCents.toBigInt().toInt())} × ${item.quantity}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.minus, size: 18),
                onPressed: item.quantity > 1
                    ? () => onQuantityChanged(item.quantity - 1)
                    : null,
              ),
              Text(
                '${item.quantity}',
                style: theme.textTheme.titleSmall,
              ),
              IconButton(
                icon: const Icon(LucideIcons.plus, size: 18),
                onPressed: () => onQuantityChanged(item.quantity + 1),
              ),
            ],
          ),
          Text(
            currencyService.format(item.totalCents.toBigInt().toInt()),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.trash2, size: 18, color: colorScheme.error),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _AddItemSheet extends StatefulWidget {
  final void Function(Product product, ProductVariant? variant, int quantity, Decimal unitCost) onItemAdded;

  const _AddItemSheet({required this.onItemAdded});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  Product? _selectedProduct;
  final int _quantity = 1;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'purchases.search_product'.tr(),
                    prefixIcon: const Icon(LucideIcons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: _selectedProduct == null
                    ? _buildProductList(scrollController)
                    : _buildVariantSelection(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductList(ScrollController scrollController) {
    return BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
      builder: (context, state) {
        List<Product>? products;
        if (state is RealtimeSuccess<List<Product>>) {
          products = state.data;
        } else if (state is RealtimeLoading<List<Product>>) {
          products = state.previousData;
        }

        if (products == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final query = _searchController.text.toLowerCase();
        final filtered = products.where((p) {
          if (query.isEmpty) return true;
          return p.name.toLowerCase().contains(query) ||
              (p.sku?.toLowerCase().contains(query) ?? false) ||
              (p.barcode?.toLowerCase().contains(query) ?? false);
        }).toList();

        return ListView.builder(
          controller: scrollController,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final product = filtered[index];
            return ListTile(
              leading: Icon(
                product.hasVariants ? LucideIcons.layers : LucideIcons.package,
              ),
              title: Text(product.name),
              subtitle: product.sku != null ? Text('SKU: ${product.sku}') : null,
              trailing: product.hasVariants
                  ? const Icon(LucideIcons.chevronRight)
                  : null,
              onTap: () {
                if (product.hasVariants) {
                  setState(() => _selectedProduct = product);
                } else {
                  widget.onItemAdded(
                    product,
                    null,
                    _quantity,
                    product.costCents,
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildVariantSelection() {
    final theme = Theme.of(context);

    return BlocProvider(
      create: (context) => sl<ProductVariantsBloc>()
        ..add(ProductVariantsInitialized(_selectedProduct!.id)),
      child: Column(
        children: [
          ListTile(
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => setState(() {
                _selectedProduct = null;
              }),
            ),
            title: Text(
              _selectedProduct!.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text('purchases.select_variant'.tr()),
          ),
          const Divider(),
          Expanded(
            child: BlocBuilder<ProductVariantsBloc, RealtimeState<List<ProductVariant>>>(
              builder: (context, state) {
                List<ProductVariant>? variants;
                if (state is RealtimeSuccess<List<ProductVariant>>) {
                  variants = state.data;
                } else if (state is RealtimeLoading<List<ProductVariant>>) {
                  variants = state.previousData;
                }

                if (variants == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView.builder(
                  itemCount: variants.length,
                  itemBuilder: (context, index) {
                    final variant = variants![index];
                    return ListTile(
                      title: Text(variant.sku ?? 'Variant ${variant.id}'),
                      subtitle: Text('Stock: ${variant.stockQuantity}'),
                      onTap: () {
                        widget.onItemAdded(
                          _selectedProduct!,
                          variant,
                          _quantity,
                          variant.costCents,
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
    );
  }
}
