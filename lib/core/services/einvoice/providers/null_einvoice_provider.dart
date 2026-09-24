import '../einvoice_document.dart';
import '../einvoice_provider.dart';
import '../einvoice_status.dart';

/// Default provider used when the company has not configured any
/// e-invoice jurisdiction. Every method is a no-op that completes with
/// `cleared` immediately so the dispatcher writes a trivial row with no
/// signature and no payload. This keeps the dispatch path uniform: the
/// SAME code runs whether or not the tenant is in an e-invoicing country.
class NullEInvoiceProvider implements EInvoiceProvider {
  const NullEInvoiceProvider();

  @override
  EInvoiceJurisdiction get jurisdiction => EInvoiceJurisdiction.none;

  @override
  Future<PreparedArtifact> prepare(
    EInvoiceSubject subject,
    EInvoiceChainContext chain,
  ) async {
    // No chain, no UUID, no payload. The dispatcher will still record
    // the artifact row for full auditability.
    return PreparedArtifact(
      documentUuid: '',
      icv: chain.nextIcv,
      previousHash: chain.previousHash,
      documentHash: '',
    );
  }

  @override
  Future<SignedArtifact> sign(PreparedArtifact prepared) async =>
      const SignedArtifact();

  @override
  Future<SubmissionResult> submit(
    PreparedArtifact prepared,
    SignedArtifact signed,
  ) async => const SubmissionResult(status: EInvoiceStatus.cleared);
}
