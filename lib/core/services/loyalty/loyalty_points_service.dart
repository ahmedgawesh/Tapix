// ════════════════════════════════════════════════════════════════════════════
// LoyaltyPointsService — single source of truth for loyalty-point math.
// ════════════════════════════════════════════════════════════════════════════
//
// Extracted from `sale_repository_impl.dart` and `loyalty_repository_impl.dart`
// during Phase 6 of the scattered-calculation-logic migration (May 2026).
//
// CONTRACT
// --------
//   * `compute(input)`              — pure, deterministic. Award formula
//                                     used by BOTH the live award path
//                                     and the UI preview path. Replaces
//                                     three historical copies that could
//                                     silently drift apart.
//   * `awardForSale(...)`           — orchestrator: compute + persist via
//                                     LoyaltyRepository.addPoints + post
//                                     the loyalty-earn journal entry.
//   * `reverseForReturn(...)`       — orchestrator: proportional reversal
//                                     when a sale return is created.
//
// ROUNDING
// --------
// All scalar multiplications (tier multiplier, bonus%, birthday%) are
// performed with `Decimal` arithmetic — NEVER `(int * double).round()`.
// This eliminates the IEEE-754 traps documented in the audit (e.g.
// `(15 * 1.1).round()` = 17 in IEEE because 15*1.1 ≈ 16.500000000000004).
// Half-away-from-zero rounding matches the legacy `.round()` semantics
// byte-for-byte on the common cases that arise from human-entered
// percentages (integer or one-decimal-place values).
//
// CALLERS
// -------
// Only `SaleRepositoryImpl` (award + reverse) and `LoyaltyRepositoryImpl`
// (preview) should depend on this service. No other code computes
// `loyalty_point_transactions.points` or `customers.loyalty_points_balance`.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../../features/customers/domain/repositories/loyalty_repository.dart';
import '../journal_entry_service.dart';
import '../currency_service.dart' as money;

/// Inputs for the pure award formula.
///
/// Every field is derived from `LoyaltySettings` + the customer's
/// current `LoyaltyTier`. Keeping this as a pure data class lets the
/// preview path build it from cached/default values and the award
/// path build it from freshly-loaded values — both routes hit the
/// same `compute` function.
class LoyaltyAwardInput {
  /// Sale total in cents — the base on which points accrue.
  final int amountCents;
  final int minorUnitFactor;

  /// `LoyaltySettings.pointsPerCurrencyUnit`.
  final int pointsPerCurrencyUnit;

  /// `LoyaltySettings.minSpendForPoints`. If `amountCents <` this, no
  /// points are awarded and the result is all zeros.
  final int minSpendForPoints;

  /// `LoyaltyTier.pointsMultiplier` (e.g. 1.0, 1.5, 2.0). Applied to
  /// the base points BEFORE the bonus% layer.
  final double multiplier;

  /// `LoyaltyTier.discountPercent` — despite the column name this is
  /// the **bonus-points percentage** added on top of the tier-adjusted
  /// total. Stored as a percent (e.g. `5.0` = +5%).
  final double bonusPercent;

  /// Whether the business birthday matches today (the orchestrator
  /// computes this before calling `compute`). Lets the formula stay
  /// pure / clock-independent and testable.
  final bool applyBirthdayBonus;

  /// `LoyaltyTier.birthdayBonusPoints` — flat extra points granted
  /// once when `applyBirthdayBonus` is true.
  final int birthdayBonusPoints;

  /// `LoyaltyTier.birthdayDiscountPercent` — additional percentage
  /// bonus on top of the post-flat total when the birthday matches.
  final double birthdayDiscountPercent;

  const LoyaltyAwardInput({
    required this.amountCents,
    this.minorUnitFactor = 100,
    required this.pointsPerCurrencyUnit,
    required this.minSpendForPoints,
    this.multiplier = 1.0,
    this.bonusPercent = 0.0,
    this.applyBirthdayBonus = false,
    this.birthdayBonusPoints = 0,
    this.birthdayDiscountPercent = 0.0,
  });
}

