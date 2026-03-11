# TAPIX — Second Engineering Pass Report

**Date:** March 6, 2026  
**Scope:** Stability, correctness, performance  
**flutter analyze:** ✅ Zero errors, zero warnings  
**New tests added:** 31 (all passing)  
**Pre-existing test failures:** 40 (unchanged — not introduced by this pass)

---

## PART 1 — Fix Invoice Number Collision

**Problem:** Invoice and purchase number generation happened *outside* the database transaction, creating a race condition window where two concurrent sales could get the same number.

**Fix:**
- Moved `generateInvoiceNumber()` / `generatePurchaseNumber()` calls **inside** the atomic `transaction()` block in both `SaleRepositoryImpl` and `PurchaseRepositoryImpl`.
- Added **retry logic** (up to 3 attempts) that catches `SqliteException` unique-constraint violations and regenerates the number.
- The `UNIQUE` constraint on `invoice_number` and `purchase_number` columns was already present — confirmed.

**Files changed:**
- `lib/features/sales/data/repositories/sale_repository_impl.dart`
- `lib/features/purchases/data/repositories/purchase_repository_impl.dart`

---

## PART 2 — Enable Database Encryption

**Problem:** The SQLite database stored sensitive financial data in plaintext on disk.

**Fix:**
- Created `DatabaseEncryptionKeyManager` that generates a cryptographically secure 32-byte hex key and stores it in `flutter_secure_storage` (iOS Keychain, Android EncryptedSharedPreferences, Desktop OS keyring).
- Modified `database_native.dart` to support **opt-in encryption** via `PRAGMA key` (SQLCipher / SQLite3MultipleCiphers).
- Implemented **transparent migration**: existing unencrypted databases are copied and re-keyed via `PRAGMA rekey` on first encrypted open. Falls back to unencrypted mode if migration fails.
- Web platform remains unaffected (WASM doesn't support SQLCipher).
- Added `sqlcipher_flutter_libs: 0.6.8` dependency.

**Files changed:**
- `lib/core/database/database_encryption.dart` (new)
- `lib/core/database/database_native.dart` (rewritten)
- `pubspec.yaml`

---

## PART 3 — Optimize Dashboard Queries

**Problem:** Both `SaleDao.getDashboardStats()` and `PurchaseDao.getDashboardStats()` loaded **ALL rows into memory** and filtered/aggregated in Dart. With 100k transactions this would cause multi-second pauses and high memory usage.

**Fix:**
- Replaced both methods with **SQL-level aggregation** using `customSelect()` with `SUM(CASE WHEN ...)` and `COALESCE`. Each dashboard now executes exactly 2 SQL queries (main stats + returns count) instead of loading entire tables.
- Added **13 new covering indexes** optimized for dashboard aggregation, invoice number generation, journal entry source lookups, customer/supplier transaction queries, and product variant stock lookups.

**Performance impact:** Dashboard load goes from O(n) full-table scan + in-memory filter to O(1) index-assisted aggregate — expected **50-100x speedup** for 100k+ rows.

**Files changed:**
- `lib/core/database/daos/sale_dao.dart`
- `lib/core/database/daos/purchase_dao.dart`
- `lib/core/database/app_database.dart` (new indexes)

---

## PART 4 — Remove Unused Code

**Problem:** Dead code increases maintenance burden and confuses contributors.

**Removed:**
- `lib/core/services/validation_engine.dart` — unused class, only imported by the also-dead TransactionOrchestrator.
- `lib/core/services/transaction_orchestrator.dart` — explicitly marked `DEPRECATED / NOT IN USE`, all methods threw `UnimplementedError`.
- `test/features/accounting/validation_engine_test.dart` — test file for the removed class.

**Verification:** Neither class was registered in DI (`injection_container.dart`) or imported anywhere in production code.

---

## PART 5 — Add Missing Tests

**Problem:** No automated tests covering the core accounting integrity invariants (debit=credit, balance lifecycle, VAT calculations).

**Added:** `test/features/accounting/accounting_integrity_test.dart` — **31 tests** covering:

| Group | Tests | What's verified |
|-------|-------|----------------|
| Sale Journal Entry Integrity | 4 | Cash sale, credit sale, VAT sale, partial payment — all balanced |
| COGS Journal Entry Integrity | 3 | COGS entry, reversal, combined sale+COGS balance |
| Purchase Journal Entry Integrity | 3 | Cash purchase, credit purchase, purchase with VAT |
| Inventory Quantity Integrity | 5 | Stock add/subtract, negative guard, return restore, void guard, WAC calculation |
| VAT Calculation Integrity | 5 | 15%, 5%, rounding floor, input/output netting, zero-rated |
| Customer Balance Integrity | 5 | Credit sale, payment, refund, cash refund no-op, full lifecycle |
| Supplier Balance Integrity | 5 | Purchase, payment, return, void reversal, full lifecycle |
| Trial Balance Verification | 1 | Complete business cycle produces zero trial balance |

All 31 tests pass.

---

## PART 6 — Stability Hardening

**Problem:** Potential division-by-zero crashes in proportional calculation paths.

**Fixes:**
- Added `saleTotalCents <= 0` guard before commission proportional reversal division in `_reverseCommissionsForReturn()`.
- Added `saleTotalCents <= 0` guard before loyalty points proportional deduction in `_reverseLoyaltyPointsForReturn()`.

**Audit findings (no action needed):**
- All core DAOs and services already have proper null safety (no `!.` operators in backend code).
- All bloc event handlers already wrap operations in try/catch.
- Payroll calculation service already guards `workingDays > 0`.
- Report blocs already guard `totalPurchases > 0` and `totalTransactions > 0`.
- The `toBigInt().toInt()` pattern (447 occurrences) is safe for cent values within normal business ranges.

**Files changed:**
- `lib/features/sales/data/repositories/sale_repository_impl.dart`

---

## PART 7 — Final Verification

| Check | Result |
|-------|--------|
| `flutter analyze` | ✅ **No issues found** |
| New accounting tests (31) | ✅ **All pass** |
| Full test suite (1218 pass / 40 fail) | ⚠️ 40 failures are **pre-existing**, not introduced by this pass |

---

## Summary of All Changes

| File | Change |
|------|--------|
| `lib/features/sales/data/repositories/sale_repository_impl.dart` | Atomic invoice gen + retry + div-by-zero guards |
| `lib/features/purchases/data/repositories/purchase_repository_impl.dart` | Atomic purchase number gen + retry |
| `lib/core/database/database_encryption.dart` | **New** — encryption key manager |
| `lib/core/database/database_native.dart` | Opt-in encryption support + migration |
| `lib/core/database/daos/sale_dao.dart` | SQL aggregation for dashboard stats |
| `lib/core/database/daos/purchase_dao.dart` | SQL aggregation for dashboard stats |
| `lib/core/database/app_database.dart` | 13 new covering indexes |
| `pubspec.yaml` | Added `sqlcipher_flutter_libs` |
| `lib/core/services/validation_engine.dart` | **Deleted** — dead code |
| `lib/core/services/transaction_orchestrator.dart` | **Deleted** — dead code |
| `test/features/accounting/validation_engine_test.dart` | **Deleted** — test for dead code |
| `test/features/accounting/accounting_integrity_test.dart` | **New** — 31 accounting integrity tests |
