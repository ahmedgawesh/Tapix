import '../database/app_database.dart';
import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../../features/accounting/domain/models/journal_entry_data.dart';
import 'validation_engine.dart';
import 'audit_log_service.dart';

/// TransactionOrchestrator - Coordinates all financial operations
/// 
/// This is the CENTRAL service for all transactions that affect:
/// - Account balances
/// - Inventory levels
/// - Customer/Supplier balances
/// 
/// ALL financial operations MUST go through this orchestrator to ensure:
/// - Validation before execution
/// - Atomic transactions
/// - Proper journal entries
/// - Complete audit trail
class TransactionOrchestrator {
  final AppDatabase _db;
  final AccountingRepository _accountingRepo;
  final ValidationEngine _validationEngine;
  final AuditLogService _auditService;

  TransactionOrchestrator({
    required AppDatabase db,
    required AccountingRepository accountingRepo,
    required ValidationEngine validationEngine,
    required AuditLogService auditService,
  })  : _db = db,
        _accountingRepo = accountingRepo,
        _validationEngine = validationEngine,
        _auditService = auditService;

  // ============================================================
  // SALE TRANSACTIONS
  // ============================================================

  /// Execute a complete sale transaction
  /// 
  /// This creates:
  /// - Sale record
  /// - Sale items
  /// - Journal entries (Revenue, COGS)
  /// - Inventory updates
  /// - Customer balance update (if credit sale)
  /// - Audit log
  Future<TransactionResult> executeSale({
    required SaleTransactionData sale,
    required int userId,
  }) async {
    // 1. Validate BEFORE any changes
    final validation = _validationEngine.validateSale(SaleValidationData(
      totalCents: sale.totalCents,
      discountCents: sale.discountCents,
      taxCents: sale.taxCents,
      customerId: sale.customerId,
      items: sale.items.map((item) => SaleItemValidationData(
        productId: item.productId,
        quantity: item.quantity,
        priceInCents: item.priceInCents,
        currentStock: item.currentStock,
      )).toList(),
    ));

    if (!validation.isValid) {
      return TransactionResult.failed(validation.errors);
    }

    // 2. Get required account IDs
    final cashAccount = await _accountingRepo.getAccountByCode('1000');
    final receivablesAccount = await _accountingRepo.getAccountByCode('1100');
    final revenueAccount = await _accountingRepo.getAccountByCode('4000');
    final cogsAccount = await _accountingRepo.getAccountByCode('5000');
    final inventoryAccount = await _accountingRepo.getAccountByCode('1200');

    if (cashAccount == null || revenueAccount == null || 
        cogsAccount == null || inventoryAccount == null) {
      return TransactionResult.failed(['Required accounts not found']);
    }

    // 3. Execute in atomic transaction
    try {
      return await _db.transaction(() async {
        // 3a. Create sale record (implementation depends on your sale table)
        final saleId = await _createSaleRecord(sale, userId);

        // 3b. Create sale items
        for (final item in sale.items) {
          await _createSaleItem(saleId, item);
        }

        // 3c. Create revenue journal entry
        final debitAccountId = sale.isCreditSale 
            ? receivablesAccount!.id 
            : cashAccount.id;

        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Sale #$saleId - Revenue',
            debitAccountId: debitAccountId,
            creditAccountId: revenueAccount.id,
            amountCents: sale.totalCents,
            currencyId: sale.currencyId,
            entryType: 'sale',
            sourceTable: 'sales',
            sourceId: saleId,
            autoPost: true,
          ),
          userId: userId,
        );

        // 3d. Create COGS journal entry
        final totalCost = sale.items.fold<int>(
          0,
          (sum, item) => sum + (item.quantity * item.costInCents),
        );

        if (totalCost > 0) {
          await _accountingRepo.createJournalEntry(
            entryData: JournalEntryData.simple(
              description: 'Sale #$saleId - COGS',
              debitAccountId: cogsAccount.id,
              creditAccountId: inventoryAccount.id,
              amountCents: totalCost,
              currencyId: sale.currencyId,
              entryType: 'sale',
              sourceTable: 'sales',
              sourceId: saleId,
              autoPost: true,
            ),
            userId: userId,
          );
        }

        // 3e. Update inventory
        for (final item in sale.items) {
          await _updateInventory(
            productId: item.productId,
            quantityChange: -item.quantity,
            reason: 'Sale #$saleId',
          );
        }

        // 3f. Update customer balance (if credit sale)
        if (sale.isCreditSale && sale.customerId != null) {
          await _updateCustomerBalance(
            customerId: sale.customerId!,
            amountCents: sale.totalCents,
            isIncrease: true,
          );
        }

        // 3g. Create audit log
        await _auditService.log(
          entityType: 'sale',
          entityId: saleId,
          action: 'create',
          newValue: sale.toJson(),
          userId: userId,
        );

        return TransactionResult.success(saleId);
      });
    } catch (e) {
      return TransactionResult.failed(['Transaction failed: $e']);
    }
  }

  /// Void a sale transaction
  Future<TransactionResult> voidSale({
    required int saleId,
    required String reason,
    required int userId,
  }) async {
    try {
      return await _db.transaction(() async {
        // Get original sale data
        final sale = await _getSaleById(saleId);
        if (sale == null) {
          return TransactionResult.failed(['Sale not found']);
        }

        // Get journal entries for this sale
        final entries = await _getJournalEntriesForSource('sales', saleId);

        // Void each journal entry (creates reversal entries)
        for (final entry in entries) {
          await _accountingRepo.voidJournalEntry(
            entryId: entry.id,
            reason: reason,
            userId: userId,
          );
        }

        // Restore inventory
        final items = await _getSaleItems(saleId);
        for (final item in items) {
          await _updateInventory(
            productId: item.productId,
            quantityChange: item.quantity, // Positive to restore
            reason: 'Void Sale #$saleId',
          );
        }

        // Update customer balance if credit sale
        if (sale.customerId != null) {
          await _updateCustomerBalance(
            customerId: sale.customerId!,
            amountCents: sale.totalCents.toBigInt().toInt(),
            isIncrease: false, // Decrease balance
          );
        }

        // Mark sale as voided
        await _markSaleAsVoided(saleId, reason, userId);

        // Create void log
        await _auditService.logVoid(
          entityType: 'sale',
          entityId: saleId,
          reason: reason,
          userId: userId,
        );

        return TransactionResult.success(saleId);
      });
    } catch (e) {
      return TransactionResult.failed(['Void failed: $e']);
    }
  }

  // ============================================================
  // PURCHASE TRANSACTIONS
  // ============================================================

  /// Execute a complete purchase transaction
  Future<TransactionResult> executePurchase({
    required PurchaseTransactionData purchase,
    required int userId,
  }) async {
    // 1. Validate
    final validation = _validationEngine.validatePurchase(PurchaseValidationData(
      totalCents: purchase.totalCents,
      supplierId: purchase.supplierId,
      items: purchase.items.map((item) => PurchaseItemValidationData(
        productId: item.productId,
        quantity: item.quantity,
        costInCents: item.costInCents,
      )).toList(),
    ));

    if (!validation.isValid) {
      return TransactionResult.failed(validation.errors);
    }

    // 2. Get required accounts
    final cashAccount = await _accountingRepo.getAccountByCode('1000');
    final payablesAccount = await _accountingRepo.getAccountByCode('2000');
    final inventoryAccount = await _accountingRepo.getAccountByCode('1200');

    if (cashAccount == null || payablesAccount == null || inventoryAccount == null) {
      return TransactionResult.failed(['Required accounts not found']);
    }

    // 3. Execute atomically
    try {
      return await _db.transaction(() async {
        // Create purchase record
        final purchaseId = await _createPurchaseRecord(purchase, userId);

        // Create purchase items
        for (final item in purchase.items) {
          await _createPurchaseItem(purchaseId, item);
        }

        // Create journal entry (Inventory increase, Payables increase)
        final creditAccountId = purchase.isPaid 
            ? cashAccount.id 
            : payablesAccount.id;

        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Purchase #$purchaseId',
            debitAccountId: inventoryAccount.id,
            creditAccountId: creditAccountId,
            amountCents: purchase.totalCents,
            currencyId: purchase.currencyId,
            entryType: 'purchase',
            sourceTable: 'purchases',
            sourceId: purchaseId,
            autoPost: true,
          ),
          userId: userId,
        );

        // Update inventory
        for (final item in purchase.items) {
          await _updateInventory(
            productId: item.productId,
            quantityChange: item.quantity, // Positive to increase
            reason: 'Purchase #$purchaseId',
          );

          // Update product cost (weighted average or last cost)
          await _updateProductCost(
            productId: item.productId,
            newCostCents: item.costInCents,
            quantity: item.quantity,
          );
        }

        // Update supplier balance if not paid
        if (!purchase.isPaid) {
          await _updateSupplierBalance(
            supplierId: purchase.supplierId,
            amountCents: purchase.totalCents,
            isIncrease: true,
          );
        }

        // Audit log
        await _auditService.log(
          entityType: 'purchase',
          entityId: purchaseId,
          action: 'create',
          newValue: purchase.toJson(),
          userId: userId,
        );

        return TransactionResult.success(purchaseId);
      });
    } catch (e) {
      return TransactionResult.failed(['Transaction failed: $e']);
    }
  }

  // ============================================================
  // PAYMENT TRANSACTIONS
  // ============================================================

  /// Record a customer payment
  Future<TransactionResult> recordCustomerPayment({
    required int customerId,
    required int amountCents,
    required String paymentMethod,
    required int currencyId,
    required int userId,
    String? reference,
  }) async {
    // Validate
    final validation = _validationEngine.validatePayment(PaymentValidationData(
      amountCents: amountCents,
      paymentMethod: paymentMethod,
      customerId: customerId,
    ));

    if (!validation.isValid) {
      return TransactionResult.failed(validation.errors);
    }

    // Get accounts
    final cashAccount = await _accountingRepo.getAccountByCode('1000');
    final receivablesAccount = await _accountingRepo.getAccountByCode('1100');

    if (cashAccount == null || receivablesAccount == null) {
      return TransactionResult.failed(['Required accounts not found']);
    }

    try {
      return await _db.transaction(() async {
        // Create payment record
        final paymentId = await _createPaymentRecord(
          customerId: customerId,
          amountCents: amountCents,
          paymentMethod: paymentMethod,
          reference: reference,
          userId: userId,
        );

        // Create journal entry (Cash increase, Receivables decrease)
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Customer Payment #$paymentId',
            debitAccountId: cashAccount.id,
            creditAccountId: receivablesAccount.id,
            amountCents: amountCents,
            currencyId: currencyId,
            entryType: 'payment',
            sourceTable: 'payments',
            sourceId: paymentId,
            autoPost: true,
          ),
          userId: userId,
        );

        // Update customer balance
        await _updateCustomerBalance(
          customerId: customerId,
          amountCents: amountCents,
          isIncrease: false, // Decrease balance (they paid)
        );

        // Audit log
        await _auditService.log(
          entityType: 'payment',
          entityId: paymentId,
          action: 'create',
          newValue: {
            'customerId': customerId,
            'amountCents': amountCents,
            'paymentMethod': paymentMethod,
          },
          userId: userId,
        );

        return TransactionResult.success(paymentId);
      });
    } catch (e) {
      return TransactionResult.failed(['Payment failed: $e']);
    }
  }

  /// Record a supplier payment
  Future<TransactionResult> recordSupplierPayment({
    required int supplierId,
    required int amountCents,
    required String paymentMethod,
    required int currencyId,
    required int userId,
    String? reference,
  }) async {
    // Validate
    final validation = _validationEngine.validatePayment(PaymentValidationData(
      amountCents: amountCents,
      paymentMethod: paymentMethod,
      supplierId: supplierId,
    ));

    if (!validation.isValid) {
      return TransactionResult.failed(validation.errors);
    }

    // Get accounts
    final cashAccount = await _accountingRepo.getAccountByCode('1000');
    final payablesAccount = await _accountingRepo.getAccountByCode('2000');

    if (cashAccount == null || payablesAccount == null) {
      return TransactionResult.failed(['Required accounts not found']);
    }

    try {
      return await _db.transaction(() async {
        // Create payment record
        final paymentId = await _createSupplierPaymentRecord(
          supplierId: supplierId,
          amountCents: amountCents,
          paymentMethod: paymentMethod,
          reference: reference,
          userId: userId,
        );

        // Create journal entry (Payables decrease, Cash decrease)
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Supplier Payment #$paymentId',
            debitAccountId: payablesAccount.id,
            creditAccountId: cashAccount.id,
            amountCents: amountCents,
            currencyId: currencyId,
            entryType: 'payment',
            sourceTable: 'supplier_payments',
            sourceId: paymentId,
            autoPost: true,
          ),
          userId: userId,
        );

        // Update supplier balance
        await _updateSupplierBalance(
          supplierId: supplierId,
          amountCents: amountCents,
          isIncrease: false, // Decrease balance (we paid)
        );

        // Audit log
        await _auditService.log(
          entityType: 'supplier_payment',
          entityId: paymentId,
          action: 'create',
          newValue: {
            'supplierId': supplierId,
            'amountCents': amountCents,
            'paymentMethod': paymentMethod,
          },
          userId: userId,
        );

        return TransactionResult.success(paymentId);
      });
    } catch (e) {
      return TransactionResult.failed(['Payment failed: $e']);
    }
  }

  // ============================================================
  // EXPENSE TRANSACTIONS
  // ============================================================

  /// Record an expense
  Future<TransactionResult> recordExpense({
    required int categoryId,
    required int amountCents,
    required String description,
    required int currencyId,
    required int userId,
    int? accountId,
    String? receiptPath,
  }) async {
    // Validate
    final validation = _validationEngine.validateExpense(ExpenseValidationData(
      amountCents: amountCents,
      categoryId: categoryId,
      description: description,
    ));

    if (!validation.isValid) {
      return TransactionResult.failed(validation.errors);
    }

    // Get accounts
    final cashAccount = await _accountingRepo.getAccountByCode('1000');
    final expenseAccount = accountId != null 
        ? await _accountingRepo.getAccountById(accountId)
        : await _accountingRepo.getAccountByCode('5100'); // Default operating expenses

    if (cashAccount == null || expenseAccount == null) {
      return TransactionResult.failed(['Required accounts not found']);
    }

    try {
      return await _db.transaction(() async {
        // Create expense record
        final expenseId = await _createExpenseRecord(
          categoryId: categoryId,
          amountCents: amountCents,
          description: description,
          currencyId: currencyId,
          accountId: expenseAccount.id,
          receiptPath: receiptPath,
        );

        // Create journal entry (Expense increase, Cash decrease)
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Expense #$expenseId - $description',
            debitAccountId: expenseAccount.id,
            creditAccountId: cashAccount.id,
            amountCents: amountCents,
            currencyId: currencyId,
            entryType: 'expense',
            sourceTable: 'expenses',
            sourceId: expenseId,
            autoPost: true,
          ),
          userId: userId,
        );

        // Audit log
        await _auditService.log(
          entityType: 'expense',
          entityId: expenseId,
          action: 'create',
          newValue: {
            'categoryId': categoryId,
            'amountCents': amountCents,
            'description': description,
          },
          userId: userId,
        );

        return TransactionResult.success(expenseId);
      });
    } catch (e) {
      return TransactionResult.failed(['Expense recording failed: $e']);
    }
  }

  // ============================================================
  // PRIVATE HELPER METHODS
  // ============================================================

  // These methods would interact with the actual database tables
  // Implementation depends on your specific table structure

  Future<int> _createSaleRecord(SaleTransactionData sale, int userId) async {
    // TODO: Implement based on your Sales table structure
    throw UnimplementedError('Implement based on Sales table');
  }

  Future<void> _createSaleItem(int saleId, SaleItemTransactionData item) async {
    // TODO: Implement based on your SaleItems table structure
    throw UnimplementedError('Implement based on SaleItems table');
  }

  Future<Sale?> _getSaleById(int saleId) async {
    return await (_db.select(_db.sales)..where((s) => s.id.equals(saleId)))
        .getSingleOrNull();
  }

  Future<List<SaleItem>> _getSaleItems(int saleId) async {
    return await (_db.select(_db.saleItems)
          ..where((i) => i.saleId.equals(saleId)))
        .get();
  }

  Future<void> _markSaleAsVoided(int saleId, String reason, int userId) async {
    // TODO: Implement voiding logic
  }

  Future<int> _createPurchaseRecord(PurchaseTransactionData purchase, int userId) async {
    // TODO: Implement based on your Purchases table structure
    throw UnimplementedError('Implement based on Purchases table');
  }

  Future<void> _createPurchaseItem(int purchaseId, PurchaseItemTransactionData item) async {
    // TODO: Implement based on your PurchaseItems table structure
    throw UnimplementedError('Implement based on PurchaseItems table');
  }

  Future<int> _createPaymentRecord({
    required int customerId,
    required int amountCents,
    required String paymentMethod,
    String? reference,
    required int userId,
  }) async {
    // TODO: Implement based on your Payments table structure
    throw UnimplementedError('Implement based on Payments table');
  }

  Future<int> _createSupplierPaymentRecord({
    required int supplierId,
    required int amountCents,
    required String paymentMethod,
    String? reference,
    required int userId,
  }) async {
    // TODO: Implement based on your SupplierPayments table structure
    throw UnimplementedError('Implement based on SupplierPayments table');
  }

  Future<int> _createExpenseRecord({
    required int categoryId,
    required int amountCents,
    required String description,
    required int currencyId,
    int? accountId,
    String? receiptPath,
  }) async {
    // TODO: Implement based on your Expenses table structure
    throw UnimplementedError('Implement based on Expenses table');
  }

  Future<void> _updateInventory({
    required int productId,
    required int quantityChange,
    required String reason,
  }) async {
    // TODO: Implement inventory update logic
  }

  Future<void> _updateProductCost({
    required int productId,
    required int newCostCents,
    required int quantity,
  }) async {
    // TODO: Implement cost update logic (weighted average or last cost)
  }

  Future<void> _updateCustomerBalance({
    required int customerId,
    required int amountCents,
    required bool isIncrease,
  }) async {
    // TODO: Implement customer balance update
  }

  Future<void> _updateSupplierBalance({
    required int supplierId,
    required int amountCents,
    required bool isIncrease,
  }) async {
    // TODO: Implement supplier balance update
  }

  Future<List<JournalEntry>> _getJournalEntriesForSource(String sourceTable, int sourceId) async {
    return await (_db.select(_db.journalEntries)
          ..where((e) => e.sourceTable.equals(sourceTable))
          ..where((e) => e.sourceId.equals(sourceId)))
        .get();
  }
}

