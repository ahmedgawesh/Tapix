/// Phase 3 — exceptions raised by the return approval pipeline.
library;

/// Thrown by `ReturnPostingService.post` when a return is submitted for
/// posting but its `approval_status` is not in [`ApprovalStatus.postable`].
///
/// Callers (DAO / bloc / API layer) should surface this as a 4xx-equivalent
/// business-logic error: the request is valid but a human approval step
/// is missing. The UI is expected to render a "Needs manager approval"
/// banner and expose an Approve button for authorised users.
class ReturnApprovalRequiredException implements Exception {
  /// Return header id (`sale_returns.id`, `purchase_returns.id`, etc.).
  final int returnId;

  /// Persisted `approval_status` found on the return header at post-time.
  final String currentStatus;

  /// Machine reason codes (comma-joined in storage; list here) that
  /// triggered the approval requirement.
  final List<String> reasonCodes;

  /// `sale` | `purchase`.
  final String side;

  const ReturnApprovalRequiredException({
    required this.returnId,
    required this.currentStatus,
    required this.reasonCodes,
    required this.side,
  });

  @override
  String toString() =>
      'ReturnApprovalRequiredException: $side return #$returnId '
      'requires manager approval (status=$currentStatus, '
      'reasons=${reasonCodes.join(",")}).';
}

/// Thrown when a caller attempts to approve/reject a return that is not
/// in `pending` state, or mutate immutable audit fields.
class ReturnApprovalStateException implements Exception {
  final String message;
  const ReturnApprovalStateException(this.message);
  @override
  String toString() => 'ReturnApprovalStateException: $message';
}

/// Thrown when a caller attempts to delete or mutate a system-seeded
/// reason code (`return_reason_codes.is_system = 1`).
class SystemReasonCodeProtectedException implements Exception {
  final String code;
  const SystemReasonCodeProtectedException(this.code);
  @override
  String toString() =>
      "SystemReasonCodeProtectedException: reason code '$code' is "
      'system-seeded and cannot be deleted or renamed.';
}
