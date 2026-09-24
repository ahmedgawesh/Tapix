import 'einvoice_document.dart';
import 'einvoice_status.dart';

/// Pluggable per-jurisdiction e-invoice provider.
///
/// Lifecycle contract (called by `EInvoiceDispatchService` in order):
///
///   1. `prepare(subject, chainContext)` — generate UUID, assign ICV,
///      compute hash, build the canonical payload, set PIH from the
///      previous artifact in the chain. Returns a [PreparedArtifact]
///      that the dispatcher persists.
///
///   2. `sign(prepared)` — sign the payload (ZATCA: ECDSA over
///      canonicalised XML). For ETA / PEPPOL the sign step may be a
///      no-op if signing is done by a separate signing service.
///
///   3. `submit(signed)` — deliver to the government endpoint.
///      Returns the response payload and final status
///      (`cleared` | `reported` | `rejected`).
///
/// A provider MAY short-circuit any step by returning a terminal or
/// rejected result; the dispatcher handles that uniformly.
abstract class EInvoiceProvider {
  /// Jurisdiction this provider handles. The registry selects by exact
  /// match against the company's configured jurisdiction.
  EInvoiceJurisdiction get jurisdiction;

  /// Build + hash + UUID + ICV + PIH chain.
  Future<PreparedArtifact> prepare(
    EInvoiceSubject subject,
    EInvoiceChainContext chain,
  );

  /// Sign the prepared artifact. Default implementation is a no-op so
  /// providers that have no signing step (or sign inline during
  /// [prepare]) do not need to override it.
  Future<SignedArtifact> sign(PreparedArtifact prepared) async {
    return SignedArtifact(
      payloadXml: prepared.payloadXml,
      payloadJson: prepared.payloadJson,
      qrCodeBase64: prepared.qrCodeBase64,
      signature: null,
    );
  }

  /// Ship to the government endpoint. Implementations MUST NOT throw on
  /// HTTP errors; instead they return a [SubmissionResult] with
  /// `status=rejected` and `lastError` set so the dispatcher can persist
  /// a retryable failure.
  Future<SubmissionResult> submit(
    PreparedArtifact prepared,
    SignedArtifact signed,
  );
}

/// Chain context the dispatcher hands to the provider at prepare time.
///
/// ICV is the next counter value (1 for the first invoice ever posted
/// under this jurisdiction). [previousHash] is the `document_hash` of
/// the row with `icv = nextIcv - 1`, or NULL for the very first row.
///
/// All values are read from the DB in a transaction so concurrent
/// posts can never fork the chain.
class EInvoiceChainContext {
  final int nextIcv;
  final String? previousHash;

  const EInvoiceChainContext({
    required this.nextIcv,
    required this.previousHash,
  });

  /// Chain context for the first invoice of a brand-new jurisdiction.
  static const EInvoiceChainContext genesis = EInvoiceChainContext(
    nextIcv: 1,
    previousHash: null,
  );
}

class PreparedArtifact {
  final String documentUuid;
  final int icv;
  final String? previousHash;
  final String documentHash;
  final String? payloadXml;
  final String? payloadJson;
  final String? qrCodeBase64;

  const PreparedArtifact({
    required this.documentUuid,
    required this.icv,
    required this.documentHash,
    this.previousHash,
    this.payloadXml,
    this.payloadJson,
    this.qrCodeBase64,
  });
}

class SignedArtifact {
  final String? payloadXml;
  final String? payloadJson;
  final String? qrCodeBase64;

  /// Provider-specific signature representation (PKCS#7 DER, detached
  /// XMLDSig, JWS, ...). `null` when the provider performs no signing.
  final String? signature;

  const SignedArtifact({
    this.payloadXml,
    this.payloadJson,
    this.qrCodeBase64,
    this.signature,
  });
}

class SubmissionResult {
  final EInvoiceStatus status;
  final String? responsePayload;
  final String? lastError;

  const SubmissionResult({
    required this.status,
    this.responsePayload,
    this.lastError,
  });

  const SubmissionResult.cleared(String response)
    : status = EInvoiceStatus.cleared,
      responsePayload = response,
      lastError = null;

  const SubmissionResult.reported(String response)
    : status = EInvoiceStatus.reported,
      responsePayload = response,
      lastError = null;

  const SubmissionResult.rejected(String error, {String? response})
    : status = EInvoiceStatus.rejected,
      responsePayload = response,
      lastError = error;
}