/// Result of a transaction operation
class TransactionResult {
  final bool isSuccess;
  final int? entityId;
  final List<String> errors;

  TransactionResult._({
    required this.isSuccess,
    this.entityId,
    required this.errors,
  });

  factory TransactionResult.success(int entityId) {
    return TransactionResult._(
      isSuccess: true,
      entityId: entityId,
      errors: [],
    );
  }

  factory TransactionResult.failed(List<String> errors) {
    return TransactionResult._(
      isSuccess: false,
      entityId: null,
      errors: errors,
    );
  }

  String get errorMessage => errors.join('; ');
}

/// Data class for sale transaction
class SaleTransactionData {
  final int totalCents;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int? customerId;
  final int currencyId;
  final bool isCreditSale;
  final List<SaleItemTransactionData> items;

  SaleTransactionData({
    required this.totalCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    this.customerId,
    required this.currencyId,
    required this.isCreditSale,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'totalCents': totalCents,
    'subtotalCents': subtotalCents,
    'discountCents': discountCents,
    'taxCents': taxCents,
    'customerId': customerId,
    'currencyId': currencyId,
    'isCreditSale': isCreditSale,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

class SaleItemTransactionData {
  final int productId;
  final int quantity;
  final int priceInCents;
  final int costInCents;
  final int currentStock;

  SaleItemTransactionData({
    required this.productId,
    required this.quantity,
    required this.priceInCents,
    required this.costInCents,
    required this.currentStock,
  });

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'quantity': quantity,
    'priceInCents': priceInCents,
    'costInCents': costInCents,
  };
}

/// Data class for purchase transaction
class PurchaseTransactionData {
  final int totalCents;
  final int supplierId;
  final int currencyId;
  final bool isPaid;
  final List<PurchaseItemTransactionData> items;

  PurchaseTransactionData({
    required this.totalCents,
    required this.supplierId,
    required this.currencyId,
    required this.isPaid,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'totalCents': totalCents,
    'supplierId': supplierId,
    'currencyId': currencyId,
    'isPaid': isPaid,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

class PurchaseItemTransactionData {
  final int productId;
  final int quantity;
  final int costInCents;

  PurchaseItemTransactionData({
    required this.productId,
    required this.quantity,
    required this.costInCents,
  });

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'quantity': quantity,
    'costInCents': costInCents,
  };
}
