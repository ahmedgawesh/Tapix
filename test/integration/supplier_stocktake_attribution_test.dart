import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_stocktake_report_bloc.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int supplierA;
  late int supplierB;

  Future<int> supplier(String name) {
    return db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: name,
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  }

  Future<({int productId, int variantId})> product({
    required String name,
    required int stock,
    required int cost,
    required bool fifo,
  }) async {
    final productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: name,
            sku: Value(name),
            trackInventory: const Value(true),
            stockQuantity: Value(stock),
            costCents: Decimal.fromInt(cost),
            priceCents: Decimal.fromInt(1000),
            costingMethod: Value(fifo ? 'fifo' : 'wac'),
            inventoryTrackingType: Value(fifo ? 'batch' : 'standard'),
            hasVariants: const Value(true),
          ),
        );
    final variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: Value(stock),
            costCents: Decimal.fromInt(cost),
            priceCents: Decimal.fromInt(1000),
          ),
        );
    return (productId: productId, variantId: variantId);
  }

  Future<({int purchaseId, int itemId})> postedPurchase({
    required int supplierId,
    required int productId,
    required int variantId,
    required int quantity,
    required int cost,
    required String number,
  }) async {
    final total = quantity * cost;
    final purchaseId = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: number,
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(total),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(total),
            currencyId: currencyId,
            status: const Value('posted'),
            purchaseDate: Value(DateTime.now()),
          ),
        );
    final itemId = await db
        .into(db.purchaseItems)
        .insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitCostCents: Decimal.fromInt(cost),
            subtotalCents: Decimal.fromInt(total),
            totalCents: Decimal.fromInt(total),
          ),
        );
    return (purchaseId: purchaseId, itemId: itemId);
  }

  Future<SupplierStocktakeReportData> reportFor(int supplierId) async {
    final bloc = SupplierStocktakeReportBloc(db);
    bloc.add(SupplierStocktakeReportSupplierChanged(supplierId));
    final state =
        await bloc.stream.firstWhere(
              (state) =>
                  state is RealtimeSuccess<SupplierStocktakeReportData> &&
                  state.data.supplierId == supplierId,
            )
            as RealtimeSuccess<SupplierStocktakeReportData>;
    await bloc.close();
    return state.data;
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((currency) => currency.code.equals('USD'))).getSingle()).id;
    supplierA = await supplier('Supplier A');
    supplierB = await supplier('Supplier B');
  });

  tearDown(() => db.close());

  test(
    'supplier balances never duplicate stock: FIFO exact and WAC allocated',
    () async {
      final fifo = await product(
        name: 'FIFO-SUPPLIER',
        stock: 5,
        cost: 160,
        fifo: true,
      );
      final fifoPurchaseA = await postedPurchase(
        supplierId: supplierA,
        productId: fifo.productId,
        variantId: fifo.variantId,
        quantity: 2,
        cost: 100,
        number: 'PO-FIFO-A',
      );
      final fifoPurchaseB = await postedPurchase(
        supplierId: supplierB,
        productId: fifo.productId,
        variantId: fifo.variantId,
        quantity: 3,
        cost: 200,
        number: 'PO-FIFO-B',
      );
      final batchA = await db
          .into(db.productBatches)
          .insert(
            ProductBatchesCompanion.insert(
              productId: fifo.productId,
              variantId: Value(fifo.variantId),
              batchNumber: 'B-FIFO-A',
              purchaseItemId: Value(fifoPurchaseA.itemId),
              supplierId: Value(supplierA),
              receivedQuantity: 2,
              remainingQuantity: 2,
              unitCostCents: Decimal.fromInt(100),
            ),
          );
      final batchB = await db
          .into(db.productBatches)
          .insert(
            ProductBatchesCompanion.insert(
              productId: fifo.productId,
              variantId: Value(fifo.variantId),
              batchNumber: 'B-FIFO-B',
              purchaseItemId: Value(fifoPurchaseB.itemId),
              supplierId: Value(supplierB),
              receivedQuantity: 3,
              remainingQuantity: 2,
              unitCostCents: Decimal.fromInt(200),
            ),
          );

      // One sale consumes one unit from each supplier batch. A linked return
      // restores only Supplier A's unit. Revenue follows consumed quantities,
      // while COGS follows each batch's frozen unit cost.
      await db.customUpdate(
        'UPDATE products SET stock_quantity = 4 WHERE id = ?',
        variables: [Variable.withInt(fifo.productId)],
        updates: {db.products},
      );
      await db.customUpdate(
        'UPDATE product_variants SET stock_quantity = 4 WHERE id = ?',
        variables: [Variable.withInt(fifo.variantId)],
        updates: {db.productVariants},
      );
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-FIFO-SUPPLIERS',
              subtotalCents: Decimal.fromInt(1000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(1000),
              currencyId: currencyId,
              paymentMethod: 'cash',
              status: const Value('completed'),
              saleDate: Value(DateTime.now()),
            ),
          );
      final saleItemId = await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: fifo.productId,
              variantId: Value(fifo.variantId),
              quantity: 2,
              unitPriceCents: Decimal.fromInt(500),
              subtotalCents: Decimal.fromInt(1000),
              totalCents: Decimal.fromInt(1000),
              costCents: Value(Decimal.fromInt(150)),
            ),
          );
      await db
          .into(db.batchConsumptions)
          .insert(
            BatchConsumptionsCompanion.insert(
              batchId: batchA,
              consumptionType: 'sale',
              direction: 'out',
              quantity: 1,
              unitCostCents: Decimal.fromInt(100),
              saleItemId: Value(saleItemId),
            ),
          );
      await db
          .into(db.batchConsumptions)
          .insert(
            BatchConsumptionsCompanion.insert(
              batchId: batchB,
              consumptionType: 'sale',
              direction: 'out',
              quantity: 1,
              unitCostCents: Decimal.fromInt(200),
              saleItemId: Value(saleItemId),
            ),
          );
      final saleReturnId = await db
          .into(db.saleReturns)
          .insert(
            SaleReturnsCompanion.insert(
              saleId: saleId,
              returnNumber: 'SR-FIFO-A',
              totalCents: Decimal.fromInt(500),
              currencyId: currencyId,
              status: const Value('posted'),
              returnDate: Value(DateTime.now()),
            ),
          );
      final saleReturnItemId = await db
          .into(db.saleReturnItems)
          .insert(
            SaleReturnItemsCompanion.insert(
              returnId: saleReturnId,
              saleItemId: saleItemId,
              quantity: 1,
              refundCents: Decimal.fromInt(500),
              unitCostAtPostCents: Value(Decimal.fromInt(100)),
            ),
          );
      await db
          .into(db.batchConsumptions)
          .insert(
            BatchConsumptionsCompanion.insert(
              batchId: batchA,
              consumptionType: 'sale_return_reverse',
              direction: 'in',
              quantity: 1,
              unitCostCents: Decimal.fromInt(100),
              saleReturnItemId: Value(saleReturnItemId),
            ),
          );

      final wac = await product(
        name: 'WAC-SUPPLIER',
        stock: 2,
        cost: 500,
        fifo: false,
      );
      final wacPurchaseA = await postedPurchase(
        supplierId: supplierA,
        productId: wac.productId,
        variantId: wac.variantId,
        quantity: 3,
        cost: 500,
        number: 'PO-WAC-A',
      );
      await postedPurchase(
        supplierId: supplierB,
        productId: wac.productId,
        variantId: wac.variantId,
        quantity: 3,
        cost: 500,
        number: 'PO-WAC-B',
      );

      // Both purchase-return paths must reduce Supplier A's source weight and
      // appear in its period return quantity.
      final linkedReturnId = await db
          .into(db.purchaseReturns)
          .insert(
            PurchaseReturnsCompanion.insert(
              purchaseId: wacPurchaseA.purchaseId,
              returnNumber: 'PR-WAC-A',
              totalCents: Decimal.fromInt(500),
              currencyId: currencyId,
              status: const Value('posted'),
              returnDate: Value(DateTime.now()),
            ),
          );
      await db
          .into(db.purchaseReturnItems)
          .insert(
            PurchaseReturnItemsCompanion.insert(
              returnId: linkedReturnId,
              purchaseItemId: wacPurchaseA.itemId,
              quantity: 1,
              refundCents: Decimal.fromInt(500),
            ),
          );
      final adjustmentReturnId = await db
          .into(db.purchaseReturnAdjustments)
          .insert(
            PurchaseReturnAdjustmentsCompanion.insert(
              returnNumber: 'PRA-WAC-A',
              supplierId: supplierA,
              currencyId: currencyId,
              totalCents: Decimal.fromInt(500),
              status: const Value('posted'),
              returnDate: Value(DateTime.now()),
            ),
          );
      await db
          .into(db.purchaseReturnAdjustmentItems)
          .insert(
            PurchaseReturnAdjustmentItemsCompanion.insert(
              returnId: adjustmentReturnId,
              productId: wac.productId,
              variantId: Value(wac.variantId),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(500),
              totalCents: Decimal.fromInt(500),
            ),
          );

      final reportA = await reportFor(supplierA);
      final reportB = await reportFor(supplierB);
      final fifoA = reportA.products.singleWhere(
        (item) => item.productName == 'FIFO-SUPPLIER',
      );
      final fifoB = reportB.products.singleWhere(
        (item) => item.productName == 'FIFO-SUPPLIER',
      );
      final wacA = reportA.products.singleWhere(
        (item) => item.productName == 'WAC-SUPPLIER',
      );
      final wacB = reportB.products.singleWhere(
        (item) => item.productName == 'WAC-SUPPLIER',
      );

      expect((fifoA.remainingQuantity, fifoA.remainingValueCents), (2, 200));
      expect((fifoB.remainingQuantity, fifoB.remainingValueCents), (2, 400));
      expect((fifoA.soldQuantity, fifoA.saleReturnedQuantity), (1, 1));
      expect((fifoB.soldQuantity, fifoB.saleReturnedQuantity), (1, 0));
      expect(fifoA.profitCents, 0);
      expect(fifoB.profitCents, 300);
      expect(wacA.purchaseReturnedQuantity, 2);
      expect(wacB.purchaseReturnedQuantity, 0);
      expect(wacA.remainingQuantity + wacB.remainingQuantity, 2);
      expect(wacA.remainingValueCents + wacB.remainingValueCents, 1000);

      expect(
        reportA.totalRemainingQuantity + reportB.totalRemainingQuantity,
        6,
      );
      expect(
        reportA.totalRemainingValueCents + reportB.totalRemainingValueCents,
        1600,
      );
      final accountingValue = await JournalLocalDatasourceImpl(
        AccountingDao(db),
      ).getTotalInventoryValueCents();
      expect(accountingValue, 1600);
      expect(
        reportA.totalRemainingValueCents + reportB.totalRemainingValueCents,
        accountingValue,
      );
    },
  );
}
