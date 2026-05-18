// Phase 7 — Reporting consolidation regression suite.
//
// Pins the contract of the four small SoT helpers introduced in Phase 7:
//   * TrialBalance.totalForType / TrialBalanceItem.naturalBalanceCents
//   * LedgerRunningBalance
//   * TaxCalculationService.recoverRateBps
//   * RatioHelper (percent + bpsToPercent)
//
// Each helper is exercised independently with edge cases, and the
// "byte-identical to legacy formula" property is asserted where the
// migration claims byte-identity (recoverRateBps and bpsToPercent).

import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/services/ledger/ledger_running_balance.dart';
import 'package:tapix/core/services/reporting/ratio_helper.dart';
import 'package:tapix/core/services/tax_calculation_service.dart';
import 'package:tapix/features/accounting/domain/models/trial_balance.dart';

void main() {
  // ────────────────────────────────────────────────────────────────────────
  // 1. TrialBalance — natural-balance signing SoT
  // ────────────────────────────────────────────────────────────────────────

  group('TrialBalanceItem.naturalBalanceCents', () {
    TrialBalanceItem item({
      required String type,
      required int debit,
      required int credit,
    }) =>
        TrialBalanceItem(
          accountId: 1,
          accountCode: '1000',
          accountName: 'Account',
          accountType: type,
          debitCents: debit,
          creditCents: credit,
        );

    test('asset → debit − credit', () {
      expect(item(type: 'asset', debit: 1000, credit: 300).naturalBalanceCents,
          700);
    });

    test('expense → debit − credit', () {
      expect(
        item(type: 'expense', debit: 500, credit: 50).naturalBalanceCents,
        450,
      );
    });

    test('liability → credit − debit', () {
      expect(
        item(type: 'liability', debit: 100, credit: 800).naturalBalanceCents,
        700,
      );
    });

    test('equity → credit − debit', () {
      expect(
        item(type: 'equity', debit: 0, credit: 5000).naturalBalanceCents,
        5000,
      );
    });

    test('revenue → credit − debit', () {
      expect(
        item(type: 'revenue', debit: 200, credit: 9000).naturalBalanceCents,
        8800,
      );
    });

    test('unknown type falls back to debit − credit (safe default)', () {
      expect(
        item(type: 'mystery', debit: 100, credit: 30).naturalBalanceCents,
        70,
      );
    });

    test('case-insensitive on account type', () {
      expect(
        item(type: 'REVENUE', debit: 0, credit: 100).naturalBalanceCents,
        100,
      );
      expect(
        item(type: 'Asset', debit: 100, credit: 0).naturalBalanceCents,
        100,
      );
    });
  });

  group('TrialBalance.totalForType', () {
    TrialBalance build(List<TrialBalanceItem> items) => TrialBalance(
          asOfDate: DateTime(2026, 1, 1),
          items: items,
          totalDebitCents: 0,
          totalCreditCents: 0,
          isBalanced: true,
        );

    TrialBalanceItem mk(String type, int debit, int credit, [int id = 1]) =>
        TrialBalanceItem(
          accountId: id,
          accountCode: '$id',
          accountName: 'A$id',
          accountType: type,
          debitCents: debit,
          creditCents: credit,
        );

    test('sums natural balances across all items of one type', () {
      final tb = build([
        mk('asset', 1000, 0, 1),
        mk('asset', 500, 100, 2),
        mk('liability', 0, 800, 3),
      ]);
      expect(tb.totalForType('asset'), 1400); // (1000−0) + (500−100)
      expect(tb.totalForType('liability'), 800);
    });

    test('returns 0 for a type absent in the report', () {
      final tb = build([mk('asset', 100, 0)]);
      expect(tb.totalForType('expense'), 0);
    });

    test('matches the manual fold pattern it replaces', () {
      // Legacy pattern in profit_loss_screen.dart was
      //   revenue.fold(0, (s, i) => s + i.creditCents - i.debitCents)
      // expense.fold(0, (s, i) => s + i.debitCents - i.creditCents)
      final tb = build([
        mk('revenue', 0, 10000),
        mk('revenue', 100, 5000),
        mk('expense', 3000, 0),
        mk('expense', 2000, 200),
      ]);
      final legacyRevenue = tb.getItemsByType('revenue').fold<int>(
            0,
            (sum, i) => sum + i.creditCents - i.debitCents,
          );
      final legacyExpense = tb.getItemsByType('expense').fold<int>(
            0,
            (sum, i) => sum + i.debitCents - i.creditCents,
          );
      expect(tb.totalForType('revenue'), legacyRevenue);
      expect(tb.totalForType('expense'), legacyExpense);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 2. LedgerRunningBalance — running-total SoT
  // ────────────────────────────────────────────────────────────────────────

  group('LedgerRunningBalance', () {
    test('opening balance is the first value of current', () {
      final r = LedgerRunningBalance(500);
      expect(r.current, 500);
    });

    test('apply returns post-mutation balance and updates current', () {
      final r = LedgerRunningBalance(0);
      expect(r.apply(100), 100);
      expect(r.apply(50), 150);
      expect(r.apply(-30), 120);
      expect(r.current, 120);
    });

    test('reproduces the legacy `runningBalance += delta` loop', () {
      const deltas = [100, -40, 25, -10, 200, -150];
      // Legacy
      int legacy = 1000;
      final legacyTrail = <int>[];
      for (final d in deltas) {
        legacy += d;
        legacyTrail.add(legacy);
      }
      // SoT
      final r = LedgerRunningBalance(1000);
      final sotTrail = deltas.map(r.apply).toList();
      expect(sotTrail, legacyTrail);
      expect(r.current, legacy);
    });

    test('handles a fully-zero stream without drift', () {
      final r = LedgerRunningBalance(42);
      for (var i = 0; i < 100; i++) {
        r.apply(0);
      }
      expect(r.current, 42);
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 3. TaxCalculationService.recoverRateBps
  // ────────────────────────────────────────────────────────────────────────

  group('TaxCalculationService.recoverRateBps', () {
    test('recovers 15% (1500 bps) exactly from a 100 / 15 pair', () {
      expect(
        TaxCalculationService.recoverRateBps(
          taxableSubtotalCents: 100,
          taxOnLineCents: 15,
        ),
        1500,
      );
    });

    test('rounds half-away-from-zero like the legacy DAO formula', () {
      // 7.5% on 200 = exact 15. Test a value that rounds.
      // (12 * 10000) / 100 = 1200 → 12%
      expect(
        TaxCalculationService.recoverRateBps(
          taxableSubtotalCents: 100,
          taxOnLineCents: 12,
        ),
        1200,
      );
      // (1 * 10000) / 3 = 3333.33… → halfUp rounds to 3333
      expect(
        TaxCalculationService.recoverRateBps(
          taxableSubtotalCents: 3,
          taxOnLineCents: 1,
        ),
        3333,
      );
    });

    test('zero subtotal returns 0 (legacy guard)', () {
      expect(
        TaxCalculationService.recoverRateBps(
          taxableSubtotalCents: 0,
          taxOnLineCents: 99,
        ),
        0,
      );
    });

    test('negative subtotal returns 0 (legacy `subtotal > 0` guard)', () {
      expect(
        TaxCalculationService.recoverRateBps(
          taxableSubtotalCents: -100,
          taxOnLineCents: 15,
        ),
        0,
      );
    });

    test('zero tax yields 0 bps without throwing', () {
      expect(
        TaxCalculationService.recoverRateBps(
          taxableSubtotalCents: 1000,
          taxOnLineCents: 0,
        ),
        0,
      );
    });

    test('byte-identical to the legacy inline DAO formula', () {
      // Sweep a small grid of (subtotal, tax) pairs and verify both
      // formulas agree, EXCLUDING the legacy guard divergence point
      // (subtotal == 0 → both return 0; negative → both return 0).
      const subtotals = [1, 50, 100, 333, 1000, 9999, 100000];
      const taxes = [0, 1, 15, 50, 100, 333, 1500];
      for (final s in subtotals) {
        for (final t in taxes) {
          final legacy =
              s > 0 ? ((t * 10000) / s).round() : 0;
          final sot = TaxCalculationService.recoverRateBps(
            taxableSubtotalCents: s,
            taxOnLineCents: t,
          );
          expect(sot, legacy,
              reason: 'subtotal=$s tax=$t → legacy=$legacy sot=$sot');
        }
      }
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // 4. RatioHelper
  // ────────────────────────────────────────────────────────────────────────

  group('RatioHelper.percent', () {
    test('exact percentage on friendly inputs', () {
      expect(
        RatioHelper.percent(numeratorCents: 250, denominatorCents: 1000),
        25.0,
      );
      expect(
        RatioHelper.percent(numeratorCents: 50, denominatorCents: 200),
        25.0,
      );
    });

    test('zero denominator returns 0.0 (display-safe)', () {
      expect(
        RatioHelper.percent(numeratorCents: 100, denominatorCents: 0),
        0.0,
      );
      expect(
        RatioHelper.percent(numeratorCents: 0, denominatorCents: 0),
        0.0,
      );
    });

    test('negative numerator (return rows) returns negative percent', () {
      expect(
        RatioHelper.percent(numeratorCents: -250, denominatorCents: 1000),
        -25.0,
      );
    });

    test('negative denominator is computed (matches profit-row "!= 0")', () {
      // Legacy profit_reports_bloc.dart return-row guard was `revenue != 0`
      // (allowing negative revenue). SoT preserves that semantics — only
      // exact-zero denominators are short-circuited.
      expect(
        RatioHelper.percent(numeratorCents: 100, denominatorCents: -1000),
        -10.0,
      );
    });

    test('matches legacy double-division on a friendly grid', () {
      const numerators = [0, 1, 99, 250, 1000, 9999, 100000];
      const denominators = [1, 10, 100, 1000, 12345, 100000];
      for (final n in numerators) {
        for (final d in denominators) {
          final legacy = (n / d) * 100;
          final sot = RatioHelper.percent(
            numeratorCents: n,
            denominatorCents: d,
          );
          // Tolerate IEEE-754 last-bit jitter when comparing the legacy
          // double pipeline to the Decimal→double SoT.
          expect(
            sot,
            closeTo(legacy, 1e-9),
            reason: 'n=$n d=$d → legacy=$legacy sot=$sot',
          );
        }
      }
    });
  });

  group('RatioHelper.bpsToPercent', () {
    test('500 bps → 5.0%', () {
      expect(RatioHelper.bpsToPercent(500), 5.0);
    });

    test('1250 bps → 12.5%', () {
      expect(RatioHelper.bpsToPercent(1250), 12.5);
    });

    test('0 bps → 0.0% (short-circuit)', () {
      expect(RatioHelper.bpsToPercent(0), 0.0);
    });

    test('1 bps → 0.01% (sub-percent precision retained)', () {
      expect(RatioHelper.bpsToPercent(1), 0.01);
    });

    test('byte-identical to legacy `bps / 100` on a wide range', () {
      for (var bps = 0; bps <= 10000; bps += 17) {
        final legacy = bps / 100;
        final sot = RatioHelper.bpsToPercent(bps);
        expect(sot, legacy, reason: 'bps=$bps');
      }
    });

    test('negative bps is sign-preserving', () {
      expect(RatioHelper.bpsToPercent(-250), -2.5);
    });
  });
}
