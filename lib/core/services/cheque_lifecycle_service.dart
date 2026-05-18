import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Variable;

import '../database/app_database.dart';
import '../database/daos/cheque_confirmation_dao.dart';
import '../../features/purchases/domain/repositories/purchase_repository.dart';
import '../../features/sales/domain/repositories/sale_repository.dart';

/// Outcome of a [`ChequeLifecycleService`] transition. Useful for the UI
/// to surface "settled $X" / "reversed $Y" snackbars.
class ChequeTransitionResult {
  /// New status persisted on `cheque_confirmations`.
  final String status;

  /// Outstanding amount (cents) that was settled by this transition.
  /// Non-null only when a real `purchase_payments` / `sale_payments` row
  /// was inserted (i.e. `pending → cleared` for `sale`/`purchase` with
  /// `total > paid`).
  final int? settledAmountCents;

  /// Amount (cents) reversed by this transition. Non-null only on
  /// `cleared → bounced` or `cleared → cancelled` paths that found a
  /// previously-stamped `cleared_payment_id`.
  final int? reversedAmountCents;

  /// `purchase_payments.id` or `sale_payments.id` created by this
  /// transition (cleared path). Mirrors the value persisted on
  /// `cheque_confirmations.cleared_payment_id` so callers can audit.
  final int? createdPaymentId;

  const ChequeTransitionResult({
    required this.status,
    this.settledAmountCents,
    this.reversedAmountCents,
    this.createdPaymentId,
  });
}

/// Thrown when a transition is requested for an unknown / soft-deleted
/// source document. Lets the dashboard show a sane snackbar instead of
/// crashing.
class ChequeSourceNotFoundException implements Exception {
  final String sourceTable;
  final int sourceId;
  ChequeSourceNotFoundException(this.sourceTable, this.sourceId);

  @override
  String toString() =>
      'ChequeSourceNotFoundException: $sourceTable#$sourceId not found';
}

/// Phase 15.0 — single source of truth for cheque lifecycle transitions.
///
/// Phase 14 only persisted the lifecycle state to `cheque_confirmations`.
/// It explicitly deferred the journal-entry side of the transition,
/// which produced a field-reported P0: confirming a cheque as `cleared`
/// in the dashboard did NOT settle the AP/AR balance, did NOT update
/// `purchases.paid_amount_cents` / `sales.paid_amount_cents`, did NOT
/// insert a payment row, and did NOT post `Dr 2000 / Cr Bank` (purchase)
/// or `Dr Bank / Cr 1100` (sale). The supplier/customer profile screen
/// kept showing the original balance and the reconciliation engine
/// surfaced this gap immediately.
///
/// This service closes that gap by orchestrating BOTH writes inside a
/// SINGLE Drift transaction (Drift maps nested transactions to
/// savepoints, so wrapping the repo's own `recordPayment` /
/// `deletePayment` calls is safe and atomic).
///
/// ## Transitions handled
///
/// | from → to              | sale/purchase source        | return source              |
/// | ---------------------- | --------------------------- | -------------------------- |
/// | pending → cleared      | record settlement payment   | mark only (return JE       |
/// |                        | for `total − paid` (≥ 0)    | already credited cash on   |
/// |                        | via repo.recordPayment;     | post; refund leg was       |
/// |                        | stamp `cleared_payment_id`. | independent of the cheque  |
/// |                        |                             | lifecycle).                |
/// | cleared → bounced      | call repo.deletePayment(    | mark only.                 |
/// | cleared → cancelled    | cleared_payment_id) to      |                            |
/// |                        | reverse balance + void JE;  |                            |
/// |                        | NULL the pointer.           |                            |
/// | pending → bounced      | mark only (no payment row   | mark only.                 |
/// | pending → cancelled    | was ever created).          |                            |
///
/// ## Out of scope (deliberately deferred)
///
/// - Two-step IAS-7 pipeline with `1020 Cheques in Hand` /
///   `2030 Cheques Issued` intermediate accounts. The one-step model
///   matches QuickBooks/Xero defaults and keeps the migration risk
///   minimal.
/// - Bounce-fee accounting (bank charges).
/// - Replace-cheque workflow (issue a new cheque to cancel an old one).
/// - Per-cheque metadata (cheque-number, bank, branch). These belong on
///   a dedicated `cheques` table when the field workflow needs them.
class ChequeLifecycleService {
  final AppDatabase _db;
  final ChequeConfirmationDao _confirmDao;
  final PurchaseRepository _purchaseRepo;
  final SaleRepository _saleRepo;

  static const _tag = 'ChequeLifecycleService';

  ChequeLifecycleService({
    required AppDatabase db,
    required ChequeConfirmationDao confirmationDao,
    required PurchaseRepository purchaseRepository,
    required SaleRepository saleRepository,
  })  : _db = db,
        _confirmDao = confirmationDao,
        _purchaseRepo = purchaseRepository,
        _saleRepo = saleRepository;

