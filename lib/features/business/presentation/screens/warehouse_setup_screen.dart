import 'warehouse_reports_screen.dart';
import 'warehouse_valuation_screen.dart';
import '../../../../core/measurement/measurement.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart' show BusinessWarehouse;
import '../../data/warehouse_setup_service.dart';
import 'warehouse_stocktake_screen.dart';

/// Local multi-warehouse setup included in the existing Pro plan.
/// Online branch synchronization has a separate commercial boundary.
class WarehouseSetupScreen extends StatefulWidget {
  const WarehouseSetupScreen({super.key, required this.service});
  final WarehouseSetupService service;
  @override
  State<WarehouseSetupScreen> createState() => _WarehouseSetupScreenState();
}

class _WarehouseSetupScreenState extends State<WarehouseSetupScreen> {
  final _query = TextEditingController();
  final _cost = TextEditingController();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  final _lot = TextEditingController();
  bool _opening = false;
  DateTime? _expiry;
  final _form = GlobalKey<FormState>();
  List<BusinessWarehouse> _warehouses = [];
  List<WarehouseSetupItem> _items = [];
  String? _warehouse;
  WarehouseSetupItem? _item;
  String? _message;
  bool _busy = true;
  bool _canCreate = false;
  int _offset = 0;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _cost.dispose();
    _quantity.dispose();
    _reason.dispose();
    _lot.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final rows = await widget.service.warehouses();
      final canCreate = await widget.service.canCreateWarehouse();
      if (!mounted) return;
      setState(() {
        _warehouses = rows;
        _canCreate = canCreate;
        _warehouse = null;
        _items = [];
        _item = null;
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'warehouse_setup.unavailable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createWarehouse() async {
    var selectedName = '';
    var selectedCode = '';
    final form = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('warehouse_setup.create_warehouse'.tr()),
        content: SizedBox(
          width: 440,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    onChanged: (value) => selectedName = value,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: 'warehouse_setup.warehouse_name'.tr(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'warehouse_setup.required'.tr()
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (value) => selectedCode = value,
                    maxLength: 32,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'warehouse_setup.warehouse_code'.tr(),
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$',
                        ).hasMatch((value ?? '').trim())
                        ? null
                        : 'warehouse_setup.invalid_code'.tr(),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('warehouse_setup.back'.tr()),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: Text('warehouse_setup.create_warehouse'.tr()),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      final created = await widget.service.createWarehouse(
        name: selectedName,
        code: selectedCode,
      );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _warehouse = created.id);
      await _loadItems();
    } catch (_) {
      if (mounted) setState(() => _message = 'warehouse_setup.create_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadItems() async {
    final warehouse = _warehouse;
    if (warehouse == null) return;
    setState(() {
      _busy = true;
      _item = null;
      _items = [];
      _message = null;
    });
    _cost.clear();
    _quantity.clear();
    _reason.clear();
    _lot.clear();
    _expiry = null;
    _opening = false;
    try {
      final items = await widget.service.items(
        warehouse,
        query: _search,
        offset: _offset,
      );
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _message = 'warehouse_setup.load_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy ||
        _warehouse == null ||
        _item == null ||
        !_form.currentState!.validate()) {
      return;
    }
    if (_opening) {
      if (_item!.tracking == 'batch_expiry' && _expiry == null) {
        setState(() => _message = 'warehouse_setup.expiry_required');
        return;
      }
      final total = MeasuredAmount.cents(
        unitCents: _item!.parseCost(_cost.text),
        quantity: _item!.parseQuantity(_quantity.text),
        quantityScale: _item!.quantityScale,
      );
      final factor = List.filled(
        _item!.decimalDigits,
        10,
      ).fold<int>(1, (a, b) => a * b);
      final value = NumberFormat.currency(
        locale: context.locale.toString(),
        symbol: _item!.currencyCode,
        decimalDigits: _item!.decimalDigits,
      ).format(total / factor);
      final selected = _warehouses.firstWhere((w) => w.id == _warehouse);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('warehouse_setup.review'.tr()),
          content: SingleChildScrollView(
            child: Text(
              'warehouse_setup.review_body'.tr(
                namedArgs: {
                  'warehouse': selected.name.isEmpty
                      ? selected.code
                      : selected.name,
                  'product': _item!.name,
                  'quantity': _quantity.text,
                  'value': value,
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('warehouse_setup.back'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('warehouse_setup.confirm'.tr()),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final opening = _opening;
      final count = opening
          ? await widget.service.initializeOpening(
              warehouseId: _warehouse!,
              item: _item!,
              cost: _cost.text,
              quantity: _quantity.text,
              reason: _reason.text,
              expiryDate: _expiry,
              manufacturerLotNumber: _lot.text.isEmpty ? null : _lot.text,
            )
          : await widget.service.initialize(
              warehouseId: _warehouse!,
              item: _item!,
              cost: _cost.text,
            );
      if (!mounted) return;
      await _loadItems();
      if (mounted) {
        setState(
          () => _message = count == 0
              ? 'warehouse_setup.already_exists'
              : opening
              ? 'warehouse_setup.opening_saved'
              : 'warehouse_setup.saved',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'warehouse_setup.save_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('warehouse_setup.title'.tr())),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warehouse_outlined,
                          size: 36,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'warehouse_setup.intro'.tr(),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text('warehouse_setup.zero_note'.tr()),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_canCreate)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _createWarehouse,
                      icon: const Icon(Icons.add),
                      label: Text('warehouse_setup.create_warehouse'.tr()),
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_message!.tr()),
                    ),
                  ),
                if (!_busy && _warehouses.isEmpty) ...[
                  Text('warehouse_setup.unavailable'.tr()),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text('warehouse_setup.retry'.tr()),
                    ),
                  ),
                ],
                if (_warehouse != null)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => WarehouseReportsScreen(
                                  service: widget.service,
                                  warehouseId: _warehouse!,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.analytics_outlined),
                      label: Text('warehouse_reports.title'.tr()),
                    ),
                  ),
                if (_warehouse != null)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () {
                              final selected = _warehouses.firstWhere(
                                (w) => w.id == _warehouse,
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => WarehouseValuationScreen(
                                    service: widget.service,
                                    warehouseId: selected.id,
                                    warehouseName: selected.name.isEmpty
                                        ? selected.code
                                        : selected.name,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.price_change_outlined),
                      label: Text('warehouse_value.title'.tr()),
                    ),
                  ),
                if (_warehouse != null)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () {
                              final selected = _warehouses.firstWhere(
                                (w) => w.id == _warehouse,
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => WarehouseStocktakeScreen(
                                    service: widget.service,
                                    warehouseId: selected.id,
                                    warehouseName: selected.name.isEmpty
                                        ? selected.code
                                        : selected.name,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.fact_check_outlined),
                      label: Text('warehouse_count.title'.tr()),
                    ),
                  ),
                if (_warehouses.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey(_warehouse),
                    initialValue: _warehouse,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'warehouse_setup.warehouse'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                    items: _warehouses
                        .map(
                          (w) => DropdownMenuItem(
                            value: w.id,
                            child: Text(
                              w.name.isEmpty ? w.code : '${w.name} · ${w.code}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _warehouse = value;
                              _offset = 0;
                              _search = '';
                              _query.clear();
                            });
                            _loadItems();
                          },
                  ),
                if (_warehouse != null) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _query,
                    enabled: !_busy,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      _offset = 0;
                      _search = _query.text;
                      _loadItems();
                    },
                    decoration: InputDecoration(
                      labelText: 'warehouse_setup.search'.tr(),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'warehouse_setup.search'.tr(),
                        onPressed: _busy
                            ? null
                            : () {
                                _offset = 0;
                                _search = _query.text;
                                _loadItems();
                              },
                        icon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_busy && _items.isEmpty)
                    Text('warehouse_setup.empty'.tr()),
                  for (final item in _items.where(
                    (i) => _item == null || i.variantId == _item!.variantId,
                  ))
                    Card(
                      color: _item?.variantId == item.variantId
                          ? theme.colorScheme.secondaryContainer
                          : null,
                      child: ListTile(
                        enabled: !_busy,
                        selected: _item?.variantId == item.variantId,
                        leading: Icon(
                          _item?.variantId == item.variantId
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          '${item.label.isEmpty ? 'warehouse_setup.variant'.tr(namedArgs: {'id': '${item.variantId}'}) : item.label} · ${item.currencyCode}',
                        ),
                        onTap: _busy
                            ? null
                            : () => setState(() {
                                _item = item;
                                _cost.clear();
                                _message = null;
                              }),
                      ),
                    ),
                  if (_item != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _item = null;
                                _cost.clear();
                              }),
                        child: Text('warehouse_setup.change_product'.tr()),
                      ),
                    ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: _busy || _offset == 0
                            ? null
                            : () {
                                _offset -= 50;
                                _loadItems();
                              },
                        child: Text('warehouse_setup.previous'.tr()),
                      ),
                      TextButton(
                        onPressed: _busy || _items.length < 50
                            ? null
                            : () {
                                _offset += 50;
                                _loadItems();
                              },
                        child: Text('warehouse_setup.next'.tr()),
                      ),
                    ],
                  ),
                ],
                if (_item != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _item!.name,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _cost,
                              enabled: !_busy,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'warehouse_setup.cost'.tr(),
                                suffixText: _item!.currencyCode,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) {
                                try {
                                  _item!.parseCost(value ?? '');
                                  return null;
                                } catch (_) {
                                  return 'warehouse_setup.invalid_cost'.tr(
                                    namedArgs: {
                                      'digits': '${_item!.decimalDigits}',
                                    },
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: _opening,
                              title: Text('warehouse_setup.opening'.tr()),
                              subtitle: Text(
                                'warehouse_setup.opening_note'.tr(),
                              ),
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() => _opening = value),
                            ),
                            if (!_opening)
                              Text('warehouse_setup.zero_quantity'.tr()),
                            if (_opening) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _quantity,
                                enabled: !_busy,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: 'warehouse_setup.quantity'.tr(),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  try {
                                    if (_item!.parseQuantity(value ?? '') <=
                                            0 ||
                                        _item!.parseCost(_cost.text) <= 0) {
                                      throw const FormatException();
                                    }
                                    return null;
                                  } catch (_) {
                                    return 'warehouse_setup.invalid_opening'
                                        .tr();
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _reason,
                                enabled: !_busy,
                                maxLength: 500,
                                minLines: 1,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: 'warehouse_setup.reason'.tr(),
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'warehouse_setup.reason_required'.tr()
                                    : null,
                              ),
                              if (_item!.tracking != 'standard') ...[
                                TextFormField(
                                  controller: _lot,
                                  enabled: !_busy,
                                  maxLength: 20,
                                  decoration: InputDecoration(
                                    labelText: 'warehouse_setup.lot'.tr(),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          final date = await showDatePicker(
                                            context: context,
                                            initialDate:
                                                _expiry ?? DateTime.now(),
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2200),
                                          );
                                          if (mounted && date != null) {
                                            setState(() => _expiry = date);
                                          }
                                        },
                                  icon: const Icon(Icons.event_outlined),
                                  label: Text(
                                    _expiry == null
                                        ? 'warehouse_setup.expiry'.tr()
                                        : DateFormat.yMd(
                                            context.locale.toString(),
                                          ).format(_expiry!),
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _busy ? null : _save,
                              icon: const Icon(Icons.add_task),
                              label: Text(
                                (_opening
                                        ? 'warehouse_setup.review'
                                        : 'warehouse_setup.save')
                                    .tr(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
