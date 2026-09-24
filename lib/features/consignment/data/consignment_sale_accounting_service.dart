import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/journal_entry_service.dart';

/// Completes every pending obligation before its sale can be completed.
class ConsignmentSaleAccountingService {
  const ConsignmentSaleAccountingService(this._db, this._journal);

  final AppDatabase _db;
  final JournalEntryService _journal;

  Future<void> postPendingAccruals(int saleId, {int? userId}) async {
    final sale = await (_db.select(
      _db.sales,
    )..where((s) => s.id.equals(saleId))).getSingle();
    final events =
        await (_db.select(_db.consignmentObligationEvents)..where(
              (e) =>
                  e.sourceTable.equals('sales') &
                  e.sourceId.equals(saleId) &
                  e.kind.equals('sale_accrual') &
                  e.journalEntryId.isNull(),
            ))
            .get();
    for (final event in events) {
      if (event.signedAmountCents == 0) continue;
      final journalId = await _journal.recordConsignmentObligationJournalEntry(
        obligationEventId: event.id,
        signedAmountCents: event.signedAmountCents,
        currencyId: event.currencyId,
        entryDate: sale.saleDate,
        description:
            'Consignment sale #$saleId - supplier #${event.supplierId}',
        userId: userId,
      );
      final changed =
          await (_db.update(_db.consignmentObligationEvents)..where(
                (e) => e.id.equals(event.id) & e.journalEntryId.isNull(),
              ))
              .write(
                ConsignmentObligationEventsCompanion(
                  journalEntryId: Value(journalId),
                ),
              );
      if (changed != 1) {
        throw StateError('Consignment obligation journal link changed.');
      }
    }

    final pending =
        await (_db.select(_db.consignmentObligationEvents)..where(
              (e) =>
                  e.sourceTable.equals('sales') &
                  e.sourceId.equals(saleId) &
                  e.signedAmountCents.isNotValue(0) &
                  e.journalEntryId.isNull(),
            ))
            .get();
    if (pending.isNotEmpty) {
      throw StateError('Sale has unposted consignment obligations.');
    }
  }

  Future<void> postPendingReturnReversals(int returnId, {int? userId}) async {
    final events =
        await (_db.select(_db.consignmentObligationEvents)..where(
              (e) =>
                  e.sourceTable.equals('sale_returns') &
                  e.sourceId.equals(returnId) &
                  e.kind.equals('linked_return_reversal') &
                  e.journalEntryId.isNull(),
            ))
            .get();
    for (final event in events) {
      if (event.signedAmountCents == 0) continue;
      final journalId = await _journal.recordConsignmentObligationJournalEntry(
        obligationEventId: event.id,
        signedAmountCents: event.signedAmountCents,
        currencyId: event.currencyId,
        entryDate: event.occurredAt,
        description:
            'Consignment return #$returnId - supplier #${event.supplierId}',
        userId: userId,
      );
      final changed =
          await (_db.update(_db.consignmentObligationEvents)..where(
                (e) => e.id.equals(event.id) & e.journalEntryId.isNull(),
              ))
              .write(
                ConsignmentObligationEventsCompanion(
                  journalEntryId: Value(journalId),
                ),
              );
      if (changed != 1) {
        throw StateError('Consignment return journal link changed.');
      }
    }
    final pending =
        await (_db.select(_db.consignmentObligationEvents)..where(
              (e) =>
                  e.sourceTable.equals('sale_returns') &
                  e.sourceId.equals(returnId) &
                  e.signedAmountCents.isNotValue(0) &
                  e.journalEntryId.isNull(),
            ))
            .get();
    if (pending.isNotEmpty) {
      throw StateError('Return has unposted consignment reversals.');
    }
  }

  Future<void> postPendingReturnVoidReaccruals(
    int returnId, {
    int? userId,
  }) async {
    final events =
        await (_db.select(_db.consignmentObligationEvents)..where(
              (e) =>
                  e.sourceTable.equals('sale_returns') &
                  e.sourceId.equals(returnId) &
                  e.kind.equals('return_void_reaccrual') &
                  e.journalEntryId.isNull(),
            ))
            .get();
    for (final event in events) {
      if (event.signedAmountCents == 0) continue;
      final journalId = await _journal.recordConsignmentObligationJournalEntry(
        obligationEventId: event.id,
        signedAmountCents: event.signedAmountCents,
        currencyId: event.currencyId,
        entryDate: event.occurredAt,
        description:
            'Consignment return void #$returnId - supplier #${event.supplierId}',
        userId: userId,
      );
      final changed =
          await (_db.update(_db.consignmentObligationEvents)..where(
                (e) => e.id.equals(event.id) & e.journalEntryId.isNull(),
              ))
              .write(
                ConsignmentObligationEventsCompanion(
                  journalEntryId: Value(journalId),
                ),
              );
      if (changed != 1) {
        throw StateError('Consignment return-void journal link changed.');
      }
    }
    final pending =
        await (_db.select(_db.consignmentObligationEvents)..where(
              (e) =>
                  e.sourceTable.equals('sale_returns') &
                  e.sourceId.equals(returnId) &
                  e.signedAmountCents.isNotValue(0) &
                  e.journalEntryId.isNull(),
            ))
            .get();
    if (pending.isNotEmpty) {
      throw StateError('Return void has unposted consignment obligations.');
    }
  }

  Future<void> postPendingSaleVoidReversals(int saleId, {int? userId}) async {
    final events =
        await (_db.select(_db.consignmentObligationEvents)..where(
              (e) =>
                  e.sourceTable.equals('sales') &
                  e.sourceId.equals(saleId) &
                  e.kind.equals('sale_void_reversal') &
                  e.journalEntryId.isNull(),
            ))
            .get();
    for (final event in events) {
      if (event.signedAmountCents == 0) continue;
      final journalId = await _journal.recordConsignmentObligationJournalEntry(
        obligationEventId: event.id,
        signedAmountCents: event.signedAmountCents,
        currencyId: event.currencyId,
        entryDate: event.occurredAt,
        description:
            'Consignment sale void #$saleId - supplier #${event.supplierId}',
        userId: userId,
      );
      final changed =
          await (_db.update(_db.consignmentObligationEvents)..where(
                (e) => e.id.equals(event.id) & e.journalEntryId.isNull(),
              ))
              .write(
                ConsignmentObligationEventsCompanion(
                  journalEntryId: Value(journalId),
                ),
              );
      if (changed != 1) {
        throw StateError('Consignment sale-void journal link changed.');
      }
    }
    final pending =
        await (_db.select(_db.consignmentObligationEvents)..where(
              (e) =>
                  e.sourceTable.equals('sales') &
                  e.sourceId.equals(saleId) &
                  e.signedAmountCents.isNotValue(0) &
                  e.journalEntryId.isNull(),
            ))
            .get();
    if (pending.isNotEmpty) {
      throw StateError('Sale void has unposted consignment reversals.');
    }
  }
}
