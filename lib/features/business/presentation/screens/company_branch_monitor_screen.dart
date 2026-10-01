import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../data/company_branch_monitor_service.dart';
import 'company_document_detail_screen.dart';

class CompanyBranchMonitorScreen extends StatefulWidget {
  const CompanyBranchMonitorScreen({
    super.key,
    this.service,
    this.initialBranchId,
    this.initialWarehouseId,
    this.embedded = false,
  });

  final CompanyBranchMonitorService? service;
  final String? initialBranchId;
  final String? initialWarehouseId;
  final bool embedded;

  @override
  State<CompanyBranchMonitorScreen> createState() =>
      _CompanyBranchMonitorScreenState();
}

class _CompanyBranchMonitorScreenState
    extends State<CompanyBranchMonitorScreen> {
  late final CompanyBranchMonitorService _service =
      widget.service ?? CompanyBranchMonitorService(sl<AppDatabase>());
  CompanyBranchMonitorSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  String? _branchId;
  String? _warehouseId;
  CompanyDocumentKind? _kind;

  @override
  void initState() {
    super.initState();
    _branchId = widget.initialBranchId;
    _warehouseId = widget.initialWarehouseId;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await _service.load();
      if (!mounted) return;
      setState(() => _snapshot = value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CompanyWarehouseStatus> get _warehouses {
    final locations = _snapshot?.locations ?? const <CompanyLocationStatus>[];
    return [
      for (final location in locations)
        if (_branchId == null || location.branchId == _branchId)
          ...location.warehouses,
    ];
  }

  List<CompanyDocumentSnapshot> get _documents {
    final documents = _snapshot?.documents ?? const <CompanyDocumentSnapshot>[];
    return documents
        .where((document) {
          if (_branchId != null && document.branchId != _branchId) return false;
          if (_warehouseId != null && document.warehouseId != _warehouseId) {
            return false;
          }
          if (_kind != null && document.kind != _kind) return false;
          return true;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: _body(theme),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: Text('company_monitor.title'.tr()),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'company_monitor.refresh'.tr(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('company_monitor.load_failed'.tr()),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text('company_monitor.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }
    final snapshot = _snapshot!;
    final documents = _documents;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _ReadOnlyNotice(generatedAt: snapshot.generatedAt),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: _LocationStrip(locations: snapshot.locations),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: _SummaryGrid(
                locations: snapshot.locations,
                documents: documents,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverToBoxAdapter(child: _filters(snapshot)),
          ),
          if (documents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(hasFilters: _hasFilters),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.crossAxisExtent < 900) {
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: EdgeInsets.only(
                            bottom: index == documents.length - 1 ? 0 : 12,
                          ),
                          child: _DocumentCard(document: documents[index]),
                        ),
                        childCount: documents.length,
                      ),
                    );
                  }
                  return SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 220,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _DocumentCard(document: documents[index]),
                      childCount: documents.length,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasFilters =>
      _branchId != null || _warehouseId != null || _kind != null;

  Widget _filters(CompanyBranchMonitorSnapshot snapshot) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'company_monitor.filters'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 820
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth >= 520
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _branchId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'company_monitor.branch'.tr(),
                          prefixIcon: const Icon(Icons.store_outlined),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('company_monitor.all_branches'.tr()),
                          ),
                          for (final location in snapshot.locations)
                            DropdownMenuItem<String?>(
                              value: location.branchId,
                              child: Text(
                                location.branchName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _branchId = value;
                          if (_warehouseId != null &&
                              !_warehouses.any(
                                (warehouse) => warehouse.id == _warehouseId,
                              )) {
                            _warehouseId = null;
                          }
                        }),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey('warehouse-$_branchId-$_warehouseId'),
                        initialValue: _warehouseId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'company_monitor.warehouse'.tr(),
                          prefixIcon: const Icon(Icons.warehouse_outlined),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('company_monitor.all_warehouses'.tr()),
                          ),
                          for (final warehouse in _warehouses)
                            DropdownMenuItem<String?>(
                              value: warehouse.id,
                              child: Text(
                                warehouse.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _warehouseId = value),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<CompanyDocumentKind?>(
                        initialValue: _kind,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'company_monitor.document_type'.tr(),
                          prefixIcon: const Icon(Icons.description_outlined),
                        ),
                        items: [
                          DropdownMenuItem<CompanyDocumentKind?>(
                            value: null,
                            child: Text('company_monitor.all_documents'.tr()),
                          ),
                          for (final kind in CompanyDocumentKind.values)
                            DropdownMenuItem<CompanyDocumentKind?>(
                              value: kind,
                              child: Text(_kindLabel(kind)),
                            ),
                        ],
                        onChanged: (value) => setState(() => _kind = value),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_hasFilters) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  _branchId = null;
                  _warehouseId = null;
                  _kind = null;
                }),
                icon: const Icon(Icons.filter_alt_off),
                label: Text('company_monitor.clear_filters'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice({required this.generatedAt});
  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.monitor_heart_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'company_monitor.read_only_title'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('company_monitor.read_only_help'.tr()),
                  const SizedBox(height: 6),
                  Text(
                    'company_monitor.generated_at'.tr(
                      namedArgs: {
                        'time': DateFormat.yMd().add_Hm().format(
                          generatedAt.toLocal(),
                        ),
                      },
                    ),
                    style: theme.textTheme.bodySmall,
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

class _LocationStrip extends StatelessWidget {
  const _LocationStrip({required this.locations});
  final List<CompanyLocationStatus> locations;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'company_monitor.connection_status'.tr(),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final location in locations) ...[
                _LocationChip(location: location),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.location});
  final CompanyLocationStatus location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = location.isOnline;
    final color = online ? Colors.green : theme.colorScheme.error;
    final status = location.isLocal
        ? 'company_monitor.this_device'.tr()
        : online
        ? 'company_monitor.online'.tr()
        : 'company_monitor.offline'.tr();
    return Container(
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 13, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location.branchName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '$status • ${'company_monitor.warehouse_count'.tr(namedArgs: {'count': '${location.warehouses.length}'})}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.locations, required this.documents});
  final List<CompanyLocationStatus> locations;
  final List<CompanyDocumentSnapshot> documents;

  @override
  Widget build(BuildContext context) {
    final active = documents.where((document) => !document.isVoided).toList();
    final values = [
      (
        Icons.store_outlined,
        'company_monitor.summary.branches'.tr(),
        '${locations.length}',
      ),
      (
        Icons.receipt_long_outlined,
        'company_monitor.summary.sales'.tr(),
        '${active.where((document) => document.isSale).length}',
      ),
      (
        Icons.local_shipping_outlined,
        'company_monitor.summary.purchases'.tr(),
        '${active.where((document) => document.isPurchase).length}',
      ),
      (
        Icons.assignment_return_outlined,
        'company_monitor.summary.returns'.tr(),
        '${active.where((document) => document.isReturn).length}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 780 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final value in values)
              SizedBox(
                width: width,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(value.$1),
                        const SizedBox(height: 8),
                        Text(
                          value.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          value.$3,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document});
  final CompanyDocumentSnapshot document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = document.isVoided;
    return Card(
      key: ValueKey('company-document-${document.documentId}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CompanyDocumentDetailScreen(document: document),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(child: Icon(_kindIcon(document.kind), size: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kindLabel(document.kind),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            decoration: muted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(
                          document.number,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    document.isVoided
                        ? 'company_monitor.voided'.tr()
                        : document.isRemote
                        ? 'company_monitor.remote'.tr()
                        : 'company_monitor.local'.tr(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _DetailLine(
                icon: Icons.store_outlined,
                text: document.branchName,
              ),
              _DetailLine(
                icon: Icons.warehouse_outlined,
                text: document.warehouseName,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat.yMd().add_Hm().format(
                        document.documentDate.toLocal(),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '${document.currencyCode} ${(document.totalMinor / 100).toStringAsFixed(2)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      decoration: muted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters});
  final bool hasFilters;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 56),
          const SizedBox(height: 12),
          Text(
            hasFilters
                ? 'company_monitor.no_filtered_documents'.tr()
                : 'company_monitor.no_documents'.tr(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

String _kindLabel(CompanyDocumentKind kind) => switch (kind) {
  CompanyDocumentKind.purchase => 'company_monitor.kinds.purchase'.tr(),
  CompanyDocumentKind.sale => 'company_monitor.kinds.sale'.tr(),
  CompanyDocumentKind.purchaseReturn =>
    'company_monitor.kinds.purchase_return'.tr(),
  CompanyDocumentKind.saleReturn => 'company_monitor.kinds.sale_return'.tr(),
  CompanyDocumentKind.purchaseAdjustmentReturn =>
    'company_monitor.kinds.purchase_adjustment_return'.tr(),
  CompanyDocumentKind.saleAdjustmentReturn =>
    'company_monitor.kinds.sale_adjustment_return'.tr(),
};

IconData _kindIcon(CompanyDocumentKind kind) => switch (kind) {
  CompanyDocumentKind.purchase => Icons.local_shipping_outlined,
  CompanyDocumentKind.sale => Icons.receipt_long_outlined,
  CompanyDocumentKind.purchaseReturn => Icons.keyboard_return_outlined,
  CompanyDocumentKind.saleReturn => Icons.assignment_return_outlined,
  CompanyDocumentKind.purchaseAdjustmentReturn => Icons.rule_outlined,
  CompanyDocumentKind.saleAdjustmentReturn => Icons.fact_check_outlined,
};
