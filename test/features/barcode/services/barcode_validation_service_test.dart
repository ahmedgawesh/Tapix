import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/barcode/services/barcode_validation_service.dart';
import 'package:tapix/features/barcode/domain/entities/scanner_result.dart';

void main() {
  late BarcodeValidationService service;

  setUp(() {
    service = BarcodeValidationService();
  });

  group('BarcodeValidationService', () {
    group('validateBarcode', () {
      test('should validate correct EAN-13 barcode', () {
        // Valid EAN-13: 5901234123457
        final result = service.validateBarcode(
          '5901234123457',
          BarcodeFormat.ean13,
        );
        expect(result.isValid, true);
        expect(result.errorMessage, isNull);
      });

      test('should reject invalid EAN-13 checksum', () {
        // Invalid checksum (last digit should be 7, not 0)
        final result = service.validateBarcode(
          '5901234123450',
          BarcodeFormat.ean13,
        );
        expect(result.isValid, false);
        expect(result.errorMessage, isNotNull);
      });

      test('should reject EAN-13 with wrong length', () {
        final result = service.validateBarcode(
          '123456789',
          BarcodeFormat.ean13,
        );
        expect(result.isValid, false);
        expect(result.errorMessage, contains('13 digits'));
      });

      test('should validate correct UPC-A barcode', () {
        // Valid UPC-A: 012345678905
        final result = service.validateBarcode(
          '012345678905',
          BarcodeFormat.upcA,
        );
        expect(result.isValid, true);
      });

      test('should reject invalid UPC-A checksum', () {
        final result = service.validateBarcode(
          '012345678900',
          BarcodeFormat.upcA,
        );
        expect(result.isValid, false);
      });

      test('should validate Code128 with valid characters', () {
        final result = service.validateBarcode(
          'ABC-123',
          BarcodeFormat.code128,
        );
        expect(result.isValid, true);
      });

      test('should accept any format for unknown type', () {
        final result = service.validateBarcode(
          'anybarcode123',
          BarcodeFormat.unknown,
        );
        expect(result.isValid, true);
      });
    });

    group('detectFormat', () {
      test('should detect EAN-13 format', () {
        final format = service.detectFormat('5901234123457');
        expect(format, BarcodeFormat.ean13);
      });

      test('should detect UPC-A format', () {
        final format = service.detectFormat('012345678905');
        expect(format, BarcodeFormat.upcA);
      });

      test('should detect EAN-8 format', () {
        final format = service.detectFormat('96385074');
        expect(format, BarcodeFormat.ean8);
      });

      test('should return unknown for unrecognized format', () {
        // Non-ASCII characters that don't match any known format
        final format = service.detectFormat('αβγ');
        expect(format, BarcodeFormat.unknown);
      });
    });

    group('calculateEan13Checksum', () {
      test('should calculate correct checksum for EAN-13', () {
        // For 590123412345, checksum should be 7
        final checksum = service.calculateEan13Checksum('590123412345');
        expect(checksum, 7);
      });
    });
  });
}
