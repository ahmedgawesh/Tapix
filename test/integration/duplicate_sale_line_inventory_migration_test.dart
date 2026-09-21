import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  test('10072 repairs only the cumulative duplicate-line shape and its void '
      'reverses the correction', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tapix-duplicate-sale-migration-',
    );
    final file = File('${directory.path}/tapix.db');
    AppDatabase? db;
    try {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      final currencyId = (await (db.select(
        db.currencies,
      )..where((row) => row.code.equals('USD'))).getSingle()).id;
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Legacy promoted fabric',
              costCents: Decimal.fromInt(1188),
              priceCents: Decimal.fromInt(2500),
              currencyId: Value(currencyId),
              stockQuantity: const Value(482300),
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
              costCents: Decimal.fromInt(1188),
              priceCents: Decimal.fromInt(2500),
              stockQuantity: const Value(482300),
            ),
          );
      final journal = JournalEntryService(AccountingRepository(db));

      await db
          .into(db.inventoryAdjustments)
          .insert(
            InventoryAdjustmentsCompanion.insert(
              id: const Value(10072001),
              adjustmentNumber: 'OPEN-FIXTURE-10072001',
              productId: productId,
              adjustmentType: 'opening_balance',
              quantityDelta: 482300,
              unitCostCents: Decimal.fromInt(1188),
              totalValueCents: Decimal.fromInt(575348),
              reason: 'Opening fixture source',
              currencyId: currencyId,
            ),
          );
      await journal.recordInventoryOpeningBalanceJournalEntry(
        adjustmentId: 10072001,
        valueCents: 575348,
        currencyId: currencyId,
        reason: 'pre-sale stock fixture',
      );
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'SI-LEGACY-OVERLAP-1',
              subtotalCents: Decimal.fromInt(5000),
              discountCents: Value(Decimal.fromInt(500)),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(4500),
              paidAmountCents: Value(Decimal.fromInt(4500)),
              currencyId: currencyId,
              paymentMethod: 'cash',
              status: const Value('completed'),
            ),
          );
      for (final storedValue in [2376, 1188]) {
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
                costCents: Value(Decimal.fromInt(1188)),
                inventoryValueAtPostCents: Value(Decimal.fromInt(storedValue)),
              ),
            );
      }
      await journal.recordSaleCOGSJournalEntry(
        saleId: saleId,
        costCents: 3564,
        currencyId: currencyId,
      );

      Future<int> inventoryGl(AppDatabase database) async {
        final row = await database.customSelect('''
            SELECT COALESCE(SUM(jl.debit_cents - jl.credit_cents), 0) AS value
            FROM journal_entry_lines jl
            JOIN journal_entries je ON je.id = jl.journal_entry_id
            JOIN accounts a ON a.id = jl.account_id
            WHERE je.status = 'posted' AND a.account_code = '1200'
          ''').getSingle();
        return row.read<int>('value');
      }

      Future<int> inventoryValue(AppDatabase database) =>
          JournalLocalDatasourceImpl(
            database.accountingDao,
          ).getTotalInventoryValueCents();

      expect(await inventoryValue(db) - await inventoryGl(db), 1188);

      // Simulate opening a database created by the affected v10071 build.
      await db.customStatement('PRAGMA user_version = 10071');
      await db.close();
      db = null;

      final migrated = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      db = migrated;
      await migrated.customSelect('SELECT 1').get();
      expect(migrated.schemaVersion, 10091);

      final lines = await (migrated.select(
        migrated.saleItems,
      )..where((row) => row.saleId.equals(saleId))).get();
      expect(
        lines
            .map((row) => row.inventoryValueAtPostCents!.toBigInt().toInt())
            .toList(),
        [1188, 1188],
      );
      expect(await inventoryGl(migrated), await inventoryValue(migrated));

      final correction =
          await (migrated.select(migrated.journalEntries)..where(
                (row) =>
                    row.sourceTable.equals('sales') &
                    row.sourceId.equals(saleId) &
                    row.entryType.equals('sale_cogs_correction'),
              ))
              .getSingle();
      expect(correction.totalDebitCents.toBigInt().toInt(), 1188);
      expect(correction.totalCreditCents.toBigInt().toInt(), 1188);
      final audit =
          await (migrated.select(migrated.auditLogs)..where(
                (row) =>
                    row.targetTable.equals('sales') &
                    row.recordId.equals(saleId) &
                    row.action.equals('repair_inventory_valuation'),
              ))
              .getSingle();
      expect(audit.changes['correctionCents'], 1188);

      // The corrective entry shares the sale source, so normal cancellation
      // reverses it together with the original bad COGS posting.
      final migratedJournal = JournalEntryService(
        AccountingRepository(migrated),
      );
      await migratedJournal.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: saleId,
        reason: 'migration regression void',
      );
      await migrated.saleDao.voidSale(
        saleId,
        journalEntryService: migratedJournal,
      );
      expect(await inventoryGl(migrated), await inventoryValue(migrated));
      expect(await inventoryValue(migrated), 575348);
    } finally {
      await db?.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });
}
