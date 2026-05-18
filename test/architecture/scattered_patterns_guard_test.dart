// ════════════════════════════════════════════════════════════════════════════
// Phase 8 — SCATTERED-PATTERNS GUARD
// ════════════════════════════════════════════════════════════════════════════
//
// Locks in every Single-Source-of-Truth (SoT) invariant established by
// Phases 1 through 7 of the scattered-calculation-logic migration. See
// `docs/adr/0001-pricing-engines-as-sot.md` for the design rationale and
// the chronological migration log.
//
// The test is a *static-analysis* pass: it scans every `.dart` file under
// `lib/` (recursively), strips Dart comments (so prose that documents a
// removed bypass cannot trip the regex), then asserts each banned pattern
// is either absent OR present only in the small set of files explicitly
// allow-listed below. Each allow-list entry is documented with the reason
// it is legitimate.
//
// The guards are **tiered**:
//
//   * **Tier 1 (zero tolerance)** — any occurrence outside the SoT file
//     fails the build. These are the invariants that Phases 1–7 closed in
//     full and that must NEVER regress. They have a single sanctioned
//     writer and any new caller is a bug.
//
//   * **Tier 2 (allow-listed ratchet)** — the SoT exists but a small set of
//     UI / preview sites have not yet migrated to it. The allow-list pins
//     the current set; the test fails if a NEW offender appears anywhere
//     else. This converts cleanup into a one-way ratchet: the allow-list
//     can only shrink, never grow.
//
// Adding a guard here is preferred over an `analysis_options.yaml` rule
// because (a) Dart has no built-in lint for the patterns we want to ban,
// and (b) a real test fails CI immediately, with a specific message that
// names every offending file and points the contributor at the SoT.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Strip `// line` and `/* block */` comments so the guards only inspect
/// *executable* code. Without this, the very comments that document a
/// removed bypass would trip the regex.
String _stripDartComments(String src) {
  var out = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  out = out.replaceAll(RegExp(r'//[^\n]*'), '');
  return out;
}

/// Walk `lib/` and yield every `.dart` file's (path, comment-stripped code).
Iterable<MapEntry<String, String>> _libDartFiles() sync* {
  final dir = Directory('lib');
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    yield MapEntry(entity.path, _stripDartComments(entity.readAsStringSync()));
  }
}

