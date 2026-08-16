import 'package:bloc_test/bloc_test.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart' hide Product;
import 'package:tapix/core/database/daos/barcode_template_dao.dart';
import 'package:tapix/core/database/daos/product_variant_dao.dart';
import 'package:tapix/features/barcode/domain/models/barcode_design_state.dart';
import 'package:tapix/features/barcode/presentation/bloc/barcode_design_bloc.dart';
import 'package:tapix/features/barcode/presentation/bloc/barcode_design_event.dart';
import 'package:tapix/features/barcode/services/barcode_printer_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/settings/data/services/company_profile_service.dart';
import 'package:tapix/features/settings/domain/entities/company_profile.dart';
import 'package:decimal/decimal.dart';

@GenerateMocks([
  BarcodeTemplateDao,
  BarcodePrinterService,
  CompanyProfileService,
])
import 'barcode_design_bloc_test.mocks.dart';

class MockProductVariantDao extends Mock implements ProductVariantDao {
  final Map<int, String> productInfoById = <int, String>{};

  @override
  Future<Map<int, String>> getVariantInfoByProductIds(
    List<int> productIds,
  ) async {
    final requestedIds = productIds.toSet();
    return Map<int, String>.fromEntries(
      productInfoById.entries.where(
        (entry) => requestedIds.contains(entry.key),
      ),
    );
  }
}

