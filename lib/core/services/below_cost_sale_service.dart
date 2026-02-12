import 'package:decimal/decimal.dart';

import '../../features/auth/domain/entities/user_entity.dart';

/// Result of a below-cost check on a sale line item.
class BelowCostCheckResult {
  final bool isBelowCost;
  final Decimal costCents;
  final Decimal sellingPriceCents;
  final Decimal lossCents;
  final String productName;
  final int productId;
  final bool canOverride;

  const BelowCostCheckResult({
    required this.isBelowCost,
    required this.costCents,
    required this.sellingPriceCents,
    required this.lossCents,
    required this.productName,
    required this.productId,
    required this.canOverride,
  });

  BelowCostCheckResult.ok()
      : isBelowCost = false,
        costCents = Decimal.zero,
        sellingPriceCents = Decimal.zero,
        lossCents = Decimal.zero,
        productName = '',
        productId = 0,
        canOverride = false;
}

/// Service that checks whether a sale line item is being sold below cost.
///
/// Rules:
/// - Uses ACTUAL cost from variant (or product fallback). No manual cost entry.
/// - Cashier / Salesperson: BLOCKED, cannot override.
/// - Manager / Owner: Can override with mandatory reason.
class BelowCostSaleService {
  const BelowCostSaleService();

  /// Check if a selling price is below cost for a product/variant.
  ///
  /// [costCents] - The actual cost (from variant or product).
  /// [sellingPriceCents] - The unit price being charged.
  /// [productName] - Display name for error messages.
  /// [productId] - Product ID for audit.
  /// [userRole] - Current user's role to determine override capability.
  BelowCostCheckResult check({
    required Decimal costCents,
    required Decimal sellingPriceCents,
    required String productName,
    required int productId,
    required UserRole userRole,
  }) {
    // Zero cost = no check (product has no cost set yet)
    if (costCents <= Decimal.zero) {
      return BelowCostCheckResult.ok();
    }

    if (sellingPriceCents >= costCents) {
      return BelowCostCheckResult.ok();
    }

    final loss = costCents - sellingPriceCents;
    final canOverride = _canOverride(userRole);

    return BelowCostCheckResult(
      isBelowCost: true,
      costCents: costCents,
      sellingPriceCents: sellingPriceCents,
      lossCents: loss,
      productName: productName,
      productId: productId,
      canOverride: canOverride,
    );
  }

  /// Only Manager and Owner can override below-cost sales.
  bool _canOverride(UserRole role) {
    return role == UserRole.owner || role == UserRole.manager;
  }

  /// Check if a role is allowed to override below-cost sales.
  static bool canRoleOverride(UserRole role) {
    return role == UserRole.owner || role == UserRole.manager;
  }
}
