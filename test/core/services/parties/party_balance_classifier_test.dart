import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/parties/party_balance_classifier.dart';

/// Phase 3.5.2 — locks the sign convention for customer & supplier
/// balances so the widgets that used to hand-roll this can never drift
/// apart again.
void main() {
  const c = PartyBalanceClassifier();

  group('statusOf — customer (AR, positive = owed to us)', () {
    test('zero → settled', () {
      expect(c.statusOf(0, PartyKind.customer), PartyBalanceStatus.settled);
    });
    test('positive → receivable (customer owes us)', () {
      expect(c.statusOf(500, PartyKind.customer), PartyBalanceStatus.receivable);
    });
    test('negative → payable (we owe customer / advance)', () {
      expect(c.statusOf(-500, PartyKind.customer), PartyBalanceStatus.payable);
    });
  });

  group('statusOf — supplier (AP, positive = we owe them)', () {
    test('zero → settled', () {
      expect(c.statusOf(0, PartyKind.supplier), PartyBalanceStatus.settled);
    });
    test('positive → payable (we owe supplier)', () {
      expect(c.statusOf(500, PartyKind.supplier), PartyBalanceStatus.payable);
    });
    test('negative → receivable (supplier advance / they owe us)', () {
      expect(c.statusOf(-500, PartyKind.supplier), PartyBalanceStatus.receivable);
    });
  });

  group('classify — customer bucket math', () {
    test('empty list → all zeros', () {
      final b = c.classify(const <int>[], PartyKind.customer);
      expect(b.receivableCents, 0);
      expect(b.payableCents, 0);
      expect(b.nonZeroCount, 0);
      expect(b.settledCount, 0);
      expect(b.totalCount, 0);
      expect(b.netCents, 0);
    });

    test('mixed balances split into receivable / payable buckets (abs values)', () {
      // Two customers owe us (500 + 300) and one is in credit (-200).
      final b = c.classify(const [500, 0, -200, 300], PartyKind.customer);
      expect(b.receivableCents, 800);
      expect(b.payableCents, 200);
      expect(b.nonZeroCount, 3);
      expect(b.settledCount, 1);
      expect(b.totalCount, 4);
      expect(b.netCents, 600);
    });
  });

  group('classify — supplier bucket math (signs reversed)', () {
    test('positive supplier balances land in payable; negatives in receivable', () {
      // Two suppliers we owe (1000 + 200), one that owes us (-150).
      final b = c.classify(const [1000, 200, -150], PartyKind.supplier);
      expect(b.payableCents, 1200);
      expect(b.receivableCents, 150);
      expect(b.nonZeroCount, 3);
      expect(b.settledCount, 0);
      expect(b.netCents, -1050); // we are net payable
    });
  });

  group('classifyDecimal — lossless for integer-backed Drift columns', () {
    test('Decimal values round-trip through classify', () {
      final balances = [
        Decimal.fromInt(500),
        Decimal.fromInt(-200),
        Decimal.zero,
      ];
      final b = c.classifyDecimal(balances, PartyKind.customer);
      expect(b.receivableCents, 500);
      expect(b.payableCents, 200);
      expect(b.settledCount, 1);
    });
  });

  test('PartyBalanceBreakdown.empty is a true zero', () {
    const b = PartyBalanceBreakdown.empty;
    expect(b.receivableCents, 0);
    expect(b.payableCents, 0);
    expect(b.totalCount, 0);
    expect(b.netCents, 0);
  });

  // ──────────────────────────────────────────────────────────────────
  // Phase 3.5.6 — balance projection invariants
  //
  // These tests lock the `+ invoice − paid` formula in one place so
  // any future change (cheque fees, FX, applied advances) shows up as
  // a single failing test instead of silently diverging across the
  // sale and purchase widgets that used to hand-roll it.
  // ──────────────────────────────────────────────────────────────────
  group('project — customer projection', () {
    test('cash sale (fully paid) leaves the balance unchanged', () {
      expect(
        c.project(
          currentBalanceCents: 0,
          invoiceTotalCents: 10000,
          paidAmountCents: 10000,
        ),
        0,
      );
    });

    test('credit sale (unpaid) increases what the customer owes us', () {
      expect(
        c.project(
          currentBalanceCents: 0,
          invoiceTotalCents: 10000,
          paidAmountCents: 0,
        ),
        10000,
      );
    });

    test('partial payment leaves the remainder on AR', () {
      expect(
        c.project(
          currentBalanceCents: 2500,
          invoiceTotalCents: 10000,
          paidAmountCents: 4000,
        ),
        2500 + 10000 - 4000,
      );
    });

    test('over-payment flips the sign to a customer advance', () {
      // Customer paid more than they owed — the projected balance goes
      // negative, which `statusOf` then labels as payable (we owe them).
      final projected = c.project(
        currentBalanceCents: 1000,
        invoiceTotalCents: 5000,
        paidAmountCents: 8000,
      );
      expect(projected, -2000);
      expect(c.statusOf(projected, PartyKind.customer),
          PartyBalanceStatus.payable);
    });
  });

  group('project — supplier projection', () {
    test('cash purchase (fully paid) leaves the balance unchanged', () {
      expect(
        c.project(
          currentBalanceCents: 0,
          invoiceTotalCents: 20000,
          paidAmountCents: 20000,
          kind: PartyKind.supplier,
        ),
        0,
      );
    });

    test('credit purchase increases what we owe the supplier', () {
      // Same formula as the customer side — the sign convention
      // (positive = payable on suppliers) makes "we owe more" come
      // out positive, which is exactly what the UI expects.
      final projected = c.project(
        currentBalanceCents: 0,
        invoiceTotalCents: 20000,
        paidAmountCents: 0,
        kind: PartyKind.supplier,
      );
      expect(projected, 20000);
      expect(c.statusOf(projected, PartyKind.supplier),
          PartyBalanceStatus.payable);
    });

    test('payment exceeding the purchase creates a supplier advance', () {
      final projected = c.project(
        currentBalanceCents: 0,
        invoiceTotalCents: 5000,
        paidAmountCents: 8000,
        kind: PartyKind.supplier,
      );
      expect(projected, -3000);
      expect(c.statusOf(projected, PartyKind.supplier),
          PartyBalanceStatus.receivable);
    });
  });
}
