import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../money/money.dart';

/// An explicit, reviewed plan. No automatic migration guesses return identity.
class ReviewedCommissionReturnLink {
  final int commissionId;
  final int returnId;
  final int expectedAmountCents;

  const ReviewedCommissionReturnLink({
    required this.commissionId,
    required this.returnId,
    required this.expectedAmountCents,
  });
}

class CommissionSourceReconciliationService {
  final AppDatabase db;
  const CommissionSourceReconciliationService(this.db);

  /// Conservative legacy percentage-commission repair. Ambiguous, fixed-rate,
  /// changed or inconsistent rows require a separate review, never guessing.
  /// Link and audit are atomic; amounts, dates and statuses are never rewritten.
  Future<int> applyReviewedLinks(
    List<ReviewedCommissionReturnLink> links, {
    required String reason,
    int? userId,
  }) => db.transaction(() async {
    if (reason.trim().isEmpty ||
        links.map((l) => l.commissionId).toSet().length != links.length) {
      throw ArgumentError(
        'A review reason and unique commission IDs are required.',
      );
    }
    var changed = 0;
    for (final link in links) {
      final commission = await (db.select(
        db.commissions,
      )..where((c) => c.id.equals(link.commissionId))).getSingle();
      final amount = commission.commissionAmountCents.toBigInt().toInt();
      if (amount >= 0 ||
          amount != link.expectedAmountCents ||
          commission.saleId == null ||
          commission.saleReturnAdjustmentId != null) {
        throw StateError(
          'Commission changed or has no supported legacy source.',
        );
      }
      if (commission.saleReturnId != null) {
        if (commission.saleReturnId == link.returnId) continue;
        throw StateError('Commission already belongs to a different return.');
      }
      final returned = await (db.select(
        db.saleReturns,
      )..where((r) => r.id.equals(link.returnId))).getSingle();
      if (returned.saleId != commission.saleId ||
          returned.status != 'posted' ||
          returned.currencyId != commission.currencyId ||
          commission.effectiveDate == null ||
          !commission.effectiveDate!.isAtSameMomentAs(returned.returnDate)) {
        throw StateError('Reviewed return does not match commission evidence.');
      }
      final candidates = await (db.select(
        db.saleReturns,
      )..where((r) => r.saleId.equals(returned.saleId))).get();
      if (candidates.length != 1) {
        throw StateError('Multiple historical returns require further review.');
      }
      final originals =
          await (db.select(db.commissions)..where(
                (c) =>
                    c.saleId.equals(returned.saleId) &
                    c.employeeId.equals(commission.employeeId),
              ))
              .get();
      final positive = originals
          .where((c) => c.commissionAmountCents.toBigInt().toInt() > 0)
          .toList();
      final negative = originals
          .where((c) => c.commissionAmountCents.toBigInt().toInt() < 0)
          .toList();
      if (positive.length != 1 ||
          negative.length != 1 ||
          positive.single.commissionRateBps <= 0 ||
          positive.single.currencyId != commission.currencyId) {
        throw StateError('Original commission is ambiguous or unsupported.');
      }
      final sale = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(returned.saleId))).getSingle();
      final whole = sale.subtotalCents.toBigInt().toInt();
      final part = returned.subtotalCents.toBigInt().toInt();
      if (whole <= 0 || part <= 0 || part > whole) {
        throw StateError('Return ratio is invalid.');
      }
      final expected = Money.fromCents(
        positive.single.commissionAmountCents.toBigInt().toInt(),
      ).allocate([part, whole - part]).first.cents;
      if (-amount != expected) {
        throw StateError(
          'Deduction does not reconcile to the original commission.',
        );
      }
      await (db.update(db.commissions)
            ..where((c) => c.id.equals(link.commissionId)))
          .write(CommissionsCompanion(saleReturnId: Value(link.returnId)));
      await db
          .into(db.auditLogs)
          .insert(
            AuditLogsCompanion.insert(
              targetTable: 'commissions',
              recordId: link.commissionId,
              action: 'reconcile_return_source',
              userId: Value(userId),
              changes: {
                'old_sale_return_id': null,
                'sale_return_id': link.returnId,
                'amount_cents_unchanged': amount,
                'reason': reason.trim(),
              },
            ),
          );
      changed++;
    }
    return changed;
  });
}
