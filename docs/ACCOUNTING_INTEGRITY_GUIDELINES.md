# Accounting Integrity Guidelines

> **For Developers and AI Agents**  
> **Version**: 1.0  
> **Last Updated**: January 2026  
> **Status**: MANDATORY - Follow for all financial implementations

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

## 📞 Questions?

1. Check `project-context.md` first
2. Review `TAPIX_ACCOUNTING_INTEGRITY_ARCHITECTURE.md`
3. Look at existing implementations
4. Ask for clarification before implementing

---

**Remember: Money is sacred. Every cent must be accounted for. No exceptions.**
