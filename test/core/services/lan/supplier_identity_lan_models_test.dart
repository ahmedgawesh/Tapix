import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_business_models.dart';

void main() {
  test('supplier identity survives LAN sale and adjustment-return JSON', () {
    const sale = LanSaleLineRequest(
      productId: 11,
      variantId: 12,
      supplierIdentityId: 13,
      quantity: 2,
    );
    final decodedSale = LanSaleLineRequest.fromJson(sale.toJson());
    expect(decodedSale.supplierIdentityId, 13);
    expect(decodedSale.productId, 11);
    expect(decodedSale.variantId, 12);

    const adjustment = LanSaleAdjustmentReturnLineRequest(
      productId: 11,
      variantId: 12,
      supplierIdentityId: 13,
      quantity: 1,
      unitPriceCents: 2500,
    );
    final decodedAdjustment = LanSaleAdjustmentReturnLineRequest.fromJson(
      adjustment.toJson(),
    );
    expect(decodedAdjustment.supplierIdentityId, 13);
    expect(decodedAdjustment.consignmentLayerId, isNull);
  });

  test('exact supplier source-code match survives catalog JSON', () {
    const product = LanCatalogProduct(
      id: 11,
      name: 'Shoe',
      priceCents: 2500,
      stockQuantity: 4,
      hasVariants: true,
      isTaxable: false,
      salesTaxRateBps: 0,
      trackInventory: true,
      measurementType: 'piece',
      quantityScale: 1,
      matchedSupplierIdentityId: 13,
      matchedCanonicalVariantId: 12,
      matchedSupplierSourceSku: 'SUP-SHOE-40',
      matchedSupplierName: 'Supplier A',
    );
    final decoded = LanCatalogProduct.fromJson(product.toJson());
    expect(decoded.matchedSupplierIdentityId, 13);
    expect(decoded.matchedCanonicalVariantId, 12);
    expect(decoded.matchedSupplierSourceSku, 'SUP-SHOE-40');
    expect(decoded.matchedSupplierName, 'Supplier A');
  });

  test('consignment source survives catalog and sale-line JSON', () {
    const product = LanCatalogProduct(
      id: 11,
      name: 'Shoe',
      priceCents: 2500,
      stockQuantity: 4,
      hasVariants: true,
      isTaxable: false,
      salesTaxRateBps: 0,
      trackInventory: true,
      measurementType: 'piece',
      quantityScale: 1,
      matchedCanonicalVariantId: 12,
      matchedSupplierName: 'Consignment supplier',
      matchedConsignmentLayerId: '11111111-1111-4111-8111-111111111111',
      matchedConsignmentSourceCode: 'C-11111111-1111-4111-8111-111111111111',
    );
    final decodedProduct = LanCatalogProduct.fromJson(product.toJson());
    expect(
      decodedProduct.matchedConsignmentLayerId,
      '11111111-1111-4111-8111-111111111111',
    );
    expect(
      decodedProduct.matchedConsignmentSourceCode,
      'C-11111111-1111-4111-8111-111111111111',
    );

    const line = LanSaleLineRequest(
      productId: 11,
      variantId: 12,
      consignmentLayerId: '11111111-1111-4111-8111-111111111111',
      quantity: 1,
    );
    final decodedLine = LanSaleLineRequest.fromJson(line.toJson());
    expect(
      decodedLine.consignmentLayerId,
      '11111111-1111-4111-8111-111111111111',
    );
    expect(decodedLine.supplierIdentityId, isNull);
  });

  test('stock-source snapshot survives LAN JSON without ownership loss', () {
    const snapshot = LanProductStockSourceSnapshot(
      productId: 11,
      warehouseId: 'main',
      physicalQuantity: 8,
      enterpriseQuantity: 5,
      consignmentQuantity: 3,
      quantityScale: 1,
      measurementType: 'piece',
      reconciled: true,
      sources: [
        LanInventoryStockSource(
          productId: 11,
          variantId: 12,
          quantity: 3,
          quantityScale: 1,
          measurementType: 'piece',
          ownership: 'consignment',
          variantLabel: 'Blue / 42',
          supplierId: 4,
          supplierName: 'Supplier A',
          consignmentLayerId: '11111111-1111-4111-8111-111111111111',
          sourceCode: 'C-11111111-1111-4111-8111-111111111111',
          receiptNumber: 'CR-22',
        ),
      ],
    );
    final decoded = LanProductStockSourceSnapshot.fromJson(snapshot.toJson());
    expect(decoded.reconciled, isTrue);
    expect(decoded.enterpriseQuantity, 5);
    expect(decoded.consignmentQuantity, 3);
    expect(decoded.sources.single.supplierName, 'Supplier A');
    expect(decoded.sources.single.isConsignment, isTrue);
    expect(decoded.sources.single.isVerified, isTrue);
  });

  test('legacy LAN JSON remains valid without supplier identity fields', () {
    final decoded = LanSaleLineRequest.fromJson({
      'productId': 11,
      'variantId': 12,
      'quantity': 1,
    });
    expect(decoded.supplierIdentityId, isNull);
  });
}
