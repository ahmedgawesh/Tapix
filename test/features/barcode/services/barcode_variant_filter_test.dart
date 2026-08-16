import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/barcode/services/barcode_variant_filter.dart';

void main() {
  test('anonymous default variant is not a barcode label target', () {
    expect(
      shouldIncludeBarcodeVariant(
        variantId: 1,
        isActive: true,
        hasDimensions: false,
        selectedVariantIds: const {},
      ),
      isFalse,
    );
  });

  test(
    'active dimensional variants are included when no restriction exists',
    () {
      expect(
        shouldIncludeBarcodeVariant(
          variantId: 10,
          isActive: true,
          hasDimensions: true,
          selectedVariantIds: const {},
        ),
        isTrue,
      );
    },
  );

  test('explicit selection excludes sibling variants', () {
    expect(
      shouldIncludeBarcodeVariant(
        variantId: 10,
        isActive: true,
        hasDimensions: true,
        selectedVariantIds: const {11},
      ),
      isFalse,
    );
    expect(
      shouldIncludeBarcodeVariant(
        variantId: 11,
        isActive: true,
        hasDimensions: true,
        selectedVariantIds: const {11},
      ),
      isTrue,
    );
  });

  test('inactive variants are never included', () {
    expect(
      shouldIncludeBarcodeVariant(
        variantId: 11,
        isActive: false,
        hasDimensions: true,
        selectedVariantIds: const {11},
      ),
      isFalse,
    );
  });
}
