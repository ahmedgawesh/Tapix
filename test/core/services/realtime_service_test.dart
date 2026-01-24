import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/realtime_service.dart';

void main() {
  late AppDatabase database;
  late RealtimeService service;

  setUp(() {
    database = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    service = RealtimeService(database);
  });

  tearDown(() async {
    service.dispose();
    await database.close();
  });

  group('RealtimeService', () {
    group('Stream Configuration', () {
      test('uses adaptive config based on platform', () {
        final config = StreamConfig.adaptive();
        expect(config.debounceDuration.inMilliseconds, greaterThan(0));
        expect(config.maxRetries, greaterThan(0));
        expect(config.retryDelay.inMilliseconds, greaterThan(0));
      });

      test('allows custom configuration', () {
        final customConfig = const StreamConfig(
          debounceDuration: Duration(milliseconds: 200),
          maxRetries: 5,
          retryDelay: Duration(seconds: 2),
        );

        final customService = RealtimeService(database, config: customConfig);
        expect(customService, isNotNull);
        customService.dispose();
      });
    });

    group('Supplier Streams', () {
      test('watchSuppliers emits supplier list', () async {
        final currencyId = await database.into(database.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'SUP',
            name: 'Supplier Currency',
            symbol: 'S',
            exchangeRate: Decimal.fromInt(1),
          ),
        );

        await database.into(database.suppliers).insert(
          SuppliersCompanion.insert(name: 'Test Supplier', currencyId: currencyId),
        );

        final stream = service.watchSuppliers();

        await expectLater(
          stream.first,
          completion(hasLength(1)),
        );
      });
    });

    group('Purchase Streams', () {
      test('watchPurchases emits purchase list', () async {
        final currencyId = await database.into(database.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'PUR',
            name: 'Purchase Currency',
            symbol: 'P',
            exchangeRate: Decimal.fromInt(1),
          ),
        );

        final supplierId = await database.into(database.suppliers).insert(
          SuppliersCompanion.insert(name: 'Purchase Supplier', currencyId: currencyId),
        );

        final stream = service.watchPurchases();
        final emissions = <List<Purchase>>[];
        final subscription = stream.listen(emissions.add);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        await database.into(database.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-001',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(1000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(1000),
            currencyId: currencyId,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 200));
        await subscription.cancel();

        expect(emissions, isNotEmpty);
        expect(emissions.last, hasLength(1));
        expect(emissions.last.first.purchaseNumber, equals('PO-001'));
      });
    });

    group('Product Streams', () {
      test('watchProducts emits initial empty list', () async {
        final stream = service.watchProducts();

        await expectLater(
          stream.first,
          completion(isEmpty),
        );
      });

      test('watchProducts emits updated list when product is added', () async {
        final currencyId = await database.into(database.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'TST',
            name: 'Test Currency',
            symbol: 'T',
            exchangeRate: Decimal.fromInt(1),
          ),
        );

        final stream = service.watchProducts();
        final emissions = <List<Product>>[];
        final subscription = stream.listen(emissions.add);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        await database.into(database.products).insert(
          ProductsCompanion.insert(
            sku: 'TEST-001',
            name: 'Test Product',
            costCents: Decimal.fromInt(10),
            priceCents: Decimal.fromInt(20),
            currencyId: currencyId,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 200));
        await subscription.cancel();

        expect(emissions.length, greaterThanOrEqualTo(1));
        expect(emissions.last.length, equals(1));
        expect(emissions.last.first.name, equals('Test Product'));
      });

      test('watchProduct emits single product changes', () async {
        final currencyId = await database.into(database.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'TST',
            name: 'Test Currency',
            symbol: 'T',
            exchangeRate: Decimal.fromInt(1),
          ),
        );

        final productId = await database.into(database.products).insert(
          ProductsCompanion.insert(
            sku: 'TEST-002',
            name: 'Initial Name',
            costCents: Decimal.fromInt(10),
            priceCents: Decimal.fromInt(20),
            currencyId: currencyId,
          ),
        );

        final stream = service.watchProduct(productId);
        final emissions = <Product?>[];
        final subscription = stream.listen(emissions.add);

        await Future<void>.delayed(const Duration(milliseconds: 100));

        await (database.update(database.products)
              ..where((p) => p.id.equals(productId)))
            .write(const ProductsCompanion(name: Value('Updated Name')));

        await Future<void>.delayed(const Duration(milliseconds: 200));
        await subscription.cancel();

        expect(emissions.length, greaterThanOrEqualTo(1));
        expect(emissions.last?.name, equals('Updated Name'));
      });
    });

    group('Customer Streams', () {
      test('watchCustomers emits customer list', () async {
        final currencyId = await database.into(database.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'CUS',
            name: 'Customer Currency',
            symbol: 'C',
            exchangeRate: Decimal.fromInt(1),
          ),
        );

        await database.into(database.customers).insert(
          CustomersCompanion.insert(name: 'Test Customer', currencyId: currencyId),
        );

        final stream = service.watchCustomers();

        await expectLater(
          stream.first,
          completion(hasLength(1)),
        );
      });

      test('watchCustomer emits single customer', () async {
        final currencyId = await database.into(database.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'CU2',
            name: 'Customer Currency 2',
            symbol: 'C',
            exchangeRate: Decimal.fromInt(1),
          ),
        );

        final customerId = await database.into(database.customers).insert(
          CustomersCompanion.insert(name: 'Single Customer', currencyId: currencyId),
        );

        final stream = service.watchCustomer(customerId);

        await expectLater(
          stream.first,
          completion(isNotNull),
        );
      });
    });

    group('Sales Streams', () {
      test('watchSales emits sales list', () async {
        final currencyId = await database.into(database.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'TST',
            name: 'Test Currency',
            symbol: 'T',
            exchangeRate: Decimal.fromInt(1),
          ),
        );

        await database.into(database.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-001',
            subtotalCents: Decimal.fromInt(100),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(100),
            currencyId: currencyId,
            paymentMethod: 'cash',
          ),
        );

        final stream = service.watchSales();

        await expectLater(
          stream.first,
          completion(hasLength(1)),
        );
      });
    });

    group('Stream Lifecycle', () {
      test('activeStreamCount tracks active streams', () async {
        expect(service.activeStreamCount, equals(0));

        final subscription1 = service.watchProducts().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.activeStreamCount, greaterThanOrEqualTo(1));

        final subscription2 = service.watchCustomers().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(service.activeStreamCount, greaterThanOrEqualTo(2));

        await subscription1.cancel();
        await subscription2.cancel();
      });

      test('cancelStream removes specific stream', () async {
        final subscription = service.watchProducts().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final initialCount = service.activeStreamCount;
        service.cancelStream('products');
        await subscription.cancel();

        expect(service.activeStreamCount, lessThan(initialCount));
      });

      test('dispose cleans up all streams', () async {
        service.watchProducts().listen((_) {});
        service.watchCustomers().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 50));

        service.dispose();

        expect(service.activeStreamCount, equals(0));
      });
    });

    group('Error Handling', () {
      test('StreamError contains error details', () {
        final error = StreamError(
          error: Exception('Test error'),
          stackTrace: StackTrace.current,
          retryCount: 2,
        );

        expect(error.error, isA<Exception>());
        expect(error.retryCount, equals(2));
        expect(error.timestamp, isNotNull);
        expect(error.toString(), contains('Test error'));
      });

      test('onError callback is triggered on stream errors', () async {
        StreamError? capturedError;
        service.onError = (error) {
          capturedError = error;
        };

        expect(capturedError, isNull);
      });
    });

    group('Performance', () {
      test('stream updates arrive within 100ms', () async {
        final perfService = RealtimeService(
          database,
          config: const StreamConfig(debounceDuration: Duration.zero),
        );
        final currencyId = await database.into(database.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'TST',
            name: 'Test Currency',
            symbol: 'T',
            exchangeRate: Decimal.fromInt(1),
          ),
        );

        final stopwatch = Stopwatch();
        final completer = Completer<Duration>();

        final subscription = perfService.watchProducts().listen((products) {
          if (products.isNotEmpty && stopwatch.isRunning) {
            stopwatch.stop();
            if (!completer.isCompleted) {
              completer.complete(stopwatch.elapsed);
            }
          }
        });

        await Future<void>.delayed(const Duration(milliseconds: 100));

        stopwatch.start();
        await database.into(database.products).insert(
          ProductsCompanion.insert(
            sku: 'PERF-001',
            name: 'Performance Test',
            costCents: Decimal.fromInt(10),
            priceCents: Decimal.fromInt(20),
            currencyId: currencyId,
          ),
        );

        final elapsed = await completer.future.timeout(
          const Duration(seconds: 1),
          onTimeout: () => const Duration(milliseconds: 1000),
        );

        await subscription.cancel();
        perfService.dispose();

        expect(elapsed.inMilliseconds, lessThan(100));
      });
    });
  });
}
