import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_business_models.dart';

void main() {
  test(
    'purchase request round-trip keeps scaled integers and batch metadata',
    () {
      final expiry = DateTime.utc(2027, 12, 31);
      final request = LanPurchaseRequest(
        idempotencyKey: 'purchase-contract-001',
        supplierId: 7,
        paymentMethod: 'mixed',
        paidAmountCents: 1234,
        overallDiscountType: 'percentage',
        overallDiscountValue: 250,
        lines: [
          LanPurchaseLineRequest(
            productId: 11,
            variantId: 19,
            quantity: 750,
            unitCostCents: 1299,
            discountType: 'fixed',
            discountValue: 25,
            expiryDate: expiry,
            manufacturerLotNumber: 'LOT-001',
            newSellPriceCents: 1550,
            newWholesalePriceCents: 1400,
          ),
        ],
        payments: const [
          LanCheckoutPaymentRequest(method: 'cash', amountCents: 1234),
        ],
      );

      final json = request.toJson();
      final decoded = LanPurchaseRequest.fromJson(json);

      expect(decoded.supplierId, 7);
      expect(decoded.paidAmountCents, 1234);
      expect(decoded.overallDiscountValue, 250);
      expect(decoded.lines.single.quantity, 750);
      expect(decoded.lines.single.unitCostCents, 1299);
      expect(decoded.lines.single.expiryDate, expiry);
      expect(decoded.lines.single.manufacturerLotNumber, 'LOT-001');
      expect(decoded.payments.single.amountCents, 1234);
      expect(json['paidAmountCents'], isA<int>());
      expect((json['lines'] as List).single['quantity'], isA<int>());
      expect((json['lines'] as List).single['unitCostCents'], isA<int>());
    },
  );

  for (final malformed in <Map<String, dynamic>>[
    {
      'idempotencyKey': 'purchase-contract-float-quantity',
      'supplierId': 7,
      'paymentMethod': 'credit',
      'lines': [
        {'productId': 11, 'quantity': 1.5, 'unitCostCents': 1200},
      ],
    },
    {
      'idempotencyKey': 'purchase-contract-float-money',
      'supplierId': 7,
      'paymentMethod': 'credit',
      'paidAmountCents': 10.5,
      'lines': [
        {'productId': 11, 'quantity': 1, 'unitCostCents': 1200},
      ],
    },
    {
      'idempotencyKey': 'purchase-contract-float-cost',
      'supplierId': 7,
      'paymentMethod': 'credit',
      'lines': [
        {'productId': 11, 'quantity': 1, 'unitCostCents': 1200.25},
      ],
    },
    {
      'idempotencyKey': 'purchase-contract-float-discount',
      'supplierId': 7,
      'paymentMethod': 'credit',
      'overallDiscountValue': 2.5,
      'lines': [
        {'productId': 11, 'quantity': 1, 'unitCostCents': 1200},
      ],
    },
    {
      'idempotencyKey': 'purchase-contract-float-payment',
      'supplierId': 7,
      'paymentMethod': 'mixed',
      'lines': [
        {'productId': 11, 'quantity': 1, 'unitCostCents': 1200},
      ],
      'payments': [
        {'method': 'cash', 'amountCents': 1.25},
      ],
    },
  ]) {
    test(
      'purchase request rejects floating payload ${malformed['idempotencyKey']}',
      () {
        expect(
          () => LanPurchaseRequest.fromJson(malformed),
          throwsA(isA<FormatException>()),
        );
      },
    );
  }
}
