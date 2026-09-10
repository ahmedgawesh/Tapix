import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/money/money.dart';
import 'package:tapix/core/promotions/promotion_engine.dart';
import 'package:tapix/core/promotions/promotion_margin_policy.dart';

void main() {
  const rule = PromotionRule(
    id: 1,
    code: 'BUY1-GET1',
    name: 'Buy one get one free',
    type: PromotionType.buyXGetY,
    qualifierScopes: [PromotionScope.category(7)],
    minimumQuantity: 1,
    rewardType: PromotionRewardType.freeQuantity,
    rewardQuantity: 1,
    rewardUsesQualifierPool: true,
  );

  PromotionEvaluationResult evaluation() => PromotionEngine.evaluate(
    cart: PromotionCart(
      currencyId: 1,
      evaluatedAt: DateTime(2026, 9, 3),
      lines: [
        PromotionCartLine(
          lineId: 'paid',
          productId: 1,
          categoryId: 7,
          quantity: 1,
          unitPrice: Money.fromCents(15000),
        ),
        PromotionCartLine(
          lineId: 'gift',
          productId: 2,
          categoryId: 7,
          quantity: 1,
          unitPrice: Money.fromCents(3000),
        ),
      ],
    ),
    promotions: const [rule],
  );

  test('allows a free gift when paid margin covers the whole bundle cost', () {
    final result = evaluation();

    expect(result.totalDiscount.cents, 3000);
    expect(result.discountByLine.keys, containsAll(['paid', 'gift']));
    final allowed = PromotionMarginPolicy.profitableFreeBundleLineIds(
      evaluation: result,
      lines: [
        PromotionMarginLine(
          lineId: 'paid',
          quantity: 1,
          quantityScale: 1,
          unitCost: Money.fromCents(12000),
          netBeforePromotions: Money.fromCents(15000),
        ),
        PromotionMarginLine(
          lineId: 'gift',
          quantity: 1,
          quantityScale: 1,
          unitCost: Money.fromCents(3000),
          netBeforePromotions: Money.fromCents(3000),
        ),
      ],
    );

    expect(allowed, {'paid', 'gift'});
  });

  test('rejects a free gift when the complete bundle is below cost', () {
    final allowed = PromotionMarginPolicy.profitableFreeBundleLineIds(
      evaluation: evaluation(),
      lines: [
        PromotionMarginLine(
          lineId: 'paid',
          quantity: 1,
          quantityScale: 1,
          unitCost: Money.fromCents(12500),
          netBeforePromotions: Money.fromCents(15000),
        ),
        PromotionMarginLine(
          lineId: 'gift',
          quantity: 1,
          quantityScale: 1,
          unitCost: Money.fromCents(3000),
          netBeforePromotions: Money.fromCents(3000),
        ),
      ],
    );

    expect(allowed, isEmpty);
  });

  test('manual pricing below cost never receives the bundle exemption', () {
    final allowed = PromotionMarginPolicy.profitableFreeBundleLineIds(
      evaluation: evaluation(),
      lines: [
        PromotionMarginLine(
          lineId: 'paid',
          quantity: 1,
          quantityScale: 1,
          unitCost: Money.fromCents(12000),
          netBeforePromotions: Money.fromCents(11000),
        ),
        PromotionMarginLine(
          lineId: 'gift',
          quantity: 1,
          quantityScale: 1,
          unitCost: Money.fromCents(3000),
          netBeforePromotions: Money.fromCents(3000),
        ),
      ],
    );

    expect(allowed, isEmpty);
  });
}
