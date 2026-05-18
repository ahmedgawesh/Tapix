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

## �� Questions?

1. Check `project-context.md` first
2. Review `TAPIX_ACCOUNTING_INTEGRITY_ARCHITECTURE.md`
3. Look at existing implementations
4. Ask for clarification before implementing

---

**Remember: Money is sacred. Every cent must be accounted for. No exceptions.**
