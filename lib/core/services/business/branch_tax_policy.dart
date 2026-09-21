import '../../../features/settings/domain/entities/app_settings.dart';

/// Effective tax defaults only. Currency, prices and posted documents are not
/// part of this policy. Rates use the same basis points as the pricing engine.
class BranchTaxPolicy {
  BranchTaxPolicy({
    required this.enabled,
    required this.salesRateBps,
    required this.purchaseRateBps,
    required this.inclusivePricing,
    required this.registrationNumber,
  }) {
    _checkInteger(salesRateBps);
    _checkInteger(purchaseRateBps);
  }

  static const maxSafeInteger = 9007199254740991;
  final bool enabled;
  final int salesRateBps;
  final int purchaseRateBps;
  final bool inclusivePricing;
  final String registrationNumber;

  factory BranchTaxPolicy.fromLegacy(AppSettings settings) => BranchTaxPolicy(
    enabled: settings.enableTaxCalculations,
    salesRateBps: _rate(settings.defaultSalesTaxRate),
    purchaseRateBps: _rate(settings.defaultPurchaseTaxRate),
    inclusivePricing: settings.taxInclusivePricing,
    registrationNumber: settings.taxRegistrationNumber,
  );

  static int _rate(double percent) {
    final scaled = percent * 100;
    if (!percent.isFinite ||
        percent < 0 ||
        !scaled.isFinite ||
        scaled > maxSafeInteger) {
      throw ArgumentError('Invalid legacy tax rate.');
    }
    return scaled.round();
  }

  static void _checkInteger(int rate) {
    if (rate < 0 || rate > maxSafeInteger) {
      throw ArgumentError(
        'Tax basis points must be a nonnegative safe integer.',
      );
    }
  }

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'salesRateBps': salesRateBps,
    'purchaseRateBps': purchaseRateBps,
    'inclusivePricing': inclusivePricing,
    'registrationNumber': registrationNumber,
  };

  factory BranchTaxPolicy.fromJson(Object? input) {
    if (input is! Map ||
        input['enabled'] is! bool ||
        input['salesRateBps'] is! int ||
        input['purchaseRateBps'] is! int ||
        input['inclusivePricing'] is! bool ||
        input['registrationNumber'] is! String) {
      throw const FormatException('Invalid branch tax policy.');
    }
    return BranchTaxPolicy(
      enabled: input['enabled'] as bool,
      salesRateBps: input['salesRateBps'] as int,
      purchaseRateBps: input['purchaseRateBps'] as int,
      inclusivePricing: input['inclusivePricing'] as bool,
      registrationNumber: input['registrationNumber'] as String,
    );
  }

  /// Overlay only branch-owned tax fields; retain every device preference.
  AppSettings applyTo(AppSettings settings) => settings.copyWith(
    enableTaxCalculations: enabled,
    defaultSalesTaxRate: salesRateBps / 100,
    defaultPurchaseTaxRate: purchaseRateBps / 100,
    taxInclusivePricing: inclusivePricing,
    taxRegistrationNumber: registrationNumber,
  );

  bool hasSameValues(BranchTaxPolicy other) =>
      enabled == other.enabled &&
      salesRateBps == other.salesRateBps &&
      purchaseRateBps == other.purchaseRateBps &&
      inclusivePricing == other.inclusivePricing &&
      registrationNumber == other.registrationNumber;
}
