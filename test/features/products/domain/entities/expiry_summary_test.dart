// ─────────────────────────────────────────────────────────────────────────────
// ExpirySummary — domain unit tests
//
// These tests pin the *decision matrix* for the per-product expiry badge:
//   1. hasExpired                                      → ExpiryStatus.expired
//   2. daysUntilNearestExpiry != null && <= threshold  → ExpiryStatus.nearExpiry
//   3. otherwise                                       → ExpiryStatus.healthy
//
// They are framework-free (no Flutter / no Drift) on purpose — both Phase C
// (product list tile) and Phase E (alert dashboard) call the same `statusFor`
// method, so this single file guards the contract for both surfaces.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/products/domain/entities/expiry_summary.dart';

void main() {
  group('ExpirySummary.statusFor — decision matrix', () {
    test('expired wins over near-expiry (priority #1)', () {
      // Even when the nearest non-expired batch is also within the threshold,
      // the presence of any expired-with-stock batch must surface as expired.
      const s = ExpirySummary(
        hasExpired: true,
        expiredQuantity: 5,
        nearestExpiry: null,
        daysUntilNearestExpiry: 3,
      );
      expect(s.statusFor(), ExpiryStatus.expired);
      expect(s.statusFor(thresholdDays: 90), ExpiryStatus.expired);
    });

    test('nearExpiry when daysUntilNearestExpiry == 0', () {
      // 0 days = expires today (already start-of-day clamped). Must badge
      // amber, not red — the batch is still sellable until the cutoff.
      const s = ExpirySummary(
        hasExpired: false,
        expiredQuantity: 0,
        nearestExpiry: null,
        daysUntilNearestExpiry: 0,
      );
      expect(s.statusFor(), ExpiryStatus.nearExpiry);
    });

    test('nearExpiry when daysUntilNearestExpiry == threshold (boundary)', () {
      const s = ExpirySummary(
        hasExpired: false,
        expiredQuantity: 0,
        nearestExpiry: null,
        daysUntilNearestExpiry: 30,
      );
      expect(s.statusFor(thresholdDays: 30), ExpiryStatus.nearExpiry);
    });

    test('healthy when daysUntilNearestExpiry > threshold', () {
      const s = ExpirySummary(
        hasExpired: false,
        expiredQuantity: 0,
        nearestExpiry: null,
        daysUntilNearestExpiry: 31,
      );
      expect(s.statusFor(thresholdDays: 30), ExpiryStatus.healthy);
    });

    test('healthy when daysUntilNearestExpiry is null (no upcoming expiry)', () {
      // A product whose only remaining batches are already expired would set
      // `hasExpired=true`. A product with NO batches at all simply isn't in
      // the map, so this branch represents an edge case where a `null`
      // distance must NOT be treated as "near".
      const s = ExpirySummary(
        hasExpired: false,
        expiredQuantity: 0,
        nearestExpiry: null,
        daysUntilNearestExpiry: null,
      );
      expect(s.statusFor(), ExpiryStatus.healthy);
    });

    test('custom threshold is respected (60-day amber window)', () {
      const s = ExpirySummary(
        hasExpired: false,
        expiredQuantity: 0,
        nearestExpiry: null,
        daysUntilNearestExpiry: 45,
      );
      expect(s.statusFor(thresholdDays: 30), ExpiryStatus.healthy);
      expect(s.statusFor(thresholdDays: 60), ExpiryStatus.nearExpiry);
    });

    test('default threshold equals kDefaultNearExpiryThresholdDays', () {
      // Pin the public default — a regression here would silently shift the
      // amber window globally (Phase C tile + Phase E alerts both rely on it).
      expect(kDefaultNearExpiryThresholdDays, 30);
      const s = ExpirySummary(
        hasExpired: false,
        expiredQuantity: 0,
        nearestExpiry: null,
        daysUntilNearestExpiry: kDefaultNearExpiryThresholdDays,
      );
      expect(s.statusFor(), ExpiryStatus.nearExpiry);
    });
  });

  group('ExpirySummary — field invariants', () {
    test('expired summary preserves expiredQuantity for tooltips', () {
      const s = ExpirySummary(
        hasExpired: true,
        expiredQuantity: 17,
        nearestExpiry: null,
        daysUntilNearestExpiry: null,
      );
      expect(s.expiredQuantity, 17);
      expect(s.statusFor(), ExpiryStatus.expired);
    });

    test('nearestExpiry round-trips through the constructor unchanged', () {
      final next = DateTime(2026, 6, 1);
      final s = ExpirySummary(
        hasExpired: false,
        expiredQuantity: 0,
        nearestExpiry: next,
        daysUntilNearestExpiry: 14,
      );
      expect(s.nearestExpiry, next);
      expect(s.daysUntilNearestExpiry, 14);
    });
  });
}
