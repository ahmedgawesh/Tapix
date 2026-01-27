import 'package:flutter_test/flutter_test.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/entities/product_variant_entity.dart';

void main() {
  group('VariantManagementWidget State Logic', () {
    test('RealtimeLoading state indicates loading', () {
      const state = RealtimeLoading<List<ProductVariant>>();
      expect(state, isA<RealtimeLoading<List<ProductVariant>>>());
    });

    test('RealtimeSuccess with empty list indicates no variants', () {
      final state = RealtimeSuccess<List<ProductVariant>>(data: []);
      expect(state.data, isEmpty);
    });

    test('RealtimeSuccess with variants contains variant data', () {
      final variants = [
        ProductVariant(
          id: 1,
          productId: 1,
          sku: 'VAR-1',
          stockQuantity: 10,
          costCents: Decimal.zero,
          priceCents: Decimal.zero,
          priceAdjustmentCents: Decimal.zero,
          isActive: true,
        ),
      ];

      final state = RealtimeSuccess<List<ProductVariant>>(data: variants);
      expect(state.data, hasLength(1));
      expect(state.data.first.sku, equals('VAR-1'));
      expect(state.data.first.stockQuantity, equals(10));
    });

    test('ProductVariant entity has correct properties', () {
      final variant = ProductVariant(
        id: 1,
        productId: 1,
        sku: 'TEST-SKU',
        barcode: '123456789',
        colorId: 1,
        sizeId: 2,
        costCents: Decimal.fromInt(1000),
        priceCents: Decimal.fromInt(2000),
        priceAdjustmentCents: Decimal.fromInt(500),
        stockQuantity: 50,
        isActive: true,
      );

      expect(variant.id, equals(1));
      expect(variant.productId, equals(1));
      expect(variant.sku, equals('TEST-SKU'));
      expect(variant.barcode, equals('123456789'));
      expect(variant.colorId, equals(1));
      expect(variant.sizeId, equals(2));
      expect(variant.costCents, equals(Decimal.fromInt(1000)));
      expect(variant.priceCents, equals(Decimal.fromInt(2000)));
      expect(variant.priceAdjustmentCents, equals(Decimal.fromInt(500)));
      expect(variant.stockQuantity, equals(50));
      expect(variant.isActive, isTrue);
    });
  });
}
