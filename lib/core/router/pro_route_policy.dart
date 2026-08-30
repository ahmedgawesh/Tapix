import '../services/feature_gate_service.dart';

/// Maps router paths to the [AppFeature] that governs them, then defers the
/// free-vs-Pro decision to [FeatureGateService.requiresPro].
///
/// **SoT boundary**: this class owns only the *path → feature* mapping. It does
/// NOT decide which features are Pro — that remains [FeatureGateService]. This
/// avoids the freemium policy drifting across two places.
///
/// Free tier may reach ONLY:
/// - Products module (add/edit/delete, metadata) — except barcode label design.
/// - Sales / POS (create + view own receipts) — except returns.
/// - Barcode scanning (POS lookup).
/// - Basic settings — except backup/restore and admin tools.
/// - System / auth / dashboard landing.
///
/// Everything else is locked until the user upgrades.
class ProRoutePolicy {
  ProRoutePolicy._();

  /// Paths that are never gated (system, auth, neutral landing, the paywall
  /// route itself). Matched exactly.
  static const List<String> _ungated = <String>[
    '/',
    '/splash',
    '/welcome',
    '/login',
    '/forgot-password',
    '/setup',
    '/access-denied',
    '/upgrade',
    '/dashboard',
  ];

  /// Most-specific Pro overrides nested under otherwise-free prefixes.
  /// Checked BEFORE [_sections] so the nested rule wins.
  static const Map<String, AppFeature> _overrides = <String, AppFeature>{
    '/products/barcode-design': AppFeature.barcodePrint,
    '/sales/returns': AppFeature.returns,
    '/settings/backup': AppFeature.backupRestore,
    '/settings/admin-tools': AppFeature.multiUser,
  };

  /// Top-level section prefixes → governing feature.
  static const Map<String, AppFeature> _sections = <String, AppFeature>{
    // Free sections
    '/products': AppFeature.productsManage,
    '/sales': AppFeature.salesCreate,
    '/barcode-scanner': AppFeature.barcodeScan,
    '/settings': AppFeature.basicSettings,
    // Pro sections
    '/barcode-designer': AppFeature.barcodePrint,
    '/customers': AppFeature.customers,
    '/suppliers': AppFeature.suppliers,
    '/purchases': AppFeature.purchases,
    '/expenses': AppFeature.accounting,
    '/reports': AppFeature.reports,
    '/users': AppFeature.multiUser,
    '/employees': AppFeature.employees,
    '/cashier-shifts': AppFeature.cashierShifts,
    '/client-session': AppFeature.cashierShifts,
    '/financial-management': AppFeature.accounting,
    '/accounting': AppFeature.accounting,
    '/audit': AppFeature.multiUser,
  };

  static bool _matches(String path, String prefix) =>
      path == prefix || path.startsWith('$prefix/');

  /// The feature governing [path], or `null` when the path is never gated.
  static AppFeature? featureFor(String path) {
    if (_ungated.contains(path)) return null;

    for (final entry in _overrides.entries) {
      if (_matches(path, entry.key)) return entry.value;
    }

    // Most specific (longest) prefix wins.
    final prefixes = _sections.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final prefix in prefixes) {
      if (_matches(path, prefix)) return _sections[prefix];
    }

    // Unknown path: do not lock (role permissions still apply elsewhere).
    return null;
  }

  /// Whether [path] requires a Pro subscription, per the [FeatureGateService]
  /// tier table. Free / ungated paths return `false`.
  static bool requiresPro(String path) {
    final feature = featureFor(path);
    if (feature == null) return false;
    return FeatureGateService.requiresPro(feature);
  }
}
