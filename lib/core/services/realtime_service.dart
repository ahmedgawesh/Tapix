import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';

/// Configuration for stream behavior
class StreamConfig {
  final Duration debounceDuration;
  final int maxRetries;
  final Duration retryDelay;

  const StreamConfig({
    this.debounceDuration = const Duration(milliseconds: 50),
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
  });

  /// Platform-adaptive configuration
  factory StreamConfig.adaptive() {
    if (kIsWeb) {
      return const StreamConfig(
        debounceDuration: Duration(milliseconds: 100),
        maxRetries: 5,
        retryDelay: Duration(seconds: 2),
      );
    }
    return const StreamConfig();
  }
}

/// Error wrapper for stream failures
class StreamError {
  final Object error;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final int retryCount;

  StreamError({required this.error, this.stackTrace, required this.retryCount})
    : timestamp = DateTime.now();

  @override
  String toString() => 'StreamError(error: $error, retryCount: $retryCount)';
}

/// Callback type for stream error handling
typedef StreamErrorCallback = void Function(StreamError error);

/// Service for managing real-time database streams with error handling,
/// retry logic, and debouncing.
class RealtimeService {
  final AppDatabase _database;
  final StreamConfig _config;
  final Map<String, StreamController<dynamic>> _controllers = {};
  final Map<String, StreamSubscription<dynamic>> _subscriptions = {};
  final Map<String, int> _retryCounts = {};
  final Map<String, Object?> _lastEmitted = {};
  final Map<String, Timer> _retryTimers = {};
  bool _isDisposed = false;

  StreamErrorCallback? onError;

  RealtimeService(this._database, {StreamConfig? config})
    : _config = config ?? StreamConfig.adaptive();

  /// Watch all active products with debouncing
  Stream<List<Product>> watchProducts() {
    return _createManagedStream<List<Product>>(
      'products',
      () => _database.productDao.watchAllProducts(),
    );
  }

  /// Watch a single product by ID
  Stream<Product?> watchProduct(int id) {
    return _createManagedStream<Product?>(
      'product_$id',
      () => _database.productDao.watchProduct(id),
    );
  }

  /// Watch all sales
  Stream<List<Sale>> watchSales() {
    return _createManagedStream<List<Sale>>(
      'sales',
      () => _database.saleDao.watchAllSales(),
    );
  }

  Stream<List<Purchase>> watchPurchases() {
    return _createManagedStream<List<Purchase>>(
      'purchases',
      () =>
          (_database.select(_database.purchases)..orderBy([
                (p) => OrderingTerm(
                  expression: p.purchaseDate,
                  mode: OrderingMode.desc,
                ),
              ]))
              .watch(),
    );
  }

  Stream<List<Purchase>> watchSupplierPurchases(int supplierId) {
    return _createManagedStream<List<Purchase>>(
      'supplier_purchases_$supplierId',
      () =>
          (_database.select(_database.purchases)
                ..where((p) => p.supplierId.equals(supplierId))
                ..orderBy([
                  (p) => OrderingTerm(
                    expression: p.purchaseDate,
                    mode: OrderingMode.desc,
                  ),
                ]))
              .watch(),
    );
  }

  /// Watch sales for a specific customer
  Stream<List<Sale>> watchCustomerSales(int customerId) {
    return _createManagedStream<List<Sale>>(
      'customer_sales_$customerId',
      () => _database.saleDao.watchCustomerSales(customerId),
    );
  }

  /// Watch all active customers
  Stream<List<Customer>> watchCustomers() {
    return _createManagedStream<List<Customer>>(
      'customers',
      () => _database.customerDao.watchAllCustomers(),
    );
  }

  Stream<List<Supplier>> watchSuppliers() {
    return _createManagedStream<List<Supplier>>(
      'suppliers',
      () =>
          (_database.select(_database.suppliers)
                ..where((s) => s.isActive.equals(true))
                ..orderBy([(s) => OrderingTerm(expression: s.name)]))
              .watch(),
    );
  }

  Stream<Supplier?> watchSupplier(int id) {
    return _createManagedStream<Supplier?>(
      'supplier_$id',
      () => (_database.select(
        _database.suppliers,
      )..where((s) => s.id.equals(id))).watchSingleOrNull(),
    );
  }

  /// Watch a single customer by ID
  Stream<Customer?> watchCustomer(int id) {
    return _createManagedStream<Customer?>(
      'customer_$id',
      () => _database.customerDao.watchCustomer(id),
    );
  }

  /// Watch product categories
  Stream<List<ProductCategory>> watchCategories() {
    return _createManagedStream<List<ProductCategory>>(
      'categories',
      () => _database.productDao.watchCategories(),
    );
  }

  /// Watch product variants for a specific product
  Stream<List<ProductVariant>> watchProductVariants(int productId) {
    return _createManagedStream<List<ProductVariant>>(
      'product_variants_$productId',
      () => _database.productDao.watchProductVariants(productId),
    );
  }

