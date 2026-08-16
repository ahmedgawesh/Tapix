import 'package:decimal/decimal.dart';

/// Converts the checkout value of one loyalty point between the user-facing
/// major currency unit (for example 0.01 USD/EGP) and the integer minor unit
/// used by invoices and journal entries.
abstract final class LoyaltyPointValue {
  static const int minCents = 1;
  static const int maxCents = 10000;

  static String toInputText(int cents) => (cents / 100).toStringAsFixed(2);

  static int fromInputText(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    final value = Decimal.tryParse(normalized);
    if (value == null || value <= Decimal.zero) return minCents;

    final cents = (value * Decimal.fromInt(100)).round().toBigInt().toInt();
    return cents.clamp(minCents, maxCents);
  }
}
