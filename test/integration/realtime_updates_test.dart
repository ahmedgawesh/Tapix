import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/realtime_service.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/data/repositories/product_repository_impl.dart';
import 'package:tapix/features/products/data/datasources/product_local_datasource.dart';
import 'package:tapix/features/products/presentation/bloc/products_bloc.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';

void main() {
  group('End-to-End Realtime Updates', () {
    late AppDatabase database;
    late RealtimeService realtimeService;
    late ProductRepository productRepository;
    late ProductsBloc productsBloc;
    late int currencyId;

    setUp(() async {
      database = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      realtimeService = RealtimeService(database);
      productRepository = ProductRepositoryImpl(
        ProductLocalDatasourceImpl(database.productDao),
        AuditLogService(database),
        SessionService(),
      );
      productsBloc = ProductsBloc(productRepository);

      currencyId = await database
          .into(database.currencies)
          .insert(
            CurrenciesCompanion.insert(
              code: 'TST',
              name: 'Test Currency',
              symbol: 'T',
              exchangeRate: Decimal.fromInt(1),
            ),
          );
    });

    tearDown(() async {
      await productsBloc.close();
      realtimeService.dispose();
      await database.close();
    });

    test('Database → RealtimeService → UI flow works correctly', () async {
      final emissions = <List<Product>>[];
      final subscription = realtimeService.watchProducts().listen(
        emissions.add,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(emissions.last, isEmpty);

      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('E2E-001'),
              name: 'End-to-End Product',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              currencyId: Value(currencyId),
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      await subscription.cancel();

      expect(emissions.last.length, equals(1));
      expect(emissions.last.first.name, equals('End-to-End Product'));
    });

    test('Database → ProductsBloc → State flow works correctly', () async {
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(productsBloc.currentData, isEmpty);

      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('BLOC-001'),
              name: 'Bloc Test Product',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              currencyId: Value(currencyId),
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(productsBloc.hasData, isTrue);
      expect(productsBloc.currentData?.length, equals(1));
      expect(productsBloc.currentData?.first.name, equals('Bloc Test Product'));
    });

    test('Multiple rapid database changes are handled correctly', () async {
      await Future<void>.delayed(const Duration(milliseconds: 100));

      for (int i = 1; i <= 10; i++) {
        await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: Value<String?>('RAPID-$i'),
                name: 'Rapid Product $i',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );
      }

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(productsBloc.currentData?.length, equals(10));
    });

    test('Product updates propagate to bloc state', () async {
      final productId = await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('UPDATE-001'),
              name: 'Original Name',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              currencyId: Value(currencyId),
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(productsBloc.currentData?.first.name, equals('Original Name'));

      await (database.update(database.products)
            ..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(name: Value('Updated Name')));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(productsBloc.currentData?.first.name, equals('Updated Name'));
    });

    test('Product deletion propagates to bloc state', () async {
      final productId = await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('DELETE-001'),
              name: 'To Be Deleted',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              currencyId: Value(currencyId),
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(productsBloc.currentData?.length, equals(1));

      await (database.update(database.products)
            ..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(isActive: Value(false)));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(productsBloc.currentData, isEmpty);
    });
  });

  group('Performance Tests', () {
    late AppDatabase database;
    late ProductRepository productRepository;
    late ProductsBloc productsBloc;
    late int currencyId;

    setUp(() async {
      database = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      productRepository = ProductRepositoryImpl(
        ProductLocalDatasourceImpl(database.productDao),
        AuditLogService(database),
        SessionService(),
      ); // Use Impl
      productsBloc = ProductsBloc(productRepository);

      currencyId = await database
          .into(database.currencies)
          .insert(
            CurrenciesCompanion.insert(
              code: 'TST',
              name: 'Test Currency',
              symbol: 'T',
              exchangeRate: Decimal.fromInt(1),
            ),
          );
    });

    tearDown(() async {
      await productsBloc.close();
      await database.close();
    });

    test('Update latency is under 100ms', () async {
      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('PERF-001'),
              name: 'Performance Test',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              currencyId: Value(currencyId),
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      final stopwatch = Stopwatch()..start();
      bool updateReceived = false;

      final originalName = productsBloc.currentData?.first.name;

      await (database.update(database.products)
            ..where((p) => p.sku.equals('PERF-001')))
          .write(const ProductsCompanion(name: Value('Updated for Perf')));

      while (!updateReceived && stopwatch.elapsedMilliseconds < 1000) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (productsBloc.currentData?.first.name != originalName) {
          updateReceived = true;
        }
      }

      stopwatch.stop();

      expect(updateReceived, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('Handles 100 products without performance degradation', () async {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 100; i++) {
        await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: Value<String?>('BULK-$i'),
                name: 'Bulk Product $i',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));

      stopwatch.stop();

      expect(productsBloc.currentData?.length, equals(100));
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('Memory Leak Tests', () {
    test('No retained streams after bloc disposal', () async {
      final database = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      final realtimeService = RealtimeService(database);
      final productRepository = ProductRepositoryImpl(
        ProductLocalDatasourceImpl(database.productDao),
        AuditLogService(database),
        SessionService(),
      ); // Use Impl
      final productsBloc = ProductsBloc(productRepository);

      final currencyId = await database
          .into(database.currencies)
          .insert(
            CurrenciesCompanion.insert(
              code: 'TST',
              name: 'Test Currency',
              symbol: 'T',
              exchangeRate: Decimal.fromInt(1),
            ),
          );

      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('MEM-001'),
              name: 'Memory Test',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              currencyId: Value(currencyId),
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(productsBloc.hasData, isTrue);

      await productsBloc.close();

      expect(productsBloc.isClosed, isTrue);

      realtimeService.dispose();
      expect(realtimeService.activeStreamCount, equals(0));

      await database.close();
    });

    test('Multiple bloc creation and disposal does not leak', () async {
      final database = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );

      for (int i = 0; i < 10; i++) {
        final productRepository = ProductRepositoryImpl(
          ProductLocalDatasourceImpl(database.productDao),
          AuditLogService(database),
          SessionService(),
        ); // Use Impl
        final bloc = ProductsBloc(productRepository);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await bloc.close();
      }

      await database.close();
    });
  });
}
