import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/sales/domain/services/sale_stock_source_reservation.dart';

void main() {
  const identitySource = SaleStockSourceRef(
    productId: 1,
    variantId: 11,
    supplierIdentityId: 7,
  );
  const sameIdentityOnAnotherProduct = SaleStockSourceRef(
    productId: 2,
    variantId: 22,
    supplierIdentityId: 7,
  );
  const consignmentSource = SaleStockSourceRef(
    productId: 1,
    variantId: 11,
    consignmentLayerId: 'layer-a',
  );

  test('reserves repeated supplier source selections across cart lines', () {
    const reservations = [
      SaleStockSourceReservation(
        lineId: 'a',
        source: identitySource,
        quantity: 2,
      ),
      SaleStockSourceReservation(
        lineId: 'b',
        source: sameIdentityOnAnotherProduct,
        quantity: 3,
      ),
      SaleStockSourceReservation(
        lineId: 'c',
        source: consignmentSource,
        quantity: 4,
      ),
    ];

    expect(
      SaleStockSourceReservationLedger.remainingQuantity(
        availableQuantity: 8,
        reservations: reservations,
        source: identitySource,
      ),
      3,
    );
    expect(
      SaleStockSourceReservationLedger.remainingQuantity(
        availableQuantity: 8,
        reservations: reservations,
        source: consignmentSource,
      ),
      4,
    );
  });

  test('excludes the edited line and includes pending bundle quantities', () {
    const reservations = [
      SaleStockSourceReservation(
        lineId: 'editing',
        source: identitySource,
        quantity: 2,
      ),
      SaleStockSourceReservation(
        lineId: 'other',
        source: identitySource,
        quantity: 1,
      ),
    ];

    expect(
      SaleStockSourceReservationLedger.remainingQuantity(
        availableQuantity: 6,
        reservations: reservations,
        source: identitySource,
        excludingLineId: 'editing',
        pendingQuantity: 2,
      ),
      3,
    );
  });

  test('keeps unverified inventory separated by operational variant', () {
    const first = SaleStockSourceRef(productId: 1, variantId: 10);
    const second = SaleStockSourceRef(productId: 1, variantId: 20);
    const reservations = [
      SaleStockSourceReservation(lineId: 'a', source: first, quantity: 3),
    ];

    expect(
      SaleStockSourceReservationLedger.reservedQuantity(reservations, first),
      3,
    );
    expect(
      SaleStockSourceReservationLedger.reservedQuantity(reservations, second),
      0,
    );
  });
}
