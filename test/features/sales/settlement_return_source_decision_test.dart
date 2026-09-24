import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_adj_return_form_bloc.dart';

void main() {
  AdjReturnLineItem item({
    bool trackInventory = true,
    AdjReturnConsignmentSource? consignment,
    AdjReturnSupplierIdentitySource? identity,
  }) => AdjReturnLineItem(
    productId: 1,
    variantId: 2,
    productName: 'Item',
    quantity: 1,
    unitPriceCents: 100,
    trackInventory: trackInventory,
    consignmentSource: consignment,
    supplierIdentitySource: identity,
  );

  test('tracked settlement return starts pending until source is decided', () {
    expect(item().sourceResolution, AdjReturnSourceResolution.pending);
  });

  test('non inventory item does not require an inventory source', () {
    expect(
      item(trackInventory: false).sourceResolution,
      AdjReturnSourceResolution.notApplicable,
    );
  });

  test('scanned supplier identity is an explicit verified decision', () {
    const identity = AdjReturnSupplierIdentitySource(
      identityId: 4,
      supplierId: 7,
      supplierName: 'Supplier',
      sourceSku: 'SRC-4',
    );
    expect(
      item(identity: identity).sourceResolution,
      AdjReturnSourceResolution.supplierIdentity,
    );
  });
}
