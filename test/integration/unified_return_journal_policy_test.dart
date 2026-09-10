import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/returns/posted_return.dart';
import 'package:tapix/core/services/returns/return_journal_policy.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';

/// Phase-1 proof-of-unification tests.
///
/// These tests exercise `ReturnJournalPolicy` in isolation (no DAO / DB
/// writes) and assert:
/// - Linked and adjustment returns produce **identical** JE shape for the
///   same monetary inputs (same accounts, same amounts, same debits/credits).
/// - Every JE is double-entry balanced.
/// - Refund-channel routing is correct across every combination.
/// - Defense-in-depth invariants fire (e.g. credit-refund without party).
/// - Disposition routes damaged/scrap cost to 5800, not 1200.
///
/// The policy is the **single source of truth** for return-JE shape, so
/// if any caller produces a divergent shape, it's a caller bug — not a
/// policy bug. These tests lock in the shape contract.
void main() {
  late AppDatabase db;
  late AccountingRepository repo;
  late ReturnJournalPolicy policy;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    repo = AccountingRepository(db);
    policy = ReturnJournalPolicy(repo);

    // Force seed of default accounts.
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  // ── Helpers ─────────────────────────────────────────────────────────

  Future<int> acctId(String code) async {
    final row = await db
        .customSelect(
          'SELECT id FROM accounts WHERE account_code = ?',
          variables: [Variable.withString(code)],
        )
        .getSingle();
    return row.read<int>('id');
  }

  /// Total debits / credits on a JE data shape.
  ({int debit, int credit}) totals(JournalEntryData e) {
    int d = 0, c = 0;
    for (final l in e.lines) {
      d += l.debitCents;
      c += l.creditCents;
    }
    return (debit: d, credit: c);
  }

  /// Fetch the net (debit − credit) touching a given account code across
  /// every line of a JE. Signed integer: positive = net debit.
  Future<int> netOnAccount(JournalEntryData e, String code) async {
    final id = await acctId(code);
    int net = 0;
    for (final l in e.lines) {
      if (l.accountId != id) continue;
      net += l.debitCents - l.creditCents;
    }
    return net;
  }

  // ── Sale-side tests ──────────────────────────────────────────────────

  group('Sale Return — linked vs adjustment parity', () {
    // Inputs chosen so tax = 15% and cost recovers exactly.
    const totalCents = 1150;
    const taxCents = 150;
    const netRevenue = 1000;
    const inventoryCost = 700;

    // Each entry in this table exercises one refund channel. For credit we
    // split by side (linked→AR 1100, adjustment→Customer Credit Liab. 2400).
    final cases = [
      (channel: RefundChannel.cash, settleCode: '1000'),
      (channel: RefundChannel.bank, settleCode: '1010'),
      (channel: RefundChannel.cheque, settleCode: '1100'),
    ];

    for (final c in cases) {
      test(
        'refund=${c.channel.wireValue} → linked & adjustment JEs match shape',
        () async {
          final linked = await policy.toJournalEntry(
            PostedReturn(
              side: ReturnSide.sale,
              link: ReturnLink.linked(
                sourceInvoiceId: 101,
                sourceTable: 'sale_returns',
              ),
              partyId: 42,
              returnId: 101,
              refund: c.channel,
              currencyId: 1,
              lines: [
                const PostedReturnLine(
                  totalCents: totalCents,
                  taxCents: taxCents,
                  inventoryCostCents: inventoryCost,
                ),
              ],
            ),
          );

          final adj = await policy.toJournalEntry(
            PostedReturn(
              side: ReturnSide.sale,
              link: ReturnLink.adjustment,
              partyId: 42,
              returnId: 101,
              refund: c.channel,
              currencyId: 1,
              lines: [
                const PostedReturnLine(
                  totalCents: totalCents,
                  taxCents: taxCents,
                  inventoryCostCents: inventoryCost,
                ),
              ],
            ),
          );

          // ── Structural equality ──
          expect(linked.entryType, ReturnJournalPolicy.entryTypeSaleReturn);
          expect(adj.entryType, ReturnJournalPolicy.entryTypeSaleReturn);

          // Both JEs balance.
          final lt = totals(linked);
          final at = totals(adj);
          expect(lt.debit, lt.credit, reason: 'linked not balanced');
          expect(at.debit, at.credit, reason: 'adjustment not balanced');

          // Same totals on the wire.
          expect(lt.debit, totalCents + inventoryCost);
          expect(at.debit, totalCents + inventoryCost);

          // Same per-account net movement on every key account.
          for (final code in ['5700', '2100', '5300', '1200', c.settleCode]) {
            final linkedNet = await netOnAccount(linked, code);
            final adjNet = await netOnAccount(adj, code);
            expect(
              linkedNet,
              adjNet,
              reason:
                  'Account $code net differs: linked=$linkedNet adj=$adjNet',
            );
          }

          // Expected shape — 5700 debit, 2100 debit, settle credit, 1200 debit, 5300 credit.
          expect(await netOnAccount(linked, '5700'), netRevenue);
          expect(await netOnAccount(linked, '2100'), taxCents);
          expect(await netOnAccount(linked, c.settleCode), -totalCents);
          expect(await netOnAccount(linked, '1200'), inventoryCost);
          expect(await netOnAccount(linked, '5300'), -inventoryCost);
        },
      );
    }

    test('refund=credit: linked → 1100 AR; adjustment → 2400 CCL', () async {
      final linked = await policy.toJournalEntry(
        PostedReturn(
          side: ReturnSide.sale,
          link: ReturnLink.linked(
            sourceInvoiceId: 101,
            sourceTable: 'sale_returns',
          ),
          partyId: 42,
          returnId: 101,
          refund: RefundChannel.credit,
          currencyId: 1,
          lines: [
            const PostedReturnLine(
              totalCents: totalCents,
              taxCents: taxCents,
              inventoryCostCents: inventoryCost,
            ),
          ],
        ),
      );

      final adj = await policy.toJournalEntry(
        const PostedReturn(
          side: ReturnSide.sale,
          link: ReturnLink.adjustment,
          partyId: 42,
          returnId: 202,
          refund: RefundChannel.credit,
          currencyId: 1,
          lines: [
            PostedReturnLine(
              totalCents: totalCents,
              taxCents: taxCents,
              inventoryCostCents: inventoryCost,
            ),
          ],
        ),
      );

      // Both balanced.
      expect(totals(linked).debit, totals(linked).credit);
      expect(totals(adj).debit, totals(adj).credit);

      // Linked → AR
      expect(await netOnAccount(linked, '1100'), -totalCents);
      expect(await netOnAccount(linked, '2400'), 0);

      // Adjustment → Customer Credit Liability (2400) — clean AR sub-ledger.
      expect(await netOnAccount(adj, '1100'), 0);
      expect(await netOnAccount(adj, '2400'), -totalCents);

      // Contra-revenue/VAT/inventory identical on both.
      expect(
        await netOnAccount(linked, '5700'),
        await netOnAccount(adj, '5700'),
      );
      expect(
        await netOnAccount(linked, '2100'),
        await netOnAccount(adj, '2100'),
      );
      expect(
        await netOnAccount(linked, '1200'),
        await netOnAccount(adj, '1200'),
      );
      expect(
        await netOnAccount(linked, '5300'),
        await netOnAccount(adj, '5300'),
      );
    });

    test('refund=credit without partyId → AccountingException', () async {
      expect(
        () => policy.toJournalEntry(
          const PostedReturn(
            side: ReturnSide.sale,
            link: ReturnLink.adjustment,
            partyId: null,
            returnId: 303,
            refund: RefundChannel.credit,
            currencyId: 1,
            lines: [
              PostedReturnLine(
                totalCents: totalCents,
                taxCents: taxCents,
                inventoryCostCents: inventoryCost,
              ),
            ],
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'disposition=damaged routes inventory cost to 5800 Shrinkage',
      () async {
        final je = await policy.toJournalEntry(
          const PostedReturn(
            side: ReturnSide.sale,
            link: ReturnLink.adjustment,
            partyId: 42,
            returnId: 404,
            refund: RefundChannel.cash,
            currencyId: 1,
            lines: [
              PostedReturnLine(
                totalCents: totalCents,
                taxCents: taxCents,
                inventoryCostCents: inventoryCost,
                disposition: ReturnDisposition.damaged,
              ),
            ],
          ),
        );

        expect(totals(je).debit, totals(je).credit);
        expect(await netOnAccount(je, '5800'), inventoryCost);
        expect(await netOnAccount(je, '1200'), 0);
        // COGS still fully reversed.
        expect(await netOnAccount(je, '5300'), -inventoryCost);
      },
    );

    test('tax=0 emits no 2100 line; JE still balanced', () async {
      final je = await policy.toJournalEntry(
        const PostedReturn(
          side: ReturnSide.sale,
          link: ReturnLink.adjustment,
          partyId: 42,
          returnId: 505,
          refund: RefundChannel.cash,
          currencyId: 1,
          lines: [
            PostedReturnLine(
              totalCents: 1000,
              taxCents: 0,
              inventoryCostCents: 700,
            ),
          ],
        ),
      );

      expect(totals(je).debit, totals(je).credit);
      expect(await netOnAccount(je, '2100'), 0);
      expect(await netOnAccount(je, '5700'), 1000);
      expect(await netOnAccount(je, '1000'), -1000);
    });

    test(
      'totalCents=0 (COGS-only, restock path) emits only inventory leg',
      () async {
        final je = await policy.toJournalEntry(
          PostedReturn(
            side: ReturnSide.sale,
            link: ReturnLink.linked(
              sourceInvoiceId: 606,
              sourceTable: 'sale_returns',
            ),
            partyId: null,
            returnId: 606,
            refund: RefundChannel.cash,
            currencyId: 1,
            lines: [
              const PostedReturnLine(
                totalCents: 0,
                taxCents: 0,
                inventoryCostCents: 700,
              ),
            ],
          ),
        );

        expect(totals(je).debit, totals(je).credit);
        expect(je.lines.length, 2); // Dr 1200, Cr 5300 — nothing else.
        expect(await netOnAccount(je, '1200'), 700);
        expect(await netOnAccount(je, '5300'), -700);
        // Revenue / VAT / settlement untouched.
        expect(await netOnAccount(je, '5700'), 0);
        expect(await netOnAccount(je, '2100'), 0);
        expect(await netOnAccount(je, '1000'), 0);
      },
    );
  });

  // ── Purchase-side tests ──────────────────────────────────────────────

  group('Purchase Return — linked vs adjustment parity', () {
    const totalCents = 1150;
    const taxCents = 150;
    const netCents = 1000;

    test('linked (net == inventoryCost) → 4100 nets to zero, shape matches '
        'adjustment with same inputs', () async {
      final linked = await policy.toJournalEntry(
        PostedReturn(
          side: ReturnSide.purchase,
          link: ReturnLink.linked(
            sourceInvoiceId: 701,
            sourceTable: 'purchase_returns',
          ),
          partyId: null,
          returnId: 701,
          refund: RefundChannel.credit,
          currencyId: 1,
          lines: [
            const PostedReturnLine(
              totalCents: totalCents,
              taxCents: taxCents,
              inventoryCostCents: netCents, // linked-return invariant
            ),
          ],
        ),
      );

      final adj = await policy.toJournalEntry(
        const PostedReturn(
          side: ReturnSide.purchase,
          link: ReturnLink.adjustment,
          partyId: null,
          returnId: 702,
          refund: RefundChannel.credit,
          currencyId: 1,
          lines: [
            PostedReturnLine(
              totalCents: totalCents,
              taxCents: taxCents,
              inventoryCostCents: netCents,
            ),
          ],
        ),
      );

      // Both balanced.
      expect(totals(linked).debit, totals(linked).credit);
      expect(totals(adj).debit, totals(adj).credit);

      // 4100 nets to zero in both (no price variance).
      expect(await netOnAccount(linked, '4100'), 0);
      expect(await netOnAccount(adj, '4100'), 0);

      // Per-account parity.
      for (final code in ['2000', '1300', '1200', '4100']) {
        expect(
          await netOnAccount(linked, code),
          await netOnAccount(adj, code),
          reason: 'Account $code differs',
        );
      }

      // AP debited full total, VAT Receivable credited, Inventory credited net.
      expect(await netOnAccount(linked, '2000'), totalCents);
      expect(await netOnAccount(linked, '1300'), -taxCents);
      expect(await netOnAccount(linked, '1200'), -netCents);
    });

    test(
      'adjustment with price variance (net > cost) → 4100 credited surplus',
      () async {
        // Supplier credits us more than the inventory cost — "income" portion
        // parks on 4100 (contra-purchase).
        const cost = 900;
        final je = await policy.toJournalEntry(
          const PostedReturn(
            side: ReturnSide.purchase,
            link: ReturnLink.adjustment,
            partyId: null,
            returnId: 801,
            refund: RefundChannel.credit,
            currencyId: 1,
            lines: [
              PostedReturnLine(
                totalCents: totalCents,
                taxCents: taxCents,
                inventoryCostCents: cost,
              ),
            ],
          ),
        );

        expect(totals(je).debit, totals(je).credit);
        // 4100 = Cr net − Dr cost = -(1000 - 900) = -100 (surplus credited).
        expect(await netOnAccount(je, '4100'), -(netCents - cost));
        // Inventory drops by actual cost only.
        expect(await netOnAccount(je, '1200'), -cost);
      },
    );

    test('cash refund routes Dr to 1000 (not AP)', () async {
      final je = await policy.toJournalEntry(
        PostedReturn(
          side: ReturnSide.purchase,
          link: ReturnLink.linked(
            sourceInvoiceId: 901,
            sourceTable: 'purchase_returns',
          ),
          partyId: null,
          returnId: 901,
          refund: RefundChannel.cash,
          currencyId: 1,
          lines: [
            const PostedReturnLine(
              totalCents: totalCents,
              taxCents: taxCents,
              inventoryCostCents: netCents,
            ),
          ],
        ),
      );

      expect(totals(je).debit, totals(je).credit);
      expect(await netOnAccount(je, '1000'), totalCents);
      expect(await netOnAccount(je, '2000'), 0);
    });

    test(
      'bank and cheque refunds use their correct settlement accounts',
      () async {
        for (final c in [
          (channel: RefundChannel.bank, settleCode: '1010'),
          (channel: RefundChannel.cheque, settleCode: '2000'),
        ]) {
          final je = await policy.toJournalEntry(
            PostedReturn(
              side: ReturnSide.purchase,
              link: ReturnLink.adjustment,
              partyId: c.channel == RefundChannel.cheque ? 42 : null,
              returnId: 1001,
              refund: c.channel,
              currencyId: 1,
              lines: [
                const PostedReturnLine(
                  totalCents: totalCents,
                  taxCents: taxCents,
                  inventoryCostCents: netCents,
                ),
              ],
            ),
          );
          expect(totals(je).debit, totals(je).credit);
          expect(
            await netOnAccount(je, c.settleCode),
            totalCents,
            reason: 'channel=${c.channel.wireValue}',
          );
        }
      },
    );
  });

  // ── Edge cases ───────────────────────────────────────────────────────

  group('Edge cases', () {
    test('empty lines list throws', () async {
      expect(
        () => policy.toJournalEntry(
          const PostedReturn(
            side: ReturnSide.sale,
            link: ReturnLink.adjustment,
            partyId: 1,
            returnId: 1,
            refund: RefundChannel.cash,
            currencyId: 1,
            lines: [],
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('negative totalCents throws', () async {
      expect(
        () => policy.toJournalEntry(
          const PostedReturn(
            side: ReturnSide.sale,
            link: ReturnLink.adjustment,
            partyId: 1,
            returnId: 1,
            refund: RefundChannel.cash,
            currencyId: 1,
            lines: [
              PostedReturnLine(
                totalCents: -100,
                taxCents: 0,
                inventoryCostCents: 0,
              ),
            ],
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
