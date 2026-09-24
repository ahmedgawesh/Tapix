import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../einvoice_document.dart';
import '../einvoice_provider.dart';
import '../einvoice_status.dart';

/// PEPPOL BIS Billing 3.0 (UBL 2.1) provider **skeleton**.
///
/// PEPPOL is the EU standard for cross-border e-invoicing. The tenant
/// connects to an Access Point (AP) which handles the BIS 3.0 envelope
/// and ships the document over AS4 to the receiver's AP.
///
/// This skeleton produces a minimal UBL 2.1 Invoice document and computes
/// a SHA-256 digest for traceability. Actual AS4 shipping is delegated
/// to a future Access-Point integration (Mustang, Storecove, or an
/// in-house AP).
class PeppolUblProvider implements EInvoiceProvider {
  final String sellerTaxNumber;
  final String sellerLegalName;
  final bool onlineMode;

  const PeppolUblProvider({
    required this.sellerTaxNumber,
    required this.sellerLegalName,
    this.onlineMode = false,
  });

  @override
  EInvoiceJurisdiction get jurisdiction => EInvoiceJurisdiction.euPeppol;

  @override
  Future<PreparedArtifact> prepare(
    EInvoiceSubject subject,
    EInvoiceChainContext chain,
  ) async {
    final ubl = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8"?>')
      ..write(
        '<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2">',
      )
      ..write(
        '<cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0</cbc:CustomizationID>',
      )
      ..write('<cbc:ID>${subject.documentNumber}</cbc:ID>')
      ..write('<cbc:IssueDate>${_iso(subject.issueDate)}</cbc:IssueDate>')
      ..write(
        '<cbc:InvoiceTypeCode>'
        '${subject.documentType == 'credit_note' ? '381' : '380'}'
        '</cbc:InvoiceTypeCode>',
      )
      ..write(
        '<cbc:DocumentCurrencyCode>CUR${subject.currencyId}</cbc:DocumentCurrencyCode>',
      )
      ..write(
        '<cac:AccountingSupplierParty><cac:Party>'
        '<cac:PartyName><cbc:Name>'
        '${subject.sellerLegalName ?? sellerLegalName}'
        '</cbc:Name></cac:PartyName>'
        '<cac:PartyTaxScheme><cbc:CompanyID>'
        '${subject.sellerTaxNumber ?? sellerTaxNumber}'
        '</cbc:CompanyID></cac:PartyTaxScheme>'
        '</cac:Party></cac:AccountingSupplierParty>',
      )
      ..write(
        '<cbc:TaxAmount>${(subject.taxCents / 100).toStringAsFixed(2)}</cbc:TaxAmount>',
      )
      ..write(
        '<cbc:PayableAmount>${(subject.totalCents / 100).toStringAsFixed(2)}</cbc:PayableAmount>',
      )
      ..write('</Invoice>');

    final xml = ubl.toString();
    final hash = base64Encode(sha256.convert(utf8.encode(xml)).bytes);
    return PreparedArtifact(
      documentUuid: subject.documentNumber,
      icv: chain.nextIcv,
      previousHash: chain.previousHash,
      documentHash: hash,
      payloadXml: xml,
    );
  }

  @override
  Future<SignedArtifact> sign(PreparedArtifact prepared) async =>
      SignedArtifact(payloadXml: prepared.payloadXml);

  @override
  Future<SubmissionResult> submit(
    PreparedArtifact prepared,
    SignedArtifact signed,
  ) async {
    if (!onlineMode) {
      return const SubmissionResult.reported(
        '{"offline":true,"note":"PEPPOL Access Point not configured."}',
      );
    }
    // TODO(peppol): AS4 shipment via configured Access Point.
    return const SubmissionResult.rejected(
      'PEPPOL online submission stub — configure Access Point first.',
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