  // ── public API ────────────────────────────────────────────────────────

  /// Transition the cheque on `(sourceTable, sourceId)` to `cleared`.
  ///
  /// For `sale` / `purchase` with `outstanding = total − paid > 0` this
  /// will also insert a real payment row, update the party balance,
  /// post the journal entry, and stamp `cleared_payment_id` on the
  /// confirmation row. For the four return source types, or when
  /// `outstanding == 0`, only the lifecycle status flips.
  Future<ChequeTransitionResult> markCleared({
    required String sourceTable,
    required int sourceId,
    int? userId,
    String? note,
  }) {
    return _db.transaction(() async {
      final existing = await _confirmDao.getBySource(
        sourceTable: sourceTable,
        sourceId: sourceId,
      );

      // Idempotency — a second click on "Confirm Paid" must NOT post a
      // second payment row. We treat `cleared` (with or without a
      // payment id) as terminal here; the user can transition out via
      // bounce/cancel if they made a mistake.
      if (existing != null &&
          existing.status == ChequeConfirmationStatus.cleared) {
        return ChequeTransitionResult(
          status: ChequeConfirmationStatus.cleared,
          createdPaymentId: existing.clearedPaymentId,
        );
      }

      int? createdPaymentId;
      int? settledAmount;

      if (_isSettleableSource(sourceTable)) {
        final outstanding = await _outstandingCentsFor(
          sourceTable: sourceTable,
          sourceId: sourceId,
        );

        if (outstanding > 0) {
          createdPaymentId = await _recordSettlementPayment(
            sourceTable: sourceTable,
            sourceId: sourceId,
            amountCents: outstanding,
            note: note,
          );
          settledAmount = outstanding;
          developer.log(
            'Cheque cleared → settled $outstanding¢ on $sourceTable#$sourceId '
            'via payment#$createdPaymentId',
            name: _tag,
          );
        } else {
          developer.log(
            'Cheque cleared on $sourceTable#$sourceId — outstanding=0, '
            'lifecycle row updated without a new payment.',
            name: _tag,
          );
        }
      } else {
        developer.log(
          'Cheque cleared on $sourceTable#$sourceId — return source, '
          'no settlement payment posted (refund JE already booked at '
          'return-post time).',
          name: _tag,
        );
      }

      await _confirmDao.confirm(
        sourceTable: sourceTable,
        sourceId: sourceId,
        status: ChequeConfirmationStatus.cleared,
        note: note,
        userId: userId,
        clearedPaymentId: createdPaymentId,
      );

      return ChequeTransitionResult(
        status: ChequeConfirmationStatus.cleared,
        settledAmountCents: settledAmount,
        createdPaymentId: createdPaymentId,
      );
    });
  }

  /// Transition the cheque to `bounced`. Reverses the prior settlement
  /// payment iff the cheque was previously `cleared` and a payment id is
  /// stamped on the confirmation row.
  Future<ChequeTransitionResult> markBounced({
    required String sourceTable,
    required int sourceId,
    required String bounceReason,
    int? userId,
  }) {
    if (bounceReason.trim().isEmpty) {
      throw ArgumentError('bounceReason is required when marking bounced');
    }
    return _db.transaction(() async {
      final reversed = await _reversePriorSettlementIfNeeded(
        sourceTable: sourceTable,
        sourceId: sourceId,
      );

      await _confirmDao.confirm(
        sourceTable: sourceTable,
        sourceId: sourceId,
        status: ChequeConfirmationStatus.bounced,
        bounceReason: bounceReason,
        userId: userId,
        // Drop the payment id pointer — the row is gone.
        clearClearedPaymentId: true,
      );

      return ChequeTransitionResult(
        status: ChequeConfirmationStatus.bounced,
        reversedAmountCents: reversed,
      );
    });
  }

  /// Transition the cheque to `cancelled`. Reverses the prior
  /// settlement payment iff the cheque was previously `cleared`.
  Future<ChequeTransitionResult> markCancelled({
    required String sourceTable,
    required int sourceId,
    int? userId,
  }) {
    return _db.transaction(() async {
      final reversed = await _reversePriorSettlementIfNeeded(
        sourceTable: sourceTable,
        sourceId: sourceId,
      );

      await _confirmDao.confirm(
        sourceTable: sourceTable,
        sourceId: sourceId,
        status: ChequeConfirmationStatus.cancelled,
        userId: userId,
        clearClearedPaymentId: true,
      );

      return ChequeTransitionResult(
        status: ChequeConfirmationStatus.cancelled,
        reversedAmountCents: reversed,
      );
    });
  }

  // ── helpers ───────────────────────────────────────────────────────────

  bool _isSettleableSource(String sourceTable) =>
      sourceTable == ChequeSourceTables.sale ||
      sourceTable == ChequeSourceTables.purchase;

