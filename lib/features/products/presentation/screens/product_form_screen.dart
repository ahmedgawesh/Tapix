import 'dart:io';
import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../bloc/product_form_bloc.dart';
import '../bloc/product_variants_bloc.dart';
import '../bloc/categories_bloc.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/colors_event.dart';
import '../bloc/sizes_bloc.dart';
import '../bloc/sizes_event.dart';
import '../bloc/categories_event.dart';
import '../widgets/money_input_widget.dart';
import '../widgets/variant_management_widget.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/size_entity.dart';

class ProductFormScreen extends StatelessWidget {
  final int? productId;
  final String? initialBarcode;

  const ProductFormScreen({super.key, this.productId, this.initialBarcode});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => sl<ProductFormBloc>()
            ..add(ProductFormInitialized(productId: productId, initialBarcode: initialBarcode)),
        ),
        BlocProvider(
          create: (context) => sl<CategoriesBloc>()..add(const LoadCategories()),
        ),
        BlocProvider(
          create: (context) => sl<ColorsBloc>()..add(const LoadColors()),
        ),
        BlocProvider(
          create: (context) => sl<SizesBloc>()..add(const LoadSizes()),
        ),
        if (productId != null) ...[
          BlocProvider(
            create: (context) => sl<ProductVariantsBloc>()
              ..add(ProductVariantsInitialized(productId!)),
          ),
        ],
      ],
      child: const _ProductFormView(),
    );
  }
}

class _ProductFormView extends StatefulWidget {
  const _ProductFormView();

  @override
  State<_ProductFormView> createState() => _ProductFormViewState();
}

