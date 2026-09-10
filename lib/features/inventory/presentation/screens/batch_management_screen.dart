import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/daos/batch_audit_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../widgets/batch_consumption_list.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BATCH MANAGEMENT SCREEN  (Phase H3 — standalone audit/transparency surface)
// ══════════════════════════════════════════════════════════════════════════════
//
// Cross-product, FEFO-ordered batch listing with filter chips for:
//   • Source         (purchase / opening / found / sale_return)
//   • Expiry bucket  (no expiry / expired / ≤30 / ≤60 / ≤90 days)
//   • Free-text search across product name, SKU and batch number
//   • Toggle: include depleted batches
//
// Each row reveals the same consumption ledger (`BatchConsumptionList`) the
// product detail "Batches" tab uses, so the auditor sees identical numbers
// regardless of entry point.
//
// Architectural rules mirrored from the rest of Phase H:
//   • Read-only. No edit/create affordances. All write paths flow through
//     Purchase / Return / Adjustment forms (which already exist).
//   • Reactive. The DAO stream re-emits on any IN/OUT movement, so the list
//     and counters stay live without manual refresh.
//   • Display unit-cost values via `CurrencyService.format` so the currency
//     and locale formatting match the rest of the app.
// ══════════════════════════════════════════════════════════════════════════════

class BatchManagementScreen extends StatefulWidget {
  const BatchManagementScreen({super.key});

  @override
  State<BatchManagementScreen> createState() => _BatchManagementScreenState();
}

