import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/barcode/domain/entities/scanner_result.dart';
import 'package:tapix/features/barcode/presentation/bloc/barcode_scanner_bloc.dart';
import 'package:tapix/features/barcode/services/barcode_validation_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:decimal/decimal.dart';

class MockProductRepository extends Mock implements ProductRepository {}
class MockBarcodeValidationService extends Mock implements BarcodeValidationService {}

void main() {
  late MockProductRepository mockRepository;
  late MockBarcodeValidationService mockValidationService;

  setUp(() {
    mockRepository = MockProductRepository();
    mockValidationService = MockBarcodeValidationService();
  });

  setUpAll(() {
    registerFallbackValue(BarcodeFormat.ean13);
  });

  Product createTestProduct({
    int id = 1,
    String name = 'Test Product',
    String? barcode = '5901234123457',
  }) {
    return Product(
      id: id,
      name: name,
      barcode: barcode,
      costCents: Decimal.fromInt(1000),
      priceCents: Decimal.fromInt(1999),
      stockQuantity: 10,
      minQuantity: 5,
      hasVariants: false,
      isTaxable: false,
      purchaseTaxRateBps: 0,
      salesTaxRateBps: 0,
      isActive: true,
      trackInventory: true,
    );
  }

  group('BarcodeScannerBloc', () {
    test('initial state is RealtimeSuccess with default ScannerState', () {
      final bloc = BarcodeScannerBloc(
        productRepository: mockRepository,
        validationService: mockValidationService,
      );
      
      expect(bloc.state, isA<RealtimeSuccess<ScannerState>>());
      final state = (bloc.state as RealtimeSuccess<ScannerState>).data;
      expect(state.isScanning, false);
      expect(state.lastResult, isNull);
      expect(state.foundProduct, isNull);
      
      bloc.close();
    });

    blocTest<BarcodeScannerBloc, RealtimeState<ScannerState>>(
      'emits scanning state when StartScanning is added',
      build: () => BarcodeScannerBloc(
        productRepository: mockRepository,
        validationService: mockValidationService,
      ),
      act: (bloc) => bloc.add(const StartScanning()),
      expect: () => [
        // First: event handler emission with scanning=true
        isA<RealtimeSuccess<ScannerState>>().having(
          (s) => s.data.isScanning,
          'isScanning',
          true,
        ),
        // Second: stream emission with default state
        isA<RealtimeSuccess<ScannerState>>().having(
          (s) => s.data.isScanning,
          'isScanning',
          false,
        ),
      ],
    );

    blocTest<BarcodeScannerBloc, RealtimeState<ScannerState>>(
      'emits not scanning state when StopScanning is added',
      build: () => BarcodeScannerBloc(
        productRepository: mockRepository,
        validationService: mockValidationService,
      ),
      seed: () => RealtimeSuccess(
        data: const ScannerState(isScanning: true),
      ),
      act: (bloc) => bloc.add(const StopScanning()),
      expect: () => [
        // First: event handler emission with scanning=false
        isA<RealtimeSuccess<ScannerState>>().having(
          (s) => s.data.isScanning,
          'isScanning',
          false,
        ),
        // Second: stream emission with default state
        isA<RealtimeSuccess<ScannerState>>().having(
          (s) => s.data.isScanning,
          'isScanning',
          false,
        ),
      ],
    );

    blocTest<BarcodeScannerBloc, RealtimeState<ScannerState>>(
      'emits error when barcode validation fails',
      build: () {
        when(() => mockValidationService.validateBarcode(any(), any()))
            .thenReturn(const ValidationResult(
              isValid: false,
              errorMessage: 'Invalid checksum',
            ));
        
        return BarcodeScannerBloc(
          productRepository: mockRepository,
          validationService: mockValidationService,
        );
      },
      act: (bloc) => bloc.add(const BarcodeDetected(
        barcode: '5901234123450',
        format: BarcodeFormat.ean13,
      )),
      expect: () => [
        // First: event handler emission with error
        isA<RealtimeSuccess<ScannerState>>().having(
          (s) => s.data.error,
          'error',
          'Invalid checksum',
        ),
        // Second: stream emission with default state
        isA<RealtimeSuccess<ScannerState>>(),
      ],
    );

    blocTest<BarcodeScannerBloc, RealtimeState<ScannerState>>(
      'clears state when ClearScanResult is added',
      build: () => BarcodeScannerBloc(
        productRepository: mockRepository,
        validationService: mockValidationService,
      ),
      seed: () => RealtimeSuccess(
        data: ScannerState(
          lastResult: ScannerResult(
            barcode: '123',
            format: BarcodeFormat.ean13,
            timestamp: DateTime.now(),
          ),
          foundProduct: createTestProduct(),
        ),
      ),
      act: (bloc) => bloc.add(const ClearScanResult()),
      expect: () => [
        // First: event handler emission with cleared state
        isA<RealtimeSuccess<ScannerState>>().having(
          (s) => s.data.lastResult,
          'lastResult',
          isNull,
        ),
        // Second: stream emission with default state
        isA<RealtimeSuccess<ScannerState>>(),
      ],
    );

    test('finds product when valid barcode is scanned', () async {
      when(() => mockValidationService.validateBarcode(any(), any()))
          .thenReturn(const ValidationResult(isValid: true));
      when(() => mockRepository.findByBarcode('5901234123457'))
          .thenAnswer((_) async => createTestProduct());
      
      final bloc = BarcodeScannerBloc(
        productRepository: mockRepository,
        validationService: mockValidationService,
      );
      
      bloc.add(const BarcodeDetected(
        barcode: '5901234123457',
        format: BarcodeFormat.ean13,
      ));
      
      // Wait for async operations to complete
      await expectLater(
        bloc.stream,
        emitsThrough(isA<RealtimeSuccess<ScannerState>>().having(
          (s) => s.data.foundProduct?.name,
          'product name',
          'Test Product',
        )),
      );
      
      await bloc.close();
    });

    test('handles manual barcode entry', () async {
      when(() => mockValidationService.detectFormat(any()))
          .thenReturn(BarcodeFormat.ean13);
      when(() => mockValidationService.validateBarcode(any(), any()))
          .thenReturn(const ValidationResult(isValid: true));
      when(() => mockRepository.findByBarcode(any()))
          .thenAnswer((_) async => createTestProduct());
      
      final bloc = BarcodeScannerBloc(
        productRepository: mockRepository,
        validationService: mockValidationService,
      );
      
      bloc.add(const ManualBarcodeEntered('5901234123457'));
      
      // Wait for async operations to complete
      await expectLater(
        bloc.stream,
        emitsThrough(isA<RealtimeSuccess<ScannerState>>().having(
          (s) => s.data.foundProduct,
          'product',
          isNotNull,
        )),
      );
      
      await bloc.close();
    });
  });
}
