import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/money/money.dart';
import 'package:tapix/core/promotions/promotion_engine.dart';

PromotionCartLine _line({
  required String id,
  required int productId,
  int? variantId,
  int? categoryId,
  int quantity = 1,
  int scale = 1,
  int unitPriceCents = 10000,
  String measurementType = 'piece',
  int existingDiscountCents = 0,
}) => PromotionCartLine(
  lineId: id,
  productId: productId,
  variantId: variantId,
  categoryId: categoryId,
  quantity: quantity,
  quantityScale: scale,
  measurementType: measurementType,
  unitPrice: Money.fromCents(unitPriceCents),
  existingDiscount: Money.fromCents(existingDiscountCents),
);

PromotionCart _cart(List<PromotionCartLine> lines, {int currencyId = 1}) =>
    PromotionCart(
      currencyId: currencyId,
      evaluatedAt: DateTime(2026, 8, 31, 12),
      lines: lines,
    );

PromotionRule _percentRule({
  required int id,
  required String code,
  int percentBps = 1000,
  List<PromotionScope> scopes = const [],
  PromotionType type = PromotionType.simple,
  PromotionConcurrencyMode concurrency = PromotionConcurrencyMode.bestPrice,
  int priority = 0,
  int minimumQuantity = 0,
  int quantityScale = 1,
  String? measurementType,
  bool allowManualDiscountCombination = false,
  int? maxApplicationsPerTransaction,
}) => PromotionRule(
  id: id,
  code: code,
  name: code,
  type: type,
  concurrencyMode: concurrency,
  priority: priority,
  qualifierScopes: scopes,
  rewardScopes: scopes,
  minimumQuantity: minimumQuantity,
  quantityScale: quantityScale,
  measurementType: measurementType,
  rewardType: PromotionRewardType.percentageOff,
  percentBps: percentBps,
  allowManualDiscountCombination: allowManualDiscountCombination,
  maxApplicationsPerTransaction: maxApplicationsPerTransaction,
);

