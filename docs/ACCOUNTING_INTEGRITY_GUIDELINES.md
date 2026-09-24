# Accounting Integrity Guidelines

> **For Developers and AI Agents**
> **Version**: 2.1 (post-Phase-11 compliance hardening)
> **Last Updated**: May 2026
> **Status**: MANDATORY — Follow for all financial implementations

---

## 🔒 Canonical Single Sources of Truth (SoT)

The 10-phase scattered-calculation-logic migration is complete (see
[`adr/0001-pricing-engines-as-sot.md`](adr/0001-pricing-engines-as-sot.md) §7).
Before adding ANY arithmetic that touches money, qty, tax, discount,
balance, cost, commission, loyalty, payroll, or stock — **consume the
SoT below; never re-implement it**. The visual map lives in
[`SOURCE_OF_TRUTH_MAP.md`](SOURCE_OF_TRUTH_MAP.md).

### Write-side SoTs (sole writers of their persisted column)

| Domain                                              | Sole writer                                                   |
|-----------------------------------------------------|---------------------------------------------------------------|
| `accounts.balance_cents`                            | `AccountingRepository._updateAccountBalance` (via `createJournalEntry`) |
| `customers.balance_cents`                           | `BalanceService.adjustCustomerBalance`                        |
| `suppliers.balance_cents`                           | `BalanceService.adjustSupplierBalance`                        |
| Opening-balance party adjustments                   | `Customer/SupplierRepository.adjustOpeningBalance`            |
| Invoice pricing totals (sale + purchase)            | `InvoicePricingEngine.compute`                                |
| Line-level pricing totals                           | `LineItemPricingEngine.compute`                               |
| Return-line proportional reversals                  | `ReturnCalculationService.computeProportionalReturn`          |
| Return-rollup aggregates                            | `ReturnCalculationService.aggregate`                          |
| `commissions` rows                                  | `CommissionService`                                           |
| `loyalty_point_transactions` + `customers.loyalty_points_balance` | `LoyaltyPointsService`                          |
| `products`/`product_variants.stock_quantity`        | `StockService`                                                |
| `product_batches.remaining_quantity`                | `BatchService`                                                |
| `products`/`product_variants.cost_cents`            | `ProductCostService`                                          |
| `customer_credit_notes.balance_cents`              | `CustomerCreditNoteService`                                   |
| Inventory adjustment (shrinkage/gain/reval/opening) | `InventoryAdjustmentService`                                  |
| Payroll calculation                                 | `PayrollCalculationService`                                   |
| Fiscal-period closure guard on every JE             | `FiscalPeriodService.assertOpen` (called from `AccountingRepository.createJournalEntry`) — Phase 11.1 |
| Pricing-engine version / tax-inclusive / rounding-mode header snapshot | `PricingSnapshot` + `withPricingSnapshot(taxInclusive:)` — Phase 11.2 |
| Single-currency invariant on JE lines               | `AccountingRepository.createJournalEntry` — rejects mixed-currency entries before tx opens — Phase 11.3a |
| Sensitive-accounting permissions                    | `Permissions.voidJournalEntry` / `closeFiscalPeriod` / `reopenFiscalPeriod` (owner-only by default) — Phase 11.3b |
| Pre-flight integrity check on every sale/purchase void | `VoidImpactAnalyzer.analyzeSaleVoid` / `analyzePurchaseVoid` (called from repository before any state change) — Phase 12 |
| Cascade-void of linked-return JEs inside the parent void tx | `SaleDao.voidSale` / `PurchaseDao.voidPurchase` with `journalEntryService:` argument — Phase 12 |
| Adjustment-return cap ("ever sold/purchased per party per product") | `AdjustmentReturnDao` four cap queries, all filtered by `sales.status = 'completed'` / `purchases.status = 'posted'` — Phase 12 |

### Read-side SoTs (reporting, no DB mutation)

| Concern                                             | Sole owner                                                    |
|-----------------------------------------------------|---------------------------------------------------------------|
| Account-type signing for reports                    | `TrialBalance.totalForType` / `TrialBalanceItem.naturalBalanceCents` |
| Ledger running-balance loop                         | `LedgerRunningBalance`                                        |
| Tax-rate snapshot recovery                          | `TaxCalculationService.recoverRateBps`                        |
| Ratio / percent display                             | `RatioHelper.percent` / `RatioHelper.bpsToPercent`            |
| Text → cents (with sign)                            | `MoneyInputParser.parseSignedOrZero`                          |
| Text → cents (magnitude only)                       | `MoneyInputParser.parseOrZero` / `parse`                      |
| `%` ↔ `¢` conversion                                | `DiscountConverter`                                           |
| Original cost / price / wholesale snapshot          | `OriginalPriceResolver`                                       |

### Banned patterns (enforced by static guard tests)

