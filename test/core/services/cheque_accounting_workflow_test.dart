import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';
import 'package:tapix/core/payments/checkout_settlement.dart';
import 'package:tapix/core/payments/return_settlement_service.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/cheque_lifecycle_service.dart';
import 'package:tapix/core/services/cheque_source_void_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';

class _PurchaseRepository extends Mock implements PurchaseRepository {}

class _SaleRepository extends Mock implements SaleRepository {}

void main() {
  late AppDatabase db;
  late AccountingRepository accounting;
  late JournalEntryService journal;
  late ChequeInstrumentDao instruments;
  late ChequeLifecycleService lifecycle;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.seedInitialDataForTest();
    accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);
    instruments = ChequeInstrumentDao(db);
    lifecycle = ChequeLifecycleService(
      db: db,
      confirmationDao: ChequeConfirmationDao(db),
      instrumentDao: instruments,
      purchaseRepository: _PurchaseRepository(),
      saleRepository: _SaleRepository(),
      journalEntryService: journal,
      auditLogService: AuditLogService(db),
    );
  });

  tearDown(() => db.close());

  Future<Map<String, ({int debit, int credit})>> postedLines(
    String sourceTable,
    int sourceId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT a.account_code, jel.debit_cents, jel.credit_cents '
          'FROM journal_entries je '
          'JOIN journal_entry_lines jel ON jel.journal_entry_id = je.id '
          'JOIN accounts a ON a.id = jel.account_id '
          'WHERE je.source_table = ? AND je.source_id = ? '
          "AND je.status = 'posted' AND je.is_reversed = 0",
          variables: [
            Variable.withString(sourceTable),
            Variable.withInt(sourceId),
          ],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('account_code'): (
          debit: row.read<int>('debit_cents'),
          credit: row.read<int>('credit_cents'),
        ),
    };
  }

  test(
    'cheque invoices post to clearing accounts, never directly to bank',
    () async {
      await journal.recordSaleJournalEntry(
        saleId: 10,
        totalCents: 10000,
        paidAmountCents: 10000,
        currencyId: 1,
        paymentMethod: 'cheque',
      );
      final sale = await postedLines('sales', 10);
      expect(sale['1020']?.debit, 10000);
      expect(sale.containsKey('1010'), isFalse);

      await journal.recordPurchaseJournalEntry(
        purchaseId: 20,
        totalCents: 8000,
        paidAmountCents: 8000,
        currencyId: 1,
        inventoryNetCents: 8000,
        paymentMethod: 'cheque',
      );
      final purchase = await postedLines('purchases', 20);
      expect(purchase['2020']?.credit, 8000);
      expect(purchase.containsKey('1010'), isFalse);
    },
  );

  test('clearance moves incoming and outgoing cheques through bank', () async {
    final supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Return supplier',
            currencyId: 1,
            balanceCents: Value(Decimal.fromInt(-3000)),
          ),
        );
    final incomingId = await instruments.create(
      direction: ChequeDirectionValue.incoming,
      sourceTable: ChequeSourceTables.purchaseReturn,
      sourceId: 30,
      amountCents: 3000,
      currencyId: 1,
      dueDate: DateTime(2026, 9, 10),
      partyType: 'supplier',
      partyId: supplierId,
    );
    await lifecycle.markCleared(
      sourceTable: ChequeSourceTables.purchaseReturn,
      sourceId: 30,
    );
    final incoming = await postedLines('cheque_instruments', incomingId);
    expect(incoming['1010']?.debit, 3000);
    expect(incoming['1020']?.credit, 3000);

    final customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Return customer',
            currencyId: 1,
            balanceCents: Value(Decimal.fromInt(-2500)),
          ),
        );
    final outgoingId = await instruments.create(
      direction: ChequeDirectionValue.outgoing,
      sourceTable: ChequeSourceTables.saleReturn,
      sourceId: 31,
      amountCents: 2500,
      currencyId: 1,
      dueDate: DateTime(2026, 9, 10),
      partyType: 'customer',
      partyId: customerId,
    );
    await lifecycle.markCleared(
      sourceTable: ChequeSourceTables.saleReturn,
      sourceId: 31,
    );
    final outgoing = await postedLines('cheque_instruments', outgoingId);
    expect(outgoing['2020']?.debit, 2500);
    expect(outgoing['1010']?.credit, 2500);
  });

  test(
    'account cheques settle all four party directions only on clearance',
    () async {
      final cases =
          <
            ({
              String partyType,
              String source,
              String direction,
              int openingBalance,
              int transactionDelta,
              String obligation,
              String clearing,
            })
          >[
            (
              partyType: 'customer',
              source: ChequeSourceTables.customerAccount,
              direction: ChequeDirectionValue.incoming,
              openingBalance: 4000,
              transactionDelta: -4000,
              obligation: '1100',
              clearing: '1020',
            ),
            (
              partyType: 'customer',
              source: ChequeSourceTables.customerAccount,
              direction: ChequeDirectionValue.outgoing,
              openingBalance: -4000,
              transactionDelta: 4000,
              obligation: '1100',
              clearing: '2020',
            ),
            (
              partyType: 'supplier',
              source: ChequeSourceTables.supplierAccount,
              direction: ChequeDirectionValue.outgoing,
              openingBalance: 4000,
              transactionDelta: -4000,
              obligation: '2000',
              clearing: '2020',
            ),
            (
              partyType: 'supplier',
              source: ChequeSourceTables.supplierAccount,
              direction: ChequeDirectionValue.incoming,
              openingBalance: -4000,
              transactionDelta: 4000,
              obligation: '2000',
              clearing: '1020',
            ),
          ];

      for (var index = 0; index < cases.length; index++) {
        final testCase = cases[index];
        final int partyId;
        if (testCase.partyType == 'customer') {
          partyId = await db
              .into(db.customers)
              .insert(
                CustomersCompanion.insert(
                  name: 'Account customer $index',
                  currencyId: 1,
                  balanceCents: Value(Decimal.fromInt(testCase.openingBalance)),
                ),
              );
        } else {
          partyId = await db
              .into(db.suppliers)
              .insert(
                SuppliersCompanion.insert(
                  name: 'Account supplier $index',
                  currencyId: 1,
                  balanceCents: Value(Decimal.fromInt(testCase.openingBalance)),
                ),
              );
        }
        final chequeId = await instruments.create(
          direction: testCase.direction,
          sourceTable: testCase.source,
          sourceId: partyId,
          amountCents: 4000,
          currencyId: 1,
          issueDate: DateTime(2026, 9, 10),
          dueDate: DateTime(2026, 9, 20),
          partyType: testCase.partyType,
          partyId: partyId,
          chequeNumber: 'ACCOUNT-CLEAR-$index',
        );

        final first = await lifecycle.markCleared(
          sourceTable: testCase.source,
          sourceId: partyId,
          instrumentId: chequeId,
        );
        final second = await lifecycle.markCleared(
          sourceTable: testCase.source,
          sourceId: partyId,
          instrumentId: chequeId,
        );
        expect(second.createdPaymentId, first.createdPaymentId);

        final transactionTable = testCase.partyType == 'customer'
            ? 'customer_transactions'
            : 'supplier_transactions';
        final transaction = await db
            .customSelect(
              'SELECT id, amount_cents FROM $transactionTable '
              "WHERE reference_type = 'cheque_instrument' AND reference_id = ?",
              variables: [Variable.withInt(chequeId)],
            )
            .getSingle();
        final transactionId = transaction.read<int>('id');
        expect(first.createdPaymentId, transactionId);
        expect(
          transaction.read<int>('amount_cents'),
          testCase.transactionDelta,
        );

        final settlement = await postedLines(transactionTable, transactionId);
        if (testCase.direction == ChequeDirectionValue.incoming) {
          expect(settlement[testCase.clearing]?.debit, 4000);
          expect(settlement[testCase.obligation]?.credit, 4000);
        } else {
          expect(settlement[testCase.obligation]?.debit, 4000);
          expect(settlement[testCase.clearing]?.credit, 4000);
        }
        final clearance = await postedLines('cheque_instruments', chequeId);
        if (testCase.direction == ChequeDirectionValue.incoming) {
          expect(clearance['1010']?.debit, 4000);
          expect(clearance['1020']?.credit, 4000);
        } else {
          expect(clearance['2020']?.debit, 4000);
          expect(clearance['1010']?.credit, 4000);
        }

        final balanceRow = await db
            .customSelect(
              'SELECT balance_cents FROM '
              '${testCase.partyType == 'customer' ? 'customers' : 'suppliers'} '
              'WHERE id = ?',
              variables: [Variable.withInt(partyId)],
            )
            .getSingle();
        expect(balanceRow.read<int>('balance_cents'), 0);
        final confirmationCount = await db
            .customSelect(
              'SELECT COUNT(*) AS c FROM cheque_confirmations '
              'WHERE source_table = ? AND source_id = ?',
              variables: [
                Variable.withString(testCase.source),
                Variable.withInt(partyId),
              ],
            )
            .getSingle();
        expect(confirmationCount.read<int>('c'), 0);
      }
    },
  );

  test(
    'cleared incoming account cheque bounce restores party then cash resolves it',
    () async {
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Bounced account customer',
              currencyId: 1,
              balanceCents: Value(Decimal.fromInt(5000)),
            ),
          );
      final chequeId = await instruments.create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        amountCents: 2000,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'customer',
        partyId: customerId,
        chequeNumber: 'ACCOUNT-BOUNCE-IN',
      );

      await lifecycle.markCleared(
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        instrumentId: chequeId,
      );
      await lifecycle.markBounced(
        sourceTable: ChequeSourceTables.customerAccount,
        sourceId: customerId,
        instrumentId: chequeId,
        bounceReason: 'Bank rejected',
      );
      var customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      expect(customer.balanceCents, Decimal.fromInt(5000));
      var chequeLines = await postedLines('cheque_instruments', chequeId);
      expect(chequeLines['1030']?.debit, 2000);

      await lifecycle.resolveBounced(
        instrumentId: chequeId,
        resolutionType: ChequeResolutionType.cash,
      );
      customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      expect(customer.balanceCents, Decimal.fromInt(3000));
      chequeLines = await postedLines('cheque_instruments', chequeId);
      expect(chequeLines['1030']?.credit, 2000);
      expect(chequeLines['1000']?.debit, 2000);
    },
  );

  test(
    'pending outgoing account cheque creates no posting until cash resolution',
    () async {
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Bounced account supplier',
              currencyId: 1,
              balanceCents: Value(Decimal.fromInt(5000)),
            ),
          );
      final chequeId = await instruments.create(
        direction: ChequeDirectionValue.outgoing,
        sourceTable: ChequeSourceTables.supplierAccount,
        sourceId: supplierId,
        amountCents: 2000,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 20),
        partyType: 'supplier',
        partyId: supplierId,
        chequeNumber: 'ACCOUNT-BOUNCE-OUT',
      );

      await lifecycle.markBounced(
        sourceTable: ChequeSourceTables.supplierAccount,
        sourceId: supplierId,
        instrumentId: chequeId,
        bounceReason: 'Bank rejected',
      );
      var supplier = await (db.select(
        db.suppliers,
      )..where((row) => row.id.equals(supplierId))).getSingle();
      expect(supplier.balanceCents, Decimal.fromInt(5000));
      expect(await postedLines('cheque_instruments', chequeId), isEmpty);
      final beforeResolution = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM supplier_transactions WHERE reference_type = 'cheque_instrument' AND reference_id = ?",
            variables: [Variable.withInt(chequeId)],
          )
          .getSingle();
      expect(beforeResolution.read<int>('c'), 0);

      await lifecycle.resolveBounced(
        instrumentId: chequeId,
        resolutionType: ChequeResolutionType.cash,
      );
      supplier = await (db.select(
        db.suppliers,
      )..where((row) => row.id.equals(supplierId))).getSingle();
      expect(supplier.balanceCents, Decimal.fromInt(3000));
      final transaction = await db
          .customSelect(
            "SELECT id FROM supplier_transactions WHERE reference_type = 'cheque_instrument' AND reference_id = ?",
            variables: [Variable.withInt(chequeId)],
          )
          .getSingle();
      final lines = await postedLines(
        'supplier_transactions',
        transaction.read<int>('id'),
      );
      expect(lines['2000']?.debit, 2000);
      expect(lines['1000']?.credit, 2000);
    },
  );

  test('return cheque cannot clear without a linked party', () async {
    await instruments.create(
      direction: ChequeDirectionValue.outgoing,
      sourceTable: ChequeSourceTables.saleReturn,
      sourceId: 32,
      amountCents: 1200,
      currencyId: 1,
      dueDate: DateTime(2026, 9, 10),
    );

    await expectLater(
      lifecycle.markCleared(
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: 32,
      ),
      throwsA(isA<StateError>()),
    );

    final cheque = await instruments.getBySource(
      sourceTable: ChequeSourceTables.saleReturn,
      sourceId: 32,
    );
    expect(cheque.single.status, ChequeInstrumentStatus.issued);
    expect(await postedLines('cheque_instruments', cheque.single.id), isEmpty);
  });

  test(
    'failed pending return cheque keeps the existing customer obligation',
    () async {
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Customer',
              currencyId: 1,
              balanceCents: Value(Decimal.fromInt(-5000)),
            ),
          );
      final chequeId = await instruments.create(
        direction: ChequeDirectionValue.outgoing,
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: 40,
        amountCents: 5000,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 10),
        partyType: 'customer',
        partyId: customerId,
      );

      await lifecycle.markBounced(
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: 40,
        bounceReason: 'Insufficient funds',
      );
      var customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      expect(customer.balanceCents, Decimal.fromInt(-5000));
      final failed = await postedLines('cheque_instruments', chequeId);
      expect(failed, isEmpty);

      await ChequeSourceVoidService.voidForSource(
        db: db,
        journalService: journal,
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: 40,
        reason: 'Return voided',
      );
      customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      // The source-return DAO owns reversal of the original pending row;
      // this lifecycle helper must not duplicate that balance movement.
      expect(customer.balanceCents, Decimal.fromInt(-5000));
      expect(await postedLines('cheque_instruments', chequeId), isEmpty);

      final cheque = await instruments.getById(chequeId);
      expect(cheque?.status, ChequeInstrumentStatus.cancelled);
      expect(cheque?.dishonourJournalEntryId, isNull);
    },
  );

  test(
    'cancelled pending supplier return cheque keeps its obligation',
    () async {
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Supplier',
              currencyId: 1,
              balanceCents: Value(Decimal.fromInt(-4200)),
            ),
          );
      final chequeId = await instruments.create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.purchaseReturnAdjustment,
        sourceId: 50,
        amountCents: 4200,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 10),
        partyType: 'supplier',
        partyId: supplierId,
      );

      await lifecycle.markCancelled(
        sourceTable: ChequeSourceTables.purchaseReturnAdjustment,
        sourceId: 50,
      );
      var supplier = await (db.select(
        db.suppliers,
      )..where((row) => row.id.equals(supplierId))).getSingle();
      expect(supplier.balanceCents, Decimal.fromInt(-4200));
      final failed = await postedLines('cheque_instruments', chequeId);
      expect(failed, isEmpty);

      await ChequeSourceVoidService.voidForSource(
        db: db,
        journalService: journal,
        sourceTable: ChequeSourceTables.purchaseReturnAdjustment,
        sourceId: 50,
        reason: 'Adjustment return voided',
      );
      supplier = await (db.select(
        db.suppliers,
      )..where((row) => row.id.equals(supplierId))).getSingle();
      expect(supplier.balanceCents, Decimal.fromInt(-4200));
      expect(await postedLines('cheque_instruments', chequeId), isEmpty);
    },
  );
  test(
    'a failed cheque cannot be failed twice with another terminal status',
    () async {
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Customer',
              currencyId: 1,
              balanceCents: Value(Decimal.fromInt(-5000)),
            ),
          );
      final chequeId = await instruments.create(
        direction: ChequeDirectionValue.outgoing,
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: 60,
        amountCents: 5000,
        currencyId: 1,
        dueDate: DateTime(2026, 9, 10),
        partyType: 'customer',
        partyId: customerId,
      );

      await lifecycle.markBounced(
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: 60,
        bounceReason: 'Insufficient funds',
      );
      await expectLater(
        lifecycle.markCancelled(
          sourceTable: ChequeSourceTables.saleReturn,
          sourceId: 60,
        ),
        throwsA(isA<StateError>()),
      );

      final customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      expect(customer.balanceCents, Decimal.fromInt(-5000));
      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS count FROM journal_entries '
            'WHERE source_table = ? AND source_id = ? '
            'AND status = ? AND is_reversed = 0',
            variables: [
              Variable.withString('cheque_instruments'),
              Variable.withInt(chequeId),
              Variable.withString('posted'),
            ],
          )
          .getSingle();
      expect(rows.read<int>('count'), 0);
    },
  );

  test(
    'mixed sale return defers its cheque until clearance and reverses safely',
    () async {
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Mixed return customer',
              currencyId: 1,
              balanceCents: Value(Decimal.fromInt(-10000)),
            ),
          );
      const sourceId = 70;
      final allocations = [
        CheckoutPaymentAllocation(
          method: 'cheque',
          amountCents: 4000,
          reference: 'RETURN-4000',
          issueDate: DateTime(2026, 9, 8),
          dueDate: DateTime(2026, 10, 8),
        ),
        const CheckoutPaymentAllocation(method: 'cash', amountCents: 3000),
      ];

      await ReturnSettlementService.apply(
        db: db,
        journalService: journal,
        side: ReturnSettlementSide.sale,
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: sourceId,
        partyId: customerId,
        totalCents: 10000,
        currencyId: 1,
        allocations: allocations,
        documentDate: DateTime(2026, 9, 8),
      );

      var customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      // Only the cash allocation settles immediately. The cheque portion
      // remains in the customer obligation until bank clearance.
      expect(customer.balanceCents, Decimal.fromInt(-7000));
      final cashRows =
          await (db.select(db.customerTransactions)..where(
                (row) =>
                    row.referenceType.equals(ChequeSourceTables.saleReturn) &
                    row.referenceId.equals(sourceId),
              ))
              .get();
      expect(cashRows, hasLength(1));
      expect(cashRows.single.transactionType, 'return_settlement_cash');
      expect(cashRows.single.amountCents, Decimal.fromInt(3000));
      var cheques = await instruments.getBySource(
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: sourceId,
      );
      expect(cheques, hasLength(1));
      expect(cheques.single.status, ChequeInstrumentStatus.issued);
      expect(cheques.single.settlementPaymentId, isNull);
      final recognition = await postedLines(
        'cheque_instruments',
        cheques.single.id,
      );
      expect(recognition, isEmpty);

      await lifecycle.markCleared(
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: sourceId,
        instrumentId: cheques.single.id,
      );
      customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      expect(customer.balanceCents, Decimal.fromInt(-3000));
      cheques = await instruments.getBySource(
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: sourceId,
      );
      expect(cheques.single.settlementPaymentId, isNotNull);

      await lifecycle.markBounced(
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: sourceId,
        instrumentId: cheques.single.id,
        bounceReason: 'Bank rejected cheque',
      );
      customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      expect(customer.balanceCents, Decimal.fromInt(-7000));

      await ChequeSourceVoidService.voidForSource(
        db: db,
        journalService: journal,
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: sourceId,
        reason: 'Return voided',
      );
      await ReturnSettlementService.voidImmediate(
        db: db,
        journalService: journal,
        side: ReturnSettlementSide.sale,
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: sourceId,
        reason: 'Return settlement voided',
      );
      customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      // The remaining -10000 is the base return obligation. The owning
      // return DAO reverses that final leg when the source document is voided.
      expect(customer.balanceCents, Decimal.fromInt(-10000));
      cheques = await instruments.getBySource(
        sourceTable: ChequeSourceTables.saleReturn,
        sourceId: sourceId,
      );
      expect(cheques.single.status, ChequeInstrumentStatus.cancelled);
      final reversal =
          await (db.select(db.customerTransactions)..where(
                (row) => row.transactionType.equals('return_settlement_void'),
              ))
              .get();
      expect(reversal, hasLength(1));
      expect(reversal.single.amountCents, Decimal.fromInt(-3000));
    },
  );

  test('mixed purchase return defers its cheque until clearance', () async {
    final supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Mixed return supplier',
            currencyId: 1,
            balanceCents: Value(Decimal.fromInt(-10000)),
          ),
        );
    const sourceId = 71;
    await ReturnSettlementService.apply(
      db: db,
      journalService: journal,
      side: ReturnSettlementSide.purchase,
      sourceTable: ChequeSourceTables.purchaseReturnAdjustment,
      sourceId: sourceId,
      partyId: supplierId,
      totalCents: 10000,
      currencyId: 1,
      allocations: [
        CheckoutPaymentAllocation(
          method: 'cheque',
          amountCents: 4000,
          reference: 'SUPPLIER-RETURN-4000',
          issueDate: DateTime(2026, 9, 8),
          dueDate: DateTime(2026, 10, 8),
        ),
        const CheckoutPaymentAllocation(method: 'cash', amountCents: 3000),
      ],
      documentDate: DateTime(2026, 9, 8),
    );

    var supplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    // Only the cash allocation settles immediately. The cheque portion
    // remains in the supplier obligation until bank clearance.
    expect(supplier.balanceCents, Decimal.fromInt(-7000));
    final cheques = await instruments.getBySource(
      sourceTable: ChequeSourceTables.purchaseReturnAdjustment,
      sourceId: sourceId,
    );
    expect(cheques, hasLength(1));
    expect(cheques.single.direction, ChequeDirectionValue.incoming);
    expect(cheques.single.settlementPaymentId, isNull);
    final recognition = await postedLines(
      'cheque_instruments',
      cheques.single.id,
    );
    expect(recognition, isEmpty);

    await lifecycle.markCleared(
      sourceTable: ChequeSourceTables.purchaseReturnAdjustment,
      sourceId: sourceId,
      instrumentId: cheques.single.id,
    );
    supplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    expect(supplier.balanceCents, Decimal.fromInt(-3000));
    final cleared = await instruments.getById(cheques.single.id);
    expect(cleared?.settlementPaymentId, isNotNull);

    await lifecycle.markBounced(
      sourceTable: ChequeSourceTables.purchaseReturnAdjustment,
      sourceId: sourceId,
      instrumentId: cheques.single.id,
      bounceReason: 'Supplier cheque rejected',
    );
    supplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    expect(supplier.balanceCents, Decimal.fromInt(-7000));
    final bounced = await instruments.getById(cheques.single.id);
    expect(bounced?.settlementPaymentId, isNotNull);
    expect(bounced?.dishonourJournalEntryId, isNotNull);
    final dishonour = await postedLines(
      'cheque_instruments',
      cheques.single.id,
    );
    expect(dishonour['1030']?.debit, 4000);
    expect(dishonour['1020']?.credit, 4000);
  });
}
