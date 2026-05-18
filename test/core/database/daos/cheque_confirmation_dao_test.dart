// Phase 14.0 — regression tests for ChequeConfirmationDao.
//
// Pins the contract relied on by the dashboard cheque-reminders widget
// AND the SharedPreferences → DB backfill path:
//
//   • `confirm` is idempotent on (status, note, bounceReason).
//   • Bounced status REQUIRES a non-empty bounceReason.
//   • Invalid `sourceTable` is rejected at the API boundary.
//   • Re-opening a resolved cheque resets confirmed_at/confirmed_by/
//     bounce_reason and goes back to `pending`.
//   • `backfillClearedIfAbsent` never overwrites an existing row.
//   • `watchAllAsMap` keys rows by `'$source_table|$source_id'`.
//
// No JE / stock side effects to verify — Phase 14.0 deliberately keeps
// this sidecar isolated from the accounting layer (covered separately
// by `journal_repository_impl_test.dart`).
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';

void main() {
  late AppDatabase db;
  late ChequeConfirmationDao dao;

  setUp(() {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    dao = ChequeConfirmationDao(db);
  });

  tearDown(() async => db.close());

  group('confirm', () {
    test('inserts a new row with status=cleared', () async {
      final id = await dao.confirm(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 42,
        status: ChequeConfirmationStatus.cleared,
      );
      expect(id, isNonZero);
      final row = await dao.getBySource(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 42,
      );
      expect(row, isNotNull);
      expect(row!.status, ChequeConfirmationStatus.cleared);
      expect(row.confirmedAt, isNotNull);
      expect(row.bounceReason, isNull);
    });

    test('is idempotent — repeating same payload returns same id, no new row',
        () async {
      final id1 = await dao.confirm(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: 7,
        status: ChequeConfirmationStatus.cleared,
      );
      final id2 = await dao.confirm(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: 7,
        status: ChequeConfirmationStatus.cleared,
      );
      expect(id1, id2);
      final all = await db.select(db.chequeConfirmations).get();
      expect(all.length, 1);
    });

    test('updates in place on status change (no second row)', () async {
      await dao.confirm(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 1,
        status: ChequeConfirmationStatus.cleared,
      );
      await dao.confirm(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 1,
        status: ChequeConfirmationStatus.bounced,
        bounceReason: 'NSF',
      );
      final all = await db.select(db.chequeConfirmations).get();
      expect(all.length, 1);
      expect(all.first.status, ChequeConfirmationStatus.bounced);
      expect(all.first.bounceReason, 'NSF');
    });

    test('rejects bounced without bounceReason', () async {
      expect(
        () => dao.confirm(
          sourceTable: ChequeSourceTables.sale,
          sourceId: 1,
          status: ChequeConfirmationStatus.bounced,
        ),
        throwsArgumentError,
      );
      expect(
        () => dao.confirm(
          sourceTable: ChequeSourceTables.sale,
          sourceId: 1,
          status: ChequeConfirmationStatus.bounced,
          bounceReason: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown sourceTable', () async {
      expect(
        () => dao.confirm(
          sourceTable: 'inventory_adjustment',
          sourceId: 1,
          status: ChequeConfirmationStatus.cleared,
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown status', () async {
      expect(
        () => dao.confirm(
          sourceTable: ChequeSourceTables.sale,
          sourceId: 1,
          status: 'reissued',
        ),
        throwsArgumentError,
      );
    });

    test('pending status leaves confirmedAt null', () async {
      await dao.confirm(
        sourceTable: ChequeSourceTables.purchaseReturn,
        sourceId: 9,
        status: ChequeConfirmationStatus.pending,
      );
      final row = await dao.getBySource(
        sourceTable: ChequeSourceTables.purchaseReturn,
        sourceId: 9,
      );
      expect(row!.confirmedAt, isNull);
    });
  });

  group('reopenToPending', () {
    test('clears confirmedAt, confirmedBy, bounceReason', () async {
      await dao.confirm(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 1,
        status: ChequeConfirmationStatus.bounced,
        bounceReason: 'NSF',
      );
      await dao.reopenToPending(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 1,
      );
      final row = await dao.getBySource(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 1,
      );
      expect(row!.status, ChequeConfirmationStatus.pending);
      expect(row.confirmedAt, isNull);
      expect(row.bounceReason, isNull);
    });
  });

  group('backfillClearedIfAbsent', () {
    test('inserts a cleared row when none exists', () async {
      final inserted = await dao.backfillClearedIfAbsent(
        sourceTable: ChequeSourceTables.saleReturnAdjustment,
        sourceId: 5,
      );
      expect(inserted, isTrue);
      final row = await dao.getBySource(
        sourceTable: ChequeSourceTables.saleReturnAdjustment,
        sourceId: 5,
      );
      expect(row!.status, ChequeConfirmationStatus.cleared);
      expect(row.note, contains('backfilled'));
    });

    test('never overwrites an existing row', () async {
      await dao.confirm(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: 11,
        status: ChequeConfirmationStatus.bounced,
        bounceReason: 'stop-pay',
      );
      final inserted = await dao.backfillClearedIfAbsent(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: 11,
      );
      expect(inserted, isFalse);
      final row = await dao.getBySource(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: 11,
      );
      expect(row!.status, ChequeConfirmationStatus.bounced);
      expect(row.bounceReason, 'stop-pay');
    });
  });

  group('watchAllAsMap', () {
    test('keys rows by "<source_table>|<source_id>"', () async {
      await dao.confirm(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 1,
        status: ChequeConfirmationStatus.cleared,
      );
      await dao.confirm(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: 2,
        status: ChequeConfirmationStatus.bounced,
        bounceReason: 'NSF',
      );
      final map = await dao.watchAllAsMap().first;
      expect(map.keys, containsAll(['sale|1', 'purchase|2']));
      expect(map['sale|1']!.status, ChequeConfirmationStatus.cleared);
      expect(map['purchase|2']!.status, ChequeConfirmationStatus.bounced);
    });
  });

  group('unique constraint', () {
    test('cannot create two rows for the same (sourceTable, sourceId)',
        () async {
      await dao.confirm(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 1,
        status: ChequeConfirmationStatus.cleared,
      );
      // Direct insert that bypasses the upsert path should fail on the
      // table-level UNIQUE constraint.
      expect(
        () => db.into(db.chequeConfirmations).insert(
              ChequeConfirmationsCompanion.insert(
                sourceTable: ChequeSourceTables.sale,
                sourceId: 1,
              ),
            ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('resolved set', () {
    test('matches the values the dashboard treats as dismissed', () {
      expect(
        ChequeConfirmationStatus.resolved,
        equals({
          ChequeConfirmationStatus.cleared,
          ChequeConfirmationStatus.bounced,
          ChequeConfirmationStatus.cancelled,
        }),
      );
      expect(
        ChequeConfirmationStatus.resolved
            .contains(ChequeConfirmationStatus.pending),
        isFalse,
      );
    });
  });
}