| Banned pattern                                                                 | Required SoT                  |
|--------------------------------------------------------------------------------|-------------------------------|
| `(double.parse(...) * 100).round()`                                            | `MoneyInputParser.parseOrZero` |
| `runningBalance += amountCents` outside the helper                              | `LedgerRunningBalance`         |
| `creditCents - debitCents` (or inverse) signing outside `TrialBalance`          | `TrialBalanceItem.naturalBalanceCents` |
| `(num / den) * 100` inline percentage                                           | `RatioHelper.percent`          |
| `bps / 100` for display                                                         | `RatioHelper.bpsToPercent`     |
| Direct `customer_dao.updateCustomerBalance` / `supplier_dao.updateSupplierBalance` | `BalanceService`           |
| Raw `UPDATE accounts SET balance_cents` SQL anywhere in `lib/`                  | `AccountingRepository.createJournalEntry` |
| Inline tax-rate recovery `(taxOnLine * 10000 / subtotal).round()`               | `TaxCalculationService.recoverRateBps` |
| Inline `(subtotal * pct / 100).round()` for line/invoice totals                 | `LineItemPricingEngine` / `InvoicePricingEngine` |
| Inserting a sale/purchase/return header companion without snapshot columns      | `withPricingSnapshot(taxInclusive: …)` on the companion (Phase 11.2) |
| Posting a JE without `FiscalPeriodService.assertOpen(entryDate)` upstream       | `AccountingRepository.withFiscalPeriodGuard(...)` constructor (Phase 11.1) |
| Constructing a JE whose lines mix currencies                                    | Caller must convert to a single currency before `createJournalEntry` (Phase 11.3a) |
| Hard-coded role checks for void-JE / period close / period reopen               | `Permissions.voidJournalEntry` / `closeFiscalPeriod` / `reopenFiscalPeriod` (Phase 11.3b) |
| Calling `voidSale` / `voidPurchase` on a repository / DAO without first asking `VoidImpactAnalyzer` | `sale_repository_impl.voidSale` / `purchase_repository_impl.voidPurchase` (analyzer + `VoidBlockedByImpactException`) — Phase 12 |
| Calling `SaleDao.voidSale` / `PurchaseDao.voidPurchase` from a repository path without passing `journalEntryService:` | Repository layer must thread the service so the cascade reverses linked-return JEs — Phase 12 |
| Computing an "ever sold/purchased" cap from `sales` / `purchases` without a `status` filter | All four cap queries in `AdjustmentReturnDao` (use them as the template for any new cap) — Phase 12 |

Static guard tests:

- [`test/architecture/scattered_patterns_guard_test.dart`](../test/architecture/scattered_patterns_guard_test.dart)
- [`test/core/database/app_database_single_writer_guard_test.dart`](../test/core/database/app_database_single_writer_guard_test.dart)

Phase 11 invariant tests:

- [`test/integration/phase11_1_fiscal_period_je_guard_test.dart`](../test/integration/phase11_1_fiscal_period_je_guard_test.dart)
- [`test/integration/phase11_2_pricing_snapshot_stamping_test.dart`](../test/integration/phase11_2_pricing_snapshot_stamping_test.dart)
- [`test/integration/phase11_3a_single_currency_invariant_test.dart`](../test/integration/phase11_3a_single_currency_invariant_test.dart)
- [`test/features/auth/data/services/phase11_3b_granular_accounting_permissions_test.dart`](../test/features/auth/data/services/phase11_3b_granular_accounting_permissions_test.dart)

Phase 12 invariant tests:

- [`test/integration/void_corruption_regression_test.dart`](../test/integration/void_corruption_regression_test.dart) — 8 tests pinning Fix A (status filter on adjustment-return caps), Fix B (cascade-void of linked-return JEs), and Fix C (`VoidImpactAnalyzer` entanglement detection) for both sale and purchase sides.

---

## 🎯 Purpose

This document provides quick-reference guidelines for implementing any feature that involves money, balances, or financial transactions in Tapix. Following these guidelines ensures **ZERO accounting errors**.

---

## ⚡ Quick Reference Card

### DO ✅

| Action | How |
|--------|-----|
| Store money | Integer cents (`int priceInCents = 1999`) |
| Access accounting data | Through `AccountingRepository` |
| Execute transactions | Through `TransactionOrchestrator` |
| Validate before commit | Use `ValidationEngine` |
| Log all changes | Use `AuditLogService` |
| Change balances | Create journal entries |
| Cancel transactions | Create reversal entries |
| Test calculations | 100% unit test coverage |

### DON'T ❌

| Action | Why |
|--------|-----|
| Use `double` for money | Floating point errors |
| Direct database access | Bypasses validation |
| Update posted entries | Breaks audit trail |
| Skip validation | Data corruption |
| Skip audit logging | Compliance issues |
| Manual balance updates | Breaks double-entry |

---

## 📋 Implementation Checklist

Copy this checklist into your story when implementing financial features:

```markdown
## Accounting Integrity Checklist

### Money Handling
- [ ] All amounts stored as integer cents
- [ ] No floating-point calculations for money
- [ ] CurrencyService used for display formatting

### Transaction Integrity
- [ ] Changes go through AccountingRepository
- [ ] TransactionOrchestrator used for operations
- [ ] Journal entries created for balance changes
- [ ] Atomic transaction wraps all related changes
- [ ] Void/reversal pattern used (no direct updates)

### Validation
- [ ] ValidationEngine checks run before commit
- [ ] Business rules enforced
- [ ] Error messages are clear and actionable

### Audit Trail
- [ ] AuditLogService records all changes
- [ ] Old and new values captured
- [ ] User and timestamp recorded

### Testing
- [ ] Unit tests for all calculations
- [ ] Integration tests for transaction flow
- [ ] Reconciliation passes after operation
```

---

## 🔢 Money Calculation Patterns

### Basic Calculations