/// Breakdown of an award computation. The orchestrator only persists
/// `totalPoints`, but exposing every intermediate value lets the UI
/// show "earned 100 + 10% bonus + birthday 50" and lets tests pin
/// down each layer independently.
class LoyaltyAwardResult {
  final int basePoints;
  final int tierAdjustedPoints;
  final int bonusPoints;
  final int birthdayFlatBonus;
  final int birthdayPercentBonus;
  final int totalPoints;

  const LoyaltyAwardResult({
    required this.basePoints,
    required this.tierAdjustedPoints,
    required this.bonusPoints,
    required this.birthdayFlatBonus,
    required this.birthdayPercentBonus,
    required this.totalPoints,
  });

  static const LoyaltyAwardResult zero = LoyaltyAwardResult(
    basePoints: 0,
    tierAdjustedPoints: 0,
    bonusPoints: 0,
    birthdayFlatBonus: 0,
    birthdayPercentBonus: 0,
    totalPoints: 0,
  );
}

/// Non-mutating preview of a loyalty-point deduction for a credit
/// adjustment return, plus the per-point monetary value so the UI can
/// render "‑N points (= X cents = $Y)" in the selected currency.
class LoyaltyDeductionPreview {
  /// Whether the loyalty program is enabled (drives UI visibility).
  final bool enabled;

  /// Points that WOULD be deducted (already capped at the customer's
  /// current balance). Zero when nothing to deduct.
  final int pointsToDeduct;

  /// Value of ONE point in cents (from `LoyaltySettings.pointValueCents`).
  final int pointValueCents;

  const LoyaltyDeductionPreview({
    required this.enabled,
    required this.pointsToDeduct,
    required this.pointValueCents,
  });

  /// Total monetary value of [pointsToDeduct] in cents.
  int get totalValueCents => pointsToDeduct * pointValueCents;

  static const LoyaltyDeductionPreview disabled = LoyaltyDeductionPreview(
    enabled: false,
    pointsToDeduct: 0,
    pointValueCents: 0,
  );
}

class LoyaltyPointsService {
  final LoyaltyRepository _loyalty;
  final JournalEntryService _journal;
  final AppDatabase _db;

  LoyaltyPointsService(this._loyalty, this._journal, this._db);

  Future<int> _minorUnitFactor(int currencyId) async {
    final row = await (_db.select(
      _db.currencies,
    )..where((c) => c.id.equals(currencyId))).getSingle();
    final currency = money.Currency.allCurrencies.singleWhere(
      (c) => c.code == row.code,
    );
    var factor = 1;
    for (var i = 0; i < currency.decimalDigits; i++) {
      factor *= 10;
    }
    return factor;
  }

  // ─────────────────────────── PURE COMPUTE ───────────────────────────

  /// Pure award formula. Matches the legacy formula in
  /// `_awardLoyaltyPointsForSale` byte-for-byte on every integer-and
  /// one-decimal-place percentage input. Decimal arithmetic eliminates
  /// the IEEE-754 corner cases on inputs like `multiplier=1.1`.
  static LoyaltyAwardResult compute(LoyaltyAwardInput input) {
    if (input.minorUnitFactor <= 0) {
      throw ArgumentError.value(input.minorUnitFactor);
    }
    if (input.amountCents < input.minSpendForPoints) {
      return LoyaltyAwardResult.zero;
    }
    if (input.pointsPerCurrencyUnit <= 0 || input.amountCents <= 0) {
      return LoyaltyAwardResult.zero;
    }

    // Base points: same formula as legacy — integer-floor division.
    final basePoints =
        (input.amountCents * input.pointsPerCurrencyUnit) ~/
        input.minorUnitFactor;
    if (basePoints <= 0) return LoyaltyAwardResult.zero;

    // Tier multiplier — Decimal, half-away-from-zero rounding.
    final tierAdjusted = _mulRound(basePoints, input.multiplier);

    // Bonus % on top of the tier-adjusted total.
    final bonus = input.bonusPercent > 0
        ? _mulRound(tierAdjusted, input.bonusPercent / 100.0)
        : 0;

    var points = tierAdjusted + bonus;

    int birthdayFlat = 0;
    int birthdayPct = 0;
    if (input.applyBirthdayBonus) {
      if (input.birthdayBonusPoints > 0) {
        birthdayFlat = input.birthdayBonusPoints;
        points += birthdayFlat;
      }
      if (input.birthdayDiscountPercent > 0) {
        birthdayPct = _mulRound(points, input.birthdayDiscountPercent / 100.0);
        points += birthdayPct;
      }
    }

    return LoyaltyAwardResult(
      basePoints: basePoints,
      tierAdjustedPoints: tierAdjusted,
      bonusPoints: bonus,
      birthdayFlatBonus: birthdayFlat,
      birthdayPercentBonus: birthdayPct,
      totalPoints: points,
    );
  }

