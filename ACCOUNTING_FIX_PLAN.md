# Tapix Accounting Fix Plan

## Fix 1: Make CustomerDao.createTransaction atomic (like SupplierDao)
**File:** `lib/core/database/daos/customer_dao.dart`
**Problem:** `createTransaction()` only inserts a row — does NOT update `customers.balanceCents`
**Fix:** Wrap in `transaction()`, add balance-affecting logic matching SupplierDao pattern

## Fix 2: Remove separate updateCustomerBalance calls from UI screens
**Files:**
- `lib/features/customers/presentation/screens/receive_payment_screen.dart`
- `lib/features/customers/presentation/screens/customer_profile_screen.dart`
**Problem:** Two non-atomic calls: recordTransaction + updateCustomerBalance using stale data
**Fix:** Remove the manual `updateCustomerBalance` calls — the DAO now handles it atomically

## Fix 3: Fix voidPurchase — missing supplier balance reversal
**File:** `lib/core/database/daos/purchase_dao.dart`
**Problem:** `voidPurchase()` reverses stock but NOT supplier balance or transaction
**Fix:** Add supplier_transaction reversal + balance adjustment (same pattern as voidPurchaseReturn)

## Fix 4: Fix voidPurchaseReturn — unconditional balance reversal
**File:** `lib/core/database/daos/purchase_dao.dart`
**Problem:** Always reverses balance, but postPurchaseReturn only adjusts for credit refunds
**Fix:** Only reverse balance when `refundMethod == 'credit'`

## Fix 5: Add recalculateBalance for supplier and customer (reconciliation)
**Files:**
- `lib/core/database/daos/supplier_dao.dart`
- `lib/core/database/daos/customer_dao.dart`
**Purpose:** Derive balance from SUM(transactions) — can be called to fix drift

## Fix 6: Eliminate .toDouble().round() lossy money conversions
**Files:** All files using `balanceCents.toDouble().round()`
**Fix:** Use `.toBigInt().toInt()` consistently (lossless integer extraction from Decimal)

## Fix 7: Fix console timestamp conversion warning
**File:** `lib/core/database/app_database.dart`
**Problem:** `users` table has NOT NULL on created_at/updated_at, datetime() can return NULL for already-text values
**Fix:** Add extra guard to skip rows where typeof is already 'text'

## Fix 8: Fix SupplierProfileBloc extra subscribe calls
**File:** Already fixed in previous session — verify logs show max 3 subscribe calls now
