import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/features/products/domain/entities/import_file_data.dart';
import 'package:tapix/features/products/domain/entities/import_result.dart';
import 'package:tapix/features/products/domain/usecases/import_products.dart';
import 'package:tapix/features/products/domain/usecases/parse_import_file.dart';
import 'package:tapix/features/products/domain/usecases/validate_import_data.dart';
import 'package:tapix/features/products/presentation/bloc/import_products_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/import_products_event.dart';
import 'package:tapix/features/products/presentation/bloc/import_products_state.dart';

class MockParseImportFile extends Mock implements ParseImportFile {}

class MockValidateImportData extends Mock implements ValidateImportData {}

class MockImportProducts extends Mock implements ImportProducts {}

class MockCurrencyService extends Mock implements CurrencyService {}

class FakeImportFileData extends Fake implements ImportFileData {}

class FakeColumnMapping extends Fake implements ColumnMapping {}

void main() {
  late ImportProductsBloc bloc;
  late MockParseImportFile mockParseImportFile;
  late MockValidateImportData mockValidateImportData;
  late MockImportProducts mockImportProducts;
  late MockCurrencyService mockCurrencyService;

  setUpAll(() {
    registerFallbackValue(FakeImportFileData());
    registerFallbackValue(FakeColumnMapping());
  });

  setUp(() {
    mockParseImportFile = MockParseImportFile();
    mockValidateImportData = MockValidateImportData();
    mockImportProducts = MockImportProducts();
    mockCurrencyService = MockCurrencyService();

    when(
      () => mockCurrencyService.getCurrency(),
    ).thenReturn(const Currency(code: 'USD', symbol: '\$', name: 'US Dollar'));

    bloc = ImportProductsBloc(
      parseImportFile: mockParseImportFile,
      validateImportData: mockValidateImportData,
      importProducts: mockImportProducts,
      currencyService: mockCurrencyService,
    );
  });

  tearDown(() {
    bloc.close();
  });

  group('ImportProductsBloc', () {
    test('initial state is ImportProductsInitial', () {
      expect(bloc.state, const ImportProductsInitial());
    });

    blocTest<ImportProductsBloc, ImportProductsState>(
      'emits [ImportFileLoading, ImportFileParsed] when file is selected successfully',
      build: () {
        const fileData = ImportFileData(
          fileName: 'test.csv',
          fileType: ImportFileType.csv,
          headers: ['name', 'price'],
          rows: [
            ['Product 1', '19.99'],
          ],
          totalRows: 1,
        );

        when(
          () => mockParseImportFile(
            bytes: any(named: 'bytes'),
            fileName: any(named: 'fileName'),
          ),
        ).thenAnswer((_) async => fileData);

        return bloc;
      },
      act: (bloc) => bloc.add(
        const ImportFileSelected(fileBytes: [1, 2, 3], fileName: 'test.csv'),
      ),
      expect: () => [const ImportFileLoading(), isA<ImportFileParsed>()],
    );

    blocTest<ImportProductsBloc, ImportProductsState>(
      'emits [ImportFileLoading, ImportFailed] when file parsing fails',
      build: () {
        when(
          () => mockParseImportFile(
            bytes: any(named: 'bytes'),
            fileName: any(named: 'fileName'),
          ),
        ).thenThrow(Exception('Parse error'));

        return bloc;
      },
      act: (bloc) => bloc.add(
        const ImportFileSelected(fileBytes: [1, 2, 3], fileName: 'test.csv'),
      ),
      expect: () => [const ImportFileLoading(), isA<ImportFailed>()],
    );

    blocTest<ImportProductsBloc, ImportProductsState>(
      'emits [ImportValidating, ImportValidated] when validation succeeds',
      build: () {
        when(
          () => mockValidateImportData(
            fileData: any(named: 'fileData'),
            columnMapping: any(named: 'columnMapping'),
          ),
        ).thenAnswer((_) async => []);

        return bloc;
      },
      seed: () => const ImportColumnMappingReady(
        fileData: ImportFileData(
          fileName: 'test.csv',
          fileType: ImportFileType.csv,
          headers: ['name', 'price'],
          rows: [
            ['Product 1', '19.99'],
          ],
          totalRows: 1,
        ),
        columnMapping: ColumnMapping({'name': 0, 'price': 1}),
        availableFields: [],
      ),
      act: (bloc) => bloc.add(const ImportValidationRequested()),
      expect: () => [isA<ImportValidating>(), isA<ImportValidated>()],
    );

    blocTest<ImportProductsBloc, ImportProductsState>(
      'emits [ImportInProgress, ImportCompleted] when import succeeds',
      build: () {
        const result = ImportResult(
          totalRows: 1,
          successfulRows: 1,
          failedRows: 0,
          errors: [],
          rowToProductId: {0: 1},
          duration: Duration(seconds: 1),
        );

        when(
          () => mockImportProducts(
            fileData: any(named: 'fileData'),
            columnMapping: any(named: 'columnMapping'),
          ),
        ).thenAnswer((_) async => result);

        return bloc;
      },
      seed: () => const ImportValidated(
        fileData: ImportFileData(
          fileName: 'test.csv',
          fileType: ImportFileType.csv,
          headers: ['name', 'price'],
          rows: [
            ['Product 1', '19.99'],
          ],
          totalRows: 1,
        ),
        columnMapping: ColumnMapping({'name': 0, 'price': 1}),
        validationErrors: [],
      ),
      act: (bloc) => bloc.add(const ImportExecutionStarted()),
      expect: () => [isA<ImportInProgress>(), isA<ImportCompleted>()],
    );

    blocTest<ImportProductsBloc, ImportProductsState>(
      'resets to initial state when ImportReset is added',
      build: () => bloc,
      seed: () => const ImportFileLoading(),
      act: (bloc) => bloc.add(const ImportReset()),
      expect: () => [const ImportProductsInitial()],
    );
  });
}
