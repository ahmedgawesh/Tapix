# Tapix Accounting System — Deep Audit Report

**Date**: 2026-02-13  
**Triggered by**: Trial Balance mismatch (Debit=$1,508.00 ≠ Credit=$3,899.64) + AR mismatch (GL=60400, Customers=30400)

---

## Executive Summary

After a line-by-line audit of every financial operation in the codebase, I identified **7 critical bugs** and **5 architectural weaknesses** that collectively cause the trial balance imbalance and the AR/AP sub-ledger mismatch. The root causes fall into three categories:

1. **Dual-path journal entry creation** — Two independent systems (`AccountingRepository` and `JournalRepositoryImpl`) both create journal entries with different balance-update logic, causing double-counting or missed updates.
2. **GL ↔ Sub-ledger atomicity gap** — Journal entries update GL account balances, but customer/supplier sub-ledger balances are updated in a separate, non-atomic step in the DAO layer, with no transactional link to the GL update.
3. **Control account unprotected** — Manual journal entries can directly debit/credit Accounts Receivable (1100) and Accounts Payable (2000) without touching the customer/supplier sub-ledger, creating permanent divergence.

---

## Architecture Map (As-Is)

```
SaleFormBloc ──► SaleRepository ──► SaleDao.postSale() ──► customer.balanceCents (sub-ledger)
                                 ──► JournalEntryService ──► AccountingRepository.createJournalEntry()
                                                              ──► accounts.balanceCents (GL)

PurchaseFormBloc ──► PurchaseRepository ──► PurchaseDao.postPurchase() ──► supplier.balanceCents
                                        ──► JournalEntryService ──► AccountingRepository.createJournalEntry()

ExpenseFormBloc ──► ExpenseRepository ──► JournalEntryService ──► AccountingRepository.createJournalEntry()

JournalEntryFormBloc ──► JournalRepositoryImpl.createJournalEntryWithLines()
                         ──► JournalRepositoryImpl.postJournalEntry()
                              ──► account.balanceCents (GL) — DIFFERENT CODE PATH
```

**Two separate journal entry creation paths exist:**
- `AccountingRepository.createJournalEntry()` — used by `JournalEntryService` (auto-posted)
- `JournalRepositoryImpl.createJournalEntryWithLines()` + `postJournalEntry()` — used by manual journal entries (draft → post)

---

## Critical Bugs Found

### BUG-1: Dual Balance Update Paths (ROOT CAUSE of Trial Balance Imbalance)

**Severity**: 🔴 CRITICAL  
**Files**:
- `lib/features/accounting/data/repositories/accounting_repository.dart` (lines 656–687)
- `lib/features/accounting/data/repositories/journal_repository_impl.dart` (lines 196–237)

**Problem**: Two completely independent implementations of `_updateAccountBalance` exist:

**Path A** (`AccountingRepository._updateAccountBalance`):
```dart
// Uses int arithmetic
int balanceChange = 0;
if (type == 'asset' || type == 'expense') {
  balanceChange = debitCents - creditCents;
} else {
  balanceChange = creditCents - debitCents;
}
final newBalance = currentBalance + balanceChange;
```

**Path B** (`JournalRepositoryImpl.postJournalEntry`):
```dart
// Uses Decimal arithmetic
final isDebitNormal = account.accountType == 'asset' || account.accountType == 'expense';
final balanceChange = isDebitNormal
    ? (line.debitCents - line.creditCents)
    : (line.creditCents - line.debitCents);
final newBalance = account.balanceCents + balanceChange;
```

While the logic is mathematically equivalent, the problem is:
- **Path A** is used by `JournalEntryService` (sales, purchases, expenses, payments) — entries are auto-posted and balances updated immediately.
- **Path B** is used by manual journal entries via `JournalRepositoryImpl` — entries are created as draft, then posted separately.

If a manual journal entry is created via `JournalRepositoryImpl.createJournalEntryWithLines()`, it creates the entry as **draft** (status='draft') and does NOT update account balances. When `postJournalEntry()` is called, it updates balances via Path B. **However**, if the same entry is somehow also processed through `AccountingRepository`, balances get updated twice.

**Impact**: Any inconsistency between these two paths causes permanent trial balance drift.

---

### BUG-2: GL ↔ Customer Sub-Ledger Not Atomic (ROOT CAUSE of AR Mismatch)

**Severity**: 🔴 CRITICAL  
**Files**:
- `lib/features/sales/data/repositories/sale_repository_impl.dart` (lines 96–114)
- `lib/core/database/daos/sale_dao.dart` (lines 263–408)

**Problem**: When a sale is created:

1. `SaleDao.postSale()` runs in its own `transaction()` — updates `customers.balanceCents` (sub-ledger)
2. `JournalEntryService.recordSaleJournalEntry()` runs AFTER — updates `accounts.balanceCents` for account 1100 (GL)

These are **two separate transactions**. If step 1 succeeds but step 2 fails (or vice versa), the GL and sub-ledger diverge permanently.

