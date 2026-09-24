import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../einvoice_document.dart';
import '../einvoice_provider.dart';
import '../einvoice_status.dart';

/// Egyptian Tax Authority (ETA) e-invoicing provider **skeleton**.
///
/// Unlike ZATCA, ETA uses JSON submissions to
/// `https://api.invoicing.eta.gov.eg/api/v1.0/documents/submit` with
/// OAuth-2 client-credentials auth against the ETA ID server.
///
/// This skeleton produces a deterministic JSON payload and a
/// placeholder `internalID` that mirrors the ETA document structure.
/// Signing (USB-token HSM) and actual submission are TODO and require
/// a real tax-payer account.
class EtaProvider implements EInvoiceProvider {
  final String sellerTaxNumber;
  final String sellerLegalName;
  final bool onlineMode;

  const EtaProvider({
    required this.sellerTaxNumber,
    required this.sellerLegalName,
    this.onlineMode = false,
  });

  @override
  EInvoiceJurisdiction get jurisdiction => EInvoiceJurisdiction.egEta;

  @override
  Future<PreparedArtifact> prepare(
    EInvoiceSubject subject,
    EInvoiceChainContext chain,
  ) async {
    final internalId = 'ETA-${subject.documentNumber}-${chain.nextIcv}';
    final doc = <String, Object?>{
      'documentType': subject.documentType == 'credit_note' ? 'C' : 'I',
      'documentTypeVersion': '1.0',
      'dateTimeIssued': subject.issueDate.toUtc().toIso8601String(),
      'taxpayerActivityCode': '4711',
      'internalID': internalId,
      'issuer': {
        'type': 'B',
        'id': subject.sellerTaxNumber ?? sellerTaxNumber,
        'name': subject.sellerLegalName ?? sellerLegalName,
      },
      'receiver': {
        'type': subject.buyerTaxNumber != null ? 'B' : 'P',
        'id': subject.buyerTaxNumber ?? '',
        'name': subject.buyerLegalName ?? '',
      },
      'totalSalesAmount': subject.subtotalCents / 100.0,
      'totalDiscountAmount': 0,
      'netAmount': subject.subtotalCents / 100.0,
      'totalAmount': subject.totalCents / 100.0,
      'taxTotals': [
        {'taxType': 'T1', 'amount': subject.taxCents / 100.0},
      ],
      'invoiceLines': subject.lines,
      if (subject.originalInvoiceUuid != null)
        'references': [subject.originalInvoiceUuid],
    };
    final json = jsonEncode(doc);
    final hash = base64Encode(sha256.convert(utf8.encode(json)).bytes);
    return PreparedArtifact(
      documentUuid: internalId,
      icv: chain.nextIcv,
      previousHash: chain.previousHash,
      documentHash: hash,
      payloadJson: json,
    );
  }

  @override
  Future<SignedArtifact> sign(PreparedArtifact prepared) async =>
      SignedArtifact(payloadJson: prepared.payloadJson);

  @override
  Future<SubmissionResult> submit(
    PreparedArtifact prepared,
    SignedArtifact signed,
  ) async {
    if (!onlineMode) {
      return const SubmissionResult.reported(
        '{"offline":true,"note":"ETA online mode not configured."}',
      );
    }
    // TODO(eta): HTTPS POST signed JSON to ETA submit endpoint.
    return const SubmissionResult.rejected(
      'ETA online submission stub — configure OAuth + HSM first.',
    );
  }
}
