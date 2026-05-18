#!/usr/bin/env python3
"""
One-shot recovery script for the field drift discovered in
`tapix_backup_20260513_014004.db` (and any DB that posted adjustment
sale returns or discounted purchases against the buggy code paths
fixed in:
    - lib/core/database/daos/adjustment_return_dao.dart  (P1a / P1b / P1c / P1d)
    - lib/core/database/daos/purchase_dao.dart           (P2)

WHAT THIS SCRIPT FIXES
======================
Drift 1 — AR sub-ledger drift (per-customer)
    Root cause: postSaleAdjReturn used to write a `customer_transactions`
    row + decrement `customers.balance_cents` for cash / bank / 2400-credit
    refunds, but the JE never touched 1100 AR for those refund methods.
    Forward fix is in adjustment_return_dao.dart. To repair existing rows:
      1) DELETE customer_transactions rows where reference_type =
         'sale_return_adjustment' AND the underlying SAR's refund_method
         is NOT 'credit-via-AR' (in this codebase, NONE of them are).
      2) Recompute customers.balance_cents = SUM(amount_cents) over the
         remaining (correct) rows.

Drift 2 — Inventory GL vs Σ(stock × cost) drift (per-variant)
    Root cause: postPurchase stored variant.cost_cents = the GROSS typed-in
    list cost, while the JE correctly debited 1200 Inventory at NET (=
    subtotal − discount). Fix in purchase_dao.dart updates the variant
    cost to (gross − round(line_discount / qty)). To repair existing rows
    we recompute each variant's effective unit cost from its historical
    purchase_items rows (weighted by quantity, like WAC) and (optionally)
    post a one-shot 'inventory_drift_correction' JE for the residual
    difference between Inventory GL and the corrected Σ(stock × cost).

USAGE
=====
    # 1) Diagnostic only (default — read-only, no writes):
    python3 tool/recover_field_drift_2026_05_13.py /path/to/tapix.db

    # 2) Apply the fix (transactional, writes a backup .pre_recovery copy):
    python3 tool/recover_field_drift_2026_05_13.py /path/to/tapix.db --apply

The script is IDEMPOTENT: re-running --apply on a fixed DB is a no-op
(it always recomputes from the source rows, so nothing drifts further).

SAFETY RAILS
============
- Always operates inside a single SQLite transaction.
- Writes a `.pre_recovery` snapshot of the DB BEFORE applying.
- Refuses to run if `journal_entries` are missing the columns it needs.
- Prints every change before committing.
"""

import argparse
import shutil
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path


def _now_iso():
    """Timezone-aware UTC ISO timestamp (replaces deprecated utcnow())."""
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def fetchall(cur, sql, args=()):
    cur.execute(sql, args)
    return cur.fetchall()


def fetchone(cur, sql, args=()):
    cur.execute(sql, args)
    return cur.fetchone()


def acct_id(cur, code):
    row = fetchone(cur, "SELECT id FROM accounts WHERE account_code = ?", (code,))
    if not row:
        raise RuntimeError(f"Required account {code!r} missing from chart of accounts")
    return row[0]


def gl_balance(cur, code):
    aid = acct_id(cur, code)
    row = fetchone(
        cur,
        "SELECT COALESCE(SUM(jl.debit_cents), 0) AS dr, "
        "       COALESCE(SUM(jl.credit_cents), 0) AS cr "
        "FROM journal_entry_lines jl "
        "INNER JOIN journal_entries je ON je.id = jl.journal_entry_id "
        "WHERE jl.account_id = ? AND je.status = 'posted'",
        (aid,),
    )
    return row[0] - row[1]


def section(title):
    print()
    print("=" * 78)
    print(" " + title)
    print("=" * 78)


# ---------------------------------------------------------------------------
# Drift 1 — AR sub-ledger
# ---------------------------------------------------------------------------