```dart
// Addition
int total = price1Cents + price2Cents;

// Multiplication
int lineTotal = priceInCents * quantity;

// Percentage (use integer division)
int discount = (subtotalCents * discountPercent) ~/ 100;

// Tax with basis points (1500 = 15%)
int tax = (amountCents * taxRateBasisPoints) ~/ 10000;
```

### Complete Sale Calculation

```dart
int calculateSaleTotal({
  required List<SaleItem> items,
  required int discountPercent,
  required int taxRateBasisPoints,
}) {
  // 1. Calculate subtotal
  int subtotalCents = items.fold(0, (sum, item) => 
    sum + (item.priceInCents * item.quantity));
  
  // 2. Calculate discount
  int discountCents = (subtotalCents * discountPercent) ~/ 100;
  
  // 3. Calculate taxable amount
  int taxableAmount = subtotalCents - discountCents;
  
  // 4. Calculate tax
  int taxCents = (taxableAmount * taxRateBasisPoints) ~/ 10000;
  
  // 5. Calculate total
  return taxableAmount + taxCents;
}
```

---

## 🏦 Transaction Patterns

### Sale Transaction

```dart
final result = await transactionOrchestrator.executeSale(
  sale: SaleTransactionData(
    totalCents: totalCents,
    subtotalCents: subtotalCents,
    discountCents: discountCents,
    taxCents: taxCents,
    customerId: customerId,
    currencyId: currencyId,
    isCreditSale: isCreditSale,
    items: items,
  ),
  userId: currentUserId,
);

if (result.isSuccess) {
  // Sale created successfully
  final saleId = result.entityId;
} else {
  // Handle errors
  showError(result.errorMessage);
}
```

### Payment Transaction

```dart
final result = await transactionOrchestrator.recordCustomerPayment(
  customerId: customerId,
  amountCents: amountCents,
  paymentMethod: 'cash', // or 'card', 'bank_transfer'
  currencyId: currencyId,
  userId: currentUserId,
);
```

### Void Transaction

```dart
final result = await transactionOrchestrator.voidSale(
  saleId: saleId,
  reason: 'Customer requested cancellation',
  userId: currentUserId,
);
```

---

## 📊 Journal Entry Patterns

### Simple Two-Line Entry

```dart
await accountingRepository.createJournalEntry(
  entryData: JournalEntryData.simple(
    description: 'Sale #123',
    debitAccountId: cashAccountId,      // 1000 - Cash
    creditAccountId: revenueAccountId,  // 4000 - Revenue
    amountCents: 10000,
    currencyId: currencyId,
    entryType: 'sale',
    sourceTable: 'sales',
    sourceId: saleId,
    autoPost: true,
  ),
  userId: userId,
);
```

### Multi-Line Entry

```dart
await accountingRepository.createJournalEntry(
  entryData: JournalEntryData(
    description: 'Complex transaction',
    lines: [
      JournalEntryLineData(
        accountId: cashAccountId,
        debitCents: 8500,
        creditCents: 0,
        currencyId: currencyId,
      ),
      JournalEntryLineData(
        accountId: receivablesAccountId,
        debitCents: 1500,
        creditCents: 0,
        currencyId: currencyId,
      ),
      JournalEntryLineData(
        accountId: revenueAccountId,
        debitCents: 0,
        creditCents: 10000,
        currencyId: currencyId,
      ),
    ],
    autoPost: true,
  ),
  userId: userId,
);
```

---

## 🧪 Testing Patterns

### Unit Test for Calculations

```dart
test('calculates sale total correctly', () {
  final total = calculateSaleTotal(
    items: [
      SaleItem(priceInCents: 1000, quantity: 2),
      SaleItem(priceInCents: 500, quantity: 3),
    ],
    discountPercent: 10,
    taxRateBasisPoints: 1500,
  );
  
  // Subtotal: 2000 + 1500 = 3500
  // Discount: 3500 * 10% = 350
  // After discount: 3150
  // Tax: 3150 * 15% = 472
  // Total: 3150 + 472 = 3622
  expect(total, equals(3622));
});
```

### Integration Test for Transaction

```dart
test('sale creates correct journal entries', () async {
  final result = await transactionOrchestrator.executeSale(
    sale: testSaleData,
    userId: testUserId,
  );
  
  expect(result.isSuccess, isTrue);
  
  // Verify journal entries
  final entries = await accountingRepository
      .getJournalEntriesForSource('sales', result.entityId!);
  
  expect(entries.length, greaterThanOrEqualTo(1));
  
  // Verify trial balance
  final trialBalance = await accountingRepository.getTrialBalance();
  expect(trialBalance.isBalanced, isTrue);
});
```

---

## 🔍 Reconciliation

### Run Reconciliation Check

```dart
final result = await accountingRepository.reconcileBalances();

if (!result.isHealthy) {
  for (final issue in result.issues) {
    logger.error('Reconciliation issue: $issue');
  }
}
```

### What Gets Checked

1. **Trial Balance** - Total debits must equal total credits
2. **Customer Balances** - Sum must match Accounts Receivable
3. **Supplier Balances** - Sum must match Accounts Payable
4. **Inventory Value** - Must match Inventory account

---

## 📁 Key Files Reference

| File | Purpose |
|------|---------|
| `lib/features/accounting/data/repositories/accounting_repository.dart` | Single source of truth |
| `lib/core/services/transaction_orchestrator.dart` | Transaction coordination |
| `lib/core/services/validation_engine.dart` | Pre-commit validation |
| `lib/core/services/audit_log_service.dart` | Change tracking |
| `lib/features/accounting/domain/models/journal_entry_data.dart` | Entry data models |
| `lib/core/database/tables/accounting.dart` | Database schema |
| `project-context.md` | Project-wide patterns |
| `_bmad-output/planning-artifacts/TAPIX_ACCOUNTING_INTEGRITY_ARCHITECTURE.md` | Full architecture |

