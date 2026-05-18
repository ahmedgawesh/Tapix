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

import '../../database/app_database.dart';
import '../../../features/customers/domain/repositories/loyalty_repository.dart';
import '../journal_entry_service.dart';

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

class LoyaltyPointsService {
  final LoyaltyRepository _loyalty;
  final JournalEntryService _journal;
  final AppDatabase _db;

  LoyaltyPointsService(this._loyalty, this._journal, this._db);

  // ─────────────────────────── PURE COMPUTE ───────────────────────────

  /// Pure award formula. Matches the legacy formula in
  /// `_awardLoyaltyPointsForSale` byte-for-byte on every integer-and
  /// one-decimal-place percentage input. Decimal arithmetic eliminates
  /// the IEEE-754 corner cases on inputs like `multiplier=1.1`.
  static LoyaltyAwardResult compute(LoyaltyAwardInput input) {
    if (input.amountCents < input.minSpendForPoints) {
      return LoyaltyAwardResult.zero;
    }
    if (input.pointsPerCurrencyUnit <= 0 || input.amountCents <= 0) {
      return LoyaltyAwardResult.zero;
    }

    // Base points: same formula as legacy — integer-floor division.
    final basePoints =
        (input.amountCents * input.pointsPerCurrencyUnit) ~/ 100;
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
    return compute(LoyaltyAwardInput(
      amountCents: amountCents,
      pointsPerCurrencyUnit: pointsPerCurrencyUnit,
      minSpendForPoints: minSpendForPoints,
      multiplier: multiplier,
    )).totalPoints;
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
  /// Never throws — failures are logged so a loyalty error never
  /// rolls back the sale.
  Future<int> awardForSale({
    required int customerId,
    required int saleId,
    required int totalCents,
  }) async {
    try {
      final settings = await _loyalty.getLoyaltySettings();
      if (settings == null || !settings.isEnabled) return 0;

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

      final result = compute(LoyaltyAwardInput(
        amountCents: totalCents,
        pointsPerCurrencyUnit: settings.pointsPerCurrencyUnit,
        minSpendForPoints: settings.minSpendForPoints,
        multiplier: tier?.pointsMultiplier ?? 1.0,
        bonusPercent: tier?.discountPercent ?? 0.0,
        applyBirthdayBonus: applyBirthday,
        birthdayBonusPoints: tier?.birthdayBonusPoints ?? 0,
        birthdayDiscountPercent: tier?.birthdayDiscountPercent ?? 0.0,
      ));

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
        final customer = await _db.customerDao.getCustomer(customerId);
        final currencyId = customer?.currencyId ?? 1;
        await _journal.recordLoyaltyEarnJournalEntry(
          saleId: saleId,
          valueCents: earnValueCents,
          currencyId: currencyId,
        );
      }

      return points;
    } catch (e, st) {
      developer.log(
        'LoyaltyPointsService.awardForSale failed for sale #$saleId: $e\n$st',
        name: 'LoyaltyPointsService',
      );
      return 0;
    }
  }

  // ─────────────────────── REVERSE ORCHESTRATOR ───────────────────────

  /// Reverse loyalty points proportionally when a sale return is created.
  ///
  /// Proration uses `returnTotalCents / saleTotalCents` against the
  /// originally-awarded points (recomputed via [compute] without any
  /// birthday/bonus layers — matching the legacy semantics that
  /// reversed only the BASE * MULTIPLIER component).
  ///
  /// The deduction is capped at the customer's current balance: we
  /// never push the balance negative on a return.
  ///
  /// Never throws — failures are logged.
  Future<int> reverseForReturn({
    required int saleId,
    required int returnId,
    required int returnTotalCents,
  }) async {
    try {
      final db = _db;
      final sale = await db.saleDao.getSaleById(saleId);
      if (sale == null || sale.customerId == null) return 0;

      final settings = await _loyalty.getLoyaltySettings();
      if (settings == null || !settings.isEnabled) return 0;

      final saleTotalCents = sale.totalCents.toBigInt().toInt();
      if (saleTotalCents <= 0) return 0;

      final summary =
          await _loyalty.getCustomerLoyaltySummary(sale.customerId!);
      final multiplier = summary?.currentTier?.pointsMultiplier ?? 1.0;

      // Original points base layer — birthday/tier-bonus layers are
      // intentionally excluded to match the legacy reversal semantics
      // (otherwise customers could lose a one-time birthday windfall
      // on a partial return).
      final originalBasePoints =
          (saleTotalCents * settings.pointsPerCurrencyUnit) ~/ 100;
      if (originalBasePoints <= 0) return 0;
      final originalPoints = _mulRound(originalBasePoints, multiplier);
      if (originalPoints <= 0) return 0;

      final pointsToDeduct =
          (originalPoints * returnTotalCents) ~/ saleTotalCents;
      if (pointsToDeduct <= 0) return 0;

      final currentBalance = summary?.pointsBalance ?? 0;
      final actualDeduction =
          pointsToDeduct > currentBalance ? currentBalance : pointsToDeduct;
      if (actualDeduction <= 0) return 0;

      await _loyalty.redeemPoints(
        customerId: sale.customerId!,
        points: actualDeduction,
        reason: 'Points reversed for return #$returnId on sale #$saleId',
        referenceId: returnId,
        referenceType: 'sale_return',
      );

      return actualDeduction;
    } catch (e) {
      developer.log(
        'LoyaltyPointsService.reverseForReturn failed for return #$returnId: $e',
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
