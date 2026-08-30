import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/daos/batch_audit_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import 'batch_consumption_list.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BATCHES SECTION WIDGET  (Phase H2 — product detail "Batches" tab)
// ══════════════════════════════════════════════════════════════════════════════
//
// Read-only audit surface for the product detail screen. Streams the FEFO-
// ordered list of active batches for a product (optionally narrowed to a
// variant) from `BatchAuditDao.watchBatchesForProduct`, and lazily loads each
// batch's consumption ledger on expansion via `getConsumptionsForBatch`.
//
// Architectural rule mirrored from `batch_audit_dao.dart`:
//   • This widget NEVER initiates writes. There is no "edit batch" affordance.
//   • The only paths that produce/consume batches are Purchase, Return,
//     Adjustment — all of which already exist with their own dialogs/forms.
//
// The widget is intentionally self-contained (no Bloc) because it has no
// mutable state of its own. Reactivity flows from Drift's `customSelect.watch`
// → StreamBuilder, which already debounces rebuilds at the SQL layer.
// ══════════════════════════════════════════════════════════════════════════════

/// Inline section showing every active batch for [productId] (optionally
/// filtered by [variantId]). Each batch row expands to its full consumption
/// ledger with human-readable references (INV-XXXX, SR-XXXX, …).
///
/// Drop into any product detail screen. Renders nothing (zero chrome) when the
/// product has no active batches — same UX rule the other inventory sections
/// follow.
class BatchesSectionWidget extends StatelessWidget {
  final int productId;

  /// When non-null, narrows the list to a single variant. When null, shows
  /// all variants for the product (each row carries a variant chip).
  final int? variantId;

  /// When `true`, depleted/inactive batches are also shown. The default
  /// (`false`) keeps the list focused on what the next sale will actually
  /// consume from.
  final bool includeDepleted;

  const BatchesSectionWidget({
    super.key,
    required this.productId,
    this.variantId,
    this.includeDepleted = false,
  });

  @override
  Widget build(BuildContext context) {
    final dao = sl<BatchAuditDao>();
    return StreamBuilder<List<BatchSummary>>(
      stream: dao.watchBatchesForProduct(
        productId: productId,
        variantId: variantId,
        includeDepleted: includeDepleted,
      ),
      builder: (context, snapshot) {
        final batches = snapshot.data ?? const <BatchSummary>[];
        if (batches.isEmpty) return const SizedBox.shrink();
        return _BatchesCard(batches: batches);
      },
    );
  }
}

class _BatchesCard extends StatelessWidget {
  final List<BatchSummary> batches;
  const _BatchesCard({required this.batches});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(LucideIcons.layers, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'product_form.batches_title'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _CountPill(count: batches.length),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: batches.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, indent: 12, endIndent: 12),
            itemBuilder: (context, i) => _BatchTile(batch: batches[i]),
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int count;
  const _CountPill({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Single batch row with an inline expand → consumption ledger.
///
/// Uses a one-shot `getConsumptionsForBatch` future on first expansion (cached
/// for the rest of the screen's lifetime). The cache is invalidated whenever
/// the parent stream re-emits with a new `BatchSummary` (different
/// `remainingQuantity`), because the constructor reuses `batchId` as the key.
class _BatchTile extends StatefulWidget {
  final BatchSummary batch;
  const _BatchTile({required this.batch});

  @override
  State<_BatchTile> createState() => _BatchTileState();
}

class _BatchTileState extends State<_BatchTile> {
  bool _expanded = false;
  Future<List<BatchConsumptionRecord>>? _consumptionsFuture;
  int? _cachedForBatchSnapshot;

  void _ensureLoaded() {
    // Re-fetch when remaining changes (i.e. a new sale/return/adjustment hit).
    final snapshotKey = Object.hash(
      widget.batch.batchId,
      widget.batch.remainingQuantity,
    );
    if (_consumptionsFuture == null || _cachedForBatchSnapshot != snapshotKey) {
      _consumptionsFuture = sl<BatchAuditDao>().getConsumptionsForBatch(
        widget.batch.batchId,
      );
      _cachedForBatchSnapshot = snapshotKey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final batch = widget.batch;
    final currency = sl<CurrencyService>();
    final expiryStatus = _expiryStatusFor(batch.expiryDate);

    return Theme(
      // Strip the default ExpansionTile divider; we already have one between rows.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        onExpansionChanged: (expanded) {
          if (expanded) {
            _ensureLoaded();
          }
          setState(() => _expanded = expanded);
        },
        leading: Icon(
          LucideIcons.package,
          size: 18,
          color: expiryStatus.color ?? cs.onSurfaceVariant,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                batch.batchNumber,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
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
              _Chip(
                label: 'product_form.batches_received_on'.tr(
                  args: [DateFormat.yMMMd().format(batch.receivedDate)],
                ),
                icon: LucideIcons.truck,
                color: cs.onSurfaceVariant,
              ),
              if (batch.expiryDate != null)
                _Chip(
                  label: 'product_form.batches_expiry_on'.tr(
                    args: [DateFormat.yMMMd().format(batch.expiryDate!)],
                  ),
                  icon: LucideIcons.calendarClock,
                  color: expiryStatus.color ?? cs.onSurfaceVariant,
                ),
              if (batch.supplierName != null && batch.supplierName!.isNotEmpty)
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
        ),
        trailing: Icon(
          _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
          size: 18,
          color: cs.onSurfaceVariant,
        ),
        children: [BatchConsumptionList(future: _consumptionsFuture)],
      ),
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
