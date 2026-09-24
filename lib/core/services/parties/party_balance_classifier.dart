import 'package:decimal/decimal.dart';

/// Phase 3.5.2 — single source of truth for classifying and aggregating
/// party (customer / supplier) running balances.
///
/// ## Why this exists
///
/// Before this service, the same classification logic was hand-rolled in
/// four separate widgets:
///
///   * `customer_hub_screen.dart`   — debtor / creditor totals
///   * `supplier_hub_screen.dart`   — payable / receivable totals
///   * `customer_profile_screen.dart` — single-party receivable / credit label
///   * `supplier_profile_screen.dart` — single-party payable / credit label
///
/// Each site re-implemented the same two rules:
///
///   1. *Interpret the sign* of `balanceCents` (the two sides disagree on
///      which sign means what — see [PartyKind] below).
///   2. *Sum the positive side and the |negative side| independently* so the
///      UI can show two cards (e.g. "total we owe" vs "total they owe").
///
/// Both rules are accounting invariants, not presentation. Duplicating them
/// in widgets means:
///
///   * The sign convention can drift if a developer edits one site and not
///     the others.
///   * There is no single regression test that locks the convention.
///   * Currency-aware aggregation (skipping parties on different currencies,
///     or grouping them) becomes painful.
///
/// This classifier centralises both rules and exposes an immutable
/// [PartyBalanceBreakdown] that the widgets just render.
///
/// ## Sign convention (GL-aligned)
///
/// The DB stores `balance_cents` for both customers and suppliers as a
/// signed integer. The convention matches the control accounts:
///
///   * **Customers** — account 1100 Accounts Receivable (asset / debit).
///     `balance_cents > 0` → customer owes us (we have a receivable).
///     `balance_cents < 0` → we owe the customer (advance / credit note).
///
///   * **Suppliers** — account 2000 Accounts Payable (liability / credit).
///     `balance_cents > 0` → we owe the supplier.
///     `balance_cents < 0` → the supplier owes us (advance / debit note).
///
/// The classifier translates the raw sign into neutral accounting buckets
/// (`receivableCents` = "something owed *to us*", `payableCents` =
/// "something owed *by us*") so the UI never touches the sign again.

enum PartyKind {
  /// Customer ledger — positive balance means receivable.
  customer,

  /// Supplier ledger — positive balance means payable.
  supplier,
}

/// Result of classifying a list of party balances.
///
/// All amounts are in minor units (cents / fils / ...). All non-receivable
/// / non-payable amounts are reported as positive magnitudes so callers do
/// not have to re-negate.
class PartyBalanceBreakdown {
  /// Sum of amounts *owed to us* (positive side for customers, negative
  /// side for suppliers). Always `>= 0`.
  final int receivableCents;

  /// Sum of amounts *owed by us* (negative side for customers, positive
  /// side for suppliers). Always `>= 0`.
  final int payableCents;

  /// Number of parties with any non-zero balance.
  final int nonZeroCount;

  /// Number of parties whose balance is exactly zero.
  final int settledCount;

  /// Total count of parties considered (`= nonZeroCount + settledCount`).
  final int totalCount;

  const PartyBalanceBreakdown({
    required this.receivableCents,
    required this.payableCents,
    required this.nonZeroCount,
    required this.settledCount,
    required this.totalCount,
  });

  /// Net position from *our* point of view:
  /// positive → net receivable, negative → net payable.
  int get netCents => receivableCents - payableCents;

  /// Convenience empty instance for `initialState` in blocs.
  static const empty = PartyBalanceBreakdown(
    receivableCents: 0,
    payableCents: 0,
    nonZeroCount: 0,
    settledCount: 0,
    totalCount: 0,
  );
}

/// How a single party's balance should be labelled in the UI.
enum PartyBalanceStatus {
  /// Balance is exactly zero — "settled".
  settled,

  /// Something is owed *to us* (asset side).
  receivable,

  /// Something is owed *by us* (liability side).
  payable,
}

class PartyBalanceClassifier {
  const PartyBalanceClassifier();