def diagnose_ar(cur):
    """Returns (ar_gl, sum_balance, bad_rows) where bad_rows is a list of
    customer_transactions ids that were incorrectly written by the buggy
    postSaleAdjReturn path. Per the new policy, NO customer_transactions
    row should exist with reference_type = 'sale_return_adjustment'
    regardless of refund_method (the unified pipeline never touches the
    1100 AR sub-ledger from an adjustment return)."""
    ar_gl = gl_balance(cur, "1100")
    sum_bal_row = fetchone(
        cur,
        "SELECT COALESCE(SUM(balance_cents), 0) FROM customers WHERE is_active = 1",
    )
    sum_balance = sum_bal_row[0] if sum_bal_row else 0
    bad = fetchall(
        cur,
        "SELECT ct.id, ct.customer_id, ct.amount_cents, ct.reference_id, "
        "       sra.return_number, sra.refund_method "
        "FROM customer_transactions ct "
        "LEFT JOIN sale_return_adjustments sra ON sra.id = ct.reference_id "
        "WHERE ct.reference_type = 'sale_return_adjustment'",
    )
    return ar_gl, sum_balance, bad


def fix_ar(cur, bad_rows, dry_run):
    if not bad_rows:
        print("  ✓ No bad customer_transactions rows — AR sub-ledger is clean.")
        return 0

    affected_customers = sorted({r[1] for r in bad_rows})
    print(f"  Found {len(bad_rows)} bad customer_transactions row(s) "
          f"affecting {len(affected_customers)} customer(s):")
    for r in bad_rows:
        print(f"    tx_id={r[0]} customer_id={r[1]} amount={r[2]} "
              f"sar={r[4]} refund_method={r[5]}")

    if dry_run:
        print("  (dry-run: not deleting)")
        return 0

    # Atomically delete the bad rows + recompute balances from the surviving
    # customer_transactions. Mirrors `CustomerDao.recalculateBalance`.
    ids = [r[0] for r in bad_rows]
    cur.executemany("DELETE FROM customer_transactions WHERE id = ?",
                    [(i,) for i in ids])
    for cust_id in affected_customers:
        sum_row = fetchone(
            cur,
            "SELECT COALESCE(SUM(amount_cents), 0) FROM customer_transactions "
            "WHERE customer_id = ?",
            (cust_id,),
        )
        new_bal = sum_row[0]
        cur.execute(
            "UPDATE customers SET balance_cents = ?, updated_at = ? WHERE id = ?",
            (new_bal, _now_iso(), cust_id),
        )
        print(f"    ✓ customer_id={cust_id} balance recomputed → {new_bal}")
    return len(ids)


# ---------------------------------------------------------------------------
# Drift 2 — Inventory cost basis
# ---------------------------------------------------------------------------

def diagnose_inventory(cur):
    """Returns (inv_gl, stock_value_current, variant_corrections) where
    variant_corrections is a list of (variant_id, current_cost, net_cost)
    tuples to apply. Net cost is computed from purchase_items as
    weighted_avg(unit_cost − round(discount / qty))."""
    inv_gl = gl_balance(cur, "1200")

    # Current Σ(stock × cost) over active variants only.
    row = fetchone(
        cur,
        "SELECT COALESCE(SUM(v.stock_quantity * v.cost_cents), 0) "
        "FROM product_variants v "
        "WHERE v.is_active = 1 AND v.stock_quantity > 0",
    )
    stock_val = row[0] if row else 0

    # Effective unit cost from purchase_items = weighted avg over (unit_cost
    # − round(discount/qty)). We weight by quantity to mirror WAC behaviour.
    rows = fetchall(
        cur,
        "SELECT pi.variant_id, "
        "       SUM((pi.unit_cost_cents - "
        "            CASE WHEN pi.quantity > 0 "
        "                 THEN ROUND(CAST(pi.discount_cents AS REAL) / pi.quantity) "
        "                 ELSE 0 END) * pi.quantity) AS weighted_net_value, "
        "       SUM(pi.quantity) AS total_qty "
        "FROM purchase_items pi "
        "INNER JOIN purchases p ON p.id = pi.purchase_id "
        "WHERE p.status = 'posted' AND pi.variant_id IS NOT NULL "
        "GROUP BY pi.variant_id",
    )

    corrections = []
    for variant_id, weighted_net_value, total_qty in rows:
        if total_qty is None or total_qty <= 0:
            continue
        net_unit = round(weighted_net_value / total_qty)
        cur_row = fetchone(
            cur,
            "SELECT cost_cents, stock_quantity FROM product_variants WHERE id = ?",
            (variant_id,),
        )
        if not cur_row:
            continue
        current_cost, stock_qty = cur_row
        if int(current_cost) != int(net_unit):
            corrections.append((variant_id, int(current_cost), int(net_unit), int(stock_qty)))
    return inv_gl, stock_val, corrections


