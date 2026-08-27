part of 'sale_form_screen.dart';

// ═══════════════════════════════════════════════════════
// SHARED HANDLE WIDGET
// ═══════════════════════════════════════════════════════
Widget _handle(ColorScheme cs) => Center(
  child: Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    width: 40,
    height: 4,
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
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = sl<CurrencyService>();

    return BlocProvider(
      create: (_) => CustomersBloc(sl<CustomerRepository>()),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollCtrl) => Column(
          children: [
            _handle(cs),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(LucideIcons.users, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'sales.select_customer'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('common.cancel'.tr()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'customers.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  isDense: true,
                ),
                onChanged: (v) => context.read<CustomersBloc>().add(
                  CustomersSearchRequested(v),
                ),
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
                    if (customers.isEmpty) {
                      return Center(child: Text('customers.no_results'.tr()));
                    }
                    return ListView.builder(
                      controller: scrollCtrl,
                      itemCount: customers.length,
                      itemBuilder: (context, i) {
                        final c = customers[i];
                        final bal = c.balanceCents.toBigInt().toInt();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Text(
                              c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                              style: TextStyle(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            c.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            curr.format(bal),
                            style: TextStyle(
                              color: bal > 0 ? Colors.red : Colors.green,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          onTap: () => widget.onSelected(c),
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
      final employees = await sl<EmployeeRepository>().searchEmployees(
        '',
        isActive: true,
      );
      if (mounted) {
        setState(() {
          _all = employees;
          _filtered = employees;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _search(String q) {
    if (q.isEmpty) {
      setState(() => _filtered = _all);
      return;
    }
    final lower = q.toLowerCase();
    setState(
      () => _filtered = _all
          .where(
            (e) =>
                e.name.toLowerCase().contains(lower) ||
                (e.phone?.toLowerCase().contains(lower) ?? false) ||
                (e.employeeCode?.toLowerCase().contains(lower) ?? false),
          )
          .toList(),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) => Column(
        children: [
          _handle(cs),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(LucideIcons.userCheck, size: 20, color: cs.tertiary),
                const SizedBox(width: 8),
                Text(
                  'sales.select_salesperson'.tr(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('common.cancel'.tr()),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'employees.search_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                isDense: true,
              ),
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
                    controller: scrollCtrl,
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final e = _filtered[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.tertiaryContainer,
                          child: Text(
                            e.name.isNotEmpty ? e.name[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: cs.onTertiaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          e.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          e.position ?? e.department ?? '',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                        onTap: () => widget.onSelected(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// REMOTE MASTER PICKERS
// These reuse the original sale form and replace only its data source when
// this device is an authenticated LAN client. No client-side business record
// is created; the master remains the sole source of truth.
// ═══════════════════════════════════════════════════════
class _RemoteCustomerPickerSheet extends StatefulWidget {
  final void Function(LanCustomerSummary customer) onSelected;
  const _RemoteCustomerPickerSheet({required this.onSelected});

  @override
  State<_RemoteCustomerPickerSheet> createState() =>
      _RemoteCustomerPickerSheetState();
}

class _RemoteCustomerPickerSheetState
    extends State<_RemoteCustomerPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<LanCustomerSummary>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    try {
      final values = await sl<LanNetworkService>().fetchRemoteCustomers(
        query: _searchCtrl.text,
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _items = values;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          _handle(cs),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'sales.select_customer'.tr(),
                prefixIcon: const Icon(LucideIcons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(LucideIcons.rotateCcw),
                      label: Text('common.retry'.tr()),
                    ),
                  )
                : _items == null
                ? const Center(child: CircularProgressIndicator())
                : _items!.isEmpty
                ? Center(child: Text('customers.no_results'.tr()))
                : ListView.separated(
                    controller: scrollController,
                    itemCount: _items!.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final customer = _items![index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Text(
                            customer.name.isEmpty
                                ? '?'
                                : customer.name[0].toUpperCase(),
                          ),
                        ),
                        title: Text(customer.name),
                        subtitle: customer.phone == null
                            ? null
                            : Text(customer.phone!),
                        onTap: () => widget.onSelected(customer),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RemoteEmployeePickerSheet extends StatefulWidget {
  final void Function(LanEmployeeSummary employee) onSelected;
  const _RemoteEmployeePickerSheet({required this.onSelected});

  @override
  State<_RemoteEmployeePickerSheet> createState() =>
      _RemoteEmployeePickerSheetState();
}

class _RemoteEmployeePickerSheetState
    extends State<_RemoteEmployeePickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<LanEmployeeSummary>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    try {
      final values = await sl<LanNetworkService>().fetchRemoteSalespeople(
        query: _searchCtrl.text,
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _items = values;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          _handle(cs),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'sales.select_salesperson'.tr(),
                prefixIcon: const Icon(LucideIcons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(LucideIcons.rotateCcw),
                      label: Text('common.retry'.tr()),
                    ),
                  )
                : _items == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    controller: scrollController,
                    itemCount: _items!.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final employee = _items![index];
                      return ListTile(
                        leading: const Icon(LucideIcons.userCheck),
                        title: Text(employee.name),
                        subtitle: employee.position == null
                            ? null
                            : Text(employee.position!),
                        onTap: () => widget.onSelected(employee),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RemoteAddItemSheet extends StatefulWidget {
  final LanCatalogProduct? initialProduct;
  final void Function(LanCatalogProduct product, LanCatalogVariant? variant)
  onSelected;

  const _RemoteAddItemSheet({this.initialProduct, required this.onSelected});

  @override
  State<_RemoteAddItemSheet> createState() => _RemoteAddItemSheetState();
}

class _RemoteAddItemSheetState extends State<_RemoteAddItemSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  LanCatalogPage? _page;
  LanCatalogProduct? _selected;
  String? _error;
  final Map<int, Future<Uint8List?>> _imageFutures = {};

  @override
  void initState() {
    super.initState();
    _selected = widget.initialProduct;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _search(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    try {
      final page = await sl<LanNetworkService>().fetchRemoteCatalog(
        query: _searchCtrl.text,
        limit: 200,
      );
      final currencyService = sl<CurrencyService>();
      final knownCurrency = Currency.fromCode(page.currencyCode);
      if (knownCurrency.code != page.currencyCode ||
          knownCurrency.symbol != page.currencySymbol) {
        await currencyService.addCustomCurrency(
          Currency(
            code: page.currencyCode,
            symbol: page.currencySymbol,
            name: page.currencyCode,
            isCustom: true,
          ),
        );
      }
      await currencyService.setCurrency(page.currencyCode);
      if (!mounted) return;
      setState(() {
        _page = page;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  String _money(int cents) {
    final page = _page;
    if (page == null) return (cents / 100).toStringAsFixed(2);
    return '${page.currencySymbol}${(cents / 100).toStringAsFixed(2)}';
  }

  Future<bool> _canSelect(int stock) async {
    if (_page?.allowNegativeStock == true || stock > 0) return true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          LucideIcons.alertTriangle,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text('sales.out_of_stock_warning'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
    return false;
  }

  Widget _productImage(LanCatalogProduct product, ColorScheme cs) {
    if (!product.hasImage) {
      return Icon(
        product.hasVariants ? LucideIcons.layers : LucideIcons.package,
        color: cs.primary,
      );
    }
    final future = _imageFutures.putIfAbsent(
      product.id,
      () => sl<LanNetworkService>()
          .fetchRemoteProductImage(product.id)
          .catchError((_) => null),
    );
    return SizedBox.square(
      dimension: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ColoredBox(
          color: cs.surfaceContainerHighest,
          child: FutureBuilder<Uint8List?>(
            future: future,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes != null && bytes.isNotEmpty) {
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              }
              return Icon(LucideIcons.package, color: cs.onSurfaceVariant);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          _handle(cs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                if (_selected != null)
                  IconButton(
                    onPressed: () => setState(() => _selected = null),
                    icon: const Icon(LucideIcons.arrowLeft),
                  ),
                Expanded(
                  child: Text(
                    _selected?.name ?? 'sales.add_item'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_selected == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'sales.search_products'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: _search,
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildBody(scrollController, cs)),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController, ColorScheme cs) {
    if (_error != null) {
      return Center(
        child: TextButton.icon(
          onPressed: _load,
          icon: const Icon(LucideIcons.rotateCcw),
          label: Text('common.retry'.tr()),
        ),
      );
    }
    if (_page == null) return const Center(child: CircularProgressIndicator());
    final selected = _selected;
    if (selected != null) {
      if (selected.variants.isEmpty) {
        return Center(child: Text('sales.no_products'.tr()));
      }
      return ListView.separated(
        controller: scrollController,
        itemCount: selected.variants.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) {
          final variant = selected.variants[index];
          final details = [
            variant.colorName,
            variant.sizeName,
            variant.sku,
          ].whereType<String>().where((value) => value.trim().isNotEmpty);
          return ListTile(
            leading: _productImage(selected, cs),
            title: Text(details.join(' / ')),
            subtitle: Text(
              '${localizedQuantity(variant.stockQuantity, selected.measurementType)} • ${_money(variant.priceCents)}',
            ),
            trailing: const Icon(LucideIcons.plusCircle),
            onTap: () async {
              if (await _canSelect(variant.stockQuantity)) {
                widget.onSelected(selected, variant);
              }
            },
          );
        },
      );
    }

    final products = _page!.products;
    if (products.isEmpty) {
      return Center(child: Text('sales.no_products'.tr()));
    }
    return ListView.separated(
      controller: scrollController,
      itemCount: products.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final product = products[index];
        return ListTile(
          leading: _productImage(product, cs),
          title: Text(product.name),
          subtitle: Text(
            '${localizedQuantity(product.stockQuantity, product.measurementType)} • ${_money(product.priceCents)}',
          ),
          trailing: Icon(
            product.hasVariants
                ? LucideIcons.chevronRight
                : LucideIcons.plusCircle,
          ),
          onTap: () async {
            if (product.hasVariants) {
              setState(() => _selected = product);
              return;
            }
            if (await _canSelect(product.stockQuantity)) {
              widget.onSelected(product, null);
            }
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// ADD ITEM SHEET (Product + Variant Selection)
// Follows purchase_form_screen.dart _AddItemSheet pattern
// ═══════════════════════════════════════════════════════
class _AddItemSheet extends StatefulWidget {
  final Product? initialProduct;
  final void Function(
    Product product,
    ProductVariant? variant,
    int quantity,
    Decimal unitPrice,
  )
  onItemAdded;
  const _AddItemSheet({this.initialProduct, required this.onItemAdded});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  Product? _selectedProduct;
  final _searchController = TextEditingController();
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            _handle(cs),
            // Title row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (_selectedProduct != null)
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      onPressed: () => setState(() => _selectedProduct = null),
                    ),
                  Expanded(
                    child: Text(
                      _selectedProduct != null
                          ? _selectedProduct!.name
                          : 'sales.add_item'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Search + Category Filter (only when selecting product)
            if (_selectedProduct == null) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'sales.search_products'.tr(),
                    prefixIcon: const Icon(LucideIcons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  onChanged: (v) => context.read<ProductsBloc>().add(
                    ProductSearchRequested(v),
                  ),
                ),
              ),
              // Category filter chips
              BlocBuilder<CategoriesBloc, RealtimeState<List<Category>>>(
                builder: (context, catState) {
                  List<Category> categories = const [];
                  if (catState is RealtimeSuccess<List<Category>>) {
                    categories = catState.data;
                  } else if (catState is RealtimeLoading<List<Category>>) {
                    categories = catState.previousData ?? const [];
                  }
                  if (categories.isEmpty) return const SizedBox.shrink();

                  return SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 6),
                          child: ChoiceChip(
                            label: Text('sales.all_categories'.tr()),
                            selected: _selectedCategoryId == null,
                            onSelected: (_) =>
                                setState(() => _selectedCategoryId = null),
                            showCheckmark: false,
                            selectedColor: cs.primaryContainer,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        ...categories.map(
                          (cat) => Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(
                              label: Text(cat.name),
                              selected: _selectedCategoryId == cat.id,
                              onSelected: (_) => setState(() {
                                _selectedCategoryId =
                                    _selectedCategoryId == cat.id
                                    ? null
                                    : cat.id;
                              }),
                              showCheckmark: false,
                              selectedColor: cs.primaryContainer,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'sales.select_variant'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _selectedProduct == null
                  ? _buildProductList(scrollController)
                  : _buildVariantSelection(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProductList(ScrollController scrollController) {
    final cs = Theme.of(context).colorScheme;
    final currencyService = sl<CurrencyService>();

    return BlocBuilder<
      VariantPreviewsBloc,
      RealtimeState<Map<int, VariantPreview>>
    >(
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

            if (products == null) {
              return const Center(child: CircularProgressIndicator());
            }

            // Apply category filter
            final query = _searchController.text.toLowerCase();
            final filtered = products.where((p) {
              if (_selectedCategoryId != null &&
                  p.categoryId != _selectedCategoryId) {
                return false;
              }
              if (query.isEmpty) return true;
              return p.name.toLowerCase().contains(query) ||
                  (p.sku?.toLowerCase().contains(query) ?? false) ||
                  (p.barcode?.toLowerCase().contains(query) ?? false);
            }).toList();

            if (filtered.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.searchX,
                      size: 48,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'sales.no_products'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              controller: scrollController,
              itemCount: filtered.length,
              separatorBuilder: (context, i) => Divider(
                height: 1,
                indent: 56,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              itemBuilder: (context, index) {
                final product = filtered[index];
                final preview = previews[product.id];
                final sizeName = (!product.hasVariants
                    ? preview?.sizeName?.trim()
                    : null);
                final colorHex = (!product.hasVariants
                    ? preview?.colorHex?.trim()
                    : null);
                final shade = _tryParseHexColor(colorHex);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      product.hasVariants
                          ? LucideIcons.layers
                          : LucideIcons.package,
                      size: 20,
                      color: cs.primary,
                    ),
                  ),
                  title: Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Row(
                    children: [
                      // Identifier group takes the available space so the SKU is
                      // never truncated just to make room for a color dot.
                      Expanded(
                        child: Row(
                          children: [
                            if (product.sku != null) ...[
                              Flexible(
                                child: Text(
                                  'SKU: ${product.sku}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (sizeName != null && sizeName.isNotEmpty) ...[
                              Flexible(
                                child: Text(
                                  sizeName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (shade != null) const SizedBox(width: 6),
                            ],
                            if (shade != null)
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: shade,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: cs.outline),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!product.hasVariants) ...[
                        const SizedBox(width: 8),
                        Icon(
                          LucideIcons.warehouse,
                          size: 12,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          localizedQuantity(
                            product.stockQuantity,
                            product.measurementType,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          currencyService.format(
                            product.priceCents.toBigInt().toInt(),
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: product.hasVariants
                      ? Icon(
                          LucideIcons.chevronRight,
                          size: 20,
                          color: cs.primary,
                        )
                      : Icon(
                          LucideIcons.plusCircle,
                          size: 20,
                          color: cs.primary,
                        ),
                  onTap: () async {
                    if (product.hasVariants) {
                      setState(() => _selectedProduct = product);
                    } else {
                      // Check stock via default variant
                      try {
                        final variantRepo = sl<ProductVariantRepository>();
                        final defaultVariant = await variantRepo
                            .getDefaultVariantByProduct(product.id);
                        if (defaultVariant != null &&
                            defaultVariant.stockQuantity <= 0 &&
                            context.mounted) {
                          await showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              icon: Icon(
                                LucideIcons.alertTriangle,
                                color: Theme.of(ctx).colorScheme.error,
                                size: 32,
                              ),
                              title: Text('sales.out_of_stock_warning'.tr()),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text('common.ok'.tr()),
                                ),
                              ],
                            ),
                          );
                          return;
                        }
                      } catch (_) {
                        // If we can't check stock, allow the sale
                      }
                      if (context.mounted) {
                        widget.onItemAdded(
                          product,
                          null,
                          product.quantityScale,
                          product.priceCents,
                        );
                      }
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
      create: (context) =>
          sl<ProductVariantsBloc>()
            ..add(ProductVariantsInitialized(_selectedProduct!.id)),
      child:
          BlocBuilder<ProductVariantsBloc, RealtimeState<List<ProductVariant>>>(
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

              return FutureBuilder<
                ({
                  Map<int, String> sizeNameById,
                  Map<int, String?> colorHexById,
                })
              >(
                future: () async {
                  final colorRepo = sl<ProductColorRepository>();
                  final sizeRepo = sl<SizeRepository>();
                  final results = await Future.wait([
                    colorRepo.getAllColors(),
                    sizeRepo.getAllSizes(),
                  ]);
                  final colors = results[0] as List<dynamic>;
                  final sizes = results[1] as List<dynamic>;

                  final sizeNameById = <int, String>{};
                  for (final s in sizes) {
                    sizeNameById[(s as dynamic).id as int] =
                        (s as dynamic).name as String;
                  }
                  final colorHexById = <int, String?>{};
                  for (final c in colors) {
                    colorHexById[(c as dynamic).id as int] =
                        (c as dynamic).hexCode as String?;
                  }

                  return (
                    sizeNameById: sizeNameById,
                    colorHexById: colorHexById,
                  );
                }(),
                builder: (context, snapshot) {
                  final sizeNameById =
                      snapshot.data?.sizeNameById ?? const <int, String>{};
                  final colorHexById =
                      snapshot.data?.colorHexById ?? const <int, String?>{};

                  return ListView.separated(
                    itemCount: variants!.length,
                    separatorBuilder: (context, i) => Divider(
                      height: 1,
                      indent: 56,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    itemBuilder: (context, index) {
                      final variant = variants![index];
                      final sizeName = variant.sizeId == null
                          ? null
                          : sizeNameById[variant.sizeId!];
                      final colorHex = variant.colorId == null
                          ? null
                          : colorHexById[variant.colorId!];
                      final shade = _tryParseHexColor(colorHex);

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: shade != null
                                ? shade.withValues(alpha: 0.2)
                                : cs.tertiaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: shade != null
                                ? Border.all(color: shade)
                                : null,
                          ),
                          child: shade != null
                              ? Center(
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: shade,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                )
                              : Icon(
                                  LucideIcons.tag,
                                  size: 18,
                                  color: cs.tertiary,
                                ),
                        ),
                        title: Text(
                          variant.sku ?? 'Variant ${variant.id}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Row(
                          children: [
                            if (sizeName != null &&
                                sizeName.trim().isNotEmpty) ...[
                              Flexible(
                                child: Text(
                                  sizeName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (shade != null) const SizedBox(width: 6),
                            ],
                            if (shade != null) ...[
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: shade,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: cs.outline),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Icon(
                              LucideIcons.warehouse,
                              size: 12,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              localizedQuantity(
                                variant.stockQuantity,
                                _selectedProduct!.measurementType,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              LucideIcons.coins,
                              size: 12,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              currencyService.format(
                                variant.priceCents.toBigInt().toInt(),
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        trailing: Icon(
                          LucideIcons.plusCircle,
                          size: 20,
                          color: variant.stockQuantity > 0
                              ? cs.primary
                              : cs.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        onTap: () async {
                          if (variant.stockQuantity <= 0) {
                            await showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                icon: Icon(
                                  LucideIcons.alertTriangle,
                                  color: Theme.of(ctx).colorScheme.error,
                                  size: 32,
                                ),
                                title: Text('sales.out_of_stock_warning'.tr()),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: Text('common.ok'.tr()),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }
                          widget.onItemAdded(
                            _selectedProduct!,
                            variant,
                            _selectedProduct!.quantityScale,
                            variant.priceCents,
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
  final bool showSalesperson;
  final bool allowDiscounts;
  final void Function(
    int quantity,
    Decimal unitPrice,
    Decimal discount, {
    int? employeeId,
    String? employeeName,
    String? itemNote,
    bool clearEmployee,
  })
  onUpdated;
  final VoidCallback onRemoved;
  final bool canViewProductCost;
  const _EditItemSheet({
    required this.item,
    required this.onUpdated,
    required this.onRemoved,
    required this.canViewProductCost,
    this.showSalesperson = false,
    this.allowDiscounts = true,
  });

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late int _quantity;
  late TextEditingController _priceCtrl;
  late TextEditingController _discountCtrl;
  late TextEditingController _noteCtrl;
  late TextEditingController _quantityCtrl;
  late MeasurementUnit _quantityUnit;
  bool _discountIsPercent = false;
  int? _employeeId;
  String? _employeeName;

  @override
  void initState() {
    super.initState();
    _quantity = widget.item.quantity;
    _quantityUnit = widget.item.product.measurement.majorUnit;
    _priceCtrl = TextEditingController(
      text: (widget.item.unitPriceCents.toBigInt().toInt() / 100)
          .toStringAsFixed(2),
    );
    _discountCtrl = TextEditingController(
      text: widget.item.discountCents > Decimal.zero
          ? (widget.item.discountCents.toBigInt().toInt() / 100)
                .toStringAsFixed(2)
          : '',
    );
    _noteCtrl = TextEditingController(text: widget.item.itemNote ?? '');
    _quantityCtrl = TextEditingController(
      text: MeasuredQuantity.editableValue(_quantity, _quantityUnit),
    );
    _employeeId = widget.item.employeeId;
    _employeeName = widget.item.employeeName;
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    _noteCtrl.dispose();
    _quantityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final curr = sl<CurrencyService>();
    final variant = widget.item.variant;
    final stockQty =
        variant?.stockQuantity ?? widget.item.product.stockQuantity;
    final costCents = variant?.costCents ?? widget.item.product.costCents;
    final wholesalePrice =
        variant?.wholesalePriceCents ?? widget.item.product.wholesalePriceCents;
    final retailPrice = variant?.priceCents ?? widget.item.product.priceCents;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with barcode icon
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.package,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Product/variant identifier (SKU) — shown under the name like
                      // every other model. Color/size are already surfaced in
                      // `displayName` (e.g. "فستان مطرز (Pink)"), so we must never
                      // print the raw color hex (e.g. "#FFC0CB") here.
                      Builder(
                        builder: (context) {
                          final variantSku = widget.item.variant?.sku?.trim();
                          final productSku = widget.item.product.sku?.trim();
                          final sku =
                              (variantSku != null && variantSku.isNotEmpty)
                              ? variantSku
                              : (productSku ?? '');
                          if (sku.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'SKU: $sku',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                      if (variant?.barcode != null &&
                          variant!.barcode!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.scanLine,
                                size: 12,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                variant.barcode!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(LucideIcons.trash2, color: cs.error),
                  onPressed: widget.onRemoved,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Stock & Cost info row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.warehouse,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${'sales.available_stock'.tr()}: ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    localizedQuantity(
                      stockQty,
                      widget.item.product.measurementType,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: stockQty > 0 ? cs.primary : cs.error,
                    ),
                  ),
                  if (widget.canViewProductCost) ...[
                    const Spacer(),
                    Icon(
                      LucideIcons.coins,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${'sales.cost_price'.tr()}: ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      curr.format(costCents.toBigInt().toInt()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ── Sales Tax Rate (read-only info) ──
            if (widget.item.product.isTaxable &&
                widget.item.product.salesTaxRateBps > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.tertiary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.percent, size: 16, color: cs.tertiary),
                    const SizedBox(width: 8),
                    Text(
                      'sales.product_tax_rate'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(widget.item.product.salesTaxRateBps / 100).toStringAsFixed(2)}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Price with tier buttons
            Text(
              'sales.unit_price'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _priceTierBtn(
                  cs,
                  theme,
                  'sales.retail_price'.tr(),
                  retailPrice,
                  curr,
                ),
                if (wholesalePrice != null) ...[
                  const SizedBox(width: 6),
                  _priceTierBtn(
                    cs,
                    theme,
                    'sales.wholesale_price'.tr(),
                    wholesalePrice,
                    curr,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              onTap: () => selectAllText(_priceCtrl),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                isDense: true,
                prefixIcon: const Icon(LucideIcons.dollarSign, size: 18),
              ),
            ),
            const SizedBox(height: 16),

            // Quantity (editable text input with +/- buttons)
            Text(
              'sales.quantity'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: _quantity > _quantityUnit.internalFactor
                        ? () => setState(() {
                            _quantity -= _quantityUnit.internalFactor;
                            _quantityCtrl.text = MeasuredQuantity.editableValue(
                              _quantity,
                              _quantityUnit,
                            );
                          })
                        : null,
                    icon: const Icon(LucideIcons.minus, size: 18),
                  ),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _quantityCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                      ],
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      onTap: () => selectAllText(_quantityCtrl),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onChanged: (v) {
                        try {
                          final parsed = MeasuredQuantity.parseToStored(
                            v,
                            _quantityUnit,
                          );
                          if (parsed > 0) setState(() => _quantity = parsed);
                        } on FormatException {
                          // Keep the previous valid value while typing.
                        }
                      },
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      _quantity += _quantityUnit.internalFactor;
                      _quantityCtrl.text = MeasuredQuantity.editableValue(
                        _quantity,
                        _quantityUnit,
                      );
                    }),
                    icon: const Icon(LucideIcons.plus, size: 18),
                  ),
                  if (widget.item.product.measurement.minorUnit != null) ...[
                    const SizedBox(width: 8),
                    DropdownButton<MeasurementUnit>(
                      value: _quantityUnit,
                      items: widget.item.product.measurement.inputUnits
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit,
                              child: Text(
                                'measurement.units.${unit.dbValue}'.tr(),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (unit) {
                        if (unit == null) return;
                        setState(() {
                          _quantityUnit = unit;
                          _quantityCtrl.text = MeasuredQuantity.editableValue(
                            _quantity,
                            unit,
                          );
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Discount with % / $ toggle
            if (widget.allowDiscounts) ...[
              Row(
                children: [
                  Text(
                    'sales.item_discount'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(
                          curr.currencySymbol,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const ButtonSegment(
                        value: true,
                        label: Text('%', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {_discountIsPercent},
                    onSelectionChanged: (v) => setState(() {
                      _discountIsPercent = v.first;
                      _discountCtrl.clear();
                    }),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _discountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                onTap: () => selectAllText(_discountCtrl),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  isDense: true,
                  hintText: _discountIsPercent ? '0 %' : '0.00',
                  prefixIcon: Icon(
                    _discountIsPercent ? LucideIcons.percent : LucideIcons.tag,
                    size: 18,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
            ],

            // Item note
            Text(
              'sales.item_note'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'sales.item_note_hint'.tr(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                isDense: true,
                prefixIcon: const Icon(LucideIcons.stickyNote, size: 18),
              ),
            ),
            const SizedBox(height: 16),

            // Per-item salesperson
            if (widget.showSalesperson) ...[
              _buildItemSalesperson(theme, cs),
              const SizedBox(height: 16),
            ],

            // Preview totals (before & after tax)
            //
            // Phase 3.5.4 — the preview now goes through the same
            // [LineItemPricingEngine] that the bloc uses on submit, so a
            // tax-inclusive setting / global default rate / rounding-mode
            // change is reflected here without divergence (the historical
            // "preview shows X, posted invoice shows Y" bug class).
            Builder(
              builder: (context) {
                // Parse price using Decimal end-to-end (no `double` in money
                // arithmetic — IEEE-754 traps like 99999.99 * 100 are the
                // class of bug Phase 3.5 closes).
                final priceDec =
                    Decimal.tryParse(_priceCtrl.text.trim()) ?? Decimal.zero;
                final priceCents = (priceDec * Decimal.fromInt(100))
                    .round()
                    .toBigInt()
                    .toInt();
                final discountCents = _computeDiscountCents();
                final product = widget.item.product;
                // Source the global tax flags from the SaleFormBloc so the
                // preview honours `taxInclusivePricing` and the default rate
                // exactly like the bloc's [InvoicePricingEngine.compute] call.
                final saleState = context.read<SaleFormBloc>().state;
                final pricing = LineItemPricingEngine.compute(
                  input: LineItemPricingInput(
                    unitPrice: Money.fromCents(priceCents),
                    quantity: _quantity,
                    quantityScale: product.quantityScale,
                    discount: discountCents > 0
                        ? Discount.fixed(Money.fromCents(discountCents))
                        : Discount.none,
                    isTaxable: product.isTaxable,
                    productTaxRateBps: product.salesTaxRateBps,
                  ),
                  enableTaxCalculations: saleState.enableTaxCalculations,
                  defaultTaxRateBps: saleState.defaultSalesTaxRateBps,
                  taxInclusivePricing: saleState.taxInclusivePricing,
                );
                final taxCents = pricing.tax.cents;
                final totalAfterTax = pricing.total.cents;
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'sales.subtotal'.tr(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            curr.format(pricing.subtotal.cents),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (discountCents > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'sales.discount'.tr(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '- ${curr.format(discountCents)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.tertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (taxCents > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'sales.tax'.tr(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '+${curr.format(taxCents)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.tertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const Divider(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'sales.total'.tr(),
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            curr.format(totalAfterTax > 0 ? totalAfterTax : 0),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _onSave,
                icon: const Icon(LucideIcons.check, size: 18),
                label: Text('common.save'.tr()),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceTierBtn(
    ColorScheme cs,
    ThemeData theme,
    String tier,
    Decimal priceCents,
    CurrencyService curr,
  ) {
    final priceStr = (priceCents.toBigInt().toInt() / 100).toStringAsFixed(2);
    final isActive = _priceCtrl.text == priceStr;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _priceCtrl.text = priceStr),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? cs.primary : cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tier,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              curr.format(priceCents.toBigInt().toInt()),
              style: theme.textTheme.labelSmall?.copyWith(
                color: isActive ? cs.onPrimary : cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemSalesperson(ThemeData theme, ColorScheme cs) {
    final hasEmp = _employeeId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'sales.item_salesperson'.tr(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final lan = sl<LanNetworkService>();
            if (lan.snapshot.mode == LanMode.client &&
                lan.hasRemoteUserSession) {
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (sheetContext) => _RemoteEmployeePickerSheet(
                  onSelected: (employee) {
                    setState(() {
                      _employeeId = employee.id;
                      _employeeName = employee.name;
                    });
                    Navigator.pop(sheetContext);
                  },
                ),
              );
              return;
            }
            final result = await showModalBottomSheet<Employee>(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (sc) =>
                  _EmployeePickerSheet(onSelected: (e) => Navigator.pop(sc, e)),
            );
            if (result != null) {
              setState(() {
                _employeeId = result.id;
                _employeeName = result.name;
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.userCheck,
                  size: 16,
                  color: hasEmp ? cs.tertiary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasEmp ? _employeeName! : 'sales.select_salesperson'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: hasEmp ? null : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (hasEmp)
                  GestureDetector(
                    onTap: () => setState(() {
                      _employeeId = null;
                      _employeeName = null;
                    }),
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  int _computeDiscountCents() {
    final val = Decimal.tryParse(_discountCtrl.text.trim()) ?? Decimal.zero;
    if (_discountIsPercent) {
      final price = Decimal.tryParse(_priceCtrl.text.trim()) ?? Decimal.zero;
      final subtotalCents = MeasuredAmount.cents(
        unitCents: (price * Decimal.fromInt(100)).round().toBigInt().toInt(),
        quantity: _quantity,
        quantityScale: widget.item.product.quantityScale,
      );
      // Phase 3.5.5 — centralised percent → cents conversion.
      return sl<DiscountConverter>().fixedFromPercent(
        subtotalCents: subtotalCents,
        percent: val,
      );
    }
    return (val * Decimal.fromInt(100)).round().toBigInt().toInt();
  }

  void _onSave() {
    // Phase 3.5.4 — parse the price via Decimal so the saved value is
    // bit-identical to the preview shown by [LineItemPricingEngine].
    // Mixing `double.parse` here with the Decimal-based preview is
    // exactly how the "preview vs invoice differs by 1 cent" bug class
    // creeps back in.
    final priceDec = Decimal.tryParse(_priceCtrl.text.trim()) ?? Decimal.zero;
    final priceCents = (priceDec * Decimal.fromInt(100))
        .round()
        .toBigInt()
        .toInt();
    final discountCents = _computeDiscountCents();
    final note = _noteCtrl.text.trim();
    widget.onUpdated(
      _quantity,
      Decimal.fromInt(priceCents),
      Decimal.fromInt(discountCents),
      employeeId: _employeeId,
      employeeName: _employeeName,
      itemNote: note.isEmpty ? null : note,
      clearEmployee: _employeeId == null && widget.item.employeeId != null,
    );
  }
}

// ═══════════════════════════════════════════════════════
// CHECKOUT SHEET
// ═══════════════════════════════════════════════════════
class _CheckoutSheet extends StatefulWidget {
  final CurrencyService currencyService;
  final TextEditingController notesCtrl;
  final VoidCallback onConfirm;

  const _CheckoutSheet({
    required this.currencyService,
    required this.notesCtrl,
    required this.onConfirm,
  });

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late final TextEditingController _paidCtrl;
  late final TextEditingController _discountPercentCtrl;
  late final TextEditingController _discountFixedCtrl;
  bool _updatingDiscount = false;
  bool _hasHydratedFromBloc = false;
  bool _loyaltyLoadTriggered = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<SaleFormBloc>().state;
    _paidCtrl = TextEditingController(
      text: state.paidAmountCents > Decimal.zero
          ? (state.paidAmountCents.toBigInt().toInt() / 100).toStringAsFixed(2)
          : '',
    );

    final discCents = state.invoiceDiscountCents.toBigInt().toInt();
    final subtotalCents = state.subtotalCents.toBigInt().toInt();
    _discountFixedCtrl = TextEditingController(
      text: discCents > 0 ? (discCents / 100).toStringAsFixed(2) : '',
    );
    _discountPercentCtrl = TextEditingController(
      text: discCents > 0 && subtotalCents > 0
          ? ((discCents / subtotalCents) * 100).toStringAsFixed(2)
          : '',
    );

    _discountPercentCtrl.addListener(_syncDiscountFromPercent);
    _discountFixedCtrl.addListener(_syncDiscountFromFixed);
  }

  void _hydrateControllersIfNeeded(SaleFormState state) {
    final focused = FocusManager.instance.primaryFocus;
    final isEditingText = focused?.context?.widget is EditableText;
    if (isEditingText) return;

    if (!_hasHydratedFromBloc) {
      final paidText = state.paidAmountCents > Decimal.zero
          ? (state.paidAmountCents.toBigInt().toInt() / 100).toStringAsFixed(2)
          : '';
      if (_paidCtrl.text != paidText) _paidCtrl.text = paidText;

      final discCents = state.invoiceDiscountCents.toBigInt().toInt();
      final subtotalCents = state.subtotalCents.toBigInt().toInt();
      final fixedText = discCents > 0
          ? (discCents / 100).toStringAsFixed(2)
          : '';
      final pctText = discCents > 0 && subtotalCents > 0
          ? ((discCents / subtotalCents) * 100).toStringAsFixed(2)
          : '';

      if (_discountFixedCtrl.text != fixedText) {
        _discountFixedCtrl.text = fixedText;
      }
      if (_discountPercentCtrl.text != pctText) {
        _discountPercentCtrl.text = pctText;
      }

      _hasHydratedFromBloc = true;
    }
  }

  void _syncDiscountFromPercent() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    // Phase 3.5.5 — percent → fixed handled by the central converter so
    // this screen can never drift from the line-edit discount helper.
    final pct =
        Decimal.tryParse(_discountPercentCtrl.text.trim()) ?? Decimal.zero;
    final sub = context
        .read<SaleFormBloc>()
        .state
        .subtotalCents
        .toBigInt()
        .toInt();
    final cents = sl<DiscountConverter>().fixedFromPercent(
      subtotalCents: sub,
      percent: pct,
    );
    _discountFixedCtrl.text = cents > 0 ? (cents / 100).toStringAsFixed(2) : '';
    _applyInvoiceDiscount();
    _updatingDiscount = false;
  }

  void _syncDiscountFromFixed() {
    if (_updatingDiscount) return;
    _updatingDiscount = true;
    final fixedVal =
        Decimal.tryParse(_discountFixedCtrl.text.trim()) ?? Decimal.zero;
    final fixedCents = (fixedVal * Decimal.fromInt(100))
        .round()
        .toBigInt()
        .toInt();
    final sub = context
        .read<SaleFormBloc>()
        .state
        .subtotalCents
        .toBigInt()
        .toInt();
    final pct = sl<DiscountConverter>().percentFromFixed(
      subtotalCents: sub,
      fixedCents: fixedCents,
    );
    _discountPercentCtrl.text = pct == Decimal.zero ? '' : pct.toString();
    _applyInvoiceDiscount();
    _updatingDiscount = false;
  }

  void _applyInvoiceDiscount() {
    final fixedVal = double.tryParse(_discountFixedCtrl.text) ?? 0;
    final cents = (fixedVal * 100).round();
    context.read<SaleFormBloc>().add(
      SaleInvoiceDiscountChanged(Decimal.fromInt(cents)),
    );
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    _discountPercentCtrl.dispose();
    _discountFixedCtrl.dispose();
    super.dispose();
  }

  void _ensureLoyaltyDataLoaded(BuildContext context, SaleFormState state) {
    if (_loyaltyLoadTriggered) return;
    if (state.customerId != null && state.loyaltySettings == null) {
      _loyaltyLoadTriggered = true;
      context.read<SaleFormBloc>().add(
        SaleLoyaltyDataRequested(state.customerId!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BlocBuilder<SaleFormBloc, SaleFormState>(
      builder: (context, state) {
        _hydrateControllersIfNeeded(state);
        _ensureLoyaltyDataLoaded(context, state);
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollCtrl) => Column(
            children: [
              _handle(cs),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(LucideIcons.shoppingBag, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'sales.checkout'.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('common.cancel'.tr()),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Customer Selection
                    _section(
                      theme,
                      cs,
                      LucideIcons.users,
                      'sales.customer'.tr(),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _showCustomerPickerInCheckout(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: cs.outlineVariant),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              if (state.customerName != null) ...[
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: cs.primaryContainer,
                                  child: Text(
                                    state.customerName![0].toUpperCase(),
                                    style: TextStyle(
                                      color: cs.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Text(
                                  state.customerName ??
                                      'sales.select_customer'.tr(),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: state.customerName != null
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                    color: state.customerName != null
                                        ? null
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (state.customerId != null)
                                GestureDetector(
                                  onTap: () => context.read<SaleFormBloc>().add(
                                    const SaleCustomerChanged(),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      end: 4,
                                    ),
                                    child: Icon(
                                      LucideIcons.x,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              Icon(
                                LucideIcons.chevronDown,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Customer Balance Info
                    if (state.customerId != null &&
                        sl<LanNetworkService>().snapshot.mode != LanMode.client)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: _CustomerBalanceInfo(
                          customerId: state.customerId!,
                          invoiceTotalCents: state.totalCents
                              .toBigInt()
                              .toInt(),
                          paidAmountCents: state.paidAmountCents
                              .toBigInt()
                              .toInt(),
                          currencyService: widget.currencyService,
                        ),
                      ),
                    // Loyalty Points Redemption
                    if (state.canOfferLoyaltyRedemption) ...[
                      _LoyaltyRedemptionSection(
                        state: state,
                        currencyService: widget.currencyService,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Payment Method
                    _section(
                      theme,
                      cs,
                      LucideIcons.wallet,
                      'sales.payment_method'.tr(),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: SalePaymentMethod.values.map((m) {
                          final sel = state.paymentMethod == m;
                          return ChoiceChip(
                            label: Text(_pmLabel(m)),
                            selected: sel,
                            onSelected: (_) => context.read<SaleFormBloc>().add(
                              SalePaymentMethodChanged(m),
                            ),
                            avatar: Icon(_pmIcon(m), size: 16),
                            selectedColor: cs.primaryContainer,
                            showCheckmark: false,
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Cheque due date (only for cheque)
                    if (state.paymentMethod == SalePaymentMethod.cheque) ...[
                      _section(
                        theme,
                        cs,
                        LucideIcons.calendar,
                        'sales.cheque_due_date'.tr(),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  state.dueDate ??
                                  DateTime.now().add(const Duration(days: 30)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null && context.mounted) {
                              context.read<SaleFormBloc>().add(
                                SaleDueDateChanged(picked),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: cs.outlineVariant),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.calendar,
                                  size: 18,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    state.dueDate != null
                                        ? '${state.dueDate!.year}-${state.dueDate!.month.toString().padLeft(2, '0')}-${state.dueDate!.day.toString().padLeft(2, '0')}'
                                        : 'sales.select_due_date'.tr(),
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: state.dueDate != null
                                          ? null
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Icon(
                                  LucideIcons.chevronDown,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Credit/Cheque info message
                    if (state.paymentMethod == SalePaymentMethod.credit ||
                        state.paymentMethod == SalePaymentMethod.cheque) ...[
                      if (state.customerId == null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.alertTriangle,
                                size: 16,
                                color: cs.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'sales.customer_required_for_credit'.tr(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer.withValues(
                                  alpha: 0.3,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: cs.tertiary.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.info,
                                    size: 16,
                                    color: cs.tertiary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'sales.credit_balance_info'.tr(),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Receiving a separate customer payment is a
                            // different master transaction and is hidden until
                            // that original screen receives a remote gateway.
                            if (sl<LanNetworkService>().snapshot.mode !=
                                LanMode.client)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    // Navigate to receive payment screen with customer pre-selected
                                    context.push(
                                      '/customers/receive-payment',
                                      extra: {'customerId': state.customerId},
                                    );
                                  },
                                  icon: const Icon(
                                    LucideIcons.banknote,
                                    size: 18,
                                  ),
                                  label: Text('sales.add_payment'.tr()),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    side: BorderSide(color: cs.primary),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 16),
                    ],

                    // Tax (read-only, sum of line item taxes)
                    if (state.taxCents > Decimal.zero) ...[
                      _section(
                        theme,
                        cs,
                        LucideIcons.percent,
                        'sales.tax'.tr(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.receipt,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.currencyService.format(
                                  state.taxCents.toBigInt().toInt(),
                                ),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'sales.tax_from_products'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Invoice Discount (if invoice mode and allowed)
                    if (state.allowDiscounts &&
                        state.discountMode == SaleDiscountMode.invoice) ...[
                      _section(
                        theme,
                        cs,
                        LucideIcons.tag,
                        'sales.invoice_discount'.tr(),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _discountFixedCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d.]'),
                                  ),
                                ],
                                onTap: () => selectAllText(_discountFixedCtrl),
                                decoration: InputDecoration(
                                  labelText: 'purchases.discount_fixed'.tr(),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _discountPercentCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d.]'),
                                  ),
                                ],
                                onTap: () =>
                                    selectAllText(_discountPercentCtrl),
                                decoration: InputDecoration(
                                  labelText: 'purchases.discount_percent'.tr(),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Paid Amount (only for cash)
                    if (state.paymentMethod == SalePaymentMethod.cash) ...[
                      _section(
                        theme,
                        cs,
                        LucideIcons.banknote,
                        'sales.paid_amount'.tr(),
                        child: TextField(
                          controller: _paidCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                          ],
                          onTap: () => selectAllText(_paidCtrl),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            isDense: true,
                            hintText:
                                (state.totalCents.toBigInt().toInt() / 100)
                                    .toStringAsFixed(2),
                            prefixIcon: const Icon(
                              LucideIcons.dollarSign,
                              size: 18,
                            ),
                          ),
                          onChanged: (v) {
                            final val = double.tryParse(v) ?? 0;
                            context.read<SaleFormBloc>().add(
                              SalePaidAmountChanged(
                                Decimal.fromInt((val * 100).round()),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Remaining / Change display
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: state.changeCents > Decimal.zero
                              ? Colors.green.withValues(alpha: 0.08)
                              : state.remainingCents > Decimal.zero
                              ? cs.errorContainer.withValues(alpha: 0.3)
                              : cs.primaryContainer.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: state.changeCents > Decimal.zero
                                ? Colors.green.withValues(alpha: 0.3)
                                : state.remainingCents > Decimal.zero
                                ? cs.error.withValues(alpha: 0.2)
                                : cs.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Underpayment warning (cash with customer selected)
                            if (state.remainingCents > Decimal.zero &&
                                state.customerId != null)
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        LucideIcons.alertTriangle,
                                        size: 16,
                                        color: cs.error,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'sales.underpayment_warning'.tr(),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(color: cs.error),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _cRow(
                                    theme,
                                    'sales.remaining'.tr(),
                                    widget.currencyService.format(
                                      state.remainingCents.toBigInt().toInt(),
                                    ),
                                    isBold: true,
                                    valueColor: cs.error,
                                  ),
                                ],
                              )
                            // Underpayment without customer (walk-in)
                            else if (state.remainingCents > Decimal.zero)
                              _cRow(
                                theme,
                                'sales.remaining'.tr(),
                                widget.currencyService.format(
                                  state.remainingCents.toBigInt().toInt(),
                                ),
                                isBold: true,
                                valueColor: cs.error,
                              ),
                            // Overpayment with customer - show options
                            if (state.changeCents > Decimal.zero &&
                                state.customerId != null) ...[
                              _cRow(
                                theme,
                                'sales.overpayment_amount'.tr(),
                                widget.currencyService.format(
                                  state.changeCents.toBigInt().toInt(),
                                ),
                                isBold: true,
                                valueColor: Colors.green,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'sales.overpayment_handling'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ChoiceChip(
                                      label: Text('sales.return_change'.tr()),
                                      selected:
                                          state.overpaymentHandling ==
                                          SaleOverpaymentHandling.returnChange,
                                      onSelected: (_) =>
                                          context.read<SaleFormBloc>().add(
                                            const SaleOverpaymentHandlingChanged(
                                              SaleOverpaymentHandling
                                                  .returnChange,
                                            ),
                                          ),
                                      avatar: const Icon(
                                        LucideIcons.banknote,
                                        size: 16,
                                      ),
                                      selectedColor: cs.primaryContainer,
                                      showCheckmark: false,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ChoiceChip(
                                      label: Text('sales.add_to_balance'.tr()),
                                      selected:
                                          state.overpaymentHandling ==
                                          SaleOverpaymentHandling.addToBalance,
                                      onSelected: (_) =>
                                          context.read<SaleFormBloc>().add(
                                            const SaleOverpaymentHandlingChanged(
                                              SaleOverpaymentHandling
                                                  .addToBalance,
                                            ),
                                          ),
                                      avatar: const Icon(
                                        LucideIcons.wallet,
                                        size: 16,
                                      ),
                                      selectedColor: cs.primaryContainer,
                                      showCheckmark: false,
                                    ),
                                  ),
                                ],
                              ),
                            ]
                            // Overpayment without customer (walk-in) - just show change
                            else if (state.changeCents > Decimal.zero)
                              _cRow(
                                theme,
                                'sales.change'.tr(),
                                widget.currencyService.format(
                                  state.changeCents.toBigInt().toInt(),
                                ),
                                isBold: true,
                                valueColor: Colors.green,
                              ),
                            if (state.remainingCents == Decimal.zero &&
                                state.changeCents == Decimal.zero)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    LucideIcons.checkCircle,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'sales.fully_paid'.tr(),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Financial Summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          _cRow(
                            theme,
                            'sales.subtotal'.tr(),
                            widget.currencyService.format(
                              state.subtotalCents.toBigInt().toInt(),
                            ),
                          ),
                          if (state.totalDiscountCents > Decimal.zero) ...[
                            const SizedBox(height: 8),
                            _cRow(
                              theme,
                              'sales.discount'.tr(),
                              '- ${widget.currencyService.format(state.totalDiscountCents.toBigInt().toInt())}',
                              valueColor: cs.tertiary,
                            ),
                          ],
                          if (state.taxCents > Decimal.zero) ...[
                            const SizedBox(height: 8),
                            _cRow(
                              theme,
                              'sales.tax'.tr(),
                              widget.currencyService.format(
                                state.taxCents.toBigInt().toInt(),
                              ),
                            ),
                          ],
                          if (state.loyaltyDiscountCents > 0) ...[
                            const SizedBox(height: 8),
                            _cRow(
                              theme,
                              'sales.loyalty_discount'.tr(),
                              '- ${widget.currencyService.format(state.loyaltyDiscountCents)}',
                              valueColor: Colors.deepPurple,
                            ),
                          ],
                          Divider(
                            height: 20,
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                          _cRow(
                            theme,
                            'sales.total'.tr(),
                            widget.currencyService.format(
                              state.totalCents.toBigInt().toInt(),
                            ),
                            isBold: true,
                            valueColor: cs.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Notes
                    _section(
                      theme,
                      cs,
                      LucideIcons.stickyNote,
                      'sales.notes'.tr(),
                      child: TextField(
                        controller: widget.notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'sales.notes_hint'.tr(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                        ),
                        onChanged: (v) => context.read<SaleFormBloc>().add(
                          SaleNotesChanged(v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),

              // Bottom actions
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(
                    top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.05),
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
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'sales.total'.tr(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              widget.currencyService.format(
                                state.totalCents.toBigInt().toInt(),
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Builder(
                          builder: (ctx) {
                            final cashInsufficient =
                                state.paymentMethod == SalePaymentMethod.cash &&
                                state.paidAmountCents < state.totalCents;
                            final chequeNoDueDate =
                                state.paymentMethod ==
                                    SalePaymentMethod.cheque &&
                                state.dueDate == null;
                            final customerRequiredButMissing =
                                (state.paymentMethod ==
                                        SalePaymentMethod.credit ||
                                    state.paymentMethod ==
                                        SalePaymentMethod.cheque) &&
                                state.customerId == null;
                            final canConfirm =
                                !state.isSubmitting &&
                                !cashInsufficient &&
                                !chequeNoDueDate &&
                                !customerRequiredButMissing;
                            return FilledButton.icon(
                              onPressed: canConfirm ? widget.onConfirm : null,
                              icon: state.isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(LucideIcons.check, size: 18),
                              label: Text('sales.confirm_save'.tr()),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _section(
    ThemeData theme,
    ColorScheme cs,
    IconData icon,
    String title, {
    required Widget child,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      child,
    ],
  );

  Widget _cRow(
    ThemeData t,
    String l,
    String v, {
    bool isBold = false,
    Color? valueColor,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        l,
        style: (isBold ? t.textTheme.titleSmall : t.textTheme.bodyMedium)
            ?.copyWith(color: isBold ? null : t.colorScheme.onSurfaceVariant),
      ),
      Text(
        v,
        style: (isBold ? t.textTheme.titleMedium : t.textTheme.bodyMedium)
            ?.copyWith(
              color: valueColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            ),
      ),
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

  void _showCustomerPickerInCheckout(BuildContext context) {
    final lan = sl<LanNetworkService>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) =>
          lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession
          ? _RemoteCustomerPickerSheet(
              onSelected: (customer) {
                context.read<SaleFormBloc>().add(
                  SaleCustomerChanged(
                    customerId: customer.id,
                    customerName: customer.name,
                  ),
                );
                Navigator.pop(sheetCtx);
              },
            )
          : _CustomerPickerSheet(
              onSelected: (customer) {
                context.read<SaleFormBloc>().add(
                  SaleCustomerChanged(
                    customerId: customer.id,
                    customerName: customer.name,
                  ),
                );
                Navigator.pop(sheetCtx);
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CUSTOMER BALANCE INFO (inline widget in checkout)
// ═══════════════════════════════════════════════════════
class _CustomerBalanceInfo extends StatelessWidget {
  final int customerId;
  final int invoiceTotalCents;
  final int paidAmountCents;
  final CurrencyService currencyService;

  const _CustomerBalanceInfo({
    required this.customerId,
    required this.invoiceTotalCents,
    required this.paidAmountCents,
    required this.currencyService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<Customer?>(
      stream: sl<CustomerRepository>().watchCustomer(customerId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final customer = snapshot.data!;
        final currentBalanceCents = customer.balanceCents.toBigInt().toInt();
        // Phase 3.5.6 — projection lives in [PartyBalanceClassifier].
        // The widget no longer hand-rolls the `+ invoice − paid`
        // formula, so future tweaks (advances, FX, cheque fees) ripple
        // through one service instead of every screen.
        final classifier = sl<PartyBalanceClassifier>();
        final projectedBalanceCents = classifier.project(
          currentBalanceCents: currentBalanceCents,
          invoiceTotalCents: invoiceTotalCents,
          paidAmountCents: paidAmountCents,
          kind: PartyKind.customer,
        );

        final isCurrentReceivable = currentBalanceCents > 0;
        final isProjectedReceivable = projectedBalanceCents > 0;

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showBalanceDetailDialog(
            context,
            customer: customer,
            currentBalanceCents: currentBalanceCents,
            projectedBalanceCents: projectedBalanceCents,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'sales.customer_balance'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Directionality(
                  textDirection: ui.TextDirection.ltr,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currencyService.format(currentBalanceCents),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isCurrentReceivable ? cs.error : Colors.green,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        LucideIcons.arrowRight,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        currencyService.format(projectedBalanceCents),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isProjectedReceivable
                              ? cs.error
                              : Colors.green,
                        ),
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

  void _showBalanceDetailDialog(
    BuildContext context, {
    required Customer customer,
    required int currentBalanceCents,
    required int projectedBalanceCents,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isCurrentReceivable = currentBalanceCents > 0;
    final isProjectedReceivable = projectedBalanceCents > 0;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.wallet, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'sales.customer_account'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Customer name
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      customer.name.isNotEmpty
                          ? customer.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      customer.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Current balance
            _balanceRow(
              theme: theme,
              cs: cs,
              icon: LucideIcons.wallet,
              label: 'sales.current_balance'.tr(),
              amount: currencyService.format(currentBalanceCents),
              amountColor: isCurrentReceivable ? cs.error : Colors.green,
              subtitle: isCurrentReceivable
                  ? 'sales.balance_owes_you'.tr()
                  : 'sales.balance_credit'.tr(),
            ),
            const SizedBox(height: 12),
            // Invoice amount
            _balanceRow(
              theme: theme,
              cs: cs,
              icon: LucideIcons.fileText,
              label: 'sales.this_invoice'.tr(),
              amount: '+ ${currencyService.format(invoiceTotalCents)}',
              amountColor: cs.error,
              subtitle: paidAmountCents > 0
                  ? '${'sales.paid_now'.tr()}: - ${currencyService.format(paidAmountCents)}'
                  : null,
            ),
            Divider(
              height: 24,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            // Projected balance
            _balanceRow(
              theme: theme,
              cs: cs,
              icon: LucideIcons.trendingUp,
              label: 'sales.projected_balance'.tr(),
              amount: currencyService.format(projectedBalanceCents),
              amountColor: isProjectedReceivable ? cs.error : Colors.green,
              subtitle: isProjectedReceivable
                  ? 'sales.balance_owes_you'.tr()
                  : 'sales.balance_credit'.tr(),
              isBold: true,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _balanceRow({
    required ThemeData theme,
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required String amount,
    required Color amountColor,
    String? subtitle,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
        Text(
          amount,
          style:
              (isBold
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    color: amountColor,
                  ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// LOYALTY POINTS REDEMPTION SECTION
// ═══════════════════════════════════════════════════════
class _LoyaltyRedemptionSection extends StatefulWidget {
  final SaleFormState state;
  final CurrencyService currencyService;

  const _LoyaltyRedemptionSection({
    required this.state,
    required this.currencyService,
  });

  @override
  State<_LoyaltyRedemptionSection> createState() =>
      _LoyaltyRedemptionSectionState();
}

class _LoyaltyRedemptionSectionState extends State<_LoyaltyRedemptionSection> {
  late TextEditingController _pointsCtrl;

  @override
  void initState() {
    super.initState();
    _pointsCtrl = TextEditingController(
      text: widget.state.loyaltyPointsToRedeem > 0
          ? widget.state.loyaltyPointsToRedeem.toString()
          : '',
    );
  }

  @override
  void didUpdateWidget(covariant _LoyaltyRedemptionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.loyaltyPointsToRedeem !=
        widget.state.loyaltyPointsToRedeem) {
      final newText = widget.state.loyaltyPointsToRedeem > 0
          ? widget.state.loyaltyPointsToRedeem.toString()
          : '';
      if (_pointsCtrl.text != newText) {
        _pointsCtrl.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _pointsCtrl.dispose();
    super.dispose();
  }

  int _maxRedeemablePoints() {
    final settings = widget.state.loyaltySettings;
    if (settings == null) return 0;

    final pointValueCents = settings.pointValueCents;
    final maxPercentBps = settings.maxRedemptionPercentBps;
    final invoiceTotal = widget.state.totalBeforeLoyaltyCents
        .toBigInt()
        .toInt();

    final maxDiscountFromPercent = (invoiceTotal * maxPercentBps) ~/ 10000;
    final maxDiscountFromPoints =
        widget.state.loyaltyPointsBalance * pointValueCents;
    final maxDiscount = [
      maxDiscountFromPercent,
      maxDiscountFromPoints,
      invoiceTotal,
    ].reduce((a, b) => a < b ? a : b);

    return pointValueCents > 0 ? maxDiscount ~/ pointValueCents : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final settings = widget.state.loyaltySettings!;
    final pointValueCents = settings.pointValueCents;
    final balance = widget.state.loyaltyPointsBalance;
    final balanceValueCents = balance * pointValueCents;
    final maxPoints = _maxRedeemablePoints();
    final maxPercent = (settings.maxRedemptionPercentBps / 100).toStringAsFixed(
      0,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(LucideIcons.award, size: 18, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text(
                'sales.loyalty_points'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.deepPurple,
                ),
              ),
              const Spacer(),
              // Points balance badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$balance ${'sales.points'.tr()}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Points value info
          Row(
            children: [
              Icon(LucideIcons.coins, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '${'sales.points_value'.tr()}: ${widget.currencyService.format(balanceValueCents)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '${'sales.max_discount'.tr()}: $maxPercent%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Toggle + redeem controls
          Row(
            children: [
              Switch.adaptive(
                value: widget.state.loyaltyRedemptionEnabled,
                activeTrackColor: Colors.deepPurple,
                onChanged: (enabled) {
                  if (enabled) {
                    // Auto-set to max redeemable points
                    context.read<SaleFormBloc>().add(
                      SaleLoyaltyRedemptionChanged(
                        enabled: true,
                        pointsToRedeem: maxPoints,
                      ),
                    );
                  } else {
                    context.read<SaleFormBloc>().add(
                      const SaleLoyaltyRedemptionChanged(
                        enabled: false,
                        pointsToRedeem: 0,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'sales.use_loyalty_points'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: widget.state.loyaltyRedemptionEnabled
                        ? Colors.deepPurple
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),

          // Points input + slider (only when enabled)
          if (widget.state.loyaltyRedemptionEnabled && maxPoints > 0) ...[
            const SizedBox(height: 8),
            // Slider
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: Colors.deepPurple,
                thumbColor: Colors.deepPurple,
                inactiveTrackColor: Colors.deepPurple.withValues(alpha: 0.15),
                overlayColor: Colors.deepPurple.withValues(alpha: 0.1),
              ),
              child: Slider(
                value: widget.state.loyaltyPointsToRedeem.toDouble(),
                min: 0,
                max: maxPoints.toDouble(),
                divisions: maxPoints > 0 ? maxPoints : 1,
                label: '${widget.state.loyaltyPointsToRedeem}',
                onChanged: (val) {
                  context.read<SaleFormBloc>().add(
                    SaleLoyaltyRedemptionChanged(
                      enabled: true,
                      pointsToRedeem: val.round(),
                    ),
                  );
                },
              ),
            ),
            // Points input field
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pointsCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onTap: () => selectAllText(_pointsCtrl),
                    decoration: InputDecoration(
                      labelText: 'sales.points_to_redeem'.tr(),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                      suffixText: '/ $maxPoints',
                    ),
                    onChanged: (v) {
                      final pts = int.tryParse(v) ?? 0;
                      context.read<SaleFormBloc>().add(
                        SaleLoyaltyRedemptionChanged(
                          enabled: true,
                          pointsToRedeem: pts,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Quick max button
                FilledButton.tonal(
                  onPressed: () {
                    context.read<SaleFormBloc>().add(
                      SaleLoyaltyRedemptionChanged(
                        enabled: true,
                        pointsToRedeem: maxPoints,
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.deepPurple.withValues(alpha: 0.12),
                    foregroundColor: Colors.deepPurple,
                  ),
                  child: Text('sales.max'.tr()),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Discount preview
            if (widget.state.loyaltyDiscountCents > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.tag,
                      size: 14,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'sales.loyalty_discount'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.deepPurple,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '- ${widget.currencyService.format(widget.state.loyaltyDiscountCents)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
