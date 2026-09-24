import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/lan/lan_business_models.dart';
import '../../data/warehouse_transfer_application_service.dart';

String _warehouseTransferErrorKey(Object error, String fallback) {
  if (error is LanBusinessException) {
    return switch (error.code) {
      'lan_capability_required' => 'warehouse_transfer.master_update_required',
      'authentication_required' => 'warehouse_transfer.sign_in_required',
      'permission_denied' => 'warehouse_transfer.permission_denied',
      'warehouse_access_denied' => 'warehouse_transfer.warehouse_access_denied',
      _ => fallback,
    };
  }
  return fallback;
}

class WarehouseTransferScreen extends StatefulWidget {
  const WarehouseTransferScreen({super.key, required this.service});

  final WarehouseTransferApplicationService service;

  @override
  State<WarehouseTransferScreen> createState() =>
      _WarehouseTransferScreenState();
}

class _WarehouseTransferScreenState extends State<WarehouseTransferScreen> {
  bool _busy = true;
  List<WarehouseTransferAppWarehouse> _warehouses = const [];
  List<WarehouseTransferAppDocument> _transfers = const [];
  String? _message;
  String _filter = 'active';
  final Map<String, String> _operationKeys = {};

  String _operationKey(String intent) =>
      _operationKeys.putIfAbsent(intent, () => const Uuid().v4());