  /// Synchronous preview used by `LoyaltyRepository.calculatePointsToEarn`.
  ///
  /// The legacy preview hard-coded `pointsPerCurrencyUnit = 1`, which
  /// drifted from the actual award whenever an operator configured
  /// anything other than 1. To preserve the existing public signature
  /// without breaking call sites, we keep that fallback but funnel
  /// through `compute` so the formula is identical.
  static int previewSync({
    required int amountCents,
    required double multiplier,
    int pointsPerCurrencyUnit = 1,
    int minSpendForPoints = 0,
  }) {
    return compute(
      LoyaltyAwardInput(
        amountCents: amountCents,
        pointsPerCurrencyUnit: pointsPerCurrencyUnit,
        minSpendForPoints: minSpendForPoints,
        multiplier: multiplier,
      ),
    ).totalPoints;
  }

  // ───────────────────────── AWARD ORCHESTRATOR ─────────────────────────

  /// Award loyalty points after a sale is posted. Returns the points
  /// added (0 if loyalty is disabled, customer is below threshold, etc.).
  ///
  /// Mirrors the legacy `_awardLoyaltyPointsForSale` orchestration:
  /// 1. resolve settings + tier,
  /// 2. evaluate birthday match,
  /// 3. compute points via [compute],
  /// 4. persist via `LoyaltyRepository.addPoints`,
  /// 5. record `Dr Discounts Given / Cr Loyalty Points Liability` JE.
  ///
  /// With strict=true, failures propagate to the document transaction.
  /// Otherwise failures are logged so a loyalty error never
  /// rolls back the sale.
  Future<int> awardForSale({
    required int customerId,
    required int saleId,
    required int totalCents,
    bool strict = false,
  }) async {
    try {
      return await _db.transaction(() async {
        final settings = await _loyalty.getLoyaltySettings();
        if (settings == null || !settings.isEnabled) return 0;

        final sale = await _db.saleDao.getSaleById(saleId);
        if (sale == null ||
            sale.customerId != customerId ||
            sale.status != 'completed') {
          throw StateError(
            'Loyalty award requires the completed customer sale',
          );
        }
        final factor = await _minorUnitFactor(sale.currencyId);
        final summary = await _loyalty.getCustomerLoyaltySummary(customerId);
        final tier = summary?.currentTier;

        var applyBirthday = false;
        if (tier != null &&
            tier.birthdayBonus &&
            settings.businessBirthdayDate != null) {
          final today = DateTime.now();
          final bday = settings.businessBirthdayDate!;
          applyBirthday = today.month == bday.month && today.day == bday.day;
        }

        final result = compute(
          LoyaltyAwardInput(
            amountCents: totalCents,
            minorUnitFactor: factor,
            pointsPerCurrencyUnit: settings.pointsPerCurrencyUnit,
            minSpendForPoints: settings.minSpendForPoints,
            multiplier: tier?.pointsMultiplier ?? 1.0,
            bonusPercent: tier?.discountPercent ?? 0.0,
            applyBirthdayBonus: applyBirthday,
            birthdayBonusPoints: tier?.birthdayBonusPoints ?? 0,
            birthdayDiscountPercent: tier?.birthdayDiscountPercent ?? 0.0,
          ),
        );

        final points = result.totalPoints;
        if (points <= 0) return 0;

        await _loyalty.addPoints(
          customerId: customerId,
          points: points,
          source: 'sale',
          referenceId: saleId,
          referenceType: 'sale',
          description: 'Points earned from sale #$saleId',
        );

        // Dr Discounts Given (5500), Cr Loyalty Points Liability (2300).
        final earnValueCents = points * settings.pointValueCents;
        if (earnValueCents > 0) {
          final currencyId = sale.currencyId;
          await _journal.recordLoyaltyEarnJournalEntry(
            saleId: saleId,
            valueCents: earnValueCents,
            currencyId: currencyId,
          );
        }

        return points;
      });
    } catch (e, st) {
      if (strict) rethrow;
      developer.log(
        'LoyaltyPointsService.awardForSale failed for sale #$saleId: $e\n$st',
        name: 'LoyaltyPointsService',
      );
      return 0;
    }
  }

