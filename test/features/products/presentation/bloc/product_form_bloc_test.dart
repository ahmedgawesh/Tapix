import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/features/barcode/services/barcode_generation_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/entities/price_history_entity.dart';
import 'package:tapix/features/products/domain/entities/product_variant_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/products/presentation/bloc/product_form_bloc.dart';

/// Mock that runs `runInTransaction` inline so the bloc's orchestration code
/// executes during unit tests (no DB attached). We override rather than stub
/// because mocktail can't match the generic function parameter reliably.
class MockProductRepository extends Mock implements ProductRepository {
  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) => action();
}

class MockProductVariantRepository extends Mock
    implements ProductVariantRepository {}

class FakeProduct extends Fake implements Product {}

class FakeDecimal extends Fake implements Decimal {}

class FakeProductVariant extends Fake implements ProductVariant {}

class FakePriceHistory extends Fake implements PriceHistory {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeProduct());
    registerFallbackValue(FakeDecimal());
    registerFallbackValue(FakeProductVariant());
    registerFallbackValue(FakePriceHistory());
    // The bloc resolves a barcode generator from GetIt to auto-fill missing
    // barcodes during submission — register it once for all tests.
    if (!sl.isRegistered<BarcodeGenerationService>()) {
      sl.registerLazySingleton(() => BarcodeGenerationService());
    }
  });

  group('ProductFormBloc', () {
    late MockProductRepository repository;
    late MockProductVariantRepository variantRepository;
    late ProductFormBloc bloc;

    setUp(() {
      repository = MockProductRepository();
      variantRepository = MockProductVariantRepository();

      // Default stubs for variant repository
      when(
        () => variantRepository.getDefaultVariantByProduct(any()),
      ).thenAnswer((_) async => null);
      when(
        () => variantRepository.ensureDefaultVariantForProduct(
          productId: any(named: 'productId'),
          costCents: any(named: 'costCents'),
          priceCents: any(named: 'priceCents'),
          stockQuantity: any(named: 'stockQuantity'),
        ),
      ).thenAnswer((_) async => 1);
      when(
        () => variantRepository.updateVariant(any()),
      ).thenAnswer((_) async => true);

      // Default stub: cost-method lock probe is called from `_onInitialized`
      // for every existing product. Returning `null` keeps the segment
      // editable, matching the default for a freshly-created product.
      when(
        () => repository.getCostingMethodLockReason(any()),
      ).thenAnswer((_) async => null);
      when(
        () => repository.countProductReferences(any()),
      ).thenAnswer((_) async => 0);

      bloc = ProductFormBloc(repository, variantRepository);

      // Default stubs for uniqueness checks called during submission
      when(() => repository.findByName(any())).thenAnswer((_) async => null);
      when(() => repository.findByBarcode(any())).thenAnswer((_) async => null);
      when(() => repository.findBySku(any())).thenAnswer((_) async => null);
      when(
        () => variantRepository.getVariantByBarcode(any()),
      ).thenAnswer((_) async => null);
      when(
        () => variantRepository.getVariantBySku(any()),
      ).thenAnswer((_) async => null);
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
          emits(
            isA<ProductFormState>().having(
              (s) => s.isEditing,
              'isEditing',
              false,
            ),
          ),
        );
      });

      // Regression (May 2026): the product form silently hard-coded
      // `defaultMinQuantity: 0` after the inventory-tracking-types refactor,
      // which broke the long-standing UX where new products inherit the
      // global `lowStockThreshold` from settings as their initial re-order
      // point. The screen now forwards `settings.lowStockThreshold` to the
      // bloc; this test pins the bloc-side contract so any future regression
      // surfaces immediately.
      test(
        'new product inherits defaultMinQuantity and defaultTrackInventory from settings',
        () async {
          bloc.add(
            const ProductFormInitialized(
              productId: null,
              defaultTrackInventory: true,
              defaultMinQuantity: 7,
            ),
          );
          await expectLater(
            bloc.stream,
            emits(
              isA<ProductFormState>()
                  .having((s) => s.isEditing, 'isEditing', false)
                  .having((s) => s.minQuantity, 'minQuantity', 7)
                  .having((s) => s.trackInventory, 'trackInventory', true),
            ),
          );
        },
      );

      test(
        'new product can be initialized with tracking disabled by default',
        () async {
          bloc.add(
            const ProductFormInitialized(
              productId: null,
              defaultTrackInventory: false,
              defaultMinQuantity: 0,
            ),
          );
          await expectLater(
            bloc.stream,
            emits(
              isA<ProductFormState>()
                  .having((s) => s.trackInventory, 'trackInventory', false)
                  .having((s) => s.minQuantity, 'minQuantity', 0),
            ),
          );
        },
      );

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

        when(
          () => repository.watchProduct(1),
        ).thenAnswer((_) => Stream.value(product));

        // Stub getDefaultVariantByProduct for non-variant product
        when(() => variantRepository.getDefaultVariantByProduct(1)).thenAnswer(
          (_) async => ProductVariant(
            id: 1,
            productId: 1,
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
            priceAdjustmentCents: Decimal.zero,
            stockQuantity: 10,
            isActive: true,
          ),
        );

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
        bloc.add(
          const ProductFormFieldChanged(field: 'name', value: 'New Name'),
        );
        await expectLater(
          bloc.stream,
          emits(
            isA<ProductFormState>().having((s) => s.name, 'name', 'New Name'),
          ),
        );
      });

      test('updates costCents', () async {
        final cost = Decimal.fromInt(1500);
        bloc.add(ProductFormFieldChanged(field: 'costCents', value: cost));
        await expectLater(
          bloc.stream,
          emits(
            isA<ProductFormState>().having(
              (s) => s.costCents,
              'costCents',
              cost,
            ),
          ),
        );
      });
    });

    group('ProductFormSubmitted', () {
      test('emits errors when form is invalid', () async {
        bloc.add(const ProductFormSubmitted());
        await expectLater(
          bloc.stream,
          emits(
            isA<ProductFormState>().having(
              (s) => s.fieldErrors,
              'fieldErrors',
              isNotEmpty,
            ),
          ),
        );
      });

      test('creates product when form is valid and not editing', () async {
        bloc.add(
          const ProductFormFieldChanged(field: 'name', value: 'New Product'),
        );
        bloc.add(
          ProductFormFieldChanged(
            field: 'costCents',
            value: Decimal.fromInt(100),
          ),
        );
        bloc.add(
          ProductFormFieldChanged(
            field: 'priceCents',
            value: Decimal.fromInt(200),
          ),
        );

        when(
          () => repository.createProduct(
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
          ),
        ).thenAnswer((_) async => 1);

        // Skip the state emissions from field changes
        await Future<void>.delayed(Duration.zero);

        bloc.add(const ProductFormSubmitted());

        await expectLater(
          bloc.stream,
          emitsInOrder([
            // Intermediate states from validation + barcode generation
            emitsThrough(
              isA<ProductFormState>().having(
                (s) => s.isSubmitting,
                'isSubmitting',
                true,
              ),
            ),
            isA<ProductFormState>()
                .having((s) => s.isSubmitting, 'isSubmitting', false)
                .having((s) => s.isSuccess, 'isSuccess', true),
          ]),
        );

        verify(
          () => repository.createProduct(
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
            barcode: any(named: 'barcode'),
            nameAr: any(named: 'nameAr'),
            nameFr: any(named: 'nameFr'),
            description: any(named: 'description'),
            sku: any(named: 'sku'),
            wholesalePriceCents: any(named: 'wholesalePriceCents'),
            categoryId: any(named: 'categoryId'),
            supplierId: any(named: 'supplierId'),
            currencyId: any(named: 'currencyId'),
            imagePath: any(named: 'imagePath'),
          ),
        ).called(1);
      });

      /// Regression — first-save-loses-tracking-type bug.
      ///
      /// Repro before the fix:
      ///   1. User opens "create product" form.
      ///   2. Picks `batch_expiry` in the inventory-tracking segmented
      ///      control (`ProductFormFieldChanged` for `inventoryTrackingType`).
      ///   3. Saves. The bloc only forwarded `costingMethod` to the repo,
      ///      so the INSERT silently fell back to the DB default
      ///      (`'standard'`) for `inventory_tracking_type`. Re-opening the
      ///      product showed `'standard'` again — user had to re-select +
      ///      re-save (which then routed through `setInventoryTrackingType`
      ///      in the edit path and finally persisted).
      ///
      /// The fix threads `state.inventoryTrackingType` through
      /// `ProductRepository.createProduct` so the very first INSERT carries
      /// the user's choice. This test asserts that wiring for both `batch`
      /// and `batch_expiry`, and confirms the legacy `costingMethod` mirror
      /// stays in lockstep (`standard → wac`, otherwise `fifo`).
      test(
        'create path forwards inventoryTrackingType=batch_expiry + mirrors costingMethod=fifo',
        () async {
          bloc.add(const ProductFormFieldChanged(field: 'name', value: 'P1'));
          bloc.add(
            ProductFormFieldChanged(
              field: 'costCents',
              value: Decimal.fromInt(100),
            ),
          );
          bloc.add(
            ProductFormFieldChanged(
              field: 'priceCents',
              value: Decimal.fromInt(200),
            ),
          );
          bloc.add(
            const ProductFormFieldChanged(
              field: 'inventoryTrackingType',
              value: 'batch_expiry',
            ),
          );

          when(
            () => repository.createProduct(
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
              costingMethod: any(named: 'costingMethod'),
              inventoryTrackingType: any(named: 'inventoryTrackingType'),
            ),
          ).thenAnswer((_) async => 42);

          await Future<void>.delayed(Duration.zero);
          bloc.add(const ProductFormSubmitted());

          await expectLater(
            bloc.stream,
            emitsThrough(
              isA<ProductFormState>()
                  .having((s) => s.isSubmitting, 'isSubmitting', false)
                  .having((s) => s.isSuccess, 'isSuccess', true),
            ),
          );

          verify(
            () => repository.createProduct(
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
              costingMethod: 'fifo',
              inventoryTrackingType: 'batch_expiry',
            ),
          ).called(1);
        },
      );

      test(
        'create path forwards inventoryTrackingType=batch + mirrors costingMethod=fifo',
        () async {
          bloc.add(const ProductFormFieldChanged(field: 'name', value: 'P2'));
          bloc.add(
            ProductFormFieldChanged(
              field: 'costCents',
              value: Decimal.fromInt(100),
            ),
          );
          bloc.add(
            ProductFormFieldChanged(
              field: 'priceCents',
              value: Decimal.fromInt(200),
            ),
          );
          bloc.add(
            const ProductFormFieldChanged(
              field: 'inventoryTrackingType',
              value: 'batch',
            ),
          );

          when(
            () => repository.createProduct(
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
              costingMethod: any(named: 'costingMethod'),
              inventoryTrackingType: any(named: 'inventoryTrackingType'),
            ),
          ).thenAnswer((_) async => 43);

          await Future<void>.delayed(Duration.zero);
          bloc.add(const ProductFormSubmitted());

          await expectLater(
            bloc.stream,
            emitsThrough(
              isA<ProductFormState>()
                  .having((s) => s.isSubmitting, 'isSubmitting', false)
                  .having((s) => s.isSuccess, 'isSuccess', true),
            ),
          );

          verify(
            () => repository.createProduct(
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
              costingMethod: 'fifo',
              inventoryTrackingType: 'batch',
            ),
          ).called(1);
        },
      );

      /// Variants-enabled products travel the same `createProduct` path
      /// (the column lives on `products`, not on variants), so the
      /// tracking type must be forwarded identically.
      test(
        'create path forwards inventoryTrackingType when hasVariants=true',
        () async {
          bloc.add(const ProductFormFieldChanged(field: 'name', value: 'PV'));
          bloc.add(
            ProductFormFieldChanged(
              field: 'costCents',
              value: Decimal.fromInt(100),
            ),
          );
          bloc.add(
            ProductFormFieldChanged(
              field: 'priceCents',
              value: Decimal.fromInt(200),
            ),
          );
          bloc.add(
            const ProductFormFieldChanged(field: 'hasVariants', value: true),
          );
          bloc.add(
            const ProductFormFieldChanged(
              field: 'inventoryTrackingType',
              value: 'batch_expiry',
            ),
          );

          when(
            () => repository.createProduct(
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
              costingMethod: any(named: 'costingMethod'),
              inventoryTrackingType: any(named: 'inventoryTrackingType'),
            ),
          ).thenAnswer((_) async => 44);

          await Future<void>.delayed(Duration.zero);
          bloc.add(const ProductFormSubmitted());

          await expectLater(
            bloc.stream,
            emitsThrough(
              isA<ProductFormState>()
                  .having((s) => s.isSubmitting, 'isSubmitting', false)
                  .having((s) => s.isSuccess, 'isSuccess', true),
            ),
          );

          verify(
            () => repository.createProduct(
              name: any(named: 'name'),
              costCents: any(named: 'costCents'),
              priceCents: any(named: 'priceCents'),
              stockQuantity: any(named: 'stockQuantity'),
              minQuantity: any(named: 'minQuantity'),
              hasVariants: true,
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
              costingMethod: 'fifo',
              inventoryTrackingType: 'batch_expiry',
            ),
          ).called(1);
        },
      );

      test(
        'editing refuses variants-to-simple transition when stock remains',
        () async {
          final product = Product(
            id: 77,
            name: 'Stocked variants',
            barcode: '2000000000078',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            stockQuantity: 5,
            minQuantity: 0,
            hasVariants: true,
            isTaxable: false,
            purchaseTaxRateBps: 0,
            salesTaxRateBps: 0,
            isActive: true,
            trackInventory: true,
          );
          when(
            () => repository.watchProduct(77),
          ).thenAnswer((_) => Stream.value(product));
          when(
            () => repository.getProductById(77),
          ).thenAnswer((_) async => product);
          when(
            () => repository.updateProduct(any()),
          ).thenAnswer((_) async => true);
          when(
            () => repository.createPriceHistory(any()),
          ).thenAnswer((_) async => 1);
          when(
            () => variantRepository.deactivateDimensionalVariants(77),
          ).thenThrow(const VariantStockConflictException(2));

          bloc.add(const ProductFormInitialized(productId: 77));
          await bloc.stream.firstWhere(
            (s) => !s.isLoading && s.productId == 77,
          );
          bloc.add(
            const ProductFormFieldChanged(field: 'hasVariants', value: false),
          );
          await bloc.stream.firstWhere((s) => !s.hasVariants);

          bloc.add(const ProductFormSubmitted());
          final rejected = await bloc.stream.firstWhere(
            (s) => s.error == 'variant_stock_conflict:2',
          );

          expect(rejected.isSubmitting, isFalse);
          expect(rejected.isSuccess, isFalse);
          expect(rejected.hasVariants, isTrue);
          verify(
            () => variantRepository.deactivateDimensionalVariants(77),
          ).called(1);
          verifyNever(
            () => variantRepository.ensureDefaultVariantForProduct(
              productId: any(named: 'productId'),
              costCents: any(named: 'costCents'),
              priceCents: any(named: 'priceCents'),
              stockQuantity: any(named: 'stockQuantity'),
            ),
          );
        },
      );
    });
  });
}