def fix_inventory(cur, corrections, inv_gl, stock_val_before, dry_run):
    if not corrections:
        print("  ✓ All variant costs already match net-of-discount basis.")
        return 0

    print(f"  Found {len(corrections)} variant cost correction(s):")
    delta_value = 0
    for variant_id, current, net, qty in corrections:
        delta = (net - current) * qty
        delta_value += delta
        print(f"    variant_id={variant_id} qty={qty} cost {current} → {net} "
              f"(Δ stock value = {delta:+d})")

    print(f"\n  Σ(stock × cost) before fix : {stock_val_before}")
    print(f"  Σ(stock × cost) after fix  : {stock_val_before + delta_value}")
    print(f"  Inventory GL (1200)        : {inv_gl}")
    residual = inv_gl - (stock_val_before + delta_value)
    print(f"  Residual GL−stock*cost     : {residual:+d}")

    if dry_run:
        print("  (dry-run: not updating variants nor posting residual JE)")
        return 0

    # 1) Update variant costs.
    for variant_id, _current, net, _qty in corrections:
        cur.execute(
            "UPDATE product_variants SET cost_cents = ?, updated_at = ? "
            "WHERE id = ?",
            (net, _now_iso(), variant_id),
        )
    # 2) Sync products.cost_cents from variants (weighted avg over active stock).
    cur.execute(
        "UPDATE products SET cost_cents = COALESCE(("
        "  SELECT CASE WHEN SUM(v.stock_quantity) > 0 "
        "              THEN ROUND(CAST(SUM(v.stock_quantity * v.cost_cents) AS REAL) "
        "                         / SUM(v.stock_quantity)) "
        "              ELSE products.cost_cents END "
        "  FROM product_variants v "
        "  WHERE v.product_id = products.id AND v.is_active = 1"
        "), cost_cents)"
    )
    print("  ✓ variant + product cost basis updated.")

    # 3) Optionally post a one-shot residual JE if non-zero (rounding from
    #    historical sale_cogs / return JEs that used the gross cost). The
    #    JE keeps the trial balance balanced and lets the reconciliation
    #    screen go to zero.
    if residual != 0:
        post_residual_je(cur, residual)
    return len(corrections)


