import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/products/domain/entities/import_file_data.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/services/import_validation_service.dart';

class MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late ImportValidationService service;
  late MockProductRepository mockRepository;

  setUp(() {
    mockRepository = MockProductRepository();
    service = ImportValidationService(mockRepository);
  });

  group('ImportValidationService', () {
    test('should return error when required name field is empty', () async {
      const fileData = ImportFileData(
        fileName: 'test.csv',
        fileType: ImportFileType.csv,
        headers: ['name', 'price'],
        rows: [
          ['', '19.99'],
        ],
        totalRows: 1,
      );

      const columnMapping = ColumnMapping({'name': 0, 'price': 1});

      final errors = await service(
        fileData: fileData,
        columnMapping: columnMapping,
      );

      expect(errors.length, greaterThan(0));
      expect(
        errors.any((e) => e.field == 'name' && e.message.contains('required')),
        true,
      );
    });

    test('should return error when price is invalid format', () async {
      const fileData = ImportFileData(
        fileName: 'test.csv',
        fileType: ImportFileType.csv,
        headers: ['name', 'price'],
        rows: [
          ['Product 1', 'invalid'],
        ],
        totalRows: 1,
      );

      const columnMapping = ColumnMapping({'name': 0, 'price': 1});

      final errors = await service(
        fileData: fileData,
        columnMapping: columnMapping,
      );

      expect(errors.length, greaterThan(0));
      expect(
        errors.any((e) => e.field == 'price' && e.message.contains('Invalid')),
        true,
      );
    });

    test('should detect duplicate SKU', () async {
      const fileData = ImportFileData(
        fileName: 'test.csv',
        fileType: ImportFileType.csv,
        headers: ['name', 'sku', 'price'],
        rows: [
          ['Product 1', 'SKU001', '19.99'],
        ],
        totalRows: 1,
      );

      const columnMapping = ColumnMapping({'name': 0, 'sku': 1, 'price': 2});

      when(
        () => mockRepository.findBySku('SKU001'),
      ).thenAnswer((_) async => null);

      await service(fileData: fileData, columnMapping: columnMapping);

      verify(() => mockRepository.findBySku('SKU001')).called(1);
    });

    test('should return no errors for valid data', () async {
      const fileData = ImportFileData(
        fileName: 'test.csv',
        fileType: ImportFileType.csv,
        headers: ['name', 'price', 'stock_quantity'],
        rows: [
          ['Product 1', '19.99', '100'],
        ],
        totalRows: 1,
      );

      const columnMapping = ColumnMapping({
        'name': 0,
        'price': 1,
        'stock_quantity': 2,
      });

      final errors = await service(
        fileData: fileData,
        columnMapping: columnMapping,
      );

      expect(errors, isEmpty);
    });
  });
}