class _BatchManagementScreenState extends State<BatchManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  String _query = '';
  String? _source; // null = All
  BatchExpiryFilter? _expiryFilter; // null = All
  bool _includeDepleted = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dao = sl<BatchAuditDao>();

    return Scaffold(
      appBar: AppBar(title: Text('batch_management.title'.tr())),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'batch_management.search_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              onChanged: (q) {
                setState(() {}); // refresh clear-button visibility
                _onSearchChanged(q);
              },
            ),
          ),

          // Source filter row
          _SourceFilterRow(
            value: _source,
            onChanged: (v) => setState(() => _source = v),
          ),

          // Expiry filter row
          _ExpiryFilterRow(
            value: _expiryFilter,
            onChanged: (v) => setState(() => _expiryFilter = v),
          ),

          // Include-depleted toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Switch.adaptive(
                  value: _includeDepleted,
                  onChanged: (v) => setState(() => _includeDepleted = v),
                ),
                const SizedBox(width: 8),
                Text(
                  'batch_management.include_depleted'.tr(),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Live list
          Expanded(
            child: StreamBuilder<List<BatchSummary>>(
              stream: dao.watchAllBatches(
                query: _query,
                source: _source,
                expiryFilter: _expiryFilter,
                includeDepleted: _includeDepleted,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        snapshot.error.toString(),
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final rows = snapshot.data ?? const <BatchSummary>[];
                if (rows.isEmpty) {
                  return _EmptyState(hasFilters: _hasAnyFilter);
                }
                return _CountedList(rows: rows);
              },
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasAnyFilter =>
      _query.isNotEmpty ||
      _source != null ||
      _expiryFilter != null ||
      _includeDepleted;
}

// ─── Source filter row ───────────────────────────────────────────────────────

class _SourceFilterRow extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _SourceFilterRow({required this.value, required this.onChanged});

  static const List<({String? value, String labelKey, IconData icon})>
  _options = [
    (
      value: null,
      labelKey: 'batch_management.source_all',
      icon: LucideIcons.layers,
    ),
    (
      value: 'purchase',
      labelKey: 'product_form.batches_source_purchase',
      icon: LucideIcons.truck,
    ),
    (
      value: 'opening',
      labelKey: 'product_form.batches_source_opening',
      icon: LucideIcons.flag,
    ),
    (
      value: 'found',
      labelKey: 'product_form.batches_source_found',
      icon: LucideIcons.sliders,
    ),
    (
      value: 'sale_return',
      labelKey: 'product_form.batches_source_sale_return',
      icon: LucideIcons.undo2,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final opt in _options) ...[
              FilterChip(
                avatar: Icon(opt.icon, size: 14),
                label: Text(opt.labelKey.tr()),
                selected: value == opt.value,
                onSelected: (_) => onChanged(opt.value),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Expiry filter row ───────────────────────────────────────────────────────

class _ExpiryFilterRow extends StatelessWidget {
  final BatchExpiryFilter? value;
  final ValueChanged<BatchExpiryFilter?> onChanged;

  const _ExpiryFilterRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip(
              label: 'reports.expiry_report_filter_all'.tr(),
              selected: value == null,
              onTap: () => onChanged(null),
            ),
            const SizedBox(width: 8),
            _chip(
              label: 'batch_management.expiry_none'.tr(),
              selected: value == BatchExpiryFilter.none,
              onTap: () => onChanged(BatchExpiryFilter.none),
            ),
            const SizedBox(width: 8),
            _chip(
              label: 'reports.expiry_report_filter_expired'.tr(),
              selected: value == BatchExpiryFilter.expired,
              onTap: () => onChanged(BatchExpiryFilter.expired),
              tone: Colors.red,
            ),
            const SizedBox(width: 8),
            _chip(
              label: 'reports.expiry_report_filter_30'.tr(),
              selected: value == BatchExpiryFilter.in30Days,
              onTap: () => onChanged(BatchExpiryFilter.in30Days),
              tone: Colors.orange,
            ),
            const SizedBox(width: 8),
            _chip(
              label: 'reports.expiry_report_filter_60'.tr(),
              selected: value == BatchExpiryFilter.in60Days,
              onTap: () => onChanged(BatchExpiryFilter.in60Days),
              tone: Colors.amber.shade700,
            ),
            const SizedBox(width: 8),
            _chip(
              label: 'reports.expiry_report_filter_90'.tr(),
              selected: value == BatchExpiryFilter.in90Days,
              onTap: () => onChanged(BatchExpiryFilter.in90Days),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? tone,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: tone?.withValues(alpha: 0.18),
      checkmarkColor: tone,
    );
  }
}

// ─── List ─────────────────────────────────────────────────────────────────────

class _CountedList extends StatelessWidget {
  final List<BatchSummary> rows;
  const _CountedList({required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final remainingByType = <String, int>{};
    for (final batch in rows) {
      remainingByType.update(
        batch.measurementType,
        (value) => value + batch.remainingQuantity,
        ifAbsent: () => batch.remainingQuantity,
      );
    }
    final totalValueCents = rows.fold<int>(
      0,
      (s, b) => s + b.totalRemainingValueCents,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'batch_management.count_summary'.tr(
                    args: [
                      '${rows.length}',
                      localizedQuantityTotals(remainingByType),
                    ],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                sl<CurrencyService>().format(totalValueCents),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _BatchTile(batch: rows[i]),
          ),
        ),
      ],
    );
  }
}

class _BatchTile extends StatelessWidget {
  final BatchSummary batch;
  const _BatchTile({required this.batch});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currency = sl<CurrencyService>();
    final expiryStatus = _expiryStatusFor(batch.expiryDate);
    final tileTone = expiryStatus.color ?? cs.outlineVariant;

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDrillDown(context, batch),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row: product name + remaining/received
              Row(
                children: [
                  Icon(LucideIcons.package, size: 18, color: tileTone),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          batch.productName ??
                              'batch_management.unknown_product'.tr(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          batch.batchNumber,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'product_form.batches_remaining'.tr(
                      args: [
                        localizedQuantity(
                          batch.remainingQuantity,
                          batch.measurementType,
                        ),
                        localizedQuantity(
                          batch.receivedQuantity,
                          batch.measurementType,
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Chips
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (batch.productSku != null && batch.productSku!.isNotEmpty)
                    _Chip(
                      label: batch.productSku!,
                      icon: LucideIcons.hash,
                      color: cs.onSurfaceVariant,
                    ),
                  if (batch.variantLabel != null)
                    _Chip(
                      label: batch.variantLabel!,
                      icon: LucideIcons.tag,
                      color: cs.primary,
                    ),
                  _Chip(
                    label: 'product_form.batches_unit_cost'.tr(
                      args: [currency.format(batch.unitCostCents)],
                    ),
                    icon: LucideIcons.dollarSign,
                    color: cs.tertiary,
                  ),
                  if (batch.expiryDate != null)
                    _Chip(
                      label: 'product_form.batches_expiry_on'.tr(
                        args: [
                          DateFormat('dd/MM/yyyy').format(batch.expiryDate!),
                        ],
                      ),
                      icon: LucideIcons.calendarClock,
                      color: expiryStatus.color ?? cs.onSurfaceVariant,
                    ),
                  if (batch.supplierName != null &&
                      batch.supplierName!.isNotEmpty)
                    _Chip(
                      label: batch.supplierName!,
                      icon: LucideIcons.building2,
                      color: cs.onSurfaceVariant,
                    ),
                  _Chip(
                    label: _sourceLabel(batch.source),
                    icon: LucideIcons.gitBranch,
                    color: cs.secondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDrillDown(BuildContext context, BatchSummary batch) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BatchDrillDownSheet(batch: batch),
    );
  }

  static String _sourceLabel(String source) {
    switch (source) {
      case 'purchase':
        return 'product_form.batches_source_purchase'.tr();
      case 'opening':
        return 'product_form.batches_source_opening'.tr();
      case 'found':
        return 'product_form.batches_source_found'.tr();
      case 'sale_return':
        return 'product_form.batches_source_sale_return'.tr();
      default:
        return source;
    }
  }

  ({Color? color}) _expiryStatusFor(DateTime? expiry) {
    if (expiry == null) return const (color: null);
    final now = DateTime.now();
    if (expiry.isBefore(now)) return (color: Colors.red.shade700);
    if (expiry.isBefore(now.add(const Duration(days: 30)))) {
      return (color: Colors.orange.shade700);
    }
    return const (color: null);
  }
}

// ─── Drill-down sheet ────────────────────────────────────────────────────────

class _BatchDrillDownSheet extends StatelessWidget {
  final BatchSummary batch;
  const _BatchDrillDownSheet({required this.batch});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currency = sl<CurrencyService>();
    final future = sl<BatchAuditDao>().getConsumptionsForBatch(batch.batchId);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                batch.productName ?? 'batch_management.unknown_product'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                batch.batchNumber,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // Key facts
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FactPill(
                    icon: LucideIcons.boxes,
                    label: 'product_form.batches_remaining'.tr(
                      args: [
                        localizedQuantity(
                          batch.remainingQuantity,
                          batch.measurementType,
                        ),
                        localizedQuantity(
                          batch.receivedQuantity,
                          batch.measurementType,
                        ),
                      ],
                    ),
                  ),
                  _FactPill(
                    icon: LucideIcons.dollarSign,
                    label: 'product_form.batches_unit_cost'.tr(
                      args: [currency.format(batch.unitCostCents)],
                    ),
                  ),
                  if (batch.expiryDate != null)
                    _FactPill(
                      icon: LucideIcons.calendarClock,
                      label: 'product_form.batches_expiry_on'.tr(
                        args: [
                          DateFormat('dd/MM/yyyy').format(batch.expiryDate!),
                        ],
                      ),
                    ),
                  _FactPill(
                    icon: LucideIcons.truck,
                    label: 'product_form.batches_received_on'.tr(
                      args: [
                        DateFormat('dd/MM/yyyy').format(batch.receivedDate),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(
                'batch_management.drilldown_title'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              BatchConsumptionList(
                future: future,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FactPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FactPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  const _EmptyState({required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.layers, size: 56, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              hasFilters
                  ? 'batch_management.empty_filtered'.tr()
                  : 'batch_management.empty_all'.tr(),
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared chip ─────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _Chip({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
