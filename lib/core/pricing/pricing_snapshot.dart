import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'pricing_engine_version.dart';

/// Phase 11.2 — single source for stamping the immutable pricing-snapshot
/// fields on every invoice / return header at INSERT time.
///
/// The three snapshot columns (`pricing_engine_version`,
/// `tax_inclusive_at_post`, `rounding_mode_at_post`) are written once and
/// never mutated. They let an auditor reproduce the exact engine call that
/// produced the row's totals — even after the engine ships a v2 with
/// different rounding or allocation rules.
///
/// **Usage** at every header INSERT site:
/// ```dart
/// final companion = SalesCompanion(...).withPricingSnapshot(
///   taxInclusive: state.taxInclusivePricing,
/// );
/// ```
///
/// **Rules**
/// 1. Stamp ONLY at INSERT (or replace-on-edit). NEVER on `paid_amount`
///    or `status` updates — that would lie about the engine run that
///    actually produced the row's totals.
/// 2. Use [PricingEngineVersion.current] and [RoundingModeLabel.halfUp]
///    (the defaults baked into `LineItemPricingEngine` /
///    `InvoicePricingEngine`). Bump these only when the engine semantics
///    actually change.
/// 3. The `taxInclusive` argument MUST match the actual flag passed to
///    the engine that produced the persisted totals.
class PricingSnapshot {
  PricingSnapshot._();

  /// The engine-version label every NEW post written today should record.
  static const String engineVersion = PricingEngineVersion.current;

  /// The rounding-mode label every NEW post written today should record.
  /// Both `MoneyRoundingMode.halfUp` and `TaxRoundingMode.halfUp` are
  /// the engine defaults — kept in sync with this constant.
  static const String roundingMode = RoundingModeLabel.halfUp;
}

extension SalesCompanionPricingSnapshot on SalesCompanion {
  /// Stamp the Phase 11.2 audit-snapshot fields onto a new sale row.
  /// Must be called BEFORE `into(sales).insert(...)`.
  SalesCompanion withPricingSnapshot({required bool taxInclusive}) =>
      copyWith(
        pricingEngineVersion: const Value(PricingSnapshot.engineVersion),
        taxInclusiveAtPost: Value(taxInclusive),
        roundingModeAtPost: const Value(PricingSnapshot.roundingMode),
      );
}

extension PurchasesCompanionPricingSnapshot on PurchasesCompanion {
  PurchasesCompanion withPricingSnapshot({required bool taxInclusive}) =>
      copyWith(
        pricingEngineVersion: const Value(PricingSnapshot.engineVersion),
        taxInclusiveAtPost: Value(taxInclusive),
        roundingModeAtPost: const Value(PricingSnapshot.roundingMode),
      );
}

extension SaleReturnsCompanionPricingSnapshot on SaleReturnsCompanion {
  SaleReturnsCompanion withPricingSnapshot({required bool taxInclusive}) =>
      copyWith(
        pricingEngineVersion: const Value(PricingSnapshot.engineVersion),
        taxInclusiveAtPost: Value(taxInclusive),
        roundingModeAtPost: const Value(PricingSnapshot.roundingMode),
      );
}

extension PurchaseReturnsCompanionPricingSnapshot on PurchaseReturnsCompanion {
  PurchaseReturnsCompanion withPricingSnapshot({required bool taxInclusive}) =>
      copyWith(
        pricingEngineVersion: const Value(PricingSnapshot.engineVersion),
        taxInclusiveAtPost: Value(taxInclusive),
        roundingModeAtPost: const Value(PricingSnapshot.roundingMode),
      );
}

extension SaleReturnAdjustmentsCompanionPricingSnapshot
    on SaleReturnAdjustmentsCompanion {
  SaleReturnAdjustmentsCompanion withPricingSnapshot({
    required bool taxInclusive,
  }) => copyWith(
        pricingEngineVersion: const Value(PricingSnapshot.engineVersion),
        taxInclusiveAtPost: Value(taxInclusive),
        roundingModeAtPost: const Value(PricingSnapshot.roundingMode),
      );
}

extension PurchaseReturnAdjustmentsCompanionPricingSnapshot
    on PurchaseReturnAdjustmentsCompanion {
  PurchaseReturnAdjustmentsCompanion withPricingSnapshot({
    required bool taxInclusive,
  }) => copyWith(
        pricingEngineVersion: const Value(PricingSnapshot.engineVersion),
        taxInclusiveAtPost: Value(taxInclusive),
        roundingModeAtPost: const Value(PricingSnapshot.roundingMode),
      );
}
