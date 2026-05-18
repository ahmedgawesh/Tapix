/// A single batch row surfaced by the Phase E expiry alert service.
///
/// One [ExpiryAlertItem] = one `product_batches` row that either:
///   * already expired (`expiry_date < today`) AND still carries
///     `remaining_quantity > 0` — accounting still owes us a write-off, and
///     the shelf still owes us a discard. Bucket: [ExpiryBucket.expired].
///   * will expire within `N` days, where `N ∈ {30, 60, 90}` — the standard
///     pharmacy / supermarket cadence used by Odoo, SAP B1, NetSuite and
///     QuickBooks Enterprise. Bucket: [ExpiryBucket.in30Days] /
///     [ExpiryBucket.in60Days] / [ExpiryBucket.in90Days].
///
/// The entity is intentionally framework-free. No Drift, no Flutter. It is
/// computed in the data layer (via `ExpiryAlertService`) and rendered by
/// (a) the dashboard widget (top-N preview) and (b) the full expiry report
/// screen — both of which share the exact same shape so the data never
/// drifts between the two surfaces.
library;

enum ExpiryBucket {
  /// Already past the expiry calendar day with stock remaining.
  expired,

  /// Will expire in (0, 30] days from start-of-today.
  in30Days,

  /// Will expire in (30, 60] days from start-of-today.
  in60Days,

  /// Will expire in (60, 90] days from start-of-today.
  in90Days,
}

/// Severity is purely a UI hint — the SQL is bucket-driven, not severity-
/// driven. The mapping is fixed and matches the badge colors used by
/// `product_tile_widget.dart` (Phase C):
///   expired      → red    ("error")
///   in30Days     → amber  ("warning")
///   in60Days     → amber  (same — the user only needs a single warning hue)
///   in90Days     → blue   ("info" — heads-up only)
enum ExpirySeverity { error, warning, info }

extension ExpiryBucketX on ExpiryBucket {
  ExpirySeverity get severity {
    switch (this) {
      case ExpiryBucket.expired:
        return ExpirySeverity.error;
      case ExpiryBucket.in30Days:
      case ExpiryBucket.in60Days:
        return ExpirySeverity.warning;
      case ExpiryBucket.in90Days:
        return ExpirySeverity.info;
    }
  }

  /// Stable string key used by translations (`reports.expiry_bucket_*`).
  String get translationKey {
    switch (this) {
      case ExpiryBucket.expired:
        return 'reports.expiry_bucket_expired';
      case ExpiryBucket.in30Days:
        return 'reports.expiry_bucket_30';
      case ExpiryBucket.in60Days:
        return 'reports.expiry_bucket_60';
      case ExpiryBucket.in90Days:
        return 'reports.expiry_bucket_90';
    }
  }
}

class ExpiryAlertItem {
  /// `product_batches.id` — stable handle for navigation / drill-down.
  final int batchId;

  /// `product_batches.batch_number` — human-readable lot identifier.
  final String batchNumber;

  final int productId;
  final String productName;

  /// `product_variants.id` — null for products without variants.
  final int? variantId;

  /// Pre-formatted variant label (color / size / SKU) for display, exactly
  /// as the existing `_VariantLabel` helper composes it elsewhere. Empty
  /// string means "no variant context".
  final String variantLabel;

  /// SKU for the variant (or product if no variant). Null when unset.
  final String? sku;

  /// Effective expiry date (always non-null — the SQL filters out NULL
  /// expiries before they reach this entity).
  final DateTime expiryDate;

  /// Days from start-of-today to [expiryDate]. Negative means already
  /// expired (kept as the actual diff so dashboards can show "5 days late"
  /// rather than always 0).
  final int daysUntilExpiry;

  /// Remaining on-hand quantity in this specific batch.
  final int remainingQuantity;

  /// Frozen per-unit cost at batch creation time, in cents. Used by the
  /// dashboard to show "potential write-off value" — purely informational,
  /// no posting happens here.
  final int unitCostCents;

  /// Resolved bucket. Pre-computed at query time so the UI never branches.
  final ExpiryBucket bucket;

  const ExpiryAlertItem({
    required this.batchId,
    required this.batchNumber,
    required this.productId,
    required this.productName,
    required this.variantId,
    required this.variantLabel,
    required this.sku,
    required this.expiryDate,
    required this.daysUntilExpiry,
    required this.remainingQuantity,
    required this.unitCostCents,
    required this.bucket,
  });

  /// Total potential write-off cost = `remainingQuantity × unitCostCents`.
  /// Useful for dashboard summaries; not a posted accounting figure.
  int get totalCostCents => remainingQuantity * unitCostCents;

  ExpirySeverity get severity => bucket.severity;
}

/// Aggregate counts emitted alongside the item list — drives the dashboard
/// widget's pill counters without forcing it to walk the whole list.
class ExpiryAlertSummary {
  final int expiredCount;
  final int in30DaysCount;
  final int in60DaysCount;
  final int in90DaysCount;

  /// Total potential write-off value across the [ExpiryBucket.expired] rows
  /// only (the other buckets are not yet a write-off — just a heads-up).
  final int expiredCostCents;

  const ExpiryAlertSummary({
    required this.expiredCount,
    required this.in30DaysCount,
    required this.in60DaysCount,
    required this.in90DaysCount,
    required this.expiredCostCents,
  });

  static const empty = ExpiryAlertSummary(
    expiredCount: 0,
    in30DaysCount: 0,
    in60DaysCount: 0,
    in90DaysCount: 0,
    expiredCostCents: 0,
  );

  int get totalAlertCount =>
      expiredCount + in30DaysCount + in60DaysCount + in90DaysCount;

  bool get isEmpty => totalAlertCount == 0;
  bool get isNotEmpty => !isEmpty;
}

/// Combined payload streamed by the alert service so consumers get items +
/// pre-computed counts in a single emission (no second pass on the UI side).
class ExpiryAlertSnapshot {
  final List<ExpiryAlertItem> items;
  final ExpiryAlertSummary summary;

  const ExpiryAlertSnapshot({
    required this.items,
    required this.summary,
  });

  static const empty = ExpiryAlertSnapshot(
    items: <ExpiryAlertItem>[],
    summary: ExpiryAlertSummary.empty,
  );
}
