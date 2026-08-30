import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

/// Result type from the return type selection bottom sheet.
enum ReturnType { linked, adjustment }

/// Premium bottom sheet that lets the user choose between
/// a Linked Return (invoice-based) and an Adjustment Return (unlinked).
///
/// Returns [ReturnType.linked] or [ReturnType.adjustment], or null if dismissed.
Future<ReturnType?> showReturnTypeBottomSheet(
  BuildContext context, {
  /// 'purchase' or 'sale'
  required String returnContext,
}) {
  return showModalBottomSheet<ReturnType>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ReturnTypeSheet(returnContext: returnContext),
  );
}

class _ReturnTypeSheet extends StatelessWidget {
  final String returnContext;
  const _ReturnTypeSheet({required this.returnContext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isPurchase = returnContext == 'purchase';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(LucideIcons.undo2, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'returns.choose_return_type'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isPurchase
                            ? 'returns.choose_return_type_purchase_desc'.tr()
                            : 'returns.choose_return_type_sale_desc'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Option 1: Linked Return (recommended)
            _ReturnTypeOption(
              icon: LucideIcons.link,
              title: 'returns.linked_return'.tr(),
              description: isPurchase
                  ? 'returns.linked_return_purchase_desc'.tr()
                  : 'returns.linked_return_sale_desc'.tr(),
              badgeText: 'returns.recommended'.tr(),
              badgeColor: Colors.green,
              borderColor: cs.primary.withValues(alpha: 0.3),
              onTap: () => Navigator.pop(context, ReturnType.linked),
            ),
            const SizedBox(height: 12),

            // Option 2: Adjustment Return
            _ReturnTypeOption(
              icon: LucideIcons.unlink,
              title: 'returns.adjustment_return'.tr(),
              description: isPurchase
                  ? 'returns.adjustment_return_purchase_desc'.tr()
                  : 'returns.adjustment_return_sale_desc'.tr(),
              badgeText: 'returns.advanced'.tr(),
              badgeColor: Colors.orange,
              borderColor: cs.outlineVariant.withValues(alpha: 0.5),
              warningText: 'returns.adjustment_cost_warning'.tr(),
              onTap: () => Navigator.pop(context, ReturnType.adjustment),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnTypeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String badgeText;
  final Color badgeColor;
  final Color borderColor;
  final String? warningText;
  final VoidCallback onTap;

  const _ReturnTypeOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.badgeText,
    required this.badgeColor,
    required this.borderColor,
    this.warningText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: badgeColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      badgeText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 44),
                child: Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              if (warningText != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 44),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.alertTriangle,
                            size: 12, color: Colors.amber.shade700),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            warningText!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.amber.shade800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
