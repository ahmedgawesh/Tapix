import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../di/injection_container.dart';
import '../services/currency_service.dart';
import '../services/void_impact_analyzer.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// VoidImpactDialog — pre-flight UX surface for the void operation.
///
/// Reads a [VoidImpactReport] from [VoidImpactAnalyzer] and renders it in
/// three semantic sections:
///
///   1. **Blockers** (red) — entangled adjustment returns + projected
///      negative-stock lines. The "Confirm void" button is DISABLED while
///      any blocker exists. The user is told exactly which return number
///      to void first, and the projected stock numbers per variant.
///
///   2. **Warnings** (amber) — linked returns that will cascade-void.
///      Allowed but the user is told which return numbers will flip.
///
///   3. **Estimated GL impact** (neutral) — signed AR/AP and Inventory
///      deltas in the user's display currency. This is what world-class
///      tools (NetSuite, SAP, Odoo) all show before confirming.
///
/// The dialog returns `true` only when the user clicked the confirm
/// button AND there were no blockers. Any other dismissal returns
/// `false` / `null`.
///
/// Used by:
///   • `lib/features/sales/presentation/screens/sale_detail_screen.dart`
///   • `lib/features/purchases/presentation/screens/purchase_detail_screen.dart`
/// ──────────────────────────────────────────────────────────────────────────
class VoidImpactDialog extends StatelessWidget {
  final VoidImpactReport report;

  const VoidImpactDialog({super.key, required this.report});

  /// Convenience: shows the dialog and returns `true` only when the user
  /// confirms a non-blocked void.
  static Future<bool> show(
    BuildContext context,
    VoidImpactReport report,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => VoidImpactDialog(report: report),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cs = sl<CurrencyService>();
    final isSale = report.side == 'sale';

    final hasBlockers = report.hasBlockers;
    final hasWarnings = report.hasWarnings;

    return AlertDialog(
      icon: Icon(
        hasBlockers ? LucideIcons.shieldAlert : LucideIcons.alertTriangle,
        color: hasBlockers ? scheme.error : Colors.amber.shade700,
        size: 36,
      ),
      title: Text(
        hasBlockers
            ? 'void_impact.blocked_title'.tr()
            : 'void_impact.confirm_title'.tr(),
        textAlign: TextAlign.center,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Headline summary
              Text(
                hasBlockers
                    ? 'void_impact.blocked_summary'.tr()
                    : 'void_impact.warning_summary'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hasBlockers ? scheme.error : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),

              // ── Section 1: Blockers ────────────────────────────────
              if (report.entangledAdjustmentReturns.isNotEmpty)
                _Section(
                  color: scheme.error,
                  icon: LucideIcons.ban,
                  title: 'void_impact.entangled_returns_title'.tr(),
                  description: 'void_impact.entangled_returns_description'.tr(),
                  rows: report.entangledAdjustmentReturns
                      .map(
                        (e) => _Row(
                          label: e.returnNumber,
                          value: cs.formatCents(e.totalCents),
                        ),
                      )
                      .toList(),
                ),

              if (report.negativeStockRisks.isNotEmpty)
                _Section(
                  color: scheme.error,
                  icon: LucideIcons.packageX,
                  title: 'void_impact.negative_stock_title'.tr(),
                  description: 'void_impact.negative_stock_description'.tr(),
                  rows: report.negativeStockRisks
                      .map(
                        (r) => _Row(
                          label: 'void_impact.product_label'.tr(
                            namedArgs: {
                              'pid': r.productId.toString(),
                              'vid': r.variantId?.toString() ?? '—',
                            },
                          ),
                          value: 'void_impact.stock_short_value'.tr(
                            namedArgs: {
                              'have': r.currentStock.toString(),
                              'need': r.requiredQuantity.toString(),
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),

              // ── Section 2: Warnings (cascade-voided linked returns) ──
              if (hasWarnings)
                _Section(
                  color: Colors.amber.shade700,
                  icon: LucideIcons.alertTriangle,
                  title: 'void_impact.linked_cascade_title'.tr(),
                  description: 'void_impact.linked_cascade_description'.tr(),
                  rows: report.linkedReturns
                      .map(
                        (e) => _Row(
                          label: e.returnNumber,
                          value: cs.formatCents(e.totalCents),
                        ),
                      )
                      .toList(),
                ),

              // ── Section 3: Estimated GL impact ──────────────────────
              _Section(
                color: scheme.primary,
                icon: LucideIcons.calculator,
                title: 'void_impact.gl_impact_title'.tr(),
                description: 'void_impact.gl_impact_description'.tr(),
                rows: [
                  _Row(
                    label: isSale
                        ? 'void_impact.gl_ar_label'.tr()
                        : 'void_impact.gl_ap_label'.tr(),
                    value: _signed(cs, report.estimatedArAdjustmentCents),
                  ),
                  _Row(
                    label: 'void_impact.gl_inventory_label'.tr(),
                    value: _signed(
                      cs,
                      report.estimatedInventoryAdjustmentCents,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton.icon(
          icon: const Icon(LucideIcons.ban, size: 16),
          onPressed: hasBlockers ? null : () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          label: Text(
            isSale ? 'sales.void_sale'.tr() : 'purchases.void_purchase'.tr(),
          ),
        ),
      ],
    );
  }

  String _signed(CurrencyService cs, int cents) {
    if (cents == 0) return cs.formatCents(0);
    final sign = cents > 0 ? '+' : '−';
    return '$sign${cs.formatCents(cents.abs())}';
  }
}

class _Section extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String description;
  final List<_Row> rows;

  const _Section({
    required this.color,
    required this.icon,
    required this.title,
    required this.description,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (rows.isNotEmpty) ...[const SizedBox(height: 8), ...rows],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
