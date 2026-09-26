import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feature_gate_service.dart';
import 'local_integrity_key_service.dart';

/// Thrown when a free-tier user has exhausted a cumulative quota.
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

enum FreeQuotaKind { products, sales }

class FreeQuotaStatus {
  final int productsCreatedLifetime;
  final int salesCreatedLifetime;
  final int? productsLimit;
  final int? salesLimit;

  const FreeQuotaStatus({
    required this.productsCreatedLifetime,
    required this.salesCreatedLifetime,
    required this.productsLimit,
    required this.salesLimit,
  });

  int? get productsRemaining => productsLimit == null
      ? null
      : (productsLimit! - productsCreatedLifetime).clamp(0, productsLimit!);

  int? get salesRemaining => salesLimit == null
      ? null
      : (salesLimit! - salesCreatedLifetime).clamp(0, salesLimit!);

  bool get productsExhausted =>
      productsLimit != null && productsCreatedLifetime >= productsLimit!;

  bool get salesExhausted =>
      salesLimit != null && salesCreatedLifetime >= salesLimit!;

  bool get isUnlimited => productsLimit == null && salesLimit == null;
}

/// Storage boundary for the signed cumulative quota state.
abstract interface class FreeQuotaStateStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

class SecureFreeQuotaStateStore implements FreeQuotaStateStore {
  static const _key = 'tapix.free_quota_state.v1';
  final FlutterSecureStorage _storage;

  SecureFreeQuotaStateStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

typedef FreeQuotaUsageReader = Future<({int products, int sales})> Function();

/// Enforces cumulative free-tier limits.
///
/// Production stores one signed state in platform secure storage. The old
/// SharedPreferences counters remain mirrors for backwards compatibility and
/// are imported once during upgrade; they are no longer the authority. At
/// startup the state is reconciled upwards with live database counts, so a
/// crash after committing a product/sale cannot lose quota usage. Deleting or
/// voiding a row never decrements the lifetime counters.
class FreeQuotaService {
  static const int defaultMaxProductsLifetime = 100;
  static const int defaultMaxSalesLifetime = 100;

  static const String _kProductsKey = 'free_quota.products_created_lifetime';
  static const String _kSalesKey = 'free_quota.sales_created_lifetime';
  static const String _integrityScope = 'tapix.free_quota.v1';
  static const int _stateVersion = 1;

  final SharedPreferences _prefs;
  final FeatureGateService _featureGateService;
  final FreeQuotaStateStore? _stateStore;
  final LocalIntegritySigner? _integritySigner;
  final FreeQuotaUsageReader? _usageReader;

  final int maxProductsLifetime;
  final int maxSalesLifetime;

  late int _productsCreatedLifetime;
  late int _salesCreatedLifetime;
  late bool _initialized;

  FreeQuotaService({
    required SharedPreferences prefs,
    required FeatureGateService featureGateService,
    FreeQuotaStateStore? stateStore,
    LocalIntegritySigner? integritySigner,
    FreeQuotaUsageReader? usageReader,
    this.maxProductsLifetime = defaultMaxProductsLifetime,
    this.maxSalesLifetime = defaultMaxSalesLifetime,
  }) : _prefs = prefs,
       _featureGateService = featureGateService,
       _stateStore = stateStore,
       _integritySigner = integritySigner,
       _usageReader = usageReader {
    _productsCreatedLifetime = _nonNegative(_prefs.getInt(_kProductsKey) ?? 0);
    _salesCreatedLifetime = _nonNegative(_prefs.getInt(_kSalesKey) ?? 0);
    _initialized = _stateStore == null;
  }

  /// Loads and verifies secure state, imports legacy counters, and reconciles
  /// committed rows that may have preceded a crash before counter persistence.
  Future<void> initialize() async {
    if (_initialized) return;
    final store = _stateStore!;
    final signer = _integritySigner;
    if (signer == null || !signer.isReady) {
      throw StateError('FreeQuotaService requires an initialized signer.');
    }

    final live = await _readLiveUsage();
    String? encoded;
    var secureStoreAvailable = true;
    try {
      encoded = await store.read();
    } on Object catch (error, stackTrace) {
      secureStoreAvailable = false;
      developer.log(
        'Secure quota state is unavailable; free-tier limits fail closed.',
        name: 'FreeQuotaService',
        error: error,
        stackTrace: stackTrace,
      );
    }
    var products = _productsCreatedLifetime;
    var sales = _salesCreatedLifetime;
    var trustedState = false;

    if (!secureStoreAvailable) {
      products = _max(live.products, maxProductsLifetime);
      sales = _max(live.sales, maxSalesLifetime);
    }

    if (encoded != null && encoded.isNotEmpty) {
      try {
        final json = jsonDecode(encoded) as Map<String, dynamic>;
        final version = (json['version'] as num?)?.toInt() ?? 0;
        final storedProducts = _nonNegative(
          (json['products'] as num?)?.toInt() ?? 0,
        );
        final storedSales = _nonNegative((json['sales'] as num?)?.toInt() ?? 0);
        final signature = json['signature'] as String? ?? '';
        trustedState =
            version == _stateVersion &&
            signer.verify(
              _integrityScope,
              _payload(storedProducts, storedSales),
              signature,
            );
        if (trustedState) {
          products = storedProducts;
          sales = storedSales;
        }
      } on Object catch (error) {
        if (kDebugMode) {
          debugPrint('FreeQuota: invalid secure state: $error');
        }
      }

      if (!trustedState) {
        // A present but invalid signed state fails closed. Live counts are
        // still retained when already above the configured free limit.
        products = live.products.clamp(maxProductsLifetime, 0x7fffffff);
        sales = live.sales.clamp(maxSalesLifetime, 0x7fffffff);
      }
    }

    _productsCreatedLifetime = _max(products, live.products);
    _salesCreatedLifetime = _max(sales, live.sales);
    _initialized = true;
    await _persist();
  }

