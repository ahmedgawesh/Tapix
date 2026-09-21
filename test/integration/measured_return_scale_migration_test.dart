import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';

void main() {
  test(
    '10065 repairs measured linked return snapshots and inventory journals',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'tapix-measured-return-migration-',
      );
      final file = File('${temp.path}/tapix.db');
      AppDatabase? db;
      try {
        db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
        await db.customSelect('SELECT 1').get();
        final currency = await (db.select(
          db.currencies,
        )..where((row) => row.code.equals('USD'))).getSingle();
        final currencyId = currency.id;
        final supplierId = await db
            .into(db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                name: 'Migration supplier',
                currencyId: currencyId,
                balanceCents: Value(Decimal.zero),
              ),
            );
        final customerId = await db
            .into(db.customers)
            .insert(
              CustomersCompanion.insert(
                name: 'Migration customer',
                currencyId: currencyId,
                balanceCents: Value(Decimal.zero),
              ),
            );
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Measured migration product',
                costCents: Decimal.fromInt(1200),
                priceCents: Decimal.fromInt(2000),
                currencyId: Value(currencyId),
                stockQuantity: const Value(1500),
                measurementType: const Value('length'),
              ),
            );

        final saleId = await db
            .into(db.sales)
            .insert(
              SalesCompanion.insert(
                invoiceNumber: 'SI-MIGRATION',
                customerId: Value(customerId),
                subtotalCents: Decimal.fromInt(2000),
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(2000),
                paidAmountCents: Value(Decimal.fromInt(2000)),
                currencyId: currencyId,
                paymentMethod: 'cash',
                status: const Value('posted'),
              ),
            );
        final saleItemId = await db
            .into(db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                saleId: saleId,
                productId: productId,
                quantity: 1000,
                quantityScale: const Value(1000),
                measurementType: const Value('length'),
                unitPriceCents: Decimal.fromInt(2000),
                subtotalCents: Decimal.fromInt(2000),
                totalCents: Decimal.fromInt(2000),
                costCents: Value(Decimal.fromInt(1200)),
              ),
            );
        final saleReturnId = await db
            .into(db.saleReturns)
            .insert(
              SaleReturnsCompanion.insert(
                saleId: saleId,
                returnNumber: 'SR-MIGRATION',
                totalCents: Decimal.fromInt(2000),
                currencyId: currencyId,
                status: const Value('posted'),
              ),
            );
        await db
            .into(db.saleReturnItems)
            .insert(
              SaleReturnItemsCompanion.insert(
                returnId: saleReturnId,
                saleItemId: saleItemId,
                quantity: 1000,
                // Reproduce v10063-v10064 defect: defaults are scale=1/piece.
                refundCents: Decimal.fromInt(2000),
                unitCostAtPostCents: Value(Decimal.fromInt(1200)),
              ),
            );

        final purchaseId = await db
            .into(db.purchases)
            .insert(
              PurchasesCompanion.insert(
                purchaseNumber: 'PI-MIGRATION',
                supplierId: supplierId,
                subtotalCents: Decimal.fromInt(600),
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(600),
                paidAmountCents: Value(Decimal.zero),
                currencyId: currencyId,
                status: const Value('posted'),
              ),
            );
        final purchaseItemId = await db
            .into(db.purchaseItems)
            .insert(
              PurchaseItemsCompanion.insert(
                purchaseId: purchaseId,
                productId: productId,
                quantity: 500,
                quantityScale: const Value(1000),
                measurementType: const Value('length'),
                unitCostCents: Decimal.fromInt(1200),
                subtotalCents: Decimal.fromInt(600),
                totalCents: Decimal.fromInt(600),
              ),
            );
        final purchaseReturnId = await db
            .into(db.purchaseReturns)
            .insert(
              PurchaseReturnsCompanion.insert(
                purchaseId: purchaseId,
                returnNumber: 'PR-MIGRATION',
                totalCents: Decimal.fromInt(600),
                currencyId: currencyId,
                status: const Value('posted'),
              ),
            );
        await db
            .into(db.purchaseReturnItems)
            .insert(
              PurchaseReturnItemsCompanion.insert(
                returnId: purchaseReturnId,
                purchaseItemId: purchaseItemId,
                quantity: 500,
                // Reproduce v10063-v10064 defect: defaults are scale=1/piece.
                refundCents: Decimal.fromInt(600),
                unitCostAtPostCents: Value(Decimal.fromInt(1200)),
              ),
            );

        Future<int> accountId(String code) async {
          final account = await (db!.select(
            db.accounts,
          )..where((row) => row.accountCode.equals(code))).getSingle();
          return account.id;
        }

        final inventoryId = await accountId('1200');
        final cogsId = await accountId('5300');
        final apId = await accountId('2000');
        final purchaseReturnsId = await accountId('4100');
        final accounting = AccountingRepository(db);

        await accounting.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Corrupt measured sale return COGS',
            debitAccountId: inventoryId,
            creditAccountId: cogsId,
            amountCents: 1200000,
            currencyId: currencyId,
            entryType: 'sale_return',
            sourceTable: 'sale_returns',
            sourceId: saleReturnId,
          ),
          userId: null,
        );
        await accounting.createJournalEntry(
          entryData: JournalEntryData(
            description: 'Corrupt measured purchase return',
            entryType: 'purchase_return',
            sourceTable: 'purchase_returns',
            sourceId: purchaseReturnId,
            autoPost: true,
            lines: [
              JournalEntryLineData(
                accountId: apId,
                debitCents: 600,
                creditCents: 0,
                currencyId: currencyId,
              ),
              JournalEntryLineData(
                accountId: purchaseReturnsId,
                debitCents: 0,
                creditCents: 600,
                currencyId: currencyId,
              ),
              JournalEntryLineData(
                accountId: purchaseReturnsId,
                debitCents: 600000,
                creditCents: 0,
                currencyId: currencyId,
              ),
              JournalEntryLineData(
                accountId: inventoryId,
                debitCents: 0,
                creditCents: 600000,
                currencyId: currencyId,
              ),
            ],
          ),
          userId: null,
        );

        await db.customStatement('PRAGMA user_version = 10064');
        await db.close();
        db = null;

        db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
        await db.customSelect('SELECT 1').get();

        final saleReturnItem = await (db.select(
          db.saleReturnItems,
        )..where((row) => row.returnId.equals(saleReturnId))).getSingle();
        final purchaseReturnItem = await (db.select(
          db.purchaseReturnItems,
        )..where((row) => row.returnId.equals(purchaseReturnId))).getSingle();
        expect(saleReturnItem.quantityScale, 1000);
        expect(saleReturnItem.measurementType, 'length');
        expect(purchaseReturnItem.quantityScale, 1000);
        expect(purchaseReturnItem.measurementType, 'length');

        Future<int> netFor(String source, int sourceId, String code) async {
          final row = await db!
              .customSelect(
                'SELECT COALESCE(SUM(jel.debit_cents - jel.credit_cents), 0) '
                'AS net FROM journal_entry_lines jel '
                'JOIN journal_entries je ON je.id = jel.journal_entry_id '
                'JOIN accounts a ON a.id = jel.account_id '
                'WHERE je.source_table = ? AND je.source_id = ? '
                'AND je.status = ? AND a.account_code = ?',
                variables: [
                  Variable.withString(source),
                  Variable.withInt(sourceId),
                  Variable.withString('posted'),
                  Variable.withString(code),
                ],
              )
              .getSingle();
          return row.read<int>('net');
        }

        expect(netFor('sale_returns', saleReturnId, '1200'), completion(1200));
        expect(netFor('sale_returns', saleReturnId, '5300'), completion(-1200));
        expect(
          netFor('purchase_returns', purchaseReturnId, '1200'),
          completion(-600),
        );
        expect(
          netFor('purchase_returns', purchaseReturnId, '4100'),
          completion(0),
        );

        final unbalanced = await db
            .customSelect(
              'SELECT COUNT(*) AS count FROM journal_entries '
              'WHERE total_debit_cents != total_credit_cents',
            )
            .getSingle();
        expect(unbalanced.read<int>('count'), 0);
        final inventory = await (db.select(
          db.accounts,
        )..where((row) => row.accountCode.equals('1200'))).getSingle();
        expect(inventory.balanceCents.toBigInt().toInt(), 600);
      } finally {
        await db?.close();
        await temp.delete(recursive: true);
      }
    },
  );

  test('10066 repairs the one-cent measured purchase-return drift', () async {
    final temp = await Directory.systemTemp.createTemp(
      'tapix-measured-rounding-migration-',
    );
    final file = File('${temp.path}/tapix.db');
    AppDatabase? db;
    try {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      final currency = await (db.select(
        db.currencies,
      )..where((row) => row.code.equals('USD'))).getSingle();
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Rounding supplier',
              currencyId: currency.id,
              balanceCents: Value(Decimal.zero),
            ),
          );
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Rounding fabric',
              costCents: Decimal.fromInt(1188),
              priceCents: Decimal.fromInt(2500),
              currencyId: Value(currency.id),
              stockQuantity: const Value(491800),
              hasVariants: const Value(true),
              measurementType: const Value('length'),
            ),
          );
      final variantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              stockQuantity: const Value(491800),
              costCents: Decimal.fromInt(1188),
              priceCents: Decimal.fromInt(2500),
            ),
          );
      final returnId = await db
          .into(db.purchaseReturnAdjustments)
          .insert(
            PurchaseReturnAdjustmentsCompanion.insert(
              returnNumber: 'PRS-MIGRATION-ROUNDING',
              supplierId: supplierId,
              currencyId: currency.id,
              totalCents: Decimal.fromInt(2138),
              refundMethod: const Value('credit'),
              status: const Value('posted'),
            ),
          );
      await db
          .into(db.purchaseReturnAdjustmentItems)
          .insert(
            PurchaseReturnAdjustmentItemsCompanion.insert(
              returnId: returnId,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1800,
              quantityScale: const Value(1000),
              measurementType: const Value('length'),
              unitPriceCents: Decimal.fromInt(1188),
              unitCostCents: Value(Decimal.fromInt(1188)),
              unitCostAtPostCents: Value(Decimal.fromInt(1188)),
              totalCents: Decimal.fromInt(2138),
              inventoryValueAtPostCents: const Value.absent(),
            ),
          );

      Future<int> accountId(String code) async {
        final account = await (db!.select(
          db.accounts,
        )..where((row) => row.accountCode.equals(code))).getSingle();
        return account.id;
      }

      final inventoryId = await accountId('1200');
      final openingId = await accountId('3100');
      final payableId = await accountId('2000');
      final purchaseReturnId = await accountId('4100');
      final accounting = AccountingRepository(db);
      await db
          .into(db.inventoryAdjustments)
          .insert(
            InventoryAdjustmentsCompanion.insert(
              id: const Value(991),
              adjustmentNumber: 'OPEN-FIXTURE-991',
              productId: productId,
              adjustmentType: 'opening_balance',
              quantityDelta: 493600,
              unitCostCents: Decimal.fromInt(1188),
              totalValueCents: Decimal.fromInt(586397),
              reason: 'Opening fixture source',
              currencyId: currency.id,
            ),
          );
      await accounting.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Opening measured pool',
          debitAccountId: inventoryId,
          creditAccountId: openingId,
          amountCents: 586397,
          currencyId: currency.id,
          entryType: 'opening_balance',
          sourceTable: 'inventory_adjustments',
          sourceId: 991,
        ),
        userId: null,
      );
      await accounting.createJournalEntry(
        entryData: JournalEntryData(
          description: 'Legacy rounded purchase adjustment return',
          entryType: 'purchase_return',
          sourceTable: 'purchase_return_adjustments',
          sourceId: returnId,
          autoPost: true,
          lines: [
            JournalEntryLineData(
              accountId: payableId,
              debitCents: 2138,
              creditCents: 0,
              currencyId: currency.id,
            ),
            JournalEntryLineData(
              accountId: purchaseReturnId,
              debitCents: 0,
              creditCents: 2138,
              currencyId: currency.id,
            ),
            JournalEntryLineData(
              accountId: purchaseReturnId,
              debitCents: 2138,
              creditCents: 0,
              currencyId: currency.id,
            ),
            JournalEntryLineData(
              accountId: inventoryId,
              debitCents: 0,
              creditCents: 2138,
              currencyId: currency.id,
            ),
          ],
        ),
        userId: null,
      );
      await db.customStatement('PRAGMA user_version = 10065');
      await db.close();
      db = null;

      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      final item = await (db.select(
        db.purchaseReturnAdjustmentItems,
      )..where((row) => row.returnId.equals(returnId))).getSingle();
      expect(item.inventoryValueAtPostCents!.toBigInt().toInt(), 2139);

      final values = await db
          .customSelect(
            '''
        SELECT
          (SELECT COALESCE(SUM(jel.debit_cents - jel.credit_cents), 0)
             FROM journal_entry_lines jel
             JOIN journal_entries je ON je.id = jel.journal_entry_id
             JOIN accounts a ON a.id = jel.account_id
            WHERE je.status = 'posted' AND a.account_code = '1200') AS gl,
          CAST(ROUND(1.0 * pv.stock_quantity * pv.cost_cents / 1000)
               AS INTEGER) AS stock
        FROM product_variants pv WHERE pv.id = ?
      ''',
            variables: [Variable.withInt(variantId)],
          )
          .getSingle();
      expect(values.read<int>('gl'), 584258);
      expect(values.read<int>('stock'), 584258);

      final unbalanced = await db
          .customSelect(
            'SELECT COUNT(*) AS count FROM journal_entries '
            'WHERE total_debit_cents != total_credit_cents',
          )
          .getSingle();
      expect(unbalanced.read<int>('count'), 0);
      final inventory = await (db.select(
        db.accounts,
      )..where((row) => row.accountCode.equals('1200'))).getSingle();
      expect(inventory.balanceCents.toBigInt().toInt(), 584258);
    } finally {
      await db?.close();
      await temp.delete(recursive: true);
    }
  });
}
