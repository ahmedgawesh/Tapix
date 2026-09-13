import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/cheque_lifecycle_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/party_account_payment_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';

class _PurchaseRepository extends Mock implements PurchaseRepository {}

class _SaleRepository extends Mock implements SaleRepository {}

void main() {
  late AppDatabase db;
  late ChequeInstrumentDao instruments;
  late PartyAccountPaymentService payments;
  late ChequeLifecycleService lifecycle;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.seedInitialDataForTest();
    instruments = ChequeInstrumentDao(db);
    final audit = AuditLogService(db);
    payments = PartyAccountPaymentService(db: db, auditLogService: audit);
    lifecycle = ChequeLifecycleService(
      db: db,
      confirmationDao: ChequeConfirmationDao(db),
      instrumentDao: instruments,
      purchaseRepository: _PurchaseRepository(),
      saleRepository: _SaleRepository(),
      journalEntryService: JournalEntryService(AccountingRepository(db)),
      auditLogService: audit,
      accountPaymentService: payments,
    );
  });

  tearDown(() => db.close());

  test('cleared zero-balance customer cheque stays fully unapplied', () async {
    final customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(name: 'Advance customer', currencyId: 1),
        );
    final chequeId = await instruments.create(
      direction: ChequeDirectionValue.incoming,
      sourceTable: ChequeSourceTables.customerAccount,
      sourceId: customerId,
      amountCents: 10000,
      currencyId: 1,
      dueDate: DateTime(2026, 9, 20),
      partyType: 'customer',
      partyId: customerId,
      chequeNumber: 'ADV-C-1',
    );

    expect(await payments.getByChequeId(chequeId), isNull);
    await lifecycle.markCleared(
      sourceTable: ChequeSourceTables.customerAccount,
      sourceId: customerId,
      instrumentId: chequeId,
    );

    final advance = await payments.getByChequeId(chequeId);
    expect(advance, isNotNull);
    expect(advance!.amountCents, Decimal.fromInt(10000));
    expect(advance.appliedCents, Decimal.zero);
    expect(advance.status, PartyAccountPaymentStatus.open);
    expect(await payments.getOutstandingDocuments(advance.id), isEmpty);
    final customer = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    expect(customer.balanceCents, Decimal.fromInt(-10000));
  });

  test(
    'customer advance can be partially allocated without posting again',
    () async {
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(name: 'Advance customer', currencyId: 1),
          );
      final chequeId = await instruments.create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        amountCents: 10000,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'customer',
        partyId: customerId,
        chequeNumber: 'ADV-C-2',
      );
      await lifecycle.markCleared(
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        instrumentId: chequeId,
      );
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'SI-ADV-1',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(6000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(6000),
              currencyId: 1,
              paymentMethod: 'credit',
              status: const Value('completed'),
            ),
          );
      final advance = (await payments.getByChequeId(chequeId))!;
      final journalCountBefore = await _count(db, 'journal_entries');
      final transactionCountBefore = await _count(db, 'customer_transactions');
      final balanceBefore = (await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle()).balanceCents;

      final applicationId = await payments.applyToDocument(
        accountPaymentId: advance.id,
        documentType: PartyAccountPaymentDocumentType.sale,
        documentId: saleId,
        amountCents: 4000,
      );

      var sale = await (db.select(
        db.sales,
      )..where((row) => row.id.equals(saleId))).getSingle();
      var updated = (await payments.getByChequeId(chequeId))!;
      expect(sale.paidAmountCents, Decimal.fromInt(4000));
      expect(updated.appliedCents, Decimal.fromInt(4000));
      expect(updated.status, PartyAccountPaymentStatus.partiallyApplied);
      expect(_cents(updated.amountCents) - _cents(updated.appliedCents), 6000);
      expect(await _count(db, 'journal_entries'), journalCountBefore);
      expect(await _count(db, 'customer_transactions'), transactionCountBefore);
      expect(
        (await (db.select(
          db.customers,
        )..where((row) => row.id.equals(customerId))).getSingle()).balanceCents,
        balanceBefore,
      );

      await payments.reverseApplication(applicationId: applicationId);
      sale = await (db.select(
        db.sales,
      )..where((row) => row.id.equals(saleId))).getSingle();
      updated = (await payments.getByChequeId(chequeId))!;
      expect(sale.paidAmountCents, Decimal.zero);
      expect(updated.appliedCents, Decimal.zero);
      expect(updated.status, PartyAccountPaymentStatus.open);
      expect(await _count(db, 'journal_entries'), journalCountBefore);
    },
  );

  test(
    'supplier advance allocates only to same supplier and currency',
    () async {
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(name: 'Advance supplier', currencyId: 1),
          );
      final otherSupplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(name: 'Other supplier', currencyId: 1),
          );
      final chequeId = await instruments.create(
        direction: ChequeDirectionValue.outgoing,
        sourceTable: ChequeSourceTables.supplierAccount,
        sourceId: supplierId,
        amountCents: 12000,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'supplier',
        partyId: supplierId,
        chequeNumber: 'ADV-S-1',
      );
      await lifecycle.markCleared(
        sourceTable: ChequeSourceTables.supplierAccount,
        sourceId: supplierId,
        instrumentId: chequeId,
      );
      final validPurchase = await _insertPurchase(db, supplierId, 'PI-ADV-1');
      final otherPurchase = await _insertPurchase(
        db,
        otherSupplierId,
        'PI-ADV-OTHER',
      );
      final advance = (await payments.getByChequeId(chequeId))!;

      await payments.applyToDocument(
        accountPaymentId: advance.id,
        documentType: PartyAccountPaymentDocumentType.purchase,
        documentId: validPurchase,
        amountCents: 7000,
      );
      final purchase = await (db.select(
        db.purchases,
      )..where((row) => row.id.equals(validPurchase))).getSingle();
      expect(purchase.paidAmountCents, Decimal.fromInt(7000));

      await expectLater(
        payments.applyToDocument(
          accountPaymentId: advance.id,
          documentType: PartyAccountPaymentDocumentType.purchase,
          documentId: otherPurchase,
          amountCents: 1000,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'account_payment_document_mismatch',
          ),
        ),
      );
    },
  );

  test(
    'bounced cleared cheque reverses allocations and advance record',
    () async {
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(name: 'Bounce customer', currencyId: 1),
          );
      final chequeId = await instruments.create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        amountCents: 5000,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'customer',
        partyId: customerId,
        chequeNumber: 'ADV-BOUNCE',
      );
      await lifecycle.markCleared(
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        instrumentId: chequeId,
      );
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'SI-BOUNCE',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(5000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(5000),
              currencyId: 1,
              paymentMethod: 'credit',
              status: const Value('completed'),
            ),
          );
      final advance = (await payments.getByChequeId(chequeId))!;
      await payments.applyToDocument(
        accountPaymentId: advance.id,
        documentType: PartyAccountPaymentDocumentType.sale,
        documentId: saleId,
        amountCents: 5000,
      );

      await lifecycle.markBounced(
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        instrumentId: chequeId,
        bounceReason: 'Rejected',
      );

      final sale = await (db.select(
        db.sales,
      )..where((row) => row.id.equals(saleId))).getSingle();
      final reversed = (await payments.getByChequeId(chequeId))!;
      expect(sale.paidAmountCents, Decimal.zero);
      expect(reversed.appliedCents, Decimal.zero);
      expect(reversed.status, PartyAccountPaymentStatus.reversed);
      expect(await db.select(db.salePayments).get(), isEmpty);
    },
  );

  test(
    'deleting an allocated invoice restores the unapplied balance',
    () async {
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Deleted invoice customer',
              currencyId: 1,
            ),
          );
      final chequeId = await instruments.create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        amountCents: 8000,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'customer',
        partyId: customerId,
        chequeNumber: 'ADV-DELETE',
      );
      await lifecycle.markCleared(
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        instrumentId: chequeId,
      );
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'SI-DELETE',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(5000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(5000),
              currencyId: 1,
              paymentMethod: 'credit',
              status: const Value('completed'),
            ),
          );
      final advance = (await payments.getByChequeId(chequeId))!;
      await payments.applyToDocument(
        accountPaymentId: advance.id,
        documentType: PartyAccountPaymentDocumentType.sale,
        documentId: saleId,
        amountCents: 5000,
      );

      await (db.delete(db.sales)..where((row) => row.id.equals(saleId))).go();

      final restored = (await payments.getByChequeId(chequeId))!;
      final applications = await payments.getApplications(restored.id);
      expect(restored.appliedCents, Decimal.zero);
      expect(restored.status, PartyAccountPaymentStatus.open);
      expect(applications, hasLength(1));
      expect(applications.single.application.status, 'reversed');
    },
  );
}

Future<int> _insertPurchase(AppDatabase db, int supplierId, String number) => db
    .into(db.purchases)
    .insert(
      PurchasesCompanion.insert(
        purchaseNumber: number,
        supplierId: supplierId,
        subtotalCents: Decimal.fromInt(10000),
        taxCents: Decimal.zero,
        totalCents: Decimal.fromInt(10000),
        currencyId: 1,
        status: const Value('posted'),
      ),
    );

Future<int> _count(AppDatabase db, String table) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM $table')
      .getSingle();
  return row.read<int>('c');
}

int _cents(Decimal value) => value.toBigInt().toInt();
