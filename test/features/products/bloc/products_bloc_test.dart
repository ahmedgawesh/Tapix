import 'package:tapix/features/products/data/repositories/product_variant_repository_impl.dart';
import 'package:tapix/features/products/data/datasources/variant_local_datasource.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart' hide Product;
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/data/repositories/product_repository_impl.dart';
import 'package:tapix/features/products/data/datasources/product_local_datasource.dart';
import 'package:tapix/features/products/presentation/bloc/products_bloc.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';

void main() {
  group('ProductsBloc', () {
    late AppDatabase database;
    late ProductRepository repository;
    late ProductsBloc bloc;
    late int currencyId;

    setUp(() async {
      database = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      await database.customStatement(
        "INSERT OR IGNORE INTO users (id, username, password_hash, role, is_active, created_at, updated_at) VALUES (0, 'system', 'no-pin', 'owner', 1, 0, 0)",
      );

      currencyId = (await (database.select(
        database.currencies,
      )..where((currency) => currency.code.equals('USD'))).getSingle()).id;
      await BranchCurrencyPolicyStore(database).bind('USD');
      repository = ProductRepositoryImpl(
        ProductLocalDatasourceImpl(database.productDao),
        AuditLogService(database),
        SessionService(),
      );
      final variants = ProductVariantRepositoryImpl(
        VariantLocalDatasourceImpl(
          database.productVariantDao,
          database.productColorDao,
          database.sizeDao,
        ),
        InventoryAdjustmentService(
          db: database,
          dao: InventoryAdjustmentDao(database),
          journal: JournalEntryService(AccountingRepository(database)),
        ),
      );
      bloc = ProductsBloc(repository, null, null, variants);
    });

    tearDown(() async {
      await bloc.close();
      await database.close();
    });

    test('initial state is RealtimeLoading', () {
      expect(bloc.state, isA<RealtimeLoading<List<Product>>>());
    });

    test('emits RealtimeSuccess after stream emits data', () async {
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(bloc.state, isA<RealtimeSuccess<List<Product>>>());
      expect(bloc.currentData, isEmpty);
    });

    test('currentSearchQuery is null initially', () {
      expect(bloc.currentSearchQuery, isNull);
    });

    group('ProductCreateRequested', () {
      test('creates product and stream updates state', () async {
        await Future<void>.delayed(const Duration(milliseconds: 100));

        bloc.add(
          ProductCreateRequested(
            sku: 'CREATE-001',
            name: 'Created Product',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            currencyId: currencyId,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(bloc.currentData?.length, equals(1));
        expect(bloc.currentData?.first.name, equals('Created Product'));
      });

      test('creates product with all optional fields', () async {
        await Future<void>.delayed(const Duration(milliseconds: 100));

        bloc.add(
          ProductCreateRequested(
            sku: 'CREATE-002',
            name: 'Full Product',
            description: 'A detailed description',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            currencyId: currencyId,
            trackInventory: true,
            stockQuantity: 50,
            minQuantity: 10,
            hasVariants: false,
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(bloc.currentData?.length, equals(1));
        expect(
          bloc.currentData?.first.description,
          equals('A detailed description'),
        );
        expect(bloc.currentData?.first.stockQuantity, equals(50));
        expect(
          await database.select(database.inventoryAdjustments).get(),
          hasLength(1),
        );
        final journal = await database
            .customSelect(
              'SELECT SUM(debit_cents) AS dr, SUM(credit_cents) AS cr FROM journal_entry_lines',
            )
            .getSingle();
        expect(journal.read<int>('dr'), 5000);
        expect(journal.read<int>('cr'), 5000);
      });
    });

    group('ProductUpdateRequested', () {
      test('updates product optimistically', () async {
        await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('UPDATE-001'),
                name: 'Original',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );

        await Future<void>.delayed(const Duration(milliseconds: 200));

        final original = bloc.currentData!.first;
        final updated = original.copyWith(name: 'Updated');

        bloc.add(ProductUpdateRequested(updated));

        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(bloc.currentData?.first.name, equals('Updated'));
      });
    });

    group('ProductDeleteRequested', () {
      test('deletes product optimistically', () async {
        final productId = await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('DELETE-001'),
                name: 'To Delete',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );

        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(bloc.currentData?.length, equals(1));

        bloc.add(ProductDeleteRequested(productId));

        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(bloc.currentData, isEmpty);
      });
    });

    group('ProductSearchRequested', () {
      test('searches products and updates state', () async {
        await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('SEARCH-001'),
                name: 'Apple Phone',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );

        await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('SEARCH-002'),
                name: 'Samsung Phone',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );

        await Future<void>.delayed(const Duration(milliseconds: 200));

        bloc.add(const ProductSearchRequested('Apple'));

        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(bloc.currentSearchQuery, equals('Apple'));
        expect(bloc.currentData?.length, equals(1));
        expect(bloc.currentData?.first.name, equals('Apple Phone'));
      });

      test('empty search clears query and refreshes', () async {
        await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('SEARCH-003'),
                name: 'Test Product',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );

        await Future<void>.delayed(const Duration(milliseconds: 200));

        bloc.add(const ProductSearchRequested('Test'));
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(bloc.currentSearchQuery, equals('Test'));

        bloc.add(const ProductSearchRequested(''));
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(bloc.currentSearchQuery, isNull);
      });

      test('clearSearch resets to full list', () async {
        await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('CLEAR-001'),
                name: 'Product One',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );

        await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('CLEAR-002'),
                name: 'Product Two',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );

        await Future<void>.delayed(const Duration(milliseconds: 200));

        bloc.add(const ProductSearchRequested('One'));
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(bloc.currentData?.length, equals(1));

        bloc.clearSearch();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(bloc.currentSearchQuery, isNull);
      });
    });

    group('Refresh', () {
      test('refresh resubscribes to stream', () async {
        await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('REFRESH-001'),
                name: 'Refresh Test',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currencyId),
              ),
            );

        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(bloc.currentData?.length, equals(1));

        bloc.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(bloc.hasData, isTrue);
        expect(bloc.currentData?.length, equals(1));
      });
    });
  });

  group('ProductsEvent', () {
    test('ProductCreateRequested equality', () {
      final event1 = ProductCreateRequested(
        sku: 'SKU-001',
        name: 'Product',
        costCents: Decimal.fromInt(100),
        priceCents: Decimal.fromInt(200),
        currencyId: 1,
      );

      final event2 = ProductCreateRequested(
        sku: 'SKU-001',
        name: 'Product',
        costCents: Decimal.fromInt(100),
        priceCents: Decimal.fromInt(200),
        currencyId: 1,
      );

      expect(event1.sku, equals(event2.sku));
      expect(event1.name, equals(event2.name));
    });

    test('ProductSearchRequested with query', () {
      const event = ProductSearchRequested('search term');
      expect(event.query, equals('search term'));
    });

    test('ProductDeleteRequested with id', () {
      const event = ProductDeleteRequested(42);
      expect(event.productId, equals(42));
    });
  });
}
