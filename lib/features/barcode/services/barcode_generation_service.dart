import 'dart:math';

/// Central service for generating valid EAN-13 barcodes.
///
/// An EAN-13 barcode is 13 digits long where the 13th digit is a checksum
/// computed from the first 12 digits using the standard weighting 1,3,1,3,...
/// The checksum is `(10 - (sum % 10)) % 10`.
///
/// Prior to this service the app had two copies of the random-generation
/// helper (in `product_form_screen` and `product_form_bloc`) and a third
/// helper (`_buildAutoBarcode`) that produced **13 digits without a valid
/// checksum**, which caused EAN-13-strict scanners to reject store-generated
/// labels. This service replaces all three usages.
class BarcodeGenerationService {
  /// EAN-13 "Internal / In-store" prefix. Codes starting with 2 are reserved
  /// by GS1 for in-store / internal use and are safe to generate locally
  /// without colliding with registered manufacturer prefixes.
  static const String inStorePrefix = '2';

  /// Deterministic in-store prefix used for stable auto-barcodes derived
  /// from a variant ID. Using a different first digit (29) keeps these
  /// distinguishable from randomly generated ones in reports.
  static const String deterministicPrefix = '29';

  final Random _random;

  BarcodeGenerationService({Random? random}) : _random = random ?? Random();

  /// Generates a random, valid EAN-13 barcode with the "in-store" prefix `2`.
  String generateRandomEan13() {
    final digits = List<int>.generate(11, (_) => _random.nextInt(10));
    final base = inStorePrefix + digits.join();
    return _appendChecksum(base);
  }

  /// Generates a deterministic EAN-13 from a numeric variant/product id so
  /// the same record always gets the same barcode. Useful for auto-assigning
  /// barcodes on first save. Produces exactly 13 digits with a valid checksum.
  ///
  /// Layout: `29` (2 digits) + zero-padded id (10 digits) + checksum (1 digit)
  String generateDeterministicEan13(int id) {
    if (id < 0) {
      throw ArgumentError('id must be non-negative for EAN-13 generation');
    }
    final padded = id.toString().padLeft(10, '0');
    if (padded.length > 10) {
      // IDs large enough to overflow 10 digits cannot fit; fall back to random.
      return generateRandomEan13();
    }
    final base = deterministicPrefix + padded;
    return _appendChecksum(base);
  }

  /// Returns true if [code] is exactly 13 digits with a valid EAN-13 checksum.
  bool isValidEan13(String code) {
    if (code.length != 13 || !RegExp(r'^\d{13}$').hasMatch(code)) return false;
    final expected = _computeChecksum(code.substring(0, 12));
    return expected == int.parse(code[12]);
  }

  /// Computes the EAN-13 checksum digit for a 12-digit base.
  static int _computeChecksum(String base12) {
    assert(base12.length == 12);
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = int.parse(base12[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    return (10 - (sum % 10)) % 10;
  }

  static String _appendChecksum(String base12) {
    return base12 + _computeChecksum(base12).toString();
  }
}
