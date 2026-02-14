# TAPIX Deep Application Audit Report V2

**Date:** 2026-02-13  
**Scope:** Full application — all repositories, DAOs, services, blocs, and data flows  
**Auditor:** Cascade AI  

---

## Executive Summary

After a comprehensive review of every repository implementation, DAO, service, bloc, and data flow in the Tapix application, the system is in **good overall health** with several important fixes already applied. The remaining findings are categorized by severity.

### Previously Fixed (This Audit Cycle)
| Fix | Status |
|-----|--------|
| 1.1 Control account protection (AR/AP) | ✅ Done |
| 1.2 Atomic sale/purchase creation transactions | ✅ Done |
| 1.3 Consolidated journal entry paths with protection | ✅ Done |
| 1.4 Batch journal entries (solved by 1.2) | ✅ Done |
| 2.1 Recompute GL balances from journal lines | ✅ Done |
| 2.2 Reconcile AR/AP with sub-ledger repair | ✅ Done |
| 3.1 Journal entry diagnostic dialog per account | ✅ Done |
| 3.2 Health check screen with repair buttons | ✅ Done |

---

## CRITICAL Findings (Must Fix)

### C1. Expense Creation Not Atomic
**File:** `lib/features/expenses/data/repositories/expense_repository_impl.dart:100-134`  
**Severity:** 🔴 CRITICAL  
**Description:** `createExpense()` creates the expense record, then calls `_journalService.recordExpenseJournalEntry()` as a separate operation. If the journal entry fails, the expense exists without a GL entry — causing ledger drift.  
**Impact:** Unbalanced ledger. Expense recorded in sub-ledger but not in GL.  
**Fix:** Wrap in a single DB transaction, same pattern as sale/purchase creation.

### C2. Expense Update Not Atomic
**File:** `lib/features/expenses/data/repositories/expense_repository_impl.dart:138-168`  
**Severity:** 🔴 CRITICAL  
**Description:** `updateExpense()` voids old journal entries, updates the record, then re-creates journal entries — three separate operations. If step 3 fails after step 1, the expense has no journal entries.  
**Fix:** Wrap void + update + re-create in a single transaction.

### C3. Sale Return Creation Not Atomic
**File:** `lib/features/sales/data/repositories/sale_repository_impl.dart:362-436`  
**Severity:** 🔴 CRITICAL  
**Description:** `createSaleReturn()` performs: create return → post return (stock) → journal entry → commission reversal as separate operations. If journal entry creation fails after stock was restored, GL and inventory are out of sync.  
**Fix:** Wrap in a single DB transaction.

### C4. Purchase Return Creation Not Atomic
**File:** `lib/features/purchases/data/repositories/purchase_repository_impl.dart:354-424`  
**Severity:** 🔴 CRITICAL  
**Description:** Same pattern as C3. `createPurchaseReturn()` creates return → posts return (stock deduction) → journal entry as separate operations.  
**Fix:** Wrap in a single DB transaction.

### C5. Sale Payment Recording Not Atomic
**File:** `lib/features/sales/data/repositories/sale_repository_impl.dart:469-499`  
**Severity:** 🔴 CRITICAL  
**Description:** `recordPayment()` records the payment in the DAO (which updates customer balance), then creates a journal entry as a separate call. If the journal entry fails, customer balance is updated but GL is not.  
**Fix:** Wrap in a single DB transaction.

### C6. Purchase Payment Recording Not Atomic
**File:** `lib/features/purchases/data/repositories/purchase_repository_impl.dart:477-519`  
**Severity:** 🔴 CRITICAL  
**Description:** Same as C5 but for supplier payments.  
**Fix:** Wrap in a single DB transaction.

### C7. Customer Direct Transaction + Journal Not Atomic
**File:** `lib/features/customers/data/repositories/customer_repository_impl.dart:125-171`  
**Severity:** 🔴 CRITICAL  
**Description:** `recordTransaction()` creates the customer transaction (which updates customer balance via DAO), then creates journal entries for payments/discounts. If journal entry fails, customer balance changed but GL didn't.  
**Fix:** Wrap in a single DB transaction.

