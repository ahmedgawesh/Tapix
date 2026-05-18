/// Per-product summary of batch expiry health, used by the product list to
/// render a near-expiry / expired badge next to each tile.
///
/// Computed only for products whose `inventory_tracking_type` is
/// `'batch_expiry'` (Layer 2 of the two-layer inventory architecture). For
/// any other product the bloc will simply omit the entry from its map, and
/// the tile renders no badge — matching the existing variant-summary
/// pattern that drives the same screen.
///
/// Discriminator status:
///   - [ExpiryStatus.expired]    — at least one batch has `expiry_date < today`
///                                 AND `remaining_quantity > 0`. Highest
///                                 priority. Rendered as a red pill.
///   - [ExpiryStatus.nearExpiry] — at least one batch with stock will expire
///                                 within `nearExpiryThresholdDays` (default 30)
///                                 but no expired-with-stock rows exist.
///                                 Rendered as a yellow / amber pill.
///   - [ExpiryStatus.healthy]    — batches exist but the nearest expiring one
///                                 is still beyond the threshold. No badge.
///
/// Empty / standard / batch-without-expiry products yield no entry.
///
/// This file is intentionally framework-free: no Drift, no Flutter. The two
/// callers — Phase C tile badge and Phase E alert dashboard — share the same
/// enum, so the analytics never drift between the two surfaces.
library;

enum ExpiryStatus {
  healthy,
  nearExpiry,
  expired,
}

/// Default near-expiry window in days. Mirrors the convention used by Odoo
/// (30 / 60 / 90), QuickBooks Enterprise (30 default) and most pharmacy POS
/// systems. Centralized here so Phase E reuses the exact same threshold.
const int kDefaultNearExpiryThresholdDays = 30;

class ExpirySummary {
  /// `true` when at least one batch row with on-hand stock has already
  /// expired (`expiry_date < today`). Drives the red badge.
  final bool hasExpired;

  /// Total on-hand quantity across batches whose `expiry_date < today`.
  /// Useful for tooltips / dashboards. Always 0 when [hasExpired] is false.
  final int expiredQuantity;

  /// Nearest non-expired `expiry_date` across batches with stock, or `null`
  /// when every remaining batch is already expired (or none exists).
  final DateTime? nearestExpiry;

  /// Number of days until [nearestExpiry] from "now" at the moment this
  /// summary was computed. Negative values are clamped to 0 by the bloc
  /// before storage. `null` mirrors [nearestExpiry] being `null`.
  final int? daysUntilNearestExpiry;

  const ExpirySummary({
    required this.hasExpired,
    required this.expiredQuantity,
    required this.nearestExpiry,
    required this.daysUntilNearestExpiry,
  });

  /// Resolve the badge status for a given threshold (default 30 days).
  ///
  /// Decision matrix (in order — first match wins):
  ///   1. `hasExpired`                                       → expired
  ///   2. `daysUntilNearestExpiry != null && <= threshold`   → nearExpiry
  ///   3. otherwise                                          → healthy
  ExpiryStatus statusFor({
    int thresholdDays = kDefaultNearExpiryThresholdDays,
  }) {
    if (hasExpired) return ExpiryStatus.expired;
    final d = daysUntilNearestExpiry;
    if (d != null && d <= thresholdDays) return ExpiryStatus.nearExpiry;
    return ExpiryStatus.healthy;
  }
}
