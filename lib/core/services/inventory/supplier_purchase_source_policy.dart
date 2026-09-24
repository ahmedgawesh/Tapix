/// Supplier identity is an opt-in inventory feature.
///
/// The complete source-aware cycle is available in debug, profile and release
/// builds. The persisted user setting remains the only feature switch.
class SupplierPurchaseSourcePolicy {
  SupplierPurchaseSourcePolicy._();

  static const buildAllowsWrites = true;

  static bool enabled(bool requested) => requested;
}
