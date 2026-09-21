import 'package:tapix/core/services/business/warehouse_read_scope.dart';
import 'package:tapix/core/services/business/warehouse_catalog_scope.dart';
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_stocktake_report_bloc.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:tapix/features/reports/presentation/bloc/inventory_reports_bloc.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  setUp(() async {
    db = fixtures.memoryDb();
    await db.customSelect('SELECT 1').get();
  });
  tearDown(() => db.close());

  Future<int> seed({bool variants = false, bool weight = false}) async {
    final product = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Warehouse report',
            hasVariants: Value(variants),
            measurementType: Value(weight ? 'weight' : 'piece'),
            stockQuantity: const Value(9000),
            minQuantity: const Value(20),
            costCents: Decimal.fromInt(9999),
            priceCents: Decimal.fromInt(1500),
          ),
        );
    final variant = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: product,
            stockQuantity: const Value(10),
            costCents: Decimal.fromInt(701),
            priceCents: Decimal.fromInt(1500),
          ),
        );
    // Test only: disconnect the compatibility mirror to prove reports read
    // the warehouse, even if obsolete display fields differ.
    await db.customStatement('DROP TRIGGER business_stock_primary_update');
    await db.customStatement(
      'UPDATE business_warehouse_stocks SET quantity = 12, unit_cost_cents = 801 WHERE variant_id = ?',
      [variant],
    );
    return variant;
  }

  Future<InventoryReportsData> report() async {
    final bloc = InventoryReportsBloc(db);
    try {
      return await bloc.dataStream.first.timeout(const Duration(seconds: 10));
    } finally {
      await bloc.close();
    }
  }

  Future<int> accounting() => JournalLocalDatasourceImpl(
    AccountingDao(db),
  ).getTotalInventoryValueCents();

  for (final variants in [false, true]) {
    for (final weight in [false, true]) {
      test(
        'warehouse quantity/cost: variants=$variants weight=$weight',
        () async {
          await seed(variants: variants, weight: weight);
          final data = await report();
          final expected = weight ? 10 : 9612;
          expect(data.stockValuation.single.totalStock, 12);
          expect(data.stockValuation.single.costCents, 801);
          expect(data.totalValuationCents, expected);
          expect(await accounting(), expected);
          expect(data.lowStockItems.single.currentStock, 12);
          expect(data.lowStockItems.single.deficit, 8);
        },
      );
    }
  }

  test('secondary warehouse cannot inflate local stock or valuation', () async {
    final variant = await seed();
    final scope = await BusinessFoundationRepository(db).getScope();
    final other = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: other,
            organizationId: scope.organizationId,
            branchId: scope.branchId,
            code: 'SECOND',
          ),
        );
    await db
        .into(db.businessWarehouseStocks)
        .insert(
          BusinessWarehouseStocksCompanion.insert(
            warehouseId: other,
            variantId: variant,
            quantity: const Value(999),
            unitCostCents: const Value(9000),
          ),
        );
    expect((await report()).totalStockUnits, 12);
    expect(await accounting(), 9612);
  });

  test('disabled warehouse remains visible in stock and accounting', () async {
    await seed();
    await db.customStatement('UPDATE business_warehouses SET is_active = 0');
    expect((await report()).totalStockUnits, 12);
    expect(await accounting(), 9612);
  });

  test('warehouse-only writes refresh inventory stream', () async {
    final variant = await seed();
    final bloc = InventoryReportsBloc(db);
    final events = StreamIterator(bloc.dataStream);
    try {
      expect(await events.moveNext(), isTrue);
      expect(events.current.totalStockUnits, 12);
      await (db.update(db.businessWarehouseStocks)
            ..where((s) => s.variantId.equals(variant)))
          .write(const BusinessWarehouseStocksCompanion(quantity: Value(14)));
      do {
        expect(
          await events.moveNext().timeout(const Duration(seconds: 10)),
          isTrue,
        );
      } while (events.current.totalStockUnits != 14);
      expect(events.current.totalValuationCents, 11214);
      expect(events.current.lowStockItems.single.currentStock, 14);
    } finally {
      await events.cancel();
      await bloc.close();
    }
  });

  test(
    'supplier attribution reads warehouse cost and refreshes on stock writes',
    () async {
      final variant = await seed();
      final product =
          (await db.select(db.productVariants).getSingle()).productId;
      final currency = (await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle()).id;
      final supplier = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Warehouse supplier',
              currencyId: currency,
            ),
          );
      final purchase = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'REPORT-WAREHOUSE',
              supplierId: supplier,
              subtotalCents: Decimal.fromInt(16020),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(16020),
              currencyId: currency,
              status: const Value('posted'),
              purchaseDate: Value(DateTime.now()),
            ),
          );
      await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchase,
              productId: product,
              variantId: Value(variant),
              quantity: 20,
              unitCostCents: Decimal.fromInt(801),
              subtotalCents: Decimal.fromInt(16020),
              totalCents: Decimal.fromInt(16020),
            ),
          );
      final bloc = SupplierStocktakeReportBloc(db);
      final events = StreamIterator(bloc.stream);
      bloc.add(SupplierStocktakeReportSupplierChanged(supplier));
      try {
        Future<SupplierStocktakeReportData> nextWithQuantity(
          int quantity,
        ) async {
          while (await events.moveNext().timeout(const Duration(seconds: 10))) {
            final state = events.current;
            if (state is RealtimeSuccess<SupplierStocktakeReportData> &&
                state.data.products.isNotEmpty &&
                state.data.products.single.remainingQuantity == quantity) {
              return state.data;
            }
          }
          throw StateError('Report stream closed');
        }

        final initial = await nextWithQuantity(12);
        expect(initial.products.single.remainingValueCents, 9612);
        await (db.update(db.businessWarehouseStocks)
              ..where((s) => s.variantId.equals(variant)))
            .write(const BusinessWarehouseStocksCompanion(quantity: Value(14)));
        final updated = await nextWithQuantity(14);
        expect(updated.products.single.remainingValueCents, 11214);
      } finally {
        await events.cancel();
        await bloc.close();
      }
    },
  );
  test(
    'selected warehouse valuation and catalog retain disabled history',
    () async {
      final variant = await seed();
      final local = await BusinessFoundationRepository(db).getScope();
      final other = const Uuid().v4();
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: other,
              organizationId: local.organizationId,
              branchId: local.branchId,
              code: 'REPORT-2',
            ),
          );
      await db
          .into(db.businessWarehouseStocks)
          .insert(
            BusinessWarehouseStocksCompanion.insert(
              warehouseId: other,
              variantId: variant,
              quantity: const Value(3),
              unitCostCents: const Value(205),
            ),
          );
      final scope = await WarehouseReadScope.resolve(db, warehouseId: other);
      await db.customStatement(
        'UPDATE business_warehouses SET is_active = 0 WHERE id = ?',
        [other],
      );
      final bloc = InventoryReportsBloc(db, warehouseScope: scope);
      try {
        final data = await bloc.dataStream.first.timeout(
          const Duration(seconds: 10),
        );
        expect(data.totalStockUnits, 3);
        expect(data.totalValuationCents, 615);
        final row = (await WarehouseCatalogScope.readVariants(db, [
          variant,
        ], scope: scope)).single;
        expect(row.stockQuantity, 3);
        expect(row.costCents, Decimal.fromInt(205));
        expect((await report()).totalStockUnits, 12);
      } finally {
        await bloc.close();
      }
    },
  );

  test('read scope rejects another connection and unknown warehouse', () async {
    final scope = await WarehouseReadScope.resolve(db);
    final otherDb = fixtures.memoryDb();
    try {
      await expectLater(scope.validate(otherDb), throwsStateError);
      await expectLater(
        WarehouseCatalogScope.readVariants(otherDb, [], scope: scope),
        throwsStateError,
      );
      await expectLater(
        WarehouseReadScope.resolve(db, warehouseId: 'missing'),
        throwsStateError,
      );
    } finally {
      await otherDb.close();
    }
  });
}