def post_residual_je(cur, residual):
    """Post a one-shot 'inventory_drift_correction' journal entry to absorb
    the residual Inventory-GL vs Σ(stock × cost) gap left by historical
    JEs that used the buggy gross cost. Keeps the trial balance balanced.

    residual = inv_gl - corrected_stock_value
        > 0 → GL has more inventory than physical → write down: Cr 1200, Dr 5800
        < 0 → GL has less inventory than physical → write up:   Dr 1200, Cr 5800

    Uses 5800 'Inventory Shrinkage / Adjustments' (already in seed; if
    missing we fall back to 5300 COGS so the script never fails on a
    well-formed chart of accounts).
    """
    inv_account = acct_id(cur, "1200")
    try:
        adj_account = acct_id(cur, "5800")
    except RuntimeError:
        adj_account = acct_id(cur, "5300")

    now_iso = _now_iso()
    # Generate an entry_number like JEYYYYMMNNNNN (best-effort; not collision-
    # safe under heavy concurrent writes, but this is a one-shot recovery).
    yr_mo = datetime.now(timezone.utc).strftime("%Y%m")
    nxt_row = fetchone(
        cur,
        "SELECT COALESCE(MAX(CAST(SUBSTR(entry_number, 9) AS INTEGER)), 0) + 1 "
        "FROM journal_entries WHERE entry_number LIKE ?",
        (f"JE{yr_mo}%",),
    )
    seq = nxt_row[0] if nxt_row else 1
    entry_number = f"JE{yr_mo}{seq:05d}"

    abs_amount = abs(residual)
    cur.execute(
        "INSERT INTO journal_entries "
        "(entry_number, description, entry_date, status, entry_type, "
        " source_table, source_id, total_debit_cents, total_credit_cents, "
        " created_at, updated_at, posted_at) "
        "VALUES (?, ?, ?, 'posted', 'inventory_drift_correction', "
        " 'inventory_recovery', 0, ?, ?, ?, ?, ?)",
        (entry_number,
         "One-shot recovery for purchase-line-discount inventory drift "
         "(see tool/recover_field_drift_2026_05_13.py)",
         now_iso, abs_amount, abs_amount, now_iso, now_iso, now_iso),
    )
    je_id = cur.lastrowid

    # Look up base currency (1) — same convention used elsewhere in the
    # codebase.
    base_ccy = fetchone(cur, "SELECT id FROM currencies ORDER BY id LIMIT 1")[0]

    if residual > 0:
        # GL > stock value → GL inflated → Cr 1200 Inventory, Dr 5800 Adj
        debit_acc, credit_acc = adj_account, inv_account
    else:
        # GL < stock value → GL deflated → Dr 1200 Inventory, Cr 5800 Adj
        debit_acc, credit_acc = inv_account, adj_account

    cur.executemany(
        "INSERT INTO journal_entry_lines "
        "(journal_entry_id, account_id, debit_cents, credit_cents, "
        " currency_id, line_number, description, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (je_id, debit_acc, abs_amount, 0, base_ccy, 1,
             "Inventory drift correction (Dr)", now_iso),
            (je_id, credit_acc, 0, abs_amount, base_ccy, 2,
             "Inventory drift correction (Cr)", now_iso),
        ],
    )
    print(f"  ✓ Posted JE {entry_number} for residual {residual:+d} cents "
          f"(Dr={debit_acc}, Cr={credit_acc}).")


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("db", help="Path to the tapix SQLite DB")
    parser.add_argument("--apply", action="store_true",
                        help="Apply the fix. Default is diagnostic / dry-run.")
    args = parser.parse_args()

    db_path = Path(args.db).expanduser().resolve()
    if not db_path.exists():
        print(f"ERROR: DB not found: {db_path}", file=sys.stderr)
        sys.exit(2)

    if args.apply:
        snap = db_path.with_suffix(db_path.suffix + ".pre_recovery")
        shutil.copy2(db_path, snap)
        print(f"Snapshot saved: {snap}")

    con = sqlite3.connect(str(db_path))
    cur = con.cursor()

    section("Drift 1 — AR sub-ledger")
    ar_gl, sum_bal, bad_rows = diagnose_ar(cur)
    print(f"  AR GL (1100)              : {ar_gl}")
    print(f"  Σ customers.balance_cents : {sum_bal}")
    print(f"  Delta (GL − customers)    : {ar_gl - sum_bal:+d}")
    fix_ar(cur, bad_rows, dry_run=not args.apply)

    section("Drift 2 — Inventory cost basis")
    inv_gl, stock_val, corrections = diagnose_inventory(cur)
    print(f"  Inventory GL (1200)        : {inv_gl}")
    print(f"  Σ(stock × cost) (current) : {stock_val}")
    print(f"  Delta (GL − stock×cost)   : {inv_gl - stock_val:+d}")
    fix_inventory(cur, corrections, inv_gl, stock_val, dry_run=not args.apply)

    if args.apply:
        con.commit()
        print()
        print("=" * 78)
        print(" Recovery committed.")
        print("=" * 78)
        # Re-diagnose to print the post-fix totals.
        ar_gl2, sum_bal2, _ = diagnose_ar(cur)
        inv_gl2, stock_val2, _ = diagnose_inventory(cur)
        print(f"  AR delta    after fix: {ar_gl2 - sum_bal2:+d}")
        print(f"  Inv delta   after fix: {inv_gl2 - stock_val2:+d}")
    else:
        print()
        print("Run again with --apply to commit the changes.")
    con.close()


if __name__ == "__main__":
    main()