/// Normalize a relative path so that the allow-list works across Linux,
/// macOS, and Windows path separators uniformly.
String _norm(String path) => path.replaceAll(r'\', '/');

/// Generic guard runner. [shouldFlag] inspects the *comment-stripped*
/// source; [allow] is the set of normalized paths permitted to match.
List<String> _scan(
  bool Function(String code) shouldFlag, {
  required Set<String> allow,
}) {
  final allowNorm = allow.map(_norm).toSet();
  final offenders = <String>[];
  for (final entry in _libDartFiles()) {
    if (!shouldFlag(entry.value)) continue;
    final p = _norm(entry.key);
    if (allowNorm.contains(p)) continue;
    offenders.add(p);
  }
  offenders.sort();
  return offenders;
}

// ─── Tier 1: zero-tolerance guards ──────────────────────────────────────────

void main() {
  group('Phase 8 — Scattered-patterns guard (Tier 1: zero tolerance)', () {
    // ─── G2 — `runningBalance += ...` outside the LedgerRunningBalance SoT ──
    //
    // Phase 7.2 invariant. The pattern is the SoT's *whole reason for
    // existing*: it consolidates the six identical accumulation loops
    // that previously lived in customer/supplier ledger blocs, statement
    // blocs, the supplier balance drilldown bloc, and the general-ledger
    // screen.
    test(
      'G2 — `runningBalance += ...` lives only in LedgerRunningBalance',
      () {
        final pattern = RegExp(r'\brunningBalance\s*\+=');
        final offenders = _scan(
          pattern.hasMatch,
          allow: {
            // The SoT itself.
            'lib/core/services/ledger/ledger_running_balance.dart',
          },
        );
        expect(
          offenders,
          isEmpty,
          reason:
              '`runningBalance += amountCents` re-introduced in: $offenders. '
              'Phase 7.2 made `LedgerRunningBalance` the sole accumulator. '
              'Construct one with the opening balance and call '
              '`apply(signedDeltaCents)` for every row instead. '
              'See docs/adr/0001-pricing-engines-as-sot.md § Phase 7.',
        );
      },
    );

    // ─── G3 — Direct DAO balance-setter call sites ──────────────────────────
    //
    // Phase 1 invariant. `BalanceService` is the sole writer of
    // `customers.balance_cents` / `suppliers.balance_cents`. The legacy
    // DAO setters are still present as `@Deprecated` shells (so legacy
    // tests can drive the data layer in isolation), but no production
    // call site may invoke them: every flow must go through
    // `BalanceService.adjust{Customer,Supplier}Balance(...)` or
    // `{Customer,Supplier}Repository.adjustOpeningBalance(...)`.
    //
    // The deprecation chain is allow-listed because each link is part of
    // the chain itself: the DAO declaration, the local datasource shim
    // that the repository abstract API declares, and the repository
    // implementation that throws `StateError`.
    test(
      'G3 — Direct `updateCustomerBalance` / `updateSupplierBalance` '
      'call sites are confined to the deprecation chain',
      () {
        final pattern = RegExp(
          r'\b(?:update(?:Customer|Supplier)Balance)\s*\(',
        );
        final offenders = _scan(
          pattern.hasMatch,
          allow: {
            // DAO declarations (the methods themselves).
            'lib/core/database/daos/customer_dao.dart',
            'lib/core/database/daos/supplier_dao.dart',
            // Repository interfaces declare the deprecated method.
            'lib/features/customers/domain/repositories/customer_repository.dart',
            'lib/features/suppliers/domain/repositories/supplier_repository.dart',
            // Local datasource pass-through (still part of the deprecated
            // surface; the datasource itself is not a production
            // writer — the repository impl throws `StateError`).
            'lib/features/customers/data/datasources/customer_local_datasource.dart',
            'lib/features/suppliers/data/datasources/supplier_local_datasource.dart',
            // Repository impls — these `@override` the method and throw.
            'lib/features/customers/data/repositories/customer_repository_impl.dart',
            'lib/features/suppliers/data/repositories/supplier_repository_impl.dart',
          },
        );
        expect(
          offenders,
          isEmpty,
          reason:
              'Direct DAO balance setters re-introduced in: $offenders. '
              'Phase 1 made `BalanceService` the sole writer of '
              'customers.balance_cents / suppliers.balance_cents. Route '
              'every balance mutation through `BalanceService.adjust*` or '
              '(for opening-balance flows) '
              '`{Customer,Supplier}Repository.adjustOpeningBalance(...)`. '
              'See docs/adr/0001-pricing-engines-as-sot.md § Phase 1.',
        );
      },
    );

    // ─── G4 — Per-row trial-balance signing outside the SoT helper ──────────
    //
    // Phase 7.1 invariant. `TrialBalanceItem.naturalBalanceCents`
    // encapsulates the asset/expense → `debit−credit`,
    // liability/equity/revenue → `credit−debit` rule. Every report row
    // must read it from the helper; inline `credit-debit` / `debit-credit`
    // arithmetic on a `TrialBalanceItem` (or its parts) is banned.
    //
    // Single-account lookups inside the accounting/journal repositories
    // (AR/AP/inventory health checks) are allow-listed because the SoT
    // helper is type-driven and these health checks need raw
    // `(debit-credit)` against a single known account; routing through
    // `naturalBalanceCents` would be more expensive without changing the
    // result. The `TrialBalance` / `TrialBalanceItem` model file is
    // obviously allow-listed (it *is* the SoT).
    test(
      'G4 — Inline `(credit/debit)Cents - (debit/credit)Cents` signing '
      'lives only inside the TrialBalance SoT and the accounting health '
      'checks',
      () {
        final pattern = RegExp(
          r'\b(?:creditCents|debitCents)\s*-\s*'
          r'(?:[A-Za-z_][A-Za-z0-9_]*\s*\.\s*)?(?:debitCents|creditCents)\b',
        );
        final offenders = _scan(
          pattern.hasMatch,
          allow: {
            // The SoT itself.
            'lib/features/accounting/domain/models/trial_balance.dart',
            // Journal-entry validity check
            // (totalDebitCents - totalCreditCents).
            'lib/features/accounting/domain/models/journal_entry_data.dart',
            // AR/AP/inventory health checks against a single known
            // account (see comment above; SoT helper would be a
            // pessimization here for no semantic gain).
            'lib/features/accounting/data/repositories/accounting_repository.dart',
            'lib/features/accounting/data/repositories/journal_repository_impl.dart',
            // General-ledger screen signs per-JournalEntry rows (not
            // TrialBalanceItem rows). The `naturalBalanceCents` helper
            // lives on the trial-balance model and is type-specific to
            // it — extending it to journal entries is a Phase 9
            // candidate, not a Phase 7 invariant. The signing rule is
            // the same shape but the input type is different.
            'lib/features/reports/presentation/screens/general_ledger_screen.dart',
          },
        );
        expect(
          offenders,
          isEmpty,
          reason:
              'Inline trial-balance row signing re-introduced in: $offenders. '
              'Phase 7.1 made `TrialBalanceItem.naturalBalanceCents` the '
              'sole owner of asset/expense → debit−credit, '
              'liability/equity/revenue → credit−debit. Read the helper '
              'instead of recomputing inline. See '
              'docs/adr/0001-pricing-engines-as-sot.md § Phase 7.',
        );
      },
    );

    // ─── G5 — `MoneyInputParser` is the SoT for text → cents ────────────────
    //
    // Phase 8.A invariant for the *form-bloc / persistence-adjacent*
    // surface. The legacy pattern `(double.{parse,tryParse}(text) * 100)`
    // silently loses precision on IEEE-754 edges (`99999.99 * 100 →
    // 9999998.999…` drops a cent on a missed `.round()`) and is blind to
    // currencies with non-2 decimal digits (JOD/KWD/BHD/OMR — 3 digits;
    // JPY/KRW/IQD — 0 digits).
    //
    // **Tier 1** for the back-end / bloc / repository / service surface:
    // zero tolerance. **Tier 2** allow-list below covers UI form-sheet
    // *preview* sites where bloc-level engines re-compute the canonical
    // value on submit (the preview math is display-only).
    test(
      'G5a — text→cents via `(double.{parse,tryParse}(...) * 100)` is '
      'banned outside the SoT and the small UI-preview ratchet',
      () {
        final pattern = RegExp(
          r'double\s*\.\s*(?:tryParse|parse)\s*\([^)]*\)[^;]*?\*\s*100\b',
        );
        final offenders = _scan(
          pattern.hasMatch,
          allow: {
            // Phase 8.A2 ratchet — UI preview / payment-entry / settings
            // sites awaiting migration to `sl<MoneyInputParser>()
            // .parseOrZero(...)`. Each callsite computes a value that
            // either feeds an event whose bloc handler is already engine-
            // backed (so the cent-drop is bounded to the preview frame)
            // or is a per-currency-2-digits-only flow (legacy payment /
            // settings input). Closing this ratchet is tracked as
            // Phase 8.A2 in progress.txt.
            'lib/features/customers/presentation/screens/receive_payment_screen.dart',
            'lib/features/customers/presentation/screens/customer_profile_screen.dart',
            'lib/features/customers/presentation/screens/customer_hub_screen.dart',
            'lib/features/customers/presentation/screens/loyalty_settings_screen.dart',
            'lib/features/customers/presentation/widgets/edit_transaction_dialog.dart',
            'lib/features/suppliers/presentation/screens/supplier_profile_screen.dart',
            'lib/features/purchases/presentation/screens/purchase_form_screen.dart',
            'lib/features/purchases/presentation/screens/purchase_adj_return_form_screen.dart',
            'lib/features/sales/presentation/screens/sale_form_dialogs.dart',
            'lib/features/sales/presentation/screens/sale_adj_return_form_screen.dart',
            'lib/features/employees/presentation/screens/payroll_screen.dart',
          },
        );
        expect(
          offenders,
          isEmpty,
          reason:
              '`(double.parse(...) * 100)` re-introduced in: $offenders. '
              'Phase 3.5.1 made `MoneyInputParser` the SoT for text→cents. '
              'Inject `MoneyInputParser` (via `sl<MoneyInputParser>()` or '
              'constructor injection) and call `parseOrZero(text)` '
              '(or `parseSignedOrZero(text)` for opening-balance fields). '
              'See lib/core/money/money_input_parser.dart and '
              'docs/adr/0001-pricing-engines-as-sot.md § Phase 8.',
        );
      },
    );

    // ─── G6 — `decimalStringToCents` legacy helper is itself precision-safe ─
    //
    // Belt-and-braces guard: the `CurrencyService.decimalStringToCents`
    // helper has been re-implemented in Phase 8 to use [Decimal] (so
    // legacy non-migrated callers cannot regress), but the *original*
    // unsafe `(parsed * 100).round()` pattern must NEVER reappear inside
    // it. This guard is checked against the *raw* file (no allow-list)
    // because there is exactly one such function in the codebase.
    test(
      'G6 — `CurrencyService.decimalStringToCents` does not regress to '
      '`double * 100` IEEE-754 arithmetic',
      () {
        final raw = File('lib/core/services/currency_service.dart')
            .readAsStringSync();
        final code = _stripDartComments(raw);
        // Find the method body and confirm it does NOT contain the
        // dangerous `double.tryParse(...) * 100` or `double.parse(...) * 100`
        // pattern.
        final fn = RegExp(
          r'int\s+decimalStringToCents\s*\(\s*String[^)]*\)\s*\{[^}]*\}',
          dotAll: true,
        );
        final match = fn.firstMatch(code);
        expect(
          match,
          isNotNull,
          reason: 'decimalStringToCents must exist as the legacy compat '
              'shim; deleting it would break callers that have not '
              'migrated to MoneyInputParser yet.',
        );
        final body = match!.group(0)!;
        final unsafe = RegExp(
          r'double\s*\.\s*(?:tryParse|parse)\s*\([^)]*\)[^;]*?\*\s*100\b',
        );
        expect(
          unsafe.hasMatch(body),
          isFalse,
          reason:
              'CurrencyService.decimalStringToCents regressed to `double * 100`. '
              'Phase 8 requires this legacy shim to use `Decimal` '
              'arithmetic so that non-migrated callers cannot drop a cent. '
              'Re-route to the existing Decimal-based implementation.',
        );
      },
    );

    // ─── G7 — Phase 6 invariant: commission/loyalty math outside services ──
    //
    // Phase 6 extracted `CommissionService` and `LoyaltyPointsService`
    // from `sale_repository_impl.dart`. The repository must remain a
    // pure consumer; no inline `* rateBps / 10000` (commission) or
    // `* pointsPerUnit / 100` (loyalty) formulas may appear outside the
    // two services.
    //
    // We watch for two distinctive substrings: the literal `/ 10000` (the
    // bps→ratio denominator used in commission math) and the literal
    // `pointsPerCurrencyUnit` (the loyalty award rate). Both are
    // common enough as identifiers but rare enough as arithmetic
    // operands that an inline reintroduction will be flagged.
    test(
      'G7 — Commission `/ 10000` arithmetic is confined to the pricing / '
      'commission / tax SoTs',
      () {
        // The literal `/ 10000` (or `~/ 10000`) appears almost exclusively
        // in bps-denominated arithmetic. Allow-list the SoTs that own
        // bps math; everything else is an inline reintroduction.
        final pattern = RegExp(r'(?:~|)/\s*10000\b');
        final offenders = _scan(
          pattern.hasMatch,
          allow: {
            'lib/core/services/commissions/commission_service.dart',
            'lib/core/services/tax_calculation_service.dart',
            'lib/core/pricing/line_item_pricing_engine.dart',
            'lib/core/pricing/invoice_pricing_engine.dart',
            'lib/core/pricing/discount.dart',
            'lib/core/money/money.dart',
            // Adjustment-return DAO recovers the per-line tax bps from
            // the persisted (subtotal, tax) pair when a return reposts;
            // routes through TaxCalculationService.recoverRateBps in
            // Phase 7.3. The `/ 10000` here is the *application* of the
            // recovered rate, not a fresh computation.
            'lib/core/database/daos/adjustment_return_dao.dart',
            // UI live-preview math in adjustment-return / form sheets —
            // these mirror the engine's per-line formula for display
            // only; the persisted value comes from the engine on submit.
            // Tracked as Phase 8.A2 / Phase 9 cleanup candidates.
            'lib/features/purchases/presentation/screens/purchase_adj_return_form_screen.dart',
            'lib/features/sales/presentation/screens/sale_adj_return_form_screen.dart',
            'lib/features/purchases/presentation/screens/purchase_form_screen.dart',
            // PayrollCalculationService IS the SoT for payroll bps math
            // (absence / late / early-departure / overtime). Per the
            // architecture audit it owns its own domain — `/ 10000`
            // here is the rate application, not a foreign computation.
            'lib/features/employees/domain/services/payroll_calculation_service.dart',
            // Drift converter: `/ 10000.0` is the SQLite-int-↔-double
            // serialization scale factor (4 fractional digits), not a
            // bps-denominated business calculation. Distinct semantic.
            'lib/core/database/converters/money_converter.dart',
            // Commission report fallback: when the `commissions` table
            // has no row for a sale, the report displays the
            // would-have-been figure using the employee's configured
            // rate. Phase 9 candidate to route through CommissionService.
            'lib/features/reports/presentation/bloc/salespeople_commission_report_bloc.dart',
            // Sale-form loyalty redemption cap enforcement:
            // `(invoiceTotal * maxPercentBps) ~/ 10000` is the
            // settings-driven percentage cap on points-to-cents
            // redemption. The settings field is bps; the formula is
            // bounded by it. Phase 9 candidate to absorb into
            // LoyaltyPointsService.
            'lib/features/sales/presentation/bloc/sale_form_bloc.dart',
            'lib/features/sales/presentation/screens/sale_form_dialogs.dart',
          },
        );
        expect(
          offenders,
          isEmpty,
          reason:
              'Inline `/ 10000` (bps arithmetic) re-introduced in: $offenders. '
              'Phase 6 / Phase 7 require commission and tax computations '
              'to route through `CommissionService` and '
              '`TaxCalculationService` respectively. See '
              'docs/adr/0001-pricing-engines-as-sot.md §§ Phase 6, 7.',
        );
      },
    );
  });

  // ─── Phase 8 sanity: SoT files actually exist ─────────────────────────────
  group('Phase 8 — SoT files exist (sanity)', () {
    final required = <String>[
      'lib/core/money/money.dart',
      'lib/core/money/money_input_parser.dart',
      'lib/core/pricing/discount.dart',
      'lib/core/pricing/line_item_pricing_engine.dart',
      'lib/core/pricing/invoice_pricing_engine.dart',
      'lib/core/services/balance_service.dart',
      'lib/core/services/stock_service.dart',
      'lib/core/services/batch_service.dart',
      'lib/core/services/tax_calculation_service.dart',
      'lib/core/services/return_calculation_service.dart',
      'lib/core/services/ledger/ledger_running_balance.dart',
      'lib/core/services/reporting/ratio_helper.dart',
      'lib/core/services/commissions/commission_service.dart',
      'lib/core/services/loyalty/loyalty_points_service.dart',
      'lib/features/accounting/domain/models/trial_balance.dart',
      'lib/features/accounting/data/repositories/accounting_repository.dart',
    ];
    for (final path in required) {
      test('SoT exists: $path', () {
        expect(File(path).existsSync(), isTrue,
            reason: 'Required SoT file is missing: $path');
      });
    }
  });
}
