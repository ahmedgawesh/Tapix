import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/purchases/domain/entities/purchase_entity.dart';
import 'package:tapix/features/sales/domain/entities/sale_entity.dart';

void main() {
  final now = DateTime(2026, 8, 28);

  test('sale return line identity includes color, size, and variant SKU', () {
    final item = SaleItemEntity(
      id: 1,
      saleId: 1,
      productId: 10,
      productName: 'قماش ستان مضلع',
      variantId: 100,
      variantSku: 'st500-1',
      colorName: 'بني',
      sizeName: 'عرض 150 سم',
      quantity: 1000,
      measurementType: 'length',
      unitPriceCents: Decimal.fromInt(2000),
      subtotalCents: Decimal.fromInt(2000),
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      totalCents: Decimal.fromInt(2000),
      createdAt: now,
    );

    expect(
      item.returnDisplayName,
      'قماش ستان مضلع (بني / عرض 150 سم) • SKU: st500-1',
    );
  });

  test(
    'purchase return line identity includes color, size, and variant SKU',
    () {
      final item = PurchaseItemEntity(
        id: 1,
        purchaseId: 1,
        productId: 10,
        productName: 'قماش ستان مضلع',
        variantId: 100,
        variantSku: 'st500-1',
        colorName: 'بني',
        sizeName: 'عرض 150 سم',
        quantity: 1000,
        measurementType: 'length',
        unitCostCents: Decimal.fromInt(1200),
        subtotalCents: Decimal.fromInt(1200),
        taxCents: Decimal.zero,
        totalCents: Decimal.fromInt(1200),
        createdAt: now,
      );

      expect(
        item.returnDisplayName,
        'قماش ستان مضلع (بني / عرض 150 سم) • SKU: st500-1',
      );
    },
  );
}
