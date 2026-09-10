import '../money/money.dart';
import 'promotion_engine.dart';

/// Cost and pricing facts for one cart line, expressed before tax.
class PromotionMarginLine {
  final String lineId;
  final int quantity;
  final int quantityScale;
  final Money unitCost;
  final Money netBeforePromotions;

  const PromotionMarginLine({
    required this.lineId,
    required this.quantity,
    required this.quantityScale,
    required this.unitCost,
    required this.netBeforePromotions,
  });

  Money get totalCost =>
      unitCost.multiplyRatio(quantity, quantityScale).round();
}

/// Allows an automatic free-item promotion to cross an individual line's
/// recorded cost only when the exact promotion bundle remains profitable.
///
/// The policy is intentionally narrow:
/// - only Buy X Get Y / free-quantity applications qualify;
/// - manual/invoice pricing must have kept every participating line at or
///   above its own recorded cost before promotions;
/// - the bundle's post-promotion net revenue must cover the recorded cost of
///   all participating quantities.
abstract final class PromotionMarginPolicy {
  static Set<String> profitableFreeBundleLineIds({
    required PromotionEvaluationResult evaluation,
    required Iterable<PromotionMarginLine> lines,
  }) {
    final lineById = {for (final line in lines) line.lineId: line};
    final totalPromotionDiscountByLine = evaluation.discountByLine;
    final allowed = <String>{};

    for (final application in evaluation.applications) {
      if (application.type != PromotionType.buyXGetY ||
          !application.allocations.any(
            (allocation) =>
                allocation.rewardType == PromotionRewardType.freeQuantity,
          )) {
        continue;
      }

      final allocationsByLine = <String, PromotionAllocation>{};
      for (final allocation in application.allocations) {
        final existing = allocationsByLine[allocation.lineId];
        allocationsByLine[allocation.lineId] = existing == null
            ? allocation
            : PromotionAllocation(
                lineId: allocation.lineId,
                discount: existing.discount + allocation.discount,
                appliedQuantity:
                    existing.appliedQuantity + allocation.appliedQuantity,
                quantityScale: allocation.quantityScale,
                rewardType: allocation.rewardType,
              );
      }

      var bundleCost = Money.zero;
      var bundleNet = Money.zero;
      var safe = allocationsByLine.isNotEmpty;
      for (final entry in allocationsByLine.entries) {
        final line = lineById[entry.key];
        final allocation = entry.value;
        if (line == null ||
            line.quantity <= 0 ||
            line.quantityScale <= 0 ||
            allocation.appliedQuantity <= 0 ||
            allocation.appliedQuantity > line.quantity ||
            allocation.quantityScale != line.quantityScale) {
          safe = false;
          break;
        }

        // A manual or invoice discount may never use this exemption. Only the
        // automatic free-item promotion is allowed to pool margin.
        if (line.netBeforePromotions < line.totalCost) {
          safe = false;
          break;
        }

        final selectedCost = line.unitCost
            .multiplyRatio(allocation.appliedQuantity, allocation.quantityScale)
            .round();
        final selectedNetBefore = line.netBeforePromotions
            .multiplyRatio(allocation.appliedQuantity, line.quantity)
            .round();

        // Subtract every automatic promotion discount on this line. This is
        // deliberately conservative if compound promotions overlap.
        final promotionDiscount =
            totalPromotionDiscountByLine[entry.key] ?? Money.zero;
        final selectedNetAfter = (selectedNetBefore - promotionDiscount)
            .clampNonNegative();
        bundleCost += selectedCost;
        bundleNet += selectedNetAfter;
      }

      if (safe && bundleNet >= bundleCost) {
        allowed.addAll(allocationsByLine.keys);
      }
    }

    return Set.unmodifiable(allowed);
  }
}
