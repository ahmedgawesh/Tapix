import 'dart:async';

import '../../database/daos/settings_dao.dart';
import 'return_approval_decision.dart';
import 'return_approval_exceptions.dart';

/// Phase 3 — **single source of truth** for the return-approval policy.
///
/// Reads three keys from `app_settings`:
///   * `return_approval_threshold_cents`     (int  — `0` = disabled)
///   * `require_approval_when_no_invoice`    (bool — `1` / `0`)
///   * `require_approval_on_override`        (bool — `1` / `0`)
///
/// Stateless beyond a tiny in-memory cache of the parsed values. Every
/// caller (DAO at draft creation, UI manager-approval screen, integration
/// tests) goes through [evaluate] — there is no scattered policy code.
class ReturnApprovalService {
  static const _kThreshold = 'return_approval_threshold_cents';
  static const _kNoInvoice = 'require_approval_when_no_invoice';
  static const _kOverride = 'require_approval_on_override';

  final SettingsDao _settingsDao;

  // Cache: refreshed by `invalidateCache()` or after `setSetting*`.
  int? _thresholdCents;
  bool? _requireWhenNoInvoice;
  bool? _requireOnOverride;

  ReturnApprovalService(this._settingsDao);

  // ── Settings accessors (lazy + cached) ──────────────────────────

  Future<int> getThresholdCents() async {
    final cached = _thresholdCents;
    if (cached != null) return cached;
    final raw = await _settingsDao.getSetting(_kThreshold);
    final parsed = int.tryParse(raw ?? '') ?? 0;
    _thresholdCents = parsed < 0 ? 0 : parsed;
    return _thresholdCents!;
  }

  Future<bool> getRequireWhenNoInvoice() async {
    final cached = _requireWhenNoInvoice;
    if (cached != null) return cached;
    final raw = await _settingsDao.getSetting(_kNoInvoice);
    _requireWhenNoInvoice = _parseBool(raw, defaultValue: true);
    return _requireWhenNoInvoice!;
  }

  Future<bool> getRequireOnOverride() async {
    final cached = _requireOnOverride;
    if (cached != null) return cached;
    final raw = await _settingsDao.getSetting(_kOverride);
    _requireOnOverride = _parseBool(raw, defaultValue: true);
    return _requireOnOverride!;
  }

  Future<void> setThresholdCents(int cents) async {
    if (cents < 0) cents = 0;
    await _settingsDao.saveSetting(
      _kThreshold,
      cents.toString(),
      description:
          'Amount (in cents) at/above which a return requires manager '
          'approval before posting. 0 disables the threshold rule.',
    );
    _thresholdCents = cents;
  }

  Future<void> setRequireWhenNoInvoice(bool value) async {
    await _settingsDao.saveSetting(
      _kNoInvoice,
      value ? '1' : '0',
      description:
          'When 1, any adjustment return with no original invoice '
          'reference requires manager approval before posting.',
    );
    _requireWhenNoInvoice = value;
  }

  Future<void> setRequireOnOverride(bool value) async {
    await _settingsDao.saveSetting(
      _kOverride,
      value ? '1' : '0',
      description:
          'When 1, any return posted with `allowOverHistory` (bypassing '
          'the Phase 0 quantity cap) requires manager approval before '
          'posting.',
    );
    _requireOnOverride = value;
  }

  void invalidateCache() {
    _thresholdCents = null;
    _requireWhenNoInvoice = null;
    _requireOnOverride = null;
  }

  // ── Policy ──────────────────────────────────────────────────────

  /// Pure policy evaluation. Reads settings, applies the three rules,
  /// returns an immutable [ReturnApprovalDecision]. Never mutates state.
  ///
  /// Rule precedence is *additive* — multiple rules can fire, every
  /// matching reason is included in the decision so the audit log is
  /// faithful.
  Future<ReturnApprovalDecision> evaluate(ReturnApprovalContext ctx) async {
    final threshold = await getThresholdCents();
    final reqNoInv = await getRequireWhenNoInvoice();
    final reqOverride = await getRequireOnOverride();

    final reasons = <String>[];
    int? thresholdHit;

    if (threshold > 0 && ctx.totalCents.abs() >= threshold) {
      reasons.add(ApprovalReasonCode.thresholdExceeded);
      thresholdHit = threshold;
    }
    if (reqNoInv && !ctx.linked) {
      reasons.add(ApprovalReasonCode.noInvoice);
    }
    if (reqOverride && ctx.overHistoryOverride) {
      reasons.add(ApprovalReasonCode.overrideUsed);
    }

    if (reasons.isEmpty) {
      return ReturnApprovalDecision.autoApproved();
    }
    return ReturnApprovalDecision.requiresApproval(
      reasonCodes: reasons,
      thresholdCents: thresholdHit,
    );
  }

  /// Defense-in-depth gate used by `ReturnPostingService.post`. Throws
  /// [ReturnApprovalRequiredException] when [persistedStatus] is not in
  /// [ApprovalStatus.postable].
  void assertPostable({
    required int returnId,
    required String persistedStatus,
    required String side,
    String? persistedReason,
  }) {
    if (ApprovalStatus.canPost(persistedStatus)) return;
    throw ReturnApprovalRequiredException(
      returnId: returnId,
      currentStatus: persistedStatus,
      reasonCodes: (persistedReason ?? '')
          .split(',')
          .where((r) => r.isNotEmpty)
          .toList(),
      side: side,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  static bool _parseBool(String? raw, {required bool defaultValue}) {
    if (raw == null) return defaultValue;
    final v = raw.trim().toLowerCase();
    if (v == '1' || v == 'true' || v == 'yes') return true;
    if (v == '0' || v == 'false' || v == 'no') return false;
    return defaultValue;
  }
}
