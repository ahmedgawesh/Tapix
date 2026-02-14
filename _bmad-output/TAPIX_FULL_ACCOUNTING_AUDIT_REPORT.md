# TAPIX — Full System Accounting Audit Report

**Date:** 2026-02-13  
**Auditor:** Bob (SM Agent) — ERP Architecture & Financial Integrity Audit  
**Scope:** All financial operations, accounting integrity, balance sheet validation, cash control, data consistency, audit trail

---

## 1️⃣ Accounting Integrity Audit

### 1.1 Operations WITH Correct Double-Entry (✅ Verified)

| Operation | Module | Debit | Credit | Source |
|-----------|--------|-------|--------|--------|
| Cash Sale | Sales | Cash (1000) | Sales Revenue (4000) | `JournalEntryService.recordSaleJournalEntry` |
| Credit Sale | Sales | Accounts Receivable (1100) | Sales Revenue (4000) | Same |
| Sale COGS | Sales | COGS (5000) | Inventory (1200) | Same |
| Cash Purchase | Purchases | Inventory (1200) | Cash (1000) | `JournalEntryService.recordPurchaseJournalEntry` |
| Credit Purchase | Purchases | Inventory (1200) | Accounts Payable (2000) | Same |
| Sale Return (cash refund) | Sales | Sales Revenue (4000) | Cash (1000) | `JournalEntryService.recordSaleReturnJournalEntry` |
| Sale Return (credit note) | Sales | Sales Revenue (4000) | Accounts Receivable (1100) | Same |
| Sale Return COGS reversal | Sales | Inventory (1200) | COGS (5000) | Same |
| Purchase Return (cash) | Purchases | Cash (1000) | Inventory (1200) | `JournalEntryService.recordPurchaseReturnJournalEntry` |
| Purchase Return (credit) | Purchases | Accounts Payable (2000) | Inventory (1200) | Same |
| Expense | Expenses | Operating Expenses (5100) | Cash (1000) | `JournalEntryService.recordExpenseJournalEntry` |
| Customer Payment | Sales | Cash (1000) | Accounts Receivable (1100) | `JournalEntryService.recordCustomerPaymentJournalEntry` |
| Supplier Payment | Purchases | Accounts Payable (2000) | Cash (1000) | `JournalEntryService.recordSupplierPaymentJournalEntry` |
| Payroll (when paid) | Employees | Operating Expenses (5100) | Cash (1000) | `JournalEntryService.recordPayrollJournalEntry` |
| Loyalty Redemption | Customers | Operating Expenses (5100) | Sales Revenue (4000) | `JournalEntryService.recordLoyaltyRedemptionJournalEntry` |
| Inventory Adjustment (+) | Products | Inventory (1200) | COGS (5000) | `JournalEntryService.recordInventoryAdjustmentJournalEntry` |
| Inventory Adjustment (-) | Products | COGS (5000) | Inventory (1200) | Same |
| Void any posted entry | All | Reversal (swap Dr/Cr) | Reversal (swap Dr/Cr) | `AccountingRepository.voidJournalEntry` |
| Period Close | Accounting | Revenue accounts zeroed | Retained Earnings (3100) | `AccountingCloseService.closePeriod` |

**Verdict:** The core journal entry creation paths are well-designed. Every major financial event has a corresponding `JournalEntryService` method, and the `AccountingRepository.createJournalEntry` enforces debit=credit validation before committing.

---

### 1.2 Operations WITH MISSING or BROKEN Accounting Impact (🔴 CRITICAL)

#### FINDING C-1: `updateSale()` — NO Journal Reversal/Re-creation
- **Severity:** 🔴 CRITICAL
- **Module:** Sales → `sale_repository_impl.dart:124-167`
- **Problem:** `updateSale()` calls `_dao.updateSaleWithItems()` which replaces the sale record and items, but **does NOT void the original journal entries and does NOT create new ones**. The old journal entries (revenue + COGS) remain posted with the original amounts, while the sale record now has different amounts.
- **Impact:** Every edited sale creates a permanent ledger discrepancy. If a sale of $100 is edited to $80, the ledger still shows $100 revenue but the sale record shows $80.
- **Fix:** Before updating, void existing journal entries for the sale, then re-create them with new amounts. Or better: prevent editing posted sales entirely (only allow void + re-create).