---

## ⚠️ Common Mistakes to Avoid

### 1. Direct Balance Updates

```dart
// ❌ WRONG
customer.balanceCents += saleTotal;
await db.update(customers).replace(customer);

// ✅ CORRECT
await transactionOrchestrator.executeSale(...);
// Balance updated automatically via journal entries
```

### 2. Using Double for Money

```dart
// ❌ WRONG
double price = 19.99;
double total = price * quantity; // FLOATING POINT ERRORS!

// ✅ CORRECT
int priceInCents = 1999;
int totalCents = priceInCents * quantity; // EXACT
```

### 3. Modifying Posted Entries

```dart
// ❌ WRONG
entry.amountCents = newAmount;
await db.update(journalEntries).replace(entry);

// ✅ CORRECT
await accountingRepository.voidJournalEntry(
  entryId: entry.id,
  reason: 'Correction needed',
  userId: userId,
);
// Then create new correct entry
```

### 4. Skipping Validation

```dart
// ❌ WRONG
await db.into(sales).insert(saleData);

// ✅ CORRECT
final validation = validationEngine.validateSale(saleData);
if (!validation.isValid) {
  throw ValidationException(validation.errors);
}
await transactionOrchestrator.executeSale(...);
```

---

## � Phase 13 invariants (post-field-bug-fix, 2026-05-17)

### New SoT rows
| Concern | Single source of truth | Notes |
|---|---|---|
| Supplier discount JE (unallocated rebate) | `JournalEntryService.recordDirectSupplierDiscountJournalEntry` | Posts Dr 2000 / Cr **4900 Purchase Discounts Earned** (revenue). MUST NOT touch 1200 Inventory. |
| Customer discount JE | `JournalEntryService.recordDirectCustomerDiscountJournalEntry` | Posts Dr **5500 Discounts Given** / Cr 1100 AR. MUST NOT touch 1200. |
| Linked-return cap (sale) | `SaleDao.getReturnedQuantity` | Returns `linked_sum + qty_returned_adjustment` so an adjustment return shrinks the linked cap. |
| Linked-return cap (purchase) | `PurchaseDao.getReturnedQuantity` | Symmetric. |
| Returnable-qty UI | `UnifiedReturnService._getSale/PurchaseReturnableItems` | `already_returned` sub-SELECT includes both linked sum AND adjustment counter. |

### New banned patterns
- ❌ Crediting **1200 Inventory** on a transaction that does NOT move stock layers (`product_variants.stock_quantity` / `stock_batches`). Examples that previously did this and are now fixed: `supplier_discount`. The only legitimate Cr 1200 paths are: COGS posting on sale, purchase-return (with matching stock-out), inventory shrinkage / revaluation (with matching stock movement).
- ❌ Computing a sale_item's "already returned" qty by looking ONLY at `sale_return_items` (linked-side). Adjustment returns mutate `sale_items.qty_returned_adjustment` and MUST be included.
- ❌ Computing a purchase_item's "already returned" qty by looking ONLY at `purchase_return_items`. Symmetric.

### Pinned by tests
- `test/integration/supplier_discount_inventory_drift_test.dart`
- `test/integration/customer_discount_inventory_drift_test.dart`
- `test/integration/linked_return_cap_after_adjustment_test.dart`

---

## Phase 14 — Cheque Lifecycle (Minimal-Risk Slice, 2026-05-17)

### New SoTs
| Concern | Single source of truth | Notes |
|---|---|---|
| Cheque confirmation state (collected / paid / bounced / cancelled) | `ChequeConfirmationDao` (`lib/core/database/daos/cheque_confirmation_dao.dart`) | DB-backed; natural key `(source_table, source_id)` UNIQUE; replaces all SharedPreferences-based dismissals. |
| Linked sale-return cheque due date | `sale_returns.due_date` | Added in migration 10056. NULL for non-cheque refunds; required when `refund_method='cheque'` (form-level invariant). |
| Linked purchase-return cheque due date | `purchase_returns.due_date` | Symmetric. |
| Dashboard cheque feed (six sources) | `ChequeRemindersSection` (`lib/features/dashboard/presentation/widgets/cheque_reminders_section.dart`) | UNION over sales, purchases, sale_returns, purchase_returns, sale_return_adjustments, purchase_return_adjustments — filtered by `status NOT IN ('voided','draft')` and resolved-state lookup through `ChequeConfirmationDao`. |

### New banned patterns
- ❌ Writing cheque "dismissed / collected / paid" flags to `SharedPreferences`, in-memory caches, or any non-DB store. Confirmation state is DB-authoritative via `ChequeConfirmationDao`.
- ❌ Surfacing cheque reminders by reading fewer than the six canonical source tables. Any new flow that accepts a cheque MUST either join one of the six tables or extend the UNION (and the integration test below).
- ❌ Persisting a linked sale_return / purchase_return with `refund_method='cheque'` and `due_date=NULL`. The form bloc's `isChequeMissingDueDate` invariant must hold at submit time.

