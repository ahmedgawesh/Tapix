import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'einvoice_document.dart';
import 'einvoice_status.dart';

/// Thin persistence layer over `einvoice_documents`. All writes funnel
/// through here so the single-source-of-truth rule holds: there is NO
/// other place in the codebase that inserts / updates this table.
class EInvoiceArtifactRepository {
  final AppDatabase _db;
  EInvoiceArtifactRepository(this._db);

  /// Find the existing artifact for a source document, if any. The
  /// dispatcher calls this before every dispatch to honour the
  /// `(source_table, source_id)` UNIQUE constraint.
  Future<EInvoiceDocumentRecord?> findBySource({
    required String sourceTable,
    required int sourceId,
  }) async {
    final row = await (_db.select(_db.eInvoiceDocuments)
          ..where((t) =>
              t.sourceTable.equals(sourceTable) & t.sourceId.equals(sourceId)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// Last row posted under this jurisdiction — used by providers to
  /// read the PIH of the chain head.
  Future<EInvoiceDocumentRecord?> findChainHead(
    EInvoiceJurisdiction jurisdiction,
  ) async {
    final row = await (_db.select(_db.eInvoiceDocuments)
          ..where((t) => t.jurisdiction.equals(jurisdiction.wireValue))
          ..orderBy([(t) => OrderingTerm.desc(t.icv)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// Insert a new artifact row. Caller MUST have already checked that
  /// no row exists for the same (source_table, source_id); the UNIQUE
  /// index is the last line of defense against double-insert.
  Future<int> insertDraft({
    required String sourceTable,
    required int sourceId,
    required EInvoiceJurisdiction jurisdiction,
  }) async {
    return _db.into(_db.eInvoiceDocuments).insert(
          EInvoiceDocumentsCompanion.insert(
            sourceTable: sourceTable,
            sourceId: sourceId,
            jurisdiction: jurisdiction.wireValue,
          ),
        );
  }

  /// Persist the results of `provider.prepare()`.
  Future<void> recordPrepared({
    required int id,
    required int icv,
    required String documentUuid,
    required String documentHash,
    String? previousHash,
    String? payloadXml,
    String? payloadJson,
    String? qrCodeBase64,
  }) async {
    await (_db.update(_db.eInvoiceDocuments)..where((t) => t.id.equals(id)))
        .write(EInvoiceDocumentsCompanion(
      status: Value(EInvoiceStatus.prepared.wireValue),
      icv: Value(icv),
      documentUuid: Value(documentUuid),
      documentHash: Value(documentHash),
      previousHash: Value(previousHash),
      payloadXml: Value(payloadXml),
      payloadJson: Value(payloadJson),
      qrCodeBase64: Value(qrCodeBase64),
      preparedAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Persist the results of `provider.sign()`.
  Future<void> recordSigned({required int id, String? signature}) async {
    await (_db.update(_db.eInvoiceDocuments)..where((t) => t.id.equals(id)))
        .write(EInvoiceDocumentsCompanion(
      status: Value(EInvoiceStatus.signed.wireValue),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Persist the outcome of `provider.submit()`.
  Future<void> recordSubmission({
    required int id,
    required EInvoiceStatus status,
    String? responsePayload,
    String? lastError,
  }) async {
    final now = DateTime.now();
    await (_db.update(_db.eInvoiceDocuments)..where((t) => t.id.equals(id)))
        .write(EInvoiceDocumentsCompanion(
      status: Value(status.wireValue),
      responsePayload: Value(responsePayload),
      lastError: Value(lastError),
      submittedAt: Value(now),
      clearedAt: status == EInvoiceStatus.cleared ||
              status == EInvoiceStatus.reported
          ? Value(now)
          : const Value.absent(),
      attemptCount: const Value.absent(), // bumped separately
      updatedAt: Value(now),
    ));
    // Bump attempt_count atomically.
    await _db.customUpdate(
      'UPDATE e_invoice_documents SET attempt_count = attempt_count + 1 WHERE id = ?',
      variables: [Variable<int>(id)],
      updates: {_db.eInvoiceDocuments},
    );
  }

  EInvoiceDocumentRecord _fromRow(EInvoiceDocument r) => EInvoiceDocumentRecord(
        id: r.id,
        sourceTable: r.sourceTable,
        sourceId: r.sourceId,
        jurisdiction: EInvoiceJurisdiction.fromWire(r.jurisdiction),
        status: EInvoiceStatus.fromWire(r.status),
        icv: r.icv,
        documentUuid: r.documentUuid,
        documentHash: r.documentHash,
        previousHash: r.previousHash,
        payloadXml: r.payloadXml,
        payloadJson: r.payloadJson,
        qrCodeBase64: r.qrCodeBase64,
        responsePayload: r.responsePayload,
        lastError: r.lastError,
        attemptCount: r.attemptCount,
        preparedAt: r.preparedAt,
        submittedAt: r.submittedAt,
        clearedAt: r.clearedAt,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );
}