#### FINDING C-2: `updateExpense()` — NO Journal Reversal/Re-creation
- **Severity:** 🔴 CRITICAL
- **Module:** Expenses → `expense_repository_impl.dart:124-126`
- **Problem:** `updateExpense()` directly updates the expense record via `_datasource.updateExpense(expense)` with **zero accounting impact**. The original journal entry (Dr Expense, Cr Cash) remains with the old amount.
- **Impact:** Every edited expense creates a permanent ledger discrepancy.
- **Fix:** Void original journal entry, re-create with new amount. Or prevent editing expenses after creation (void + re-create pattern).

#### FINDING C-3: `deleteExpense()` — NO Journal Reversal
- **Severity:** 🔴 CRITICAL
- **Module:** Expenses → `expense_repository_impl.dart:129-131`
- **Problem:** `deleteExpense()` directly deletes the expense record with **no journal entry reversal**. The journal entry (Dr Expense, Cr Cash) remains posted, but the source expense record is gone.
- **Impact:** Orphaned journal entries. Cash account permanently reduced, expense account permanently increased, for a transaction that no longer exists.
- **Fix:** Must void journal entries before deleting. Follow the same pattern as `voidSale()` and `deletePayment()`.

#### FINDING C-4: `deleteSale()` — NO Journal Reversal for Draft Sales with Journal Entries
- **Severity:** 🟡 HIGH
- **Module:** Sales → `sale_repository_impl.dart:193-195`
- **Problem:** `deleteSale()` calls `_dao.deleteSale(saleId)` which only allows deleting draft/pending sales. However, `createSale()` auto-posts the sale AND creates journal entries immediately. So by the time a user might try to delete, journal entries already exist.
- **Nuance:** The DAO restricts deletion to draft/pending status, but `createSale()` immediately calls `_dao.postSale(saleId)` changing status to 'posted'. So in practice, `deleteSale()` may never succeed for sales that have journal entries. But if there's any race condition or status mismatch, journal entries could be orphaned.
- **Fix:** Add journal entry voiding before deletion, same as `voidSale()`.

#### FINDING C-5: `updatePurchase()` — NO Journal Reversal/Re-creation
- **Severity:** 🔴 CRITICAL
- **Module:** Purchases → `purchase_repository_impl.dart:147-213`
- **Problem:** `updatePurchase()` updates the purchase record and items but **does NOT void original journal entries or create new ones**. Same pattern as C-1.
- **Impact:** Every edited purchase creates a permanent ledger discrepancy.
- **Fix:** Same as C-1.

#### FINDING C-6: Payroll Journal Entry Only on Status Change to "Paid"
- **Severity:** 🟡 HIGH
- **Module:** Employees → `employee_repository_impl.dart:542-548`
- **Problem:** `recordPayrollJournalEntry` is only called when payroll status changes to `paid`. If a payroll is created but never marked as paid, no journal entry exists. This is **correct behavior** for accrual accounting. However, there is **no accrual entry** (Dr Salary Expense, Cr Salary Payable) when the payroll is created — only the cash disbursement entry when paid.
- **Impact:** Salary expense is only recognized when cash is paid, not when the obligation is incurred. This is cash-basis accounting for payroll while the rest of the system uses accrual-basis patterns.
- **Fix:** Add an accrual journal entry on payroll creation (Dr Salary Expense, Cr Salary Payable), then reverse it when paid (Dr Salary Payable, Cr Cash). Or document that payroll uses cash-basis intentionally.

#### FINDING C-7: Commission Tracking Has NO Accounting Impact
- **Severity:** 🟡 HIGH
- **Module:** Employees
- **Problem:** Commissions are calculated and displayed in the UI (`totalCommissionCents`) and included in payroll calculations, but there is **no separate journal entry for commission accrual**. Commissions are bundled into the payroll `netPayCents` which gets a single journal entry (Dr Operating Expenses, Cr Cash).
- **Impact:** No granular tracking of commission expense vs. salary expense in the ledger. All employee costs are lumped into Operating Expenses (5100).
- **Fix:** Either create a dedicated commission expense account (e.g., 5210) and split the payroll journal entry, or accept the current lumped approach and document it.

