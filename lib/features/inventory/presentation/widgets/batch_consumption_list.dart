import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/database/daos/batch_audit_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BATCH CONSUMPTION LIST  (Phase H3 — shared audit drill-down)
// ══════════════════════════════════════════════════════════════════════════════
//
// Public, reusable widget that renders the IN/OUT ledger of a single batch.
// Used by:
//   • `BatchesSectionWidget` (Phase H2, product detail "Batches" tab —
//     inline ExpansionTile children).
//   • `BatchManagementScreen` (Phase H3, standalone batch management screen
//     — bottom-sheet drill-down).
//
// Both surfaces must render IDENTICAL rows so the auditor sees the same
// information regardless of where they enter the drill-down. The widget is a
// pure renderer over a `Future<List<BatchConsumptionRecord>>` — the loading
// strategy (eager vs. lazy) is left to the parent.
// ══════════════════════════════════════════════════════════════════════════════

/// Renders the batch_consumptions ledger for a single batch. Pass a future
/// produced by `BatchAuditDao.getConsumptionsForBatch(batchId)`. The future
/// should be cached by the caller across rebuilds — re-creating it on each
/// build re-issues the SQL and flickers a spinner.
class BatchConsumptionList extends StatelessWidget {
  final Future<List<BatchConsumptionRecord>>? future;

  /// Optional padding override for embedding inside dense surfaces (e.g.
  /// ExpansionTile children) vs. spacious ones (e.g. BottomSheet).
  final EdgeInsetsGeometry padding;

  const BatchConsumptionList({
    super.key,
    required this.future,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (future == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return FutureBuilder<List<BatchConsumptionRecord>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final rows = snapshot.data ?? const <BatchConsumptionRecord>[];
        if (rows.isEmpty) {
          return Padding(
            padding: padding == EdgeInsets.zero
                ? const EdgeInsets.symmetric(vertical: 8)
                : padding,
            child: Text(
              'product_form.batches_no_consumptions'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final r in rows) BatchConsumptionRow(record: r)],
          ),
        );
      },
    );
  }
}

/// Single ledger row — IN movements rendered green (`+qty`), OUT red
/// (`−qty`). The reference label resolves to the source document's user-
/// facing identifier (e.g. `INV-202604-0123`) when available.
class BatchConsumptionRow extends StatelessWidget {
  final BatchConsumptionRecord record;

  const BatchConsumptionRow({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currency = sl<CurrencyService>();
    final isOut = record.direction == 'out';
    final tone = isOut ? cs.error : Colors.green.shade700;
    final icon = _iconFor(record.refKind, isOut);

    final quantity = localizedQuantity(record.quantity, record.measurementType);
    final qtyLabel = isOut ? '−$quantity' : '+$quantity';
    final ref = record.refLabel ?? _kindLabel(record.refKind);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ref,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      qtyLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat.yMMMd().add_Hm().format(record.createdAt)} • '
                  '${currency.format(record.unitCostCents)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String refKind, bool isOut) {
    switch (refKind) {
      case 'sale':
        return LucideIcons.shoppingCart;
      case 'sale_return':
      case 'sale_adj_return':
        return LucideIcons.undo2;
      case 'purchase_return':
      case 'purchase_adj_return':
        return LucideIcons.truck;
      case 'inventory_adjustment':
        return LucideIcons.sliders;
      default:
        return isOut ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft;
    }
  }

  static String _kindLabel(String refKind) {
    switch (refKind) {
      case 'sale':
        return 'product_form.batches_kind_sale'.tr();
      case 'sale_return':
        return 'product_form.batches_kind_sale_return'.tr();
      case 'purchase_return':
        return 'product_form.batches_kind_purchase_return'.tr();
      case 'inventory_adjustment':
        return 'product_form.batches_kind_adjustment'.tr();
      case 'purchase_adj_return':
        return 'product_form.batches_kind_purchase_adj_return'.tr();
      case 'sale_adj_return':
        return 'product_form.batches_kind_sale_adj_return'.tr();
      default:
        return refKind;
    }
  }
}