  // ─────────────────────── REVERSE ORCHESTRATOR ───────────────────────

  /// Reverse the actual recorded award proportionally. Cumulative allocation
  /// avoids losing points across partial returns; today's rates are irrelevant.
  Future<int> reverseForReturn({
    required int saleId,
    required int returnId,
    required int returnTotalCents,
    bool strict = false,
  }) async {
    try {
      return await _db.transaction(() async {
        final sale = await _db.saleDao.getSaleById(saleId);
        final returned = await _db.saleDao.getSaleReturnById(returnId);
        if (sale == null || sale.customerId == null) return 0;
        if (returned == null ||
            returned.saleId != saleId ||
            returned.status != 'posted' ||
            returned.totalCents.toBigInt().toInt() != returnTotalCents) {
          throw StateError(
            'Loyalty reversal requires the posted source return',
          );
        }
        final existing = await _db
            .customSelect(
              "SELECT id FROM loyalty_point_transactions WHERE reference_type='sale_return' AND reference_id=? LIMIT 1",
              variables: [Variable.withInt(returnId)],
            )
            .getSingleOrNull();
        if (existing != null) return 0;
        final earned = await _db
            .customSelect(
              "SELECT COALESCE(SUM(points),0) AS n FROM loyalty_point_transactions WHERE customer_id=? AND reference_type='sale' AND reference_id=? AND points>0",
              variables: [
                Variable.withInt(sale.customerId!),
                Variable.withInt(saleId),
              ],
            )
            .getSingle();
        final points = earned.read<int>('n');
        final total = sale.totalCents.toBigInt().toInt();
        if (points <= 0 || total <= 0) return 0;
        final history = await _db
            .customSelect(
              "SELECT COALESCE(SUM(total_cents),0) AS amount FROM sale_returns WHERE sale_id=? AND status='posted'",
              variables: [Variable.withInt(saleId)],
            )
            .getSingle();
        final amount = history.read<int>('amount').clamp(0, total);
        final deducted = await _db
            .customSelect(
              "SELECT COALESCE(-SUM(t.points),0) AS n FROM loyalty_point_transactions t JOIN sale_returns r ON r.id=t.reference_id WHERE t.reference_type='sale_return' AND t.customer_id=? AND t.points<0 AND r.sale_id=? AND r.status='posted'",
              variables: [
                Variable.withInt(sale.customerId!),
                Variable.withInt(saleId),
              ],
            )
            .getSingle();
        final customer = await _db.customerDao.getCustomer(sale.customerId!);
        final target =
            (BigInt.from(points) * BigInt.from(amount) ~/ BigInt.from(total))
                .toInt() -
            deducted.read<int>('n');
        final actual = target.clamp(0, customer?.loyaltyPointsBalance ?? 0);
        if (actual <= 0) return 0;
        await _loyalty.redeemPoints(
          customerId: sale.customerId!,
          points: actual,
          reason: 'Recorded award reversed for return #$returnId',
          referenceId: returnId,
          referenceType: 'sale_return',
        );
        final earnedValue = await _db
            .customSelect(
              "SELECT COALESCE(SUM(l.credit_cents-l.debit_cents),0) AS value FROM journal_entries j JOIN journal_entry_lines l ON l.journal_entry_id=j.id JOIN accounts a ON a.id=l.account_id WHERE j.source_table='sales' AND j.source_id=? AND j.entry_type='loyalty_earn' AND j.status='posted' AND a.account_code='2300' AND l.currency_id=?",
              variables: [
                Variable.withInt(saleId),
                Variable.withInt(sale.currencyId),
              ],
            )
            .getSingle();
        final value =
            (BigInt.from(earnedValue.read<int>('value')) *
                    BigInt.from(actual) ~/
                    BigInt.from(points))
                .toInt();
        await _journal.recordLoyaltyReturnJournalEntry(
          returnId: returnId,
          valueCents: value,
          currencyId: sale.currencyId,
        );
        return actual;
      });
    } catch (e) {
      if (strict) rethrow;
      developer.log(
        'Loyalty return reversal failed: $e',
        name: 'LoyaltyPointsService',
      );
      return 0;
    }
  }