```dart
// sale_repository_impl.dart lines 96-114
await _dao.postSale(saleId);                    // Transaction 1: updates customer balance
await _journalService.recordSaleJournalEntry(   // Transaction 2: updates GL balance
  saleId: saleId,
  totalCents: totalCents.toBigInt().toInt(),
  ...
);
```

**The same pattern exists for**:
- Purchase posting (supplier balance vs GL)
- Sale returns
- Purchase returns
- Sale payments
- Purchase payments

**Impact**: Any failure between the two steps creates a permanent mismatch between GL account 1100 (Accounts Receivable) and `SUM(customers.balance_cents)`.

---

### BUG-3: Sale Creates Multiple Journal Entries for Split Payments — Each Updates GL Independently

**Severity**: 🔴 CRITICAL  
**File**: `lib/core/services/journal_entry_service.dart` (lines 71–224)

**Problem**: `recordSaleJournalEntry()` creates up to **3 separate journal entries** for a single sale:
1. Cash Revenue entry (if paidAmountCents > 0)
2. Credit Revenue entry (if unpaid > 0)
3. COGS entry (if costOfGoodsCents > 0)

Each entry independently calls `AccountingRepository.createJournalEntry()`, which runs its own `_db.transaction()`. If entry 1 succeeds but entry 2 fails, the GL is partially updated — debits recorded without corresponding credits.

```dart
// Cash portion — separate transaction
if (paidAmountCents > 0) {
  await _accountingRepo.createJournalEntry(...);  // Transaction A
}

// Credit portion — separate transaction  
if (unpaid > 0) {
  await _accountingRepo.createJournalEntry(...);  // Transaction B
}

// COGS — separate transaction
if (costOfGoodsCents > 0) {
  await _accountingRepo.createJournalEntry(...);  // Transaction C
}
```

**Impact**: Partial journal entry creation causes trial balance imbalance.

---

### BUG-4: Manual Journal Entries Can Directly Modify Control Accounts

**Severity**: 🔴 CRITICAL  
**File**: `lib/features/accounting/presentation/bloc/journal_entry_form_bloc.dart` (lines 120–180)

**Problem**: The manual journal entry form allows users to create entries that debit/credit accounts 1100 (Accounts Receivable) and 2000 (Accounts Payable) directly. These entries update the GL balance but **never** update the customer/supplier sub-ledger.

```dart
// No check for control accounts — any account can be used
await _repository.createJournalEntryWithLines(
  description: event.description,
  entryDate: event.entryDate,
  entryType: 'manual',
  lines: event.lines,  // Can include account 1100 or 2000
  createdBy: event.createdBy,
);
```

**Impact**: Every manual entry touching 1100 or 2000 creates a permanent GL ↔ sub-ledger mismatch. This is the most likely cause of the `GL=60400, Customers=30400` discrepancy shown in the screenshot.

---

### BUG-5: Expense Update Voids Old Entry But May Create New Entry in Different Period

**Severity**: 🟡 HIGH  
**File**: `lib/features/expenses/data/repositories/expense_repository_impl.dart`

**Problem**: When updating an expense, the code voids old journal entries and creates new ones. But the void creates a reversal entry dated `DateTime.now()`, while the new entry uses the expense's original date. If the original date is in a closed period, the new entry creation will fail, but the void already succeeded — leaving a net reversal without replacement.

---

### BUG-6: Trial Balance Uses Cached `balanceCents` Without Verifying Against Journal Lines

**Severity**: 🟡 HIGH  
**Files**:
- `lib/features/accounting/data/repositories/accounting_repository.dart` (lines 384–467)
- `lib/features/accounting/data/repositories/journal_repository_impl.dart` (lines 326–393)

**Problem**: When `getTrialBalance()` is called without an `asOfDate`, it reads `account.balanceCents` directly from the accounts table. This cached balance can drift from the actual sum of posted journal entry lines if:
- A balance update failed silently
- A manual DB edit occurred
- The dual-path issue (BUG-1) caused inconsistency

The `asOfDate` path correctly recomputes from journal lines, but the default path trusts the cache.

---

### BUG-7: Reconciliation Check Compares Wrong Values for AR/AP

**Severity**: 🟡 HIGH  
**File**: `lib/features/accounting/data/repositories/accounting_repository.dart` (lines 512–540)

**Problem**: The AR reconciliation compares `accounts.balanceCents` (which stores the **natural balance** — positive for assets) against `SUM(customers.balance_cents)`. But `customers.balance_cents` represents **what the customer owes** (positive = they owe us), while the GL balance for account 1100 is stored as a natural debit balance.

The comparison `arBalance != customerTotal` is correct in principle, but the values can diverge due to BUG-2 and BUG-4.

---

## Architectural Weaknesses

### ARCH-1: No Single Transaction Wrapping Business Operations

The sale/purchase flow should wrap ALL operations (stock update, customer balance, journal entry, audit log) in a single database transaction. Currently, each step runs in its own transaction.

### ARCH-2: TransactionOrchestrator is Dead Code

`lib/core/services/transaction_orchestrator.dart` is marked `@Deprecated` and contains `UnimplementedError` stubs. It was designed to solve the atomicity problem but was never completed. The actual flow bypasses it entirely.

