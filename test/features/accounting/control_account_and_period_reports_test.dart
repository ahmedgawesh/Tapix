import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';
import 'package:tapix/core/services/party_control_account_balance_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/data/repositories/journal_repository_impl.dart';
import 'package:tapix/features/reports/presentation/bloc/reports_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

Future<void> _insertPostedEntry(
  AppDatabase db, {
  required String number,
  required DateTime date,
  required int currencyId,
  required List<({int accountId, int debit, int credit})> lines,
  String entryType = 'opening_balance',
  String? sourceTable,
  int? sourceId,
}) async {
  final debits = lines.fold<int>(0, (sum, line) => sum + line.debit);
  final credits = lines.fold<int>(0, (sum, line) => sum + line.credit);
  final entryId = await db
      .into(db.journalEntries)
      .insert(
        JournalEntriesCompanion.insert(
          entryNumber: number,
          description: number,
          entryDate: Value(date),
          status: const Value('posted'),
          entryType: Value(entryType),
          sourceTable: Value(sourceTable),
          sourceId: Value(sourceId),
          totalDebitCents: Value(Decimal.fromInt(debits)),
          totalCreditCents: Value(Decimal.fromInt(credits)),
          postedAt: Value(date),
        ),
      );

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    await db
        .into(db.journalEntryLines)
        .insert(
          JournalEntryLinesCompanion.insert(
            journalEntryId: entryId,
            accountId: line.accountId,
            debitCents: Value(Decimal.fromInt(line.debit)),
            creditCents: Value(Decimal.fromInt(line.credit)),
            currencyId: currencyId,
            lineNumber: Value(index + 1),
          ),
        );
  }
}

Future<Account> _account(AppDatabase db, String code) => (db.select(
  db.accounts,
)..where((a) => a.accountCode.equals(code))).getSingle();

