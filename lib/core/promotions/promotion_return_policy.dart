import 'promotion_sale_snapshot.dart';

/// Describes the promotion application that makes a linked return invalid.
class PromotionBundleReturnViolation {
  final int promotionId;
  final String promotionName;

  const PromotionBundleReturnViolation({
    required this.promotionId,
    required this.promotionName,
  });
}

/// Raised by the authoritative sales repository when a caller attempts to
/// return only part of a persisted buy-X-get-Y promotion application.
class PromotionBundleReturnException implements Exception {
  static const messageKey = 'promotions.errors.bundle_return_together';

  final PromotionBundleReturnViolation violation;

  const PromotionBundleReturnException(this.violation);

  @override
  String toString() => messageKey;
}

/// Linked-return rules that operate only on immutable invoice snapshots.
///
/// Promotion engine v4 persists every qualifier and reward line for a
/// buy-X-get-Y application. Older snapshots did not persist enough information
/// to reconstruct the complete bundle safely, so they deliberately keep their
/// historical return behaviour.
abstract final class PromotionReturnPolicy {
  static PromotionBundleReturnViolation? validateLinkedReturn({
    required Iterable<SalePromotionSnapshot> promotionApplications,
    required Map<int, int> previouslyReturnedQuantityBySaleItemId,
    required Map<int, int> requestedQuantityBySaleItemId,
  }) {
    for (final application in promotionApplications) {
      if (!_requiresWholeBundleReturn(application)) continue;

      final allocations = application.allocations
          .where((allocation) => allocation.appliedQuantity > 0)
          .toList(growable: false);
      if (!allocations.any(
        (allocation) =>
            (requestedQuantityBySaleItemId[allocation.saleItemId] ?? 0) > 0,
      )) {
        continue;
      }

      final applicationCount = application.applicationCount;
      int? completedBundleCount;
      for (final allocation in allocations) {
        final previous =
            previouslyReturnedQuantityBySaleItemId[allocation.saleItemId] ?? 0;
        final requested =
            requestedQuantityBySaleItemId[allocation.saleItemId] ?? 0;
        final cumulative = (previous + requested).clamp(
          0,
          allocation.appliedQuantity,
        );

        // Allocation quantity is the total quantity across every repetition of
        // this application. A valid linked return must complete the same number
        // of repetitions on every participating invoice line.
        final scaled = cumulative * applicationCount;
        if (scaled % allocation.appliedQuantity != 0) {
          return PromotionBundleReturnViolation(
            promotionId: application.promotionId,
            promotionName: application.name,
          );
        }
        final returnedBundles = scaled ~/ allocation.appliedQuantity;
        if (completedBundleCount != null &&
            completedBundleCount != returnedBundles) {
          return PromotionBundleReturnViolation(
            promotionId: application.promotionId,
            promotionName: application.name,
          );
        }
        completedBundleCount = returnedBundles;
      }
    }
    return null;
  }

  static bool _requiresWholeBundleReturn(SalePromotionSnapshot application) {
    if (application.type != 'buy_x_get_y' ||
        application.applicationCount <= 0 ||
        application.allocations.isEmpty ||
        !application.allocations.any(
          (allocation) => allocation.rewardType == 'free_quantity',
        )) {
      return false;
    }

    final versionMatch = RegExp(
      r'^promotion-v(\d+)',
    ).firstMatch(application.engineVersion);
    final engineMajor = int.tryParse(versionMatch?.group(1) ?? '') ?? 0;
    return engineMajor >= 4;
  }
}