#### FINDING C-8: Tax Collection Has No Dedicated Accounting Flow
- **Severity:** 🟡 HIGH
- **Module:** Sales / Purchases
- **Problem:** Sales and purchases include `taxCents` in their records, and there is a `Tax Payable (2100)` account in the chart of accounts. However, **no journal entry is created for tax**. The sale journal entry records the full `totalCents` (which includes tax) as revenue. Tax collected from customers is never posted to the Tax Payable liability account.
- **Impact:** Revenue is overstated by the tax amount. Tax liability is never recorded. The balance sheet will show zero tax payable even when tax has been collected.
- **Fix:** Split the sale journal entry: Dr Cash/Receivables for totalCents, Cr Revenue for (totalCents - taxCents), Cr Tax Payable for taxCents. Same pattern for purchases: Dr Inventory for (totalCents - taxCents), Dr Tax Receivable for taxCents, Cr Cash/Payables for totalCents.

---

## 2️⃣ Balance Sheet Validation

### 2.1 Balance Sheet Computation Logic

**File:** `balance_sheet_screen.dart:31-79`

The balance sheet computation is **logically correct**:
- Assets = sum of asset account debit balances
- Liabilities = sum of liability account credit balances
- Owner's Capital = sum of equity account credit balances
- Net Income = Revenue - Expenses (computed from trial balance)
- Total Equity = Owner's Capital + Net Income
- Check: Assets == Liabilities + Total Equity

### 2.2 Root Causes of Imbalance

Based on the code audit, the balance sheet imbalance is caused by one or more of these confirmed bugs:

| Root Cause | Severity | Likely Magnitude |
|-----------|----------|-----------------|
| **C-1: Updated sales don't reverse/recreate journal entries** | 🔴 CRITICAL | Grows with every sale edit |
| **C-2: Updated expenses don't reverse/recreate journal entries** | 🔴 CRITICAL | Grows with every expense edit |
| **C-3: Deleted expenses don't reverse journal entries** | 🔴 CRITICAL | Grows with every expense deletion |
| **C-5: Updated purchases don't reverse/recreate journal entries** | 🔴 CRITICAL | Grows with every purchase edit |
| **C-8: Tax not posted to Tax Payable** | 🟡 HIGH | Revenue overstated by total tax collected |
| **Missing opening capital injection** | 🟡 HIGH | Assets exist with no equity counterpart |

### 2.3 Retained Earnings Handling

- **Retained Earnings account (3100)** exists in the chart of accounts ✅
- **Period close** correctly transfers net income to retained earnings ✅
- **Net income is shown on balance sheet** as a line item under equity (before period close) ✅
- **No duplication** of retained earnings detected ✅

### 2.4 Profit Calculation

- Net profit = Revenue accounts (credit balance) - Expense accounts (debit balance) ✅
- Correctly computed from trial balance data ✅
- Included in equity section of balance sheet ✅

---

## 3️⃣ Period Closing & Locking Audit

### 3.1 Closing Validation (✅ Well-Designed)

**File:** `accounting_close_service.dart`

The closing service has **5 blocking conditions**:
1. Period must exist and be open ✅
2. Trial balance must be balanced ✅ (prevents closing when imbalanced)
3. No draft journal entries in the period ✅
4. No unposted transactions ✅
5. Period end date must be in the past ✅

**Verdict:** Closing is correctly blocked when the balance sheet is unbalanced. This is the right behavior.

### 3.2 Closed Period Lock (✅ Well-Designed)

**File:** `accounting_repository.dart:154-159`

- `isDateInClosedPeriod()` checks if a date falls in a closed period
- `createJournalEntry()` calls this check and throws `AccountingException` if the date is in a closed period ✅
- `postJournalEntry()` also checks closed period ✅

### 3.3 Historical Transaction Modification

