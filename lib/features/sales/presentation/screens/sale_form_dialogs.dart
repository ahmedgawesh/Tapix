part of 'sale_form_screen.dart';

// ═══════════════════════════════════════════════════════
// SHARED HANDLE WIDGET
// ═══════════════════════════════════════════════════════
Widget _handle(ColorScheme cs) => Center(
  child: Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    width: 40, height: 4,
    decoration: BoxDecoration(
      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(2),
    ),
  ),
);

Color? _tryParseHexColor(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.isEmpty) return null;
  final buffer = StringBuffer();
  if (cleaned.length == 6) buffer.write('FF');
  buffer.write(cleaned);
  try {
    return Color(int.parse(buffer.toString(), radix: 16));
  } catch (_) {
    return null;
  }
}

// ═══════════════════════════════════════════════════════
// CUSTOMER PICKER SHEET
// ═══════════════════════════════════════════════════════
class _CustomerPickerSheet extends StatefulWidget {
  final void Function(Customer customer) onSelected;
  const _CustomerPickerSheet({required this.onSelected});

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = sl<CurrencyService>();

    return BlocProvider(
      create: (_) => CustomersBloc(sl<CustomerRepository>()),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
        builder: (context, scrollCtrl) => Column(children: [
          _handle(cs),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(LucideIcons.users, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text('sales.select_customer'.tr(),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: Text('common.cancel'.tr())),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'customers.search_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true, isDense: true),
              onChanged: (v) => context.read<CustomersBloc>().add(CustomersSearchRequested(v)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BlocBuilder<CustomersBloc, RealtimeState<CustomersData>>(
              builder: (context, state) {
                if (state is RealtimeLoading<CustomersData>) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is RealtimeSuccess<CustomersData>) {
                  final customers = state.data.customers;
                  if (customers.isEmpty) return Center(child: Text('customers.no_results'.tr()));
                  return ListView.builder(
                    controller: scrollCtrl, itemCount: customers.length,
                    itemBuilder: (context, i) {
                      final c = customers[i];
                      final bal = c.balanceCents.toDouble().round();
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Text(
                            c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                            style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          curr.format(bal),
                          style: TextStyle(color: bal > 0 ? Colors.red : Colors.green, fontSize: 12),
                        ),
                        trailing: Icon(LucideIcons.chevronRight, size: 16, color: cs.onSurfaceVariant),
                        onTap: () => widget.onSelected(c),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// EMPLOYEE PICKER SHEET
// ═══════════════════════════════════════════════════════
class _EmployeePickerSheet extends StatefulWidget {
  final void Function(Employee employee) onSelected;
  const _EmployeePickerSheet({required this.onSelected});

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  final _searchCtrl = TextEditingController();
  List<Employee> _all = [];
  List<Employee> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final employees = await sl<EmployeeRepository>().searchEmployees('', isActive: true);
      if (mounted) setState(() { _all = employees; _filtered = employees; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _search(String q) {
    if (q.isEmpty) { setState(() => _filtered = _all); return; }
    final lower = q.toLowerCase();
    setState(() => _filtered = _all.where((e) =>
      e.name.toLowerCase().contains(lower) ||
      (e.phone?.toLowerCase().contains(lower) ?? false) ||
      (e.employeeCode?.toLowerCase().contains(lower) ?? false)
    ).toList());
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
      builder: (context, scrollCtrl) => Column(children: [
        _handle(cs),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(LucideIcons.userCheck, size: 20, color: cs.tertiary),
            const SizedBox(width: 8),
            Text('sales.select_salesperson'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: Text('common.cancel'.tr())),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'employees.search_hint'.tr(),
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true, isDense: true),
            onChanged: _search,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _filtered.isEmpty
              ? Center(child: Text('common.no_results'.tr()))
              : ListView.builder(
                  controller: scrollCtrl, itemCount: _filtered.length,
                  itemBuilder: (context, i) {
                    final e = _filtered[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.tertiaryContainer,
                        child: Text(
                          e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                          style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        e.position ?? e.department ?? '',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                      trailing: Icon(LucideIcons.chevronRight, size: 16, color: cs.onSurfaceVariant),
                      onTap: () => widget.onSelected(e),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ADD ITEM SHEET (Product + Variant Selection)
// Follows purchase_form_screen.dart _AddItemSheet pattern
// ═══════════════════════════════════════════════════════
class _AddItemSheet extends StatefulWidget {
  final void Function(Product product, ProductVariant? variant, int quantity, Decimal unitPrice) onItemAdded;
  const _AddItemSheet({required this.onItemAdded});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  Product? _selectedProduct;
  final _searchController = TextEditingController();

  @override
  void dispose() { _searchController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75, minChildSize: 0.5, maxChildSize: 0.95, expand: false,
      builder: (context, scrollController) {
        return Column(children: [
          _handle(cs),
          // Title row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              if (_selectedProduct != null)
                IconButton(
                  icon: const Icon(LucideIcons.arrowLeft),
                  onPressed: () => setState(() => _selectedProduct = null),
                ),
              Expanded(
                child: Text(
                  _selectedProduct != null ? _selectedProduct!.name : 'sales.add_item'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          // Search (only when selecting product)
          if (_selectedProduct == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'sales.search_products'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                ),
                onChanged: (v) => context.read<ProductsBloc>().add(ProductSearchRequested(v)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('sales.select_variant'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
          const Divider(height: 1),
          Expanded(
            child: _selectedProduct == null
              ? _buildProductList(scrollController)
              : _buildVariantSelection(),
          ),
        ]);
      },
    );
  }

  Widget _buildProductList(ScrollController scrollController) {
    final cs = Theme.of(context).colorScheme;
    final currencyService = sl<CurrencyService>();

    return BlocBuilder<VariantPreviewsBloc, RealtimeState<Map<int, VariantPreview>>>(
      builder: (context, previewState) {
        Map<int, VariantPreview> previews = const {};
        if (previewState is RealtimeSuccess<Map<int, VariantPreview>>) {
          previews = previewState.data;
        } else if (previewState is RealtimeLoading<Map<int, VariantPreview>>) {
          previews = previewState.previousData ?? const {};
        }

        return BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
          builder: (context, state) {
            List<Product>? products;
            if (state is RealtimeSuccess<List<Product>>) {
              products = state.data;
            } else if (state is RealtimeLoading<List<Product>>) {
              products = state.previousData;
            }

            if (products == null) return const Center(child: CircularProgressIndicator());

            if (products.isEmpty) {
              return Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(LucideIcons.searchX, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text('sales.no_products'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              );
            }

            return ListView.separated(
              controller: scrollController,
              itemCount: products.length,
              separatorBuilder: (context, i) => Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.5)),
              itemBuilder: (context, index) {
                final product = products![index];
                final preview = previews[product.id];
                final sizeName = (!product.hasVariants ? preview?.sizeName?.trim() : null);
                final colorHex = (!product.hasVariants ? preview?.colorHex?.trim() : null);
                final shade = _tryParseHexColor(colorHex);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      product.hasVariants ? LucideIcons.layers : LucideIcons.package,
                      size: 20, color: cs.primary,
                    ),
                  ),
                  title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Row(children: [
                    if (product.sku != null) ...[
                      Flexible(
                        child: Text('SKU: ${product.sku}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (sizeName != null && sizeName.isNotEmpty) ...[
                      Flexible(
                        child: Text(sizeName,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (shade != null) const SizedBox(width: 6),
                    ],
                    if (shade != null)
                      Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: shade, shape: BoxShape.circle,
                          border: Border.all(color: cs.outline))),
                    const Spacer(),
                    if (!product.hasVariants)
                      Text(currencyService.format(product.priceCents.toBigInt().toInt()),
                        style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w500)),
                  ]),
                  trailing: product.hasVariants
                    ? Icon(LucideIcons.chevronRight, size: 20, color: cs.primary)
                    : Icon(LucideIcons.plusCircle, size: 20, color: cs.primary),
                  onTap: () {
                    if (product.hasVariants) {
                      setState(() => _selectedProduct = product);
                    } else {
                      // Product without variants: use product price directly
                      widget.onItemAdded(product, null, 1, product.priceCents);
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildVariantSelection() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currencyService = sl<CurrencyService>();

    return BlocProvider(
      create: (context) => sl<ProductVariantsBloc>()
        ..add(ProductVariantsInitialized(_selectedProduct!.id)),
      child: BlocBuilder<ProductVariantsBloc, RealtimeState<List<ProductVariant>>>(
        builder: (context, state) {
          List<ProductVariant>? variants;
          if (state is RealtimeSuccess<List<ProductVariant>>) {
            variants = state.data;
          } else if (state is RealtimeLoading<List<ProductVariant>>) {
            variants = state.previousData;
          }

          if (variants == null) return const Center(child: CircularProgressIndicator());

          return FutureBuilder<({Map<int, String> sizeNameById, Map<int, String?> colorHexById})>(
            future: () async {
              final colorRepo = sl<ProductColorRepository>();
              final sizeRepo = sl<SizeRepository>();
              final results = await Future.wait([colorRepo.getAllColors(), sizeRepo.getAllSizes()]);
              final colors = results[0] as List<dynamic>;
              final sizes = results[1] as List<dynamic>;

              final sizeNameById = <int, String>{};
              for (final s in sizes) { sizeNameById[(s as dynamic).id as int] = (s as dynamic).name as String; }
              final colorHexById = <int, String?>{};
              for (final c in colors) { colorHexById[(c as dynamic).id as int] = (c as dynamic).hexCode as String?; }

              return (sizeNameById: sizeNameById, colorHexById: colorHexById);
            }(),
            builder: (context, snapshot) {
              final sizeNameById = snapshot.data?.sizeNameById ?? const <int, String>{};
              final colorHexById = snapshot.data?.colorHexById ?? const <int, String?>{};

              return ListView.separated(
                itemCount: variants!.length,
                separatorBuilder: (context, i) => Divider(height: 1, indent: 56, color: cs.outlineVariant.withValues(alpha: 0.5)),
                itemBuilder: (context, index) {
                  final variant = variants![index];
                  final sizeName = variant.sizeId == null ? null : sizeNameById[variant.sizeId!];
                  final colorHex = variant.colorId == null ? null : colorHexById[variant.colorId!];
                  final shade = _tryParseHexColor(colorHex);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: shade != null ? shade.withValues(alpha: 0.2) : cs.tertiaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: shade != null ? Border.all(color: shade) : null,
                      ),
                      child: shade != null
                        ? Center(child: Container(width: 20, height: 20,
                            decoration: BoxDecoration(color: shade, shape: BoxShape.circle)))
                        : Icon(LucideIcons.tag, size: 18, color: cs.tertiary),
                    ),
                    title: Text(
                      variant.sku ?? 'Variant ${variant.id}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Row(children: [
                      if (sizeName != null && sizeName.trim().isNotEmpty) ...[
                        Flexible(
                          child: Text(sizeName,
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (shade != null) const SizedBox(width: 6),
                      ],
                      if (shade != null) ...[
                        Container(width: 10, height: 10,
                          decoration: BoxDecoration(color: shade, shape: BoxShape.circle,
                            border: Border.all(color: cs.outline))),
                        const SizedBox(width: 12),
                      ],
                      Icon(LucideIcons.warehouse, size: 12, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('${variant.stockQuantity}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      const SizedBox(width: 12),
                      Icon(LucideIcons.coins, size: 12, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(currencyService.format(variant.priceCents.toBigInt().toInt()),
                        style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w500)),
                    ]),
                    trailing: Icon(LucideIcons.plusCircle, size: 20, color: cs.primary),
                    onTap: () {
                      widget.onItemAdded(
                        _selectedProduct!, variant, 1, variant.priceCents,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// EDIT ITEM SHEET
// ═══════════════════════════════════════════════════════
class _EditItemSheet extends StatefulWidget {
  final SaleLineItem item;
  final void Function(int quantity, Decimal unitPrice, Decimal discount) onUpdated;
  final VoidCallback onRemoved;
  const _EditItemSheet({required this.item, required this.onUpdated, required this.onRemoved});

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late int _quantity;
  late TextEditingController _priceCtrl;
  late TextEditingController _discountCtrl;

  @override
  void initState() {
    super.initState();
    _quantity = widget.item.quantity;
    _priceCtrl = TextEditingController(
      text: (widget.item.unitPriceCents.toBigInt().toInt() / 100).toStringAsFixed(2));
    _discountCtrl = TextEditingController(
      text: widget.item.discountCents > Decimal.zero
        ? (widget.item.discountCents.toBigInt().toInt() / 100).toStringAsFixed(2)
        : '');
  }

  @override
  void dispose() { _priceCtrl.dispose(); _discountCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = sl<CurrencyService>();

    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: Icon(LucideIcons.package, size: 20, color: cs.onSurfaceVariant)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.item.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                if (widget.item.colorHex != null || widget.item.sizeName != null)
                  Text(
                    [widget.item.sizeName, widget.item.colorHex]
                      .where((s) => s != null && s.isNotEmpty).join(' / '),
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            IconButton(
              icon: Icon(LucideIcons.trash2, color: cs.error),
              onPressed: widget.onRemoved,
            ),
          ]),
          const SizedBox(height: 24),

          // Quantity
          Text('sales.quantity'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(LucideIcons.minus, size: 18)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('$_quantity',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold))),
              IconButton.filledTonal(
                onPressed: () => setState(() => _quantity++),
                icon: const Icon(LucideIcons.plus, size: 18)),
            ]),
          ),
          const SizedBox(height: 20),

          // Price
          Text('sales.unit_price'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true, isDense: true,
              prefixIcon: const Icon(LucideIcons.dollarSign, size: 18)),
          ),
          const SizedBox(height: 16),

          // Discount
          Text('sales.item_discount'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _discountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true, isDense: true, hintText: '0.00',
              prefixIcon: const Icon(LucideIcons.tag, size: 18)),
          ),
          const SizedBox(height: 20),

          // Preview total
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('sales.total'.tr(), style: theme.textTheme.titleSmall),
              Text(_previewTotal(curr),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
            ]),
          ),
          const SizedBox(height: 20),

          // Save button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _onSave,
              icon: const Icon(LucideIcons.check, size: 18),
              label: Text('common.save'.tr()),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ]),
      ),
    );
  }

  String _previewTotal(CurrencyService curr) {
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final discount = double.tryParse(_discountCtrl.text) ?? 0;
    final cents = ((price * 100).round() * _quantity) - (discount * 100).round();
    return curr.format(cents > 0 ? cents : 0);
  }

  void _onSave() {
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final discount = double.tryParse(_discountCtrl.text) ?? 0;
    widget.onUpdated(
      _quantity,
      Decimal.fromInt((price * 100).round()),
      Decimal.fromInt((discount * 100).round()),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CHECKOUT SHEET
// ═══════════════════════════════════════════════════════
class _CheckoutSheet extends StatelessWidget {
  final CurrencyService currencyService;
  final TextEditingController notesCtrl;
  final TextEditingController taxCtrl;
  final VoidCallback onConfirm;

  const _CheckoutSheet({
    required this.currencyService, required this.notesCtrl,
    required this.taxCtrl, required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BlocBuilder<SaleFormBloc, SaleFormState>(
      builder: (context, state) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5, expand: false,
          builder: (context, scrollCtrl) => Column(children: [
            _handle(cs),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(LucideIcons.shoppingBag, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('sales.checkout'.tr(),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: Text('common.cancel'.tr())),
              ]),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Payment Method
                  _section(theme, cs, LucideIcons.wallet, 'sales.payment_method'.tr(),
                    child: Wrap(spacing: 8, runSpacing: 8,
                      children: SalePaymentMethod.values.map((m) {
                        final sel = state.paymentMethod == m;
                        return ChoiceChip(
                          label: Text(_pmLabel(m)), selected: sel,
                          onSelected: (_) => context.read<SaleFormBloc>().add(SalePaymentMethodChanged(m)),
                          avatar: Icon(_pmIcon(m), size: 16),
                          selectedColor: cs.primaryContainer, showCheckmark: false,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tax Rate
                  _section(theme, cs, LucideIcons.percent, 'sales.tax_rate'.tr(),
                    child: TextField(
                      controller: taxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(), suffixText: '%', hintText: '0', isDense: true),
                      onChanged: (v) {
                        final pct = double.tryParse(v) ?? 0;
                        context.read<SaleFormBloc>().add(
                          SaleTaxRateChanged(Decimal.parse(pct.toStringAsFixed(2))));
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Invoice Discount (if invoice mode)
                  if (state.discountMode == SaleDiscountMode.invoice) ...[
                    _section(theme, cs, LucideIcons.tag, 'sales.invoice_discount'.tr(),
                      child: TextField(
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                        decoration: InputDecoration(
                          labelText: 'sales.discount'.tr(),
                          border: const OutlineInputBorder(), isDense: true),
                        onChanged: (v) {
                          final val = double.tryParse(v) ?? 0;
                          context.read<SaleFormBloc>().add(
                            SaleInvoiceDiscountChanged(Decimal.fromInt((val * 100).round())));
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Notes
                  _section(theme, cs, LucideIcons.stickyNote, 'sales.notes'.tr(),
                    child: TextField(
                      controller: notesCtrl, maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'sales.notes_hint'.tr(),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true),
                      onChanged: (v) => context.read<SaleFormBloc>().add(SaleNotesChanged(v)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Financial Summary
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3))),
                    child: Column(children: [
                      _cRow(theme, 'sales.subtotal'.tr(),
                        currencyService.format(state.subtotalCents.toBigInt().toInt())),
                      if (state.totalDiscountCents > Decimal.zero) ...[
                        const SizedBox(height: 8),
                        _cRow(theme, 'sales.discount'.tr(),
                          '- ${currencyService.format(state.totalDiscountCents.toBigInt().toInt())}',
                          valueColor: cs.tertiary),
                      ],
                      if (state.taxCents > Decimal.zero) ...[
                        const SizedBox(height: 8),
                        _cRow(theme, 'sales.tax'.tr(),
                          currencyService.format(state.taxCents.toBigInt().toInt())),
                      ],
                      Divider(height: 20, color: cs.outlineVariant.withValues(alpha: 0.5)),
                      _cRow(theme, 'sales.total'.tr(),
                        currencyService.format(state.totalCents.toBigInt().toInt()),
                        isBold: true, valueColor: cs.primary),
                    ]),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),

            // Bottom actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
                boxShadow: [BoxShadow(color: cs.shadow.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
              ),
              child: SafeArea(
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('common.cancel'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: state.isSubmitting ? null : onConfirm,
                      icon: state.isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(LucideIcons.check, size: 18),
                      label: Text('sales.confirm_save'.tr()),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _section(ThemeData theme, ColorScheme cs, IconData icon, String title, {required Widget child}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 8),
      child,
    ]);

  Widget _cRow(ThemeData t, String l, String v, {bool isBold = false, Color? valueColor}) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(l, style: (isBold ? t.textTheme.titleSmall : t.textTheme.bodyMedium)?.copyWith(
        color: isBold ? null : t.colorScheme.onSurfaceVariant)),
      Text(v, style: (isBold ? t.textTheme.titleMedium : t.textTheme.bodyMedium)?.copyWith(
        color: valueColor, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
    ],
  );

  String _pmLabel(SalePaymentMethod m) => switch (m) {
    SalePaymentMethod.cash => 'sales.payment_cash'.tr(),
    SalePaymentMethod.credit => 'sales.payment_credit'.tr(),
    SalePaymentMethod.card => 'sales.payment_card'.tr(),
    SalePaymentMethod.cheque => 'sales.payment_cheque'.tr(),
  };

  IconData _pmIcon(SalePaymentMethod m) => switch (m) {
    SalePaymentMethod.cash => LucideIcons.banknote,
    SalePaymentMethod.credit => LucideIcons.clock,
    SalePaymentMethod.card => LucideIcons.creditCard,
    SalePaymentMethod.cheque => LucideIcons.fileText,
  };
}
