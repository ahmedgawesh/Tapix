import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/products/domain/entities/import_file_data.dart';
import 'package:tapix/features/products/services/file_import_service.dart';

void main() {
  late FileImportService service;

  setUp(() {
    service = FileImportService();
  });

  group('FileImportService - CSV', () {
    test('should parse valid CSV file correctly', () async {
      final csvContent = '''name,sku,price,stock
Product 1,SKU001,19.99,100
Product 2,SKU002,29.99,50''';
      final bytes = utf8.encode(csvContent);

      final result = await service(bytes: bytes, fileName: 'products.csv');

      expect(result.fileName, 'products.csv');
      expect(result.fileType, ImportFileType.csv);
      expect(result.headers.length, 4);
      expect(result.headers, ['name', 'sku', 'price', 'stock']);
      expect(result.totalRows, 2);
      expect(result.rows.length, 2);
      expect(result.rows[0], ['Product 1', 'SKU001', '19.99', '100']);
    });

    test('should handle empty CSV file', () async {
      final csvContent = '';
      final bytes = utf8.encode(csvContent);

      expect(
        () => service(bytes: bytes, fileName: 'empty.csv'),
        throwsException,
      );
    });

    test('should handle CSV with special characters', () async {
      final csvContent = '''name,description,price
"Product, with comma","Description with ""quotes""",19.99''';
      final bytes = utf8.encode(csvContent);

      final result = await service(bytes: bytes, fileName: 'special.csv');

      expect(result.totalRows, 1);
      expect(result.rows[0][0], 'Product, with comma');
      expect(result.rows[0][1], 'Description with "quotes"');
    });
  });

  group('FileImportService - Excel', () {
    test('should throw exception for unsupported file type', () async {
      final bytes = [1, 2, 3, 4];

      expect(
        () => service(bytes: bytes, fileName: 'file.txt'),
        throwsException,
      );
    });
  });
}
