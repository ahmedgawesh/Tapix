/// Phase 11.2 — pricing engine version snapshot.
///
/// Every persisted invoice / return header records the engine version that
/// produced its totals, the tax-inclusivity setting in force at post time,
/// and the rounding mode. This guarantees that an auditor reading a 2030
/// row of `sales` can determine *exactly* which algorithm produced it,
/// even if the engine ships a v2 with different rounding rules.
///
/// **Compatibility contract**: never delete or rename a version string.
/// When the engine changes meaningfully (new rounding default, new
/// allocation algorithm, etc.), bump [current] to the next version.
/// Existing rows keep their historical version forever.
class PricingEngineVersion {
  PricingEngineVersion._();

  /// v1 — initial release. Phase-3..7 migration shipped under this
  /// label. `LineItemPricingEngine` + `InvoicePricingEngine` with
  /// `MoneyRoundingMode.halfUp`, `TaxRoundingMode.halfUp`,
  /// largest-remainder allocation, and tax-on-adjusted-net.
  static const String v1 = 'v1';

  /// The version every NEW post written today should record.
  static const String current = v1;
}

/// Canonical short-form labels for the rounding mode actually used by
/// the engine when producing the persisted row. Persisted as TEXT for
/// auditability; never used as a runtime decision input.
class RoundingModeLabel {
  RoundingModeLabel._();

  static const String halfUp = 'halfUp';
  static const String halfEven = 'halfEven';
  static const String down = 'down';
}
