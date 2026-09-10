import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/promotions/promotion_return_policy.dart';
import 'package:tapix/core/promotions/promotion_sale_snapshot.dart';

void main() {
  SalePromotionSnapshot application({
    int applicationCount = 1,
    String engineVersion = 'promotion-v4',
    List<SalePromotionLineSnapshot>? allocations,
  }) => SalePromotionSnapshot(
    applicationId: 10,
    promotionId: 20,
    code: 'BUY-X-GET-Y',
    name: 'Buy together',
    version: 1,
    type: 'buy_x_get_y',
    concurrencyMode: 'exclusive',
    applicationCount: applicationCount,
    discountCents: 3000,
    engineVersion: engineVersion,
    allocations:
        allocations ??
        const [
          SalePromotionLineSnapshot(
            saleItemId: 1,
            discountCents: 2500,
            appliedQuantity: 3,
            quantityScale: 1,
            originalUnitPriceCents: 5000,
            rewardType: 'free_quantity',
          ),
          SalePromotionLineSnapshot(
            saleItemId: 2,
            discountCents: 500,
            appliedQuantity: 1,
            quantityScale: 1,
            originalUnitPriceCents: 3000,
            rewardType: 'free_quantity',
          ),
        ],
  );

  group('PromotionReturnPolicy', () {
    test('blocks returning one line from a v4 free-item bundle', () {
      final violation = PromotionReturnPolicy.validateLinkedReturn(
        promotionApplications: [application()],
        previouslyReturnedQuantityBySaleItemId: const {},
        requestedQuantityBySaleItemId: const {1: 3},
      );

      expect(violation?.promotionId, 20);
    });

    test('allows returning every participant in a complete bundle', () {
      final violation = PromotionReturnPolicy.validateLinkedReturn(
        promotionApplications: [application()],
        previouslyReturnedQuantityBySaleItemId: const {},
        requestedQuantityBySaleItemId: const {1: 3, 2: 1},
      );

      expect(violation, isNull);
    });

    test('allows one complete repetition when an offer applied twice', () {
      final violation = PromotionReturnPolicy.validateLinkedReturn(
        promotionApplications: [
          application(
            applicationCount: 2,
            allocations: const [
              SalePromotionLineSnapshot(
                saleItemId: 1,
                discountCents: 5000,
                appliedQuantity: 6,
                quantityScale: 1,
                originalUnitPriceCents: 5000,
                rewardType: 'free_quantity',
              ),
              SalePromotionLineSnapshot(
                saleItemId: 2,
                discountCents: 1000,
                appliedQuantity: 2,
                quantityScale: 1,
                originalUnitPriceCents: 3000,
                rewardType: 'free_quantity',
              ),
            ],
          ),
        ],
        previouslyReturnedQuantityBySaleItemId: const {},
        requestedQuantityBySaleItemId: const {1: 3, 2: 1},
      );

      expect(violation, isNull);
    });

    test('uses cumulative linked returns for later complete repetitions', () {
      final violation = PromotionReturnPolicy.validateLinkedReturn(
        promotionApplications: [
          application(
            applicationCount: 2,
            allocations: const [
              SalePromotionLineSnapshot(
                saleItemId: 1,
                discountCents: 5000,
                appliedQuantity: 6,
                quantityScale: 1,
                originalUnitPriceCents: 5000,
                rewardType: 'free_quantity',
              ),
              SalePromotionLineSnapshot(
                saleItemId: 2,
                discountCents: 1000,
                appliedQuantity: 2,
                quantityScale: 1,
                originalUnitPriceCents: 3000,
                rewardType: 'free_quantity',
              ),
            ],
          ),
        ],
        previouslyReturnedQuantityBySaleItemId: const {1: 3, 2: 1},
        requestedQuantityBySaleItemId: const {1: 3, 2: 1},
      );

      expect(violation, isNull);
    });

    test('does not guess missing qualifier lines in legacy snapshots', () {
      final violation = PromotionReturnPolicy.validateLinkedReturn(
        promotionApplications: [application(engineVersion: 'promotion-v3')],
        previouslyReturnedQuantityBySaleItemId: const {},
        requestedQuantityBySaleItemId: const {1: 1},
      );

      expect(violation, isNull);
    });
  });
}
