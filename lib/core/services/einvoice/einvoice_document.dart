import 'einvoice_status.dart';

/// Immutable domain record of an e-invoice artifact.
///
/// Mirrors the `einvoice_documents` table but decouples callers from
/// Drift-generated types so the rest of the codebase (services, UI,
/// tests) can depend on a stable Dart object.
class EInvoiceDocumentRecord {
  final int id;
  final String sourceTable;
  final int sourceId;
  final EInvoiceJurisdiction jurisdiction;
  final EInvoiceStatus status;
  final int? icv;
  final String? documentUuid;
  final String? documentHash;
  final String? previousHash;
  final String? payloadXml;
  final String? payloadJson;
  final String? qrCodeBase64;
  final String? responsePayload;
  final String? lastError;
  final int attemptCount;
  final DateTime? preparedAt;
  final DateTime? submittedAt;
  final DateTime? clearedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EInvoiceDocumentRecord({
    required this.id,
    required this.sourceTable,
    required this.sourceId,
    required this.jurisdiction,
    required this.status,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.icv,
    this.documentUuid,
    this.documentHash,
    this.previousHash,
    this.payloadXml,
    this.payloadJson,
    this.qrCodeBase64,
    this.responsePayload,
    this.lastError,
    this.preparedAt,
    this.submittedAt,
    this.clearedAt,
  });
}

/// Minimal input a provider receives at `prepare()` time.
///
/// The dispatch layer collates this snapshot from the originating sale /
/// return so providers never touch the transactional tables directly.
/// That isolation is what makes per-country providers pluggable.
class EInvoiceSubject {
  /// `'sales'` | `'sale_returns'` | `'sale_return_adjustments'`.
  final String sourceTable;
  final int sourceId;

  /// Human-readable invoice / credit-note number (e.g. `INV-202601-0042`).
  final String documentNumber;

  /// `'invoice'` | `'credit_note'` | `'debit_note'`.
  final String documentType;

  /// Money values are kept in CENTS (int). Providers convert to
  /// presentation units (decimal strings) during payload generation.
  final int subtotalCents;
  final int taxCents;
  final int totalCents;
  final int currencyId;

  /// ISO-8601 issue date (UTC recommended).
  final DateTime issueDate;

  /// Seller tax-registration number (VAT / CR / ...). Required for
  /// ZATCA / ETA / PEPPOL.
  final String? sellerTaxNumber;
  final String? sellerLegalName;

  /// Buyer tax-registration number (B2B path). NULL for B2C / walk-in.
  final String? buyerTaxNumber;
  final String? buyerLegalName;

  /// Line-level data the provider may render into the XML/JSON payload.
  /// Kept deliberately loose (`Map<String, Object?>`) so new providers
  /// can be added without churning this record.
  final List<Map<String, Object?>> lines;

  /// For credit/debit notes: the source invoice's UUID and number.
  /// NULL for plain invoices.
  final String? originalInvoiceUuid;
  final String? originalInvoiceNumber;

  const EInvoiceSubject({
    required this.sourceTable,
    required this.sourceId,
    required this.documentNumber,
    required this.documentType,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    required this.currencyId,
    required this.issueDate,
    required this.lines,
    this.sellerTaxNumber,
    this.sellerLegalName,
    this.buyerTaxNumber,
    this.buyerLegalName,
    this.originalInvoiceUuid,
    this.originalInvoiceNumber,
  });
}