### ARCH-3: Two Repository Paths for Journal Entries

`AccountingRepository` and `JournalRepositoryImpl` both provide journal entry creation with different implementations. This violates the Single Responsibility Principle and creates confusion about which path to use.

### ARCH-4: Balance Stored as Decimal in DB but Processed as Int

Account balances are stored as `Decimal` in the database but converted to `int` for processing via `.toBigInt().toInt()`. This is safe for cents but adds unnecessary conversion complexity and potential for subtle bugs.

### ARCH-5: No Reconciliation Auto-Repair

The reconciliation check detects mismatches but provides no mechanism to auto-repair them. A "recompute balances from journal lines" function is needed.

---

## Fix Plan

### Phase 1: Stop the Bleeding (Prevent New Mismatches)

#### Fix 1.1: Protect Control Accounts from Manual Journal Entries
- Add validation in `JournalEntryFormBloc` and `AccountingRepository.createJournalEntry()` to reject manual entries that touch system control accounts (1100, 2000).
- Allow only system-generated entries (sale, purchase, payment types) to touch these accounts.

#### Fix 1.2: Wrap Sale/Purchase Operations in Single Transaction
- Move journal entry creation inside `SaleDao.postSale()` transaction.
- Or: Create a new `SalePostingService` that wraps stock update + customer balance + journal entry in one `_db.transaction()`.

#### Fix 1.3: Consolidate Journal Entry Creation to Single Path
- Make `AccountingRepository.createJournalEntry()` the ONLY path for creating journal entries.
- Refactor `JournalRepositoryImpl` to delegate to `AccountingRepository`.
- Remove duplicate `_updateAccountBalance` logic.

#### Fix 1.4: Batch Multiple Journal Entries in Single Transaction
- Modify `JournalEntryService.recordSaleJournalEntry()` to create all entries (revenue + COGS) in a single `_db.transaction()`.

### Phase 2: Repair Existing Data

#### Fix 2.1: Add "Recompute GL Balances from Journal Lines" Function
- Create a repair function that recalculates every account's `balanceCents` by summing all posted journal entry lines.
- This fixes any drift caused by BUG-1 or BUG-6.

#### Fix 2.2: Add "Reconcile AR/AP with Sub-Ledger" Repair Function
- Compare GL account 1100 balance with `SUM(customers.balance_cents)`.
- If mismatched, create a correcting journal entry to align them.
- Same for account 2000 vs suppliers.

### Phase 3: Diagnostic UI

#### Fix 3.1: Add Journal Entry Detail Dialog
- Next to each account balance in the Chart of Accounts and reports, add an info button that shows all journal entry lines affecting that account.
- This helps users understand what transactions contributed to each balance.

#### Fix 3.2: Enhanced Health Check Screen
- Show per-account breakdown in the health check.
- Show "GL Balance" vs "Recomputed from Lines" for each account.
- Show "GL AR" vs "Customer Sub-Ledger Total" with drill-down.

---

## File Reference Map

| Component | File | Role |
|-----------|------|------|
| AccountingRepository | `lib/features/accounting/data/repositories/accounting_repository.dart` | GL operations, journal entries (Path A) |
| JournalRepositoryImpl | `lib/features/accounting/data/repositories/journal_repository_impl.dart` | Journal entries (Path B), trial balance |
| JournalEntryService | `lib/core/services/journal_entry_service.dart` | Business event → journal entry mapping |
| SaleDao | `lib/core/database/daos/sale_dao.dart` | Sale posting, stock, customer balance |
| PurchaseDao | `lib/core/database/daos/purchase_dao.dart` | Purchase posting, stock, supplier balance |
| SaleRepositoryImpl | `lib/features/sales/data/repositories/sale_repository_impl.dart` | Sale orchestration |
| ExpenseRepositoryImpl | `lib/features/expenses/data/repositories/expense_repository_impl.dart` | Expense orchestration |
| AccountingHealthBloc | `lib/features/accounting/presentation/bloc/accounting_health_bloc.dart` | Health check UI |
| JournalEntryFormBloc | `lib/features/accounting/presentation/bloc/journal_entry_form_bloc.dart` | Manual journal entries |
| TransactionOrchestrator | `lib/core/services/transaction_orchestrator.dart` | DEAD CODE — not used |
| BalanceSheetDiagnosticService | `lib/features/accounting/domain/services/balance_sheet_diagnostic_service.dart` | Balance sheet analysis |

---

## Priority Order for Implementation

1. **Fix 1.1** — Control account protection (prevents new mismatches immediately)
2. **Fix 2.1** — Recompute GL balances (fixes trial balance now)
3. **Fix 2.2** — Reconcile AR/AP (fixes sub-ledger mismatch now)
4. **Fix 1.3** — Consolidate journal entry paths (prevents future drift)
5. **Fix 1.2** — Atomic transactions (prevents future partial updates)
6. **Fix 1.4** — Batch journal entries (prevents partial sale entries)
7. **Fix 3.1** — Diagnostic dialog (user visibility)
8. **Fix 3.2** — Enhanced health check (ongoing monitoring)
