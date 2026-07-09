import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/database/daos/batch_audit_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BATCH FLOW WIDGET  (Phase H4 — sale detail "where did COGS come from?")
// ══════════════════════════════════════════════════════════════════════════════
//
// Read-only audit surface for the sale detail screen. Reconstructs the FEFO
// breakdown of every sale line by replaying `batch_consumptions` via
// `BatchAuditDao.getBatchFlowForSale`.
//
// For batch-tracked products this shows the auditor exactly which batches
// fed each line, at which frozen unit cost — the same data the manual-
// verification workflow described in INVENTORY_ARCHITECTURE.md §11 needs.
//
// For WAC / standard-tracked lines the helper returns no consumption rows;
// we still render the line with its `sale_items.cost_cents` snapshot so the
// auditor sees the recognised COGS even though no batch ledger exists.
//
// Returns are NETTED inside the DAO (out − in), so partial returns surface
// here as the *current* COGS still recognised on the sale, not the gross
// pre-return amount.
// ══════════════════════════════════════════════════════════════════════════════

class BatchFlowWidget extends StatelessWidget {
  final int saleId;

  const BatchFlowWidget({super.key, required this.saleId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SaleLineBatchFlow>>(
      future: sl<BatchAuditDao>().getBatchFlowForSale(saleId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final lines = snapshot.data ?? const <SaleLineBatchFlow>[];
        if (lines.isEmpty) return const SizedBox.shrink();

        // Hide the section entirely if NO line has a batch breakdown — the
        // information would just duplicate what the items card already shows.
        final hasAnyBatched = lines.any((l) => l.isBatchTracked);
        if (!hasAnyBatched) return const SizedBox.shrink();

        return _BatchFlowCard(lines: lines);
      },
    );
  }
}

class _BatchFlowCard extends StatelessWidget {
  final List<SaleLineBatchFlow> lines;
  const _BatchFlowCard({required this.lines});

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
                    'sales.batch_flow_title'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'sales.batch_flow_subtitle'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          for (int i = 0; i < lines.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
            _SaleLineFlowRow(line: lines[i]),
          ],
        ],
      ),
    );
  }
}

class _SaleLineFlowRow extends StatelessWidget {
  final SaleLineBatchFlow line;
  const _SaleLineFlowRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currency = sl<CurrencyService>();

    final title = line.variantLabel == null
        ? line.productName
        : '${line.productName} • ${line.variantLabel}';

    final reconstructed = line.reconstructedCogsCents;
    final snapshot = line.snapshotCostCents ?? 0;
    // `snapshot` is a PER-UNIT cost (sale_items.cost_cents) while
    // `reconstructed` is the TOTAL COGS across net-consumed batch quantity.
    // Compare like-for-like by expanding the snapshot to the same net
    // quantity the ledger reflects (post-return), allowing ±1 cent per unit
    // for the blended-cost rounding stamped at sale time.
    final netQty = line.batches.fold<int>(0, (s, b) => s + b.quantity);
    final expectedFromSnapshot = snapshot * netQty;
    final hasMismatch = line.isBatchTracked &&
        snapshot > 0 &&
        netQty > 0 &&
        (reconstructed - expectedFromSnapshot).abs() > netQty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '× ${line.totalQuantity}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (line.isBatchTracked) ...[
            for (final b in line.batches)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(LucideIcons.package, size: 13, color: cs.tertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        b.batchNumber,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${b.quantity} × ${currency.format(b.unitCostCents)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      currency.format(b.totalCostCents),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'sales.batch_flow_total_cogs'.tr(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  currency.format(reconstructed),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (hasMismatch)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(LucideIcons.alertTriangle, size: 13, color: cs.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'sales.batch_flow_mismatch'
                            .tr(args: [currency.format(snapshot)]),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ] else ...[
            // WAC / standard-tracked line: no batch ledger — show snapshot.
            Row(
              children: [
                Icon(LucideIcons.info, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'sales.batch_flow_no_batches'.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                if (snapshot > 0)
                  Text(
                    currency.format(snapshot),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
