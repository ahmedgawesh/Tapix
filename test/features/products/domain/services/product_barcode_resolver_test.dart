import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/entities/product_variant_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/products/domain/services/product_barcode_resolver.dart';

class _MockProductRepository extends Mock implements ProductRepository {}

class _MockVariantRepository extends Mock implements ProductVariantRepository {}

void main() {
  late _MockProductRepository products;
  late _MockVariantRepository variants;
  late ProductBarcodeResolver resolver;

  Product product({
    required int id,
    required bool hasVariants,
    bool isActive = true,
  }) => Product(
    id: id,
    name: 'Product $id',
    barcode: 'P$id',
    costCents: Decimal.fromInt(100),
    priceCents: Decimal.fromInt(150),
    stockQuantity: 10,
    minQuantity: 0,
    hasVariants: hasVariants,
    isTaxable: false,
    purchaseTaxRateBps: 0,
    salesTaxRateBps: 0,
    isActive: isActive,
    trackInventory: true,
  );

  ProductVariant variant({
    required int id,
    required int productId,
    int? sizeId,
  }) => ProductVariant(
    id: id,
    productId: productId,
    barcode: 'V$id',
    sizeId: sizeId,
    costCents: Decimal.fromInt(100),
    priceCents: Decimal.fromInt(150),
    priceAdjustmentCents: Decimal.zero,
    stockQuantity: 10,
    isActive: true,
  );

  setUp(() {
    products = _MockProductRepository();
    variants = _MockVariantRepository();
    resolver = ProductBarcodeResolver(
      productRepository: products,
      variantRepository: variants,
    );
  });

  test('variant barcode resolves the exact active variant', () async {
    final parent = product(id: 1, hasVariants: true);
    final child = variant(id: 11, productId: 1, sizeId: 101);
    when(() => products.findByBarcode('V11')).thenAnswer((_) async => null);
    when(
      () => variants.getVariantByBarcode('V11'),
    ).thenAnswer((_) async => child);
    when(() => products.getProductById(1)).thenAnswer((_) async => parent);

    final result = await resolver.resolve(' V11 ');

    expect(result.type, ProductBarcodeResolutionType.variant);
    expect(result.product, parent);
    expect(result.variant, child);
  });

  test('variant parent barcode requires explicit variant selection', () async {
    final parent = product(id: 2, hasVariants: true);
    when(() => products.findByBarcode('P2')).thenAnswer((_) async => parent);
    when(
      () => variants.getVariantByBarcode('P2'),
    ).thenAnswer((_) async => null);

    final result = await resolver.resolve('P2');

    expect(result.type, ProductBarcodeResolutionType.variantParent);
    expect(result.product, parent);
    expect(result.variant, isNull);
    verifyNever(() => products.getProductById(any()));
  });

  test('simple product barcode resolves without a variant picker', () async {
    final simple = product(id: 3, hasVariants: false);
    when(() => products.findByBarcode('P3')).thenAnswer((_) async => simple);
    when(
      () => variants.getVariantByBarcode('P3'),
    ).thenAnswer((_) async => null);

    final result = await resolver.resolve('P3');

    expect(result.type, ProductBarcodeResolutionType.simpleProduct);
    expect(result.product, simple);
  });

  test('same-product default variant duplicate is resolved safely', () async {
    final simple = product(id: 4, hasVariants: false);
    final defaultVariant = variant(id: 41, productId: 4);
    when(() => products.findByBarcode('P4')).thenAnswer((_) async => simple);
    when(
      () => variants.getVariantByBarcode('P4'),
    ).thenAnswer((_) async => defaultVariant);

    final result = await resolver.resolve('P4');

    expect(result.type, ProductBarcodeResolutionType.variant);
    expect(result.product, simple);
    expect(result.variant, defaultVariant);
  });

  test(
    'legacy dimensionless default on variant product opens the picker',
    () async {
      final parent = product(id: 8, hasVariants: true);
      final legacyDefault = variant(id: 81, productId: 8);
      when(() => products.findByBarcode('P8')).thenAnswer((_) async => parent);
      when(
        () => variants.getVariantByBarcode('P8'),
      ).thenAnswer((_) async => legacyDefault);

      final result = await resolver.resolve('P8');

      expect(result.type, ProductBarcodeResolutionType.variantParent);
      expect(result.product, parent);
      expect(result.variant, isNull);
    },
  );

  test('cross-product barcode collision is rejected as ambiguous', () async {
    final direct = product(id: 5, hasVariants: false);
    final otherChild = variant(id: 61, productId: 6);
    when(() => products.findByBarcode('DUP')).thenAnswer((_) async => direct);
    when(
      () => variants.getVariantByBarcode('DUP'),
    ).thenAnswer((_) async => otherChild);

    final result = await resolver.resolve('DUP');

    expect(result.type, ProductBarcodeResolutionType.ambiguous);
    verifyNever(() => products.getProductById(any()));
  });

  test(
    'inactive parent cannot be sold through an active orphan barcode',
    () async {
      final inactiveParent = product(id: 7, hasVariants: true, isActive: false);
      final child = variant(id: 71, productId: 7);
      when(() => products.findByBarcode('V71')).thenAnswer((_) async => null);
      when(
        () => variants.getVariantByBarcode('V71'),
      ).thenAnswer((_) async => child);
      when(
        () => products.getProductById(7),
      ).thenAnswer((_) async => inactiveParent);

      final result = await resolver.resolve('V71');

      expect(result.type, ProductBarcodeResolutionType.notFound);
    },
  );
}
