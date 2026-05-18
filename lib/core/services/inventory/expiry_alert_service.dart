import 'package:drift/drift.dart';

import '../../../features/inventory/domain/entities/expiry_alert_item.dart';
import '../../database/app_database.dart';

/// Centralised query layer for batch-expiry alerts.
///
/// One owner for the SQL ⇒ identical numbers across:
///   * Phase C product tile badge (already covered by
///     `ProductDao.watchExpirySummaries` — kept untouched).
///   * Phase E dashboard widget (`ExpiryAlertsSection`).
///   * Phase E full report screen (`ExpiryReportScreen`).
///
/// Standard ERP / pharmacy-POS bucket cadence — 30 / 60 / 90 days plus an
/// "already expired" bucket. Mirrors Odoo's `mrp.expiry` and SAP B1's batch
/// expiry alerts.
///
/// Notes on correctness:
///   * Today is anchored to **start-of-today (local time)** so a batch that
///     expires today is treated as already expired. This matches Odoo / SAP.
///   * `expiry_date` is stored as ISO 8601 text under
///     `storeDateTimeValuesAsText`, so lexicographic SQLite ordering matches
///     chronological ordering — no client-side post-sort needed.
///   * Rows from products *not* tracked as `'batch_expiry'` are ignored.
///     A `'batch'`-only product never raises an alert, by design.
class ExpiryAlertService {
  final AppDatabase _db;
  final DateTime Function() _now;

  ExpiryAlertService(this._db, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Reactive stream that re-emits whenever a relevant table changes.
  /// Combine with a debounce upstream if you ever wire it to a chatty UI.
  Stream<ExpiryAlertSnapshot> watchAlerts() {
    return _buildQuery().watch().map(_mapRows);
  }

  /// One-shot fetch — used by report exports / PDF jobs that prefer a
  /// snapshot over a stream.
  Future<ExpiryAlertSnapshot> fetchAlerts() async {
    final rows = await _buildQuery().get();
    return _mapRows(rows);
  }

  // ─── internals ───────────────────────────────────────────────────────────

  Selectable<QueryRow> _buildQuery() {
    final now = _now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final today = startOfToday.toIso8601String();
    // 90-day horizon — anything beyond is healthy and excluded.
    final horizon = startOfToday
        .add(const Duration(days: 90))
        // Use end-of-day on day 90 so a batch expiring at any time on that
        // calendar day is included. SQLite ISO 8601 lexicographic ordering
        // makes this a single-comparison check.
        .add(const Duration(hours: 23, minutes: 59, seconds: 59))
        .toIso8601String();

    return _db.customSelect(
      '''
      SELECT
        b.id                AS batch_id,
        b.batch_number      AS batch_number,
        b.expiry_date       AS expiry_date,
        b.remaining_quantity AS remaining_quantity,
        b.unit_cost_cents   AS unit_cost_cents,
        p.id                AS product_id,
        p.name              AS product_name,
        v.id                AS variant_id,
        COALESCE(v.sku, p.sku)   AS sku,
        pc.name             AS color_name,
        pc.hex_code         AS color_hex,
        sz.name             AS size_name
      FROM product_batches b
      INNER JOIN products p ON p.id = b.product_id
      LEFT JOIN product_variants v ON v.id = b.variant_id AND v.is_active = 1
      LEFT JOIN product_colors pc ON pc.id = v.color_id
      LEFT JOIN sizes sz ON sz.id = v.size_id
      WHERE p.is_active = 1
        AND p.inventory_tracking_type = 'batch_expiry'
        AND b.is_active = 1
        AND b.remaining_quantity > 0
        AND b.expiry_date IS NOT NULL
        AND b.expiry_date <= ?2
      ORDER BY b.expiry_date ASC, b.id ASC
      ''',
      variables: [
        Variable.withString(today),
        Variable.withString(horizon),
      ],
      readsFrom: {
        _db.products,
        _db.productVariants,
        _db.productBatches,
        _db.productColors,
        _db.sizes,
      },
    );
  }

  ExpiryAlertSnapshot _mapRows(List<QueryRow> rows) {
    if (rows.isEmpty) return ExpiryAlertSnapshot.empty;

    final now = _now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final items = <ExpiryAlertItem>[];
    var expiredCount = 0;
    var in30 = 0;
    var in60 = 0;
    var in90 = 0;
    var expiredCostCents = 0;

    for (final row in rows) {
      final expiryIso = row.read<String>('expiry_date');
      final expiry = DateTime.parse(expiryIso);
      final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
      final diffDays = expiryDay.difference(startOfToday).inDays;
      final bucket = _bucketFor(diffDays);

      // Drop any row that slips past the 90-day horizon between SQL eval and
      // the Dart mapping (rare, but possible at midnight rollover under
      // long-running streams).
      if (bucket == null) continue;

      final remainingQty = row.read<int>('remaining_quantity');
      final unitCost = row.read<int>('unit_cost_cents');
      final variantLabel = _composeVariantLabel(
        colorName: row.readNullable<String>('color_name'),
        sizeName: row.readNullable<String>('size_name'),
      );

      items.add(ExpiryAlertItem(
        batchId: row.read<int>('batch_id'),
        batchNumber: row.read<String>('batch_number'),
        productId: row.read<int>('product_id'),
        productName: row.read<String>('product_name'),
        variantId: row.readNullable<int>('variant_id'),
        variantLabel: variantLabel,
        sku: row.readNullable<String>('sku'),
        expiryDate: expiry,
        daysUntilExpiry: diffDays,
        remainingQuantity: remainingQty,
        unitCostCents: unitCost,
        bucket: bucket,
      ));

      switch (bucket) {
        case ExpiryBucket.expired:
          expiredCount++;
          expiredCostCents += remainingQty * unitCost;
        case ExpiryBucket.in30Days:
          in30++;
        case ExpiryBucket.in60Days:
          in60++;
        case ExpiryBucket.in90Days:
          in90++;
      }
    }

    return ExpiryAlertSnapshot(
      items: items,
      summary: ExpiryAlertSummary(
        expiredCount: expiredCount,
        in30DaysCount: in30,
        in60DaysCount: in60,
        in90DaysCount: in90,
        expiredCostCents: expiredCostCents,
      ),
    );
  }

  /// Pure bucket resolver — public via `@visibleForTesting` style by keeping
  /// it package-private; tests in the same file tree exercise it through
  /// `_mapRows` against a Drift in-memory DB so behavior stays end-to-end.
  static ExpiryBucket? _bucketFor(int daysUntilExpiry) {
    if (daysUntilExpiry <= 0) return ExpiryBucket.expired;
    if (daysUntilExpiry <= 30) return ExpiryBucket.in30Days;
    if (daysUntilExpiry <= 60) return ExpiryBucket.in60Days;
    if (daysUntilExpiry <= 90) return ExpiryBucket.in90Days;
    return null;
  }

  static String _composeVariantLabel({
    required String? colorName,
    required String? sizeName,
  }) {
    final parts = <String>[];
    if (colorName != null && colorName.isNotEmpty) parts.add(colorName);
    if (sizeName != null && sizeName.isNotEmpty) parts.add(sizeName);
    return parts.join(' / ');
  }
}
