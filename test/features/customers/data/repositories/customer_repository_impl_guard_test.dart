// ════════════════════════════════════════════════════════════════════════════
// Phase 1.3 — DIRECT-WRITE GUARD CONTRACT TEST
// ════════════════════════════════════════════════════════════════════════════
//
// Pins the invariant established by Phase 1.3 of the scattered-calculation
// migration (May 2026): `CustomerRepositoryImpl.updateCustomerBalance` is
// permanently disabled.
//
// Why this matters
// ----------------
// `customers.balance_cents` is the customer-side sub-ledger that MUST stay
// in lock-step with the GL `1100 Accounts Receivable` account. Every legal
// path that changes it (sale, payment, refund, adjustment, opening balance)
// posts a paired journal entry via `JournalEntryService` AND applies the
// matching delta through `BalanceService`, atomically, in a single
// transaction.
//
// The absolute-set path (`updateCustomerBalance(id, newCents)`) bypasses
// both halves of that contract — it would silently drift the GL/sub-ledger
// pair and break `AccountingRepository.reconcileBalances()`.
//
// The supplier side has had this guard since Phase 1; the customer side
// was the last remaining hole (audit finding H1 in `FULL_SYSTEM_AUDIT_REPORT.md`).
// This test ensures the guard cannot be silently removed without a failing
// red light.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/customers/data/datasources/customer_local_datasource.dart';
import 'package:tapix/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:tapix/features/suppliers/data/datasources/supplier_local_datasource.dart';
import 'package:tapix/features/suppliers/data/repositories/supplier_repository_impl.dart';

// Empty fakes — the guard throws before any dependency is touched, so the
// fakes never receive method calls. If they ever do, the test was wrong
// about the guard short-circuiting (regression!) and the UnimplementedError
// from Fake will surface it.
class _FakeCustomerDatasource extends Fake implements CustomerLocalDatasource {}
class _FakeSupplierDatasource extends Fake implements SupplierLocalDatasource {}
class _FakeAuditService extends Fake implements AuditLogService {}
class _FakeSessionService extends Fake implements SessionService {}
class _FakeJournalService extends Fake implements JournalEntryService {}
class _FakeAppDatabase extends Fake implements AppDatabase {}

void main() {
  group('CustomerRepositoryImpl.updateCustomerBalance — Phase 1.3 guard', () {
    late CustomerRepositoryImpl repo;

    setUp(() {
      repo = CustomerRepositoryImpl(
        _FakeCustomerDatasource(),
        _FakeAuditService(),
        _FakeSessionService(),
        _FakeJournalService(),
        _FakeAppDatabase(),
      );
    });

    test('throws StateError on any direct balance set', () async {
      // ignore: deprecated_member_use_from_same_package
      expect(
        () => repo.updateCustomerBalance(1, 100000),
        throwsA(isA<StateError>()),
      );
    });

    test('error message names the legal alternative (recordTransaction)',
        () async {
      try {
        // ignore: deprecated_member_use_from_same_package
        await repo.updateCustomerBalance(42, 5000);
        fail('Expected StateError, none thrown');
      } on StateError catch (e) {
        // Hard-pin the diagnostic so future "helpful" message tweaks
        // cannot accidentally hide the migration path.
        expect(e.message, contains('DISABLED'));
        expect(e.message, contains('recordTransaction'));
        expect(e.message, contains('adjustment'));
      }
    });

    test('guard short-circuits before touching the datasource', () async {
      // The Fake datasource intentionally implements nothing. If the guard
      // were removed, the production code would call
      // `_datasource.getCustomer(id)` and the test would fail with
      // UnimplementedError instead of StateError. Asserting the *kind* of
      // thrown error therefore proves no datasource write was attempted.
      Object? caught;
      try {
        // ignore: deprecated_member_use_from_same_package
        await repo.updateCustomerBalance(1, 100000);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>(),
          reason:
              'Guard must short-circuit BEFORE invoking any dependency. '
              'A NoSuchMethodError / UnimplementedError here means the '
              'rogue direct-write path is back.');
    });
  });

  group('SupplierRepositoryImpl.updateSupplierBalance — Phase 1 guard', () {
    // Mirror of the customer-side test. The supplier guard has existed for
    // longer; this group ensures symmetry so a future refactor cannot
    // accidentally re-enable one side without the other.
    late SupplierRepositoryImpl repo;

    setUp(() {
      // Note: SupplierRepositoryImpl ctor order differs from
      // CustomerRepositoryImpl: (datasource, session, journal, db, audit).
      repo = SupplierRepositoryImpl(
        _FakeSupplierDatasource(),
        _FakeSessionService(),
        _FakeJournalService(),
        _FakeAppDatabase(),
        _FakeAuditService(),
      );
    });

    test('throws StateError on any direct balance set', () async {
      // ignore: deprecated_member_use_from_same_package
      expect(
        () => repo.updateSupplierBalance(1, 100000),
        throwsA(isA<StateError>()),
      );
    });

    test('error message names the legal alternative (recordTransaction)',
        () async {
      try {
        // ignore: deprecated_member_use_from_same_package
        await repo.updateSupplierBalance(42, 5000);
        fail('Expected StateError, none thrown');
      } on StateError catch (e) {
        expect(e.message, contains('DISABLED'));
        expect(e.message, contains('recordTransaction'));
        expect(e.message, contains('adjustment'));
      }
    });
  });
}