### C8. Supplier Direct Transaction + Journal Not Atomic
**File:** `lib/features/suppliers/data/repositories/supplier_repository_impl.dart:116-161`  
**Severity:** 🔴 CRITICAL  
**Description:** Same as C7 but for suppliers.  
**Fix:** Wrap in a single DB transaction.

---

## HIGH Findings (Should Fix)

### H1. Void Sale Not Atomic with Journal Void
**File:** `lib/features/sales/data/repositories/sale_repository_impl.dart:298-318`  
**Severity:** 🟠 HIGH  
**Description:** `voidSale()` voids journal entries (with try/catch that swallows errors), deletes commissions, then voids the sale in the DAO. The journal void failure is silently logged. If the DAO void succeeds but journal void failed, the GL still shows the original entries.  
**Recommendation:** The try/catch is intentional (to not block the void), but the swallowed error should at minimum be surfaced to the user or flagged for reconciliation.

### H2. Void Purchase Not Atomic with Journal Void
**File:** `lib/features/purchases/data/repositories/purchase_repository_impl.dart:267-290`  
**Severity:** 🟠 HIGH  
**Description:** Same pattern as H1.

### H3. Employee Payroll Creation + Journal Not Atomic
**File:** `lib/features/employees/data/repositories/employee_repository_impl.dart:512-553`  
**Severity:** 🟠 HIGH  
**Description:** `createPayroll()` creates the payroll record, then creates an accrual journal entry. If the journal entry fails, payroll exists without GL recognition.  
**Fix:** Wrap in a single DB transaction (needs AppDatabase injection).

### H4. Employee Payroll Status Update + Journal Not Atomic
**File:** `lib/features/employees/data/repositories/employee_repository_impl.dart:557-588`  
**Severity:** 🟠 HIGH  
**Description:** `updatePayrollStatus()` updates the payroll, then creates a payment journal entry when status is 'paid'. If journal fails, payroll shows paid but GL doesn't reflect the cash outflow.  
**Fix:** Wrap in a single DB transaction.

### H5. Double Balance Update Risk in CustomerDao.createTransaction
**File:** `lib/core/database/daos/customer_dao.dart:61-134`  
**Severity:** 🟠 HIGH  
**Description:** `CustomerDao.createTransaction()` auto-updates customer balance for transaction types like 'sale', 'payment', etc. But `SaleDao.postSale()` ALSO manually updates customer balance. When `postSale()` inserts a customer transaction via `into(db.customerTransactions).insert()` (bypassing `CustomerDao.createTransaction()`), this is fine. However, if any code path calls `CustomerDao.createTransaction()` for a sale-related transaction, the balance would be double-counted.  
**Current Status:** The DAO paths are currently separate (SaleDao uses raw inserts, CustomerDao.createTransaction is used for direct transactions). This is safe **as long as no one accidentally routes sale transactions through CustomerDao.createTransaction**.  
**Recommendation:** Add a comment/guard in CustomerDao.createTransaction to reject 'sale' and 'sale_void' types, since those should only come through SaleDao.

### H6. Same Risk in SupplierDao.createTransaction
**File:** `lib/core/database/daos/supplier_dao.dart:61-130`  
**Severity:** 🟠 HIGH  
**Description:** Same pattern as H5 but for suppliers. SupplierDao.createTransaction auto-updates balance, but PurchaseDao.postPurchase also manually updates balance via raw inserts.  
**Recommendation:** Add guard to reject 'purchase' and 'purchase_void' types.

---

## MEDIUM Findings (Nice to Fix)

### M1. Invoice/Purchase Number Generation Race Condition
**Files:** `sale_dao.dart:198-215`, `purchase_dao.dart:166-183`  
**Severity:** 🟡 MEDIUM  
**Description:** `generateInvoiceNumber()` and `generatePurchaseNumber()` query the last number and increment. Under concurrent access (unlikely in single-user mobile but possible on web/desktop), two transactions could get the same number.  
**Recommendation:** Use a unique constraint on invoice_number/purchase_number columns (likely already exists in schema) so the DB rejects duplicates. The current approach is acceptable for single-user scenarios.