void main() {
  late BarcodeDesignBloc bloc;
  late MockBarcodeTemplateDao mockTemplateDao;
  late MockBarcodePrinterService mockPrinterService;
  late MockCompanyProfileService mockCompanyProfileService;
  late MockProductVariantDao mockProductVariantDao;

  final testProduct = Product(
    id: 1,
    name: 'Test Product',
    barcode: '1234567890123',
    sku: 'TEST-001',
    costCents: Decimal.parse('1000'),
    priceCents: Decimal.parse('1500'),
    stockQuantity: 10,
    minQuantity: 2,
    hasVariants: false,
    isTaxable: false,
    purchaseTaxRateBps: 0,
    salesTaxRateBps: 0,
    isActive: true,
    trackInventory: true,
  );

  final testTemplate = BarcodeTemplate(
    id: 1,
    name: 'Test Template',
    description: 'Test description',
    layoutConfig: '{}',
    paperSize: '58mm',
    widthMm: 58.0,
    heightMm: 40.0,
    includeName: true,
    includePrice: true,
    includeSku: false,
    includeCompanyName: false,
    includeVariantInfo: false,
    barcodeType: 'auto',
    isDefault: true,
    isActive: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  setUp(() {
    mockTemplateDao = MockBarcodeTemplateDao();
    mockPrinterService = MockBarcodePrinterService();
    mockCompanyProfileService = MockCompanyProfileService();
    mockProductVariantDao = MockProductVariantDao();

    when(
      mockCompanyProfileService.watchProfile(),
    ).thenAnswer((_) => Stream.value(CompanyProfile.empty()));
    when(
      mockCompanyProfileService.getProfile(),
    ).thenAnswer((_) async => CompanyProfile.empty());

    // Default stubs
    when(
      mockTemplateDao.watchTemplates(),
    ).thenAnswer((_) => Stream.value([testTemplate]));
    when(
      mockTemplateDao.getTemplates(),
    ).thenAnswer((_) async => [testTemplate]);
    when(
      mockTemplateDao.getDefaultTemplate(),
    ).thenAnswer((_) async => testTemplate);
    when(
      mockPrinterService.getBarcodeTypeFromString(any),
    ).thenReturn(Barcode.code128());
    when(
      mockTemplateDao.logPrint(
        productId: anyNamed('productId'),
        variantId: anyNamed('variantId'),
        templateId: anyNamed('templateId'),
        quantityPrinted: anyNamed('quantityPrinted'),
        printerName: anyNamed('printerName'),
        printType: anyNamed('printType'),
        status: anyNamed('status'),
        errorMessage: anyNamed('errorMessage'),
      ),
    ).thenAnswer((_) async => 1);

    bloc = BarcodeDesignBloc(
      templateDao: mockTemplateDao,
      printerService: mockPrinterService,
      companyProfileService: mockCompanyProfileService,
      productVariantDao: mockProductVariantDao,
    );
  });

  tearDown(() {
    bloc.close();
  });

  group('BarcodeDesignBloc', () {
    test('initial state is RealtimeLoading or RealtimeSuccess', () {
      // Bloc may start loading immediately due to stream subscription
      expect(
        bloc.state,
        anyOf(
          isA<RealtimeLoading<BarcodeDesignData>>(),
          isA<RealtimeSuccess<BarcodeDesignData>>(),
        ),
      );
    });

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'emits states when LoadBarcodeDesignData is added',
      build: () => bloc,
      act: (bloc) => bloc.add(const LoadBarcodeDesignData()),
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.state, isA<RealtimeSuccess<BarcodeDesignData>>());
        final state = bloc.state as RealtimeSuccess<BarcodeDesignData>;
        expect(state.data.templates.length, 1);
        expect(state.data.selectedTemplate?.id, 1);
        verify(mockTemplateDao.getTemplates()).called(1);
        verify(mockTemplateDao.getDefaultTemplate()).called(1);
      },
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'loads initial products when provided',
      build: () => bloc,
      act: (bloc) =>
          bloc.add(LoadBarcodeDesignData(initialProducts: [testProduct])),
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.state, isA<RealtimeSuccess<BarcodeDesignData>>());
        final state = bloc.state as RealtimeSuccess<BarcodeDesignData>;
        expect(state.data.selectedProducts.length, 1);
        expect(state.data.selectedProducts.first.id, 1);
      },
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'adds products to selection',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(AddProductsToSelection([testProduct])),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.selectedProducts.length,
          'products length',
          1,
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'removes product from selection',
      build: () => bloc,
      seed: () => RealtimeSuccess(
        data: BarcodeDesignData(selectedProducts: [testProduct]),
      ),
      act: (bloc) => bloc.add(const RemoveProductFromSelection(1)),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.selectedProducts.length,
          'products length',
          0,
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'clears product selection',
      build: () => bloc,
      seed: () => RealtimeSuccess(
        data: BarcodeDesignData(selectedProducts: [testProduct]),
      ),
      act: (bloc) => bloc.add(const ClearProductSelection()),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.selectedProducts.isEmpty,
          'products empty',
          true,
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'selects template and updates settings',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(SelectTemplate(testTemplate)),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>()
            .having((s) => s.data.selectedTemplate?.id, 'template id', 1)
            .having((s) => s.data.settings.labelWidthMm, 'width', 58.0)
            .having((s) => s.data.settings.labelHeightMm, 'height', 40.0),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'updates label dimensions',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) =>
          bloc.add(const UpdateLabelDimensions(widthMm: 80.0, heightMm: 50.0)),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>()
            .having((s) => s.data.settings.labelWidthMm, 'width', 80.0)
            .having((s) => s.data.settings.labelHeightMm, 'height', 50.0),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'toggles include name',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(const ToggleIncludeName(false)),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.settings.includeName,
          'includeName',
          false,
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'toggles include price',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(const ToggleIncludePrice(false)),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.settings.includePrice,
          'includePrice',
          false,
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'selects both retail and wholesale prices and enables price display',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) =>
          bloc.add(const UpdatePriceDisplayMode(PriceDisplayMode.both)),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>()
            .having(
              (s) => s.data.settings.priceDisplayMode,
              'priceDisplayMode',
              PriceDisplayMode.both,
            )
            .having((s) => s.data.settings.includePrice, 'includePrice', true),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'toggles include SKU',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(const ToggleIncludeSku(true)),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.settings.includeSku,
          'includeSku',
          true,
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'updates barcode type',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(const UpdateBarcodeType('qr')),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.settings.barcodeType,
          'barcodeType',
          'qr',
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'updates copies count',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(const UpdateCopies(5)),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.settings.copies,
          'copies',
          5,
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'clamps copies to valid range',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(const UpdateCopies(1000)),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.settings.copies,
          'copies',
          999,
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'updates print type',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(const UpdatePrintType('batch')),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.settings.printType,
          'printType',
          'batch',
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'shows error when printing with no products selected',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(const PrintLabels()),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.errorMessage,
          'errorMessage',
          'No products selected for printing',
        ),
      ],
    );

    test(
      'passes simple-product color and size to PDF jobs when enabled',
      () async {
        mockProductVariantDao.productInfoById[testProduct.id] = 'Large / Red';

        final loaded = bloc.stream.firstWhere(
          (state) =>
              state is RealtimeSuccess<BarcodeDesignData> &&
              state.data.selectedProducts.isNotEmpty,
        );
        bloc.add(LoadBarcodeDesignData(initialProducts: [testProduct]));
        await loaded;

        final enabled = bloc.stream.firstWhere(
          (state) =>
              state is RealtimeSuccess<BarcodeDesignData> &&
              state.data.settings.includeVariantInfo,
        );
        bloc.add(const ToggleIncludeVariantInfo(true));
        await enabled;

        final printed = bloc.stream.firstWhere(
          (state) =>
              state is RealtimeSuccess<BarcodeDesignData> &&
              state.data.operationStatus == PrintOperationStatus.success,
        );
        bloc.add(const PrintLabels());
        await printed;

        final captured = verify(
          mockPrinterService.printLabelsPdfBatch(
            jobs: captureAnyNamed('jobs'),
            barcode: anyNamed('barcode'),
            widthMm: anyNamed('widthMm'),
            heightMm: anyNamed('heightMm'),
            includeName: anyNamed('includeName'),
            includePrice: anyNamed('includePrice'),
            priceDisplayMode: anyNamed('priceDisplayMode'),
            includeBarcode: anyNamed('includeBarcode'),
            includeSku: anyNamed('includeSku'),
            includeCompanyName: anyNamed('includeCompanyName'),
            companyName: anyNamed('companyName'),
            includeCompanyContact: anyNamed('includeCompanyContact'),
            companyAddress: anyNamed('companyAddress'),
            companyPhone: anyNamed('companyPhone'),
            isA4Mode: anyNamed('isA4Mode'),
            labelsPerRow: anyNamed('labelsPerRow'),
            horizontalGapMm: anyNamed('horizontalGapMm'),
            verticalGapMm: anyNamed('verticalGapMm'),
            pageMarginMm: anyNamed('pageMarginMm'),
            includeVariantInfo: true,
          ),
        ).captured.single;

        final jobs =
            captured
                as List<({Product product, int copies, String? variantInfo})>;
        expect(jobs, hasLength(1));
        expect(jobs.single.variantInfo, 'Large / Red');
      },
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'shows error when sharing with no products selected',
      build: () => bloc,
      seed: () => RealtimeSuccess(data: BarcodeDesignData.empty()),
      act: (bloc) => bloc.add(const ShareLabels()),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>().having(
          (s) => s.data.errorMessage,
          'errorMessage',
          'No products selected for sharing',
        ),
      ],
    );

    blocTest<BarcodeDesignBloc, RealtimeState<BarcodeDesignData>>(
      'acknowledges print result and resets status',
      build: () => bloc,
      seed: () => RealtimeSuccess(
        data: const BarcodeDesignData(
          operationStatus: PrintOperationStatus.success,
          errorMessage: 'Some message',
        ),
      ),
      act: (bloc) => bloc.add(const AcknowledgePrintResult()),
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<BarcodeDesignData>>()
            .having(
              (s) => s.data.operationStatus,
              'status',
              PrintOperationStatus.idle,
            )
            .having((s) => s.data.errorMessage, 'errorMessage', null),
      ],
    );
  });

  group('BarcodeDesignSettings', () {
    test('creates from template correctly', () {
      final settings = BarcodeDesignSettings.fromTemplate(testTemplate);

      expect(settings.labelWidthMm, 58.0);
      expect(settings.labelHeightMm, 40.0);
      expect(settings.includeName, true);
      expect(settings.includePrice, true);
      expect(settings.includeSku, false);
      expect(settings.includeCompanyName, false);
      expect(settings.includeVariantInfo, false);
      expect(settings.barcodeType, 'auto');
    });

    test('copyWith preserves unchanged values', () {
      const settings = BarcodeDesignSettings();
      final updated = settings.copyWith(copies: 10);

      expect(updated.copies, 10);
      expect(updated.labelWidthMm, settings.labelWidthMm);
      expect(updated.includeName, settings.includeName);
    });
  });

  group('BarcodeDesignData', () {
    test('empty creates default state', () {
      final data = BarcodeDesignData.empty();

      expect(data.selectedProducts, isEmpty);
      expect(data.templates, isEmpty);
      expect(data.selectedTemplate, isNull);
      expect(data.operationStatus, PrintOperationStatus.idle);
    });

    test('copyWith clears error when requested', () {
      const data = BarcodeDesignData(errorMessage: 'Error');
      final updated = data.copyWith(clearError: true);

      expect(updated.errorMessage, isNull);
    });
  });
}
