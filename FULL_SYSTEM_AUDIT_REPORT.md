# TAPIX — FULL SYSTEM AUDIT REPORT

**Date:** Pre-Release Audit  
**Audited By:** Senior Software Engineer / Senior Accountant / Security Engineer / QA Tester  
**Scope:** Entire application codebase  
**Status:** READ-ONLY AUDIT — No modifications made

---

## TABLE OF CONTENTS

1. [Part 1 — Accounting Integrity Check](#part-1--accounting-integrity-check)
2. [Part 2 — Data Consistency](#part-2--data-consistency)
3. [Part 3 — Crash & Freeze Analysis](#part-3--crash--freeze-analysis)
4. [Part 4 — Performance Analysis](#part-4--performance-analysis)
5. [Part 5 — Security Audit](#part-5--security-audit)
6. [Part 6 — Edge Case Testing](#part-6--edge-case-testing)
7. [Part 7 — Test Coverage](#part-7--test-coverage)
8. [Part 8 — Release Readiness Report](#part-8--release-readiness-report)

---

## PART 1 — ACCOUNTING INTEGRITY CHECK

### 1.1 Double-Entry Bookkeeping Enforcement

**Status: STRONG with minor gaps**

The system enforces double-entry at multiple layers:

| Layer | File | Enforcement |
|-------|------|-------------|
| Data Model | `journal_entry_data.dart` | `validate()` checks debits == credits, min 2 lines, no negative amounts |
| Repository | `accounting_repository.dart:168-195` | Re-validates balance, line count, debit/credit exclusivity |
| Repository (alt) | `journal_repository_impl.dart:133-200` | Duplicate validation (redundant but safe) |
| Validation Engine | `validation_engine.dart:9-68` | Comprehensive pre-commit validation |

**Finding 1.1.1 — ValidationEngine is NOT wired into the creation path**
- **Risk:** MEDIUM
- **Module:** `core/services/validation_engine.dart`
- **Description:** `ValidationEngine` exists with comprehensive validation for sales, purchases, payments, expenses, and stock adjustments, but it is **never instantiated or injected** in `injection_container.dart`. It is dead code. The actual validation happens inside `AccountingRepository.createJournalEntry()` and `JournalEntryData.validate()`, so the system is still protected, but the sale/purchase-level validations in `ValidationEngine` (e.g., total mismatch check, discount > subtotal check) are never enforced.
- **Suggested Fix:** Either wire `ValidationEngine` into the DI container and call it before creating sales/purchases, or remove it to avoid confusion.

**Finding 1.1.2 — Duplicate validation logic across two repositories**
- **Risk:** LOW
- **Module:** `accounting_repository.dart` + `journal_repository_impl.dart`
- **Description:** Both `AccountingRepository.createJournalEntry()` and `JournalRepositoryImpl.createJournalEntry()` contain nearly identical validation logic (balance check, line count, control account protection, closed period lock). This is defense-in-depth but creates maintenance risk — a fix in one may not be applied to the other.
- **Suggested Fix:** Extract shared validation into a single method or delegate to `JournalEntryData.validate()`.

### 1.2 Sales Invoice Journal Entries

**Status: CORRECT with one rounding risk**

`JournalEntryService.recordSaleJournalEntry()` correctly generates:

| Scenario | Debit | Credit |
|----------|-------|--------|
| Cash sale (no VAT) | Dr Cash | Cr Revenue |
| Cash sale (with VAT) | Dr Cash | Cr Revenue + Cr VAT Payable |
| Credit sale (no VAT) | Dr Accounts Receivable | Cr Revenue |
| Credit sale (with VAT) | Dr Accounts Receivable | Cr Revenue + Cr VAT Payable |
| Mixed (partial payment) | Both cash + receivable entries generated separately |

**Finding 1.2.1 — VAT rounding can cause 1-cent imbalance**
- **Risk:** HIGH
- **Module:** `journal_entry_service.dart:89-92, 149-152`
- **Description:** VAT is split proportionally between paid and unpaid portions using integer division with `.round()`:
  ```dart
  final paidTax = (taxCents * paidAmountCents / totalCents).round();
  ```
  The credit portion tax is computed as `taxCents - paidTax`. While the total VAT is preserved, the individual entries could have rounding that makes `paidRevenue = paidAmountCents - paidTax` not exactly match the intended split. More critically, when `paidAmountCents` and `totalCents` produce values that round differently, the cash entry debits `paidAmountCents` but credits `paidRevenue + paidTax` where `paidRevenue = paidAmountCents - paidTax`. This is algebraically balanced (`paidAmountCents = (paidAmountCents - paidTax) + paidTax`), so **each individual journal entry IS balanced**. However, the revenue attribution between cash and credit portions may be off by 1 cent.
- **Suggested Fix:** This is cosmetically imperfect but mathematically safe for the GL. Low priority to fix unless VAT reporting requires exact per-entry accuracy.

**Finding 1.2.2 — No COGS (Cost of Goods Sold) journal entries for sales**
- **Risk:** HIGH
- **Module:** `journal_entry_service.dart`
- **Description:** When a sale is completed, journal entries are created for revenue, cash/receivables, and VAT, but **no COGS entry is generated** (Dr Cost of Goods Sold, Cr Inventory). This means:
  - The Inventory account in the GL never decreases on sale
  - The COGS expense is never recorded
  - Profit/Loss statements will be inaccurate (revenue exists but no matching expense)
  - The Inventory GL account will not match physical stock value
- **Suggested Fix:** Add COGS journal entry logic to `recordSaleJournalEntry()`. Compute COGS from the cost of each item sold and generate: Dr COGS (expense), Cr Inventory (asset).

**Finding 1.2.3 — No Inventory journal entries for purchases**
- **Risk:** HIGH
- **Module:** `journal_entry_service.dart:208-300`
- **Description:** Purchase journal entries record Dr Inventory/Expense + Cr AP/Cash, which is correct for the payment side. However, the "Inventory" debit uses account code `'5100'` (an expense account code, suggesting "Purchases Expense" not "Inventory Asset"). If `5100` is classified as an expense, then the purchase is immediately expensed rather than capitalized as inventory. For a retail/trading business, inventory should be an asset (`1xxx`).
- **Suggested Fix:** Verify account `5100` classification. If products are tracked as inventory (they are — `trackInventory` exists), purchases should debit an Inventory asset account (e.g., `1200`), and COGS should be recorded at sale time.

### 1.3 Purchase Invoice Journal Entries

**Status: CORRECT structure, account classification concern (see 1.2.3)**

`JournalEntryService.recordPurchaseJournalEntry()` correctly handles:
- Cash purchases: Dr Inventory/Expense, Cr Cash/Bank
- Credit purchases: Dr Inventory/Expense, Cr Accounts Payable
- Mixed: Both entries generated
- VAT Input: Dr VAT Receivable (2200), Cr appropriately offset

### 1.4 Customer Balances vs. Accounts Receivable GL

**Status: RECONCILIATION EXISTS but drift risk present**

**Positive:**
- `AccountingRepository.reconcileBalances()` compares GL AR balance (from journal lines) against `SUM(customers.balance_cents)` — good.
- Customer balance updates happen atomically within transactions in `SaleDao.postSale()`, `SaleDao.voidSale()`, `SaleDao.recordPayment()`.

**Finding 1.4.1 — Customer balance updated in DAO, NOT through journal entries**
- **Risk:** HIGH
- **Module:** `sale_dao.dart:326-408`, `customer_repository_impl.dart:121-139`
- **Description:** Customer `balanceCents` is updated directly via SQL in `SaleDao.postSale()` and `SaleDao.recordPayment()`. The GL is updated separately via `JournalEntryService`. These are in the same transaction in `SaleRepositoryImpl.createSale()`, but the customer balance and GL balance are **computed independently** — there is no guarantee they will always match because:
  1. `CustomerRepositoryImpl.updateCustomerBalance()` can change customer balance WITHOUT creating a journal entry (though it's audit-logged)
  2. Direct SQL in `SaleDao.recordPayment()` adjusts customer balance, while `SaleRepositoryImpl.recordPayment()` creates journal entries — but the amounts could theoretically diverge if the DAO logic and journal service logic compute differently
- **Suggested Fix:** Ensure `CustomerRepositoryImpl.updateCustomerBalance()` is either disabled (like `SupplierRepositoryImpl.updateSupplierBalance()` which throws `StateError`) or always paired with a journal entry.

**Finding 1.4.2 — Supplier balance direct update is correctly disabled**
- **Risk:** NONE (good practice)
- **Module:** `supplier_repository_impl.dart:121-128`
- **Description:** `SupplierRepositoryImpl.updateSupplierBalance()` correctly throws `StateError` with a message directing callers to use `recordTransaction()` instead. Customer side should mirror this pattern.

### 1.5 Supplier Balances vs. Accounts Payable GL

**Status: CORRECT with same structural risk as customers**

Same pattern as 1.4 — supplier balance updated in `PurchaseDao.postPurchase()` via direct SQL, while GL updated via `JournalEntryService`. Both are within the same transaction.

### 1.6 VAT Calculations

**Status: CORRECT**

- Sales VAT Payable uses account `2100`
- Purchase VAT Receivable uses account `2200`
- VAT is correctly split between paid/credit portions
- No net VAT calculation exists (VAT payable - VAT receivable) — this would need to be a report

### 1.7 Returns

**Status: CORRECT**

**Sale Returns** (`journal_entry_service.dart:302-360`):
- Cash refund: Dr Revenue, Cr Cash — correct reversal
- Credit refund: Dr Revenue, Cr Accounts Receivable — correct
- Stock is restored in `SaleDao.postSaleReturn()`
- Customer balance adjusted for credit refunds only (correct)
- Return quantities validated against (sold - already returned)

**Purchase Returns** (`journal_entry_service.dart:362-420`):
- Credit refund: Dr Accounts Payable, Cr Inventory/Expense — correct
- Cash refund: Dr Cash, Cr Inventory/Expense — correct
- Stock is deducted in `PurchaseDao.postPurchaseReturn()`
- Negative stock guard exists (throws if stock insufficient)

### 1.8 Partial Payments

**Status: CORRECT**

- Sale payments: `SaleRepositoryImpl.recordPayment()` wraps payment recording + journal entry in a transaction. Dr Cash, Cr AR.
- Purchase payments: `PurchaseRepositoryImpl.recordPayment()` same pattern. Dr AP, Cr Cash.
- Both correctly update paid amount and customer/supplier balance within the same transaction.

### 1.9 Deleting/Editing Invoices

**Status: SAFE with one gap**

- **Posted/completed sales cannot be edited** — `SaleRepositoryImpl.updateSale()` guards against non-draft edits
- **Draft edits** void old journal entries and re-create — correct
- **Void** creates reversal entries — immutable pattern, correct
- **Delete** (draft only) properly voids journal entries first

**Finding 1.9.1 — Purchase deletion does NOT void journal entries**
- **Risk:** CRITICAL
- **Module:** `purchase_repository_impl.dart:293-304`
- **Description:** `PurchaseRepositoryImpl.deletePurchase()` calls `_datasource.deletePurchase()` which only allows draft deletion. However, it does NOT call `_journalService.voidJournalEntriesForSource()` before deleting. Since `createPurchase()` creates journal entries immediately (even for drafts), deleting a draft purchase will leave orphaned journal entries in the GL.
- **Suggested Fix:** Add `_journalService.voidJournalEntriesForSource(sourceTable: 'purchases', sourceId: purchaseId, reason: 'Purchase deleted')` before the deletion call, matching the pattern in `SaleRepositoryImpl.deleteSale()`.

### 1.10 Control Account Protection

**Status: CORRECT**

- Control accounts `1100` (AR) and `2000` (AP) are protected from manual journal entries
- Only system entry types (sale, purchase, payment, reversal, etc.) can modify them
- Enforced in `AccountingRepository.createJournalEntry()` lines 196-220

**Finding 1.10.1 — AP control account code mismatch**
- **Risk:** MEDIUM
- **Module:** `accounting_repository.dart:36` vs `journal_entry_service.dart`
- **Description:** `_controlAccountCodes` contains `{'1100', '2000'}` for AR and AP. But `JournalEntryService` uses account code `'2000'` for AP. If the actual AP account is seeded with a different code, the protection would fail silently. Need to verify the chart of accounts seeding uses `2000` for AP.
- **Suggested Fix:** Verify seeded chart of accounts. Consider using constants for account codes shared between `AccountingRepository` and `JournalEntryService`.

---

## PART 2 — DATA CONSISTENCY

### 2.1 Invoice Exists but Journal Entry Missing

**Finding 2.1.1 — Sale created but journal entry creation fails silently in voidSale**
- **Risk:** MEDIUM
- **Module:** `sale_repository_impl.dart:300-321`
- **Description:** `voidSale()` wraps journal entry voiding in a try/catch and **logs a warning but continues** if it fails. This means a sale can be voided (stock restored, customer balance reversed) while the GL still has the original posted journal entries. The sale DAO `voidSale()` method also continues.
- **Suggested Fix:** Either make journal voiding mandatory (let the exception propagate) or add the sale to a "needs reconciliation" queue.

**Finding 2.1.2 — Same pattern in voidPurchase, voidSaleReturn, voidPurchaseReturn**
- **Risk:** MEDIUM
- **Module:** Multiple repository impls
- **Description:** All void operations catch journal voiding failures and continue. This is consistent but means GL can become stale after any void failure.

### 2.2 Journal Entry Exists but Invoice Missing

**Finding 2.2.1 — Sale deletion uses CASCADE but journal entries reference by sourceTable/sourceId**
- **Risk:** LOW
- **Module:** `transactions.dart`, `accounting_repository.dart`
- **Description:** `SaleItems` have `onDelete: KeyAction.cascade` from `Sales`, so deleting a sale cascades to items. However, journal entries reference sales via `sourceTable='sales'` and `sourceId=saleId` — these are NOT foreign keys, just text/int fields. If a sale is deleted without voiding journal entries first, orphaned journal entries remain. The code does void entries before deletion for sales (except the purchase deletion gap noted in 1.9.1).

### 2.3 Payment Without Linked Invoice

**Status: SAFE**

All payment recording goes through repository methods that require a `saleId` or `purchaseId`. There is no code path to create a payment without a linked invoice.

Direct customer/supplier payments (from profile pages) go through `CustomerRepositoryImpl.recordTransaction()` and `SupplierRepositoryImpl.recordTransaction()` which create proper journal entries.

### 2.4 Stock Quantity Not Matching Inventory Account

**Finding 2.4.1 — No Inventory GL account tracking**
- **Risk:** HIGH (same root cause as Finding 1.2.2/1.2.3)
- **Module:** System-wide
- **Description:** Physical stock is tracked in `products.stock_quantity` and `product_variants.stock_quantity`. However, there is no Inventory asset account in the GL that tracks the monetary value of inventory. Without COGS entries on sale and Inventory entries on purchase (using an asset account), there is no way to reconcile physical stock value against the GL.
- **Suggested Fix:** Implement full inventory accounting: Purchases debit Inventory asset, Sales debit COGS and credit Inventory asset.

### 2.5 Customer/Supplier Balance Not Matching Ledger

**Status: RECONCILIATION EXISTS**

`AccountingRepository.reconcileBalances()` checks:
- AR GL balance (from journal lines) vs `SUM(customers.balance_cents)` 
- AP GL balance (from journal lines) vs `SUM(suppliers.balance_cents)`

This is good. However, the reconciliation is not run automatically — it must be triggered manually.

**Finding 2.5.1 — No automatic reconciliation on app startup or periodic schedule**
- **Risk:** MEDIUM
- **Module:** `accounting_repository.dart:543-624`
- **Description:** Reconciliation exists but is not wired to run on startup, after transactions, or on a schedule. Drift between GL and sub-ledger could accumulate undetected.
- **Suggested Fix:** Run reconciliation on app startup and after each financial transaction batch, logging warnings to `AuditLog`.

### 2.6 Commission Records Without Matching Sales

**Finding 2.6.1 — Commission deletion on sale void uses fire-and-forget**
- **Risk:** LOW
- **Module:** `sale_repository_impl.dart:316`
- **Description:** `_employeeDao.deleteCommissionsBySaleId(saleId)` is called during void/delete. If this fails, orphaned commissions remain. Not a GL issue but affects commission reports.

### 2.7 Loyalty Points Without Matching Sales

**Finding 2.7.1 — Loyalty operations are outside the main transaction**
- **Risk:** LOW
- **Module:** `sale_repository_impl.dart:153-161, 436-441`
- **Description:** `_awardLoyaltyPointsForSale()` and `_reverseLoyaltyPointsForReturn()` run OUTSIDE the main DB transaction. If the loyalty operation fails, the sale still succeeds but loyalty points are lost/not reversed. The code catches errors and logs warnings.
- **Suggested Fix:** Acceptable for non-critical data, but consider a retry mechanism.

---

## PART 3 — CRASH & FREEZE ANALYSIS

### 3.1 Null Reference Risks

**Finding 3.1.1 — Decimal.toBigInt().toInt() chain on nullable fields**
- **Risk:** MEDIUM
- **Module:** Multiple DAOs and repositories
- **Description:** Throughout the codebase, monetary values are converted via `value.toBigInt().toInt()`. If `value` is null (from a nullable Decimal field), this will throw a `NoSuchMethodError`. Examples:
  - `sale.totalCents.toBigInt().toInt()` — `totalCents` is non-nullable in schema, safe
  - `sale.paidAmountCents.toBigInt().toInt()` — non-nullable, safe
  - `employee.fixedCommissionCents?.toBigInt().toInt() ?? 0` — correctly null-safe
  - Overall: The schema enforces non-null on critical money fields, so this is mostly safe.

**Finding 3.1.2 — Potential null customer in sale operations**
- **Risk:** LOW
- **Module:** `sale_dao.dart:395-406`
- **Description:** In `postSale()`, the code fetches the customer and checks `if (customer != null)` before updating balance. If the customer was deleted between sale creation and posting, the balance update is silently skipped. The sale succeeds but customer accounting is lost.

### 3.2 Async Race Conditions

**Finding 3.2.1 — Invoice number generation is not truly atomic**
- **Risk:** MEDIUM
- **Module:** `sale_dao.dart:198-215`, `purchase_dao.dart:166-183`
- **Description:** Invoice numbers are generated by querying the last number and incrementing. If two sales are created simultaneously (e.g., two cashiers), they could query the same last number before either inserts, producing duplicate invoice numbers. The `invoiceNumber` column does not have a UNIQUE constraint in the schema.
- **Suggested Fix:** Add a UNIQUE constraint on `sales.invoiceNumber` and `purchases.purchaseNumber`. Handle the constraint violation with retry logic.

**Finding 3.2.2 — Stock deduction race condition**
- **Risk:** MEDIUM
- **Module:** `sale_dao.dart:269-301`
- **Description:** Stock is deducted via `stock_quantity = stock_quantity - ?` which is atomic at the SQL level. However, there is no check that `stock_quantity >= item.quantity` before deduction for sales (unlike purchase voids which DO check). This means stock can go negative silently on sales.
- **Suggested Fix:** Add a negative stock guard to sale posting, or at minimum a check-and-warn.

### 3.3 Unhandled Exceptions

**Finding 3.3.1 — Ledger rebuild has no progress/cancellation mechanism**
- **Risk:** MEDIUM
- **Module:** `ledger_rebuild_service.dart`
- **Description:** The ledger rebuild is a destructive operation that deletes all journal entries and re-creates them. If the app crashes during this operation (which could take significant time with many transactions), the ledger will be in an inconsistent state with some entries missing.
- **Suggested Fix:** Add a `rebuilding` flag that is checked on app startup. If found, auto-restart the rebuild or alert the user.

**Finding 3.3.2 — Transaction nesting in SaleRepositoryImpl.createSale()**
- **Risk:** LOW
- **Module:** `sale_repository_impl.dart:104`
- **Description:** `createSale()` opens a `_dao.db.transaction()`, inside which it calls `_dao.createSaleWithItems()` which also opens a `transaction()`. Drift handles nested transactions via savepoints, so this works correctly but adds unnecessary complexity.

### 3.4 Memory Leaks

**Finding 3.4.1 — StreamController in AuthRepository not disposed on app close**
- **Risk:** LOW
- **Module:** `auth_repository.dart:16, 152-154`
- **Description:** `AuthRepository` has a `StreamController<UserEntity?>` that is created in the constructor and has a `dispose()` method. However, since `AuthRepository` is registered as a `LazySingleton` in GetIt, `dispose()` is never called. The stream lives for the app's lifetime, which is acceptable for a singleton, but the subscription in `_initializeSession()` (line 29) is never cancelled.

**Finding 3.4.2 — SessionService StreamController same pattern**
- **Risk:** LOW
- **Module:** `session_service.dart:20, 102-104`
- **Description:** Same pattern — singleton with `StreamController` that is never disposed. Acceptable for app-lifetime singletons.

### 3.5 Blocking Database Calls

**Finding 3.5.1 — Dashboard stats load ALL records into memory**
- **Risk:** MEDIUM
- **Module:** `sale_dao.dart:1087-1121`, `purchase_dao.dart:935-987`
- **Description:** `getDashboardStats()` fetches ALL sales/purchases into memory, then filters in Dart. As the dataset grows, this becomes a memory and performance issue. See Part 4 for details.

---

## PART 4 — PERFORMANCE ANALYSIS

### 4.1 Slow Database Queries

**Finding 4.1.1 — Trial balance aggregates ALL posted journal lines**
- **Risk:** MEDIUM
- **Module:** `accounting_repository.dart:424-540`
- **Description:** `getTrialBalance()` joins `journalEntryLines` with `journalEntries`, filters by status='posted' and date, then iterates ALL rows in Dart to compute balances. With thousands of entries, this becomes slow.
- **Suggested Fix:** Use SQL `GROUP BY` to aggregate debits/credits per account directly in the query.

**Finding 4.1.2 — Reconciliation runs trial balance + iterates all posted entries**
- **Risk:** MEDIUM
- **Module:** `accounting_repository.dart:543-624`
- **Description:** `reconcileBalances()` calls `getTrialBalance()` (slow) then fetches ALL posted entries to check each one is balanced. This is O(n) where n = total posted entries.
- **Suggested Fix:** Use a SQL query to find unbalanced entries: `SELECT * FROM journal_entries WHERE status='posted' AND total_debit_cents != total_credit_cents`.

### 4.2 Missing Indexes

**Finding 4.2.1 — No explicit indexes on frequently queried columns**
- **Risk:** MEDIUM
- **Module:** Database schema (tables/*.dart)
- **Description:** The following columns are frequently used in WHERE/JOIN clauses but may lack indexes:
  - `journal_entries.source_table` + `journal_entries.source_id` (used in every void/lookup)
  - `journal_entries.status` (filtered on every report)
  - `journal_entries.entry_date` (range queries for reports)
  - `customer_transactions.customer_id` + `customer_transactions.reference_type`
  - `supplier_transactions.supplier_id` + `supplier_transactions.reference_type`
  - `sale_items.sale_id`
  - `purchase_items.purchase_id`
  - Drift auto-creates indexes for foreign keys on some backends, but explicit indexes should be defined for compound queries.
- **Suggested Fix:** Add explicit `@TableIndex` annotations or create indexes in migration.

### 4.3 Unnecessary Data Loading

**Finding 4.3.1 — watchAllSalesWithCustomer loads all sales for dashboard**
- **Risk:** MEDIUM
- **Module:** `sale_dao.dart:109-123`
- **Description:** `watchAllSalesWithCustomer()` loads ALL sales with JOINs to customers and employees. On screens that only show recent sales, this loads unnecessary historical data.
- **Suggested Fix:** Add pagination or a default limit (e.g., last 100 sales).

**Finding 4.3.2 — getDashboardStats() fetches all records**
- **Risk:** MEDIUM
- **Module:** `sale_dao.dart:1087-1121`, `purchase_dao.dart:935-987`
- **Description:** Dashboard stats fetch ALL sales/purchases into memory, then iterate in Dart. Should use SQL aggregation.
- **Suggested Fix:** Replace with SQL:
  ```sql
  SELECT COUNT(*), SUM(CASE WHEN status='completed' THEN total_cents ELSE 0 END), ...
  FROM sales WHERE status != 'voided'
  ```

### 4.4 Large Loops on UI Thread

**Finding 4.4.1 — Stock sync iterates all affected products**
- **Risk:** LOW
- **Module:** `sale_dao.dart:304-321`, `purchase_dao.dart:448-479`
- **Description:** After stock changes, the code loops through all affected products to sync `products.stock_quantity` from variants. This is N queries per product. For bulk operations (bulk imports), this could be slow.
- **Suggested Fix:** Acceptable for typical transaction sizes (1-50 items). Consider batch SQL for bulk operations.

---

## PART 5 — SECURITY AUDIT

### 5.1 Authentication

**Status: GOOD**

- BCrypt hashing with 12 salt rounds — industry standard
- FlutterSecureStorage for session tokens — correct for mobile
- Session timeout (24 hours default) — reasonable
- Session validation checks token + last activity

### 5.2 Authorization

**Status: GOOD with one gap**

- Role-based access: owner > manager > accountant > cashier > salesperson
- Granular permissions per role
- Route-level permission checks

**Finding 5.2.1 — No server-side authorization on data operations**
- **Risk:** MEDIUM (for offline-first app, acceptable)
- **Module:** System-wide
- **Description:** Permission checks are UI-level only. The repository layer does not check permissions before executing operations. In an offline-first local-database app, this is acceptable since the "server" is the local device. However, if a web/API layer is ever added, every repository method would need authorization.

### 5.3 SQL Injection

**Status: SAFE**

- All raw SQL uses parameterized queries with `Variable.withInt()`, `Variable.withString()`, etc.
- Drift's typed query builders prevent injection
- `searchSales()` uses `like(searchQuery)` where `searchQuery = '%$query%'` — the `$query` is passed as a Drift parameter, not concatenated into SQL.

### 5.4 Insecure Local Storage

**Finding 5.4.1 — Session token generation uses non-cryptographic randomness**
- **Risk:** LOW
- **Module:** `session_service.dart:96-100`
- **Description:** `_generateToken()` generates tokens using `DateTime.now().millisecondsSinceEpoch` and its `hashCode`. This is predictable and not cryptographically random. For a local-only app, this is low risk, but if tokens are ever transmitted, they should use `dart:math Random.secure()` or similar.
- **Suggested Fix:** Use `Random.secure()` for token generation.

**Finding 5.4.2 — Database is not encrypted**
- **Risk:** MEDIUM
- **Module:** Database layer
- **Description:** The SQLite database is stored as a plain file. On rooted/jailbroken devices, an attacker could read all financial data. For a POS system handling sensitive financial data, database encryption (e.g., SQLCipher) is recommended.
- **Suggested Fix:** Consider adding SQLCipher encryption for production release.

### 5.5 Data Leakage

**Finding 5.5.1 — Developer logs contain financial data**
- **Risk:** LOW
- **Module:** Multiple services
- **Description:** `developer.log()` calls throughout the codebase include financial amounts, sale IDs, customer IDs, etc. In release builds, `developer.log` is stripped, but on debug builds this data appears in device logs.
- **Suggested Fix:** Ensure `developer.log` is only active in debug mode (it already is by default in Flutter).

### 5.6 Password Policy

**Finding 5.6.1 — No password complexity requirements**
- **Risk:** MEDIUM
- **Module:** `password_service.dart`, `auth_repository.dart`
- **Description:** There is no minimum password length, complexity requirement, or password history check. The `createFirstOwner()` method accepts any string as a password.
- **Suggested Fix:** Add minimum password length (8+), require at least one number/special character.

**Finding 5.6.2 — No brute force protection**
- **Risk:** MEDIUM
- **Module:** `auth_repository.dart:40-57`
- **Description:** The `login()` method has no rate limiting or account lockout after failed attempts. An attacker with device access could brute-force passwords.
- **Suggested Fix:** Add failed login counter. Lock account after N failed attempts (e.g., 5).

---

## PART 6 — EDGE CASE TESTING

### 6.1 Deleting Old Invoices

**Status: PROTECTED**
- Only draft sales/purchases can be deleted
- Posted/completed sales cannot be deleted (guard in DAO)
- Void is the correct mechanism for posted items

**Exception:** Purchase deletion doesn't void journal entries (Finding 1.9.1)

### 6.2 Editing Historical Transactions

**Status: PROTECTED**
- Only draft/pending sales can be edited (`sale_repository_impl.dart:192-198`)
- Only draft purchases can be edited (`purchase_repository_impl.dart:175-180`)
- Edit path correctly voids old journal entries and re-creates

### 6.3 Negative Inventory

**Finding 6.3.1 — Sales allow negative stock**
- **Risk:** HIGH
- **Module:** `sale_dao.dart:269-301`
- **Description:** `postSale()` deducts stock without checking if sufficient stock exists. Stock can go negative. The `ValidationEngine.validateStockAdjustment()` has an `allowNegativeStock` flag, but this validator is not wired into the sale creation path.
- **Suggested Fix:** Add a stock sufficiency check before deduction. Either block the sale or require explicit override (e.g., "Allow backorder" flag).

**Positive:** Purchase voids DO check for sufficient stock before reversing.

### 6.4 Customer Credit Turning Negative

**Status: ALLOWED**
- Customer `balanceCents` can go negative (overpayment or credit note beyond balance)
- This is acceptable business logic (customer has a credit)
- No explicit guard needed

### 6.5 Partial Returns

**Status: CORRECT**
- Return quantities validated: `returnItem.quantity > maxReturnable` throws exception
- `maxReturnable = saleItem.quantity - previouslyReturned`
- Voided returns are excluded from "already returned" count
- Proportional commission reversal: `deduction = (originalAmount * returnTotalCents) / saleTotalCents`

### 6.6 Editing Product Prices After Sales

**Status: SAFE**
- Sale items store `unitPriceCents` at time of sale — price changes don't affect historical sales
- Purchase items store `originalCostCents`, `originalPriceCents` — preserves history
- Variants store `previousCostCents`, `previousPriceCents` for audit

### 6.7 Deleting Suppliers With Transactions

**Status: PROTECTED by FK constraints**
- `Products.supplierId` uses `onDelete: KeyAction.restrict` — cannot delete supplier with linked products
- `Purchases.supplierId` has FK constraint — cannot delete supplier with purchases
- However, `SupplierRepositoryImpl.deleteSupplier()` does NOT check for existing transactions before attempting delete — it relies on the DB constraint to fail.

**Finding 6.7.1 — Poor error message on FK violation**
- **Risk:** LOW
- **Module:** `supplier_repository_impl.dart:90-92`
- **Description:** If a user tries to delete a supplier with transactions, Drift will throw a database exception. The error message will be a raw SQLite error, not a user-friendly message.
- **Suggested Fix:** Catch FK violation and throw a business-friendly exception.

### 6.8 Zero-Amount Transactions

**Finding 6.8.1 — Zero-total sales/purchases could bypass validation**
- **Risk:** LOW
- **Module:** `journal_entry_service.dart`
- **Description:** If a sale has `totalCents = 0` and `paidAmountCents = 0`, neither the cash nor credit branch executes, so NO journal entry is created. The sale record exists without GL backing. This is an edge case (who creates a zero-total sale?) but could happen with 100% discount.
- **Suggested Fix:** Either block zero-total sales at the form level or create a zero-amount journal entry for audit trail.

### 6.9 Concurrent Sale + Return on Same Invoice

**Finding 6.9.1 — Return while sale is being voided**
- **Risk:** LOW
- **Module:** `sale_dao.dart`
- **Description:** `voidSale()` cascade-voids all returns before voiding the sale. If a return is being created simultaneously, the return could reference a sale that's about to be voided. Drift transactions provide isolation, so this should be handled by the DB, but there's no application-level lock.

---

## PART 7 — TEST COVERAGE

### 7.1 Existing Test Files (42 files found)

**Well-tested areas:**
- Auth: password service, permission service, user entity, auth bloc, role-based access, permission bypass, user form, users bloc (8 files)
- Barcode: scanner, design, validation, printer (5 files)
- Accounting: journal entry data, money calculations, validation engine, journal repository, accounts bloc, journal entries bloc (6 files)
- Core: realtime bloc, theme bloc/service, localization bloc/service, money converter, product dao, database (8 files)
- Expenses: categories bloc, form bloc (2 files)

### 7.2 CRITICAL GAPS — No Tests

| Module | Risk | Description |
|--------|------|-------------|
| **SaleRepositoryImpl** | CRITICAL | No tests for sale creation, posting, voiding, updating, payment recording, commission calculation, loyalty points |
| **PurchaseRepositoryImpl** | CRITICAL | No tests for purchase creation, posting, voiding, updating, payment recording |
| **SaleDao (post/void/return)** | CRITICAL | No tests for stock deduction, customer balance updates, return posting/voiding |
| **PurchaseDao (post/void/return)** | CRITICAL | No tests for stock addition, supplier balance updates, return posting/voiding, cost strategy (weighted avg vs last cost) |
| **JournalEntryService** | CRITICAL | No tests for any of the 15+ `record*JournalEntry()` methods. This is the MANDATORY gateway for all financial operations and has ZERO tests |
| **AccountingRepository** | HIGH | No tests for `createJournalEntry()`, `voidJournalEntry()`, `getTrialBalance()`, `reconcileBalances()`, `closeAccountingPeriod()` |
| **LedgerRebuildService** | HIGH | No tests for the destructive ledger rebuild operation |
| **CustomerRepositoryImpl** | HIGH | No tests for customer creation with opening balance, transactions, balance updates |
| **SupplierRepositoryImpl** | HIGH | No tests for supplier creation with opening balance, transactions |
| **ExpenseRepositoryImpl** | MEDIUM | No tests for expense creation/update/delete with journal entries |
| **CustomerDao** | MEDIUM | No test file found |
| **SupplierDao** | MEDIUM | No test file found |
| **EmployeeDao** | MEDIUM | No test file found (commissions, payroll) |
| **EmployeeRepositoryImpl** | MEDIUM | No tests |
| **SaleFormBloc** | MEDIUM | No tests for the complex sale form logic |
| **PurchaseFormBloc** | MEDIUM | No tests |
| **All Report Blocs** | LOW | 20+ report blocs with no tests |
| **AuditLogService** | LOW | No tests |
| **ValidationEngine** | EXISTS | Has tests but the engine itself is dead code (not wired into DI) |

### 7.3 Integration Tests

- Only 1 integration test file: `realtime_updates_test.dart`
- No end-to-end accounting flow tests (create sale → check GL → void → check GL)
- No reconciliation tests

---

## PART 8 — RELEASE READINESS REPORT

### CRITICAL BUGS (Must Fix Before Release)

| # | Description | Risk | Module | Suggested Fix |
|---|-------------|------|--------|---------------|
| C1 | **Purchase deletion does not void journal entries** — Deleting a draft purchase leaves orphaned GL entries | CRITICAL | `purchase_repository_impl.dart:293-304` | Add `voidJournalEntriesForSource()` before deletion, matching the sales pattern |
| C2 | **No COGS journal entries on sales** — Revenue recorded without matching expense, P&L inaccurate | CRITICAL | `journal_entry_service.dart` | Add COGS entry: Dr Cost of Goods Sold, Cr Inventory Asset |
| C3 | **No Inventory asset account** — Purchases may debit expense (`5100`) instead of inventory asset | CRITICAL | `journal_entry_service.dart:208-300` | Verify/create Inventory Asset account (`1200`), update purchase entries |
| C4 | **Sales allow negative stock without warning** — No guard prevents selling more than available | CRITICAL | `sale_dao.dart:269-301` | Add stock check before deduction; block or warn |

### HIGH RISK ISSUES

| # | Description | Risk | Module | Suggested Fix |
|---|-------------|------|--------|---------------|
| H1 | **Customer balance can be updated without journal entry** — `updateCustomerBalance()` is not disabled like supplier equivalent | HIGH | `customer_repository_impl.dart:121-139` | Throw `StateError` like `SupplierRepositoryImpl.updateSupplierBalance()` |
| H2 | **Void operations swallow journal voiding failures** — GL can become stale after void failures | HIGH | Multiple repository impls | Make journal voiding mandatory (let exception propagate) or add reconciliation queue |
| H3 | **JournalEntryService has ZERO test coverage** — The mandatory gateway for all financial operations is untested | HIGH | Test gap | Write comprehensive tests for all `record*` methods |
| H4 | **SaleRepositoryImpl has ZERO test coverage** — The most critical business logic is untested | HIGH | Test gap | Write integration tests covering create, post, void, payment, return flows |
| H5 | **No automatic reconciliation** — GL/sub-ledger drift can accumulate undetected | HIGH | `accounting_repository.dart` | Run reconciliation on startup and periodically |
| H6 | **ValidationEngine is dead code** — Sale/purchase level business rules are never enforced | HIGH | `validation_engine.dart` | Wire into DI and call before creating transactions |

### MEDIUM ISSUES

| # | Description | Risk | Module | Suggested Fix |
|---|-------------|------|--------|---------------|
| M1 | Invoice number generation race condition | MEDIUM | `sale_dao.dart`, `purchase_dao.dart` | Add UNIQUE constraint + retry logic |
| M2 | AP control account code may not match seeded data | MEDIUM | `accounting_repository.dart` | Use shared constants for account codes |
| M3 | Dashboard stats load all records into memory | MEDIUM | `sale_dao.dart`, `purchase_dao.dart` | Use SQL aggregation |
| M4 | Trial balance aggregates all lines in Dart | MEDIUM | `accounting_repository.dart` | Use SQL GROUP BY |
| M5 | No database encryption | MEDIUM | Database layer | Consider SQLCipher |
| M6 | No password complexity requirements | MEDIUM | `password_service.dart` | Add min length + complexity |
| M7 | No brute force protection | MEDIUM | `auth_repository.dart` | Add failed login counter + lockout |
| M8 | Missing database indexes on frequently queried columns | MEDIUM | Schema | Add indexes on source_table+source_id, status, date columns |
| M9 | Duplicate validation logic in two repositories | MEDIUM | `accounting_repository.dart` + `journal_repository_impl.dart` | Extract shared validation |
| M10 | Ledger rebuild has no crash-recovery mechanism | MEDIUM | `ledger_rebuild_service.dart` | Add rebuilding flag + auto-restart |

### MINOR ISSUES

| # | Description | Risk | Module | Suggested Fix |
|---|-------------|------|--------|---------------|
| m1 | Poor error message on FK violation (supplier/customer delete) | MINOR | Repository impls | Catch and re-throw with user-friendly message |
| m2 | Zero-amount transactions create no journal entries | MINOR | `journal_entry_service.dart` | Block at form level or create audit entry |
| m3 | Nested transactions in sale creation | MINOR | `sale_repository_impl.dart` | Refactor to avoid nested transaction calls |
| m4 | `TransactionOrchestrator` is dead code | MINOR | `transaction_orchestrator.dart` | Delete the file |
| m5 | Commission deletion is fire-and-forget during void | MINOR | `sale_repository_impl.dart` | Handle error case |

### SECURITY ISSUES

| # | Description | Risk | Module | Suggested Fix |
|---|-------------|------|--------|---------------|
| S1 | Session token uses non-cryptographic randomness | LOW | `session_service.dart` | Use `Random.secure()` |
| S2 | No database encryption | MEDIUM | Database layer | SQLCipher |
| S3 | No password complexity | MEDIUM | Auth | Add policy |
| S4 | No brute force protection | MEDIUM | Auth | Add lockout |
| S5 | No server-side authorization (acceptable for offline-first) | LOW | System-wide | Add if web API is introduced |

### PERFORMANCE RISKS

| # | Description | Risk | Module | Suggested Fix |
|---|-------------|------|--------|---------------|
| P1 | Dashboard stats fetch all records | MEDIUM | DAOs | SQL aggregation |
| P2 | Trial balance iterates all lines | MEDIUM | `accounting_repository.dart` | SQL GROUP BY |
| P3 | Missing database indexes | MEDIUM | Schema | Add indexes |
| P4 | `watchAllSalesWithCustomer()` loads unbounded data | MEDIUM | `sale_dao.dart` | Add pagination |

### MISSING TESTS (Prioritized)

| Priority | Module | Why |
|----------|--------|-----|
| P0 | `JournalEntryService` | Mandatory financial gateway, zero coverage |
| P0 | `SaleRepositoryImpl` | Most critical business flow, zero coverage |
| P0 | `PurchaseRepositoryImpl` | Second most critical flow, zero coverage |
| P0 | `AccountingRepository` (create/void/trial/reconcile) | Core accounting operations, zero coverage |
| P1 | `SaleDao` (post/void/return/payment) | Stock + balance logic, zero coverage |
| P1 | `PurchaseDao` (post/void/return/payment) | Stock + balance logic, zero coverage |
| P1 | `CustomerRepositoryImpl` | Balance + transaction logic |
| P1 | `SupplierRepositoryImpl` | Balance + transaction logic |
| P2 | `LedgerRebuildService` | Destructive operation needs safety tests |
| P2 | `ExpenseRepositoryImpl` | Financial operations |
| P3 | All report blocs | Data accuracy |

---

## SUMMARY

### Overall Health Assessment

| Area | Grade | Notes |
|------|-------|-------|
| **Double-Entry Enforcement** | A- | Multiple validation layers, small rounding edge case |
| **Transaction Atomicity** | A | Consistent use of DB transactions wrapping GL + sub-ledger |
| **Sale/Purchase Flow** | B+ | Well-structured, missing COGS/Inventory accounting |
| **Return Handling** | A | Proper reversals, quantity validation, stock guards |
| **Payment Handling** | A | Atomic, correct GL entries |
| **Void/Delete Safety** | B | One critical gap (purchase delete), void swallows errors |
| **Customer/Supplier Reconciliation** | B+ | Exists but not automated |
| **Authentication** | B+ | BCrypt + secure storage, missing brute force protection |
| **Authorization** | B | Role-based, UI-only enforcement |
| **Performance** | C+ | Several queries need optimization |
| **Test Coverage** | D | Critical financial paths have ZERO tests |
| **Security** | B | Good for offline-first, needs hardening for production |

### Release Recommendation

**NOT READY FOR RELEASE** without addressing:

1. **C1** — Purchase deletion journal entry gap (easy fix, 5 minutes)
2. **C4** — Negative stock guard (moderate fix, 1-2 hours)
3. **H3/H4** — Minimum test coverage for `JournalEntryService` and `SaleRepositoryImpl` (2-3 days)
4. **C2/C3** — COGS/Inventory accounting (significant effort, 1-2 days)

**Acceptable to defer** to post-release:
- Performance optimizations (M3, M4, P1-P4)
- Security hardening (S1-S4)
- Remaining test coverage (P2-P3)
- Minor issues (m1-m5)
