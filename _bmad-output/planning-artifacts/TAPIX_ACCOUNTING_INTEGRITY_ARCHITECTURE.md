# TAPIX Accounting Integrity Architecture

> **Document Version**: 1.0  
> **Created**: January 2026  
> **Purpose**: SINGLE SOURCE OF TRUTH for all accounting operations - ZERO ERRORS ALLOWED  
> **Status**: ACTIVE - ALL implementations MUST follow this document  
> **Language**: English (for technical accuracy)

---

## 🎯 EXECUTIVE SUMMARY

This document defines the **COMPLETE ACCOUNTING INTEGRITY ARCHITECTURE** for Tapix. Every financial operation, every money calculation, every balance update MUST follow these patterns to ensure **ZERO ACCOUNTING ERRORS**.

**Core Principle**: Money is sacred. Every cent must be accounted for. No exceptions.

---

## 📋 TABLE OF CONTENTS

1. [Core Accounting Principles](#1-core-accounting-principles)
2. [Single Source of Truth Architecture](#2-single-source-of-truth-architecture)
3. [Money Calculation Rules](#3-money-calculation-rules)
4. [Transaction Integrity Patterns](#4-transaction-integrity-patterns)
5. [Double-Entry Bookkeeping](#5-double-entry-bookkeeping)
6. [Audit Trail Requirements](#6-audit-trail-requirements)
7. [Validation Engine](#7-validation-engine)
8. [Error Prevention Strategies](#8-error-prevention-strategies)
9. [Testing Requirements](#9-testing-requirements)
10. [Implementation Checklist](#10-implementation-checklist)
11. [Story Integration Requirements](#11-story-integration-requirements)

---

## 1. CORE ACCOUNTING PRINCIPLES

### 1.1 The Seven Pillars of Accounting Integrity

| Pillar | Description | Implementation |
|--------|-------------|----------------|
| **1. Single Source of Truth** | ONE repository for all accounting data | `AccountingRepository` |
| **2. Immutable Transactions** | Posted transactions NEVER change | Soft-delete + reversal entries |
| **3. Double-Entry Enforcement** | Every debit has matching credit | `JournalEntryService` validation |
| **4. Real-Time Validation** | Validate BEFORE committing | `ValidationEngine` |
| **5. Atomic Operations** | All-or-nothing transactions | Drift transactions |
| **6. Complete Audit Trail** | Every change tracked forever | `AuditLogService` |
| **7. Balance Reconciliation** | Continuous balance verification | `ReconciliationService` |

### 1.2 Non-Negotiable Rules

```dart
// ❌ NEVER DO THIS
double price = 19.99;  // FLOATING POINT ERRORS!
balance = balance + amount;  // DIRECT MUTATION!
await db.update(account);  // NO VALIDATION!

// ✅ ALWAYS DO THIS
int priceInCents = 1999;  // INTEGER CENTS
await accountingRepository.adjustBalance(accountId, amountCents);  // THROUGH REPOSITORY
await validationEngine.validateAndExecute(transaction);  // WITH VALIDATION
```

---

## 2. SINGLE SOURCE OF TRUTH ARCHITECTURE

### 2.1 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ SalesBloc   │  │PurchaseBloc │  │ExpenseBloc  │  ...        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘             │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       SERVICE LAYER                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              TransactionOrchestrator                     │   │
│  │  (Coordinates all financial operations)                  │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │                                    │
│  ┌─────────────┐  ┌────────▼────────┐  ┌─────────────────┐    │
│  │ Validation  │  │ JournalEntry    │  │ Reconciliation  │    │
│  │ Engine      │◄─┤ Service         │──► Service         │    │
│  └─────────────┘  └────────┬────────┘  └─────────────────┘    │
└────────────────────────────┼────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                     REPOSITORY LAYER                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              AccountingRepository                        │   │
│  │  (SINGLE ACCESS POINT for all accounting data)          │   │
│  │                                                          │   │
│  │  Methods:                                                │   │
│  │  - createJournalEntry()                                  │   │
│  │  - adjustAccountBalance()                                │   │
│  │  - watchAccountBalance()                                 │   │
│  │  - getTrialBalance()                                     │   │
│  │  - reconcileBalances()                                   │   │
│  └─────────────────────────┬───────────────────────────────┘   │
└────────────────────────────┼────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                       DATA LAYER                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Drift Database                        │   │
│  │  ┌──────────┐ ┌──────────────┐ ┌───────────────────┐   │   │
│  │  │ Accounts │ │JournalEntries│ │JournalEntryLines  │   │   │
│  │  └──────────┘ └──────────────┘ └───────────────────┘   │   │
│  │  ┌──────────┐ ┌──────────────┐ ┌───────────────────┐   │   │
│  │  │ AuditLog │ │AccountPeriods│ │BalanceSnapshots   │   │   │
│  │  └──────────┘ └──────────────┘ └───────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow Rules

**Rule 1: ALL accounting operations MUST go through `AccountingRepository`**
```dart
// ❌ WRONG: Direct database access
await db.into(accounts).insert(account);

// ✅ CORRECT: Through repository
await accountingRepository.createAccount(account);
```

**Rule 2: ALL balance changes MUST create journal entries**
```dart
// ❌ WRONG: Direct balance update
account.balanceCents += 1000;
await db.update(accounts).replace(account);

// ✅ CORRECT: Through journal entry
await journalEntryService.createEntry(
  debitAccountId: cashAccountId,
  creditAccountId: revenueAccountId,
  amountCents: 1000,
  description: 'Sale #123',
);
```

**Rule 3: ALL transactions MUST be atomic**
```dart
// ✅ CORRECT: Atomic transaction
await db.transaction(() async {
  final entryId = await createJournalEntry(entry);
  await createJournalLines(entryId, lines);
  await updateAccountBalances(lines);
  await createAuditLog(entryId);
});
```

---

## 3. MONEY CALCULATION RULES

### 3.1 Integer Cents - MANDATORY

**ALL money values MUST be stored and calculated as INTEGER CENTS**

```dart
// Database columns - ALL INTEGER
IntColumn get priceInCents => integer()();
IntColumn get costInCents => integer()();
IntColumn get subtotalCents => integer()();
IntColumn get discountCents => integer()();
IntColumn get taxCents => integer()();
IntColumn get totalCents => integer()();
IntColumn get balanceCents => integer()();
IntColumn get debitCents => integer()();
IntColumn get creditCents => integer()();
```

### 3.2 Calculation Patterns

```dart
// ✅ CORRECT: All calculations in cents
int calculateTotal({
  required int subtotalCents,
  required int discountCents,
  required int taxCents,
}) {
  return subtotalCents - discountCents + taxCents;
}

// ✅ CORRECT: Percentage calculations
int calculateDiscount(int subtotalCents, int discountPercent) {
  // Use integer math with rounding
  return (subtotalCents * discountPercent) ~/ 100;
}

// ✅ CORRECT: Tax calculation
int calculateTax(int amountCents, int taxRateBasisPoints) {
  // Tax rate in basis points (1500 = 15%)
  return (amountCents * taxRateBasisPoints) ~/ 10000;
}
```

### 3.3 Decimal Package for Complex Calculations

```dart
import 'package:decimal/decimal.dart';

// For complex calculations requiring precision
Decimal calculateWeightedAverage({
  required int currentQty,
  required int currentCostCents,
  required int newQty,
  required int newCostCents,
}) {
  final totalQty = Decimal.fromInt(currentQty + newQty);
  final totalValue = Decimal.fromInt(
    (currentQty * currentCostCents) + (newQty * newCostCents)
  );
  return totalValue / totalQty;
}
```

### 3.4 Display Formatting

```dart
// ✅ CORRECT: Format for display only at UI layer
String formatMoney(int cents, {String symbol = '\$'}) {
  final dollars = cents / 100;
  return '$symbol${dollars.toStringAsFixed(2)}';
}

// ✅ CORRECT: Use CurrencyService for user-selected currency
final formatted = currencyService.format(priceInCents);
```

---

## 4. TRANSACTION INTEGRITY PATTERNS

### 4.1 Transaction Types

| Transaction Type | Debit Account | Credit Account | Inventory Effect |
|-----------------|---------------|----------------|------------------|
| **Sale** | Cash/Receivable | Revenue | Decrease |
| **Sale (COGS)** | COGS | Inventory | - |
| **Sale Return** | Revenue | Cash/Receivable | Increase |
| **Purchase** | Inventory | Cash/Payable | Increase |
| **Purchase Return** | Cash/Payable | Inventory | Decrease |
| **Customer Payment** | Cash | Receivable | - |
| **Supplier Payment** | Payable | Cash | - |
| **Expense** | Expense | Cash/Payable | - |

### 4.2 Immutable Transaction Pattern

```dart
// Transactions are NEVER modified - only reversed
class TransactionService {
  // ❌ NEVER: Update existing transaction
  // Future<void> updateTransaction(Transaction t) { ... }
  
  // ✅ ALWAYS: Create reversal entry
  Future<void> voidTransaction(int transactionId) async {
    final original = await getTransaction(transactionId);
    
    // Create reversal entry with opposite amounts
    await journalEntryService.createEntry(
      debitAccountId: original.creditAccountId,  // Reversed
      creditAccountId: original.debitAccountId,  // Reversed
      amountCents: original.amountCents,
      description: 'VOID: ${original.description}',
      referenceId: transactionId,
      entryType: JournalEntryType.reversal,
    );
    
    // Mark original as voided (soft delete)
    await markAsVoided(transactionId);
  }
}
```

### 4.3 Transaction Orchestrator

```dart
class TransactionOrchestrator {
  final AccountingRepository _accountingRepo;
  final ValidationEngine _validationEngine;
  final JournalEntryService _journalService;
  final AuditLogService _auditService;
  
  Future<TransactionResult> executeSale(SaleData sale) async {
    // 1. Validate BEFORE any changes
    final validation = await _validationEngine.validateSale(sale);
    if (!validation.isValid) {
      return TransactionResult.failed(validation.errors);
    }
    
    // 2. Execute in atomic transaction
    return await _accountingRepo.transaction(() async {
      // 2a. Create sale record
      final saleId = await _createSale(sale);
      
      // 2b. Create journal entries (Revenue)
      await _journalService.createSaleEntry(saleId, sale);
      
      // 2c. Create COGS entry
      await _journalService.createCOGSEntry(saleId, sale);
      
      // 2d. Update inventory
      await _updateInventory(sale.items);
      
      // 2e. Update customer balance (if credit sale)
      if (sale.isCredit) {
        await _updateCustomerBalance(sale.customerId, sale.totalCents);
      }
      
      // 2f. Create audit log
      await _auditService.logSale(saleId, sale);
      
      return TransactionResult.success(saleId);
    });
  }
}
```

---

## 5. DOUBLE-ENTRY BOOKKEEPING

### 5.1 The Golden Rule

**EVERY journal entry MUST have equal debits and credits**

```dart
class JournalEntryService {
  Future<int> createEntry(JournalEntryData entry) async {
    // Validate double-entry balance
    int totalDebits = 0;
    int totalCredits = 0;
    
    for (final line in entry.lines) {
      totalDebits += line.debitCents;
      totalCredits += line.creditCents;
    }
    
    if (totalDebits != totalCredits) {
      throw AccountingException(
        'Journal entry unbalanced: Debits=$totalDebits, Credits=$totalCredits'
      );
    }
    
    // Proceed with creation
    return await _createEntry(entry);
  }
}
```

### 5.2 Chart of Accounts Structure

```dart
enum AccountType {
  asset,      // Debit increases, Credit decreases
  liability,  // Credit increases, Debit decreases
  equity,     // Credit increases, Debit decreases
  revenue,    // Credit increases, Debit decreases
  expense,    // Debit increases, Credit decreases
}

// Standard accounts (auto-seeded)
const standardAccounts = [
  // Assets (1xxx)
  Account(code: '1000', name: 'Cash', type: AccountType.asset),
  Account(code: '1100', name: 'Accounts Receivable', type: AccountType.asset),
  Account(code: '1200', name: 'Inventory', type: AccountType.asset),
  
  // Liabilities (2xxx)
  Account(code: '2000', name: 'Accounts Payable', type: AccountType.liability),
  
  // Equity (3xxx)
  Account(code: '3000', name: 'Owner Equity', type: AccountType.equity),
  Account(code: '3100', name: 'Retained Earnings', type: AccountType.equity),
  
  // Revenue (4xxx)
  Account(code: '4000', name: 'Sales Revenue', type: AccountType.revenue),
  Account(code: '4100', name: 'Service Revenue', type: AccountType.revenue),
  
  // Expenses (5xxx)
  Account(code: '5000', name: 'Cost of Goods Sold', type: AccountType.expense),
  Account(code: '5100', name: 'Operating Expenses', type: AccountType.expense),
  Account(code: '5200', name: 'Rent Expense', type: AccountType.expense),
];
```

### 5.3 Balance Calculation Rules

```dart
int calculateAccountBalance(Account account, List<JournalLine> lines) {
  int balance = 0;
  
  for (final line in lines) {
    switch (account.type) {
      case AccountType.asset:
      case AccountType.expense:
        // Debit increases, Credit decreases
        balance += line.debitCents - line.creditCents;
        break;
      case AccountType.liability:
      case AccountType.equity:
      case AccountType.revenue:
        // Credit increases, Debit decreases
        balance += line.creditCents - line.debitCents;
        break;
    }
  }
  
  return balance;
}
```

---

## 6. AUDIT TRAIL REQUIREMENTS

### 6.1 Audit Log Table

```dart
@DataClassName('AuditLog')
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();  // 'sale', 'purchase', 'journal_entry'
  IntColumn get entityId => integer()();
  TextColumn get action => text()();  // 'create', 'void', 'modify'
  TextColumn get oldValue => text().nullable()();  // JSON of old state
  TextColumn get newValue => text().nullable()();  // JSON of new state
  IntColumn get userId => integer().references(Users, #id)();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  TextColumn get ipAddress => text().nullable()();
  TextColumn get userAgent => text().nullable()();
}
```

### 6.2 What MUST Be Logged

| Action | Entity | Required Fields |
|--------|--------|-----------------|
| Sale Created | Sale | All sale data, items, payments |
| Sale Voided | Sale | Reason, void user, original data |
| Payment Received | Payment | Amount, method, customer |
| Journal Entry | JournalEntry | All lines, amounts, accounts |
| Balance Adjustment | Account | Old balance, new balance, reason |
| Price Change | Product | Old price, new price, user |
| Stock Adjustment | Product | Old qty, new qty, reason |

### 6.3 Audit Service Implementation

```dart
class AuditLogService {
  final AppDatabase _db;
  final SessionService _sessionService;
  
  Future<void> log({
    required String entityType,
    required int entityId,
    required String action,
    Object? oldValue,
    Object? newValue,
  }) async {
    final user = await _sessionService.currentUser;
    
    await _db.into(_db.auditLogs).insert(
      AuditLogsCompanion.insert(
        entityType: entityType,
        entityId: entityId,
        action: action,
        oldValue: Value(oldValue != null ? jsonEncode(oldValue) : null),
        newValue: Value(newValue != null ? jsonEncode(newValue) : null),
        userId: user.id,
      ),
    );
  }
}
```

---

## 7. VALIDATION ENGINE

### 7.1 Validation Rules

```dart
class ValidationEngine {
  // Sale Validation
  Future<ValidationResult> validateSale(SaleData sale) async {
    final errors = <String>[];
    
    // Rule 1: Total must be positive
    if (sale.totalCents <= 0) {
      errors.add('Sale total must be positive');
    }
    
    // Rule 2: Items must have valid quantities
    for (final item in sale.items) {
      if (item.quantity <= 0) {
        errors.add('Item quantity must be positive: ${item.productName}');
      }
      if (item.priceInCents < 0) {
        errors.add('Item price cannot be negative: ${item.productName}');
      }
    }
    
    // Rule 3: Sufficient stock (if not allowing negative)
    for (final item in sale.items) {
      final stock = await _getStock(item.productId);
      if (stock < item.quantity) {
        errors.add('Insufficient stock for: ${item.productName}');
      }
    }
    
    // Rule 4: Customer credit limit (if credit sale)
    if (sale.isCredit && sale.customerId != null) {
      final customer = await _getCustomer(sale.customerId!);
      final newBalance = customer.balanceCents + sale.totalCents;
      if (newBalance > customer.creditLimitCents) {
        errors.add('Customer credit limit exceeded');
      }
    }
    
    // Rule 5: Accounting period is open
    final period = await _getCurrentPeriod();
    if (period.isClosed) {
      errors.add('Accounting period is closed');
    }
    
    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }
  
  // Journal Entry Validation
  Future<ValidationResult> validateJournalEntry(JournalEntryData entry) async {
    final errors = <String>[];
    
    // Rule 1: Must have at least 2 lines
    if (entry.lines.length < 2) {
      errors.add('Journal entry must have at least 2 lines');
    }
    
    // Rule 2: Debits must equal credits
    int totalDebits = 0;
    int totalCredits = 0;
    for (final line in entry.lines) {
      totalDebits += line.debitCents;
      totalCredits += line.creditCents;
    }
    if (totalDebits != totalCredits) {
      errors.add('Debits ($totalDebits) must equal Credits ($totalCredits)');
    }
    
    // Rule 3: Each line must have debit OR credit, not both
    for (final line in entry.lines) {
      if (line.debitCents > 0 && line.creditCents > 0) {
        errors.add('Line cannot have both debit and credit');
      }
      if (line.debitCents == 0 && line.creditCents == 0) {
        errors.add('Line must have either debit or credit');
      }
    }
    
    // Rule 4: All accounts must exist and be active
    for (final line in entry.lines) {
      final account = await _getAccount(line.accountId);
      if (account == null) {
        errors.add('Account not found: ${line.accountId}');
      } else if (!account.isActive) {
        errors.add('Account is inactive: ${account.accountName}');
      }
    }
    
    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }
}
```

---

## 8. ERROR PREVENTION STRATEGIES

### 8.1 Compile-Time Safety

```dart
// Use type-safe money class
class Money {
  final int cents;
  
  const Money(this.cents);
  
  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator *(int multiplier) => Money(cents * multiplier);
  
  // Prevent accidental double usage
  // Money.fromDouble() - DOES NOT EXIST ON PURPOSE
}
```

### 8.2 Runtime Assertions

```dart
void updateBalance(int accountId, int amountCents) {
  assert(amountCents != 0, 'Balance update with zero amount');
  // Proceed with update
}

void createSale(SaleData sale) {
  assert(sale.items.isNotEmpty, 'Sale must have items');
  assert(sale.totalCents > 0, 'Sale total must be positive');
  // Proceed with creation
}
```

### 8.3 Database Constraints

```dart
// In Drift table definitions
@DataClassName('JournalEntryLine')
class JournalEntryLines extends Table {
  // Constraint: debit OR credit, not both
  @override
  List<String> get customConstraints => [
    'CHECK (debit_cents >= 0)',
    'CHECK (credit_cents >= 0)',
    'CHECK (debit_cents > 0 OR credit_cents > 0)',
    'CHECK (NOT (debit_cents > 0 AND credit_cents > 0))',
  ];
}
```

### 8.4 Reconciliation Service

```dart
class ReconciliationService {
  // Run daily/on-demand to verify integrity
  Future<ReconciliationResult> reconcileAll() async {
    final issues = <String>[];
    
    // Check 1: Trial balance
    final trialBalance = await _getTrialBalance();
    if (trialBalance.totalDebits != trialBalance.totalCredits) {
      issues.add('Trial balance mismatch: '
        'Debits=${trialBalance.totalDebits}, '
        'Credits=${trialBalance.totalCredits}');
    }
    
    // Check 2: Customer balances match receivables
    final customerTotal = await _getTotalCustomerBalances();
    final receivablesBalance = await _getAccountBalance('1100');
    if (customerTotal != receivablesBalance) {
      issues.add('Customer balances mismatch receivables');
    }
    
    // Check 3: Supplier balances match payables
    final supplierTotal = await _getTotalSupplierBalances();
    final payablesBalance = await _getAccountBalance('2000');
    if (supplierTotal != payablesBalance) {
      issues.add('Supplier balances mismatch payables');
    }
    
    // Check 4: Inventory value matches inventory account
    final inventoryValue = await _calculateInventoryValue();
    final inventoryBalance = await _getAccountBalance('1200');
    if (inventoryValue != inventoryBalance) {
      issues.add('Inventory value mismatch');
    }
    
    return ReconciliationResult(
      isHealthy: issues.isEmpty,
      issues: issues,
      timestamp: DateTime.now(),
    );
  }
}
```

---

## 9. TESTING REQUIREMENTS

### 9.1 Unit Tests - MANDATORY

```dart
// Every calculation MUST have unit tests
group('Money Calculations', () {
  test('calculateTotal returns correct sum', () {
    expect(
      calculateTotal(subtotalCents: 10000, discountCents: 1000, taxCents: 1350),
      equals(10350),
    );
  });
  
  test('calculateDiscount handles percentages correctly', () {
    expect(calculateDiscount(10000, 10), equals(1000)); // 10%
    expect(calculateDiscount(10000, 15), equals(1500)); // 15%
    expect(calculateDiscount(9999, 10), equals(999));   // Rounds down
  });
  
  test('calculateTax uses basis points correctly', () {
    expect(calculateTax(10000, 1500), equals(1500)); // 15%
    expect(calculateTax(10000, 1000), equals(1000)); // 10%
  });
});
```

### 9.2 Integration Tests - MANDATORY

```dart
group('Sale Transaction', () {
  test('sale creates correct journal entries', () async {
    final sale = await transactionOrchestrator.executeSale(testSale);
    
    final entries = await accountingRepo.getJournalEntriesForSale(sale.id);
    
    // Verify revenue entry
    expect(entries.any((e) => 
      e.creditAccountId == revenueAccountId &&
      e.amountCents == sale.totalCents
    ), isTrue);
    
    // Verify COGS entry
    expect(entries.any((e) =>
      e.debitAccountId == cogsAccountId
    ), isTrue);
  });
  
  test('sale updates inventory correctly', () async {
    final initialStock = await getStock(productId);
    
    await transactionOrchestrator.executeSale(testSale);
    
    final finalStock = await getStock(productId);
    expect(finalStock, equals(initialStock - testSale.quantity));
  });
  
  test('voided sale reverses all entries', () async {
    final sale = await transactionOrchestrator.executeSale(testSale);
    await transactionOrchestrator.voidSale(sale.id);
    
    final trialBalance = await accountingRepo.getTrialBalance();
    expect(trialBalance.totalDebits, equals(trialBalance.totalCredits));
  });
});
```

### 9.3 Reconciliation Tests - MANDATORY

```dart
group('Reconciliation', () {
  test('trial balance always balances after operations', () async {
    // Execute various operations
    await executeSale();
    await executePurchase();
    await executePayment();
    await executeExpense();
    
    final result = await reconciliationService.reconcileAll();
    expect(result.isHealthy, isTrue);
  });
  
  test('customer balances match receivables', () async {
    await executeMultipleSales();
    await executeMultiplePayments();
    
    final customerTotal = await getTotalCustomerBalances();
    final receivables = await getAccountBalance('1100');
    expect(customerTotal, equals(receivables));
  });
});
```

---

## 10. IMPLEMENTATION CHECKLIST

### 10.1 Phase 1: Foundation (MUST COMPLETE FIRST)

- [ ] Create `AccountingRepository` in `lib/features/accounting/data/repositories/`
- [ ] Create `JournalEntryService` in `lib/features/accounting/domain/services/`
- [ ] Create `ValidationEngine` in `lib/core/services/`
- [ ] Create `AuditLogService` in `lib/core/services/`
- [ ] Add `AuditLogs` table to database schema
- [ ] Add database constraints for accounting tables
- [ ] Create `Money` value class for type safety

### 10.2 Phase 2: Transaction Services

- [ ] Create `TransactionOrchestrator` in `lib/core/services/`
- [ ] Implement sale transaction flow
- [ ] Implement purchase transaction flow
- [ ] Implement payment transaction flow
- [ ] Implement expense transaction flow
- [ ] Implement void/reversal flow

### 10.3 Phase 3: Reconciliation

- [ ] Create `ReconciliationService` in `lib/core/services/`
- [ ] Implement trial balance check
- [ ] Implement customer balance reconciliation
- [ ] Implement supplier balance reconciliation
- [ ] Implement inventory value reconciliation
- [ ] Create reconciliation report screen

### 10.4 Phase 4: Testing

- [ ] Unit tests for all money calculations (100% coverage)
- [ ] Unit tests for validation rules
- [ ] Integration tests for all transaction types
- [ ] Reconciliation tests after each operation type
- [ ] Performance tests with large datasets

---

## 11. STORY INTEGRATION REQUIREMENTS

### 11.1 Every Story MUST Include

**For ANY story that involves money or balances:**

```yaml
Accounting Integrity Requirements:
  - [ ] All money values use integer cents
  - [ ] All balance changes go through AccountingRepository
  - [ ] All transactions create journal entries
  - [ ] All operations are atomic (Drift transactions)
  - [ ] All changes are logged to AuditLog
  - [ ] Validation runs BEFORE any changes
  - [ ] Unit tests cover all calculations
  - [ ] Integration tests verify journal entries
  - [ ] Reconciliation tests pass after operation
```

### 11.2 Story Template Addition

Add to every story that touches financial data:

```markdown
## Accounting Integrity Checklist

### Money Handling
- [ ] All amounts stored as integer cents
- [ ] No floating-point calculations
- [ ] CurrencyService used for display formatting

### Transaction Integrity
- [ ] Changes go through AccountingRepository
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
- [ ] Unit tests for calculations
- [ ] Integration tests for transaction flow
- [ ] Reconciliation passes after operation
```

### 11.3 Affected Stories

**The following stories MUST implement accounting integrity:**

| Epic | Story | Accounting Impact |
|------|-------|-------------------|
| EPIC-03 | 3-2 Product CRUD | Cost price, selling price |
| EPIC-03 | 3-5 Edit Prices | Bulk price changes |
| EPIC-04 | 4-1 Customer Management | Customer balance |
| EPIC-04 | 4-4 Customer Payment | Balance adjustment |
| EPIC-04 | 4-5 Supplier Management | Supplier balance |
| EPIC-04 | 4-10 Supplier Payment | Balance adjustment |
| EPIC-05 | 5-1 POS Interface | Sale totals |
| EPIC-05 | 5-2 Checkout Payment | Payment processing |
| EPIC-05 | 5-4 Sale Returns | Refund processing |
| EPIC-06 | 6-1 Purchase Orders | Purchase totals |
| EPIC-06 | 6-2 Purchase Returns | Return processing |
| EPIC-07 | 7-1 Expenses | Expense recording |
| EPIC-07 | 7-5 Journal Entries | Direct accounting |
| EPIC-08 | All Reports | Balance calculations |

---

## 📚 QUICK REFERENCE

### Do's ✅

- Use integer cents for ALL money values
- Go through `AccountingRepository` for ALL accounting data
- Create journal entries for ALL balance changes
- Wrap related changes in atomic transactions
- Log ALL changes to audit trail
- Validate BEFORE committing
- Test ALL calculations

### Don'ts ❌

- NEVER use `double` or `float` for money
- NEVER access accounting tables directly
- NEVER update balances without journal entries
- NEVER modify posted transactions (use reversals)
- NEVER skip validation
- NEVER skip audit logging
- NEVER skip testing

---

**Document Owner**: Architecture Team  
**Last Updated**: January 2026  
**Version**: 1.0  
**Status**: ACTIVE - MANDATORY COMPLIANCE

