import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../data/warehouse_setup_service.dart';

class WarehouseStocktakeScreen extends StatefulWidget {
  const WarehouseStocktakeScreen({
    super.key,
    required this.service,
    required this.warehouseId,
    required this.warehouseName,
  });
  final WarehouseSetupService service;
  final String warehouseId, warehouseName;

  @override
  State<WarehouseStocktakeScreen> createState() =>
      _WarehouseStocktakeScreenState();
}

class _WarehouseStocktakeScreenState extends State<WarehouseStocktakeScreen> {
  final _query = TextEditingController();
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<WarehouseCountItem> _items = [];
  WarehouseCountItem? _item;
  int? _preview;
  int _offset = 0;
  bool _busy = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _item = null;
      _preview = null;
      _message = null;
    });
    _quantity.clear();
    try {
      final items = await widget.service.countItems(
        widget.warehouseId,
        query: _query.text,
        offset: _offset,
      );
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) {
        setState(() {
          _items = [];
          _message = 'warehouse_count.load_failed';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final item = _item;
    if (_busy ||
        item == null ||
        _preview == null ||
        !_form.currentState!.validate()) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.service.postCount(
        item: item,
        countedQuantity: _quantity.text,
        reason: _reason.text,
      );
      if (!mounted) return;
      await _load();
      if (mounted) {
        setState(() {
          _message = 'warehouse_count.saved';
          _reason.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _preview = null;
          // Require a new observation before retrying; never overwrite intervening sales.
          _item = null;
          _message = 'warehouse_count.review_required';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _item;
    return Scaffold(
      appBar: AppBar(title: Text('warehouse_count.title'.tr())),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.fact_check_outlined,
                            size: 36,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.warehouseName,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text('warehouse_count.intro'.tr()),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_busy) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(_message!.tr()),
                      ),
                    ),
                  TextField(
                    controller: _query,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: 'warehouse_setup.search'.tr(),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'warehouse_setup.search'.tr(),
                        onPressed: _busy
                            ? null
                            : () {
                                _offset = 0;
                                _load();
                              },
                        icon: const Icon(Icons.search),
                      ),
                    ),
                    onSubmitted: (_) {
                      if (!_busy) {
                        _offset = 0;
                        _load();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<WarehouseCountItem>(
                    key: ValueKey(_items),
                    initialValue: item,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'warehouse_count.item'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                    items: _items
                        .map(
                          (row) => DropdownMenuItem(
                            value: row,
                            child: Text(
                              '${row.name} · ${row.label}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _item = value;
                            _preview = null;
                            _quantity.clear();
                            _message = null;
                          }),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        tooltip: 'warehouse_setup.previous'.tr(),
                        onPressed: _busy || _offset == 0
                            ? null
                            : () {
                                _offset -= 50;
                                _load();
                              },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        _items.isEmpty
                            ? '0'
                            : '${_offset + 1}–${_offset + _items.length}',
                      ),
                      IconButton(
                        tooltip: 'warehouse_setup.next'.tr(),
                        onPressed: _busy || _items.length < 50
                            ? null
                            : () {
                                _offset += 50;
                                _load();
                              },
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  if (!_busy && _items.isEmpty)
                    Text('warehouse_count.empty'.tr()),
                  if (item != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'warehouse_count.recorded'.tr(),
                              style: theme.textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.displayQuantity(item.quantity),
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _quantity,
                              enabled: !_busy,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'warehouse_count.counted'.tr(),
                                helperText:
                                    (item.quantityScale == 1
                                            ? 'warehouse_count.pieces'
                                            : 'warehouse_count.measured')
                                        .tr(),
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() => _preview = null),
                              validator: (value) {
                                try {
                                  item.parseQuantity(value ?? '');
                                  return null;
                                } catch (_) {
                                  return 'warehouse_count.invalid_quantity'
                                      .tr();
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _reason,
                              enabled: !_busy,
                              maxLines: 2,
                              maxLength: 500,
                              decoration: InputDecoration(
                                labelText: 'warehouse_count.reason'.tr(),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'warehouse_count.reason_required'.tr()
                                  : null,
                            ),
                            if (_preview != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                'warehouse_count.difference'.tr(),
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                item.displayQuantity(_preview! - item.quantity),
                                style: theme.textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text('warehouse_count.review_note'.tr()),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : _preview == null
                          ? () {
                              if (_form.currentState!.validate()) {
                                setState(
                                  () => _preview = item.parseQuantity(
                                    _quantity.text,
                                  ),
                                );
                              }
                            }
                          : _save,
                      icon: Icon(
                        _preview == null
                            ? Icons.preview_outlined
                            : Icons.check_circle_outline,
                      ),
                      label: Text(
                        (_preview == null
                                ? 'warehouse_count.preview'
                                : 'warehouse_count.confirm')
                            .tr(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: Text('warehouse_count.refresh'.tr()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
