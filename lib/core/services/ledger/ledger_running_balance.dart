/// Phase 7 — Single source of truth for running-balance accumulation across
/// every ledger / statement / general-ledger report.
///
/// Before Phase 7, the pattern `runningBalance += amountCents` was duplicated
/// across 6+ blocs / screens (customer ledger, supplier ledger, customer
/// statement, supplier statement, supplier balance drilldown, general
/// ledger). Each copy was correct on its own, but maintaining six identical
/// loops invites drift the next time someone adds an audit trail or a
/// bounds-assertion.
///
/// This helper is intentionally tiny — its value is the *contract*, not the
/// arithmetic:
///   - Opening balance is set exactly once via the constructor.
///   - Every mutation goes through `apply(signedDeltaCents)`.
///   - `apply` returns the **post-mutation** balance, which is the value the
///     row should snapshot.
///
/// The helper carries no rounding — inputs are already signed `int` cents.
/// It performs no allocation; it is a thin int accumulator so it can be used
/// freely inside hot ledger loops.
///
/// Usage:
/// ```dart
/// final running = LedgerRunningBalance(openingBalanceCents);
/// for (final tx in transactions) {
///   final post = running.apply(tx.signedAmountCents);
///   rows.add(LedgerRow(..., runningBalanceCents: post));
/// }
/// final closing = running.current;
/// ```
class LedgerRunningBalance {
  int _balance;

  LedgerRunningBalance(int openingBalanceCents) : _balance = openingBalanceCents;

  /// Apply a signed delta (positive = debit-side / charge, negative =
  /// credit-side / payment, depending on caller's sign convention) and
  /// return the new balance.
  int apply(int signedDeltaCents) {
    _balance += signedDeltaCents;
    return _balance;
  }

  /// Current (latest) balance.
  int get current => _balance;
}
