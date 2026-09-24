import 'package:equatable/equatable.dart';

enum BarcodeFormat { ean13, ean8, upcA, upcE, code128, code39, qrCode, unknown }

class ScannerResult extends Equatable {
  final String barcode;
  final BarcodeFormat format;
  final DateTime timestamp;

  const ScannerResult({
    required this.barcode,
    required this.format,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [barcode, format, timestamp];

  ScannerResult copyWith({
    String? barcode,
    BarcodeFormat? format,
    DateTime? timestamp,
  }) {
    return ScannerResult(
      barcode: barcode ?? this.barcode,
      format: format ?? this.format,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