  // ─────────────────── ADJUSTMENT-RETURN PREVIEW ───────────────────

  /// Non-mutating preview of the loyalty-point deduction that
  /// [reverseForAdjustmentReturn] would apply for a credit adjustment
  /// return of [returnTotalCents] against [customerId]. Also surfaces
  /// the monetary value of those points so the UI can show "‑N points
  /// (= X cents = $Y)". Returns [LoyaltyDeductionPreview.disabled] when
  /// loyalty is off / customer absent / nothing to deduct. Never throws.
  Future<LoyaltyDeductionPreview> previewAdjustmentReturnDeduction({
    required int customerId,
    required int returnTotalCents,
  }) async {
    try {
      final settings = await _loyalty.getLoyaltySettings();
      if (settings == null || !settings.isEnabled) {
        return LoyaltyDeductionPreview.disabled;
      }
      if (returnTotalCents <= 0) {
        return LoyaltyDeductionPreview(
          enabled: true,
          pointsToDeduct: 0,
          pointValueCents: settings.pointValueCents,
        );
      }

      final summary = await _loyalty.getCustomerLoyaltySummary(customerId);
      final multiplier = summary?.currentTier?.pointsMultiplier ?? 1.0;

      final customer = await _db.customerDao.getCustomer(customerId);
      if (customer == null) return LoyaltyDeductionPreview.disabled;
      final factor = await _minorUnitFactor(customer.currencyId);
      final basePoints =
          (returnTotalCents * settings.pointsPerCurrencyUnit) ~/ factor;
      final computed = basePoints <= 0 ? 0 : _mulRound(basePoints, multiplier);
      final currentBalance = summary?.pointsBalance ?? 0;
      final capped = computed > currentBalance ? currentBalance : computed;

      return LoyaltyDeductionPreview(
        enabled: true,
        pointsToDeduct: capped < 0 ? 0 : capped,
        pointValueCents: settings.pointValueCents,
      );
    } catch (e) {
      developer.log(
        'LoyaltyPointsService.previewAdjustmentReturnDeduction failed: $e',
        name: 'LoyaltyPointsService',
      );
      return LoyaltyDeductionPreview.disabled;
    }
  }

  // ─────────────────── ADJUSTMENT-RETURN ORCHESTRATOR ───────────────────

