import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late int currencyId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    journal = JournalEntryService(AccountingRepository(db));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((row) => row.code.equals('USD'))).getSingle()).id;
  });

  tearDown(() => db.close());

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

  Future<void> expectInventoryReconciled() async {
    expect(await inventoryGl(), await inventoryValue());
  }

  test('offer lines sharing one measured variant keep sale, return and void '
      'inventory accounting exact', () async {
    const openingQuantity = 493600;
    const unitCostCents = 1188;
    const openingValueCents = 586397;

    final productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Promoted measured fabric',
            costCents: Decimal.fromInt(unitCostCents),
            priceCents: Decimal.fromInt(2500),
            currencyId: Value(currencyId),
            stockQuantity: const Value(openingQuantity),
            hasVariants: const Value(true),
            costingMethod: const Value('wac'),
            inventoryTrackingType: const Value('standard'),
            measurementType: const Value('length'),
          ),
        );
    final variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            sku: const Value('PROMO-LENGTH-1'),
            costCents: Decimal.fromInt(unitCostCents),
            priceCents: Decimal.fromInt(2500),
            stockQuantity: const Value(openingQuantity),
          ),
        );
    await db
        .into(db.inventoryAdjustments)
        .insert(
          InventoryAdjustmentsCompanion.insert(
            id: const Value(99001),
            adjustmentNumber: 'OPEN-FIXTURE-99001',
            productId: productId,
            adjustmentType: 'opening_balance',
            quantityDelta: openingQuantity,
            unitCostCents: Decimal.fromInt(unitCostCents),
            totalValueCents: Decimal.fromInt(openingValueCents),
            reason: 'Opening fixture source',
            currencyId: currencyId,
          ),
        );
    await journal.recordInventoryOpeningBalanceJournalEntry(
      adjustmentId: 99001,
      valueCents: openingValueCents,
      currencyId: currencyId,
      reason: 'duplicate promotion-line regression fixture',
    );
    await expectInventoryReconciled();

    final promotionId = await db
        .into(db.promotions)
        .insert(
          PromotionsCompanion.insert(
            code: 'DUPLICATE-LINE-10',
            name: 'Two metres get 10%',
            promotionType: 'quantity',
            status: const Value('active'),
          ),
        );
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'SI-DUPLICATE-PROMO-1',
            subtotalCents: Decimal.fromInt(5000),
            discountCents: Value(Decimal.fromInt(500)),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(4500),
            paidAmountCents: Value(Decimal.fromInt(4500)),
            currencyId: currencyId,
            paymentMethod: 'cash',
            status: const Value('draft'),
          ),
        );
    final saleItemIds = <int>[];
    for (var index = 0; index < 2; index++) {
      saleItemIds.add(
        await db
            .into(db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                saleId: saleId,
                productId: productId,
                variantId: Value(variantId),
                quantity: 1000,
                quantityScale: const Value(1000),
                measurementType: const Value('length'),
                unitPriceCents: Decimal.fromInt(2500),
                subtotalCents: Decimal.fromInt(2500),
                discountCents: Value(Decimal.fromInt(250)),
                totalCents: Decimal.fromInt(2250),
              ),
            ),
      );
    }
    final applicationId = await db
        .into(db.salePromotionApplications)
        .insert(
          SalePromotionApplicationsCompanion.insert(
            saleId: saleId,
            promotionId: promotionId,
            promotionCode: 'DUPLICATE-LINE-10',
            promotionName: 'Two metres get 10%',
            promotionVersion: 1,
            promotionType: 'quantity',
            concurrencyMode: 'best_price',
            applicationCount: const Value(1),
            discountCents: Decimal.fromInt(500),
            promotionEngineVersion: 'promotion-v3',
            calculationSnapshotJson: '{}',
          ),
        );
    for (final saleItemId in saleItemIds) {
      await db
          .into(db.saleItemPromotionAllocations)
          .insert(
            SaleItemPromotionAllocationsCompanion.insert(
              applicationId: applicationId,
              saleItemId: saleItemId,
              discountCents: Decimal.fromInt(250),
              appliedQuantity: 1000,
              quantityScale: const Value(1000),
              originalUnitPriceCents: Decimal.fromInt(2500),
              rewardType: 'percentage_off',
            ),
          );
    }

    await db.saleDao.postSale(saleId);
    await journal.recordSaleJournalEntry(
      saleId: saleId,
      totalCents: 4500,
      paidAmountCents: 4500,
      currencyId: currencyId,
      paymentMethod: 'cash',
    );
    final saleCost = await db.saleDao.computeSaleCostCents(saleId);
    await journal.recordSaleCOGSJournalEntry(
      saleId: saleId,
      costCents: saleCost,
      currencyId: currencyId,
    );

    final postedLines = await (db.select(
      db.saleItems,
    )..where((row) => row.saleId.equals(saleId))).get();
    expect(
      postedLines
          .map((row) => row.inventoryValueAtPostCents!.toBigInt().toInt())
          .toList(),
      [1188, 1188],
    );
    expect(saleCost, 2376);
    await expectInventoryReconciled();

    // Return half of each separate sale line. The original promotion is a
    // frozen commercial snapshot; inventory must still reverse from each
    // line's frozen cost independently.
    final returnId = await db.saleDao.createSaleReturn(
      SaleReturnsCompanion.insert(
        saleId: saleId,
        returnNumber: 'SR-DUPLICATE-PROMO-1',
        subtotalCents: Value(Decimal.fromInt(2500)),
        discountCents: Value(Decimal.fromInt(250)),
        taxCents: Value(Decimal.zero),
        totalCents: Decimal.fromInt(2250),
        currencyId: currencyId,
        refundMethod: const Value('cash'),
        status: const Value('draft'),
      ),
      [
        for (final saleItemId in saleItemIds)
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: saleItemId,
            quantity: 500,
            quantityScale: const Value(1000),
            measurementType: const Value('length'),
            subtotalCents: Value(Decimal.fromInt(1250)),
            discountCents: Value(Decimal.fromInt(125)),
            taxCents: Value(Decimal.zero),
            refundCents: Decimal.fromInt(1125),
          ),
      ],
    );
    await db.saleDao.postSaleReturn(returnId);
    await journal.recordSaleReturnJournalEntry(
      returnId: returnId,
      totalCents: 2250,
      currencyId: currencyId,
      refundMethod: 'cash',
    );
    final returnCost = await db.saleDao.computeSaleReturnCostCents(returnId);
    await journal.recordSaleReturnCOGSReversalJournalEntry(
      returnId: returnId,
      costCents: returnCost,
      currencyId: currencyId,
    );
    expect(returnCost, 1188);
    await expectInventoryReconciled();

    await journal.voidJournalEntriesForSource(
      sourceTable: 'sale_returns',
      sourceId: returnId,
      reason: 'regression test return void',
    );
    await db.saleDao.voidSaleReturn(returnId);
    await expectInventoryReconciled();

    await journal.voidJournalEntriesForSource(
      sourceTable: 'sales',
      sourceId: saleId,
      reason: 'regression test sale void',
    );
    await db.saleDao.voidSale(saleId, journalEntryService: journal);
    await expectInventoryReconciled();
    expect(await inventoryValue(), openingValueCents);
  });
}
