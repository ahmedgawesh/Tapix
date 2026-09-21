import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/ledger_rebuild_service.dart';
import 'package:tapix/core/services/returns/return_journal_policy.dart';
import 'package:tapix/core/services/returns/return_posting_service.dart';
import 'package:tapix/core/services/compliance/customer_credit_note_service.dart';
import 'package:tapix/core/services/compliance/fiscal_period_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int supplierId;
  late int customerId;
  late int productId;
  late int variantId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();

    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.code.equals('USD'))).getSingle();
    currencyId = currency.id;
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Measured supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Measured customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Bulk fruit',
            costCents: Decimal.zero,
            priceCents: Decimal.fromInt(20000),
            currencyId: Value(currencyId),
            stockQuantity: const Value(0),
            hasVariants: const Value(true),
            measurementType: const Value('weight'),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.zero,
            priceCents: Decimal.fromInt(20000),
          ),
        );
  });

  tearDown(() async => db.close());

  test(
    '250g purchase, 100g sale, and measured linked returns stay exact',
    () async {
      // Buy 250 g at 100.00 per kg = 25.00.
      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'MEASURED-PO-1',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(2500),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(2500),
              paidAmountCents: Value(Decimal.fromInt(2500)),
              currencyId: currencyId,
              paymentMethod: const Value('cash'),
              status: const Value('draft'),
            ),
          );
      final purchaseItemId = await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: productId,
              variantId: Value(variantId),
              quantity: 250,
              quantityScale: const Value(1000),
              measurementType: const Value('weight'),
              unitCostCents: Decimal.fromInt(10000),
              subtotalCents: Decimal.fromInt(2500),
              totalCents: Decimal.fromInt(2500),
            ),
          );
      await db.purchaseDao.postPurchase(purchaseId);

      var variant = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();
      expect(variant.stockQuantity, 250);
      expect(variant.costCents.toBigInt().toInt(), 10000);

      // Sell 100 g at 200.00 per kg = 20.00; COGS = 10.00.
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'MEASURED-SALE-1',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(2000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(2000),
              paidAmountCents: Value(Decimal.fromInt(2000)),
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
              productId: productId,
              variantId: Value(variantId),
              quantity: 100,
              quantityScale: const Value(1000),
              measurementType: const Value('weight'),
              unitPriceCents: Decimal.fromInt(20000),
              subtotalCents: Decimal.fromInt(2000),
              totalCents: Decimal.fromInt(2000),
            ),
          );
      await db.saleDao.postSale(saleId);

      final postedSaleItem = await (db.select(
        db.saleItems,
      )..where((row) => row.id.equals(saleItemId))).getSingle();
      expect(postedSaleItem.quantityScale, 1000);
      expect(postedSaleItem.measurementType, 'weight');
      expect(postedSaleItem.costCents!.toBigInt().toInt(), 10000);
      expect(await db.saleDao.computeSaleCostCents(saleId), 1000);

      // Return 50 g from the sale: refund 10.00 and reverse COGS by 5.00.
      final saleReturnId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          saleId: saleId,
          returnNumber: 'MEASURED-SR-1',
          subtotalCents: Value(Decimal.fromInt(1000)),
          taxCents: Value(Decimal.zero),
          totalCents: Decimal.fromInt(1000),
          currencyId: currencyId,
          refundMethod: const Value('cash'),
          status: const Value('draft'),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: saleItemId,
            quantity: 50,
            quantityScale: const Value(1000),
            measurementType: const Value('weight'),
            subtotalCents: Value(Decimal.fromInt(1000)),
            taxCents: Value(Decimal.zero),
            refundCents: Decimal.fromInt(1000),
          ),
        ],
      );
      await db.saleDao.postSaleReturn(saleReturnId);
      expect(await db.saleDao.computeSaleReturnCostCents(saleReturnId), 500);

      // Return 100 g to the supplier: refund and inventory decrease are 10.00.
      final purchaseReturnId = await db.purchaseDao.createPurchaseReturn(
        PurchaseReturnsCompanion.insert(
          purchaseId: purchaseId,
          returnNumber: 'MEASURED-PR-1',
          subtotalCents: Value(Decimal.fromInt(1000)),
          taxCents: Value(Decimal.zero),
          totalCents: Decimal.fromInt(1000),
          currencyId: currencyId,
          refundMethod: const Value('cash'),
          status: const Value('draft'),
        ),
        [
          PurchaseReturnItemsCompanion.insert(
            returnId: 0,
            purchaseItemId: purchaseItemId,
            quantity: 100,
            quantityScale: const Value(1000),
            measurementType: const Value('weight'),
            subtotalCents: Value(Decimal.fromInt(1000)),
            refundCents: Decimal.fromInt(1000),
          ),
        ],
      );
      await db.purchaseDao.postPurchaseReturn(purchaseReturnId);
      expect(
        await db.purchaseDao.computePurchaseReturnInventoryCostCents(
          purchaseReturnId,
        ),
        1000,
      );

      variant = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();
      final product = await (db.select(
        db.products,
      )..where((row) => row.id.equals(productId))).getSingle();
      expect(variant.stockQuantity, 100);
      expect(product.stockQuantity, 100);
      expect(variant.costCents.toBigInt().toInt(), 10000);

      final saleReturnItem = await (db.select(
        db.saleReturnItems,
      )..where((row) => row.returnId.equals(saleReturnId))).getSingle();
      final purchaseReturnItem = await (db.select(
        db.purchaseReturnItems,
      )..where((row) => row.returnId.equals(purchaseReturnId))).getSingle();
      expect(saleReturnItem.quantityScale, 1000);
      expect(saleReturnItem.measurementType, 'weight');
      expect(saleReturnItem.unitCostAtPostCents!.toBigInt().toInt(), 10000);
      expect(purchaseReturnItem.quantityScale, 1000);
      expect(purchaseReturnItem.measurementType, 'weight');
      expect(purchaseReturnItem.unitCostAtPostCents!.toBigInt().toInt(), 10000);

      // The remaining 100 g at 100.00/kg is exactly 10.00. The health-check
      // valuation must agree with the posted Inventory (1200) ledger after
      // purchase, sale, sale return and purchase return.
      final stockValue = await JournalLocalDatasourceImpl(
        db.accountingDao,
      ).getTotalInventoryValueCents();
      expect(stockValue, 1000);
    },
  );

  test('length, weight and volume purchase/sale flows reconcile for variants '
      'and non-variant products', () async {
    final journal = JournalEntryService(AccountingRepository(db));

    Future<void> postFlow({
      required String type,
      required bool hasVariants,
      required int ordinal,
    }) async {
      final measuredProductId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: '$type product',
              costCents: Decimal.zero,
              priceCents: Decimal.fromInt(20000),
              currencyId: Value(currencyId),
              stockQuantity: const Value(0),
              hasVariants: Value(hasVariants),
              measurementType: Value(type),
            ),
          );
      // The production product-creation path gives even a product with no
      // user-facing variants one internal default variant. StockService
      // relies on that invariant when variantId is omitted by the UI.
      final measuredVariantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: measuredProductId,
              stockQuantity: const Value(0),
              costCents: Decimal.zero,
              priceCents: Decimal.fromInt(20000),
            ),
          );

      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'MEASURED-$type-PI-$ordinal',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(2500),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(2500),
              paidAmountCents: Value(Decimal.fromInt(2500)),
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
              productId: measuredProductId,
              variantId: Value(measuredVariantId),
              quantity: 250,
              quantityScale: const Value(1000),
              measurementType: Value(type),
              unitCostCents: Decimal.fromInt(10000),
              subtotalCents: Decimal.fromInt(2500),
              totalCents: Decimal.fromInt(2500),
            ),
          );
      await db.purchaseDao.postPurchase(purchaseId);
      await journal.recordPurchaseJournalEntry(
        purchaseId: purchaseId,
        totalCents: 2500,
        paidAmountCents: 2500,
        currencyId: currencyId,
        paymentMethod: 'cash',
      );

      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'MEASURED-$type-SI-$ordinal',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(2000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(2000),
              paidAmountCents: Value(Decimal.fromInt(2000)),
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
              productId: measuredProductId,
              variantId: Value(measuredVariantId),
              quantity: 100,
              quantityScale: const Value(1000),
              measurementType: Value(type),
              unitPriceCents: Decimal.fromInt(20000),
              subtotalCents: Decimal.fromInt(2000),
              totalCents: Decimal.fromInt(2000),
            ),
          );
      await db.saleDao.postSale(saleId);
      final saleCost = await db.saleDao.computeSaleCostCents(saleId);
      expect(saleCost, 1000);
      await journal.recordSaleCOGSJournalEntry(
        saleId: saleId,
        costCents: saleCost,
        currencyId: currencyId,
      );
    }

    await postFlow(type: 'length', hasVariants: true, ordinal: 1);
    await postFlow(type: 'weight', hasVariants: true, ordinal: 2);
    await postFlow(type: 'volume', hasVariants: false, ordinal: 3);

    final stockValue = await JournalLocalDatasourceImpl(
      db.accountingDao,
    ).getTotalInventoryValueCents();
    final inventoryGlRow = await db.customSelect('''
        SELECT COALESCE(SUM(jl.debit_cents - jl.credit_cents), 0) AS balance
        FROM journal_entry_lines jl
        INNER JOIN journal_entries je ON je.id = jl.journal_entry_id
        INNER JOIN accounts a ON a.id = jl.account_id
        WHERE a.account_code = '1200' AND je.status = 'posted'
      ''').getSingle();

    // Each flow leaves 150 sub-units × 100.00 / 1000 = 15.00.
    expect(stockValue, 4500);
    expect(inventoryGlRow.read<int>('balance'), stockValue);
  });

  test(
    'measured unlinked sale/purchase returns and ledger rebuild preserve 1200',
    () async {
      final accounting = AccountingRepository(db);
      final journal = JournalEntryService(accounting);

      Future<int> inventoryGl() async {
        final row = await db.customSelect('''
          SELECT COALESCE(SUM(jl.debit_cents - jl.credit_cents), 0) AS balance
          FROM journal_entry_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          JOIN accounts a ON a.id = jl.account_id
          WHERE a.account_code = '1200' AND je.status = 'posted'
        ''').getSingle();
        return row.read<int>('balance');
      }

      var ordinal = 0;
      for (final type in ['length', 'weight', 'volume']) {
        ordinal++;
        final pid = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Adjustment $type',
                costCents: Decimal.zero,
                priceCents: Decimal.fromInt(20000),
                currencyId: Value(currencyId),
                hasVariants: const Value(true),
                measurementType: Value(type),
              ),
            );
        final vid = await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: pid,
                costCents: Decimal.zero,
                priceCents: Decimal.fromInt(20000),
              ),
            );
        final purchaseId = await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                purchaseNumber: 'ADJ-MEASURED-PI-$ordinal',
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
                productId: pid,
                variantId: Value(vid),
                quantity: 1000,
                quantityScale: const Value(1000),
                measurementType: Value(type),
                unitCostCents: Decimal.fromInt(10000),
                subtotalCents: Decimal.fromInt(10000),
                totalCents: Decimal.fromInt(10000),
              ),
            );
        await db.purchaseDao.postPurchase(purchaseId);
        await journal.recordPurchaseJournalEntry(
          purchaseId: purchaseId,
          totalCents: 10000,
          paidAmountCents: 10000,
          currencyId: currencyId,
          paymentMethod: 'cash',
        );

        final saleAdjId = await db.adjustmentReturnDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SRS-MEASURED-$ordinal',
            currencyId: currencyId,
            totalCents: Decimal.fromInt(5000),
            refundMethod: const Value('cash'),
          ),
          [
            SaleReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: pid,
              variantId: Value(vid),
              quantity: 250,
              quantityScale: const Value(1000),
              measurementType: Value(type),
              unitPriceCents: Decimal.fromInt(20000),
              unitCostCents: Value(Decimal.fromInt(10000)),
              totalCents: Decimal.fromInt(5000),
            ),
          ],
        );
        await db.adjustmentReturnDao.postSaleAdjReturn(
          saleAdjId,
          journalEntryService: journal,
          allowOverHistory: true,
        );

        final purchaseAdjId = await db.adjustmentReturnDao
            .createPurchaseAdjReturn(
              PurchaseReturnAdjustmentsCompanion.insert(
                returnNumber: 'PRS-MEASURED-$ordinal',
                supplierId: supplierId,
                currencyId: currencyId,
                totalCents: Decimal.fromInt(2500),
                refundMethod: const Value('credit'),
              ),
              [
                PurchaseReturnAdjustmentItemsCompanion.insert(
                  returnId: 0,
                  productId: pid,
                  variantId: Value(vid),
                  quantity: 250,
                  quantityScale: const Value(1000),
                  measurementType: Value(type),
                  unitPriceCents: Decimal.fromInt(10000),
                  unitCostCents: Value(Decimal.fromInt(10000)),
                  totalCents: Decimal.fromInt(2500),
                ),
              ],
            );
        await db.adjustmentReturnDao.postPurchaseAdjReturn(
          purchaseAdjId,
          journalEntryService: journal,
          allowOverHistory: true,
        );

        final variant = await (db.select(
          db.productVariants,
        )..where((row) => row.id.equals(vid))).getSingle();
        expect(variant.stockQuantity, 1000, reason: type);
      }

      final valuation = await JournalLocalDatasourceImpl(
        db.accountingDao,
      ).getTotalInventoryValueCents();
      expect(valuation, 30000);
      expect(await inventoryGl(), valuation);

      final rebuild = LedgerRebuildService(
        db: db,
        accountingRepo: accounting,
        journalService: journal,
      );
      final report = await rebuild.rebuild(confirmationToken: true);
      expect(report.errors, isEmpty);
      expect(await inventoryGl(), valuation);
    },
  );

  test(
    'fractional unlinked returns store exact pool delta and void cleanly',
    () async {
      final accounting = AccountingRepository(db);
      final posting = ReturnPostingService(
        accountingRepo: accounting,
        policy: ReturnJournalPolicy(accounting),
        fiscalPeriodService: FiscalPeriodService(db),
        creditNoteService: CustomerCreditNoteService(
          db: db,
          accountingRepo: accounting,
        ),
      );
      final journal = JournalEntryService(
        accounting,
        returnPostingService: posting,
      );

      Future<int> inventoryGl() async {
        final row = await db.customSelect('''
          SELECT COALESCE(SUM(jl.debit_cents - jl.credit_cents), 0) AS balance
          FROM journal_entry_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          JOIN accounts a ON a.id = jl.account_id
          WHERE a.account_code = '1200' AND je.status = 'posted'
        ''').getSingle();
        return row.read<int>('balance');
      }

      Future<int> inventoryValue() => JournalLocalDatasourceImpl(
        db.accountingDao,
      ).getTotalInventoryValueCents();

      final lengthProductId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Boundary fabric',
              costCents: Decimal.fromInt(1188),
              priceCents: Decimal.fromInt(2500),
              currencyId: Value(currencyId),
              stockQuantity: const Value(493600),
              hasVariants: const Value(true),
              measurementType: const Value('length'),
            ),
          );
      final lengthVariantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: lengthProductId,
              stockQuantity: const Value(493600),
              costCents: Decimal.fromInt(1188),
              priceCents: Decimal.fromInt(2500),
            ),
          );
      // round(493.6 m x 11.88) = 5,863.97.
      await db
          .into(db.inventoryAdjustments)
          .insert(
            InventoryAdjustmentsCompanion.insert(
              id: const Value(9001),
              adjustmentNumber: 'OPEN-FIXTURE-9001',
              productId: lengthProductId,
              adjustmentType: 'opening_balance',
              quantityDelta: 493600,
              unitCostCents: Decimal.fromInt(1188),
              totalValueCents: Decimal.fromInt(586397),
              reason: 'Opening fixture source',
              currencyId: currencyId,
            ),
          );
      await journal.recordInventoryOpeningBalanceJournalEntry(
        adjustmentId: 9001,
        valueCents: 586397,
        currencyId: currencyId,
        reason: 'fractional-boundary fixture',
      );
      expect(await inventoryGl(), await inventoryValue());

      final purchaseReturnId = await db.adjustmentReturnDao
          .createPurchaseAdjReturn(
            PurchaseReturnAdjustmentsCompanion.insert(
              returnNumber: 'PRS-BOUNDARY-1',
              supplierId: supplierId,
              currencyId: currencyId,
              totalCents: Decimal.fromInt(2138),
              refundMethod: const Value('credit'),
            ),
            [
              PurchaseReturnAdjustmentItemsCompanion.insert(
                returnId: 0,
                productId: lengthProductId,
                variantId: Value(lengthVariantId),
                quantity: 1800,
                quantityScale: const Value(1000),
                measurementType: const Value('length'),
                unitPriceCents: Decimal.fromInt(1188),
                unitCostCents: Value(Decimal.fromInt(1188)),
                totalCents: Decimal.fromInt(2138),
              ),
            ],
          );
      await db.adjustmentReturnDao.postPurchaseAdjReturn(
        purchaseReturnId,
        journalEntryService: journal,
        allowOverHistory: true,
      );
      final purchaseLine = await (db.select(
        db.purchaseReturnAdjustmentItems,
      )..where((i) => i.returnId.equals(purchaseReturnId))).getSingle();
      // Isolated line rounding is 21.38, but 493.6m -> 491.8m removes
      // exactly 21.39 from the rounded SKU pool.
      expect(purchaseLine.totalCents.toBigInt().toInt(), 2138);
      expect(purchaseLine.inventoryValueAtPostCents!.toBigInt().toInt(), 2139);
      expect(await inventoryGl(), await inventoryValue());

      final saleReturnId = await db.adjustmentReturnDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SRS-BOUNDARY-1',
          currencyId: currencyId,
          totalCents: Decimal.fromInt(4500),
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: lengthProductId,
            variantId: Value(lengthVariantId),
            quantity: 1800,
            quantityScale: const Value(1000),
            measurementType: const Value('length'),
            unitPriceCents: Decimal.fromInt(2500),
            unitCostCents: Value(Decimal.fromInt(1188)),
            totalCents: Decimal.fromInt(4500),
          ),
        ],
      );
      await db.adjustmentReturnDao.postSaleAdjReturn(
        saleReturnId,
        journalEntryService: journal,
        allowOverHistory: true,
      );
      final saleLine = await (db.select(
        db.saleReturnAdjustmentItems,
      )..where((i) => i.returnId.equals(saleReturnId))).getSingle();
      expect(saleLine.inventoryValueAtPostCents!.toBigInt().toInt(), 2139);
      expect(await inventoryGl(), await inventoryValue());

      await db.adjustmentReturnDao.voidSaleAdjReturn(
        saleReturnId,
        journalEntryService: journal,
      );
      expect(await inventoryGl(), await inventoryValue());

      await db.adjustmentReturnDao.voidPurchaseAdjReturn(
        purchaseReturnId,
        journalEntryService: journal,
      );
      expect(await inventoryGl(), await inventoryValue());
      expect(await inventoryValue(), 586397);
    },
  );

  test(
    'measured invoice cancellation and edit replacement keep 1200 exact',
    () async {
      final accounting = AccountingRepository(db);
      final journal = JournalEntryService(accounting);

      Future<int> inventoryGl() async {
        final row = await db.customSelect('''
        SELECT COALESCE(SUM(jl.debit_cents - jl.credit_cents), 0) AS balance
        FROM journal_entry_lines jl
        JOIN journal_entries je ON je.id = jl.journal_entry_id
        JOIN accounts a ON a.id = jl.account_id
        WHERE a.account_code = '1200' AND je.status = 'posted'
      ''').getSingle();
        return row.read<int>('balance');
      }

      Future<int> inventoryValue() => JournalLocalDatasourceImpl(
        db.accountingDao,
      ).getTotalInventoryValueCents();

      Future<int> createAndPostPurchase(int quantity, String number) async {
        final lineValue = (1188 * quantity / 1000).round();
        final id = await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                purchaseNumber: number,
                supplierId: supplierId,
                subtotalCents: Decimal.fromInt(lineValue),
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(lineValue),
                paidAmountCents: Value(Decimal.zero),
                currencyId: currencyId,
                paymentMethod: const Value('credit'),
                status: const Value('draft'),
              ),
            );
        await db
            .into(db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                purchaseId: id,
                productId: productId,
                variantId: Value(variantId),
                quantity: quantity,
                quantityScale: const Value(1000),
                measurementType: const Value('weight'),
                unitCostCents: Decimal.fromInt(1188),
                subtotalCents: Decimal.fromInt(lineValue),
                totalCents: Decimal.fromInt(lineValue),
              ),
            );
        await db.purchaseDao.postPurchase(id);
        final financialInventory = await db.purchaseDao
            .computePurchaseInventoryNetCents(id);
        await journal.recordPurchaseJournalEntry(
          purchaseId: id,
          totalCents: lineValue,
          paidAmountCents: 0,
          currencyId: currencyId,
          inventoryNetCents: financialInventory,
          paymentMethod: 'credit',
        );
        final actualInventory = await db.purchaseDao
            .computePurchaseInventoryValueAtPostCents(id);
        final roundingDelta = actualInventory - financialInventory;
        if (roundingDelta != 0) {
          await journal.recordInventoryRoundingJournalEntry(
            sourceTable: 'purchases',
            sourceId: id,
            deltaValueCents: roundingDelta,
            currencyId: currencyId,
            reason: number,
          );
        }
        return id;
      }

      Future<int> createAndPostSale(int quantity, String number) async {
        final total = (2500 * quantity / 1000).round();
        final id = await db
            .into(db.sales)
            .insert(
              SalesCompanion.insert(
                invoiceNumber: number,
                customerId: Value(customerId),
                subtotalCents: Decimal.fromInt(total),
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(total),
                paidAmountCents: Value(Decimal.zero),
                currencyId: currencyId,
                paymentMethod: 'credit',
                status: const Value('draft'),
              ),
            );
        await db
            .into(db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                saleId: id,
                productId: productId,
                variantId: Value(variantId),
                quantity: quantity,
                quantityScale: const Value(1000),
                measurementType: const Value('weight'),
                unitPriceCents: Decimal.fromInt(2500),
                subtotalCents: Decimal.fromInt(total),
                totalCents: Decimal.fromInt(total),
              ),
            );
        await db.saleDao.postSale(id);
        await journal.recordSaleJournalEntry(
          saleId: id,
          totalCents: total,
          paidAmountCents: 0,
          currencyId: currencyId,
          paymentMethod: 'credit',
        );
        await journal.recordSaleCOGSJournalEntry(
          saleId: id,
          costCents: await db.saleDao.computeSaleCostCents(id),
          currencyId: currencyId,
        );
        return id;
      }

      // Reuse the setup's measured SKU but place it on the same boundary as
      // the field report: 491.8 units at 11.88.
      await (db.update(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).write(
        ProductVariantsCompanion(
          stockQuantity: const Value(491800),
          costCents: Value(Decimal.fromInt(1188)),
        ),
      );
      await (db.update(
        db.products,
      )..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          stockQuantity: const Value(491800),
          costCents: Value(Decimal.fromInt(1188)),
        ),
      );
      await db
          .into(db.inventoryAdjustments)
          .insert(
            InventoryAdjustmentsCompanion.insert(
              id: const Value(9002),
              adjustmentNumber: 'OPEN-FIXTURE-9002',
              productId: productId,
              adjustmentType: 'opening_balance',
              quantityDelta: 491800,
              unitCostCents: Decimal.fromInt(1188),
              totalValueCents: Decimal.fromInt(584258),
              reason: 'Opening fixture source',
              currencyId: currencyId,
            ),
          );
      await journal.recordInventoryOpeningBalanceJournalEntry(
        adjustmentId: 9002,
        valueCents: 584258,
        currencyId: currencyId,
        reason: 'invoice cancellation fixture',
      );

      final originalPurchase = await createAndPostPurchase(
        1800,
        'PI-BOUNDARY-ORIGINAL',
      );
      final purchaseItem = await (db.select(
        db.purchaseItems,
      )..where((i) => i.purchaseId.equals(originalPurchase))).getSingle();
      expect(purchaseItem.inventoryValueAtPostCents!.toBigInt().toInt(), 2139);
      expect(await inventoryGl(), await inventoryValue());

      await journal.voidJournalEntriesForSource(
        sourceTable: 'purchases',
        sourceId: originalPurchase,
        reason: 'test edit replacement',
      );
      await db.purchaseDao.voidPurchase(
        originalPurchase,
        journalEntryService: journal,
      );
      expect(await inventoryGl(), await inventoryValue());
      expect(await inventoryValue(), 584258);

      // A posted edit is implemented as void-old + post-new.
      final editedPurchase = await createAndPostPurchase(
        1200,
        'PI-BOUNDARY-EDITED',
      );
      expect(await inventoryGl(), await inventoryValue());

      final originalSale = await createAndPostSale(
        1200,
        'SI-BOUNDARY-ORIGINAL',
      );
      expect(await inventoryGl(), await inventoryValue());
      await journal.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: originalSale,
        reason: 'test edit replacement',
      );
      await db.saleDao.voidSale(originalSale, journalEntryService: journal);
      expect(await inventoryGl(), await inventoryValue());

      await createAndPostSale(600, 'SI-BOUNDARY-EDITED');
      expect(await inventoryGl(), await inventoryValue());

      // Keep the replacement purchase live; its presence proves rebuild input
      // can distinguish financial invoice value from exact carrying value.
      final edited = await db.purchaseDao
          .computePurchaseInventoryValueAtPostCents(editedPurchase);
      expect(edited, greaterThan(0));

      final rebuild = LedgerRebuildService(
        db: db,
        accountingRepo: accounting,
        journalService: journal,
      );
      final report = await rebuild.rebuild(confirmationToken: true);
      expect(report.errors, isEmpty);
      expect(await inventoryGl(), await inventoryValue());
    },
  );
}
