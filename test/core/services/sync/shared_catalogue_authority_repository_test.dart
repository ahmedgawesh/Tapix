import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/sync/branch_catalogue_sync_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/products/data/datasources/product_local_datasource.dart';
import 'package:tapix/features/products/data/repositories/product_repository_impl.dart';
import 'package:tapix/features/suppliers/data/datasources/supplier_local_datasource.dart';
import 'package:tapix/features/suppliers/data/repositories/supplier_repository_impl.dart';

class _Session extends Fake implements SessionService {
  @override
  Future<int?> getCurrentUserId() async => null;
}

void main() {
  late AppDatabase db;
  late int currencyId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((row) => row.code.equals('USD'))).getSingle()).id;
  });

  tearDown(() => db.close());

  ProductRepositoryImpl products({required bool authority}) =>
      ProductRepositoryImpl(
        ProductLocalDatasourceImpl(db.productDao),
        AuditLogService(db),
        _Session(),
        canEditSharedCatalogue: () async => authority,
        isSharedCatalogueDistributed: () async => true,
      );

  SupplierRepositoryImpl suppliers({required bool authority}) =>
      SupplierRepositoryImpl(
        SupplierLocalDatasourceImpl(db.supplierDao),
        _Session(),
        JournalEntryService(AccountingRepository(db)),
        db,
        AuditLogService(db),
        canEditSharedCatalogue: () async => authority,
        isSharedCatalogueDistributed: () async => true,
      );

  test('independent branch cannot mutate shared product master', () async {
    await expectLater(
      products(authority: false).createProduct(
        name: 'Rejected product',
        costCents: Decimal.fromInt(100),
        priceCents: Decimal.fromInt(200),
        stockQuantity: 0,
        minQuantity: 0,
        currencyId: currencyId,
      ),
      throwsA(isA<SharedCatalogueAuthorityRequired>()),
    );
    expect(await db.select(db.products).get(), isEmpty);
  });

  test('distributed product delete becomes an inactive tombstone', () async {
    final repository = products(authority: true);
    final id = await repository.createProduct(
      name: 'Shared product',
      costCents: Decimal.fromInt(100),
      priceCents: Decimal.fromInt(200),
      stockQuantity: 0,
      minQuantity: 0,
      currencyId: currencyId,
    );

    final result = await repository.smartDeleteProduct(id);

    expect(result.wasDeleted, isFalse);
    final stored = await (db.select(
      db.products,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(stored.isActive, isFalse);
  });

  test('distributed supplier delete becomes an inactive tombstone', () async {
    final repository = suppliers(authority: true);
    final id = await repository.createSupplier(
      name: 'Shared supplier',
      currencyId: currencyId,
      initialBalance: Decimal.zero,
    );

    expect(await repository.deleteSupplier(id), 1);
    final stored = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(stored.isActive, isFalse);
  });

  test('independent branch cannot create a competing supplier', () async {
    await expectLater(
      suppliers(
        authority: false,
      ).createSupplier(name: 'Rejected supplier', currencyId: currencyId),
      throwsA(isA<SharedCatalogueAuthorityRequired>()),
    );
    expect(await db.select(db.suppliers).get(), isEmpty);
  });
}
