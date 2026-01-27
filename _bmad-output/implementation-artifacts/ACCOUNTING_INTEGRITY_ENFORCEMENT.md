# Accounting Integrity Enforcement Notice

> **Effective Immediately**: January 2026  
> **Applies To**: ALL financial stories (completed and future)

---

## 🚨 MANDATORY REQUIREMENTS

All stories involving **money, balances, prices, or financial transactions** MUST now follow the **Accounting Integrity Architecture**.

### Affected Story Types

- ✅ Sales, Sale Returns
- ✅ Purchases, Purchase Returns  
- ✅ Customer/Supplier Payments
- ✅ Expenses
- ✅ **Price Changes** (3-2, 3-5)
- ✅ Stock Adjustments
- ✅ Any balance modifications

---

## 📋 Required Implementation Checklist

**EVERY financial story MUST include:**

### Money Handling
- [ ] All amounts stored as integer cents
- [ ] No floating-point calculations for money
- [ ] CurrencyService used for display formatting

### Transaction Integrity
- [ ] Changes go through `AccountingRepository`
- [ ] `TransactionOrchestrator` used for operations
- [ ] Journal entries created for balance changes
- [ ] Atomic transaction wraps all related changes
- [ ] Void/reversal pattern used (no direct updates)

### Validation
- [ ] `ValidationEngine` checks run before commit
- [ ] Business rules enforced
- [ ] Error messages are clear and actionable

### Audit Trail
- [ ] `AuditLogService` records all changes
- [ ] Old and new values captured
- [ ] User and timestamp recorded

### Testing
- [ ] Unit tests for all calculations
- [ ] Integration tests for transaction flow
- [ ] Reconciliation passes after operation

---

## 🔧 Implementation Components

| Component | Path | Purpose |
|-----------|------|---------|
| **AccountingRepository** | `lib/features/accounting/data/repositories/accounting_repository.dart` | Single source of truth |
| **TransactionOrchestrator** | `lib/core/services/transaction_orchestrator.dart` | Transaction coordination |
| **ValidationEngine** | `lib/core/services/validation_engine.dart` | Pre-commit validation |
| **AuditLogService** | `lib/core/services/audit_log_service.dart` | Change tracking |

---

## 📝 Story Updates Required

### Completed Stories Requiring Updates

| Story | Type | Update Required |
|-------|------|-----------------|
| **3-2** | Product CRUD | Add audit logging for price changes |
| **3-5** | Edit Prices | Add `AuditLogService.logPriceChange()` for all price updates |

### Future Stories Must Include

**ALL financial stories** starting now MUST:
1. Include accounting integrity checklist in acceptance criteria
2. Use `TransactionOrchestrator` for operations
3. Use `AccountingRepository` for data access
4. Use `ValidationEngine` for pre-commit checks
5. Use `AuditLogService` for audit trail

---

## 📚 Reference Documents

- **Architecture**: `_bmad-output/planning-artifacts/TAPIX_ACCOUNTING_INTEGRITY_ARCHITECTURE.md`
- **Guidelines**: `docs/ACCOUNTING_INTEGRITY_GUIDELINES.md`
- **Project Context**: `project-context.md` (Section: 🏦 Accounting Integrity)

---

## ⚡ Quick Action Required

### For Developers

When working on **ANY financial feature**:

```dart
// 1. Use ValidationEngine
final validation = validationEngine.validateSale(saleData);
if (!validation.isValid) {
  throw ValidationException(validation.errors);
}

// 2. Use TransactionOrchestrator
final result = await transactionOrchestrator.executeSale(
  sale: saleData,
  userId: currentUserId,
);

// 3. Use AuditLogService
await auditService.logPriceChange(
  productId: productId,
  oldPriceCents: oldPrice,
  newPriceCents: newPrice,
  priceType: 'selling',
  userId: userId,
);
```

### For Story Writers

Add this to **EVERY financial story**:

```markdown
## Accounting Integrity Checklist

- [ ] All money values stored as integer cents
- [ ] Changes go through AccountingRepository
- [ ] TransactionOrchestrator used for operations
- [ ] ValidationEngine validates before commit
- [ ] AuditLogService logs all changes
- [ ] Journal entries created for balance changes
- [ ] Atomic transactions wrap related changes
- [ ] Void/reversal pattern used
- [ ] Unit tests cover calculations
- [ ] Integration tests verify journal entries
- [ ] Reconciliation passes after operation
```

---

**Status**: ACTIVE - Enforce immediately for all new work and retrofits required for completed stories 3-2 and 3-5.