  /// Classify a single party balance into a UI-facing status.
  ///
  /// [balanceCents] is the raw signed ledger value. [kind] selects which
  /// sign convention to apply.
  PartyBalanceStatus statusOf(int balanceCents, PartyKind kind) {
    if (balanceCents == 0) return PartyBalanceStatus.settled;
    final positiveMeansOwedToUs = kind == PartyKind.customer;
    final isReceivable = positiveMeansOwedToUs
        ? balanceCents > 0
        : balanceCents < 0;
    return isReceivable
        ? PartyBalanceStatus.receivable
        : PartyBalanceStatus.payable;
  }

  /// Classify and aggregate a list of raw signed balances.
  ///
  /// Pass every party's `balanceCents` and the classifier takes care of
  /// bucketising them into [PartyBalanceBreakdown.receivableCents] and
  /// [PartyBalanceBreakdown.payableCents]. Currency conversion is out of
  /// scope — callers should pre-filter by currency or pre-normalise the
  /// values to a single base currency before calling.
  PartyBalanceBreakdown classify(Iterable<int> balances, PartyKind kind) {
    int receivable = 0;
    int payable = 0;
    int nonZero = 0;
    int settled = 0;
    int total = 0;
    for (final raw in balances) {
      total++;
      if (raw == 0) {
        settled++;
        continue;
      }
      nonZero++;
      switch (statusOf(raw, kind)) {
        case PartyBalanceStatus.receivable:
          receivable += raw.abs();
          break;
        case PartyBalanceStatus.payable:
          payable += raw.abs();
          break;
        case PartyBalanceStatus.settled:
          // Unreachable: raw != 0 here.
          break;
      }
    }
    return PartyBalanceBreakdown(
      receivableCents: receivable,
      payableCents: payable,
      nonZeroCount: nonZero,
      settledCount: settled,
      totalCount: total,
    );
  }

  /// Project a party's current balance forward by an in-flight invoice
  /// + the amount paid at the till. Returns the signed balance that
  /// would result *after* the invoice is posted.
  ///
  /// Phase 3.5.6 — single source of truth for "what will the customer
  /// owe after I save this sale?" / "what will I owe the supplier
  /// after I save this purchase?". Previously this `+ invoice − paid`
  /// formula was hand-rolled inside `_CustomerBalanceInfo` and a few
  /// purchase widgets, which meant any future change to the sign
  /// convention (e.g. adding cheque fees, FX revaluation, advances
  /// applied) had to be repeated in every widget. Now the widgets just
  /// call this method and render the result.
  ///
  /// **Sign convention** matches [statusOf]: positive return value means
  /// the party owes us (asset side); negative means we owe the party.
  /// The invoice always *increases* what the party owes us — that is,
  /// for both sides of the ledger an unpaid invoice flows in the
  /// direction of the control account:
  ///
  ///   * **Customer**: sale + invoice (debit AR), payment received
  ///     (credit AR). So `projected = current + invoiceTotal − paid`.
  ///   * **Supplier**: purchase + invoice (credit AP), payment made
  ///     (debit AP). With the supplier sign convention (positive =
  ///     payable), the same formula holds: `projected = current +
  ///     invoiceTotal − paid` where positive means "we owe them more".
  ///
  /// The caller passes [kind] purely for documentation symmetry; the
  /// formula itself is identical for both. The classifier's
  /// [statusOf] handles the kind-dependent labelling downstream.
  int project({
    required int currentBalanceCents,
    required int invoiceTotalCents,
    required int paidAmountCents,
    PartyKind kind = PartyKind.customer,
  }) {
    // Invariant: paid cannot exceed invoice + current debt at the UI
    // layer. We do not enforce that here — the bloc owns that rule.
    return currentBalanceCents + invoiceTotalCents - paidAmountCents;
  }

  /// Convenience overload that accepts Drift `Decimal` balances (the raw
  /// column type on `Customers`/`Suppliers`). Fractional cents are
  /// truncated toward zero — the underlying column is integer-backed so
  /// this is lossless in practice.
  PartyBalanceBreakdown classifyDecimal(
    Iterable<Decimal> balances,
    PartyKind kind,
  ) {
    return classify(balances.map((d) => d.toBigInt().toInt()), kind);
  }
}
