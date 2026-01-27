import '../domain/entities/scanner_result.dart';

class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult({
    required this.isValid,
    this.errorMessage,
  });
}

class BarcodeValidationService {
  ValidationResult validateBarcode(String barcode, BarcodeFormat format) {
    switch (format) {
      case BarcodeFormat.ean13:
        return _validateEan13(barcode);
      case BarcodeFormat.ean8:
        return _validateEan8(barcode);
      case BarcodeFormat.upcA:
        return _validateUpcA(barcode);
      case BarcodeFormat.upcE:
        return _validateUpcE(barcode);
      case BarcodeFormat.code128:
        return _validateCode128(barcode);
      case BarcodeFormat.code39:
        return _validateCode39(barcode);
      case BarcodeFormat.qrCode:
        return const ValidationResult(isValid: true);
      case BarcodeFormat.unknown:
        return const ValidationResult(isValid: true);
    }
  }

  BarcodeFormat detectFormat(String barcode) {
    if (barcode.isEmpty) return BarcodeFormat.unknown;

    // Check if all digits
    final isNumeric = RegExp(r'^\d+$').hasMatch(barcode);

    if (isNumeric) {
      switch (barcode.length) {
        case 13:
          return BarcodeFormat.ean13;
        case 12:
          return BarcodeFormat.upcA;
        case 8:
          return BarcodeFormat.ean8;
        case 6:
          return BarcodeFormat.upcE;
      }
    }

    // Check for alphanumeric (Code128 or Code39)
    if (RegExp(r'^[A-Z0-9\-\.\$\/\+\%\s]+$').hasMatch(barcode.toUpperCase())) {
      return BarcodeFormat.code128;
    }

    return BarcodeFormat.unknown;
  }

  int calculateEan13Checksum(String barcode12) {
    if (barcode12.length != 12) {
      throw ArgumentError('EAN-13 barcode without checksum must be 12 digits');
    }

    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = int.parse(barcode12[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }

    final checksum = (10 - (sum % 10)) % 10;
    return checksum;
  }

  int _calculateUpcAChecksum(String barcode11) {
    if (barcode11.length != 11) {
      throw ArgumentError('UPC-A barcode without checksum must be 11 digits');
    }

    int oddSum = 0;
    int evenSum = 0;
    for (int i = 0; i < 11; i++) {
      final digit = int.parse(barcode11[i]);
      if (i % 2 == 0) {
        oddSum += digit;
      } else {
        evenSum += digit;
      }
    }

    final total = (oddSum * 3) + evenSum;
    final checksum = (10 - (total % 10)) % 10;
    return checksum;
  }

  ValidationResult _validateEan13(String barcode) {
    if (barcode.length != 13) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'EAN-13 barcode must be 13 digits',
      );
    }

    if (!RegExp(r'^\d{13}$').hasMatch(barcode)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'EAN-13 barcode must contain only digits',
      );
    }

    final expectedChecksum = calculateEan13Checksum(barcode.substring(0, 12));
    final actualChecksum = int.parse(barcode[12]);

    if (expectedChecksum != actualChecksum) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Invalid EAN-13 checksum. Expected $expectedChecksum, got $actualChecksum',
      );
    }

    return const ValidationResult(isValid: true);
  }

  ValidationResult _validateEan8(String barcode) {
    if (barcode.length != 8) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'EAN-8 barcode must be 8 digits',
      );
    }

    if (!RegExp(r'^\d{8}$').hasMatch(barcode)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'EAN-8 barcode must contain only digits',
      );
    }

    // EAN-8 checksum calculation (similar to EAN-13 but with 8 digits)
    int sum = 0;
    for (int i = 0; i < 7; i++) {
      final digit = int.parse(barcode[i]);
      sum += (i % 2 == 0) ? digit * 3 : digit;
    }

    final expectedChecksum = (10 - (sum % 10)) % 10;
    final actualChecksum = int.parse(barcode[7]);

    if (expectedChecksum != actualChecksum) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Invalid EAN-8 checksum. Expected $expectedChecksum, got $actualChecksum',
      );
    }

    return const ValidationResult(isValid: true);
  }

  ValidationResult _validateUpcA(String barcode) {
    if (barcode.length != 12) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'UPC-A barcode must be 12 digits',
      );
    }

    if (!RegExp(r'^\d{12}$').hasMatch(barcode)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'UPC-A barcode must contain only digits',
      );
    }

    final expectedChecksum = _calculateUpcAChecksum(barcode.substring(0, 11));
    final actualChecksum = int.parse(barcode[11]);

    if (expectedChecksum != actualChecksum) {
      return ValidationResult(
        isValid: false,
        errorMessage: 'Invalid UPC-A checksum. Expected $expectedChecksum, got $actualChecksum',
      );
    }

    return const ValidationResult(isValid: true);
  }

  ValidationResult _validateUpcE(String barcode) {
    if (barcode.length != 6 && barcode.length != 8) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'UPC-E barcode must be 6 or 8 digits',
      );
    }

    if (!RegExp(r'^\d+$').hasMatch(barcode)) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'UPC-E barcode must contain only digits',
      );
    }

    return const ValidationResult(isValid: true);
  }

  ValidationResult _validateCode128(String barcode) {
    if (barcode.isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'Code 128 barcode cannot be empty',
      );
    }

    // Code 128 can contain ASCII characters 0-127
    for (int i = 0; i < barcode.length; i++) {
      if (barcode.codeUnitAt(i) > 127) {
        return const ValidationResult(
          isValid: false,
          errorMessage: 'Code 128 barcode contains invalid characters',
        );
      }
    }

    return const ValidationResult(isValid: true);
  }

  ValidationResult _validateCode39(String barcode) {
    if (barcode.isEmpty) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'Code 39 barcode cannot be empty',
      );
    }

    // Code 39 valid characters: A-Z, 0-9, -, ., $, /, +, %, space
    if (!RegExp(r'^[A-Z0-9\-\.\$\/\+\%\s]+$').hasMatch(barcode.toUpperCase())) {
      return const ValidationResult(
        isValid: false,
        errorMessage: 'Code 39 barcode contains invalid characters',
      );
    }

    return const ValidationResult(isValid: true);
  }
}