  int get productsCreatedLifetime {
    _ensureInitialized();
    return _productsCreatedLifetime;
  }

  int get salesCreatedLifetime {
    _ensureInitialized();
    return _salesCreatedLifetime;
  }

  FreeQuotaStatus status() {
    final isPro = _featureGateService.isPro;
    return FreeQuotaStatus(
      productsCreatedLifetime: productsCreatedLifetime,
      salesCreatedLifetime: salesCreatedLifetime,
      productsLimit: isPro ? null : maxProductsLifetime,
      salesLimit: isPro ? null : maxSalesLifetime,
    );
  }

  bool canCreateProduct() =>
      _featureGateService.isPro ||
      productsCreatedLifetime < maxProductsLifetime;

  bool canCreateSale() =>
      _featureGateService.isPro || salesCreatedLifetime < maxSalesLifetime;

  void guardProductCreation() => guardProductCreations(1);

  void guardProductCreations(int count) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    if (_featureGateService.isPro) return;
    final current = productsCreatedLifetime;
    if (current + count > maxProductsLifetime) {
      throw FreeQuotaExceededException(
        kind: FreeQuotaKind.products,
        limit: maxProductsLifetime,
        currentCount: current,
      );
    }
  }

  void guardSaleCreation() {
    if (_featureGateService.isPro) return;
    final current = salesCreatedLifetime;
    if (current >= maxSalesLifetime) {
      throw FreeQuotaExceededException(
        kind: FreeQuotaKind.sales,
        limit: maxSalesLifetime,
        currentCount: current,
      );
    }
  }

  Future<void> incrementProductsCreated() => incrementProductsCreatedBy(1);

  Future<void> incrementProductsCreatedBy(int count) async {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    _ensureInitialized();
    _productsCreatedLifetime += count;
    await _persist();
    if (kDebugMode) {
      debugPrint(
        'FreeQuota: products lifetime → '
        '$_productsCreatedLifetime / $maxProductsLifetime',
      );
    }
  }

  /// Compensates a counter changed inside a database transaction that rolled
  /// back. Callers snapshot after entering their serialized DB transaction.
  Future<void> restoreProductsCreatedAfterRollback(int snapshot) async {
    if (snapshot < 0) {
      throw ArgumentError.value(snapshot, 'snapshot', 'must not be negative');
    }
    _ensureInitialized();
    _productsCreatedLifetime = snapshot;
    await _persist();
  }

  Future<void> incrementSalesCreated() async {
    _ensureInitialized();
    _salesCreatedLifetime += 1;
    await _persist();
    if (kDebugMode) {
      debugPrint(
        'FreeQuota: sales lifetime → '
        '$_salesCreatedLifetime / $maxSalesLifetime',
      );
    }
  }

  Future<({int products, int sales})> _readLiveUsage() async {
    final reader = _usageReader;
    if (reader == null) return (products: 0, sales: 0);
    final usage = await reader();
    return (
      products: _nonNegative(usage.products),
      sales: _nonNegative(usage.sales),
    );
  }

  Future<void> _persist() async {
    final signer = _integritySigner;
    final store = _stateStore;
    if (signer != null && store != null) {
      final signature = signer.sign(
        _integrityScope,
        _payload(_productsCreatedLifetime, _salesCreatedLifetime),
      );
      try {
        await store.write(
          jsonEncode({
            'version': _stateVersion,
            'products': _productsCreatedLifetime,
            'sales': _salesCreatedLifetime,
            'signature': signature,
          }),
        );
      } on Object catch (error, stackTrace) {
        developer.log(
          'Could not persist secure quota state.',
          name: 'FreeQuotaService',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    // Compatibility mirrors. Security decisions never read these after the
    // signed secure state has been created.
    await _prefs.setInt(_kProductsKey, _productsCreatedLifetime);
    await _prefs.setInt(_kSalesKey, _salesCreatedLifetime);
  }

  String _payload(int products, int sales) => '$_stateVersion|$products|$sales';

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('FreeQuotaService.initialize() must complete first.');
    }
  }

  static int _nonNegative(int value) => value < 0 ? 0 : value;

  static int _max(int a, int b) => a > b ? a : b;

  @visibleForTesting
  Future<void> resetCountersForTesting() async {
    _productsCreatedLifetime = 0;
    _salesCreatedLifetime = 0;
    _initialized = true;
    await _stateStore?.delete();
    await _prefs.remove(_kProductsKey);
    await _prefs.remove(_kSalesKey);
  }
}