### Pinned by tests
- `test/core/database/daos/cheque_confirmation_dao_test.dart` (13 tests — DAO contract).
- `test/integration/cheque_reminder_six_sources_test.dart` (4 tests — schema + UNION + voided exclusion + natural-key lookup).

### Explicitly deferred (NOT killed)
The full IAS 7 / QuickBooks-style two-step cheque JE pipeline (`1020 Cheques in Hand` on issue → `1010 Bank` on clear, with symmetric `2030 Cheques Issued` on the outgoing side) is intentionally NOT implemented in Phase 14. Current JE policy (Dr/Cr `1010` directly at invoice post-time) is preserved untouched. Revisit when field users confirm the minimal slice meets their reconciliation needs.

---

## Phase 14.2 — Discount-Mode Toggle Symmetry (2026-05-18)

### New SoTs (state-level, not DB)
| Concern | Single source of truth | Notes |
|---|---|---|
| Purchase-form discount-mode mutual-exclusivity at the **state** level | `PurchaseFormBloc._onDiscountModeChanged` (`lib/features/purchases/presentation/bloc/purchase_form_bloc.dart`) | Switching INTO `DiscountMode.invoice` MUST wipe `discountCents` on every `state.items[i]`. Switching INTO `DiscountMode.perItem` MUST wipe `invoiceDiscountCents` and `invoiceDiscountPercent`. |
| Sale-form discount-mode mutual-exclusivity at the **state** level | `SaleFormBloc._onDiscountModeChanged` (`lib/features/sales/presentation/bloc/sale_form_bloc.dart`) | Symmetric to the purchase side; no `invoiceDiscountPercent` field on the sale state. |
| Reference implementation | `SaleAdjReturnFormBloc._onDiscountModeChanged` (`lib/features/sales/presentation/bloc/sale_adj_return_form_bloc.dart`) | Phase-11 original; pattern that Phase 14.2 mirrors into the two main forms. |

### New banned patterns
- ❌ Discount-mode handler that only zeroes `invoiceDiscountCents` / `invoiceDiscountPercent` while leaving per-line `discountCents` populated on `state.items`. The pricing-engine `overrideDiscount` mask is defence-in-depth — STATE is the SoT, the engine mask is the seatbelt.
- ❌ "Soft mode" buffers that preserve discounts across mode switches for restore-on-back-toggle. The two modes are mutually exclusive; preserving the inactive mode's input causes the user-visible "double-discount the user can't notice" bug class.
- ❌ Reading `state.itemDiscountCents` (or its sale-side twin) and treating the result as authoritative when `state.discountMode == invoice`. The getter is a raw sum and is only meaningful when `state.discountMode == perItem`. For the cross-mode total, use `state.totalDiscountCents` (or `state.pricing.totalDiscount`).

### Pinned by tests
- `test/features/purchases/purchase_form_discount_mode_toggle_test.dart` (4 tests — perItem→invoice clear, invoice→perItem clear, back-and-forth no-resurrect, engine-mask sanity).
- `test/features/sales/sale_form_discount_mode_toggle_test.dart` (4 tests — symmetric for `SaleFormBloc`).

### Explicitly deferred (NOT killed)
Confirmation dialog before clearing per-line discounts on mode switch — the existing handler already destroys the invoice-level discount silently and symmetrically; adding a one-sided confirm step would be inconsistent. Re-evaluate only if field reports request it. A historical-data sweep is also unnecessary: posted invoices already reflect the engine-masked output (per-line=0 in invoice mode), so no books are corrupted by the prior leaky state.

---

## Phase 15 — Cheque Lifecycle JE Wiring + Batch-Ledger Valuation (2026-05-18)

### New SoTs
| Concern | Single source of truth | Notes |
|---|---|---|
| Cheque-lifecycle transitions that change books (cleared / bounced / cancelled) | `ChequeLifecycleService` (`lib/core/services/cheque_lifecycle_service.dart`) | The DAO `ChequeConfirmationDao.confirm` writes only the sidecar row; the service is the ONLY caller allowed to flip `pending → cleared / bounced / cancelled` from the UI. Delegates the actual money work to `PurchaseRepository.recordPayment/deletePayment` and `SaleRepository.recordPayment/deletePayment` — no new accounting logic. Runs inside a single Drift transaction. |
| Cleared-cheque → payment-row linkage | `cheque_confirmations.cleared_payment_id` (nullable INT, migration 10057) | Polymorphic FK; interpretation is driven by `source_table` (`sale` → `sale_payments.id`, `purchase` → `purchase_payments.id`). NULLed on `cleared → bounced / cancelled / re-open` so a stale pointer can never re-settle a different cheque later. |
| Inventory valuation (Σ stock-at-cost) for the Reconciliation & Health screen | `JournalLocalDatasourceImpl.getTotalInventoryValueCents` (`lib/features/accounting/data/datasources/journal_local_datasource.dart`) | New formula: **prefer the batch ledger** when active `product_batches` rows exist for a variant. Fall back to `variant.stock × variant.cost_cents` only when there are no active batches for that variant. Third branch for legacy products with no variants and no batches. WAC happy-path unchanged on pre-batch DBs. |

