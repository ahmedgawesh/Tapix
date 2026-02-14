// Balance Sheet Diagnostic Service
//
// Provides intelligent analysis of balance sheet imbalances:
// - Classifies the root cause of imbalance
// - Generates user-friendly hint messages
// - Suggests corrective actions per cause
// - Determines severity (warning vs hard error)
//
// This is a pure logic service with no dependencies on UI or database.

enum DiagnosticSeverity { info, warning, error }

enum ImbalanceCause {
  balanced,
  missingCapitalInjection,
  lossExceedsEquity,
  openingBalancesNotPosted,
  periodNotClosed,
  suspectedMisposting,
  unknownDiscrepancy,
}

class BalanceSheetDiagnostic {
  final ImbalanceCause cause;
  final DiagnosticSeverity severity;

  /// Translation key for the hint title
  final String hintTitleKey;

  /// Translation key for the hint description
  final String hintDescriptionKey;

  /// Translation key for the suggested fix action
  final String suggestedActionKey;

  /// Whether the system can auto-fix this (e.g. capital injection journal entry)
  final bool canAutoFix;

  /// The auto-fix type identifier (used by UI to trigger the right action)
  final String? autoFixType;

  const BalanceSheetDiagnostic({
    required this.cause,
    required this.severity,
    required this.hintTitleKey,
    required this.hintDescriptionKey,
    required this.suggestedActionKey,
    this.canAutoFix = false,
    this.autoFixType,
  });
}

class BalanceSheetDiagnosticResult {
  final bool isBalanced;
  final int differenceCents;
  final List<BalanceSheetDiagnostic> diagnostics;

  const BalanceSheetDiagnosticResult({
    required this.isBalanced,
    required this.differenceCents,
    required this.diagnostics,
  });
}

class BalanceSheetDiagnosticService {
  const BalanceSheetDiagnosticService();

  /// Analyze balance sheet figures and return diagnostics
  ///
  /// [totalAssets] - Sum of all asset accounts (debit natural)
  /// [totalLiabilities] - Sum of all liability accounts (credit natural)
  /// [ownerCapital] - Sum of equity accounts
  /// [netIncome] - Revenue minus Expenses
  /// [totalEquity] - ownerCapital + netIncome
  /// [differenceCents] - totalAssets - (totalLiabilities + totalEquity)
  BalanceSheetDiagnosticResult analyze({
    required int totalAssets,
    required int totalLiabilities,
    required int ownerCapital,
    required int netIncome,
    required int totalEquity,
    required int differenceCents,
    required bool hasOpenPeriod,
  }) {
    final isBalanced = differenceCents == 0;

    if (isBalanced) {
      return const BalanceSheetDiagnosticResult(
        isBalanced: true,
        differenceCents: 0,
        diagnostics: [],
      );
    }

    final diagnostics = <BalanceSheetDiagnostic>[];

    // ── Rule 1: Missing Capital Injection ──
    // Assets > L+E and equity is zero or very small relative to assets
    // This means the business has assets but no recorded capital
    if (differenceCents > 0 && ownerCapital == 0 && totalAssets > 0) {
      diagnostics.add(const BalanceSheetDiagnostic(
        cause: ImbalanceCause.missingCapitalInjection,
        severity: DiagnosticSeverity.warning,
        hintTitleKey: 'reports.diag_missing_capital_title',
        hintDescriptionKey: 'reports.diag_missing_capital_desc',
        suggestedActionKey: 'reports.diag_missing_capital_action',
        canAutoFix: false,
      ));
    }

    // ── Rule 2: Loss Exceeds Equity ──
    // Net income is negative (loss) and its magnitude exceeds owner capital
    // This creates negative equity which is valid but concerning
    if (netIncome < 0 && ownerCapital + netIncome < 0) {
      diagnostics.add(const BalanceSheetDiagnostic(
        cause: ImbalanceCause.lossExceedsEquity,
        severity: DiagnosticSeverity.warning,
        hintTitleKey: 'reports.diag_loss_exceeds_equity_title',
        hintDescriptionKey: 'reports.diag_loss_exceeds_equity_desc',
        suggestedActionKey: 'reports.diag_loss_exceeds_equity_action',
        canAutoFix: false,
      ));
    }

    // ── Rule 3: Opening Balances Not Posted ──
    // Assets exist but no equity and no liabilities — likely opening balances missing
    if (differenceCents > 0 &&
        totalAssets > 0 &&
        ownerCapital == 0 &&
        totalLiabilities == 0 &&
        netIncome == 0) {
      diagnostics.add(const BalanceSheetDiagnostic(
        cause: ImbalanceCause.openingBalancesNotPosted,
        severity: DiagnosticSeverity.error,
        hintTitleKey: 'reports.diag_opening_balance_title',
        hintDescriptionKey: 'reports.diag_opening_balance_desc',
        suggestedActionKey: 'reports.diag_opening_balance_action',
        canAutoFix: false,
      ));
    }

    // ── Rule 4: Period Not Closed ──
    // If there's an open period and net income is non-zero
    if (hasOpenPeriod && netIncome != 0) {
      diagnostics.add(const BalanceSheetDiagnostic(
        cause: ImbalanceCause.periodNotClosed,
        severity: DiagnosticSeverity.info,
        hintTitleKey: 'reports.diag_period_not_closed_title',
        hintDescriptionKey: 'reports.diag_period_not_closed_desc',
        suggestedActionKey: 'reports.diag_period_not_closed_action',
        canAutoFix: false,
      ));
    }

    // ── Rule 5: Suspected Misposting ──
    // Difference is non-zero but doesn't match any known pattern above
    // Could be wrong account type used in a journal entry
    if (differenceCents != 0 && diagnostics.isEmpty) {
      diagnostics.add(const BalanceSheetDiagnostic(
        cause: ImbalanceCause.suspectedMisposting,
        severity: DiagnosticSeverity.error,
        hintTitleKey: 'reports.diag_misposting_title',
        hintDescriptionKey: 'reports.diag_misposting_desc',
        suggestedActionKey: 'reports.diag_misposting_action',
        canAutoFix: false,
      ));
    }

    // ── Rule 6: Unknown Discrepancy (fallback) ──
    // If we still have a difference and only info-level diagnostics
    if (differenceCents != 0 &&
        diagnostics.every((d) => d.severity == DiagnosticSeverity.info)) {
      diagnostics.add(const BalanceSheetDiagnostic(
        cause: ImbalanceCause.unknownDiscrepancy,
        severity: DiagnosticSeverity.warning,
        hintTitleKey: 'reports.diag_unknown_title',
        hintDescriptionKey: 'reports.diag_unknown_desc',
        suggestedActionKey: 'reports.diag_unknown_action',
        canAutoFix: false,
      ));
    }

    return BalanceSheetDiagnosticResult(
      isBalanced: false,
      differenceCents: differenceCents,
      diagnostics: diagnostics,
    );
  }
}