class _ProductFormViewState extends State<_ProductFormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _stockController = TextEditingController();
  final _minStockController = TextEditingController();
  final _taxRateController = TextEditingController();
  
  final _stockFocusNode = FocusNode();
  final _minStockFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _stockFocusNode.addListener(() => _selectAllOnFocus(_stockFocusNode, _stockController));
    _minStockFocusNode.addListener(() => _selectAllOnFocus(_minStockFocusNode, _minStockController));
  }
  
  void _selectAllOnFocus(FocusNode focusNode, TextEditingController controller) {
    if (focusNode.hasFocus) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    }
  }

  String _generateBarcode() {
    // Generate EAN-13 barcode
    // Format: 2 (internal use prefix) + 10 random digits + checksum
    final random = Random();
    final prefix = '2'; // Internal use prefix for store-generated barcodes
    final digits = List.generate(11, (_) => random.nextInt(10)).join();
    final barcode12 = prefix + digits;
    
    // Calculate EAN-13 checksum
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = int.parse(barcode12[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    final checksum = (10 - (sum % 10)) % 10;
    
    return barcode12 + checksum.toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    _taxRateController.dispose();
    _stockFocusNode.dispose();
    _minStockFocusNode.dispose();
    super.dispose();
  }

  void _initControllers(ProductFormState state) {
    if (_nameController.text.isEmpty && state.name.isNotEmpty) {
      _nameController.text = state.name;
    }
    if (_descriptionController.text.isEmpty && state.description != null) {
      _descriptionController.text = state.description!;
    }
    if (_skuController.text.isEmpty && state.sku != null) {
      _skuController.text = state.sku!;
    }
    if (_barcodeController.text.isEmpty && state.barcode != null) {
      _barcodeController.text = state.barcode!;
    }
    if (!_stockFocusNode.hasFocus) {
      _stockController.text = state.stockQuantity.toString();
    }
    if (!_minStockFocusNode.hasFocus) {
      _minStockController.text = state.minQuantity.toString();
    }
    if (_taxRateController.text.isEmpty && state.taxRateBps > 0) {
      _taxRateController.text = (state.taxRateBps / 100).toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          context.pop();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          context.read<ProductFormBloc>().add(const ProductFormSubmitted());
        },
      },
      child: Focus(
        autofocus: true,
        child: BlocConsumer<ProductFormBloc, ProductFormState>(
      listener: (context, state) {
        if (state.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.isEditing
                  ? 'product_updated'.tr()
                  : 'product_created'.tr()),
              backgroundColor: colorScheme.primary,
            ),
          );
          Navigator.of(context).pop(true);
        }

        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('product_form.error_saving'.tr()),
              backgroundColor: colorScheme.error,
            ),
          );
        }

        _initControllers(state);
      },
      builder: (context, state) {
        if (state.isLoading) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => context.pop(),
                tooltip: 'common.back'.tr(),
              ),
              title: Text('product_form.title'.tr()),
              centerTitle: true,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

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
            title: Text(state.isEditing
                ? 'product_form.edit'.tr()
                : 'product_form.create'.tr()),
            centerTitle: true,
            actions: [
              const ThemeToggleButton(),
              if (state.isEditing) ...[
                IconButton(
                  icon: const Icon(LucideIcons.printer),
                  onPressed: () {
                    if (state.productId == null) return;
                    
                    final product = Product(
                      id: state.productId!,
                      name: state.name,
                      nameAr: state.nameAr,
                      nameFr: state.nameFr,
                      description: state.description,
                      sku: state.sku,
                      barcode: state.barcode,
                      costCents: state.costCents,
                      priceCents: state.priceCents,
                      wholesalePriceCents: state.wholesalePriceCents,
                      stockQuantity: state.stockQuantity,
                      minQuantity: state.minQuantity,
                      categoryId: state.categoryId,
                      supplierId: state.supplierId,
                      currencyId: state.currencyId ?? 1, // Default if not set
                      imagePath: state.imagePath,
                      hasVariants: state.hasVariants,
                      isTaxable: state.isTaxable,
                      taxRateBps: state.taxRateBps,
                      isActive: state.isActive,
                      trackInventory: state.trackInventory,
                    );
                    context.push('/barcode-designer', extra: product);
                  },
                  tooltip: 'edit_prices.print_label'.tr(),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: state.isSubmitting
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('common.confirm'.tr()),
                              content: Text('product_form.delete'.tr()),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: Text('common.cancel'.tr()),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: Text('common.delete'.tr()),
                                ),
                              ],
                            ),
                          );

                          if (ok != true) return;

                          final id = state.productId;
                          if (id == null) return;

                          try {
                            await sl<ProductRepository>().deleteProduct(id);
                            if (!context.mounted) return;
                            context.go('/products');
                          } catch (_) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('product_form.error_saving'.tr()),
                                backgroundColor: colorScheme.error,
                              ),
                            );
                          }
                        },
                  tooltip: 'common.delete'.tr(),
                ),
              ],
              if (state.isSubmitting)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(LucideIcons.save),
                  onPressed: () {
                    context.read<ProductFormBloc>().add(const ProductFormSubmitted());
                  },
                  tooltip: 'common.save'.tr(),
                ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: isWide
                      ? _buildWideLayout(context, state)
                      : _buildNarrowLayout(context, state),
                ),
              );
            },
          ),
        );
      },
    ),
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context, ProductFormState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _buildBasicInfoSection(context, state),
              const SizedBox(height: 24),
              _buildPricingSection(context, state),
              const SizedBox(height: 24),
              _buildInventorySection(context, state),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            children: [
              _buildTaxSection(context, state),
              const SizedBox(height: 24),
              _buildOptionsSection(context, state),
              if (state.hasVariants) ...[
                const SizedBox(height: 24),
                _buildVariantsSection(context, state),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(BuildContext context, ProductFormState state) {
    return Column(
      children: [
        _buildBasicInfoSection(context, state),
        const SizedBox(height: 24),
        _buildPricingSection(context, state),
        const SizedBox(height: 24),
        _buildInventorySection(context, state),
        const SizedBox(height: 24),
        _buildTaxSection(context, state),
        const SizedBox(height: 24),
        _buildOptionsSection(context, state),
        if (state.hasVariants) ...[
          const SizedBox(height: 24),
          _buildVariantsSection(context, state),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ProductFormBloc bloc) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      bloc.add(ProductFormFieldChanged(field: 'imagePath', value: pickedFile.path));
    }
  }

  Widget _buildBasicInfoSection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();

    return _buildSectionCard(
      title: 'product_form_basicInfo'.tr(),
      icon: LucideIcons.package,
      children: [
        Center(
          child: GestureDetector(
            onTap: () => _pickImage(bloc),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                image: state.imagePath != null
                    ? DecorationImage(
                        image: FileImage(File(state.imagePath!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: state.imagePath == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.imagePlus,
                          size: 32,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'product_form_tap_to_add_image'.tr(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'product_form_name'.tr(),
            errorText: state.fieldErrors['name'],
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            bloc.add(ProductFormFieldChanged(field: 'name', value: value));
          },
        ),
        const SizedBox(height: 16),
        if (!state.hasVariants)
          _ColorSizePickerRow(
            selectedColorId: state.selectedColorId,
            selectedSizeId: state.selectedSizeId,
            onColorSelected: (id) => bloc.add(ProductFormFieldChanged(field: 'selectedColorId', value: id)),
            onSizeSelected: (id) => bloc.add(ProductFormFieldChanged(field: 'selectedSizeId', value: id)),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.layers,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'product_form.color_size_disabled_when_has_variants'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _buildCategoryPicker(context, state),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: 'product_form_description'.tr(),
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
          onChanged: (value) {
            bloc.add(ProductFormFieldChanged(field: 'description', value: value));
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _skuController,
                decoration: InputDecoration(
                  labelText: 'product_form_sku'.tr(),
                  errorText: state.fieldErrors['sku']?.tr(args: [state.sku ?? '']),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  bloc.add(ProductFormFieldChanged(field: 'sku', value: value));
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: 'product_form_barcode'.tr(),
                  errorText: state.fieldErrors['barcode']?.tr(args: [state.barcode ?? '']),
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.sparkles),
                        tooltip: 'barcode.auto_generate'.tr(),
                        onPressed: () {
                          final barcode = _generateBarcode();
                          _barcodeController.text = barcode;
                          bloc.add(ProductFormFieldChanged(field: 'barcode', value: barcode));
                        },
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.scanLine),
                        tooltip: 'barcode.scan'.tr(),
                        onPressed: () async {
                          final result = await context.push<String>('/barcode-scanner');
                          if (result != null && result.isNotEmpty && mounted) {
                            _barcodeController.text = result;
                            bloc.add(ProductFormFieldChanged(field: 'barcode', value: result));
                          }
                        },
                      ),
                    ],
                  ),
                ),
                onChanged: (value) {
                  bloc.add(ProductFormFieldChanged(field: 'barcode', value: value));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryPicker(BuildContext context, ProductFormState state) {
    return BlocBuilder<CategoriesBloc, RealtimeState<List<Category>>>(
      builder: (context, categoriesState) {
        final categories = categoriesState is RealtimeSuccess<List<Category>>
            ? categoriesState.data
            : <Category>[];
        final selected = state.categoryId == null
            ? null
            : categories.cast<Category?>().firstWhere(
                  (c) => c?.id == state.categoryId,
                  orElse: () => null,
                );

        return InkWell(
          onTap: () => _showCategoryPickerBottomSheet(context, state.categoryId),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'product_form.category'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.tags),
            ),
            child: Text(selected?.name ?? 'common.none'.tr()),
          ),
        );
      },
    );
  }

  Future<void> _showCategoryPickerBottomSheet(BuildContext context, int? currentId) async {
    final categoriesBloc = context.read<CategoriesBloc>();
    final bloc = context.read<ProductFormBloc>();

    final selectedId = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      builder: (sheetContext) {
        return BlocProvider.value(
          value: categoriesBloc,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'categories.search_hint'.tr(),
                      prefixIcon: const Icon(LucideIcons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => categoriesBloc.add(SearchCategories(v)),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => sheetContext.push('/products/categories'),
                      icon: const Icon(LucideIcons.settings),
                      label: Text('categories.title'.tr()),
                    ),
                  ),
                  Flexible(
                    child: BlocBuilder<CategoriesBloc, RealtimeState<List<Category>>>(
                      bloc: categoriesBloc,
                      builder: (context, state) {
                        final categories = state is RealtimeSuccess<List<Category>> ? state.data : <Category>[];
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: categories.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return ListTile(
                                title: Text('common.none'.tr()),
                                onTap: () => Navigator.of(context).pop(null),
                              );
                            }
                            final cat = categories[index - 1];
                            return ListTile(
                              title: Text(cat.name),
                              onTap: () => Navigator.of(context).pop(cat.id),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    categoriesBloc.add(const LoadCategories());
    if (selectedId != null || currentId != null) {
      bloc.add(ProductFormFieldChanged(field: 'categoryId', value: selectedId));
    }
  }

  Widget _buildPricingSection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();

    return _buildSectionCard(
      title: 'product_form_pricing'.tr(),
      icon: LucideIcons.dollarSign,
      children: [
        Row(
          children: [
            Expanded(
              child: MoneyInputWidget(
                value: state.costCents,
                label: 'product_form_cost'.tr(),
                errorText: state.fieldErrors['costCents'],
                onChanged: (value) {
                  bloc.add(ProductFormFieldChanged(field: 'costCents', value: value));
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: MoneyInputWidget(
                value: state.priceCents,
                label: 'product_form_price'.tr(),
                errorText: state.fieldErrors['priceCents'],
                onChanged: (value) {
                  bloc.add(ProductFormFieldChanged(field: 'priceCents', value: value));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: MoneyInputWidget(
                value: state.wholesalePriceCents ?? Decimal.zero,
                label: 'product_form_wholesalePrice'.tr(),
                onChanged: (value) {
                  bloc.add(ProductFormFieldChanged(
                    field: 'wholesalePriceCents',
                    value: value == Decimal.zero ? null : value,
                  ));
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'product_form_margin'.tr(),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      MarginDisplayWidget(
                        costCents: state.costCents,
                        priceCents: state.priceCents,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInventorySection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();
    final productId = state.productId;

    return _buildSectionCard(
      title: 'product_form_inventory'.tr(),
      icon: LucideIcons.warehouse,
      children: [
        if (state.hasVariants)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.layers,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'product_form.stock_is_sum_of_variants'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        if (state.hasVariants) const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: state.hasVariants && productId != null
                  ? BlocBuilder<ProductVariantsBloc, RealtimeState<List<ProductVariant>>>(
                      builder: (context, variantsState) {
                        List<ProductVariant> variants = const [];
                        if (variantsState is RealtimeSuccess<List<ProductVariant>>) {
                          variants = variantsState.data;
                        } else if (variantsState is RealtimeLoading<List<ProductVariant>>) {
                          variants = variantsState.previousData ?? const [];
                        } else if (variantsState is RealtimeError<List<ProductVariant>>) {
                          variants = variantsState.previousData ?? const [];
                        } else if (variantsState is RealtimeOptimistic<List<ProductVariant>>) {
                          variants = variantsState.optimisticData;
                        }

                        final totalStock = variants.fold<int>(0, (sum, v) => sum + v.stockQuantity);

                        return TextFormField(
                          key: ValueKey('total_stock_$totalStock'),
                          initialValue: totalStock.toString(),
                          decoration: InputDecoration(
                            labelText: 'product_form.totalStock'.tr(),
                            border: const OutlineInputBorder(),
                            suffixIcon: const Icon(LucideIcons.lock),
                          ),
                          enabled: false,
                        );
                      },
                    )
                  : TextFormField(
                      controller: _stockController,
                      focusNode: _stockFocusNode,
                      decoration: InputDecoration(
                        labelText: 'product_form_quantity'.tr(),
                        errorText: state.fieldErrors['stockQuantity'],
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (value) {
                        bloc.add(ProductFormFieldChanged(
                          field: 'stockQuantity',
                          value: int.tryParse(value) ?? 0,
                        ));
                      },
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _minStockController,
                focusNode: _minStockFocusNode,
                decoration: InputDecoration(
                  labelText: 'product_form_minQuantity'.tr(),
                  errorText: state.fieldErrors['minQuantity'],
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  bloc.add(ProductFormFieldChanged(
                    field: 'minQuantity',
                    value: int.tryParse(value) ?? 0,
                  ));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: Text('product_form_trackInventory'.tr()),
          value: state.trackInventory,
          onChanged: (value) {
            bloc.add(ProductFormFieldChanged(field: 'trackInventory', value: value));
          },
        ),
      ],
    );
  }

  Widget _buildTaxSection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();

    return _buildSectionCard(
      title: 'product_form_tax'.tr(),
      icon: LucideIcons.percent,
      children: [
        SwitchListTile(
          title: Text('product_form_isTaxable'.tr()),
          value: state.isTaxable,
          onChanged: (value) {
            bloc.add(ProductFormFieldChanged(field: 'isTaxable', value: value));
          },
        ),
        if (state.isTaxable) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _taxRateController,
            decoration: InputDecoration(
              labelText: 'product_form_taxRate'.tr(),
              errorText: state.fieldErrors['taxRateBps'],
              border: const OutlineInputBorder(),
              suffixText: '%',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              final rate = double.tryParse(value) ?? 0;
              bloc.add(ProductFormFieldChanged(
                field: 'taxRateBps',
                value: (rate * 100).toInt(),
              ));
            },
          ),
        ],
      ],
    );
  }

  Widget _buildOptionsSection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();

    return _buildSectionCard(
      title: 'product_form_options'.tr(),
      icon: LucideIcons.settings,
      children: [
        SwitchListTile(
          title: Text('product_form_hasVariants'.tr()),
          subtitle: Text('product_form_hasVariants_hint'.tr()),
          value: state.hasVariants,
          onChanged: (value) {
            bloc.add(ProductFormFieldChanged(field: 'hasVariants', value: value));
          },
        ),
        SwitchListTile(
          title: Text('product_form_isActive'.tr()),
          value: state.isActive,
          onChanged: (value) {
            bloc.add(ProductFormFieldChanged(field: 'isActive', value: value));
          },
        ),
      ],
    );
  }

  Widget _buildVariantsSection(BuildContext context, ProductFormState state) {
    final productId = state.productId;
    
    // For new products, show a message that variants can be added after saving
    if (productId == null) {
      return _buildSectionCard(
        title: 'product_form.variants'.tr(),
        icon: LucideIcons.layers,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'product_form.variants_save_first'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _buildSectionCard(
      title: 'product_form.variants'.tr(),
      icon: LucideIcons.layers,
      children: [
        VariantManagementWidget(productId: productId),
      ],
    );
  }

}

class _ColorSizePickerRow extends StatelessWidget {
  final int? selectedColorId;
  final int? selectedSizeId;
  final ValueChanged<int?> onColorSelected;
  final ValueChanged<int?> onSizeSelected;

  const _ColorSizePickerRow({
    required this.selectedColorId,
    required this.selectedSizeId,
    required this.onColorSelected,
    required this.onSizeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ColorPickerField(
            selectedColorId: selectedColorId,
            onSelected: onColorSelected,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _SizePickerField(
            selectedSizeId: selectedSizeId,
            onSelected: onSizeSelected,
          ),
        ),
      ],
    );
  }
}

class _ColorPickerField extends StatelessWidget {
  final int? selectedColorId;
  final ValueChanged<int?> onSelected;

  const _ColorPickerField({
    required this.selectedColorId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
      builder: (context, state) {
        final colors = state is RealtimeSuccess<List<ProductColor>> ? state.data : <ProductColor>[];
        final selected = selectedColorId == null
            ? null
            : colors.cast<ProductColor?>().firstWhere(
                  (c) => c?.id == selectedColorId,
                  orElse: () => null,
                );

        return InkWell(
          onTap: () => _showColorPickerBottomSheet(context, colors),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'product_form_variantColor'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.palette),
            ),
            child: Text(selected?.name ?? 'common.none'.tr()),
          ),
        );
      },
    );
  }

  Future<void> _showColorPickerBottomSheet(BuildContext context, List<ProductColor> colors) async {
    final selected = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setState) {
            final filtered = query.isEmpty
                ? colors
                : colors.where((c) => c.name.toLowerCase().contains(query.toLowerCase())).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'colors.search_hint'.tr(),
                        prefixIcon: const Icon(LucideIcons.search),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => context.push('/products/colors'),
                        icon: const Icon(LucideIcons.settings),
                        label: Text('manage_colors'.tr()),
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return ListTile(
                              title: Text('common.none'.tr()),
                              onTap: () => Navigator.of(context).pop(null),
                            );
                          }
                          final color = filtered[index - 1];
                          return ListTile(
                            title: Text(color.name),
                            onTap: () => Navigator.of(context).pop(color.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null || selectedColorId != null) {
      onSelected(selected);
    }
  }
}

class _SizePickerField extends StatelessWidget {
  final int? selectedSizeId;
  final ValueChanged<int?> onSelected;

  const _SizePickerField({
    required this.selectedSizeId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
      builder: (context, state) {
        final sizes = state is RealtimeSuccess<List<Size>> ? state.data : <Size>[];
        final selected = selectedSizeId == null
            ? null
            : sizes.cast<Size?>().firstWhere(
                  (s) => s?.id == selectedSizeId,
                  orElse: () => null,
                );

        return InkWell(
          onTap: () => _showSizePickerBottomSheet(context, sizes),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'product_form_variantSize'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.ruler),
            ),
            child: Text(selected?.name ?? 'common.none'.tr()),
          ),
        );
      },
    );
  }

  Future<void> _showSizePickerBottomSheet(BuildContext context, List<Size> sizes) async {
    final selected = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setState) {
            final filtered = query.isEmpty
                ? sizes
                : sizes.where((s) => s.name.toLowerCase().contains(query.toLowerCase())).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'sizes.search_hint'.tr(),
                        prefixIcon: const Icon(LucideIcons.search),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => query = v),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => context.push('/products/sizes'),
                        icon: const Icon(LucideIcons.settings),
                        label: Text('manage_sizes'.tr()),
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return ListTile(
                              title: Text('common.none'.tr()),
                              onTap: () => Navigator.of(context).pop(null),
                            );
                          }
                          final size = filtered[index - 1];
                          return ListTile(
                            title: Text(size.name),
                            onTap: () => Navigator.of(context).pop(size.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null || selectedSizeId != null) {
      onSelected(selected);
    }
  }
}