  /// Returns `total_cents − paid_amount_cents` (clamped at 0) for the
  /// source document. Throws [`ChequeSourceNotFoundException`] when the
  /// source row was hard-deleted (extremely rare — voiding is the
  /// sanctioned path).
  Future<int> _outstandingCentsFor({
    required String sourceTable,
    required int sourceId,
  }) async {
    if (sourceTable == ChequeSourceTables.purchase) {
      final p = await _purchaseRepo.getPurchaseById(sourceId);
      if (p == null) {
        throw ChequeSourceNotFoundException(sourceTable, sourceId);
      }
      final outstanding = p.totalCents - p.paidAmountCents;
      return outstanding < Decimal.zero
          ? 0
          : outstanding.toBigInt().toInt();
    }
    if (sourceTable == ChequeSourceTables.sale) {
      final s = await _saleRepo.getSaleById(sourceId);
      if (s == null) {
        throw ChequeSourceNotFoundException(sourceTable, sourceId);
      }
      final outstanding = s.totalCents - s.paidAmountCents;
      return outstanding < Decimal.zero
          ? 0
          : outstanding.toBigInt().toInt();
    }
    return 0;
  }

  /// Records a real payment via the matching repository. Returns the
  /// new `purchase_payments.id` or `sale_payments.id`.
  Future<int> _recordSettlementPayment({
    required String sourceTable,
    required int sourceId,
    required int amountCents,
    String? note,
  }) async {
    if (sourceTable == ChequeSourceTables.purchase) {
      final p = await _purchaseRepo.getPurchaseById(sourceId);
      if (p == null) {
        throw ChequeSourceNotFoundException(sourceTable, sourceId);
      }
      return _purchaseRepo.recordPayment(
        purchaseId: sourceId,
        currencyId: p.currencyId,
        amountCents: Decimal.fromInt(amountCents),
        paymentMethod: 'cheque',
        notes: note ?? 'Cheque cleared via confirmation',
        paymentDate: DateTime.now(),
      );
    }
    if (sourceTable == ChequeSourceTables.sale) {
      final s = await _saleRepo.getSaleById(sourceId);
      if (s == null) {
        throw ChequeSourceNotFoundException(sourceTable, sourceId);
      }
      return _saleRepo.recordPayment(
        saleId: sourceId,
        amountCents: Decimal.fromInt(amountCents),
        currencyId: s.currencyId,
        paymentMethod: 'cheque',
        notes: note ?? 'Cheque cleared via confirmation',
        paymentDate: DateTime.now(),
      );
    }
    throw StateError(
      '_recordSettlementPayment called for non-settleable source $sourceTable',
    );
  }

  /// Inverse of [`_recordSettlementPayment`]. If the confirmation row
  /// holds a `cleared_payment_id`, calls `deletePayment` on the matching
  /// repo. That SoT method already (a) voids the JE, (b) inserts the
  /// `payment_reversal` supplier/customer transaction, (c) restores the
  /// party balance, and (d) recomputes `paid_amount_cents`.
  ///
  /// Returns the reversed amount (cents) or `null` when nothing was
  /// reversed.
  Future<int?> _reversePriorSettlementIfNeeded({
    required String sourceTable,
    required int sourceId,
  }) async {
    final existing = await _confirmDao.getBySource(
      sourceTable: sourceTable,
      sourceId: sourceId,
    );
    if (existing == null) return null;
    if (existing.status != ChequeConfirmationStatus.cleared) return null;
    final paymentId = existing.clearedPaymentId;
    if (paymentId == null) return null;

    // Snapshot the amount BEFORE deleting (used for the UX result + tests).
    final amountSnapshot = await _readPaymentAmountCents(
      sourceTable: sourceTable,
      paymentId: paymentId,
    );

    if (sourceTable == ChequeSourceTables.purchase) {
      await _purchaseRepo.deletePayment(paymentId);
    } else if (sourceTable == ChequeSourceTables.sale) {
      await _saleRepo.deletePayment(paymentId);
    } else {
      // Should never happen — returns never set `cleared_payment_id`.
      developer.log(
        'Unexpected cleared_payment_id on return source $sourceTable — ignored.',
        name: _tag,
      );
      return null;
    }

    developer.log(
      'Cheque reversed on $sourceTable#$sourceId — '
      'deleted payment#$paymentId ($amountSnapshot¢)',
      name: _tag,
    );
    return amountSnapshot;
  }

  /// Reads the `amount_cents` of a payment row by id and source table.
  /// Returns `null` when the row was already removed (defensive).
  Future<int?> _readPaymentAmountCents({
    required String sourceTable,
    required int paymentId,
  }) async {
    final table = sourceTable == ChequeSourceTables.purchase
        ? 'purchase_payments'
        : 'sale_payments';
    final row = await _db.customSelect(
      'SELECT amount_cents FROM $table WHERE id = ?',
      variables: [Variable.withInt(paymentId)],
    ).getSingleOrNull();
    return row?.read<int>('amount_cents');
  }
}

