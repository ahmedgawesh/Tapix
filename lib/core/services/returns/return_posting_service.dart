import 'dart:developer' as developer;

import '../../../features/accounting/data/repositories/accounting_repository.dart';
import '../compliance/customer_credit_note_service.dart';
import '../compliance/fiscal_period_service.dart';
import 'posted_return.dart';
import 'return_approval_decision.dart';
import 'return_approval_exceptions.dart';
import 'return_journal_policy.dart';

/// **Single API** for posting return-related journal entries.
///
/// Replaces the five legacy methods on `JournalEntryService`:
///   - `recordSaleReturnJournalEntry`
///   - `recordSaleReturnCOGSReversalJournalEntry`
///   - `recordPurchaseReturnJournalEntry`
///   - `recordSaleAdjustmentReturnJournalEntry`
///   - `recordPurchaseAdjustmentReturnJournalEntry`
///
/// All return flows (linked sale, adjustment sale, linked purchase,
/// adjustment purchase) funnel through [post]. The service is the
/// **sole** enforcement point for Phase 2 compliance invariants:
///
///   1. **Fiscal-period guard** (Phase 2.5) — every post is checked
///      against [FiscalPeriodService.assertOpen] BEFORE the JE is
///      written. A post into a closed period is rejected with
///      [FiscalPeriodClosedException].
///
///   2. **Journal-entry shape** (Phase 1) — shape is delegated to
///      [ReturnJournalPolicy.toJournalEntry], the single source of
///      truth for return-JE structure.
///
///   3. **Customer-credit-note sub-ledger** (Phase 2.3) — when a sale
///      return routes its settlement to 2400 Customer Credit
///      Liability (`refund=credit` + `partyId != null` AND the policy
///      decided to route to 2400 because the return is unlinked OR
///      the operator explicitly issued credit rather than reducing
///      AR), the service automatically creates the matching
///      `customer_credit_notes` row and links it back to the issued
///      JE. Σ(open credit-note balances) then reconciles 1:1 with the
///      GL balance of 2400 — without any caller having to know.
///
/// Idempotency: the parent return row carries an `idempotency_key`
/// (Phase 0). Because the DAO insert fails on a duplicate key before
/// it ever reaches this method, [post] itself does **not** need a
/// dedupe guard. The credit-note issuance is additionally guarded by
/// `(source_table, source_id)` uniqueness inside
/// [CustomerCreditNoteService.issueForReturn], so even a manual retry
/// will not double-issue.
class ReturnPostingService {
  final AccountingRepository _accountingRepo;
  final ReturnJournalPolicy _policy;
  final FiscalPeriodService? _fiscalPeriodService;
  final CustomerCreditNoteService? _creditNoteService;

  ReturnPostingService({
    required AccountingRepository accountingRepo,
    required ReturnJournalPolicy policy,
    FiscalPeriodService? fiscalPeriodService,
    CustomerCreditNoteService? creditNoteService,
  })  : _accountingRepo = accountingRepo,
        _policy = policy,
        _fiscalPeriodService = fiscalPeriodService,
        _creditNoteService = creditNoteService;

  /// Post the return journal entry, enforcing all Phase 2 invariants.
  ///
  /// Returns the inserted `journal_entry` id.
  Future<int> post(PostedReturn ret) async {
    // ── 0. Approval gate (Phase 3) ──
    // Defense-in-depth. The DAO writes `approval_status` at draft time,
    // and the same value is plumbed through `PostedReturn`. A post can
    // only proceed when the persisted status is in `postable`. This is
    // the SOLE enforcement point — there is no scattered approval check
    // anywhere else in the codebase.
    if (!ApprovalStatus.canPost(ret.approvalStatus)) {
      throw ReturnApprovalRequiredException(
        returnId: ret.returnId,
        currentStatus: ret.approvalStatus,
        reasonCodes: (ret.approvalReason ?? '')
            .split(',')
            .where((r) => r.isNotEmpty)
            .toList(),
        side: ret.side.name,
      );
    }

    // ── 1. Fiscal-period guard (Phase 2.5) ──
    // Any post landing in a closed period MUST be rejected before the
    // JE is written. Using `now()` as a fallback is intentional — the
    // DAO layer should pass `ret.postingDate`; when it does not, the
    // current date is the correct approximation.
    final effectiveDate = ret.postingDate ?? DateTime.now();
    final fiscal = _fiscalPeriodService;
    if (fiscal != null) {
      await fiscal.assertOpen(effectiveDate);
    }

    // ── 2. Build + persist the JE (Phase 1) ──
    final entryData = await _policy.toJournalEntry(ret);
    final id = await _accountingRepo.createJournalEntry(
      entryData: entryData,
      userId: ret.userId,
    );

    // ── 3. Customer-credit-note sub-ledger (Phase 2.3) ──
    // The policy routed a credit-refund sale-return settlement to 2400
    // when `refund=credit`, the return is UNLINKED, and `partyId` is
    // present. Mirror that exact decision here to keep the sub-ledger
    // perfectly aligned with the GL. The service's own idempotency
    // guard on (source_table, source_id) keeps this safe under retries.
    final credit = _creditNoteService;
    if (credit != null &&
        ret.side == ReturnSide.sale &&
        ret.refund == RefundChannel.credit &&
        !ret.link.isLinked &&
        ret.partyId != null &&
        ret.totalCents > 0) {
      final sourceTable =
          ret.link.sourceTable ?? 'sale_return_adjustments';
      await credit.issueForReturn(
        customerId: ret.partyId!,
        currencyId: ret.currencyId,
        amountCents: ret.totalCents,
        sourceTable: sourceTable,
        sourceId: ret.returnId,
        issueJournalEntryId: id,
        issuedAt: effectiveDate,
      );
    }

    developer.log(
      'ReturnPostingService.post → JE #$id  '
      'side=${ret.side.name}  linked=${ret.link.isLinked}  '
      'returnId=${ret.returnId}  total=${ret.totalCents}  '
      'tax=${ret.taxCents}  invCost=${ret.totalInventoryCostCents}  '
      'refund=${ret.refund.wireValue}  '
      'date=$effectiveDate',
      name: 'ReturnPostingService',
    );

    return id;
  }
}
