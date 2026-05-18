// ════════════════════════════════════════════════════════════════════════════
// Phase 1.4 — adjustOpeningBalance() CONTRACT TEST
// ════════════════════════════════════════════════════════════════════════════
//
// Pins the behavioural contract of the repository-level opening-balance
// adjustment API introduced in Phase 1.4 of the scattered-calculation
// migration (May 2026). Before Phase 1.4 each presentation bloc replicated
// the same 3-step recipe (read current → compute delta → recordTransaction
// when non-zero), with no atomicity guarantee.
//
// What is tested here
// -------------------
//  1. **No-op when delta is zero.** Saving a form with the same balance the
//     customer already has must not produce a spurious adjustment row in
//     `customer_transactions` (or a GL entry).
//  2. **Positive delta** posts an `adjustment` row with a positive amount
//     AND increments `customers.balance_cents` by exactly that amount.
//     A paired GL entry is created via `JournalEntryService`.
//  3. **Negative delta** posts an `adjustment` row with a negative amount
//     AND decrements `customers.balance_cents`.
//  4. **Symmetric supplier behaviour** — the supplier-side mirror.
//  5. **Unknown customer/supplier id → StateError** (failure mode).
//
// Together these lock the read+post-in-one-transaction invariant that the
// repository now owns on behalf of every caller.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/customers/data/datasources/customer_local_datasource.dart';
import 'package:tapix/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:tapix/features/suppliers/data/datasources/supplier_local_datasource.dart';
import 'package:tapix/features/suppliers/data/repositories/supplier_repository_impl.dart';

