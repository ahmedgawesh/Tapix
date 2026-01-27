import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/barcode/domain/entities/scanner_result.dart';

void main() {
  group('ScannerResult', () {
    test('should create ScannerResult with all properties', () {
      final result = ScannerResult(
        barcode: '1234567890123',
        format: BarcodeFormat.ean13,
        timestamp: DateTime(2026, 1, 25),
      );

      expect(result.barcode, '1234567890123');
      expect(result.format, BarcodeFormat.ean13);
      expect(result.timestamp, DateTime(2026, 1, 25));
    });

    test('should support equality', () {
      final result1 = ScannerResult(
        barcode: '1234567890123',
        format: BarcodeFormat.ean13,
        timestamp: DateTime(2026, 1, 25),
      );
      final result2 = ScannerResult(
        barcode: '1234567890123',
        format: BarcodeFormat.ean13,
        timestamp: DateTime(2026, 1, 25),
      );

      expect(result1, equals(result2));
    });

    test('should have different hash codes for different barcodes', () {
      final result1 = ScannerResult(
        barcode: '1234567890123',
        format: BarcodeFormat.ean13,
        timestamp: DateTime(2026, 1, 25),
      );
      final result2 = ScannerResult(
        barcode: '9876543210987',
        format: BarcodeFormat.ean13,
        timestamp: DateTime(2026, 1, 25),
      );

      expect(result1.hashCode, isNot(equals(result2.hashCode)));
    });
  });

  group('BarcodeFormat', () {
    test('should have all supported formats', () {
      expect(BarcodeFormat.values, contains(BarcodeFormat.ean13));
      expect(BarcodeFormat.values, contains(BarcodeFormat.ean8));
      expect(BarcodeFormat.values, contains(BarcodeFormat.upcA));
      expect(BarcodeFormat.values, contains(BarcodeFormat.upcE));
      expect(BarcodeFormat.values, contains(BarcodeFormat.code128));
      expect(BarcodeFormat.values, contains(BarcodeFormat.code39));
      expect(BarcodeFormat.values, contains(BarcodeFormat.qrCode));
      expect(BarcodeFormat.values, contains(BarcodeFormat.unknown));
    });
  });
}