### New banned patterns
- ❌ Calling `ChequeConfirmationDao.confirm(status: cleared)` directly from a UI handler. The lifecycle row will say "cleared" but the supplier/customer balance, AR/AP totals, and the GL stay untouched — exactly the May 2026 P0. UI MUST go through `ChequeLifecycleService.markCleared/markBounced/markCancelled`.
- ❌ Manually inserting a `purchase_payments` / `sale_payments` row when clearing a cheque, bypassing `repo.recordPayment`. The repository's `recordPayment` is the SoT for: payment-row INSERT, `paid_amount_cents` UPDATE, supplier/customer balance adjustment, and the Dr/Cr Bank JE. Any bypass re-introduces the same field-reported drift on a new code path.
- ❌ Reconciliation / health-check queries that read `variant.cost_cents` as the per-unit valuation basis for FIFO / batch / batch_expiry products. `variant.cost_cents` is a DISPLAY value (latest paid unit cost from `product_cost_service.dart`). For accounting valuation, sum `product_batches.unit_cost_cents × remaining_quantity` for active batches. The 990¢ false-positive that triggered Phase 15 was exactly this bug class.
- ❌ Stamping a `cleared_payment_id` on a return-source confirmation row (`sale_return`, `purchase_return`, `sale_return_adjustment`, `purchase_return_adjustment`). The refund JE was already booked when the return was posted; the cheque clearance does not trigger a second payment row.

### Pinned by tests
- `test/core/services/cheque_lifecycle_service_test.dart` (9 tests — settlement on cleared, idempotency, return-source no-op, cleared→bounced reversal, cleared→cancelled reversal, pending→bounced no-reversal, bounce-reason validation, missing-source exception).
- `test/integration/inventory_valuation_batch_ledger_test.dart` (5 tests — FIFO multi-batch field case, WAC variant fallback, no-variant fallback, inactive-batch exclusion, mixed-mode sum).
- Schema-version pins: `test/integration/production_hardening_test.dart` + `test/integration/fifo_phase_6_4_test.dart` (both at 10057).

### Explicitly deferred (NOT killed)
- Two-step IAS 7 cheque pipeline (`1020 Cheques in Hand` / `2030 Cheques Issued`). The one-step model (Dr/Cr Bank directly on clear) matches QuickBooks/Xero defaults and was the minimum slice to close the field bug. Re-open trigger: cash-flow statement compliance requirement.
- Bounce-fee bank-charges JE, replace-cheque workflow, per-cheque metadata (number / bank / branch). Trigger: user / regulatory request.
- Historical drift remediation: the formula fix is data-free (re-open Reconciliation & Health → drift disappears). For unsettled cheques predating Phase 15, the user clicks "Confirm Paid" again post-upgrade and the lifecycle service records the missing payment + JE atomically — no DB sweep required.

---

## Phase 15.1 — Purchase Form Variant/No-Variant Unit-Cost Parity (2026-05-18)

### Rule
Every form that auto-fills a "user-typed cost" field (purchase line items, variant edit dialog, supplier-side rebate forms) MUST resolve the displayed value via `lastPurchasePriceCents ?? costCents`. The first branch is the GROSS supplier reference price (what the user typed on the most recent posted purchase line); the fallback handles legacy rows pre-migration 10055.

`cost_cents` alone is the IAS-2 NET basis — already netted of any per-line discount by `PurchaseDao.postPurchase`. Surfacing it directly in the UI causes the variant-vs-no-variant asymmetry that the May 2026 field report uncovered (variant lines silently dropping from `$100` to `$99` while no-variant peers of the same product kept showing `$100`).

### New banned patterns
- ❌ Reading `variant.costCents` (or `product.costCents`) directly as the auto-fill value in any "add line item" / "scan barcode" / "edit purchase line" code path. The two columns can legitimately diverge (`cost_cents` is the post-discount NET basis maintained by `PurchaseDao.postPurchase`; `last_purchase_price_cents` is the gross supplier reference price). UI MUST prefer the gross column with a NET fallback.
- ❌ Adding a `hasVariants` branch to the unit-cost auto-fill. The two paths must be symmetric: variants read `variant.lastPurchasePriceCents ?? variant.costCents`, no-variants read `product.lastPurchasePriceCents ?? product.costCents`. Same shape, same fallback semantics.
- ❌ Mirroring this gross-vs-net split into the LineItemPricingEngine, the tax engine, or any persisted total. The engine is intentionally unaware of supplier reference prices — it only sees the user-typed `unitCostCents` and the per-line / invoice discount. Stamping `last_purchase_price_cents` is a side-effect of `postPurchase` and stays in the DAO.

### Pinned by tests
- `test/features/purchases/purchase_form_variant_unit_cost_parity_test.dart` (6 tests — variant auto-fill prefers GROSS; no-variant auto-fill prefers GROSS; legacy fallback for both shapes; variant and no-variant lines produce identical per-line totals and tax for the same supplier reference price; full 3-line field-report scenario yields $300 / $3 / $303).

### Explicitly deferred (NOT killed)
- Extracting the `lastPurchasePriceCents ?? costCents` pattern into a shared helper. Six occurrences in one screen file; an abstraction at this point obscures the IAS-2-vs-supplier-reference split that the inline comments document. Re-open trigger: a third surface (e.g. sale form, quotation form) starts needing the same resolver.
- Showing both prices (GROSS and NET) in the picker. The current UX collapses to the user's intended view (what they typed last time). A power-user toggle is a YAGNI candidate until requested.

---

## Phase 15.2 — Void integrity: payment-JE reversal + WAC batch cleanup (2026-05-18)

### Rule
Voiding a sale or purchase MUST reverse the JEs of EVERY downstream side-effect row whose own JE was posted, AND deactivate EVERY `product_batches` row created by the source — not only those whose product currently uses FIFO costing.

