import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/cheques.dart';
import 'cheque_confirmation_dao.dart';

part 'cheque_instrument_dao.g.dart';

class ChequeDirectionValue {
  ChequeDirectionValue._();
  static const incoming = 'incoming';
  static const outgoing = 'outgoing';
}

class ChequeInstrumentStatus {
  ChequeInstrumentStatus._();
  static const received = 'received';
  static const issued = 'issued';
  static const deposited = 'deposited';
  static const cleared = 'cleared';
  static const bounced = 'bounced';
  static const cancelled = 'cancelled';
  static const replaced = 'replaced';

  static const open = {received, issued, deposited};
  static const terminal = {cleared, bounced, cancelled, replaced};
  static const all = {...open, ...terminal};
}

class ChequeResolutionType {
  ChequeResolutionType._();

  static const cash = 'cash';
  static const bank = 'bank';
  static const card = 'card';
  static const replacement = 'replacement';
  static const credit = 'credit';
  static const writeOff = 'write_off';

  static const all = {cash, bank, card, replacement, credit, writeOff};
}

@DriftAccessor(tables: [ChequeInstruments])
class ChequeInstrumentDao extends DatabaseAccessor<AppDatabase>
    with _$ChequeInstrumentDaoMixin {
  ChequeInstrumentDao(super.db);

  Future<ChequeInstrument?> getById(int id) => (select(
    chequeInstruments,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<List<ChequeInstrument>> getBySource({
    required String sourceTable,
    required int sourceId,
  }) {
    _validateSource(sourceTable);
    return (select(chequeInstruments)
          ..where(
            (row) =>
                row.sourceTable.equals(sourceTable) &
                row.sourceId.equals(sourceId),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
  }

  Stream<List<ChequeInstrument>> watchAll() =>
      (select(chequeInstruments)..orderBy([
            (row) => OrderingTerm.asc(row.dueDate),
            (row) => OrderingTerm.asc(row.id),
          ]))
          .watch();

  Stream<List<ChequeInstrument>> watchOpen() =>
      (select(chequeInstruments)
            ..where((row) => row.status.isIn(ChequeInstrumentStatus.open))
            ..orderBy([
              (row) => OrderingTerm.asc(row.dueDate),
              (row) => OrderingTerm.asc(row.id),
            ]))
          .watch();

  Future<int> create({
    required String direction,
    required String sourceTable,
    required int sourceId,
    required int amountCents,
    required int currencyId,
    required DateTime dueDate,
    String? partyType,
    int? partyId,
    String? chequeNumber,
    String? bankName,
    String? branchName,
    String? accountNumber,
    String? drawerName,
    DateTime? issueDate,
    int? settlementPaymentId,
    bool legacyDirectBank = false,
    int? userId,
    String? note,
  }) {
    _validateSource(sourceTable);
    if (amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', 'Must be > 0');
    }
    if (direction != ChequeDirectionValue.incoming &&
        direction != ChequeDirectionValue.outgoing) {
      throw ArgumentError.value(direction, 'direction');
    }
    final status = direction == ChequeDirectionValue.incoming
        ? ChequeInstrumentStatus.received
        : ChequeInstrumentStatus.issued;
    return into(chequeInstruments).insert(
      ChequeInstrumentsCompanion.insert(
        direction: direction,
        sourceTable: sourceTable,
        sourceId: sourceId,
        amountCents: Decimal.fromInt(amountCents),
        currencyId: currencyId,
        dueDate: dueDate,
        status: status,
        partyType: Value(partyType),
        partyId: Value(partyId),
        chequeNumber: Value(_blankToNull(chequeNumber)),
        bankName: Value(_blankToNull(bankName)),
        branchName: Value(_blankToNull(branchName)),
        accountNumber: Value(_blankToNull(accountNumber)),
        drawerName: Value(_blankToNull(drawerName)),
        issueDate: Value(issueDate),
        settlementPaymentId: Value(settlementPaymentId),
        legacyDirectBank: Value(legacyDirectBank),
        createdBy: Value(userId),
        updatedBy: Value(userId),
        note: Value(_blankToNull(note)),
      ),
    );
  }

  /// Creates the legacy/full-document cheque only when the source has no
  /// instrument. New partial payments call [create] and can coexist.
  Future<int> ensurePrimary({
    required String direction,
    required String sourceTable,
    required int sourceId,
    required int amountCents,
    required int currencyId,
    required DateTime dueDate,
    String? partyType,
    int? partyId,
    int? settlementPaymentId,
    bool legacyDirectBank = false,
    int? userId,
  }) async {
    final rows = await getBySource(
      sourceTable: sourceTable,
      sourceId: sourceId,
    );
    if (rows.isNotEmpty) {
      final first = rows.first;
      if (settlementPaymentId != null && first.settlementPaymentId == null) {
        await (update(
          chequeInstruments,
        )..where((row) => row.id.equals(first.id))).write(
          ChequeInstrumentsCompanion(
            settlementPaymentId: Value(settlementPaymentId),
            updatedBy: Value(userId),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
      return first.id;
    }
    return create(
      direction: direction,
      sourceTable: sourceTable,
      sourceId: sourceId,
      amountCents: amountCents,
      currencyId: currencyId,
      dueDate: dueDate,
      partyType: partyType,
      partyId: partyId,
      settlementPaymentId: settlementPaymentId,
      legacyDirectBank: legacyDirectBank,
      userId: userId,
    );
  }

  Future<void> updateDetails({
    required int id,
    required String chequeNumber,
    String? bankName,
    String? branchName,
    String? accountNumber,
    String? drawerName,
    DateTime? issueDate,
    DateTime? dueDate,
    String? note,
    int? userId,
  }) async {
    if (chequeNumber.trim().isEmpty) {
      throw ArgumentError('chequeNumber is required');
    }
    await (update(chequeInstruments)..where((row) => row.id.equals(id))).write(
      ChequeInstrumentsCompanion(
        chequeNumber: Value(chequeNumber.trim()),
        bankName: Value(_blankToNull(bankName)),
        branchName: Value(_blankToNull(branchName)),
        accountNumber: Value(_blankToNull(accountNumber)),
        drawerName: Value(_blankToNull(drawerName)),
        issueDate: Value(issueDate),
        dueDate: dueDate == null ? const Value.absent() : Value(dueDate),
        note: Value(_blankToNull(note)),
        updatedBy: Value(userId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> writeLifecycle({
    required int id,
    required String status,
    int? userId,
    String? bounceReason,
    int? settlementPaymentId,
    int? clearanceJournalEntryId,
    int? dishonourJournalEntryId,
    int? replacementChequeId,
    bool clearSettlementPaymentId = false,
    bool clearClearanceJournalEntryId = false,
    bool clearDishonourJournalEntryId = false,
  }) async {
    if (!ChequeInstrumentStatus.all.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final now = DateTime.now();
    await (update(chequeInstruments)..where((row) => row.id.equals(id))).write(
      ChequeInstrumentsCompanion(
        status: Value(status),
        depositedAt: status == ChequeInstrumentStatus.deposited
            ? Value(now)
            : const Value.absent(),
        clearedAt: status == ChequeInstrumentStatus.cleared
            ? Value(now)
            : const Value.absent(),
        bouncedAt: status == ChequeInstrumentStatus.bounced
            ? Value(now)
            : const Value.absent(),
        cancelledAt: status == ChequeInstrumentStatus.cancelled
            ? Value(now)
            : const Value.absent(),
        bounceReason: bounceReason == null
            ? const Value.absent()
            : Value(bounceReason.trim()),
        settlementPaymentId: clearSettlementPaymentId
            ? const Value(null)
            : settlementPaymentId == null
            ? const Value.absent()
            : Value(settlementPaymentId),
        clearanceJournalEntryId: clearClearanceJournalEntryId
            ? const Value(null)
            : clearanceJournalEntryId == null
            ? const Value.absent()
            : Value(clearanceJournalEntryId),
        dishonourJournalEntryId: clearDishonourJournalEntryId
            ? const Value(null)
            : dishonourJournalEntryId == null
            ? const Value.absent()
            : Value(dishonourJournalEntryId),
        replacementChequeId: replacementChequeId == null
            ? const Value.absent()
            : Value(replacementChequeId),
        updatedBy: Value(userId),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> writeResolution({
    required int id,
    required String resolutionType,
    int? resolutionJournalEntryId,
    int? replacementChequeId,
    String? note,
    int? userId,
  }) async {
    if (!ChequeResolutionType.all.contains(resolutionType)) {
      throw ArgumentError.value(resolutionType, 'resolutionType');
    }
    final normalizedNote = _blankToNull(note);
    await (update(chequeInstruments)..where((row) => row.id.equals(id))).write(
      ChequeInstrumentsCompanion(
        resolutionType: Value(resolutionType),
        resolutionJournalEntryId: Value(resolutionJournalEntryId),
        replacementChequeId: Value(replacementChequeId),
        resolvedAt: Value(DateTime.now()),
        resolutionNote: Value(normalizedNote),
        updatedBy: Value(userId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  String? _blankToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  void _validateSource(String value) {
    if (!ChequeSourceTables.all.contains(value)) {
      throw ArgumentError.value(value, 'sourceTable');
    }
  }
}
