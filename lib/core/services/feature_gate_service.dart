import 'package:flutter/foundation.dart';

import 'revenuecat_service.dart';

/// Enumeration of every gated feature in Tapix.
///
/// Adding a new feature → add it here, then update [FeatureGateService.requiresPro]
/// to declare its tier. This file is the **single source of truth** for what
/// is locked behind the paywall.
enum AppFeature {
  // ── Always-free (no entry below in [requiresPro]) ──
  /// Add / edit / delete products (subject to free-tier quota).
  productsManage,

  /// Create sales / POS (subject to free-tier quota).
  salesCreate,

  /// View own sale receipts and basic sale list.
  salesView,

  /// Categories, tax rates, units — direct dependencies of products / sales.
  productMetadata,

  /// Barcode **scanning** (used at POS to look up products).
  barcodeScan,

  /// Authentication, login, session.
  authentication,

  /// Basic settings (language, theme, business name).
  basicSettings,

  // ── Pro-only ──
  /// Printing / generating barcode labels.
  barcodePrint,

  /// Manual or automatic backup & restore.
  backupRestore,

  /// Purchases module (PO creation, GRN, supplier invoices).
  purchases,

  /// Customer management (CRM, customer ledger).
  customers,

  /// Supplier management (supplier ledger).
  suppliers,

  /// Employees module (HR, commissions, payroll).
  employees,

  /// Inventory operations beyond product CRUD (stock count, transfers, batches, expiry).
  inventoryAdvanced,

  /// Sale returns and purchase returns (linked + adjustment).
  returns,

  /// Cheques module (issued / received cheques lifecycle).
  cheques,

  /// All reports (sales reports, profit reports, etc).
  reports,

  /// Accounting (chart of accounts, journal entries, fiscal periods).
  accounting,

  /// Reconciliation & health screen.
  reconciliation,

  /// Multi-user / RBAC / permissions.
  multiUser,
}

/// Result of a feature-access check.
class FeatureAccess {
  /// `true` when the user can use the feature right now.
  final bool granted;

  /// Reason for denial when [granted] is `false`. `null` when granted.
  final FeatureDenyReason? denyReason;

  const FeatureAccess.granted()
      : granted = true,
        denyReason = null;

  const FeatureAccess.denied(this.denyReason) : granted = false;

  bool get denied => !granted;
}

/// Why a feature was denied.
enum FeatureDenyReason {
  /// User is on the free tier; feature requires Pro.
  requiresPro,

  /// User exceeded the free-tier cumulative quota (handled separately by
  /// `FreeQuotaService`; this enum value is reserved for callers that want to
  /// surface a unified denial result).
  freeQuotaExceeded,
}

/// Central rule-table for Tapix's freemium model.
///
/// **SoT**: this is the only place that decides whether a feature is Pro-only,
/// AND the only place that caches the live Pro entitlement. It is a
/// [ChangeNotifier] so the router (`refreshListenable`) and widgets
/// (`ListenableBuilder`) re-evaluate access the instant entitlement changes —
/// no second source of truth, no cross-bloc timing races.
///
/// Callers must NEVER hard-code `if (!isPro)` checks; they must call
/// [FeatureGateService.canAccess] (sync), read [isPro], or look up
/// [requiresPro] directly.
class FeatureGateService extends ChangeNotifier {
  final RevenueCatService _revenueCatService;

  /// Cached last-known Pro state, refreshed by [refresh] and by listening to
  /// [RevenueCatService.subscriptionStatusStream]. Reads are sync so the
  /// router and widgets can decide instantly.
  bool _isPro = false;

  /// Whether the cached value has ever been refreshed since process start.
  bool get isInitialized => _initialized;
  bool _initialized = false;

  FeatureGateService({required RevenueCatService revenueCatService})
      : _revenueCatService = revenueCatService {
    // On platforms where in-app purchases are unavailable (web / desktop),
    // there is no way to subscribe, so the freemium gate must NOT apply.
    // Treat the user as Pro so the whole app is usable.
    if (!RevenueCatConfig.isSupported) {
      _isPro = true;
      _initialized = true;
      return;
    }

    _revenueCatService.subscriptionStatusStream.listen((status) {
      _setPro(status.isPro);
    });
    // Fire-and-forget initial sync. The stream is broadcast (no replay), so
    // we must explicitly fetch the current entitlement at startup.
    // ignore: discarded_futures
    refresh();
  }

  /// Whether the user currently has Pro entitlement (sync, cached).
  /// Always `true` on platforms where purchases are unsupported.
  bool get isPro => !RevenueCatConfig.isSupported || _isPro;

  /// Update the cached state and notify listeners only when it actually
  /// changed, so the router / widgets rebuild exactly once per real transition.
  void _setPro(bool value) {
    _initialized = true;
    if (_isPro == value) return;
    _isPro = value;
    if (kDebugMode) {
      debugPrint('FeatureGate: isPro changed → $_isPro');
    }
    notifyListeners();
  }

  /// Refresh the cached Pro state from RevenueCat.
  Future<void> refresh() async {
    if (!RevenueCatConfig.isSupported) {
      _setPro(true);
      return;
    }
    final status = await _revenueCatService.checkSubscription();
    _setPro(status.isPro);
  }

  /// **SoT** — declares whether [feature] requires a Pro subscription.
  ///
  /// Free tier allows ONLY:
  /// - Products CRUD (quota-limited)
  /// - Sales / POS (quota-limited)
  /// - Sale view (own receipts)
  /// - Product metadata (categories, tax, units)
  /// - Barcode SCANNING (POS lookup)
  /// - Authentication
  /// - Basic settings
  ///
  /// Everything else — including barcode PRINTING — is Pro-only.
  static bool requiresPro(AppFeature feature) {
    switch (feature) {
      // Always free
      case AppFeature.productsManage:
      case AppFeature.salesCreate:
      case AppFeature.salesView:
      case AppFeature.productMetadata:
      case AppFeature.barcodeScan:
      case AppFeature.authentication:
      case AppFeature.basicSettings:
        return false;

      // Pro-only
      case AppFeature.barcodePrint:
      case AppFeature.backupRestore:
      case AppFeature.purchases:
      case AppFeature.customers:
      case AppFeature.suppliers:
      case AppFeature.employees:
      case AppFeature.inventoryAdvanced:
      case AppFeature.returns:
      case AppFeature.cheques:
      case AppFeature.reports:
      case AppFeature.accounting:
      case AppFeature.reconciliation:
      case AppFeature.multiUser:
        return true;
    }
  }

  /// Check whether [feature] can be accessed by the current user.
  ///
  /// Note: this does NOT enforce the free-tier quota — that is the job of
  /// `FreeQuotaService`. This method only answers the "is this Pro-only?"
  /// question against the user's entitlement.
  FeatureAccess canAccess(AppFeature feature) {
    if (!requiresPro(feature)) {
      return const FeatureAccess.granted();
    }
    if (isPro) {
      return const FeatureAccess.granted();
    }
    return const FeatureAccess.denied(FeatureDenyReason.requiresPro);
  }
}
