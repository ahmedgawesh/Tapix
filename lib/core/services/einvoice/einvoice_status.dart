/// Lifecycle state machine for a single e-invoice artifact.
///
/// Transitions allowed:
///
///   draft       → prepared            (provider.prepare)
///   prepared    → signed | rejected   (provider.sign)
///   signed      → submitted | rejected(provider.submit)
///   submitted   → cleared  | reported | rejected (async government callback)
///   rejected    → prepared            (operator retry)
///   cleared     → (terminal)
///   reported    → (terminal)
///
/// `cleared` is ZATCA's terminal success for B2B (real-time).
/// `reported` is ZATCA's terminal success for B2C (batch).
/// ETA maps `submitted` → `cleared` on `Valid` response.
/// PEPPOL uses `submitted` → `cleared` on Access-Point ACK.
enum EInvoiceStatus {
  /// Row was created but the provider has not yet produced a payload.
  draft,

  /// Payload generated, UUID + ICV + PIH populated, hash computed.
  prepared,

  /// Payload has been signed (ZATCA: ECDSA over canonical XML).
  signed,

  /// Payload dispatched to the government endpoint; awaiting response.
  submitted,

  /// Terminal success for real-time clearance (ZATCA B2B / ETA Valid).
  cleared,

  /// Terminal success for batch reporting (ZATCA B2C reporting).
  reported,

  /// Government or provider rejected the artifact; `last_error` is set.
  /// A retry transitions this row back to `prepared` (attempt_count++).
  rejected;

  /// Stable wire value persisted in `einvoice_documents.status`.
  String get wireValue => name;

  static EInvoiceStatus fromWire(String s) {
    for (final v in EInvoiceStatus.values) {
      if (v.wireValue == s) return v;
    }
    throw ArgumentError.value(s, 'status', 'Unknown EInvoiceStatus');
  }

  /// Terminal states accept no further dispatch attempts (except for
  /// explicit re-opening by an administrator, which is a separate flow).
  bool get isTerminal =>
      this == EInvoiceStatus.cleared || this == EInvoiceStatus.reported;

  /// A dispatch may advance this row when it is not terminal.
  bool get isDispatchable => !isTerminal;
}

/// Jurisdiction discriminator. Drives provider selection in
/// `EInvoiceProviderRegistry`.
enum EInvoiceJurisdiction {
  /// No e-invoicing required (default for markets like US, KW, JO, ...).
  none,

  /// Kingdom of Saudi Arabia — ZATCA Phase 2 (e-invoicing + clearance).
  ksaZatcaPhase2,

  /// Arab Republic of Egypt — ETA e-invoicing.
  egEta,

  /// European Union — PEPPOL BIS Billing 3 (UBL 2.1).
  euPeppol;

  String get wireValue {
    switch (this) {
      case EInvoiceJurisdiction.none:
        return 'NONE';
      case EInvoiceJurisdiction.ksaZatcaPhase2:
        return 'KSA_ZATCA_PHASE2';
      case EInvoiceJurisdiction.egEta:
        return 'EG_ETA';
      case EInvoiceJurisdiction.euPeppol:
        return 'EU_PEPPOL';
    }
  }

  static EInvoiceJurisdiction fromWire(String? s) {
    switch (s) {
      case 'KSA_ZATCA_PHASE2':
        return EInvoiceJurisdiction.ksaZatcaPhase2;
      case 'EG_ETA':
        return EInvoiceJurisdiction.egEta;
      case 'EU_PEPPOL':
        return EInvoiceJurisdiction.euPeppol;
      case null:
      case '':
      case 'NONE':
        return EInvoiceJurisdiction.none;
      default:
        throw ArgumentError.value(s, 'jurisdiction', 'Unknown');
    }
  }
}