void main() {
  test('LAN transport round-trip preserves financial rule semantics', () {
    const original = PromotionRule(
      id: 7,
      code: 'WHOLESALE-5',
      version: 2,
      name: 'Wholesale five',
      type: PromotionType.quantity,
      priceMode: 'wholesale',
      qualifierScopes: [
        PromotionScope.category(4, requiredQuantity: 3, quantityScale: 1),
      ],
      rewardScopes: [PromotionScope.product(9)],
      minimumQuantity: 3,
      rewardType: PromotionRewardType.percentageOff,
      percentBps: 500,
      allowManualDiscountCombination: true,
    );

    final restored = PromotionRule.fromTransportMap(original.toTransportMap());
    expect(restored.validate(), isEmpty);
    expect(restored.priceMode, 'wholesale');
    expect(restored.minimumQuantity, 3);
    expect(restored.percentBps, 500);
    expect(restored.qualifierScopes.single.type, PromotionScopeType.category);
    expect(restored.qualifierScopes.single.requiredQuantity, 3);
    expect(restored.qualifierScopes.single.quantityScale, 1);
    expect(restored.rewardScopes.single.targetId, 9);
  });

  group('PromotionEngine qualification and rewards', () {
    test('simple percentage applies only to matching products', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(id: 'a', productId: 1),
          _line(id: 'b', productId: 2),
        ]),
        promotions: [
          _percentRule(
            id: 1,
            code: 'P1-10',
            scopes: const [PromotionScope.product(1)],
          ),
        ],
      );

      expect(result.totalDiscount.cents, 1000);
      expect(result.discountByLine['a']?.cents, 1000);
      expect(result.discountByLine['b'], isNull);
    });

    test('variant scope never broadens to sibling variants', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(id: 'red-small', productId: 1, variantId: 11),
          _line(id: 'blue-large', productId: 1, variantId: 12),
        ]),
        promotions: [
          _percentRule(
            id: 1,
            code: 'RED-SMALL-10',
            scopes: const [PromotionScope.variant(11)],
          ),
        ],
      );

      expect(result.totalDiscount.cents, 1000);
      expect(result.discountByLine['red-small']?.cents, 1000);
      expect(result.discountByLine['blue-large'], isNull);
    });

    test('direct and threshold offers retain measured variant eligibility', () {
      final line = _line(
        id: 'measured-variant',
        productId: 1,
        variantId: 11,
        quantity: 1000,
        scale: 1000,
        measurementType: 'length',
        unitPriceCents: 2000,
      );
      final direct = PromotionEngine.evaluate(
        cart: _cart([line]),
        promotions: [
          _percentRule(
            id: 1,
            code: 'DIRECT-VARIANT',
            scopes: const [PromotionScope.variant(11)],
          ),
        ],
      );
      final threshold = PromotionEngine.evaluate(
        cart: _cart([line]),
        promotions: [
          PromotionRule(
            id: 2,
            code: 'THRESHOLD-VARIANT',
            name: 'Threshold variant',
            type: PromotionType.threshold,
            qualifierScopes: const [PromotionScope.variant(11)],
            rewardScopes: const [PromotionScope.variant(11)],
            minimumSpend: Money.fromCents(1500),
            rewardType: PromotionRewardType.percentageOff,
            percentBps: 1000,
          ),
        ],
      );

      expect(direct.totalDiscount.cents, 200);
      expect(threshold.totalDiscount.cents, 200);
    });

    test(
      'generic quantity offer counts measured variants in selling units',
      () {
        final result = PromotionEngine.evaluate(
          cart: _cart([
            _line(
              id: 'black-metre',
              productId: 1,
              variantId: 11,
              quantity: 1000,
              scale: 1000,
              measurementType: 'length',
              unitPriceCents: 2000,
            ),
            _line(
              id: 'brown-metre',
              productId: 1,
              variantId: 12,
              quantity: 1000,
              scale: 1000,
              measurementType: 'length',
              unitPriceCents: 2500,
            ),
          ]),
          promotions: [
            _percentRule(
              id: 1,
              code: 'TWO-VARIANTS-10',
              type: PromotionType.quantity,
              scopes: const [
                PromotionScope.variant(11),
                PromotionScope.variant(12),
              ],
              minimumQuantity: 2,
            ),
          ],
        );

        expect(result.applications.single.applicationCount, 1);
        expect(result.totalDiscount.cents, 450);
        expect(
          result.discountByLine.keys,
          containsAll(['black-metre', 'brown-metre']),
        );
      },
    );

    test('measured variant fractions combine without rounding', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(
            id: 'one-and-half',
            productId: 1,
            variantId: 11,
            quantity: 1500,
            scale: 1000,
            measurementType: 'length',
            unitPriceCents: 2000,
          ),
          _line(
            id: 'half',
            productId: 1,
            variantId: 12,
            quantity: 500,
            scale: 1000,
            measurementType: 'length',
            unitPriceCents: 3000,
          ),
        ]),
        promotions: [
          _percentRule(
            id: 1,
            code: 'TWO-METRES-10',
            type: PromotionType.quantity,
            scopes: const [PromotionScope.product(1)],
            minimumQuantity: 2,
          ),
        ],
      );

      expect(result.applications.single.applicationCount, 1);
      expect(result.totalDiscount.cents, 450);
    });

    test(
      'fixed bundle supports measured variants with generic UI quantities',
      () {
        final result = PromotionEngine.evaluate(
          cart: _cart([
            _line(
              id: 'black',
              productId: 1,
              variantId: 11,
              quantity: 1000,
              scale: 1000,
              measurementType: 'length',
              unitPriceCents: 2000,
            ),
            _line(
              id: 'brown',
              productId: 1,
              variantId: 12,
              quantity: 1000,
              scale: 1000,
              measurementType: 'length',
              unitPriceCents: 2500,
            ),
          ]),
          promotions: [
            PromotionRule(
              id: 1,
              code: 'TWO-METRES-FOR-30',
              name: 'Two metres for 30',
              type: PromotionType.fixedBundle,
              qualifierScopes: const [PromotionScope.product(1)],
              minimumQuantity: 2,
              rewardType: PromotionRewardType.fixedBundlePrice,
              fixedBundlePrice: Money.fromCents(3000),
            ),
          ],
        );

        expect(result.applications.single.applicationCount, 1);
        expect(result.totalDiscount.cents, 1500);
        expect(result.discountByLine.keys, containsAll(['black', 'brown']));
      },
    );

    test('buy X get Y chooses a measured variant using its selling unit', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(
            id: 'expensive',
            productId: 1,
            variantId: 11,
            quantity: 1000,
            scale: 1000,
            measurementType: 'length',
            unitPriceCents: 3000,
          ),
          _line(
            id: 'middle',
            productId: 1,
            variantId: 12,
            quantity: 1000,
            scale: 1000,
            measurementType: 'length',
            unitPriceCents: 2000,
          ),
          _line(
            id: 'cheapest',
            productId: 1,
            variantId: 13,
            quantity: 1000,
            scale: 1000,
            measurementType: 'length',
            unitPriceCents: 1000,
          ),
        ]),
        promotions: [
          const PromotionRule(
            id: 1,
            code: 'BUY2-GET1-METRE',
            name: 'Buy two metres get one',
            type: PromotionType.buyXGetY,
            qualifierScopes: [PromotionScope.product(1)],
            minimumQuantity: 2,
            rewardType: PromotionRewardType.freeQuantity,
            rewardQuantity: 1,
            rewardUsesQualifierPool: true,
          ),
        ],
      );

      expect(result.applications.single.applicationCount, 1);
      expect(result.totalDiscount.cents, 1000);
      expect(
        result.discountByLine.keys,
        containsAll(<String>['cheapest', 'middle', 'expensive']),
      );
      expect(result.discountByLine.length, 3);
    });

    test(
      'composed bundle requires every component and supports mixed scales',
      () {
        const rule = PromotionRule(
          id: 1,
          code: 'THREE-ITEM-BUNDLE-10',
          name: 'Three item bundle',
          type: PromotionType.quantity,
          qualifierScopes: [
            PromotionScope.product(1, requiredQuantity: 1, quantityScale: 1),
            PromotionScope.product(
              2,
              requiredQuantity: 1000,
              quantityScale: 1000,
            ),
            PromotionScope.variant(31, requiredQuantity: 1, quantityScale: 1),
          ],
          rewardScopes: [
            PromotionScope.product(1, requiredQuantity: 1, quantityScale: 1),
            PromotionScope.product(
              2,
              requiredQuantity: 1000,
              quantityScale: 1000,
            ),
            PromotionScope.variant(31, requiredQuantity: 1, quantityScale: 1),
          ],
          minimumQuantity: 3,
          rewardType: PromotionRewardType.percentageOff,
          percentBps: 1000,
        );
        final complete = PromotionEngine.evaluate(
          cart: _cart([
            _line(id: 'medicine', productId: 1, unitPriceCents: 13000),
            _line(
              id: 'fabric',
              productId: 2,
              quantity: 1000,
              scale: 1000,
              measurementType: 'length',
              unitPriceCents: 2000,
            ),
            _line(
              id: 'dress',
              productId: 3,
              variantId: 31,
              unitPriceCents: 95000,
            ),
          ]),
          promotions: const [rule],
        );
        final incomplete = PromotionEngine.evaluate(
          cart: _cart([
            _line(id: 'medicine', productId: 1, unitPriceCents: 13000),
            _line(
              id: 'fabric',
              productId: 2,
              quantity: 1000,
              scale: 1000,
              measurementType: 'length',
              unitPriceCents: 2000,
            ),
          ]),
          promotions: const [rule],
        );

        expect(complete.totalDiscount.cents, 11000);
        expect(
          complete.discountByLine.keys,
          containsAll(['medicine', 'fabric', 'dress']),
        );
        expect(incomplete.applications, isEmpty);
      },
    );

    test('fixed bundle prices the highest-value complete group only', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(
            id: 'premium',
            productId: 1,
            categoryId: 9,
            quantity: 2,
            unitPriceCents: 4000,
          ),
          _line(
            id: 'regular',
            productId: 2,
            categoryId: 9,
            quantity: 2,
            unitPriceCents: 3000,
          ),
        ]),
        promotions: [
          PromotionRule(
            id: 1,
            code: 'ANY3-100',
            name: 'Any 3 for 100',
            type: PromotionType.fixedBundle,
            qualifierScopes: const [PromotionScope.category(9)],
            minimumQuantity: 3,
            rewardType: PromotionRewardType.fixedBundlePrice,
            fixedBundlePrice: Money.fromCents(10000),
          ),
        ],
      );

      expect(result.applications.single.applicationCount, 1);
      expect(result.totalDiscount.cents, 1000);
      expect(result.discountByLine.keys, containsAll(['premium', 'regular']));
    });

    test('measured quantity uses its explicit 1000 scale', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(
            id: 'fabric',
            productId: 1,
            quantity: 3500,
            scale: 1000,
            unitPriceCents: 2000,
            measurementType: 'length',
          ),
        ]),
        promotions: [
          _percentRule(
            id: 1,
            code: '3M-10',
            type: PromotionType.quantity,
            scopes: const [PromotionScope.product(1)],
            minimumQuantity: 3000,
            quantityScale: 1000,
            measurementType: 'length',
          ),
        ],
      );

      expect(result.totalDiscount.cents, 700);
      expect(result.applications.single.applicationCount, 1);
    });

    test('a quantity offer never guesses across incompatible scales', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(
            id: 'fabric',
            productId: 1,
            quantity: 3500,
            scale: 1000,
            unitPriceCents: 2000,
            measurementType: 'length',
          ),
        ]),
        promotions: [
          _percentRule(
            id: 1,
            code: 'WRONG-SCALE',
            type: PromotionType.quantity,
            scopes: const [PromotionScope.product(1)],
            minimumQuantity: 3,
            quantityScale: 1,
            measurementType: 'length',
          ),
        ],
      );

      expect(result.applications, isEmpty);
    });

    test('quantity application cap discounts only the capped groups', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(
            id: 'six-pieces',
            productId: 1,
            quantity: 6,
            unitPriceCents: 1000,
          ),
        ]),
        promotions: [
          _percentRule(
            id: 1,
            code: 'THREE-ONLY-10',
            type: PromotionType.quantity,
            scopes: const [PromotionScope.product(1)],
            minimumQuantity: 3,
            percentBps: 1000,
            maxApplicationsPerTransaction: 1,
          ),
        ],
      );

      expect(result.applications.single.applicationCount, 1);
      expect(result.applications.single.allocations.single.appliedQuantity, 3);
      expect(result.totalDiscount.cents, 300);
    });

    test('buy two get one free chooses the cheapest eligible unit', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(id: '50', productId: 1, categoryId: 4, unitPriceCents: 5000),
          _line(id: '30', productId: 2, categoryId: 4, unitPriceCents: 3000),
          _line(id: '20', productId: 3, categoryId: 4, unitPriceCents: 2000),
        ]),
        promotions: [
          const PromotionRule(
            id: 1,
            code: 'BOGO-2-1',
            name: 'Buy 2 get 1',
            type: PromotionType.buyXGetY,
            qualifierScopes: [PromotionScope.category(4)],
            minimumQuantity: 2,
            rewardType: PromotionRewardType.freeQuantity,
            rewardQuantity: 1,
            rewardUsesQualifierPool: true,
          ),
        ],
      );

      expect(result.totalDiscount.cents, 2000);
      expect(
        result.discountByLine.keys,
        containsAll(<String>['20', '30', '50']),
      );
      expect(result.discountByLine.length, 3);
    });

    test('buy two get one supports three units on the same cart line', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(
            id: 'same-sku',
            productId: 1,
            quantity: 3,
            unitPriceCents: 2000,
          ),
        ]),
        promotions: [
          const PromotionRule(
            id: 1,
            code: 'SAME-SKU-BOGO',
            name: 'Buy two get one of the same SKU',
            type: PromotionType.buyXGetY,
            qualifierScopes: [PromotionScope.product(1)],
            minimumQuantity: 2,
            rewardType: PromotionRewardType.freeQuantity,
            rewardQuantity: 1,
            rewardUsesQualifierPool: true,
          ),
        ],
      );

      expect(result.totalDiscount.cents, 2000);
      expect(result.applications.single.allocations, hasLength(1));
      expect(result.applications.single.allocations.single.appliedQuantity, 3);
    });

    test('threshold amount is allocated without losing a cent', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([
          _line(id: 'one', productId: 1, unitPriceCents: 3333),
          _line(id: 'two', productId: 2, unitPriceCents: 6667),
        ]),
        promotions: [
          PromotionRule(
            id: 1,
            code: 'SPEND100',
            name: 'Spend 100',
            type: PromotionType.threshold,
            minimumSpend: Money.fromCents(10000),
            rewardType: PromotionRewardType.amountOff,
            amountOff: Money.fromCents(1001),
          ),
        ],
      );

      expect(result.totalDiscount.cents, 1001);
      expect(
        result.discountByLine.values.fold<int>(
          0,
          (sum, amount) => sum + amount.cents,
        ),
        1001,
      );
    });

    test('manual discount blocks an offer unless combination is explicit', () {
      final line = _line(id: 'a', productId: 1, existingDiscountCents: 1000);
      final blocked = PromotionEngine.evaluate(
        cart: _cart([line]),
        promotions: [_percentRule(id: 1, code: 'BLOCKED')],
      );
      final allowed = PromotionEngine.evaluate(
        cart: _cart([line]),
        promotions: [
          _percentRule(
            id: 2,
            code: 'ALLOWED',
            allowManualDiscountCombination: true,
          ),
        ],
      );

      expect(blocked.applications, isEmpty);
      expect(allowed.totalDiscount.cents, 900);
    });
  });

  group('PromotionEngine conflict resolution', () {
    test(
      'best-price resolver finds the optimal non-overlapping combination',
      () {
        final lines = [
          _line(id: 'a', productId: 1, categoryId: 8, unitPriceCents: 5000),
          _line(id: 'b', productId: 2, categoryId: 8, unitPriceCents: 5000),
        ];
        final result = PromotionEngine.evaluate(
          cart: _cart(lines),
          promotions: [
            PromotionRule(
              id: 1,
              code: 'BUNDLE',
              name: 'Bundle',
              type: PromotionType.fixedBundle,
              qualifierScopes: const [PromotionScope.category(8)],
              minimumQuantity: 2,
              rewardType: PromotionRewardType.fixedBundlePrice,
              fixedBundlePrice: Money.fromCents(7000),
            ),
            PromotionRule(
              id: 2,
              code: 'A-20',
              name: 'A 20 off',
              type: PromotionType.simple,
              qualifierScopes: const [PromotionScope.product(1)],
              rewardScopes: const [PromotionScope.product(1)],
              rewardType: PromotionRewardType.amountOff,
              amountOff: Money.fromCents(2000),
            ),
            PromotionRule(
              id: 3,
              code: 'B-20',
              name: 'B 20 off',
              type: PromotionType.simple,
              qualifierScopes: const [PromotionScope.product(2)],
              rewardScopes: const [PromotionScope.product(2)],
              rewardType: PromotionRewardType.amountOff,
              amountOff: Money.fromCents(2000),
            ),
          ],
        );

        expect(result.totalDiscount.cents, 4000);
        expect(
          result.applications.map((a) => a.code),
          containsAll(['A-20', 'B-20']),
        );
        expect(
          result.applications.map((a) => a.code),
          isNot(contains('BUNDLE')),
        );
      },
    );

    test(
      'exclusive promotion blocks a stronger best-price offer on its lines',
      () {
        final result = PromotionEngine.evaluate(
          cart: _cart([_line(id: 'a', productId: 1)]),
          promotions: [
            _percentRule(
              id: 1,
              code: 'EXCLUSIVE-10',
              percentBps: 1000,
              concurrency: PromotionConcurrencyMode.exclusive,
            ),
            _percentRule(id: 2, code: 'BEST-20', percentBps: 2000),
          ],
        );

        expect(result.totalDiscount.cents, 1000);
        expect(result.applications.single.code, 'EXCLUSIVE-10');
      },
    );

    test('compound promotions stack but never make a line negative', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([_line(id: 'a', productId: 1)]),
        promotions: [
          _percentRule(id: 1, code: 'BEST-80', percentBps: 8000),
          _percentRule(
            id: 2,
            code: 'STACK-50',
            percentBps: 5000,
            concurrency: PromotionConcurrencyMode.compound,
          ),
        ],
      );

      expect(result.totalDiscount.cents, 10000);
      expect(result.discountByLine['a']?.cents, 10000);
    });
  });

  group('PromotionEngine validation and audit snapshot', () {
    test('invalid definitions are rejected without breaking valid offers', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([_line(id: 'a', productId: 1)]),
        promotions: [
          _percentRule(id: 1, code: 'INVALID', percentBps: 10001),
          _percentRule(id: 2, code: 'VALID'),
        ],
      );

      expect(result.rejectedPromotions, contains('INVALID'));
      expect(result.applications.single.code, 'VALID');
    });

    test('currency and recurring schedule are enforced', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([_line(id: 'a', productId: 1)]),
        promotions: [
          const PromotionRule(
            id: 1,
            code: 'OTHER-CURRENCY',
            name: 'Other currency',
            type: PromotionType.simple,
            currencyId: 2,
            rewardType: PromotionRewardType.percentageOff,
            percentBps: 1000,
          ),
          const PromotionRule(
            id: 2,
            code: 'EVENING',
            name: 'Evening only',
            type: PromotionType.simple,
            schedule: [
              PromotionScheduleWindow(startMinute: 18 * 60, endMinute: 23 * 60),
            ],
            rewardType: PromotionRewardType.percentageOff,
            percentBps: 1000,
          ),
        ],
      );

      expect(result.applications, isEmpty);
    });

    test('snapshot freezes engine version and exact line allocations', () {
      final result = PromotionEngine.evaluate(
        cart: _cart([_line(id: 'a', productId: 1)]),
        promotions: [_percentRule(id: 1, code: 'AUDIT')],
      );
      final snapshot = result.applications.single.toSnapshotMap();

      expect(snapshot['engineVersion'], PromotionEngineVersion.current);
      expect(snapshot['discountCents'], 1000);
      expect(snapshot['allocations'], isA<List<Map<String, Object>>>());
    });
  });
}
