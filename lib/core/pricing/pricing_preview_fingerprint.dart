import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'invoice_pricing_engine.dart';

/// Versioned comparison of displayed accounting results, not authentication.
/// The server must recompute pricing and compare inside its posting transaction.
String pricingPreviewFingerprint(
  InvoicePricingResult pricing, {
  required bool taxInclusive,
}) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          'pricing-preview-v1',
          taxInclusive,
          pricing.subtotal.cents,
          pricing.itemDiscountTotal.cents,
          pricing.overallDiscount.cents,
          pricing.totalDiscount.cents,
          pricing.tax.cents,
          pricing.total.cents,
          [
            for (final line in pricing.lines)
              [
                line.subtotal.cents,
                line.local.discount.cents,
                line.shareOfOverallDiscount.cents,
                line.adjustedNet.cents,
                line.tax.cents,
                line.total.cents,
                line.effectiveTaxRateBps,
              ],
          ],
        ]),
      ),
    )
    .toString();