void main() {
  late AppDatabase db;
  late int currencyId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
  });

  tearDown(() => db.close());

  test(
    'AR/AP reconciliation ignores stale caches, audit refunds and future rows',
    () async {
      final now = DateTime.now();
      final movementDate = now.subtract(const Duration(hours: 2));
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Control customer',
              currencyId: currencyId,
              openingBalanceCents: Value(Decimal.fromInt(1000)),
              balanceCents: Value(Decimal.fromInt(7)),
              createdAt: Value(now.subtract(const Duration(days: 2))),
            ),
          );
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Control supplier',
              currencyId: currencyId,
              openingBalanceCents: Value(Decimal.fromInt(800)),
              balanceCents: Value(Decimal.fromInt(9)),
              createdAt: Value(now.subtract(const Duration(days: 2))),
            ),
          );

      await db
          .into(db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: customerId,
              transactionType: 'sale',
              amountCents: Decimal.fromInt(200),
              currencyId: currencyId,
              transactionDate: Value(movementDate),
            ),
          );
      await db
          .into(db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: customerId,
              transactionType: 'refund',
              amountCents: Decimal.fromInt(-50),
              currencyId: currencyId,
              transactionDate: Value(movementDate),
            ),
          );
      await db
          .into(db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: customerId,
              transactionType: 'sale',
              amountCents: Decimal.fromInt(9999),
              currencyId: currencyId,
              transactionDate: Value(now.add(const Duration(days: 1))),
            ),
          );
      await db
          .into(db.supplierTransactions)
          .insert(
            SupplierTransactionsCompanion.insert(
              supplierId: supplierId,
              transactionType: 'purchase',
              amountCents: Decimal.fromInt(100),
              currencyId: currencyId,
              transactionDate: Value(movementDate),
            ),
          );
      await db
          .into(db.supplierTransactions)
          .insert(
            SupplierTransactionsCompanion.insert(
              supplierId: supplierId,
              transactionType: 'refund_reversal',
              amountCents: Decimal.fromInt(25),
              currencyId: currencyId,
              transactionDate: Value(movementDate),
            ),
          );

      final ar = await _account(db, '1100');
      final ap = await _account(db, '2000');
      final equity = await _account(db, '3000');
      await _insertPostedEntry(
        db,
        number: 'JE-CONTROL-1',
        date: movementDate,
        currencyId: currencyId,
        lines: [
          (accountId: ar.id, debit: 1200, credit: 0),
          (accountId: ap.id, debit: 0, credit: 900),
          (accountId: equity.id, debit: 0, credit: 300),
        ],
      );

      final snapshot = await PartyControlAccountBalanceService(
        db,
      ).load(asOf: now);
      expect(snapshot.customerBalanceCents, 1200);
      expect(snapshot.supplierBalanceCents, 900);

      final repository = AccountingRepository(db);
      final healthy = await repository.reconcileBalances();
      expect(healthy.isHealthy, isTrue, reason: healthy.issues.join('\n'));

      final adapter = JournalRepositoryImpl(
        JournalLocalDatasourceImpl(AccountingDao(db)),
        repository,
      );
      final adapterHealthy = await adapter.reconcileBalances();
      expect(
        adapterHealthy.isHealthy,
        isTrue,
        reason: adapterHealthy.issues.join('\n'),
      );

      await db
          .into(db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: customerId,
              transactionType: 'sale',
              amountCents: Decimal.fromInt(1),
              currencyId: currencyId,
              transactionDate: Value(DateTime.now()),
            ),
          );
      final drifted = await repository.reconcileBalances();
      expect(
        drifted.issues,
        contains(
          'Accounts receivable mismatch: GL(journal_lines)=1200, Customers=1201',
        ),
      );
    },
  );

  test(
    'reconciliation assigns account 1030 to the correct party sub-ledger',
    () async {
      final now = DateTime.now();
      final date = now.subtract(const Duration(hours: 1));
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Dishonoured customer',
              currencyId: currencyId,
              openingBalanceCents: Value(Decimal.fromInt(1200)),
              createdAt: Value(now.subtract(const Duration(days: 1))),
            ),
          );
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Dishonoured supplier',
              currencyId: currencyId,
              openingBalanceCents: Value(Decimal.fromInt(1000)),
              createdAt: Value(now.subtract(const Duration(days: 1))),
            ),
          );

      for (final movement in [
        (type: 'payment', amount: -500),
        (type: 'cheque_dishonour', amount: 500),
      ]) {
        await db
            .into(db.customerTransactions)
            .insert(
              CustomerTransactionsCompanion.insert(
                customerId: customerId,
                transactionType: movement.type,
                amountCents: Decimal.fromInt(movement.amount),
                currencyId: currencyId,
                transactionDate: Value(date),
              ),
            );
      }
      for (final movement in [
        (type: 'purchase_return', amount: -400),
        (type: 'cheque_return_settlement', amount: 400),
        (type: 'cheque_dishonour', amount: -400),
      ]) {
        await db
            .into(db.supplierTransactions)
            .insert(
              SupplierTransactionsCompanion.insert(
                supplierId: supplierId,
                transactionType: movement.type,
                amountCents: Decimal.fromInt(movement.amount),
                currencyId: currencyId,
                transactionDate: Value(date),
              ),
            );
      }

      final chequeDao = ChequeInstrumentDao(db);
      final customerChequeId = await chequeDao.create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.sale,
        sourceId: 201,
        amountCents: 500,
        currencyId: currencyId,
        dueDate: date,
        partyType: 'customer',
        partyId: customerId,
      );
      final supplierChequeId = await chequeDao.create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.purchaseReturn,
        sourceId: 202,
        amountCents: 400,
        currencyId: currencyId,
        dueDate: date,
        partyType: 'supplier',
        partyId: supplierId,
      );
      await chequeDao.writeLifecycle(
        id: customerChequeId,
        status: ChequeInstrumentStatus.bounced,
        bounceReason: 'Rejected',
      );
      await chequeDao.writeLifecycle(
        id: supplierChequeId,
        status: ChequeInstrumentStatus.bounced,
        bounceReason: 'Rejected',
      );

      final ar = await _account(db, '1100');
      final ap = await _account(db, '2000');
      final equity = await _account(db, '3000');
      final clearing = await _account(db, '1020');
      final dishonoured = await _account(db, '1030');
      final inventory = await _account(db, '1200');
      await _insertPostedEntry(
        db,
        number: 'JE-OPEN-CUSTOMER',
        date: date,
        currencyId: currencyId,
        lines: [
          (accountId: ar.id, debit: 1200, credit: 0),
          (accountId: equity.id, debit: 0, credit: 1200),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-CUSTOMER-CHEQUE',
        date: date,
        currencyId: currencyId,
        lines: [
          (accountId: clearing.id, debit: 500, credit: 0),
          (accountId: ar.id, debit: 0, credit: 500),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-CUSTOMER-BOUNCE',
        date: date,
        currencyId: currencyId,
        entryType: 'cheque_dishonour',
        sourceTable: 'cheque_instruments',
        sourceId: customerChequeId,
        lines: [
          (accountId: dishonoured.id, debit: 500, credit: 0),
          (accountId: clearing.id, debit: 0, credit: 500),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-OPEN-SUPPLIER',
        date: date,
        currencyId: currencyId,
        lines: [
          (accountId: equity.id, debit: 1000, credit: 0),
          (accountId: ap.id, debit: 0, credit: 1000),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-PURCHASE-RETURN',
        date: date,
        currencyId: currencyId,
        lines: [
          (accountId: ap.id, debit: 400, credit: 0),
          (accountId: inventory.id, debit: 0, credit: 400),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-SUPPLIER-CHEQUE',
        date: date,
        currencyId: currencyId,
        lines: [
          (accountId: clearing.id, debit: 400, credit: 0),
          (accountId: ap.id, debit: 0, credit: 400),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-SUPPLIER-BOUNCE',
        date: date,
        currencyId: currencyId,
        entryType: 'cheque_dishonour',
        sourceTable: 'cheque_instruments',
        sourceId: supplierChequeId,
        lines: [
          (accountId: dishonoured.id, debit: 400, credit: 0),
          (accountId: clearing.id, debit: 0, credit: 400),
        ],
      );

      final result = await AccountingRepository(db).reconcileBalances();
      expect(result.isHealthy, isTrue, reason: result.issues.join('\n'));
    },
  );

  test(
    'P&L uses selected-period activity while TB remains cumulative',
    () async {
      final cash = await _account(db, '1000');
      final revenue = await _account(db, '4000');
      final expense = await _account(db, '5100');

      await _insertPostedEntry(
        db,
        number: 'JE-JULY',
        date: DateTime(2026, 7, 31, 12),
        currencyId: currencyId,
        lines: [
          (accountId: cash.id, debit: 100, credit: 0),
          (accountId: revenue.id, debit: 0, credit: 100),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-AUG-REVENUE',
        date: DateTime(2026, 8, 15, 12),
        currencyId: currencyId,
        lines: [
          (accountId: cash.id, debit: 200, credit: 0),
          (accountId: revenue.id, debit: 0, credit: 200),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-AUG-EXPENSE',
        date: DateTime(2026, 8, 20, 12),
        currencyId: currencyId,
        lines: [
          (accountId: expense.id, debit: 50, credit: 0),
          (accountId: cash.id, debit: 0, credit: 50),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-AUG-LAST-MILLISECOND',
        date: DateTime(2026, 8, 31, 23, 59, 59, 500),
        currencyId: currencyId,
        lines: [
          (accountId: cash.id, debit: 30, credit: 0),
          (accountId: revenue.id, debit: 0, credit: 30),
        ],
      );
      await _insertPostedEntry(
        db,
        number: 'JE-SEPTEMBER',
        date: DateTime(2026, 9, 1),
        currencyId: currencyId,
        lines: [
          (accountId: cash.id, debit: 400, credit: 0),
          (accountId: revenue.id, debit: 0, credit: 400),
        ],
      );

      final accountingRepository = AccountingRepository(db);
      final repository = JournalRepositoryImpl(
        JournalLocalDatasourceImpl(AccountingDao(db)),
        accountingRepository,
      );
      final bloc = ReportsBloc(repository, db);
      final august = ReportDateRange(
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 31, 23, 59, 59),
      );
      bloc.add(ReportsDateRangeChanged(august));

      final state = await bloc.stream
          .where((state) => state is RealtimeSuccess<ReportsData>)
          .cast<RealtimeSuccess<ReportsData>>()
          .firstWhere(
            (state) => state.data.dateRange.startDate == august.startDate,
          )
          .timeout(const Duration(seconds: 5));
      await bloc.close();

      expect(state.data.trialBalance.totalForType('revenue'), 330);
      expect(state.data.trialBalance.totalForType('expense'), 50);
      expect(state.data.periodTrialBalance.totalForType('revenue'), 230);
      expect(state.data.periodTrialBalance.totalForType('expense'), 50);
      expect(state.data.periodTrialBalance.isBalanced, isTrue);
    },
  );
}
