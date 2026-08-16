import '../domain/models/barcode_design_state.dart';
import '../../products/domain/entities/product_entity.dart';

/// Formats the price area of a barcode label without ever exposing cost.
String formatBarcodePrice({
  required Product product,
  required PriceDisplayMode mode,
  required String Function(int cents) formatCurrency,
  required String retailLabel,
  required String wholesaleLabel,
}) {
  final retail = formatCurrency(product.priceCents.toBigInt().toInt());
  final wholesaleCents = product.wholesalePriceCents?.toBigInt().toInt();
  final wholesale = wholesaleCents == null
      ? '-'
      : formatCurrency(wholesaleCents);

  switch (mode) {
    case PriceDisplayMode.retail:
      return retail;
    case PriceDisplayMode.wholesale:
      return '$wholesaleLabel: $wholesale';
    case PriceDisplayMode.both:
      return '$retailLabel: $retail\n$wholesaleLabel: $wholesale';
  }
}
