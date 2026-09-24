import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/dashboard/presentation/services/daily_sales_reporting_service.dart';
import 'package:tapix/features/reports/presentation/bloc/inventory_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/profit_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  late AppDatabase db;

  Future<T> firstSuccess<T>(Stream<RealtimeState<T>> stream) async {
    final state =
        await stream.firstWhere((s) => s is RealtimeSuccess<T>)
            as RealtimeSuccess<T>;
    return state.data;
  }

  Future<int> product({
    required String name,
    required bool trackInventory,
    required int stock,
    required int cost,
    String costingMethod = 'wac',
    String trackingType = 'standard',
    bool hasVariants = false,
  }) {
    return db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: name,
            sku: Value(name),
            trackInventory: Value(trackInventory),
            stockQuantity: Value(stock),
            costCents: Decimal.fromInt(cost),
            priceCents: Decimal.fromInt(2000),
            costingMethod: Value(costingMethod),
            inventoryTrackingType: Value(trackingType),
            hasVariants: Value(hasVariants),
          ),
        );
  }

  Future<int> variant({
    required int productId,
    required int stock,
    required int cost,
  }) {
    return db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: Value(stock),
            costCents: Decimal.fromInt(cost),
            priceCents: Decimal.fromInt(2000),
          ),
        );
  }

  Future<int> batch({
    required int productId,
    int? variantId,
    required int quantity,
    required int cost,
    String? number,
  }) {
    return db
        .into(db.productBatches)
        .insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            variantId: Value(variantId),
            batchNumber: number ?? 'B-${DateTime.now().microsecondsSinceEpoch}',
            receivedQuantity: quantity,
            remainingQuantity: quantity,
            unitCostCents: Decimal.fromInt(cost),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  test(
    'inventory report equals valuation SoT for FIFO/WAC and excludes services',
    () async {
      final fifoId = await product(
        name: 'FIFO-RPT',
        trackInventory: true,
        stock: 13,
        cost: 9801,
        costingMethod: 'fifo',
        trackingType: 'batch_expiry',
        hasVariants: true,
      );
      final fifoVariant = await variant(
        productId: fifoId,
        stock: 13,
        cost: 9801,
      );
      await batch(
        productId: fifoId,
        variantId: fifoVariant,
        quantity: 10,
        cost: 9900,
        number: 'FIFO-A',
      );
      await batch(
        productId: fifoId,
        variantId: fifoVariant,
        quantity: 3,
        cost: 9801,
        number: 'FIFO-B',
      );

      final wacId = await product(
        name: 'WAC-RPT',
        trackInventory: true,
        stock: 4,
        cost: 500,
        hasVariants: true,
      );
      final wacVariant = await variant(productId: wacId, stock: 4, cost: 500);
      // Stale WAC batch must not override the WAC stock/cost source.
      await batch(
        productId: wacId,
        variantId: wacVariant,
        quantity: 5,
        cost: 999,
        number: 'WAC-STALE',
      );

      await product(
        name: 'SERVICE-RPT',
        trackInventory: false,
        stock: 99,
        cost: 9999,
      );

      final bloc = InventoryReportsBloc(db);
      addTearDown(bloc.close);
      final data = await firstSuccess<InventoryReportsData>(bloc.stream);
      final accountingValue = await JournalLocalDatasourceImpl(
        AccountingDao(db),
      ).getTotalInventoryValueCents();

      expect(
        data.stockValuation.map((i) => i.productName),
        containsAll(<String>['FIFO-RPT', 'WAC-RPT']),
      );
      expect(
        data.stockValuation.any((i) => i.productName == 'SERVICE-RPT'),
        isFalse,
      );

      final fifo = data.stockValuation.singleWhere(
        (i) => i.productName == 'FIFO-RPT',
      );
      final wac = data.stockValuation.singleWhere(
        (i) => i.productName == 'WAC-RPT',
      );
      expect(fifo.valuationCents, 128403);
      expect(fifo.valuationByType(PriceDisplayType.cost), 128403);
      expect(wac.valuationCents, 2000);
      expect(data.totalValuationCents, 130403);
      expect(accountingValue, data.totalValuationCents);
    },
  );

  test(
    'profit breakdown and daily report match net revenue and frozen COGS',
    () async {
      final currencyId = (await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle()).id;
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Reporting customer',
              currencyId: currencyId,
            ),
          );
      final trackedId = await product(
        name: 'TRACKED-RPT',
        trackInventory: true,
        stock: 0,
        cost: 334,
        costingMethod: 'fifo',
        trackingType: 'batch',
      );
      final serviceId = await product(
        name: 'SERVICE-PROFIT',
        trackInventory: false,
        stock: 40,
        cost: 999,
      );
      final day = DateTime(2026, 8, 6, 12);
      final previousPeriod = DateTime(2026, 7, 15, 12);

      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-RPT-CURRENT',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(5000),
              taxCents: Decimal.fromInt(750),
              totalCents: Decimal.fromInt(5750),
              paidAmountCents: Value(Decimal.fromInt(5750)),
              currencyId: currencyId,
              paymentMethod: 'cash',
              status: const Value('completed'),
              saleDate: Value(day),
            ),
          );
      final trackedSaleItem = await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: trackedId,
              quantity: 3,
              unitPriceCents: Decimal.fromInt(1000),
              subtotalCents: Decimal.fromInt(3000),
              taxCents: Value(Decimal.fromInt(450)),
              totalCents: Decimal.fromInt(3450),
              costCents: Value(Decimal.fromInt(334)),
            ),
          );
      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: serviceId,
              quantity: 1,
              unitPriceCents: Decimal.fromInt(2000),
              subtotalCents: Decimal.fromInt(2000),
              taxCents: Value(Decimal.fromInt(300)),
              totalCents: Decimal.fromInt(2300),
              // Deliberately non-zero legacy snapshot: services must still be 0.
              costCents: Value(Decimal.fromInt(999)),
            ),
          );
      final layerA = await batch(
        productId: trackedId,
        quantity: 2,
        cost: 333,
        number: 'COGS-A',
      );
      final layerB = await batch(
        productId: trackedId,
        quantity: 1,
        cost: 335,
        number: 'COGS-B',
      );
      for (final layer in [
        (id: layerA, qty: 2, cost: 333),
        (id: layerB, qty: 1, cost: 335),
      ]) {
        await db
            .into(db.batchConsumptions)
            .insert(
              BatchConsumptionsCompanion.insert(
                batchId: layer.id,
                consumptionType: 'sale',
                direction: 'out',
                quantity: layer.qty,
                unitCostCents: Decimal.fromInt(layer.cost),
                saleItemId: Value(trackedSaleItem),
              ),
            );
      }

      // Pending sales are not posted and must never appear as profit.
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-RPT-PENDING',
              subtotalCents: Decimal.fromInt(99999),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(99999),
              currencyId: currencyId,
              paymentMethod: 'cash',
              status: const Value('pending'),
              saleDate: Value(day),
            ),
          );

      // Parent sale is outside the report period; its linked return is inside.
      final oldSaleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-RPT-OLD',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(1000),
              taxCents: Decimal.fromInt(150),
              totalCents: Decimal.fromInt(1150),
              currencyId: currencyId,
              paymentMethod: 'cash',
              status: const Value('completed'),
              saleDate: Value(previousPeriod),
            ),
          );
      final oldSaleItem = await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: oldSaleId,
              productId: trackedId,
              quantity: 1,
              unitPriceCents: Decimal.fromInt(1000),
              subtotalCents: Decimal.fromInt(1000),
              taxCents: Value(Decimal.fromInt(150)),
              totalCents: Decimal.fromInt(1150),
              costCents: Value(Decimal.fromInt(500)),
            ),
          );
      final linkedReturn = await db
          .into(db.saleReturns)
          .insert(
            SaleReturnsCompanion.insert(
              returnNumber: 'SR-RPT-CURRENT',
              saleId: oldSaleId,
              subtotalCents: Value(Decimal.fromInt(1000)),
              taxCents: Value(Decimal.fromInt(150)),
              totalCents: Decimal.fromInt(1150),
              currencyId: currencyId,
              status: const Value('posted'),
              refundMethod: const Value('cash'),
              returnDate: Value(day),
            ),
          );
      await db
          .into(db.saleReturnItems)
          .insert(
            SaleReturnItemsCompanion.insert(
              returnId: linkedReturn,
              saleItemId: oldSaleItem,
              quantity: 1,
              subtotalCents: Value(Decimal.fromInt(1000)),
              taxCents: Value(Decimal.fromInt(150)),
              refundCents: Decimal.fromInt(1150),
              unitCostAtPostCents: Value(Decimal.fromInt(500)),
            ),
          );

      final adjustmentReturn = await db
          .into(db.saleReturnAdjustments)
          .insert(
            SaleReturnAdjustmentsCompanion.insert(
              returnNumber: 'SAR-RPT-CURRENT',
              customerId: Value(customerId),
              currencyId: currencyId,
              subtotalCents: Value(Decimal.fromInt(500)),
              taxCents: Value(Decimal.fromInt(75)),
              totalCents: Decimal.fromInt(575),
              status: const Value('posted'),
              refundMethod: const Value('cash'),
              returnDate: Value(day),
            ),
          );
      await db
          .into(db.saleReturnAdjustmentItems)
          .insert(
            SaleReturnAdjustmentItemsCompanion.insert(
              sourceResolution: const Value('unverified'),
              sourceResolutionReason: const Value('test fixture'),
              returnId: adjustmentReturn,
              productId: serviceId,
              quantity: 1,
              unitPriceCents: Decimal.fromInt(500),
              unitCostCents: Value(Decimal.fromInt(999)),
              unitCostAtPostCents: Value(Decimal.fromInt(999)),
              taxCents: Value(Decimal.fromInt(75)),
              totalCents: Decimal.fromInt(575),
            ),
          );

      final range = ReportDateRange(
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 31, 23, 59, 59),
        preset: ReportPeriodPreset.custom,
      );
      final bloc = ProfitReportsBloc(db);
      addTearDown(bloc.close);
      bloc.add(ProfitReportsDateRangeChanged(range));
      final data = await firstSuccess<ProfitReportsData>(bloc.stream);

      expect(data.byInvoice.map((i) => i.invoiceNumber).toSet(), {
        'INV-RPT-CURRENT',
        'SR-RPT-CURRENT',
        'SAR-RPT-CURRENT',
      });
      expect(data.summary.totalRevenueCents, 3500);
      expect(data.summary.totalCostCents, 501);
      expect(data.summary.totalProfitCents, 2999);
      expect(data.summary.totalTaxCents, 525);
      expect(
        data.byProduct.fold<int>(0, (sum, i) => sum + i.totalRevenueCents),
        data.summary.totalRevenueCents,
      );
      expect(
        data.byCategory.fold<int>(0, (sum, i) => sum + i.totalCostCents),
        data.summary.totalCostCents,
      );
      expect(
        data.byCustomer.fold<int>(0, (sum, i) => sum + i.totalProfitCents),
        data.summary.totalProfitCents,
      );

      final dailyRows = await DailySalesReportingService(db).loadDay(day);
      expect(dailyRows.map((r) => r.documentNumber).toSet(), {
        'INV-RPT-CURRENT',
        'SR-RPT-CURRENT',
        'SAR-RPT-CURRENT',
      });
      expect(dailyRows.fold<int>(0, (sum, r) => sum + r.revenueCents), 3500);
      expect(dailyRows.fold<int>(0, (sum, r) => sum + r.costCents), 501);
    },
  );
}