### M2. Employee Commission Status Update Fetches All Commissions
**File:** `lib/features/employees/data/repositories/employee_repository_impl.dart:660-672`  
**Severity:** 🟡 MEDIUM  
**Description:** `updateCommissionStatus()` calls `_dao.watchEmployeeCommissions(0).first` to find a commission by ID. Passing `employeeId: 0` likely returns no results or all results depending on the DAO implementation. This is a bug — it should query by commission ID directly.  
**Fix:** Add a `getCommissionById(int id)` method to EmployeeDao.

### M3. Expense Delete Doesn't Check Status
**File:** `lib/features/expenses/data/repositories/expense_repository_impl.dart:172-188`  
**Severity:** 🟡 MEDIUM  
**Description:** `deleteExpense()` voids journal entries and deletes the expense without checking if it's in a closed accounting period. The journal void will fail if the period is closed, but the expense record will still be deleted.  
**Recommendation:** Check accounting period before allowing deletion.

### M4. LedgerRebuildService Replays ALL Sale Payments Including Initial
**File:** `lib/core/services/ledger_rebuild_service.dart:428-449`  
**Severity:** 🟡 MEDIUM  
**Description:** The ledger rebuild replays ALL sale_payments rows. But `recordSaleJournalEntry` already handles the cash portion of a sale. If the initial payment was backfilled into sale_payments by `postSale()`, the rebuild will double-count it (once in the sale journal entry, once in the payment journal entry).  
**Current Mitigation:** The journal entry service uses `sourceTable` + `sourceId` to tag entries, so the rebuild should be idempotent as long as the source tags are unique. However, the initial payment and the sale itself may create overlapping GL entries.  
**Recommendation:** During rebuild, skip sale_payments that were created as part of the initial posting (notes = 'Initial payment on posting').

---

## LOW Findings (Informational)

### L1. Audit Log Failures Are Silent in Some Paths
Several repository methods use fire-and-forget audit logging (no await, or await without try/catch). This is intentional for non-critical logging but means audit trail gaps are possible.

### L2. DateTime.now() Called Multiple Times in Transactions
In several DAO methods, `DateTime.now()` is called multiple times within a transaction, resulting in slightly different timestamps for related records. This is cosmetic but could cause confusion in audit trails.

### L3. Dashboard Stats Load All Records Into Memory
`SaleDao.getDashboardStats()` and `PurchaseDao.getDashboardStats()` load ALL sales/purchases into memory and filter in Dart. For large datasets, this should use SQL aggregation.

### L4. Customer/Supplier Balance Recalculation Is Sequential
`CustomerDao.recalculateAllBalances()` and `SupplierDao.recalculateAllBalances()` loop through all records one by one. For large datasets, a single SQL UPDATE with a subquery would be more efficient.

---

## Architecture Assessment

### Strengths ✅
1. **Clean Architecture** — Proper separation of concerns across layers
2. **Atomic Sale/Purchase Creation** — Fixed in this audit cycle
3. **Control Account Protection** — Prevents manual GL corruption
4. **Comprehensive Audit Trail** — Most operations are logged
5. **Double-Entry Validation** — All journal entries validated for balance
6. **Ledger Rebuild Capability** — Full rebuild from historical transactions
7. **Sub-Ledger Reconciliation** — Customer/supplier balance recalculation exists
8. **GL Balance Recomputation** — Can recompute from journal lines
9. **Negative Stock Guards** — Purchase void checks stock before reversing
10. **Cascade Void** — Voiding a sale/purchase cascades to associated returns

### Weaknesses ⚠️
1. **Non-Atomic Operations** — 8 critical paths still lack transaction wrapping
2. **Double Balance Update Risk** — DAO auto-balance vs manual balance paths
3. **Silent Journal Void Failures** — Void operations swallow journal errors

---

## Recommended Fix Priority

| Priority | Finding | Effort |
|----------|---------|--------|
| 1 | C1-C2: Expense atomicity | Small |
| 2 | C3-C4: Return atomicity | Small |
| 3 | C5-C6: Payment atomicity | Small |
| 4 | C7-C8: Direct transaction atomicity | Small |
| 5 | H5-H6: DAO balance guard | Tiny |
| 6 | H3-H4: Payroll atomicity | Small |
| 7 | M2: Commission status bug | Tiny |
| 8 | M4: Rebuild double-count risk | Medium |
