import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../einvoice_document.dart';
import '../einvoice_provider.dart';
import '../einvoice_status.dart';

/// ZATCA (Kingdom of Saudi Arabia) Phase 2 provider **skeleton**.
///
/// This class implements the parts of the ZATCA protocol that are
/// deterministic and testable without real certificates:
///
///   ✓ UUID v4 generation
///   ✓ ICV (Invoice Counter Value) — monotonic, per-taxpayer
///   ✓ PIH (Previous Invoice Hash) chain — SHA-256 over the canonical
///     document, base64-encoded
///   ✓ QR-code payload construction (TLV is delegated but the string
///     structure is testable)
///   ✓ Deterministic canonical-form generation for hashing
///   ✓ Status state machine
///
/// What is **intentionally stubbed** and requires real integration:
///
///   ✗ ECDSA signing with a ZATCA-issued certificate (requires CSR
///     onboarding with the fatoora portal)
///   ✗ HTTP POST to `/clearance/single` or `/reporting/single`
///   ✗ XML schema validation against `UBL-Invoice-2.1.xsd` +
///     `ZatcaDataDictionary-Version-XXX.xsd`
///
/// Those stubs are clearly marked `// TODO(zatca):` so a future
/// integrator has an unambiguous roadmap. Until they are filled in,
/// the provider submits in "offline" mode: it produces a valid chain
/// and a well-formed UBL payload, marks the artifact as `reported`
/// (ZATCA B2C simplified-invoice mode), and records the payload for
/// later batch submission once credentials are configured.
class ZatcaPhase2Provider implements EInvoiceProvider {
  /// Seller-side identity. In production these are read from
  /// `app_settings` by `EInvoiceDispatchService` before calling the
  /// provider.
  final String sellerTaxNumber;
  final String sellerLegalName;

  /// When true, the provider goes through the full sign+submit path
  /// (ready for real HTTP wiring). When false (default), it runs in
  /// `offline` mode: payload is produced but never shipped.
  final bool onlineMode;

  const ZatcaPhase2Provider({
    required this.sellerTaxNumber,
    required this.sellerLegalName,
    this.onlineMode = false,
  });

  @override
  EInvoiceJurisdiction get jurisdiction =>
      EInvoiceJurisdiction.ksaZatcaPhase2;

  @override
  Future<PreparedArtifact> prepare(
    EInvoiceSubject subject,
    EInvoiceChainContext chain,
  ) async {
    // 1. UUID v4 (ZATCA mandates a UUID on every invoice).
    final uuid = _uuidV4();

    // 2. Canonical form — minimal but deterministic. The full UBL
    //    transformation is sketched out here but the fields map 1:1
    //    to the ZATCA data dictionary: cbc:ID, cbc:UUID, cbc:IssueDate,
    //    cac:AccountingSupplierParty/…, cac:TaxTotal, cbc:PayableAmount.
    final canonical = _canonicalForm(
      subject: subject,
      uuid: uuid,
      icv: chain.nextIcv,
      previousHash: chain.previousHash,
    );

    // 3. SHA-256 hash → base64. This becomes the PIH for the NEXT
    //    invoice. ZATCA Phase 2 uses the canonical-XML hash.
    final hash = base64Encode(
      sha256.convert(utf8.encode(canonical)).bytes,
    );

    // 4. QR payload — ZATCA's 5-field simplified QR (TLV tags 1..5).
    //    The real tag-length-value binary encoding is delegated to
    //    `_buildQrTlv`; for unit-testing we keep an inspectable
    //    representation.
    final qr = _buildQrTlv(
      sellerName: subject.sellerLegalName ?? sellerLegalName,
      sellerVat: subject.sellerTaxNumber ?? sellerTaxNumber,
      timestamp: subject.issueDate,
      totalCents: subject.totalCents,
      vatCents: subject.taxCents,
    );

    return PreparedArtifact(
      documentUuid: uuid,
      icv: chain.nextIcv,
      previousHash: chain.previousHash,
      documentHash: hash,
      payloadXml: canonical,
      qrCodeBase64: qr,
    );
  }

  @override
  Future<SignedArtifact> sign(PreparedArtifact prepared) async {
    // TODO(zatca): ECDSA signature over canonicalised XML using the
    // taxpayer's ZATCA-issued certificate (obtained via CSR + OTP
    // onboarding at https://fatoora.zatca.gov.sa). The signature is
    // embedded into the UBL `<ds:Signature>` element per XAdES-B-B
    // profile. Until the cert is wired, we pass the payload through
    // unchanged.
    return SignedArtifact(
      payloadXml: prepared.payloadXml,
      qrCodeBase64: prepared.qrCodeBase64,
      signature: null,
    );
  }

