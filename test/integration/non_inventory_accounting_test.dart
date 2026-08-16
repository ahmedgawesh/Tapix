import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late int currencyId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    journal = JournalEntryService(AccountingRepository(db));
    await db.customSelect('SELECT 1').get();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users '
      '(id, username, password_hash, role, is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );
    currencyId = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Service supplier',
            currencyId: currencyId,
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> createProduct({
    required String sku,
    required bool tracksInventory,
    required int stock,
    required int cost,
    required int price,
  }) {
    return db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: Value(sku),
            name: sku,
            costCents: Decimal.fromInt(cost),
            priceCents: Decimal.fromInt(price),
            currencyId: Value(currencyId),
            trackInventory: Value(tracksInventory),
            stockQuantity: Value(stock),
            hasVariants: const Value(false),
          ),
        );
  }

  Future<int> productStock(int productId) async {
    return (await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingle()).stockQuantity;
  }

  Future<Map<String, ({int debit, int credit})>> journalTotals(
    String sourceTable,
    int sourceId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT a.account_code, '
          'COALESCE(SUM(jel.debit_cents), 0) AS debit, '
          'COALESCE(SUM(jel.credit_cents), 0) AS credit '
          'FROM journal_entry_lines jel '
          'JOIN journal_entries je ON je.id = jel.journal_entry_id '
          'JOIN accounts a ON a.id = jel.account_id '
          'WHERE je.source_table = ? AND je.source_id = ? '
          "AND je.status = 'posted' AND je.is_reversed = 0 "
          'GROUP BY a.account_code',
          variables: [
            Variable.withString(sourceTable),
            Variable.withInt(sourceId),
          ],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('account_code'): (
          debit: row.read<int>('debit'),
          credit: row.read<int>('credit'),
        ),
    };
  }

  test(
    'service sale and linked return never move or value inventory',
    () async {
      final serviceId = await createProduct(
        sku: 'SERVICE-SALE',
        tracksInventory: false,
        stock: 7,
        cost: 300,
        price: 2000,
      );
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-SERVICE-1',
              subtotalCents: Decimal.fromInt(4000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(4000),
              paidAmountCents: Value(Decimal.fromInt(4000)),
              currencyId: currencyId,
              paymentMethod: 'cash',
              status: const Value('draft'),
            ),
          );
      final saleItemId = await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: serviceId,
              quantity: 2,
              unitPriceCents: Decimal.fromInt(2000),
              subtotalCents: Decimal.fromInt(4000),
              totalCents: Decimal.fromInt(4000),
            ),
          );

      await db.saleDao.postSale(saleId);

      expect(await productStock(serviceId), 7);
      expect(await db.saleDao.computeSaleCostCents(saleId), 0);
      var saleItem = await (db.select(
        db.saleItems,
      )..where((i) => i.id.equals(saleItemId))).getSingle();
      expect(saleItem.costCents?.toBigInt().toInt(), 0);

      final returnId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          returnNumber: 'SR-SERVICE-1',
          saleId: saleId,
          subtotalCents: Value(Decimal.fromInt(2000)),
          totalCents: Decimal.fromInt(2000),
          currencyId: currencyId,
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: saleItemId,
            quantity: 1,
            subtotalCents: Value(Decimal.fromInt(2000)),
            refundCents: Decimal.fromInt(2000),
          ),
        ],
      );

      await db.saleDao.postSaleReturn(returnId);

      expect(await productStock(serviceId), 7);
      expect(await db.saleDao.computeSaleReturnCostCents(returnId), 0);
      final returnItem = await (db.select(
        db.saleReturnItems,
      )..where((i) => i.returnId.equals(returnId))).getSingle();
      expect(returnItem.unitCostAtPostCents?.toBigInt().toInt(), 0);
      saleItem = await (db.select(
        db.saleItems,
      )..where((i) => i.id.equals(saleItemId))).getSingle();
      expect(saleItem.qtyReturnedLinked, 1);

      await db.saleDao.voidSaleReturn(returnId);
      expect(await productStock(serviceId), 7);
      saleItem = await (db.select(
        db.saleItems,
      )..where((i) => i.id.equals(saleItemId))).getSingle();
      expect(saleItem.qtyReturnedLinked, 0);

      await db.saleDao.voidSale(saleId);
      expect(await productStock(serviceId), 7);
    },
  );

  test('mixed purchase splits inventory and service expense exactly', () async {
    final stockedId = await createProduct(
      sku: 'STOCK-PURCHASE',
      tracksInventory: true,
      stock: 0,
      cost: 100,
      price: 5000,
    );
    final serviceId = await createProduct(
      sku: 'SERVICE-PURCHASE',
      tracksInventory: false,
      stock: 7,
      cost: 900,
      price: 4000,
    );
    final stockedVariantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: stockedId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(5000),
          ),
        );
    final purchaseId = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-MIXED-1',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(10000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(10000),
            paidAmountCents: Value(Decimal.fromInt(10000)),
            currencyId: currencyId,
            paymentMethod: const Value('cash'),
            status: const Value('draft'),
          ),
        );
    await db
        .into(db.purchaseItems)
        .insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: stockedId,
            variantId: Value(stockedVariantId),
            quantity: 2,
            unitCostCents: Decimal.fromInt(3000),
            subtotalCents: Decimal.fromInt(6000),
            totalCents: Decimal.fromInt(6000),
          ),
        );
    final serviceItemId = await db
        .into(db.purchaseItems)
        .insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: serviceId,
            quantity: 1,
            unitCostCents: Decimal.fromInt(4000),
            subtotalCents: Decimal.fromInt(4000),
            totalCents: Decimal.fromInt(4000),
          ),
        );

    await db.purchaseDao.postPurchase(purchaseId);
    final inventoryNet = await db.purchaseDao.computePurchaseInventoryNetCents(
      purchaseId,
    );
    expect(inventoryNet, 6000);
    expect(await productStock(stockedId), 2);
    expect(await productStock(serviceId), 7);

    await journal.recordPurchaseJournalEntry(
      purchaseId: purchaseId,
      totalCents: 10000,
      paidAmountCents: 10000,
      currencyId: currencyId,
      inventoryNetCents: inventoryNet,
      paymentMethod: 'cash',
    );
    var totals = await journalTotals('purchases', purchaseId);
    expect(totals['1200'], (debit: 6000, credit: 0));
    expect(totals['5100'], (debit: 4000, credit: 0));
    expect(totals['1000'], (debit: 0, credit: 10000));

    final returnId = await db.purchaseDao.createPurchaseReturn(
      PurchaseReturnsCompanion.insert(
        returnNumber: 'PR-SERVICE-1',
        purchaseId: purchaseId,
        subtotalCents: Value(Decimal.fromInt(4000)),
        totalCents: Decimal.fromInt(4000),
        currencyId: currencyId,
        refundMethod: const Value('cash'),
      ),
      [
        PurchaseReturnItemsCompanion.insert(
          returnId: 0,
          purchaseItemId: serviceItemId,
          quantity: 1,
          subtotalCents: Value(Decimal.fromInt(4000)),
          refundCents: Decimal.fromInt(4000),
        ),
      ],
    );
    await db.purchaseDao.postPurchaseReturn(returnId);
    expect(await productStock(serviceId), 7);
    expect(
      await db.purchaseDao.computePurchaseReturnInventoryCostCents(returnId),
      0,
    );
    final returnItem = await (db.select(
      db.purchaseReturnItems,
    )..where((i) => i.returnId.equals(returnId))).getSingle();
    expect(returnItem.unitCostAtPostCents?.toBigInt().toInt(), 0);

    await journal.recordPurchaseReturnJournalEntry(
      returnId: returnId,
      totalCents: 4000,
      currencyId: currencyId,
      inventoryCostCents: 0,
      refundMethod: 'cash',
    );
    totals = await journalTotals('purchase_returns', returnId);
    expect(totals.containsKey('1200'), isFalse);
    expect(totals['4100'], (debit: 0, credit: 4000));
    expect(totals['1000'], (debit: 4000, credit: 0));

    await db.purchaseDao.voidPurchaseReturn(returnId);
    expect(await productStock(serviceId), 7);
    final serviceItem = await (db.select(
      db.purchaseItems,
    )..where((i) => i.id.equals(serviceItemId))).getSingle();
    expect(serviceItem.qtyReturnedLinked, 0);

    await db.purchaseDao.voidPurchase(purchaseId);
    expect(await productStock(stockedId), 0);
    expect(await productStock(serviceId), 7);
  });

  test('part-paid taxed mixed purchase remains balanced and exact', () async {
    await journal.recordPurchaseJournalEntry(
      purchaseId: 9001,
      totalCents: 11500,
      paidAmountCents: 4600,
      currencyId: currencyId,
      taxCents: 1500,
      inventoryNetCents: 6000,
      paymentMethod: 'cash',
    );

    final totals = await journalTotals('purchases', 9001);
    expect(totals['1200'], (debit: 6000, credit: 0));
    expect(totals['5100'], (debit: 4000, credit: 0));
    expect(totals['1300'], (debit: 1500, credit: 0));
    expect(totals['1000'], (debit: 0, credit: 4600));
    expect(totals['2000'], (debit: 0, credit: 6900));

    final debits = totals.values.fold<int>(0, (sum, line) => sum + line.debit);
    final credits = totals.values.fold<int>(
      0,
      (sum, line) => sum + line.credit,
    );
    expect(debits, 11500);
    expect(credits, 11500);
  });
}