- **Journal entries are immutable once posted** — only void+reversal is allowed ✅
- **Closed periods block new journal entries** ✅
- **BUT:** Sales, purchases, and expenses can be edited without any journal impact (C-1, C-2, C-5), effectively bypassing the immutability guarantee at the business layer

### 3.4 Closing Workflow

The closing workflow is **safe and correct**:
1. Validates all blocking conditions
2. Creates closing journal entry (Revenue/Expense → Retained Earnings)
3. Marks period as closed
4. No forced balancing ✅
5. Explains why closing is blocked ✅

---

## 4️⃣ Cash & Bank Control Audit

### 4.1 Cash Account (1000)

- **Sales (cash):** Dr Cash ✅
- **Purchases (cash):** Cr Cash ✅
- **Expenses:** Cr Cash ✅
- **Customer payments:** Dr Cash ✅
- **Supplier payments:** Cr Cash ✅
- **Payroll (paid):** Cr Cash ✅
- **Sale returns (cash refund):** Cr Cash ✅
- **Purchase returns (cash refund):** Dr Cash ✅

### 4.2 Bank Account (1010)

- **FINDING C-9:** The Bank account (1010) exists in the chart of accounts but is **never used by any journal entry service method**. All cash transactions go to account 1000 (Cash) regardless of payment method (cash, card, cheque).
- **Severity:** 🟡 HIGH
- **Impact:** No distinction between cash-in-hand and bank balance. Card payments are recorded as cash.
- **Fix:** When payment method is 'card' or 'cheque', use Bank (1010) instead of Cash (1000).

### 4.3 Manual Cash Edits

- **No direct balance editing** is possible through the UI — all balance changes go through journal entries ✅
- **Account balance updates** are only done inside `_updateAccountBalance()` which is called from `createJournalEntry()` and `postJournalEntry()` ✅
- **No manual cash adjustment endpoint** exists ✅

### 4.4 Cash Integrity Gaps

| Issue | Severity | Description |
|-------|----------|-------------|
| Expense deletion doesn't restore cash | 🔴 CRITICAL | Cash is permanently reduced (C-3) |
| Expense update doesn't adjust cash | 🔴 CRITICAL | Cash shows old amount (C-2) |
| Sale update doesn't adjust cash | 🔴 CRITICAL | Cash shows old amount (C-1) |
| Card/cheque payments go to Cash not Bank | 🟡 HIGH | Cash account inflated (C-9) |

---

## 5️⃣ Data Consistency & Workflow Review

### 5.1 Delete Without Reversing Accounting Impact

| Operation | Journal Reversal? | Risk |
|-----------|------------------|------|
| `deleteSale()` | ❌ NO | Orphaned journal entries (mitigated by draft-only restriction) |
| `deleteExpense()` | ❌ NO | 🔴 Orphaned journal entries |
| `deletePayment()` (sale) | ✅ YES | Correctly voids journal entries first |
| `deletePayment()` (purchase) | ✅ YES | Correctly voids journal entries first |
| `voidSale()` | ✅ YES | Correctly voids journal entries first |
| `voidPurchase()` | ✅ YES | Correctly voids journal entries first |
| `voidSaleReturn()` | ✅ YES | Correctly voids journal entries first |

### 5.2 Editing Invoices After Posting

| Operation | Status Check? | Journal Update? | Risk |
|-----------|--------------|-----------------|------|
| `updateSale()` | ❌ NO status check | ❌ NO journal update | 🔴 CRITICAL |
| `updatePurchase()` | ❌ NO status check | ❌ NO journal update | 🔴 CRITICAL |
| `updateExpense()` | ❌ NO status check | ❌ NO journal update | 🔴 CRITICAL |

**FINDING C-10:** None of the update methods check whether the record is posted/completed before allowing edits. A posted sale with journal entries can be freely edited through the UI, creating permanent ledger discrepancies.

### 5.3 Inventory Quantity vs. Value Consistency

- **Stock adjustments** correctly create journal entries with value based on `costCents * quantityDelta` ✅
- **Sale posting** deducts stock via `_dao.postSale()` ✅
- **Purchase posting** adds stock via `_dao.postPurchase()` ✅
- **Returns** restore/deduct stock correctly ✅

