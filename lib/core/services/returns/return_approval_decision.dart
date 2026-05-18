/// Phase 3 — value objects for the return approval workflow.
///
/// The approval pipeline has three stages:
///
/// ```
///   ┌───────────────────────────┐
///   │ ReturnApprovalService     │  policy — reads CompanySettings
///   │ .evaluate(context)        │          and emits a decision
///   └───────────────┬───────────┘
///                   │ ReturnApprovalDecision
///                   ▼
///   ┌───────────────────────────┐
///   │ DAO / Repository persists │  writes `approval_status`,
///   │ decision on return header │  `approval_required`,
///   │ at DRAFT-creation time    │  `approval_reason`
///   └───────────────┬───────────┘
///                   │ approved? — operator taps Approve button
///                   ▼
///   ┌───────────────────────────┐
///   │ ReturnPostingService.post │  enforcement — rejects any
///   │ gate                      │  return with required &&
///   │                           │  status ∉ {approved,
///   │                           │           auto_approved}
///   └───────────────────────────┘
/// ```
///
/// The split is deliberate: the **policy** (what requires approval) lives
/// in one service; **enforcement** lives in the single posting chokepoint.
/// Neither UI code nor DAO code re-implements the policy — they only
/// consume its decision. That keeps the rules centralised so a change
/// to the threshold / override flags touches exactly one place.
library;

/// Canonical machine reason codes emitted by
/// `ReturnApprovalService.evaluate`. They are stored as a
/// comma-separated string on `returns.approval_reason`.
class ApprovalReasonCode {
  /// Return total ≥ `return_approval_threshold_cents` setting.
  static const thresholdExceeded = 'threshold_exceeded';

  /// Return has no original invoice reference AND
  /// `require_approval_when_no_invoice = 1`.
  static const noInvoice = 'no_invoice';

  /// Operator used `allowOverHistory` / walk-in cash over-history and
  /// `require_approval_on_override = 1`.
  static const overrideUsed = 'override_used';

  const ApprovalReasonCode._();
}

/// Outcome of a single approval evaluation.
enum ReturnApprovalOutcome {
  /// Neither threshold nor no-invoice nor override rules fired. Safe to
  /// auto-approve without manager involvement.
  autoApproved,

  /// At least one rule fired. Return must be stored in `pending` state
  /// and cannot be posted until an authorised user approves it.
  requiresApproval,
}

/// Canonical persisted approval status on the return header.
///
/// `auto_approved` — policy was evaluated and no rule fired.
/// `pending`       — policy fired; waiting for an operator to approve.
/// `approved`      — manager approved a previously-pending return.
/// `rejected`      — manager rejected a previously-pending return.
class ApprovalStatus {
  static const autoApproved = 'auto_approved';
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';

  /// Statuses that allow `ReturnPostingService.post` to proceed.
  static const postable = <String>{autoApproved, approved};

  /// Returns `true` when a return in [status] is allowed to post.
  static bool canPost(String status) => postable.contains(status);

  const ApprovalStatus._();
}

/// Immutable context fed to `ReturnApprovalService.evaluate`. All inputs
/// required for the policy to fire must be present here so the service
/// stays stateless and trivially testable.
class ReturnApprovalContext {
  /// Total amount (cents, return currency) of the return. Drives the
  /// threshold rule.
  final int totalCents;

  /// Whether the return references a prior invoice (`true` for linked
  /// sale/purchase returns, `false` for adjustment / walk-in returns).
  final bool linked;

  /// Whether the operator used `allowOverHistory` (or equivalent) to
  /// bypass the Phase 0 quantity cap.
  final bool overHistoryOverride;

  /// Sale or purchase side. Reported back in the decision for audit
  /// logs but does not otherwise affect the policy.
  final String side; // 'sale' | 'purchase'

  const ReturnApprovalContext({
    required this.totalCents,
    required this.linked,
    required this.overHistoryOverride,
    required this.side,
  });
}

/// Result of an approval evaluation. Persist [persistedStatus] to
/// `approval_status` and [required] to `approval_required`; join
/// [reasonCodes] on comma into `approval_reason`.
class ReturnApprovalDecision {
  final ReturnApprovalOutcome outcome;
  final List<String> reasonCodes;

  /// The approval threshold that fired (in cents); `null` when the
  /// threshold rule did not contribute.
  final int? thresholdCents;

  const ReturnApprovalDecision._({
    required this.outcome,
    required this.reasonCodes,
    this.thresholdCents,
  });

  factory ReturnApprovalDecision.autoApproved() =>
      const ReturnApprovalDecision._(
        outcome: ReturnApprovalOutcome.autoApproved,
        reasonCodes: <String>[],
      );

  factory ReturnApprovalDecision.requiresApproval({
    required List<String> reasonCodes,
    int? thresholdCents,
  }) {
    assert(
      reasonCodes.isNotEmpty,
      'requiresApproval must carry at least one reason code',
    );
    return ReturnApprovalDecision._(
      outcome: ReturnApprovalOutcome.requiresApproval,
      reasonCodes: List.unmodifiable(reasonCodes),
      thresholdCents: thresholdCents,
    );
  }

  bool get required => outcome == ReturnApprovalOutcome.requiresApproval;

  /// Status to write to `approval_status` at draft-creation time.
  String get persistedStatus =>
      required ? ApprovalStatus.pending : ApprovalStatus.autoApproved;

  /// Comma-joined reason codes ready for `approval_reason`.
  String? get persistedReason =>
      reasonCodes.isEmpty ? null : reasonCodes.join(',');

  @override
  String toString() =>
      'ReturnApprovalDecision(outcome=$outcome, reasons=$reasonCodes, '
      'threshold=$thresholdCents)';
}
