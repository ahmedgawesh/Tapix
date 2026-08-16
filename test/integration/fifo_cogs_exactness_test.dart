import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/ledger_rebuild_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late AccountingRepository accounting;
  late JournalEntryService journal;
  late int currencyId;
  late int supplierId;
  late int customerId;
  late int productId;
  late int variantId;

  Future<int> postPurchase({
    required String number,
    required int quantity,
    required int unitCostCents,
  }) async {
    final purchaseId = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: number,
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(quantity * unitCostCents),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(quantity * unitCostCents),
            paidAmountCents: Value(Decimal.zero),
            currencyId: currencyId,
            status: const Value('draft'),
            paymentMethod: const Value('credit'),
          ),
        );
    await db
        .into(db.purchaseItems)
        .insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitCostCents: Decimal.fromInt(unitCostCents),
            subtotalCents: Decimal.fromInt(quantity * unitCostCents),
            totalCents: Decimal.fromInt(quantity * unitCostCents),
          ),
        );
    await db.purchaseDao.postPurchase(purchaseId);
    return purchaseId;
  }

  Future<int> postSale() async {
    const saleTotal = 3000;
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'FIFO-EXACT-SALE',
            customerId: Value(customerId),
            subtotalCents: Decimal.fromInt(saleTotal),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(saleTotal),
            paidAmountCents: Value(Decimal.fromInt(saleTotal)),
            currencyId: currencyId,
            paymentMethod: 'cash',
            status: const Value('draft'),
          ),
        );
    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: 3,
            unitPriceCents: Decimal.fromInt(1000),
            subtotalCents: Decimal.fromInt(saleTotal),
            totalCents: Decimal.fromInt(saleTotal),
          ),
        );
    await db.saleDao.postSale(saleId);
    return saleId;
  }

  Future<int> postPartialSaleReturn(int saleId) async {
    final saleItem = await (db.select(
      db.saleItems,
    )..where((i) => i.saleId.equals(saleId))).getSingle();
    final returnId = await db.saleDao.createSaleReturn(
      SaleReturnsCompanion.insert(
        saleId: saleId,
        returnNumber: 'FIFO-EXACT-RETURN',
        subtotalCents: Value(Decimal.fromInt(2000)),
        taxCents: Value(Decimal.zero),
        totalCents: Decimal.fromInt(2000),
        currencyId: currencyId,
        status: const Value('draft'),
        refundMethod: const Value('cash'),
      ),
      [
        SaleReturnItemsCompanion.insert(
          returnId: 0,
          saleItemId: saleItem.id,
          quantity: 2,
          subtotalCents: Value(Decimal.fromInt(2000)),
          taxCents: Value(Decimal.zero),
          refundCents: Decimal.fromInt(2000),
        ),
      ],
    );
    await db.saleDao.postSaleReturn(returnId);
    return returnId;
  }

  Future<({int debit, int credit})> journalAmount({
    required String entryType,
    required int sourceId,
  }) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(jel.debit_cents), 0) AS debit, '
          'COALESCE(SUM(jel.credit_cents), 0) AS credit '
          'FROM journal_entry_lines jel '
          'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
          'WHERE je.entry_type = ? AND je.source_id = ? AND je.status = ?',
          variables: [
            Variable.withString(entryType),
            Variable.withInt(sourceId),
            Variable.withString('posted'),
          ],
        )
        .getSingle();
    return (debit: row.read<int>('debit'), credit: row.read<int>('credit'));
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);

    await db.customSelect('SELECT 1').get();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users '
      '(id, username, password_hash, role, is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;

    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'FIFO exact supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'FIFO exact customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value('FIFO-EXACT'),
            name: 'FIFO exact product',
            costCents: Decimal.zero,
            priceCents: Decimal.fromInt(1000),
            currencyId: Value(currencyId),
            stockQuantity: const Value(0),
            hasVariants: const Value(true),
          ),
        );
    await db.customStatement(
      "UPDATE products SET costing_method = 'fifo', "
      "inventory_tracking_type = 'batch' WHERE id = ?",
      [productId],
    );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.zero,
            priceCents: Decimal.fromInt(1000),
          ),
        );
  });

  tearDown(() async => db.close());

  test(
    'FIFO sale and linked return use exact layer totals, not rounded blended unit cost',
    () async {
      await postPurchase(
        number: 'FIFO-EXACT-PO-1',
        quantity: 1,
        unitCostCents: 100,
      );
      await postPurchase(
        number: 'FIFO-EXACT-PO-2',
        quantity: 2,
        unitCostCents: 101,
      );

      final saleId = await postSale();
      final saleItem = await (db.select(
        db.saleItems,
      )..where((i) => i.saleId.equals(saleId))).getSingle();

      expect(saleItem.costCents!.toBigInt().toInt(), 101);
      expect(saleItem.costCents!.toBigInt().toInt() * saleItem.quantity, 303);
      expect(await db.saleDao.computeSaleCostCents(saleId), 302);

      final returnId = await postPartialSaleReturn(saleId);
      expect(await db.saleDao.computeSaleReturnCostCents(returnId), 201);
    },
  );

  test(
    'ledger rebuild restores exact sale and sale-return COGS entries',
    () async {
      await postPurchase(
        number: 'FIFO-REBUILD-PO-1',
        quantity: 1,
        unitCostCents: 100,
      );
      await postPurchase(
        number: 'FIFO-REBUILD-PO-2',
        quantity: 2,
        unitCostCents: 101,
      );
      final saleId = await postSale();
      final returnId = await postPartialSaleReturn(saleId);

      final rebuild = LedgerRebuildService(
        db: db,
        accountingRepo: accounting,
        journalService: journal,
      );
      final report = await rebuild.rebuild(confirmationToken: true);

      expect(report.errors, isEmpty);
      expect(await journalAmount(entryType: 'sale_cogs', sourceId: saleId), (
        debit: 302,
        credit: 302,
      ));
      expect(
        await journalAmount(entryType: 'sale_return_cogs', sourceId: returnId),
        (debit: 201, credit: 201),
      );
    },
  );
}