### 5.4 UI State vs. Accounting State

- The balance sheet screen correctly reads from the trial balance (account balances) ✅
- Sale/purchase/expense screens read from their respective tables, which may be out of sync with journal entries due to C-1/C-2/C-5 ❌

---

## 6️⃣ Audit Trail & User Responsibility

### 6.1 Audit Logging Coverage

| Operation | Audit Logged? | User ID Attached? |
|-----------|--------------|-------------------|
| Sale creation | ✅ YES | ✅ YES |
| Sale void | ✅ YES (critical severity) | ✅ YES |
| Sale return | ✅ YES | ✅ YES |
| Purchase creation | ✅ YES | ✅ YES |
| Purchase posting | ✅ YES | ✅ YES |
| Purchase void | ✅ YES (critical severity) | ✅ YES |
| Purchase return | ✅ YES | ✅ YES |
| Expense creation | ❌ NO | N/A |
| Expense update | ❌ NO | N/A |
| Expense deletion | ❌ NO | N/A |
| Customer payment | ❌ NO (only journal entry) | ✅ in journal |
| Supplier payment | ✅ YES | ✅ YES |
| Payroll creation | ❌ NO | N/A |
| Payroll status change | ❌ NO | N/A |
| Period close | ✅ YES (critical severity) | ✅ YES |
| Journal entry creation | ✅ YES (createdBy field) | ✅ YES |
| Journal entry void | ✅ YES (via void_logs) | ✅ YES |
| Inventory adjustment | ❌ NO (only journal entry) | ✅ in journal |
| Sale update | ❌ NO | N/A |
| Purchase update | ❌ NO | N/A |

### 6.2 Silent Background Adjustments

- **FINDING C-11:** The `LedgerRebuildService` can delete ALL journal entries and recreate them from source documents. This is a powerful recovery tool but has **no user confirmation gate** at the service level — it relies on the UI to confirm.
- **Severity:** 🟠 MEDIUM
- **Impact:** If triggered accidentally, all journal entries are wiped and rebuilt. The rebuild is comprehensive but any manual journal entries would be lost.

### 6.3 Missing Audit Gaps

- **FINDING C-12:** Expense CRUD operations have NO audit logging at all.
- **Severity:** 🟠 MEDIUM
- **FINDING C-13:** Sale and purchase UPDATE operations have NO audit logging.
- **Severity:** 🟠 MEDIUM

---

## 7️⃣ Diagnostic Output — Root Causes of Imbalance

### Root Cause Analysis

| # | Root Cause | Severity | Concrete Example | Recommendation |
|---|-----------|----------|-----------------|----------------|
| **C-1** | `updateSale()` doesn't reverse/recreate journal entries | 🔴 CRITICAL | Sale created for $100 (Dr Cash $100, Cr Revenue $100). Edited to $80. Ledger still shows $100 revenue, but sale record shows $80. Difference: $20. | **Option A:** Prevent editing posted sales — force void + re-create. **Option B:** In `updateSale()`, void old journal entries and create new ones atomically. |
| **C-2** | `updateExpense()` doesn't reverse/recreate journal entries | 🔴 CRITICAL | Expense created for $50 (Dr Expense $50, Cr Cash $50). Edited to $30. Ledger still shows $50 expense and $50 cash reduction. | Same as C-1. Void old entries, create new ones. |
| **C-3** | `deleteExpense()` doesn't reverse journal entries | 🔴 CRITICAL | Expense of $50 deleted. Journal entry (Dr Expense $50, Cr Cash $50) remains. Cash permanently understated by $50. | Add `_journalService.voidJournalEntriesForSource(sourceTable: 'expenses', sourceId: id)` before deletion. |
| **C-5** | `updatePurchase()` doesn't reverse/recreate journal entries | 🔴 CRITICAL | Purchase created for $200 (Dr Inventory $200, Cr Cash $200). Edited to $150. Ledger shows $200 inventory. | Same as C-1. |
| **C-8** | Tax not posted to Tax Payable account | 🟡 HIGH | Sale of $100 + $10 tax = $110 total. Journal: Dr Cash $110, Cr Revenue $110. Should be: Dr Cash $110, Cr Revenue $100, Cr Tax Payable $10. | Split sale journal entry to separate tax from revenue. |
| **C-9** | Bank account (1010) never used | 🟡 HIGH | Card payment of $100 goes to Cash (1000) instead of Bank (1010). Cash balance inflated. | Route card/cheque payments to Bank account. |
| **C-10** | No status check before editing posted records | 🔴 CRITICAL | Posted sale can be freely edited via `updateSale()`. | Add status guard: reject updates to posted/completed records. |
| **C-6** | Payroll uses cash-basis (no accrual entry) | 🟡 HIGH | Payroll created but not paid — no expense recognized. | Add accrual entry on creation, reverse on payment. |
| **C-7** | Commissions have no separate accounting | 🟠 MEDIUM | Commission of $500 bundled into payroll as generic operating expense. | Create dedicated commission expense account. |
| **C-11** | LedgerRebuildService has no user gate at service level | 🟠 MEDIUM | Accidental trigger wipes all journal entries. | Add confirmation token/flag parameter. |
| **C-12** | Expense operations have no audit logging | 🟠 MEDIUM | Expense created/edited/deleted with no trace. | Add audit logging to all expense CRUD. |
| **C-13** | Sale/Purchase updates have no audit logging | 🟠 MEDIUM | Posted sale edited with no record of change. | Add audit logging to update methods. |