  static const _active = {'draft', 'in_transit', 'partially_received'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? successMessage}) async {
    if (mounted) {
      setState(() {
        _busy = true;
        _message = null;
      });
    }
    try {
      final warehouses = await widget.service.warehouses();
      final statuses = switch (_filter) {
        'completed' => {'completed'},
        'cancelled' => {'cancelled'},
        _ => _active,
      };
      final transfers = await widget.service.list(statuses: statuses);
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _transfers = transfers;
        _message = successMessage;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = _warehouseTransferErrorKey(
            error,
            'warehouse_transfer.load_failed',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _warehouseName(String id) {
    final warehouse = _warehouses.where((row) => row.id == id).firstOrNull;
    if (warehouse == null) return 'warehouse_transfer.unknown_warehouse'.tr();
    return warehouse.name.trim().isEmpty
        ? warehouse.code
        : '${warehouse.name} · ${warehouse.code}';
  }

  Future<void> _create() async {
    if (_warehouses.length < 2) {
      setState(() => _message = 'warehouse_transfer.need_two_warehouses');
      return;
    }
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _WarehouseTransferComposer(
          warehouses: _warehouses,
          service: widget.service,
        ),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _dispatch(WarehouseTransferAppDocument draft) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('warehouse_transfer.dispatch_title'.tr()),
        content: Text(
          'warehouse_transfer.dispatch_warning'.tr(
            namedArgs: {
              'source': _warehouseName(draft.sourceWarehouseId),
              'destination': _warehouseName(draft.destinationWarehouseId),
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('warehouse_transfer.back'.tr()),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.local_shipping_outlined),
            label: Text('warehouse_transfer.dispatch'.tr()),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await _run(() async {
      await widget.service.dispatch(
        transferId: draft.id,
        requestKey: _operationKey('dispatch:${draft.id}'),
      );
    }, 'warehouse_transfer.dispatched');
  }

  Future<void> _cancel(WarehouseTransferAppDocument draft) async {
    final reason = await _reasonDialog('warehouse_transfer.cancel_title');
    if (reason == null) return;
    await _run(() async {
      await widget.service.cancel(
        transferId: draft.id,
        requestKey: _operationKey('cancel:${draft.id}:$reason'),
        reason: reason,
      );
    }, 'warehouse_transfer.cancelled');
  }

  Future<void> _recall(WarehouseTransferAppDocument draft) async {
    final reason = await _reasonDialog('warehouse_transfer.recall_title');
    if (reason == null) return;
    await _run(() async {
      await widget.service.recall(
        transferId: draft.id,
        requestKey: _operationKey('recall:${draft.id}:$reason'),
        reason: reason,
      );
    }, 'warehouse_transfer.recalled');
  }

  Future<String?> _reasonDialog(String titleKey) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titleKey.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'warehouse_transfer.reason'.tr(),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('warehouse_transfer.back'.tr()),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: Text('warehouse_transfer.confirm'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _receive(WarehouseTransferAppDocument draft) async {
    setState(() => _busy = true);
    try {
      final pending = await widget.service.pending(draft.id);
      if (!mounted) return;
      final request = await showDialog<_ReceiptFormResult>(
        context: context,
        builder: (_) => _TransferReceiptDialog(items: pending),
      );
      if (request == null) return;
      final receiptIntent = [
        'receive',
        draft.id,
        request.notes,
        for (final item in request.items)
          '${item.allocationId}:${item.acceptedQuantity}:${item.damagedQuantity}:${item.lostQuantity}',
      ].join('|');
      await widget.service.receive(
        transferId: draft.id,
        requestKey: _operationKey(receiptIntent),
        items: request.items,
        notes: request.notes,
      );
      await _load(successMessage: 'warehouse_transfer.received');
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = _warehouseTransferErrorKey(
            error,
            'warehouse_transfer.operation_failed',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() work, String success) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await work();
      await _load(successMessage: success);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = _warehouseTransferErrorKey(
            error,
            'warehouse_transfer.operation_failed',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('warehouse_transfer.title'.tr()),
        actions: [
          IconButton(
            onPressed: _busy ? null : () => _load(),
            tooltip: 'warehouse_transfer.refresh'.tr(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        icon: const Icon(Icons.add),
        label: Text('warehouse_transfer.new_transfer'.tr()),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _TransferHero(warehouseCount: _warehouses.length),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'active',
                        icon: const Icon(Icons.sync_alt),
                        label: Text('warehouse_transfer.active'.tr()),
                      ),
                      ButtonSegment(
                        value: 'completed',
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text('warehouse_transfer.completed'.tr()),
                      ),
                      ButtonSegment(
                        value: 'cancelled',
                        icon: const Icon(Icons.cancel_outlined),
                        label: Text('warehouse_transfer.cancelled_tab'.tr()),
                      ),
                    ],
                    selected: {_filter},
                    showSelectedIcon: false,
                    onSelectionChanged: _busy
                        ? null
                        : (value) {
                            _filter = value.single;
                            _load();
                          },
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Material(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(_message!.tr()),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (!_busy && _transfers.isEmpty)
                    _EmptyTransfers(onCreate: _create)
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 760 ? 2 : 1;
                        final width = columns == 1
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final transfer in _transfers)
                              SizedBox(
                                width: width,
                                child: _TransferCard(
                                  draft: transfer,
                                  source: _warehouseName(
                                    transfer.sourceWarehouseId,
                                  ),
                                  destination: _warehouseName(
                                    transfer.destinationWarehouseId,
                                  ),
                                  busy: _busy,
                                  onDispatch: () => _dispatch(transfer),
                                  onCancel: () => _cancel(transfer),
                                  onReceive: () => _receive(transfer),
                                  onRecall: () => _recall(transfer),
                                ),
                              ),
                          ],
                        );
                      },
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

class _TransferHero extends StatelessWidget {
  const _TransferHero({required this.warehouseCount});
  final int warehouseCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              child: const Icon(Icons.swap_horiz_rounded, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'warehouse_transfer.hero_title'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('warehouse_transfer.hero_body'.tr()),
                  const SizedBox(height: 12),
                  Chip(
                    avatar: const Icon(Icons.warehouse_outlined, size: 18),
                    label: Text(
                      'warehouse_transfer.warehouse_count'.tr(
                        namedArgs: {'count': '$warehouseCount'},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.draft,
    required this.source,
    required this.destination,
    required this.busy,
    required this.onDispatch,
    required this.onCancel,
    required this.onReceive,
    required this.onRecall,
  });

  final WarehouseTransferAppDocument draft;
  final String source, destination;
  final bool busy;
  final VoidCallback onDispatch, onCancel, onReceive, onRecall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = draft.status;
    final statusKey = draft.recalled ? 'recalled' : status;
    final canReceive = const {
      'in_transit',
      'partially_received',
    }.contains(status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${draft.id.substring(0, 8).toUpperCase()}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(label: Text('warehouse_transfer.status.$statusKey'.tr())),
              ],
            ),
            const SizedBox(height: 12),
            _RouteLine(icon: Icons.upload_outlined, label: source),
            const SizedBox(height: 6),
            _RouteLine(icon: Icons.download_outlined, label: destination),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(
                    'warehouse_transfer.lines'.tr(
                      namedArgs: {'count': '${draft.lineCount}'},
                    ),
                  ),
                ),
                if (draft.notes.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.notes, size: 18),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(draft.notes, overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
            ),
            if (status == 'draft' || canReceive) ...[
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (status == 'draft')
                    FilledButton.icon(
                      onPressed: busy ? null : onDispatch,
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: Text('warehouse_transfer.dispatch'.tr()),
                    ),
                  if (status == 'draft')
                    OutlinedButton.icon(
                      onPressed: busy ? null : onCancel,
                      icon: const Icon(Icons.close),
                      label: Text('warehouse_transfer.cancel'.tr()),
                    ),
                  if (canReceive)
                    FilledButton.icon(
                      onPressed: busy ? null : onReceive,
                      icon: const Icon(Icons.inventory_outlined),
                      label: Text('warehouse_transfer.receive'.tr()),
                    ),
                  if (canReceive)
                    OutlinedButton.icon(
                      onPressed: busy ? null : onRecall,
                      icon: const Icon(Icons.undo_rounded),
                      label: Text('warehouse_transfer.recall'.tr()),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

class _EmptyTransfers extends StatelessWidget {
  const _EmptyTransfers({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Icon(
          Icons.move_to_inbox_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 12),
        Text(
          'warehouse_transfer.empty'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: Text('warehouse_transfer.new_transfer'.tr()),
        ),
      ],
    ),
  );
}

class _WarehouseTransferComposer extends StatefulWidget {
  const _WarehouseTransferComposer({
    required this.warehouses,
    required this.service,
  });

  final List<WarehouseTransferAppWarehouse> warehouses;
  final WarehouseTransferApplicationService service;

  @override
  State<_WarehouseTransferComposer> createState() =>
      _WarehouseTransferComposerState();
}

class _WarehouseTransferComposerState
    extends State<_WarehouseTransferComposer> {
  final _search = TextEditingController();
  final _notes = TextEditingController();
  final Map<int, _CartLine> _cart = {};
  String? _source, _destination;
  List<WarehouseTransferAppCatalogItem> _catalog = const [];
  bool _busy = false;
  String? _message;
  String? _pendingIntent;
  String? _pendingRequestKey;

  String _requestKeyFor(String intent) {
    if (_pendingIntent != intent || _pendingRequestKey == null) {
      _pendingIntent = intent;
      _pendingRequestKey = const Uuid().v4();
    }
    return _pendingRequestKey!;
  }

  @override
  void dispose() {
    _search.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _name(String id) {
    final row = widget.warehouses.firstWhere((warehouse) => warehouse.id == id);
    return row.name.isEmpty ? row.code : '${row.name} · ${row.code}';
  }

  Future<void> _choose({required bool source}) async {
    final excluded = source ? _destination : _source;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _WarehousePicker(
        warehouses: widget.warehouses
            .where((warehouse) => warehouse.id != excluded)
            .toList(),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (source) {
        if (_source != selected) {
          _source = selected;
          _cart.clear();
          _catalog = const [];
          _search.clear();
        }
      } else {
        _destination = selected;
      }
      _message = null;
    });
    if (source) await _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final source = _source;
    if (source == null) return;
    setState(() => _busy = true);
    try {
      final rows = await widget.service.catalog(source, query: _search.text);
      if (mounted) setState(() => _catalog = rows);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = _warehouseTransferErrorKey(
            error,
            'warehouse_transfer.load_failed',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(WarehouseTransferAppCatalogItem item) async {
    final controller = TextEditingController(
      text: _displayQuantity(item.quantityScale, 1 * item.quantityScale),
    );
    final quantity = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'warehouse_transfer.available'.tr(
                namedArgs: {
                  'quantity': _displayQuantity(
                    item.quantityScale,
                    item.quantity,
                  ),
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'warehouse_transfer.quantity'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('warehouse_transfer.back'.tr()),
          ),
          FilledButton(
            onPressed: () {
              try {
                Navigator.pop(context, item.parseQuantity(controller.text));
              } on FormatException {
                // Keep the dialog open so the user can correct the value.
              }
            },
            child: Text('warehouse_transfer.add'.tr()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (quantity == null || !mounted) return;
    setState(() => _cart[item.variantId] = _CartLine(item, quantity));
  }

  Future<void> _review() async {
    final sourceId = _source, destinationId = _destination;
    if (sourceId == null || destinationId == null || _cart.isEmpty) {
      setState(() => _message = 'warehouse_transfer.complete_form');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final lines = [
        for (final line in _cart.values)
          WarehouseTransferAppLine(
            productId: line.item.productId,
            variantId: line.item.variantId,
            quantity: line.quantity,
          ),
      ];
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('warehouse_transfer.review_title'.tr()),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_name(sourceId)}  →  ${_name(destinationId)}'),
                  const Divider(height: 24),
                  for (final line in _cart.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(line.item.name),
                      subtitle: Text(line.item.code),
                      trailing: Text(
                        _displayQuantity(
                          line.item.quantityScale,
                          line.quantity,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text('warehouse_transfer.review_note'.tr()),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('warehouse_transfer.back'.tr()),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.save_outlined),
              label: Text('warehouse_transfer.save_draft'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final normalizedNotes = _notes.text.trim();
      final intent = [
        sourceId,
        destinationId,
        normalizedNotes,
        for (final line in [
          ...lines,
        ]..sort((left, right) => left.variantId.compareTo(right.variantId)))
          '${line.productId}:${line.variantId}:${line.quantity}',
      ].join('|');
      await widget.service.create(
        requestKey: _requestKeyFor(intent),
        sourceWarehouseId: sourceId,
        destinationWarehouseId: destinationId,
        lines: lines,
        notes: normalizedNotes,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = _warehouseTransferErrorKey(
            error,
            'warehouse_transfer.review_failed',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('warehouse_transfer.new_transfer'.tr())),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'warehouse_transfer.route'.tr(),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 620;
                          final source = _WarehouseChoice(
                            icon: Icons.upload_outlined,
                            label: 'warehouse_transfer.source'.tr(),
                            value: _source == null ? null : _name(_source!),
                            onTap: _busy ? null : () => _choose(source: true),
                          );
                          final destination = _WarehouseChoice(
                            icon: Icons.download_outlined,
                            label: 'warehouse_transfer.destination'.tr(),
                            value: _destination == null
                                ? null
                                : _name(_destination!),
                            onTap: _busy ? null : () => _choose(source: false),
                          );
                          return wide
                              ? Row(
                                  children: [
                                    Expanded(child: source),
                                    const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.arrow_forward),
                                    ),
                                    Expanded(child: destination),
                                  ],
                                )
                              : Column(
                                  children: [
                                    source,
                                    const SizedBox(height: 8),
                                    destination,
                                  ],
                                );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_source != null) ...[
                SearchBar(
                  controller: _search,
                  hintText: 'warehouse_transfer.search_product'.tr(),
                  leading: const Icon(Icons.search),
                  trailing: [
                    IconButton(
                      onPressed: _busy ? null : _loadCatalog,
                      icon: const Icon(Icons.arrow_forward),
                      tooltip: 'warehouse_transfer.search'.tr(),
                    ),
                  ],
                  onSubmitted: (_) => _loadCatalog(),
                ),
                const SizedBox(height: 12),
                if (_busy) const LinearProgressIndicator(),
                if (_catalog.isEmpty && !_busy)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('warehouse_transfer.no_products'.tr()),
                  )
                else
                  ..._catalog.map(
                    (item) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.inventory_2_outlined),
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          [
                            if (item.code.isNotEmpty) item.code,
                            'warehouse_transfer.available'.tr(
                              namedArgs: {
                                'quantity': _displayQuantity(
                                  item.quantityScale,
                                  item.quantity,
                                ),
                              },
                            ),
                            if (item.supplierOwnedQuantity > 0)
                              'warehouse_transfer.consignment_available'.tr(
                                namedArgs: {
                                  'quantity': _displayQuantity(
                                    item.quantityScale,
                                    item.supplierOwnedQuantity,
                                  ),
                                },
                              ),
                          ].join(' · '),
                        ),
                        trailing: IconButton.filledTonal(
                          onPressed: _busy ? null : () => _add(item),
                          icon: const Icon(Icons.add),
                          tooltip: 'warehouse_transfer.add'.tr(),
                        ),
                      ),
                    ),
                  ),
              ],
              if (_cart.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'warehouse_transfer.selected_items'.tr(
                    namedArgs: {'count': '${_cart.length}'},
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ..._cart.values.map(
                  (line) => Card(
                    child: ListTile(
                      title: Text(line.item.name),
                      subtitle: Text(line.item.code),
                      trailing: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _displayQuantity(
                              line.item.quantityScale,
                              line.quantity,
                            ),
                          ),
                          IconButton(
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _cart.remove(line.item.variantId),
                                  ),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'warehouse_transfer.remove'.tr(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'warehouse_transfer.notes'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _message!.tr(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: FilledButton.icon(
              onPressed: _busy ? null : _review,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text('warehouse_transfer.review'.tr()),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CartLine {
  const _CartLine(this.item, this.quantity);
  final WarehouseTransferAppCatalogItem item;
  final int quantity;
}

class _WarehouseChoice extends StatelessWidget {
  const _WarehouseChoice({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.all(16),
      alignment: AlignmentDirectional.centerStart,
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                value ?? 'warehouse_transfer.choose'.tr(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const Icon(Icons.search),
      ],
    ),
  );
}

class _WarehousePicker extends StatefulWidget {
  const _WarehousePicker({required this.warehouses});
  final List<WarehouseTransferAppWarehouse> warehouses;

  @override
  State<_WarehousePicker> createState() => _WarehousePickerState();
}

class _WarehousePickerState extends State<_WarehousePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final rows = widget.warehouses.where((warehouse) {
      final haystack = '${warehouse.name} ${warehouse.code}'.toLowerCase();
      return haystack.contains(_query.toLowerCase());
    }).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: Column(
            children: [
              Text(
                'warehouse_transfer.choose_warehouse'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  labelText: 'warehouse_transfer.search_warehouse'.tr(),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      leading: const Icon(Icons.warehouse_outlined),
                      title: Text(row.name.isEmpty ? row.code : row.name),
                      subtitle: row.name.isEmpty ? null : Text(row.code),
                      onTap: () => Navigator.pop(context, row.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptFormResult {
  const _ReceiptFormResult(this.items, this.notes);
  final List<WarehouseTransferAppReceiptItem> items;
  final String notes;
}

class _TransferReceiptDialog extends StatefulWidget {
  const _TransferReceiptDialog({required this.items});
  final List<WarehouseTransferAppPending> items;

  @override
  State<_TransferReceiptDialog> createState() => _TransferReceiptDialogState();
}

class _TransferReceiptDialogState extends State<_TransferReceiptDialog> {
  late final List<_ReceiptControllers> _rows = [
    for (final item in widget.items) _ReceiptControllers(item),
  ];
  final _notes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final requests = <WarehouseTransferAppReceiptItem>[];
      var hasVariance = false;
      for (final row in _rows) {
        final accepted = row.parse(row.accepted.text);
        final damaged = row.parse(row.damaged.text);
        final lost = row.parse(row.lost.text);
        final total = accepted + damaged + lost;
        if (total == 0) continue;
        if (total > row.item.remainingQuantity) {
          throw const FormatException('over');
        }
        hasVariance = hasVariance || damaged > 0 || lost > 0;
        requests.add(
          WarehouseTransferAppReceiptItem(
            allocationId: row.item.allocationId,
            acceptedQuantity: accepted,
            damagedQuantity: damaged,
            lostQuantity: lost,
          ),
        );
      }
      if (requests.isEmpty || (hasVariance && _notes.text.trim().isEmpty)) {
        throw const FormatException('empty');
      }
      Navigator.pop(context, _ReceiptFormResult(requests, _notes.text.trim()));
    } on FormatException {
      setState(() => _error = 'warehouse_transfer.receipt_invalid');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('warehouse_transfer.receive_title'.tr()),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('warehouse_transfer.receive_help'.tr()),
            const SizedBox(height: 12),
            for (final row in _rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.item.productName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          if (row.item.code.isNotEmpty) row.item.code,
                          'warehouse_transfer.owner.${row.item.ownerType}'.tr(),
                          'warehouse_transfer.remaining'.tr(
                            namedArgs: {
                              'quantity': _displayQuantity(
                                row.item.quantityScale,
                                row.item.remainingQuantity,
                              ),
                            },
                          ),
                        ].join(' · '),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final fields = [
                            _quantityField(
                              row.accepted,
                              'warehouse_transfer.accepted',
                            ),
                            _quantityField(
                              row.damaged,
                              'warehouse_transfer.damaged',
                            ),
                            _quantityField(row.lost, 'warehouse_transfer.lost'),
                          ];
                          return constraints.maxWidth >= 520
                              ? Row(
                                  children: [
                                    for (var i = 0; i < fields.length; i++) ...[
                                      if (i > 0) const SizedBox(width: 8),
                                      Expanded(child: fields[i]),
                                    ],
                                  ],
                                )
                              : Column(
                                  children: [
                                    for (final field in fields) ...[
                                      field,
                                      const SizedBox(height: 8),
                                    ],
                                  ],
                                );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'warehouse_transfer.receipt_notes'.tr(),
                helperText: 'warehouse_transfer.receipt_notes_help'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Text(
                _error!.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('warehouse_transfer.back'.tr()),
      ),
      FilledButton.icon(
        onPressed: _submit,
        icon: const Icon(Icons.check),
        label: Text('warehouse_transfer.post_receipt'.tr()),
      ),
    ],
  );

  Widget _quantityField(TextEditingController controller, String key) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: key.tr(),
          border: const OutlineInputBorder(),
        ),
      );
}

class _ReceiptControllers {
  _ReceiptControllers(this.item)
    : accepted = TextEditingController(
        text: _displayQuantity(item.quantityScale, item.remainingQuantity),
      ),
      damaged = TextEditingController(text: '0'),
      lost = TextEditingController(text: '0');

  final WarehouseTransferAppPending item;
  final TextEditingController accepted, damaged, lost;

  int parse(String input) {
    var text = input.trim().replaceAll('٫', '.').replaceAll(',', '.');
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    final digits = item.quantityScale == 1 ? 0 : 3;
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) {
      throw const FormatException('quantity');
    }
    final parts = text.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > digits) throw const FormatException('precision');
    final value = BigInt.parse(parts.first + fraction.padRight(digits, '0'));
    if (value > BigInt.from(9007199254740991)) {
      throw const FormatException('range');
    }
    return value.toInt();
  }

  void dispose() {
    accepted.dispose();
    damaged.dispose();
    lost.dispose();
  }
}

String _displayQuantity(int scale, int value) {
  if (scale == 1) return '$value';
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  final fraction = (absolute % scale).toString().padLeft(3, '0');
  return '$sign${absolute ~/ scale}.$fraction';
}