  /// Watch sale items for a specific sale
  Stream<List<SaleItem>> watchSaleItems(int saleId) {
    return _createManagedStream<List<SaleItem>>(
      'sale_items_$saleId',
      () => _database.saleDao.watchSaleItems(saleId),
    );
  }

  /// Watch customer transactions
  Stream<List<CustomerTransaction>> watchCustomerTransactions(int customerId) {
    return _createManagedStream<List<CustomerTransaction>>(
      'customer_transactions_$customerId',
      () => _database.customerDao.watchCustomerTransactions(customerId),
    );
  }

  /// Creates a managed stream with error handling, retry logic, and debouncing
  Stream<T> _createManagedStream<T>(
    String key,
    Stream<T> Function() streamFactory,
  ) {
    if (_controllers.containsKey(key)) {
      return (_controllers[key] as StreamController<T>).stream;
    }

    // ignore: close_sinks - Managed and closed in dispose()
    final controller = StreamController<T>.broadcast(
      onListen: () => _startSubscription<T>(key, streamFactory),
      onCancel: () {
        _cancelSubscription(key);
        _closeControllerIfUnused(key);
      },
    );

    _controllers[key] = controller;
    _retryCounts[key] = 0;

    return controller.stream;
  }

  void _startSubscription<T>(String key, Stream<T> Function() streamFactory) {
    if (_isDisposed) {
      return;
    }
    _subscriptions[key]?.cancel();
    _retryTimers[key]?.cancel();
    _retryTimers.remove(key);

    try {
      Stream<T> stream = streamFactory();

      if (_config.debounceDuration.inMilliseconds > 0) {
        stream = stream.transform(
          _DebounceStreamTransformer<T>(_config.debounceDuration),
        );
      }

      _subscriptions[key] = stream.listen(
        (data) {
          _retryCounts[key] = 0;
          // ignore: close_sinks
          final controller = _controllers[key] as StreamController<T>?;
          if (controller != null && !controller.isClosed) {
            final last = _lastEmitted[key];
            if (!_areEqual(last, data)) {
              _lastEmitted[key] = data as Object?;
              controller.add(data);
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) =>
            _handleError<T>(key, streamFactory, error, stackTrace),
        cancelOnError: false,
      );
    } catch (e, st) {
      _handleError<T>(key, streamFactory, e, st);
    }
  }

  void _handleError<T>(
    String key,
    Stream<T> Function() streamFactory,
    Object error,
    StackTrace stackTrace,
  ) {
    final retryCount = (_retryCounts[key] ?? 0) + 1;
    _retryCounts[key] = retryCount;

    final streamError = StreamError(
      error: error,
      stackTrace: stackTrace,
      retryCount: retryCount,
    );

    onError?.call(streamError);

    debugPrint(
      'RealtimeService: Stream error for $key: $error (retry $retryCount)',
    );

    if (retryCount <= _config.maxRetries) {
      _retryTimers[key]?.cancel();
      _retryTimers[key] = Timer(
        _config.retryDelay * retryCount,
        () => _startSubscription<T>(key, streamFactory),
      );
    } else {
      // ignore: close_sinks
      final controller = _controllers[key] as StreamController<T>?;
      if (controller != null && !controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    }
  }

  void _cancelSubscription(String key) {
    _subscriptions[key]?.cancel();
    _subscriptions.remove(key);
    _retryTimers[key]?.cancel();
    _retryTimers.remove(key);
  }

  /// Cancel a specific stream by key
  void cancelStream(String key) {
    _cancelSubscription(key);
    _controllers[key]?.close();
    _controllers.remove(key);
    _retryCounts.remove(key);
    _lastEmitted.remove(key);
  }

  /// Get active stream count
  int get activeStreamCount => _subscriptions.length;

  /// Dispose all streams and clean up resources
  void dispose() {
    _isDisposed = true;
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();

    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();

    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();

    _retryCounts.clear();
    _lastEmitted.clear();
  }

  void _closeControllerIfUnused(String key) {
    final controller = _controllers[key];
    if (controller is StreamController<dynamic> && !controller.hasListener) {
      controller.close();
      _controllers.remove(key);
      _retryCounts.remove(key);
      _lastEmitted.remove(key);
    }
  }

  bool _areEqual(Object? a, Object? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }
}

class _DebounceStreamTransformer<T> extends StreamTransformerBase<T, T> {
  final Duration duration;

  _DebounceStreamTransformer(this.duration);

  @override
  Stream<T> bind(Stream<T> stream) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    T? lastValue;
    var hasValue = false;

    controller = StreamController<T>.broadcast(
      onListen: () {
        subscription = stream.listen(
          (value) {
            lastValue = value;
            hasValue = true;
            timer?.cancel();
            timer = Timer(duration, () {
              if (hasValue && !controller.isClosed) {
                controller.add(lastValue as T);
              }
            });
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            if (hasValue && !controller.isClosed) {
              controller.add(lastValue as T);
            }
            controller.close();
          },
        );
      },
      onCancel: () async {
        timer?.cancel();
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }
}