---

## 8️⃣ Executive Summary

### Non-Technical Summary

Ahmed, your Tapix system has a **solid accounting foundation** — the double-entry bookkeeping engine (`AccountingRepository` + `JournalEntryService`) is well-designed with proper validation, immutability (void-only pattern), and period locking. The chart of accounts, trial balance, and period closing logic are all correct.

**However, the system has a critical gap between the business layer and the accounting layer.** When users **edit or delete** sales, purchases, or expenses after they've been created, the original journal entries are left untouched. This creates a growing discrepancy between what the business records show and what the ledger shows — which is exactly why your balance sheet is unbalanced.

Think of it like this: the accounting engine is a locked vault with proper double-entry rules. But the business operations have a side door that lets you change the source documents without updating the vault.

### Key System Risks

1. **Balance sheet will become increasingly unbalanced** with every edit/delete operation
2. **Cash account is unreliable** — deleted expenses don't restore cash, edited transactions don't adjust cash
3. **Revenue is overstated** — tax collected is recorded as revenue instead of tax liability
4. **No distinction between cash and bank** — all payments go to one account
5. **Audit gaps** — expense operations and record edits leave no trace

### Priority Fixes (Before Production)

| Priority | Fix | Effort |
|----------|-----|--------|
| **P0** | Block editing of posted sales/purchases/expenses (add status guard) | Small |
| **P0** | Add journal reversal to `deleteExpense()` | Small |
| **P0** | Add journal void+recreate to `updateSale()`, `updatePurchase()`, `updateExpense()` (if editing is allowed) | Medium |
| **P1** | Split tax from revenue in sale/purchase journal entries | Medium |
| **P1** | Route card/cheque payments to Bank account (1010) | Small |
| **P1** | Add audit logging to expense CRUD and sale/purchase updates | Small |
| **P2** | Add payroll accrual entries | Medium |
| **P2** | Create dedicated commission expense account | Small |
| **P3** | Add user confirmation gate to LedgerRebuildService | Small |

### What's Working Well

- ✅ Double-entry validation engine (debit must equal credit)
- ✅ Immutable journal entries (void-only pattern)
- ✅ Closed period locking
- ✅ Period close blocks when trial balance is unbalanced
- ✅ Comprehensive void handling for sales, purchases, returns, payments
- ✅ Audit trail for critical operations (voids, period closes)
- ✅ Balance sheet diagnostic service with intelligent hints
- ✅ Ledger rebuild service for recovery
- ✅ Integer cents for all money calculations (no floating point)
- ✅ Atomic transactions for journal entry creation

---

*This report identifies system correctness issues and accounting truth. No numbers were artificially adjusted. No balance was forced.*
