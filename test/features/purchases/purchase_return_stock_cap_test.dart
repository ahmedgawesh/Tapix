import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/features/purchases/domain/entities/purchase_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_return_form_bloc.dart';

PurchaseItemEntity item({
  required int id,
  int quantity = 11,
  int? currentStock = 10,
  bool tracksInventory = true,
  int productId = 9,
  int? variantId = 11,
}) {
  return PurchaseItemEntity(
    id: id,
    purchaseId: 6,
    productId: productId,
    variantId: variantId,
    quantity: quantity,
    currentStockQuantity: currentStock,
    tracksInventory: tracksInventory,
    unitCostCents: Decimal.fromInt(45000),
    subtotalCents: Decimal.fromInt(quantity * 45000),
    taxCents: Decimal.zero,
    totalCents: Decimal.fromInt(quantity * 45000),
    createdAt: DateTime(2026, 6, 21),
  );
}

ReturnLineItem selected(PurchaseItemEntity original, int quantity) {
  return ReturnLineItem(
    originalItem: original,
    returnQuantity: quantity,
    subtotalCents: Decimal.zero,
    discountCents: Decimal.zero,
    taxCents: Decimal.zero,
    refundCents: Decimal.zero,
  );
}

void main() {
  test('caps invoice entitlement by current physical stock', () {
    final purchaseItem = item(id: 23, quantity: 11, currentStock: 10);
    final state = PurchaseReturnFormState();

    expect(state.maxReturnableQty(purchaseItem), 10);
  });

  test('keeps the lower invoice remainder after previous returns', () {
    final purchaseItem = item(id: 23, quantity: 11, currentStock: 10);
    final state = PurchaseReturnFormState(alreadyReturnedQty: const {23: 2});

    expect(state.maxReturnableQty(purchaseItem), 9);
  });

  test('reserves shared variant stock selected on another invoice line', () {
    final first = item(id: 23, currentStock: 10);
    final other = item(id: 24, currentStock: 10);
    final state = PurchaseReturnFormState(returnItems: [selected(other, 4)]);

    expect(state.maxReturnableQty(first), 6);
  });

  test(
    'non-inventory purchase lines remain capped only by invoice history',
    () {
      final service = item(
        id: 30,
        quantity: 11,
        currentStock: 0,
        tracksInventory: false,
      );

      expect(PurchaseReturnFormState().maxReturnableQty(service), 11);
    },
  );
}