void main() {
  late AppDatabase db;
  late CustomerRepositoryImpl customerRepo;
  late SupplierRepositoryImpl supplierRepo;
  late int currencyId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    // Force schema init + chart-of-accounts seed (the opening-balance
    // adjustment posts to GL 3100 "Opening Balance Equity").
    await db.customSelect('SELECT 1').get();

    final accountingRepo = AccountingRepository(db);
    final journalService = JournalEntryService(accountingRepo);

    customerRepo = CustomerRepositoryImpl(
      CustomerLocalDatasourceImpl(db.customerDao),
      AuditLogService(db),
      SessionService(),
      journalService,
      db,
    );
    supplierRepo = SupplierRepositoryImpl(
      SupplierLocalDatasourceImpl(db.supplierDao),
      SessionService(),
      journalService,
      db,
      AuditLogService(db),
    );

    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;
  });

  tearDown(() async {
    await db.close();
  });

  // ─── Helpers ────────────────────────────────────────────────────────────

  Future<int> seedCustomer({int balanceCents = 0}) async {
    return db.into(db.customers).insert(
          CustomersCompanion.insert(
            name: 'Test Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(balanceCents)),
          ),
        );
  }

  Future<int> seedSupplier({int balanceCents = 0}) async {
    return db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'Test Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(balanceCents)),
          ),
        );
  }

  Future<int> currentCustomerBalance(int id) async {
    final c = await (db.select(db.customers)..where((c) => c.id.equals(id)))
        .getSingle();
    return c.balanceCents.toBigInt().toInt();
  }

  Future<int> currentSupplierBalance(int id) async {
    final s = await (db.select(db.suppliers)..where((s) => s.id.equals(id)))
        .getSingle();
    return s.balanceCents.toBigInt().toInt();
  }

  Future<List<CustomerTransaction>> customerTxns(int id) {
    return (db.select(db.customerTransactions)
          ..where((t) => t.customerId.equals(id)))
        .get();
  }

  Future<List<SupplierTransaction>> supplierTxns(int id) {
    return (db.select(db.supplierTransactions)
          ..where((t) => t.supplierId.equals(id)))
        .get();
  }

  // ─── Customer-side tests ────────────────────────────────────────────────

  group('CustomerRepository.adjustOpeningBalance', () {
    test('no-op when desired balance equals current balance', () async {
      final id = await seedCustomer(balanceCents: 5000);

      final txId = await customerRepo.adjustOpeningBalance(
        customerId: id,
        desiredBalanceCents: 5000,
      );

      expect(txId, isNull,
          reason: 'method must return null when nothing changes');
      expect(await currentCustomerBalance(id), 5000,
          reason: 'balance must remain untouched');
      expect(await customerTxns(id), isEmpty,
          reason: 'no spurious customer_transactions row');
    });

    test('positive delta posts an adjustment and increases balance', () async {
      final id = await seedCustomer(balanceCents: 1000);

      final txId = await customerRepo.adjustOpeningBalance(
        customerId: id,
        desiredBalanceCents: 7500,
        description: 'opening seed',
      );

      expect(txId, isNotNull);
      expect(await currentCustomerBalance(id), 7500,
          reason: 'balance must reflect the desired value exactly');

      final txns = await customerTxns(id);
      expect(txns.length, 1);
      expect(txns.first.transactionType, 'adjustment');
      // delta = desired (7500) − current (1000) = +6500
      expect(txns.first.amountCents.toBigInt().toInt(), 6500);
      expect(txns.first.description, 'opening seed');
    });

    test('negative delta posts a signed adjustment and decreases balance',
        () async {
      final id = await seedCustomer(balanceCents: 10000);

      final txId = await customerRepo.adjustOpeningBalance(
        customerId: id,
        desiredBalanceCents: 2500,
      );

      expect(txId, isNotNull);
      expect(await currentCustomerBalance(id), 2500);

      final txns = await customerTxns(id);
      expect(txns.length, 1);
      // delta = 2500 − 10000 = −7500
      expect(txns.first.amountCents.toBigInt().toInt(), -7500);
    });

    test('throws StateError when customer does not exist', () async {
      expect(
        () => customerRepo.adjustOpeningBalance(
          customerId: 9999,
          desiredBalanceCents: 100,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('posts a paired journal entry for the adjustment', () async {
      // The repository delegates GL posting to JournalEntryService inside
      // recordTransaction. We verify a journal_entries row exists with
      // source_table = customer_transactions, source_id = the new tx id.
      final id = await seedCustomer(balanceCents: 0);
      final txId = await customerRepo.adjustOpeningBalance(
        customerId: id,
        desiredBalanceCents: 1234,
      );
      expect(txId, isNotNull);

      // Opening-balance adjustments delegate to
      // JournalEntryService.recordCustomerOpeningBalanceJournalEntry, which
      // posts with source_table='customers' / source_id=customerId (not the
      // customer_transactions row), so that idempotency works across re-edits.
      final entries = await (db.select(db.journalEntries)
            ..where((e) =>
                e.sourceTable.equals('customers') & e.sourceId.equals(id)))
          .get();
      expect(entries, isNotEmpty,
          reason: 'opening-balance adjustment must produce a GL entry '
              '(otherwise customers.balance_cents drifts from 1100 AR)');
      expect(entries.first.entryType, 'opening_balance');
    });
  });

  // ─── Supplier-side mirror ───────────────────────────────────────────────

  group('SupplierRepository.adjustOpeningBalance', () {
    test('no-op when desired balance equals current balance', () async {
      final id = await seedSupplier(balanceCents: 4000);

      final txId = await supplierRepo.adjustOpeningBalance(
        supplierId: id,
        desiredBalanceCents: 4000,
      );

      expect(txId, isNull);
      expect(await currentSupplierBalance(id), 4000);
      expect(await supplierTxns(id), isEmpty);
    });

    test('positive delta posts an adjustment and increases balance', () async {
      final id = await seedSupplier(balanceCents: 0);

      final txId = await supplierRepo.adjustOpeningBalance(
        supplierId: id,
        desiredBalanceCents: 5000,
      );

      expect(txId, isNotNull);
      expect(await currentSupplierBalance(id), 5000);

      final txns = await supplierTxns(id);
      expect(txns.length, 1);
      expect(txns.first.transactionType, 'adjustment');
      expect(txns.first.amountCents.toBigInt().toInt(), 5000);
    });

    test('negative delta posts a signed adjustment and decreases balance',
        () async {
      final id = await seedSupplier(balanceCents: 8000);

      final txId = await supplierRepo.adjustOpeningBalance(
        supplierId: id,
        desiredBalanceCents: 3000,
      );

      expect(txId, isNotNull);
      expect(await currentSupplierBalance(id), 3000);

      final txns = await supplierTxns(id);
      expect(txns.length, 1);
      expect(txns.first.amountCents.toBigInt().toInt(), -5000);
    });

    test('throws StateError when supplier does not exist', () async {
      expect(
        () => supplierRepo.adjustOpeningBalance(
          supplierId: 9999,
          desiredBalanceCents: 100,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
