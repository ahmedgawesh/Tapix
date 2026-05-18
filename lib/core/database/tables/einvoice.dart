import 'package:drift/drift.dart';

// ════════════════════════════════════════════════════════════════════════════
// Phase 4 — E-Invoice compliance (ZATCA Phase 2 / ETA / PEPPOL UBL)
// ════════════════════════════════════════════════════════════════════════════
//
// Single storage table for every outgoing e-invoice artifact regardless of
// jurisdiction. One row per `(source_table, source_id)` — enforced by a
// UNIQUE index — so a retried dispatch cannot create a duplicate artifact.
//
// The table is jurisdiction-agnostic on purpose: provider-specific payloads
// (ZATCA signed XML, ETA JSON, PEPPOL UBL) all land in `payload_xml` /
// `payload_json` with a provider discriminator in `jurisdiction`. Country
// certification tooling that needs typed access reads via
// `EInvoiceArtifactRepository`, not the table directly.
//
// Critical design points:
//   • ICV (Invoice Counter Value) — ZATCA Phase 2 requires a strictly
//     monotonically increasing counter per tax-payer. `icv` is filled by
//     `ZatcaPhase2Provider.prepare` inside the same DB transaction as
//     the sale, so two concurrent posts can never take the same ICV.
//   • PIH (Previous Invoice Hash) — each ZATCA invoice references the
//     hash of the previous one, forming a tamper-evident chain. The
//     provider reads `document_hash` of the latest row ordered by `icv`.
//   • Status state machine (see EInvoiceStatus): draft → prepared →
//     signed → submitted → cleared | reported | rejected → resubmitted.
//   • Idempotency: dispatch is a no-op if a row already exists for
//     `(source_table, source_id)` in a terminal state. Re-dispatch
//     on a `rejected` row is allowed and increments `attempt_count`.
class EInvoiceDocuments extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Which source document generated this artifact.
  ///   `sales` | `sale_returns` | `sale_return_adjustments`
  /// Purchase-side is intentionally excluded: in KSA/EG/EU the supplier
  /// submits; buyer-side submission is a separate future workstream.
  TextColumn get sourceTable => text()();
  IntColumn get sourceId => integer()();

  /// Jurisdiction / provider discriminator.
  ///   `'KSA_ZATCA_PHASE2'` | `'EG_ETA'` | `'EU_PEPPOL'` | `'NONE'`
  TextColumn get jurisdiction => text()();

  /// Current status (see `EInvoiceStatus`).
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// ZATCA Phase 2: strictly-monotonic per-taxpayer counter (1-based).
  /// ETA: optional, used as internal-ID seed.
  /// PEPPOL: unused.
  IntColumn get icv => integer().nullable()();

  /// Provider-generated UUID (mandatory for ZATCA Phase 2).
  TextColumn get documentUuid => text().nullable()();

  /// SHA-256 base64 of the canonicalised document (ZATCA/PEPPOL).
  /// Used by the next invoice as its PIH.
  TextColumn get documentHash => text().nullable()();

  /// Previous-Invoice-Hash: the [documentHash] of the row with the
  /// largest [icv] less than this row. Forms the ZATCA chain.
  TextColumn get previousHash => text().nullable()();

  /// Outgoing payload (signed XML for ZATCA/PEPPOL, JSON for ETA).
  TextColumn get payloadXml => text().nullable()();
  TextColumn get payloadJson => text().nullable()();

  /// QR-code TLV encoded as base64 (ZATCA Phase 2).
  TextColumn get qrCodeBase64 => text().nullable()();

  /// Government response (XML for ZATCA clearance reports, JSON for ETA).
  TextColumn get responsePayload => text().nullable()();

  /// Last error from submission; cleared on the next successful attempt.
  TextColumn get lastError => text().nullable()();

  /// Number of times dispatch has been attempted for this artifact.
  /// Starts at 0, incremented inside `EInvoiceDispatchService`.
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get preparedAt => dateTime().nullable()();
  DateTimeColumn get submittedAt => dateTime().nullable()();
  DateTimeColumn get clearedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {sourceTable, sourceId},
      ];
}
