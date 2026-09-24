import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/injection_container.dart';
import '../../../reports/presentation/widgets/warehouse_report_context.dart';
import '../../data/warehouse_transfer_reporting_service.dart';

class WarehouseTransferReportScreen extends StatefulWidget {
  const WarehouseTransferReportScreen({super.key, this.service});

  final WarehouseTransferReportingService? service;

  @override
  State<WarehouseTransferReportScreen> createState() =>
      _WarehouseTransferReportScreenState();
}

class _WarehouseTransferReportScreenState
    extends State<WarehouseTransferReportScreen> {
  final _search = TextEditingController();
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 29)),
    end: DateTime.now(),
  );
  String _direction = 'all';
  String _ownership = 'all';
  String _status = 'all';
  String? _loadedWarehouse;
  bool _busy = false;
  String? _error;
  WarehouseTransferReportData? _data;

  WarehouseTransferReportingService get _service =>
      widget.service ?? sl<WarehouseTransferReportingService>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final warehouse = WarehouseReportContext.maybeOf(
      context,
    )?.scope.warehouseId;
    if (warehouse != null && warehouse != _loadedWarehouse) {
      _loadedWarehouse = warehouse;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _chooseRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDateRange: _range,
    );
    if (result == null || !mounted) return;
    setState(() => _range = result);
    await _load();
  }

  Future<void> _load() async {
    final warehouse = _loadedWarehouse;
    if (warehouse == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final start = DateTime.utc(
        _range.start.year,
        _range.start.month,
        _range.start.day,
      );
      final end = DateTime.utc(
        _range.end.year,
        _range.end.month,
        _range.end.day + 1,
      );
      final data = await _service.report(
        warehouseId: warehouse,
        from: start,
        toExclusive: end,
        direction: _direction,
        ownership: _ownership,
        status: _status,
        search: _search.text,
      );
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _error = 'warehouse_transfer_report.failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _money(int cents, String code) => NumberFormat.simpleCurrency(
    name: code,
    decimalDigits: 2,
    locale: context.locale.toString(),
  ).format(cents / 100);

  String _quantity(int value, int scale) => NumberFormat(
    scale == 1 ? '#,##0' : '#,##0.###',
    context.locale.toString(),
  ).format(value / scale);

  @override
  Widget build(BuildContext context) {
    final warehouse = WarehouseReportContext.maybeOf(context);
    final data = _data;
    final currency = data?.rows.firstOrNull?.currencyCode ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text('warehouse_transfer_report.title'.tr()),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: 'warehouse_transfer.refresh'.tr(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: warehouse == null
            ? Center(child: Text('warehouse_transfer_report.no_context'.tr()))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        _ReportHeader(
                          warehouse: warehouse.label,
                          range: _range,
                          busy: _busy,
                          onRange: _chooseRange,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _search,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _load(),
                          decoration: InputDecoration(
                            labelText: 'warehouse_transfer_report.search'.tr(),
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _search.clear();
                                      _load();
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth >= 780
                                ? (constraints.maxWidth - 24) / 3
                                : constraints.maxWidth >= 500
                                ? (constraints.maxWidth - 12) / 2
                                : constraints.maxWidth;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: width,
                                  child: _Filter(
                                    label:
                                        'warehouse_transfer_report.direction',
                                    value: _direction,
                                    values: const [
                                      'all',
                                      'incoming',
                                      'outgoing',
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _direction = value),
                                  ),
                                ),
                                SizedBox(
                                  width: width,
                                  child: _Filter(
                                    label:
                                        'warehouse_transfer_report.ownership',
                                    value: _ownership,
                                    values: const [
                                      'all',
                                      'owned',
                                      'consignment',
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _ownership = value),
                                  ),
                                ),
                                SizedBox(
                                  width: width,
                                  child: _Filter(
                                    label:
                                        'warehouse_transfer_report.status_label',
                                    value: _status,
                                    values: const [
                                      'all',
                                      'in_transit',
                                      'partially_received',
                                      'completed',
                                      'recalled',
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _status = value),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _load,
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: Text('warehouse_transfer_report.apply'.tr()),
                          ),
                        ),
                        if (_busy) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Material(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(_error!.tr()),
                            ),
                          ),
                        ],
                        if (data != null) ...[
                          const SizedBox(height: 16),
                          _Summary(
                            transfers: data.transferCount,
                            lines: data.rows.length,
                            accepted: currency.isEmpty
                                ? '—'
                                : _money(data.acceptedValueCents, currency),
                            variance: currency.isEmpty
                                ? '—'
                                : _money(data.varianceValueCents, currency),
                            inTransit: currency.isEmpty
                                ? '—'
                                : _money(data.inTransitValueCents, currency),
                          ),
                          const SizedBox(height: 16),
                          if (!_busy && data.rows.isEmpty)
                            _EmptyReport(onRefresh: _load)
                          else
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final columns = constraints.maxWidth >= 820
                                    ? 2
                                    : 1;
                                final width = columns == 1
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - 12) / 2;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (final row in data.rows)
                                      SizedBox(
                                        width: width,
                                        child: _TransferReportCard(
                                          row: row,
                                          quantity: _quantity,
                                          money: _money,
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.warehouse,
    required this.range,
    required this.busy,
    required this.onRange,
  });

  final String warehouse;
  final DateTimeRange range;
  final bool busy;
  final VoidCallback onRange;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMd(context.locale.toString());
    return Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'warehouse_transfer_report.description'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(warehouse),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : onRange,
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                '${date.format(range.start)} — ${date.format(range.end)}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label, value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label.tr(),
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final option in values)
        DropdownMenuItem(
          value: option,
          child: Text('warehouse_transfer_report.option.$option'.tr()),
        ),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.transfers,
    required this.lines,
    required this.accepted,
    required this.variance,
    required this.inTransit,
  });

  final int transfers, lines;
  final String accepted, variance, inTransit;

  @override
  Widget build(BuildContext context) {
    final values = <(String, String, IconData)>[
      ('warehouse_transfer_report.transfers', '$transfers', Icons.swap_horiz),
      ('warehouse_transfer_report.lines', '$lines', Icons.inventory_2_outlined),
      ('warehouse_transfer_report.accepted_value', accepted, Icons.task_alt),
      (
        'warehouse_transfer_report.variance_value',
        variance,
        Icons.warning_amber,
      ),
      (
        'warehouse_transfer_report.in_transit_value',
        inTransit,
        Icons.local_shipping_outlined,
      ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final value in values)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(value.$3, size: 20),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value.$1.tr()),
                        Text(
                          value.$2,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TransferReportCard extends StatelessWidget {
  const _TransferReportCard({
    required this.row,
    required this.quantity,
    required this.money,
  });

  final WarehouseTransferReportRow row;
  final String Function(int, int) quantity;
  final String Function(int, String) money;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat.yMd(context.locale.toString()).add_Hm();
    final status = row.recalled ? 'recalled' : row.status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.productName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(label: Text('warehouse_transfer.status.$status'.tr())),
              ],
            ),
            if (row.variantLabel.isNotEmpty || row.code.isNotEmpty)
              Text(
                [
                  row.variantLabel,
                  row.code,
                ].where((part) => part.isNotEmpty).join(' · '),
              ),
            const SizedBox(height: 10),
            _Line(icon: Icons.upload_outlined, text: row.sourceWarehouse),
            _Line(
              icon: Icons.download_outlined,
              text: row.destinationWarehouse,
            ),
            _Line(
              icon: Icons.schedule,
              text: date.format(row.dispatchedAt.toLocal()),
            ),
            const Divider(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Metric(
                  label: 'warehouse_transfer_report.sent',
                  value: quantity(row.dispatchedQuantity, row.quantityScale),
                ),
                _Metric(
                  label: 'warehouse_transfer_report.accepted',
                  value: quantity(row.acceptedQuantity, row.quantityScale),
                ),
                if (row.damagedQuantity > 0)
                  _Metric(
                    label: 'warehouse_transfer_report.damaged',
                    value: quantity(row.damagedQuantity, row.quantityScale),
                  ),
                if (row.lostQuantity > 0)
                  _Metric(
                    label: 'warehouse_transfer_report.lost',
                    value: quantity(row.lostQuantity, row.quantityScale),
                  ),
                if (row.recalledQuantity > 0)
                  _Metric(
                    label: 'warehouse_transfer_report.recalled_qty',
                    value: quantity(row.recalledQuantity, row.quantityScale),
                  ),
                if (row.inTransitQuantity > 0)
                  _Metric(
                    label: 'warehouse_transfer_report.in_transit_qty',
                    value: quantity(row.inTransitQuantity, row.quantityScale),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    row.ownerType == 'consignment'
                        ? Icons.handshake_outlined
                        : Icons.business_outlined,
                    size: 18,
                  ),
                  label: Text('warehouse_transfer.owner.${row.ownerType}'.tr()),
                ),
                for (final source in row.sources)
                  Chip(
                    avatar: const Icon(Icons.local_shipping_outlined, size: 18),
                    label: Text(
                      source.supplierName.isEmpty
                          ? 'warehouse_transfer_report.source.${source.quality}'
                                .tr()
                          : source.purchaseNumber.isEmpty
                          ? '${source.supplierName} · ${quantity(source.quantity, row.quantityScale)}'
                          : '${source.supplierName} · ${source.purchaseNumber} · ${quantity(source.quantity, row.quantityScale)}',
                    ),
                  ),
              ],
            ),
            if (row.ownerType == 'owned') ...[
              const Divider(height: 22),
              Text(
                'warehouse_transfer_report.values'.tr(
                  namedArgs: {
                    'sent': money(row.dispatchedValueCents, row.currencyCode),
                    'accepted': money(row.acceptedValueCents, row.currencyCode),
                    'variance': money(row.varianceValueCents, row.currencyCode),
                    'transit': money(row.inTransitValueCents, row.currencyCode),
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text('${label.tr()}: $value'),
  );
}

class _EmptyReport extends StatelessWidget {
  const _EmptyReport({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44),
    child: Column(
      children: [
        Icon(
          Icons.move_to_inbox_outlined,
          size: 58,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 12),
        Text('warehouse_transfer_report.empty'.tr()),
        TextButton(
          onPressed: onRefresh,
          child: Text('warehouse_transfer.refresh'.tr()),
        ),
      ],
    ),
  );
}