  /// Deduct loyalty points when a sale ADJUSTMENT (unlinked) return is
  /// posted for an attributed customer.
  ///
  /// Because the return is unlinked there is no original sale to prorate
  /// against, so the deduction is recomputed from the return's own total
  /// using the live settings + the customer's current tier multiplier —
  /// the same base×multiplier layer that [reverseForReturn] reverses for
  /// linked returns (birthday/bonus layers intentionally excluded so a
  /// customer never loses a one-time windfall on a return).
  ///
  /// The deduction is capped at the customer's current balance so the
  /// balance is never pushed negative. Keyed by [adjustmentReturnId] with
  /// `referenceType = 'sale_return_adjustment'` so a void restores it
  /// exactly. Never throws — loyalty is non-critical and must not roll
  /// back the accounting post.
  Future<int> reverseForAdjustmentReturn({
    required int customerId,
    required int adjustmentReturnId,
    required int returnTotalCents,
    DateTime? returnDate,
  }) async {
    try {
      if (returnTotalCents <= 0) return 0;

      final settings = await _loyalty.getLoyaltySettings();
      if (settings == null || !settings.isEnabled) return 0;

      final summary = await _loyalty.getCustomerLoyaltySummary(customerId);
      final multiplier = summary?.currentTier?.pointsMultiplier ?? 1.0;

      final customer = await _db.customerDao.getCustomer(customerId);
      if (customer == null) return 0;
      final factor = await _minorUnitFactor(customer.currencyId);
      final basePoints =
          (returnTotalCents * settings.pointsPerCurrencyUnit) ~/ factor;
      if (basePoints <= 0) return 0;
      final pointsToDeduct = _mulRound(basePoints, multiplier);
      if (pointsToDeduct <= 0) return 0;

      final currentBalance = summary?.pointsBalance ?? 0;
      final actualDeduction = pointsToDeduct > currentBalance
          ? currentBalance
          : pointsToDeduct;
      if (actualDeduction <= 0) return 0;

      await _loyalty.redeemPoints(
        customerId: customerId,
        points: actualDeduction,
        reason: 'Points reversed for adjustment return #$adjustmentReturnId',
        referenceId: adjustmentReturnId,
        referenceType: 'sale_return_adjustment',
      );

      return actualDeduction;
    } catch (e) {
      developer.log(
        'LoyaltyPointsService.reverseForAdjustmentReturn failed for '
        'return #$adjustmentReturnId: $e',
        name: 'LoyaltyPointsService',
      );
      return 0;
    }
  }

  /// Restore the points that [reverseForAdjustmentReturn] deducted, when
  /// that adjustment return is voided. Reads back the exact deducted
  /// amount from `loyalty_point_transactions` (the negative row keyed by
  /// [adjustmentReturnId]) and re-adds its absolute value. Never throws.
  Future<int> restoreForAdjustmentReturnVoid({
    required int customerId,
    required int adjustmentReturnId,
  }) async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT points FROM loyalty_point_transactions '
            "WHERE reference_type = 'sale_return_adjustment' "
            '  AND reference_id = ? AND customer_id = ? AND points < 0',
            variables: [
              Variable.withInt(adjustmentReturnId),
              Variable.withInt(customerId),
            ],
          )
          .get();
      if (rows.isEmpty) return 0;

      final deducted = rows.fold<int>(
        0,
        (sum, r) => sum + r.read<int>('points'),
      );
      final toRestore = -deducted;
      if (toRestore <= 0) return 0;

      await _loyalty.addPoints(
        customerId: customerId,
        points: toRestore,
        source: 'sale_return_adjustment_void',
        referenceId: adjustmentReturnId,
        referenceType: 'sale_return_adjustment_void',
        description:
            'Points restored on void of adjustment return #$adjustmentReturnId',
      );

      return toRestore;
    } catch (e) {
      developer.log(
        'LoyaltyPointsService.restoreForAdjustmentReturnVoid failed for '
        'return #$adjustmentReturnId: $e',
        name: 'LoyaltyPointsService',
      );
      return 0;
    }
  }

  // ───────────────────────────── HELPERS ─────────────────────────────

  /// Decimal-based scalar multiplication with half-away-from-zero
  /// rounding. The Dart `double.toString()` round-trip is exact for
  /// every integer / one-decimal-place / two-decimal-place value an
  /// operator can realistically enter — and is dramatically more
  /// accurate than `(int * double).round()` for all other inputs.
  static int _mulRound(int value, double factor) {
    if (value == 0 || factor == 0) return 0;
    if (factor == 1.0) return value;
    final d = Decimal.fromInt(value) * Decimal.parse(factor.toString());
    // `Decimal.round()` uses HALF_AWAY_FROM_ZERO, matching `double.round()`.
    return d.round().toBigInt().toInt();
  }
}
