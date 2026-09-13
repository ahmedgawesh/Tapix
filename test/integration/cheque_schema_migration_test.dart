import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';

void main() {
  test('10081 adds bounced-cheque resolution columns', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tapix-cheque-resolution-migration-',
    );
    final file = File('${directory.path}/tapix.db');
    AppDatabase? db;
    try {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      for (final column in const [
        'resolution_type',
        'resolution_journal_entry_id',
        'resolved_at',
        'resolution_note',
      ]) {
        await db.customStatement(
          'ALTER TABLE cheque_instruments DROP COLUMN $column',
        );
      }
      await db.customStatement('PRAGMA user_version = 10079');
      await db.close();
      db = null;

      final migrated = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      db = migrated;
      await migrated.customSelect('SELECT 1').get();
      final columns = await migrated
          .customSelect('PRAGMA table_info(cheque_instruments)')
          .get();
      final names = columns.map((row) => row.read<String>('name')).toSet();

      expect(migrated.schemaVersion, 10082);
      expect(
        names,
        containsAll(const [
          'resolution_type',
          'resolution_journal_entry_id',
          'resolved_at',
          'resolution_note',
        ]),
      );
    } finally {
      await db?.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('10074 repairs a legacy cheque instrument payment link', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tapix-cheque-migration-',
    );
    final file = File('${directory.path}/tapix.db');
    AppDatabase? db;
    try {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(name: 'Legacy customer', currencyId: 1),
          );
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'LEGACY-CHEQUE-1',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(7500),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(7500),
              paidAmountCents: Value(Decimal.fromInt(7500)),
              currencyId: 1,
              paymentMethod: 'cheque',
              status: const Value('completed'),
              dueDate: Value(DateTime(2026, 9, 20)),
            ),
          );
      final paymentId = await db
          .into(db.salePayments)
          .insert(
            SalePaymentsCompanion.insert(
              saleId: saleId,
              amountCents: Decimal.fromInt(7500),
              currencyId: 1,
              paymentMethod: 'cheque',
            ),
          );
      final chequeId = await ChequeInstrumentDao(db).create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.sale,
        sourceId: saleId,
        amountCents: 7500,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'customer',
        partyId: customerId,
        legacyDirectBank: true,
      );
      await db.customStatement('PRAGMA user_version = 10073');
      await db.close();
      db = null;

      final migrated = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      db = migrated;
      await migrated.customSelect('SELECT 1').get();

      expect(migrated.schemaVersion, 10082);
      final cheque = await ChequeInstrumentDao(migrated).getById(chequeId);
      expect(cheque?.settlementPaymentId, paymentId);
    } finally {
      await db?.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('10081 restores an open return cheque to deferred settlement', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tapix-return-cheque-migration-',
    );
    final file = File('${directory.path}/tapix.db');
    AppDatabase? db;
    try {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(name: 'Return customer', currencyId: 1),
          );
      await db
          .into(db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: customerId,
              transactionType: 'cheque_return_pending',
              amountCents: Decimal.fromInt(-1250),
              currencyId: 1,
              referenceType: const Value('sale_return'),
              referenceId: const Value(91),
            ),
          );
      final chequeId = await ChequeInstrumentDao(db).create(
        direction: ChequeDirectionValue.outgoing,
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: 91,
        amountCents: 1250,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'customer',
        partyId: customerId,
      );
      await db.customStatement('PRAGMA user_version = 10076');
      await db.close();
      db = null;

      final migrated = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      db = migrated;
      await migrated.customSelect('SELECT 1').get();

      final customer = await (migrated.select(
        migrated.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      expect(customer.balanceCents, Decimal.fromInt(-1250));
      final transaction = await (migrated.select(
        migrated.customerTransactions,
      )..where((row) => row.referenceType.equals('sale_return'))).getSingle();
      expect(transaction.transactionType, 'cheque_return_pending');
      final cheque = await ChequeInstrumentDao(migrated).getById(chequeId);
      expect(cheque?.settlementPaymentId, isNull);
      final recognitionTransactions =
          await (migrated.select(migrated.customerTransactions)..where(
                (row) =>
                    row.referenceType.equals('cheque_instrument') &
                    row.referenceId.equals(chequeId) &
                    row.transactionType.equals('cheque_return_settlement'),
              ))
              .get();
      expect(recognitionTransactions, hasLength(1));
      final reversalTransactions =
          await (migrated.select(migrated.customerTransactions)..where(
                (row) =>
                    row.referenceType.equals('cheque_instrument') &
                    row.referenceId.equals(chequeId) &
                    row.transactionType.equals(
                      'cheque_return_settlement_reversal',
                    ),
              ))
              .get();
      expect(reversalTransactions, hasLength(1));
      final entries =
          await (migrated.select(migrated.journalEntries)..where(
                (row) =>
                    row.sourceTable.equals('cheque_instruments') &
                    row.sourceId.equals(chequeId) &
                    row.entryType.equals('cheque_return_settlement'),
              ))
              .get();
      expect(entries, hasLength(1));
      expect(entries.single.isReversed, isTrue);
    } finally {
      await db?.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test('10081 restores open invoice cheques to deferred settlement', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tapix-invoice-cheque-migration-',
    );
    final file = File('${directory.path}/tapix.db');
    AppDatabase? db;
    try {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Invoice customer',
              currencyId: 1,
              balanceCents: Value(Decimal.fromInt(6500)),
            ),
          );
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Invoice supplier',
              currencyId: 1,
              balanceCents: Value(Decimal.fromInt(6550)),
            ),
          );
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'SI-MIGRATION-CHEQUE',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(6500),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(6500),
              paidAmountCents: Value(Decimal.zero),
              currencyId: 1,
              paymentMethod: 'cheque',
              status: const Value('completed'),
            ),
          );
      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'PI-MIGRATION-CHEQUE',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(6550),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(6550),
              paidAmountCents: Value(Decimal.zero),
              currencyId: 1,
              paymentMethod: const Value('cheque'),
              status: const Value('posted'),
            ),
          );
      final instrumentDao = ChequeInstrumentDao(db);
      final saleChequeId = await instrumentDao.create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.sale,
        sourceId: saleId,
        amountCents: 6500,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'customer',
        partyId: customerId,
        chequeNumber: 'SALE-6500',
      );
      final purchaseCheque1Id = await instrumentDao.create(
        direction: ChequeDirectionValue.outgoing,
        sourceTable: ChequeSourceTables.purchase,
        sourceId: purchaseId,
        amountCents: 1000,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'supplier',
        partyId: supplierId,
        chequeNumber: 'PURCHASE-1000',
      );
      final purchaseCheque2Id = await instrumentDao.create(
        direction: ChequeDirectionValue.outgoing,
        sourceTable: ChequeSourceTables.purchase,
        sourceId: purchaseId,
        amountCents: 5550,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'supplier',
        partyId: supplierId,
        chequeNumber: 'PURCHASE-5550',
      );
      await db.customStatement('PRAGMA user_version = 10077');
      await db.close();
      db = null;

      final migrated = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      db = migrated;
      await migrated.customSelect('SELECT 1').get();

      expect(migrated.schemaVersion, 10082);
      final sale = await (migrated.select(
        migrated.sales,
      )..where((row) => row.id.equals(saleId))).getSingle();
      final purchase = await (migrated.select(
        migrated.purchases,
      )..where((row) => row.id.equals(purchaseId))).getSingle();
      final customer = await (migrated.select(
        migrated.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      final supplier = await (migrated.select(
        migrated.suppliers,
      )..where((row) => row.id.equals(supplierId))).getSingle();
      expect(sale.paidAmountCents, Decimal.zero);
      expect(purchase.paidAmountCents, Decimal.zero);
      expect(customer.balanceCents, Decimal.fromInt(6500));
      expect(supplier.balanceCents, Decimal.fromInt(6550));

      for (final id in [saleChequeId, purchaseCheque1Id, purchaseCheque2Id]) {
        final cheque = await ChequeInstrumentDao(migrated).getById(id);
        expect(cheque?.settlementPaymentId, isNull);
        expect(cheque?.clearanceJournalEntryId, isNull);
      }

      Future<int> accountNet(String source, String code) async {
        final row = await migrated
            .customSelect(
              'SELECT COALESCE(SUM(jel.debit_cents - jel.credit_cents), 0) AS net '
              'FROM journal_entries je '
              'JOIN journal_entry_lines jel ON jel.journal_entry_id = je.id '
              'JOIN accounts a ON a.id = jel.account_id '
              "WHERE je.source_table = ? AND je.status = 'posted' "
              'AND je.is_reversed = 0 '
              'AND a.account_code = ?',
              variables: [
                Variable.withString(source),
                Variable.withString(code),
              ],
            )
            .getSingle();
        return row.read<int>('net');
      }

      expect(await accountNet('sale_payments', '1020'), 0);
      expect(await accountNet('sale_payments', '1100'), 0);
      expect(await accountNet('purchase_payments', '2000'), 0);
      expect(await accountNet('purchase_payments', '2020'), 0);
      expect(await accountNet('sale_payments', '1010'), 0);
      expect(await accountNet('purchase_payments', '1010'), 0);
    } finally {
      await db?.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test(
    '10079 reclassifies only historical incoming bounced cheques to 1030',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tapix-dishonoured-cheque-migration-',
      );
      final file = File('${directory.path}/tapix.db');
      AppDatabase? db;
      try {
        db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
        await db.customSelect('SELECT 1').get();
        final customerId = await db
            .into(db.customers)
            .insert(
              CustomersCompanion.insert(
                name: 'Bounced cheque customer',
                currencyId: 1,
                balanceCents: Value(Decimal.fromInt(1000)),
              ),
            );
        final supplierId = await db
            .into(db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                name: 'Bounced cheque supplier',
                currencyId: 1,
                balanceCents: Value(Decimal.fromInt(-2000)),
              ),
            );
        final dao = ChequeInstrumentDao(db);
        final saleChequeId = await dao.create(
          direction: ChequeDirectionValue.incoming,
          sourceTable: ChequeSourceTables.sale,
          sourceId: 101,
          amountCents: 1000,
          currencyId: 1,
          dueDate: DateTime(2026, 9, 1),
          partyType: 'customer',
          partyId: customerId,
        );
        await dao.writeLifecycle(
          id: saleChequeId,
          status: ChequeInstrumentStatus.bounced,
          bounceReason: 'Customer cheque rejected',
        );
        final purchaseReturnChequeId = await dao.create(
          direction: ChequeDirectionValue.incoming,
          sourceTable: ChequeSourceTables.purchaseReturnAdjustment,
          sourceId: 102,
          amountCents: 2000,
          currencyId: 1,
          dueDate: DateTime(2026, 9, 1),
          partyType: 'supplier',
          partyId: supplierId,
        );
        await dao.writeLifecycle(
          id: purchaseReturnChequeId,
          status: ChequeInstrumentStatus.bounced,
          bounceReason: 'Supplier cheque rejected',
        );
        final outgoingChequeId = await dao.create(
          direction: ChequeDirectionValue.outgoing,
          sourceTable: ChequeSourceTables.purchase,
          sourceId: 103,
          amountCents: 3000,
          currencyId: 1,
          dueDate: DateTime(2026, 9, 1),
          partyType: 'supplier',
          partyId: supplierId,
        );
        await dao.writeLifecycle(
          id: outgoingChequeId,
          status: ChequeInstrumentStatus.bounced,
          bounceReason: 'Our cheque rejected',
        );
        final cancelledChequeId = await dao.create(
          direction: ChequeDirectionValue.incoming,
          sourceTable: ChequeSourceTables.sale,
          sourceId: 104,
          amountCents: 4000,
          currencyId: 1,
          dueDate: DateTime(2026, 9, 1),
          partyType: 'customer',
          partyId: customerId,
        );
        await dao.writeLifecycle(
          id: cancelledChequeId,
          status: ChequeInstrumentStatus.cancelled,
        );
        await db.customStatement('PRAGMA user_version = 10078');
        await db.close();
        db = null;

        final migrated = AppDatabase.connect(
          DatabaseConnection(NativeDatabase(file)),
        );
        db = migrated;
        await migrated.customSelect('SELECT 1').get();
        expect(migrated.schemaVersion, 10082);

        Future<int> instrumentAccountNet(int instrumentId, String code) async {
          final row = await migrated
              .customSelect(
                'SELECT COALESCE(SUM(jel.debit_cents - jel.credit_cents), 0) AS net '
                'FROM journal_entries je '
                'JOIN journal_entry_lines jel ON jel.journal_entry_id = je.id '
                'JOIN accounts a ON a.id = jel.account_id '
                "WHERE je.source_table = 'cheque_instruments' "
                'AND je.source_id = ? AND je.status = \'posted\' '
                'AND je.is_reversed = 0 AND a.account_code = ?',
                variables: [
                  Variable.withInt(instrumentId),
                  Variable.withString(code),
                ],
              )
              .getSingle();
          return row.read<int>('net');
        }

        expect(await instrumentAccountNet(saleChequeId, '1030'), 1000);
        expect(await instrumentAccountNet(saleChequeId, '1100'), -1000);
        expect(
          await instrumentAccountNet(purchaseReturnChequeId, '1030'),
          2000,
        );
        expect(
          await instrumentAccountNet(purchaseReturnChequeId, '2000'),
          -2000,
        );
        expect(await instrumentAccountNet(outgoingChequeId, '1030'), 0);
        expect(await instrumentAccountNet(cancelledChequeId, '1030'), 0);

        final saleCheque = await ChequeInstrumentDao(
          migrated,
        ).getById(saleChequeId);
        final purchaseReturnCheque = await ChequeInstrumentDao(
          migrated,
        ).getById(purchaseReturnChequeId);
        expect(saleCheque?.dishonourJournalEntryId, isNotNull);
        expect(purchaseReturnCheque?.dishonourJournalEntryId, isNotNull);
        final customer = await (migrated.select(
          migrated.customers,
        )..where((row) => row.id.equals(customerId))).getSingle();
        final supplier = await (migrated.select(
          migrated.suppliers,
        )..where((row) => row.id.equals(supplierId))).getSingle();
        expect(customer.balanceCents, Decimal.fromInt(1000));
        expect(supplier.balanceCents, Decimal.fromInt(-2000));
      } finally {
        await db?.close();
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );

  test('10082 additively backfills cleared standalone cheque advances', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tapix-account-payment-migration-',
    );
    final file = File('${directory.path}/tapix.db');
    AppDatabase? db;
    try {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(name: 'Legacy advance', currencyId: 1),
          );
      final transactionId = await db
          .into(db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: customerId,
              transactionType: 'payment',
              amountCents: Decimal.fromInt(-7500),
              currencyId: 1,
              referenceType: const Value('cheque_instrument'),
            ),
          );
      final chequeId = await ChequeInstrumentDao(db).create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        amountCents: 7500,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'customer',
        partyId: customerId,
        chequeNumber: 'LEGACY-ADVANCE',
      );
      await ChequeInstrumentDao(db).writeLifecycle(
        id: chequeId,
        status: ChequeInstrumentStatus.cleared,
        settlementPaymentId: transactionId,
      );

      await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_sale_payment_delete_reopens_account_payment',
      );
      await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_purchase_payment_delete_reopens_account_payment',
      );
      await db.customStatement('DROP TABLE party_account_payment_applications');
      await db.customStatement('DROP TABLE party_account_payments');
      await db.customStatement('PRAGMA user_version = 10081');
      await db.close();
      db = null;

      final migrated = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      db = migrated;
      await migrated.customSelect('SELECT 1').get();

      expect(migrated.schemaVersion, 10082);
      final advance = await (migrated.select(
        migrated.partyAccountPayments,
      )..where((row) => row.chequeInstrumentId.equals(chequeId))).getSingle();
      expect(advance.partyType, 'customer');
      expect(advance.partyId, customerId);
      expect(advance.amountCents, Decimal.fromInt(7500));
      expect(advance.appliedCents, Decimal.zero);
      expect(advance.status, 'open');
      expect(advance.settlementTransactionId, transactionId);
      expect(
        await (migrated.select(
          migrated.chequeInstruments,
        )..where((row) => row.id.equals(chequeId))).getSingle(),
        isNotNull,
      );
    } finally {
      await db?.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });
}
