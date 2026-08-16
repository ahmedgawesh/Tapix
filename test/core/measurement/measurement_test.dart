import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/measurement/measurement.dart';
import 'package:tapix/core/money/money.dart';
import 'package:tapix/core/pricing/discount.dart';
import 'package:tapix/core/pricing/line_item_pricing_engine.dart';
import 'package:tapix/core/services/return_calculation_service.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';

void main() {
  group('MeasuredQuantity', () {
    test('converts major and minor units to one exact storage scale', () {
      expect(
        MeasuredQuantity.parseToStored('1.25', MeasurementUnit.kilogram),
        1250,
      );
      expect(MeasuredQuantity.parseToStored('250', MeasurementUnit.gram), 250);
      expect(
        MeasuredQuantity.parseToStored('2.5', MeasurementUnit.meter),
        2500,
      );
      expect(
        MeasuredQuantity.parseToStored('50', MeasurementUnit.centimeter),
        500,
      );
      expect(
        MeasuredQuantity.parseToStored('0.75', MeasurementUnit.liter),
        750,
      );
      expect(
        MeasuredQuantity.parseToStored('750', MeasurementUnit.milliliter),
        750,
      );
    });

    test('rejects precision that cannot be represented exactly', () {
      expect(
        () => MeasuredQuantity.parseToStored('0.1', MeasurementUnit.gram),
        throwsFormatException,
      );
    });

    test(
      'formats stored stock in its major unit instead of exposing raw scale',
      () {
        expect(
          MeasuredQuantity.majorValue(495400, MeasurementType.length),
          '495.4',
        );
        expect(
          MeasuredQuantity.majorValue(2500, MeasurementType.weight),
          '2.5',
        );
        expect(
          MeasuredQuantity.majorValue(750, MeasurementType.volume),
          '0.75',
        );
        expect(MeasuredQuantity.majorValue(12, MeasurementType.piece), '12');
      },
    );
  });

  group('measured accounting', () {
    test(
      'linked return recalculation keeps the source measurement snapshot',
      () {
        const result = ProportionalReturnResult(
          subtotalCents: 2500,
          discountCents: 100,
          taxCents: 0,
          refundCents: 2400,
        );

        for (final type in ['length', 'weight', 'volume']) {
          final sale =
              SaleReturnItemInput(
                saleItemId: 1,
                quantity: 250,
                subtotalCents: Decimal.zero,
                discountCents: Decimal.zero,
                taxCents: Decimal.zero,
                refundCents: Decimal.zero,
              ).withCalculatedAmounts(
                result,
                sourceQuantityScale: 1000,
                sourceMeasurementType: type,
              );
          final purchase =
              PurchaseReturnItemInput(
                purchaseItemId: 1,
                quantity: 250,
                subtotalCents: Decimal.zero,
                discountCents: Decimal.zero,
                taxCents: Decimal.zero,
                refundCents: Decimal.zero,
              ).withCalculatedAmounts(
                result,
                sourceQuantityScale: 1000,
                sourceMeasurementType: type,
              );

          expect(sale.quantityScale, 1000);
          expect(sale.measurementType, type);
          expect(sale.refundCents, Decimal.fromInt(2400));
          expect(purchase.quantityScale, 1000);
          expect(purchase.measurementType, type);
          expect(purchase.refundCents, Decimal.fromInt(2400));
        }
      },
    );

    test('250 grams uses one quarter of the per-kilogram price', () {
      final result = LineItemPricingEngine.compute(
        input: LineItemPricingInput(
          unitPrice: Money.fromCents(10000),
          quantity: 250,
          quantityScale: 1000,
          discount: Discount.percent(1000),
          isTaxable: true,
          productTaxRateBps: 1400,
        ),
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      expect(result.subtotal.cents, 2500);
      expect(result.discount.cents, 250);
      expect(result.net.cents, 2250);
      expect(result.tax.cents, 315);
      expect(result.total.cents, 2565);
    });

    test('inventory value rounds once to the nearest cent', () {
      expect(
        MeasuredAmount.cents(
          unitCents: 999,
          quantity: 500,
          quantityScale: 1000,
        ),
        500,
      );
      expect(
        MeasuredAmount.unitCentsFromTotal(
          totalCents: 250,
          quantity: 250,
          quantityScale: 1000,
        ),
        1000,
      );
    });
  });
}
