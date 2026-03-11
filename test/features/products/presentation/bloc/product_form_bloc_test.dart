import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/entities/product_variant_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/products/presentation/bloc/product_form_bloc.dart';

class MockProductRepository extends Mock implements ProductRepository {}

class MockProductVariantRepository extends Mock implements ProductVariantRepository {}

class FakeProduct extends Fake implements Product {}

class FakeDecimal extends Fake implements Decimal {}

class FakeProductVariant extends Fake implements ProductVariant {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeProduct());
    registerFallbackValue(FakeDecimal());
    registerFallbackValue(FakeProductVariant());
  });

  group('ProductFormBloc', () {
    late MockProductRepository repository;
    late MockProductVariantRepository variantRepository;
    late ProductFormBloc bloc;

    setUp(() {
      repository = MockProductRepository();
      variantRepository = MockProductVariantRepository();
      
      // Default stubs for variant repository
      when(() => variantRepository.getDefaultVariantByProduct(any()))
          .thenAnswer((_) async => null);
      when(() => variantRepository.ensureDefaultVariantForProduct(
            productId: any(named: 'productId'),
            costCents: any(named: 'costCents'),
            priceCents: any(named: 'priceCents'),
            stockQuantity: any(named: 'stockQuantity'),
          )).thenAnswer((_) async => 1);
      when(() => variantRepository.updateVariant(any()))
          .thenAnswer((_) async => true);
      
      bloc = ProductFormBloc(repository, variantRepository);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is ProductFormState.initial', () {
      expect(bloc.state, equals(ProductFormState()));
    });

    group('ProductFormInitialized', () {
      test('sets isEditing to false when productId is null', () async {
        bloc.add(const ProductFormInitialized(productId: null));
        await expectLater(
          bloc.stream,
          emits(isA<ProductFormState>().having((s) => s.isEditing, 'isEditing', false)),
        );
      });

      test('loads product when productId is provided', () async {
        final product = Product(
          id: 1,
          name: 'Test Product',
          costCents: Decimal.fromInt(1000),
          priceCents: Decimal.fromInt(2000),
          stockQuantity: 10,
          minQuantity: 5,
          hasVariants: false,
          isTaxable: false,
          purchaseTaxRateBps: 0,
          salesTaxRateBps: 0,
          isActive: true,
          trackInventory: true,
        );

        when(() => repository.watchProduct(1))
            .thenAnswer((_) => Stream.value(product));
        
        // Stub getDefaultVariantByProduct for non-variant product
        when(() => variantRepository.getDefaultVariantByProduct(1))
            .thenAnswer((_) async => ProductVariant(
              id: 1,
              productId: 1,
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(2000),
              priceAdjustmentCents: Decimal.zero,
              stockQuantity: 10,
              isActive: true,
            ));

        bloc.add(const ProductFormInitialized(productId: 1));

        await expectLater(
          bloc.stream,
          emitsInOrder([
            isA<ProductFormState>()
                .having((s) => s.isLoading, 'isLoading', true)
                .having((s) => s.isEditing, 'isEditing', true),
            isA<ProductFormState>()
                .having((s) => s.isLoading, 'isLoading', false)
                .having((s) => s.name, 'name', 'Test Product')
                .having((s) => s.costCents, 'costCents', product.costCents)
                .having((s) => s.priceCents, 'priceCents', product.priceCents),
          ]),
        );
      });
    });

    group('ProductFormFieldChanged', () {
      test('updates name', () async {
        bloc.add(const ProductFormFieldChanged(field: 'name', value: 'New Name'));
        await expectLater(
          bloc.stream,
          emits(isA<ProductFormState>().having((s) => s.name, 'name', 'New Name')),
        );
      });

      test('updates costCents', () async {
        final cost = Decimal.fromInt(1500);
        bloc.add(ProductFormFieldChanged(field: 'costCents', value: cost));
        await expectLater(
          bloc.stream,
          emits(isA<ProductFormState>().having((s) => s.costCents, 'costCents', cost)),
        );
      });
    });

    group('ProductFormSubmitted', () {
      test('emits errors when form is invalid', () async {
        bloc.add(const ProductFormSubmitted());
        await expectLater(
          bloc.stream,
          emits(isA<ProductFormState>().having((s) => s.fieldErrors, 'fieldErrors', isNotEmpty)),
        );
      });

      test('creates product when form is valid and not editing', () async {
        bloc.add(const ProductFormFieldChanged(field: 'name', value: 'New Product'));
        bloc.add(ProductFormFieldChanged(field: 'costCents', value: Decimal.fromInt(100)));
        bloc.add(ProductFormFieldChanged(field: 'priceCents', value: Decimal.fromInt(200)));

        when(() => repository.createProduct(
              name: any(named: 'name'),
              costCents: any(named: 'costCents'),
              priceCents: any(named: 'priceCents'),
              stockQuantity: any(named: 'stockQuantity'),
              minQuantity: any(named: 'minQuantity'),
              hasVariants: any(named: 'hasVariants'),
              isTaxable: any(named: 'isTaxable'),
              purchaseTaxRateBps: any(named: 'purchaseTaxRateBps'),
              salesTaxRateBps: any(named: 'salesTaxRateBps'),
              isActive: any(named: 'isActive'),
              trackInventory: any(named: 'trackInventory'),
              nameAr: any(named: 'nameAr'),
              nameFr: any(named: 'nameFr'),
              description: any(named: 'description'),
              sku: any(named: 'sku'),
              barcode: any(named: 'barcode'),
              wholesalePriceCents: any(named: 'wholesalePriceCents'),
              categoryId: any(named: 'categoryId'),
              supplierId: any(named: 'supplierId'),
              currencyId: any(named: 'currencyId'),
              imagePath: any(named: 'imagePath'),
            )).thenAnswer((_) async => 1);

        // Skip the state emissions from field changes
        await Future<void>.delayed(Duration.zero); 
        
        bloc.add(const ProductFormSubmitted());

        await expectLater(
          bloc.stream,
          emitsInOrder([
            isA<ProductFormState>().having((s) => s.isSubmitting, 'isSubmitting', true),
            isA<ProductFormState>()
                .having((s) => s.isSubmitting, 'isSubmitting', false)
                .having((s) => s.isSuccess, 'isSuccess', true),
          ]),
        );

        verify(() => repository.createProduct(
              name: 'New Product',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              stockQuantity: 0,
              minQuantity: 0,
              hasVariants: false,
              isTaxable: false,
              purchaseTaxRateBps: 0,
              salesTaxRateBps: 0,
              isActive: true,
              trackInventory: true,
            )).called(1);
      });
    });
  });
}