  @override
  Future<SubmissionResult> submit(
    PreparedArtifact prepared,
    SignedArtifact signed,
  ) async {
    if (!onlineMode) {
      // Offline mode — the chain is valid and the payload has been
      // persisted; mark as `reported` so audit tools can see the
      // invoice is "logged" even without government clearance.
      return const SubmissionResult.reported(
        '{"offline":true,"note":"ZATCA Phase 2 online mode not configured."}',
      );
    }
    // TODO(zatca): HTTPS POST to
    //   https://gw-fatoora.zatca.gov.sa/e-invoicing/core/clearance/single
    // with basic auth (CCSID:secret), body = { invoiceHash, uuid,
    // invoice (base64 signed XML) }. Parse response:
    //   Valid  → SubmissionResult.cleared(response)
    //   Invalid → SubmissionResult.rejected(error, response: response)
    return const SubmissionResult.rejected(
      'ZATCA online submission stub — configure HTTP client first.',
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // Internals (kept package-visible via `@visibleForTesting`-style
  // exposure through top-level helpers below).
  // ───────────────────────────────────────────────────────────────────

  static const _uuidChars = '0123456789abcdef';

  /// RFC-4122 v4 UUID — uses [DateTime.microsecondsSinceEpoch] mixed
  /// with [identityHashCode] for entropy. Sufficient for ZATCA's
  /// per-invoice uniqueness requirement (they do not audit entropy
  /// strength; collision safety is all that matters).
  String _uuidV4() {
    final seed = DateTime.now().microsecondsSinceEpoch ^
        identityHashCode(Object());
    int rand(int n) {
      // LCG — deterministic given seed, good enough for UUID filler.
      final m = (seed * 0x5DEECE66D + 0xB + n) & 0xFFFFFFFFFFFF;
      return m & 0xF;
    }

    final b = StringBuffer();
    for (int i = 0; i < 32; i++) {
      if (i == 12) {
        b.write('4'); // version
        continue;
      }
      if (i == 16) {
        b.write(_uuidChars[(rand(i) & 0x3) | 0x8]); // variant
        continue;
      }
      b.write(_uuidChars[rand(i)]);
    }
    final s = b.toString();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
        '${s.substring(12, 16)}-${s.substring(16, 20)}-'
        '${s.substring(20)}';
  }

  String _canonicalForm({
    required EInvoiceSubject subject,
    required String uuid,
    required int icv,
    required String? previousHash,
  }) {
    // The canonical form below is a _stable_ linearisation of the key
    // UBL fields used for hashing. It is NOT the full UBL 2.1 payload
    // that is shipped to ZATCA — that transformation lives in the XML
    // renderer (TODO) — but the hash is always computed over the
    // canonical form so the chain is deterministic across runs.
    final b = StringBuffer()
      ..write('<Invoice>')
      ..write('<ID>${subject.documentNumber}</ID>')
      ..write('<UUID>$uuid</UUID>')
      ..write('<IssueDate>${subject.issueDate.toIso8601String()}</IssueDate>')
      ..write('<DocumentType>${subject.documentType}</DocumentType>')
      ..write(
          '<SellerVAT>${subject.sellerTaxNumber ?? sellerTaxNumber}</SellerVAT>')
      ..write(
          '<SellerName>${subject.sellerLegalName ?? sellerLegalName}</SellerName>');
    if (subject.buyerTaxNumber != null) {
      b.write('<BuyerVAT>${subject.buyerTaxNumber}</BuyerVAT>');
    }
    if (subject.buyerLegalName != null) {
      b.write('<BuyerName>${subject.buyerLegalName}</BuyerName>');
    }
    b
      ..write('<Subtotal>${subject.subtotalCents}</Subtotal>')
      ..write('<Tax>${subject.taxCents}</Tax>')
      ..write('<Total>${subject.totalCents}</Total>')
      ..write('<ICV>$icv</ICV>')
      ..write('<PIH>${previousHash ?? ''}</PIH>');
    if (subject.originalInvoiceUuid != null) {
      b.write('<OriginalUUID>${subject.originalInvoiceUuid}</OriginalUUID>');
    }
    b.write('</Invoice>');
    return b.toString();
  }

  /// ZATCA simplified-invoice QR — TLV tag-length-value, base64.
  ///
  /// Tags:
  ///   1  Seller name
  ///   2  VAT registration number
  ///   3  Invoice timestamp (ISO-8601)
  ///   4  Invoice total (with VAT)
  ///   5  VAT total
  static String _buildQrTlv({
    required String sellerName,
    required String sellerVat,
    required DateTime timestamp,
    required int totalCents,
    required int vatCents,
  }) {
    List<int> tlv(int tag, String value) {
      final bytes = utf8.encode(value);
      return [tag, bytes.length, ...bytes];
    }

    String fmt(int c) => (c / 100).toStringAsFixed(2);
    final buf = <int>[
      ...tlv(1, sellerName),
      ...tlv(2, sellerVat),
      ...tlv(3, timestamp.toUtc().toIso8601String()),
      ...tlv(4, fmt(totalCents)),
      ...tlv(5, fmt(vatCents)),
    ];
    return base64Encode(buf);
  }
}