Concretely, in the same Drift transaction that flips `status='voided'`:
1. Enumerate `purchase_payments` (or `sale_payments`) for the source and call `JournalEntryService.voidJournalEntriesForSource(sourceTable: 'purchase_payments'|'sale_payments', sourceId: …)` for each. This closes the GL ↔ subsidiary-ledger gap that opens when a cheque has already cleared (Phase 15) but the parent invoice is later voided.
2. For purchases, deactivate `product_batches` WHERE `purchase_id = :id AND source = 'purchase'` UNCONDITIONALLY. `PurchaseDao.postPurchase` creates a batch for every tracked product regardless of `costing_method`; gating deactivation on `_isFifoProduct(...)` strands the WAC/standard batch rows and double-counts inventory in `getTotalInventoryValueCents` (which sums active batches first).

### New banned patterns
- ❌ Reversing only the parent invoice JE on void without iterating the payment table. After Phase 15 the cheque-clearance path writes a posted payment JE via `repo.recordPayment`; any void that ignores `purchase_payments`/`sale_payments` leaves an orphan posted JE → exact AP/AR vs GL drift equal to the cleared cheque amount.
- ❌ Conditioning batch deactivation on costing method (`_isFifoProduct`, `costing_method == 'fifo'`, `inventory_tracking_type == 'batch_expiry'`, …). Batch creation is unconditional for tracked products, so deactivation MUST be unconditional too. Untracked products simply match zero rows — the UPDATE is a safe no-op.

### Pinned by tests
- `test/integration/void_payment_je_and_wac_batch_test.dart` (6 tests — purchase void reverses ALL `purchase_payments` JEs, sale void reverses ALL `sale_payments` JEs, AP GL balance returns to pre-purchase after voiding a cleared-cheque PO, voiding a tracked-WAC purchase deactivates its batch row, voiding a tracked-FIFO/batch_expiry purchase still deactivates its batch, Σ(active batch × cost) matches `variant.stock × variant.cost` after void).

### Explicitly deferred (NOT killed)
- **Cheque-detail UX** (cheque amount that may legitimately differ from invoice total, cheque date, cheque number, bank, branch). User explicitly requested this. It is a NEW feature, not a fix for the field-reported drift — the GL bugs above existed regardless of whether the cheque equals the invoice. Implementing requires: (a) a `cheque_details` sidecar table (number/bank/branch/amount/issue-date/due-date), (b) UI in the cheque-payment dialog AND the cheque-confirmation reminders, (c) handling over-payment (creates supplier credit balance via `customer_credit_notes` analog on the supplier side, or routes the excess through `JournalEntryService.recordDirectSupplierDiscountJournalEntry` — needs UX decision), and (d) handling under-payment (leaves a residual AP balance — already supported by `recordPayment`, just needs the UI to allow `amount ≠ invoice.total`). Re-open trigger: the user confirms which over-payment policy they want.
- **Domain-event bus for void cascades**. The repo+DAO loop is in the same Drift tx as the status flip; atomicity already holds. An event bus only buys value when a 3rd-party integration also needs to react to "purchase voided" — none exist today.
- **Materialised "linked-payment-JEs to reverse" view**. The N+1 fetch in `voidPurchase`/`voidSale` is bounded by the cheque-payment count per invoice (≤ a handful in practice). YAGNI.

### Historical drift remediation (one-time)
For databases that already contain the Phase-15.2 bug pattern (cheque-paid invoice voided pre-fix): the user opens Reconciliation & Health → "Rebuild Ledger" (`LedgerRebuildService.rebuild`). The rebuild skips voided sources and re-emits every other JE through the post-Phase-15.2 helpers, which now correctly handle the payment-JE cascade and batch deactivation.

---

## Phase 15.3 — Inventory valuation read-formula must mirror FIFO write predicate (2026-05-18)

### Rule
The read-side inventory-valuation formula (`JournalLocalDatasourceImpl.getTotalInventoryValueCents`) MUST gate the batch-ledger branch on the SAME predicate that gates the batch-ledger write paths — i.e. `_isFifoProduct(productId)` (`inventory_tracking_type IN ('batch','batch_expiry')` OR `costing_method = 'fifo'`).

`PurchaseDao.postPurchase` creates a `product_batches` row for every tracked purchase line (Phase 6.4 unified the ledger), but `BatchService.consumeFifo` / `BatchService.unconsumeFifo` are ONLY invoked for FIFO/batch products. WAC return paths only update `variant.stock_quantity` and post the `1200 Inventory` GL leg — they NEVER decrement `batch.remaining_quantity`. WAC product batches are therefore write-once / read-stale.

If the read formula treats those stale batch rows as authoritative, every linked or adjustment purchase return against a WAC product produces a phantom drift exactly equal to `(returned_qty × unit_cost)`. The Phase-15.0 formula (`prefer batches whenever any active batch exists`) had this asymmetry; Phase 15.3 closes it by mirroring the write predicate on the read side.

### New banned pattern
- ❌ Reading `product_batches` as the inventory-valuation SoT for products whose `costing_method != 'fifo'` AND `inventory_tracking_type NOT IN ('batch','batch_expiry')`. WAC return paths never decrement `remaining_quantity`, so the batch row drifts forever. The variant SoT (`variant.stock × variant.cost`) is the authoritative valuation for WAC products.
- ❌ Adding a new "consume batch on WAC return" code path to keep batches in sync. WAC has no FIFO ordering, so any chosen layer is arbitrary; the batch ledger has no SoT semantics for WAC. Symmetry is enforced on the read side, not the write side.

