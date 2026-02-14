import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';

import '../../features/auth/domain/entities/user_entity.dart';

/// Result of a below-cost check on a sale line item.
class BelowCostCheckResult extends Equatable {
  final bool isBelowCost;
  final Decimal costCents;
  final Decimal sellingPriceCents;
  final Decimal lossCents;
  final String productName;
  final int productId;
  final bool canOverride;
  /// True when loss exceeds the configured maximum allowed loss percentage.
  final bool exceedsThreshold;
  /// The loss as a percentage of cost (0-100).
  final double lossPercent;
  /// Unique stamp so repeated warnings for the same product still trigger listeners.
  final int _stamp;

  BelowCostCheckResult({
    required this.isBelowCost,
    required this.costCents,
    required this.sellingPriceCents,
    required this.lossCents,
    required this.productName,
    required this.productId,
    required this.canOverride,
    this.exceedsThreshold = false,
    this.lossPercent = 0,
  }) : _stamp = DateTime.now().microsecondsSinceEpoch;

  BelowCostCheckResult.ok()
      : isBelowCost = false,
        costCents = Decimal.zero,
        sellingPriceCents = Decimal.zero,
        lossCents = Decimal.zero,
        productName = '',
        productId = 0,
        canOverride = false,
        exceedsThreshold = false,
        lossPercent = 0,
        _stamp = 0;

  @override
  List<Object?> get props => [isBelowCost, costCents, sellingPriceCents, lossCents, productName, productId, canOverride, exceedsThreshold, lossPercent, _stamp];
}

/// Service that checks whether a sale line item is being sold below cost.
///
/// Rules:
/// - Uses ACTUAL cost from variant (or product fallback). No manual cost entry.
/// - Cashier / Salesperson: BLOCKED, cannot override.
/// - Manager / Owner: Can override with mandatory reason.
class BelowCostSaleService {
  /// Maximum allowed loss as a percentage of cost (0-100).
  /// When loss exceeds this threshold, an extra warning is shown.
  /// Set to 0 to disable threshold warnings. Default: 50%.
  final double maxAllowedLossPercent;

  const BelowCostSaleService({this.maxAllowedLossPercent = 50});

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
    final lossPercent = loss.toDouble() / costCents.toDouble() * 100;
    final exceedsThreshold = maxAllowedLossPercent > 0 && lossPercent > maxAllowedLossPercent;

    return BelowCostCheckResult(
      isBelowCost: true,
      costCents: costCents,
      sellingPriceCents: sellingPriceCents,
      lossCents: loss,
      productName: productName,
      productId: productId,
      canOverride: canOverride,
      exceedsThreshold: exceedsThreshold,
      lossPercent: lossPercent,
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
