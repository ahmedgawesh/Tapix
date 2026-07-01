import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feature_gate_service.dart';

/// Thrown by [FreeQuotaService.guardProductCreation] and
/// [FreeQuotaService.guardSaleCreation] when a free-tier user has exhausted
/// their cumulative quota and tries to create one more.
class FreeQuotaExceededException implements Exception {
  final FreeQuotaKind kind;
  final int limit;
  final int currentCount;

  const FreeQuotaExceededException({
    required this.kind,
    required this.limit,
    required this.currentCount,
  });

  @override
  String toString() =>
      'FreeQuotaExceededException(kind=$kind, limit=$limit, current=$currentCount)';
}

/// Which counter has been exhausted.
enum FreeQuotaKind { products, sales }

/// Snapshot of the user's free-tier counters.
class FreeQuotaStatus {
  /// Cumulative number of products ever created (lifetime, never decrements).
  final int productsCreatedLifetime;

  /// Cumulative number of sale invoices ever created (lifetime).
  final int salesCreatedLifetime;

  /// Configured max for products. `null` means unlimited (Pro users).
  final int? productsLimit;

  /// Configured max for sales. `null` means unlimited (Pro users).
  final int? salesLimit;

  const FreeQuotaStatus({
    required this.productsCreatedLifetime,
    required this.salesCreatedLifetime,
    required this.productsLimit,
    required this.salesLimit,
  });

  int? get productsRemaining =>
      productsLimit == null ? null : (productsLimit! - productsCreatedLifetime).clamp(0, productsLimit!);

  int? get salesRemaining =>
      salesLimit == null ? null : (salesLimit! - salesCreatedLifetime).clamp(0, salesLimit!);

  bool get productsExhausted =>
      productsLimit != null && productsCreatedLifetime >= productsLimit!;

  bool get salesExhausted =>
      salesLimit != null && salesCreatedLifetime >= salesLimit!;

  bool get isUnlimited => productsLimit == null && salesLimit == null;
}

/// Enforces the free-tier cumulative quota:
/// - 100 products created lifetime
/// - 100 sale invoices created lifetime
///
/// **Hybrid model**: counters are stored in [SharedPreferences] and only ever
/// increment. Deleting a product / voiding a sale does NOT free up quota.
/// UI components can still query live `COUNT(*)` from the database for display.
///
/// Pro users bypass all checks via [FeatureGateService.isPro].
class FreeQuotaService {
  /// Hard caps for free tier (Phase B2, per product requirement).
  static const int defaultMaxProductsLifetime = 100;
  static const int defaultMaxSalesLifetime = 100;

  static const String _kProductsKey = 'free_quota.products_created_lifetime';
  static const String _kSalesKey = 'free_quota.sales_created_lifetime';

  final SharedPreferences _prefs;
  final FeatureGateService _featureGateService;

  /// Allows tests / future remote-config to override limits.
  final int maxProductsLifetime;
  final int maxSalesLifetime;

  FreeQuotaService({
    required SharedPreferences prefs,
    required FeatureGateService featureGateService,
    this.maxProductsLifetime = defaultMaxProductsLifetime,
    this.maxSalesLifetime = defaultMaxSalesLifetime,
  })  : _prefs = prefs,
        _featureGateService = featureGateService;

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Current cumulative count of products created (never decrements).
  int get productsCreatedLifetime => _prefs.getInt(_kProductsKey) ?? 0;

  /// Current cumulative count of sale invoices created (never decrements).
  int get salesCreatedLifetime => _prefs.getInt(_kSalesKey) ?? 0;

  /// Snapshot for UI display. When user is Pro, limits are `null` (unlimited).
  FreeQuotaStatus status() {
    final isPro = _featureGateService.isPro;
    return FreeQuotaStatus(
      productsCreatedLifetime: productsCreatedLifetime,
      salesCreatedLifetime: salesCreatedLifetime,
      productsLimit: isPro ? null : maxProductsLifetime,
      salesLimit: isPro ? null : maxSalesLifetime,
    );
  }

  // ── Guards (call before performing the action) ────────────────────────────

  /// Returns `true` when the user may create one more product.
  /// Pro users always return `true`.
  bool canCreateProduct() {
    if (_featureGateService.isPro) return true;
    return productsCreatedLifetime < maxProductsLifetime;
  }

  /// Returns `true` when the user may create one more sale invoice.
  /// Pro users always return `true`.
  bool canCreateSale() {
    if (_featureGateService.isPro) return true;
    return salesCreatedLifetime < maxSalesLifetime;
  }

  /// Throw [FreeQuotaExceededException] if the user cannot create another
  /// product. Pro users bypass.
  void guardProductCreation() {
    if (_featureGateService.isPro) return;
    final count = productsCreatedLifetime;
    if (count >= maxProductsLifetime) {
      throw FreeQuotaExceededException(
        kind: FreeQuotaKind.products,
        limit: maxProductsLifetime,
        currentCount: count,
      );
    }
  }

  /// Throw [FreeQuotaExceededException] if the user cannot create another
  /// sale invoice. Pro users bypass.
  void guardSaleCreation() {
    if (_featureGateService.isPro) return;
    final count = salesCreatedLifetime;
    if (count >= maxSalesLifetime) {
      throw FreeQuotaExceededException(
        kind: FreeQuotaKind.sales,
        limit: maxSalesLifetime,
        currentCount: count,
      );
    }
  }

  // ── Mutations (call after a successful creation) ──────────────────────────

  /// Increment the cumulative products counter. Pro users still increment so
  /// that if their subscription lapses, their lifetime usage is accurate.
  Future<void> incrementProductsCreated() async {
    final next = productsCreatedLifetime + 1;
    await _prefs.setInt(_kProductsKey, next);
    if (kDebugMode) {
      debugPrint('FreeQuota: products lifetime → $next / $maxProductsLifetime');
    }
  }

  /// Increment the cumulative sales counter. Pro users still increment.
  Future<void> incrementSalesCreated() async {
    final next = salesCreatedLifetime + 1;
    await _prefs.setInt(_kSalesKey, next);
    if (kDebugMode) {
      debugPrint('FreeQuota: sales lifetime → $next / $maxSalesLifetime');
    }
  }

  // ── Admin / Tests ─────────────────────────────────────────────────────────

  /// Reset both counters. Used by tests and by an admin "reset usage"
  /// flow if one is ever exposed (not exposed to free users).
  @visibleForTesting
  Future<void> resetCountersForTesting() async {
    await _prefs.remove(_kProductsKey);
    await _prefs.remove(_kSalesKey);
  }
}