### Pinned by tests
- `test/integration/inventory_valuation_batch_ledger_test.dart` adds 4 Phase-15.3 regressions:
  - WAC variant with stale batch row uses variant SoT, NOT batch SoT.
  - WAC product without variants with stale batch uses product SoT.
  - Field-report reproduction (FIFO + WAC mix after a 1-unit linked purchase return) sums to GL exactly with no phantom drift.
  - Defense-in-depth: a product with `costing_method='fifo'` but `inventory_tracking_type='standard'` is still treated as FIFO (mirrors the OR predicate in `_isFifoProduct`).

### Field-facing remediation
The fix is read-only — no schema change, no data migration. The drift in `tapix_backup_20260518_061018.db` (267 300 vs 277 200 = exactly the 1-unit returned WAC line) disappears the moment the user upgrades and re-opens Reconciliation & Health.

### Explicitly deferred (NOT killed)
- A trigger that asserts `Σ(batch.remaining × batch.unit_cost) == GL(1200)` on every batch UPDATE for FIFO products. The current per-product `BatchService.assertInvariantForProduct` already does this; a global trigger would be redundant.
- Soft-deleting WAC product batches on the first WAC return so the read predicate would not need the costing-method gate. Rejected: the batch row is still useful for purchase-history audit and cost-trace UIs; deactivating it on first return would lose that audit trail. The read-side gate is cheaper and SoT-clean.

---

## Phase 15.4 — Purchase adjustment return must surface GROSS supplier reference (2026-05-18)

### Rule
Every PURCHASE-side product picker / auto-fill (purchase form, purchase adjustment return, supplier-history search) MUST resolve the displayed unit money via `lastPurchasePriceCents ?? costCents` — the same Phase 15.1 SoT used by `VariantEditDialog` and the six sites in `purchase_form_screen.dart`. Variant rows and no-variant rows MUST fall through the SAME resolver so the picker is symmetric.

`priceCents` is the customer SELL price and has NO semantic on the purchase side; reaching for it from a purchase-side picker is a bug class — the variant row will surface the markup and the no-variant row will look correct only when `cost_cents == price_cents` by coincidence.

### New banned patterns
- ❌ Reading `priceCents` (or `vr['price_cents']`) inside any picker / search result row that feeds a purchase form, purchase adjustment return, or purchase-side journal entry. Use `lastPurchasePriceCents ?? costCents` instead. The May 2026 field report on `PAR-202605-0001` (variants at $150 SELL, no-variant at $99 SELL) was exactly this bug.
- ❌ Using `cost_cents` alone as the purchase-side fallback in `UnifiedReturnService.searchProducts` (or any other supplier-history search). `cost_cents` is the IAS-2 NET basis (post per-line discount); the picker must surface the GROSS user-typed reference. Resolve `last_purchase_price_cents ?? cost_cents` in the SQL `SELECT` list, NOT downstream.

### Pinned by tests
- `test/integration/purchase_adj_return_supplier_ref_test.dart` (7 tests): no-variant + variant GROSS-wins + NULL-fallback + variant/no-variant symmetry at the same GROSS + sale-side untouched (still returns `price_cents`).

### Field-facing remediation
Phase 15.4 is UI-only. Existing posted PAR / SAR rows are unaffected; the next time the user opens `PurchaseAdjReturnFormScreen` the picker will display the GROSS supplier reference — no DB sweep, no migration, no ledger rebuild.

### Explicitly deferred (NOT killed)
- Shared resolver across `purchase_adj_return_form_screen.dart` and `sale_adj_return_form_screen.dart` `_PickerRow` classes. The sale form INTENTIONALLY keeps `priceCents` (customer-facing refund) and a shared helper would only add an indirection without removing duplication — both classes are 30-line value objects local to their screen.
- A picker-level GROSS / NET toggle. YAGNI until a user requests it; the supplier reference is the only correct money for a supplier-facing return.

---

## �� Questions?

1. Check `project-context.md` first
2. Review `TAPIX_ACCOUNTING_INTEGRITY_ARCHITECTURE.md`
3. Look at existing implementations
4. Ask for clarification before implementing

---

**Remember: Money is sacred. Every cent must be accounted for. No exceptions.**


## Supplier sales provenance — schema10093 (2026-09-22)

Quantity provenance and financial valuation are separate. Standard WAC/last-cost movements may record receipt-order allocations in `inventory_origin_events` and maintain `inventory_origin_states`, in the same transaction as stock. These tables must NEVER drive COGS, GL inventory valuation, or WAC batch depletion. The Phase15.3 prohibition on using stale WAC `product_batches.remaining_quantity` remains in force.

Report receipt allocations as `allocated`, separately from saved batch links (`verified`). Never backfill supplier attribution from current preferred vendor, old WAC batch balances, SAR names, or purchase proportions. Unverified customer returns are their own source category. Restore linked returns from saved sale allocations and reverse their claims on cancellation. Direct stock edits invalidate the quantity projection instead of silently keeping stale source shares.

Transfer dispatch/receipt must explicitly preserve these source portions in addition to financial values; merely calling StockService without transfer provenance creates an unidentified movement. Details and verification: `business/INVENTORY_ORIGIN_VERIFICATION_AR.md`.
