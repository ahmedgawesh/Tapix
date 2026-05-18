/// Business-wide inventory valuation method.
///
/// Mirrors the IAS 2 / ASC 330 *consistency principle*: a business picks ONE
/// method and applies it uniformly. World-class ERPs (Odoo, SAP, NetSuite,
/// Cin7) all enforce this at the policy level even when they expose
/// per-product flags for engineering convenience.
///
/// Storage:
///   * Persisted as a single row in `app_settings` with key
///     [InventoryValuationMethod.settingKey] and value matching one of
///     [wac]/[fifo] string keys.
///   * Read/written exclusively via `InventoryValuationService` so we keep
///     a single cache + change-stream contract.
///
/// Naming:
///   * `wac`  = Weighted Average Cost (running blended cost).
///   * `fifo` = First-In-First-Out (cost of oldest batch consumed first).
///
/// Design notes:
///   * No `last` / `lifo` here — both are accounting-illegal under IFRS,
///     and `last` was an engineering crutch in the old per-product flag.
///   * The method does not encode the *removal strategy* (FEFO vs FIFO).
///     Removal strategy is decided per-product via `inventory_tracking_type`
///     (Phase B). FEFO is automatic when expiry tracking is enabled.
enum InventoryValuationMethod {
  /// Weighted Average Cost. Default for new businesses. Behaviour:
  ///   * On purchase: `cost_cents` becomes `(old × oldQty + new × newQty) / total`.
  ///   * On sale: COGS = `cost_cents × qty` for batch-less products, or
  ///     `Σ batch.unit_cost × qty` for batched products (the batches still
  ///     freeze cost — WAC at the *product* level, FIFO inside the batch
  ///     ledger; both stay coherent because batches are created at the
  ///     paid cost).
  wac('wac'),

  /// First-In-First-Out. Behaviour:
  ///   * On purchase: `cost_cents` displays the latest paid price (the
  ///     batches own per-layer truth).
  ///   * On sale: COGS = oldest batch's frozen `unit_cost_cents`. This
  ///     requires the product to have batches; products with
  ///     `inventory_tracking_type = 'standard'` cannot use FIFO and the
  ///     callers fall back to WAC math at posting time.
  fifo('fifo');

  /// Stable string key persisted in `app_settings` and migration scripts.
  /// Never change a value — older installations rely on the exact spelling.
  final String key;

  const InventoryValuationMethod(this.key);

  /// Settings table key. Centralised so tests and migrations agree.
  static const String settingKey = 'inventory_valuation_method';

  /// Default for new installations. Matches QuickBooks Online (UK/AU) and
  /// Xero defaults; the safest behaviour for a small business that has not
  /// expressed a preference, and it requires no batch infrastructure to
  /// produce a correct COGS.
  static const InventoryValuationMethod defaultMethod =
      InventoryValuationMethod.wac;

  /// Parse a stored string into the enum, falling back to [defaultMethod]
  /// when the value is absent or not recognised. Never throws — this is
  /// the read path used by background services.
  static InventoryValuationMethod fromKey(String? raw) {
    switch (raw) {
      case 'wac':
        return InventoryValuationMethod.wac;
      case 'fifo':
        return InventoryValuationMethod.fifo;
      default:
        return defaultMethod;
    }
  }

  /// Convenience for the legacy column shape (`'wac' | 'fifo'`). Keeps
  /// migration code readable.
  String get legacyColumnValue => key;
}
