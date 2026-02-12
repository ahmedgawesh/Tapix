import 'package:drift/drift.dart';
import '../database/app_database.dart';

/// Severity levels for audit events.
/// critical = immutable, cannot be ignored (e.g. void, period close, permission change)
/// normal   = standard operational events (e.g. create, update)
enum AuditSeverity { normal, critical }

/// AuditLogService - Records all changes to financial data
/// 
/// This service is CRITICAL for accounting integrity.
/// ALL changes to financial data MUST be logged.
class AuditLogService {
  final AppDatabase _db;

  AuditLogService(this._db);

  /// Log a general action
  Future<int> log({
    required String entityType,
    required int entityId,
    required String action,
    Object? oldValue,
    Object? newValue,
    int? userId,
    String? userRole,
    AuditSeverity severity = AuditSeverity.normal,
  }) async {
    return await _db.into(_db.auditLogs).insert(
      AuditLogsCompanion.insert(
        targetTable: entityType,
        recordId: entityId,
        action: action,
        changes: {
          'role': ?userRole,
          'severity': severity.name,
          'old': oldValue,
          'new': newValue,
          'timestamp': DateTime.now().toIso8601String(),
        },
        userId: userId == null ? const Value.absent() : Value(userId),
      ),
    );
  }

  /// Log a void action (CRITICAL severity)
  Future<int> logVoid({
    required String entityType,
    required int entityId,
    required String reason,
    int? userId,
    String? userRole,
  }) async {
    // Log to void_logs table
    await _db.into(_db.voidLogs).insert(
      VoidLogsCompanion.insert(
        targetTable: entityType,
        recordId: entityId,
        reason: reason,
        voidedBy: userId == null ? const Value.absent() : Value(userId),
      ),
    );

    // Also log to audit_logs for complete trail
    return await log(
      entityType: entityType,
      entityId: entityId,
      action: 'void',
      newValue: {'reason': reason},
      userId: userId,
      userRole: userRole,
      severity: AuditSeverity.critical,
    );
  }

  /// Log a balance change
  Future<int> logBalanceChange({
    required String entityType,
    required int entityId,
    required int oldBalanceCents,
    required int newBalanceCents,
    required String reason,
    required int userId,
    String? userRole,
  }) async {
    return await log(
      entityType: entityType,
      entityId: entityId,
      action: 'balance_change',
      oldValue: {'balanceCents': oldBalanceCents},
      newValue: {
        'balanceCents': newBalanceCents,
        'changeCents': newBalanceCents - oldBalanceCents,
        'reason': reason,
      },
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log a price change
  Future<int> logPriceChange({
    required int productId,
    required int oldPriceCents,
    required int newPriceCents,
    required String priceType,
    required int userId,
    String? userRole,
  }) async {
    return await log(
      entityType: 'product',
      entityId: productId,
      action: 'price_change',
      oldValue: {'${priceType}PriceCents': oldPriceCents},
      newValue: {'${priceType}PriceCents': newPriceCents},
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log a stock adjustment
  Future<int> logStockAdjustment({
    required int productId,
    required int oldQuantity,
    required int newQuantity,
    required String reason,
    required int userId,
    String? userRole,
  }) async {
    return await log(
      entityType: 'product',
      entityId: productId,
      action: 'stock_adjustment',
      oldValue: {'quantity': oldQuantity},
      newValue: {
        'quantity': newQuantity,
        'change': newQuantity - oldQuantity,
        'reason': reason,
      },
      userId: userId,
      userRole: userRole,
    );
  }

  // ═══════════════════════════════════════════════════════
  // AUTO-HOOK CONVENIENCE METHODS
  // These are called automatically by repositories.
  // ═══════════════════════════════════════════════════════

  /// Log sale creation
  Future<int> logSaleCreated({
    required int saleId,
    required int totalCents,
    required String paymentMethod,
    int? customerId,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'sale',
      entityId: saleId,
      action: 'create',
      newValue: {
        'totalCents': totalCents,
        'paymentMethod': paymentMethod,
        'customerId': ?customerId,
      },
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log sale void (CRITICAL)
  Future<int> logSaleVoided({
    required int saleId,
    required String reason,
    int? userId,
    String? userRole,
  }) {
    return logVoid(
      entityType: 'sale',
      entityId: saleId,
      reason: reason,
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log sale return creation
  Future<int> logSaleReturnCreated({
    required int returnId,
    required int saleId,
    required int totalCents,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'sale_return',
      entityId: returnId,
      action: 'create',
      newValue: {
        'saleId': saleId,
        'totalCents': totalCents,
      },
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log purchase creation
  Future<int> logPurchaseCreated({
    required int purchaseId,
    required int totalCents,
    int? supplierId,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'purchase',
      entityId: purchaseId,
      action: 'create',
      newValue: {
        'totalCents': totalCents,
        'supplierId': ?supplierId,
      },
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log purchase void (CRITICAL)
  Future<int> logPurchaseVoided({
    required int purchaseId,
    required String reason,
    int? userId,
    String? userRole,
  }) {
    return logVoid(
      entityType: 'purchase',
      entityId: purchaseId,
      reason: reason,
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log purchase return creation
  Future<int> logPurchaseReturnCreated({
    required int returnId,
    required int purchaseId,
    required int totalCents,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'purchase_return',
      entityId: returnId,
      action: 'create',
      newValue: {
        'purchaseId': purchaseId,
        'totalCents': totalCents,
      },
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log product creation
  Future<int> logProductCreated({
    required int productId,
    required String productName,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'product',
      entityId: productId,
      action: 'create',
      newValue: {'name': productName},
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log product update
  Future<int> logProductUpdated({
    required int productId,
    required String productName,
    Map<String, dynamic>? changedFields,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'product',
      entityId: productId,
      action: 'update',
      newValue: {
        'name': productName,
        if (changedFields != null) ...changedFields,
      },
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log product deletion (CRITICAL)
  Future<int> logProductDeleted({
    required int productId,
    required String productName,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'product',
      entityId: productId,
      action: 'delete',
      oldValue: {'name': productName},
      userId: userId,
      userRole: userRole,
      severity: AuditSeverity.critical,
    );
  }

  /// Log user creation (CRITICAL)
  Future<int> logUserCreated({
    required int targetUserId,
    required String username,
    required String role,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'user',
      entityId: targetUserId,
      action: 'create',
      newValue: {'username': username, 'role': role},
      userId: userId,
      userRole: userRole,
      severity: AuditSeverity.critical,
    );
  }

  /// Log user role/permission change (CRITICAL)
  Future<int> logUserUpdated({
    required int targetUserId,
    required String username,
    String? oldRole,
    String? newRole,
    Map<String, dynamic>? changedFields,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'user',
      entityId: targetUserId,
      action: 'update',
      oldValue: {
        'username': username,
        'role': ?oldRole,
      },
      newValue: {
        'role': ?newRole,
        if (changedFields != null) ...changedFields,
      },
      userId: userId,
      userRole: userRole,
      severity: AuditSeverity.critical,
    );
  }

  /// Log user deletion (CRITICAL)
  Future<int> logUserDeleted({
    required int targetUserId,
    required String username,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'user',
      entityId: targetUserId,
      action: 'delete',
      oldValue: {'username': username},
      userId: userId,
      userRole: userRole,
      severity: AuditSeverity.critical,
    );
  }

  /// Log accounting period close (CRITICAL)
  Future<int> logPeriodClosed({
    required int periodId,
    required String periodName,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'accounting_period',
      entityId: periodId,
      action: 'close_period',
      newValue: {'periodName': periodName},
      userId: userId,
      userRole: userRole,
      severity: AuditSeverity.critical,
    );
  }

  /// Log journal entry posted
  Future<int> logJournalEntryPosted({
    required int entryId,
    required int totalDebitCents,
    required int totalCreditCents,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'journal_entry',
      entityId: entryId,
      action: 'post',
      newValue: {
        'totalDebitCents': totalDebitCents,
        'totalCreditCents': totalCreditCents,
      },
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log customer creation
  Future<int> logCustomerCreated({
    required int customerId,
    required String customerName,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'customer',
      entityId: customerId,
      action: 'create',
      newValue: {'name': customerName},
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log customer update
  Future<int> logCustomerUpdated({
    required int customerId,
    required String customerName,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'customer',
      entityId: customerId,
      action: 'update',
      newValue: {'name': customerName},
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log customer deletion
  Future<int> logCustomerDeleted({
    required int customerId,
    required String customerName,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'customer',
      entityId: customerId,
      action: 'delete',
      oldValue: {'name': customerName},
      userId: userId,
      userRole: userRole,
      severity: AuditSeverity.critical,
    );
  }

  /// Log supplier creation
  Future<int> logSupplierCreated({
    required int supplierId,
    required String supplierName,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'supplier',
      entityId: supplierId,
      action: 'create',
      newValue: {'name': supplierName},
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log supplier update
  Future<int> logSupplierUpdated({
    required int supplierId,
    required String supplierName,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'supplier',
      entityId: supplierId,
      action: 'update',
      newValue: {'name': supplierName},
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log below-cost sale override (CRITICAL)
  Future<int> logBelowCostOverride({
    required int saleId,
    required int productId,
    required String productName,
    required int costCents,
    required int sellingPriceCents,
    required int lossCents,
    required String reason,
    required int userId,
    required String userRole,
  }) {
    return log(
      entityType: 'sale',
      entityId: saleId,
      action: 'below_cost_override',
      newValue: {
        'productId': productId,
        'productName': productName,
        'costCents': costCents,
        'sellingPriceCents': sellingPriceCents,
        'lossCents': lossCents,
        'reason': reason,
      },
      userId: userId,
      userRole: userRole,
      severity: AuditSeverity.critical,
    );
  }

  /// Log expense creation
  Future<int> logExpenseCreated({
    required int expenseId,
    required int amountCents,
    required String category,
    int? userId,
    String? userRole,
  }) {
    return log(
      entityType: 'expense',
      entityId: expenseId,
      action: 'create',
      newValue: {
        'amountCents': amountCents,
        'category': category,
      },
      userId: userId,
      userRole: userRole,
    );
  }

  /// Log login event
  Future<int> logUserLogin({
    required int targetUserId,
    required String username,
    required String role,
  }) {
    return log(
      entityType: 'user',
      entityId: targetUserId,
      action: 'login',
      newValue: {'username': username},
      userId: targetUserId,
      userRole: role,
    );
  }

  /// Log logout event
  Future<int> logUserLogout({
    required int targetUserId,
    required String username,
    required String role,
  }) {
    return log(
      entityType: 'user',
      entityId: targetUserId,
      action: 'logout',
      newValue: {'username': username},
      userId: targetUserId,
      userRole: role,
    );
  }

  /// Get audit logs for an entity
  Future<List<AuditLog>> getLogsForEntity({
    required String entityType,
    required int entityId,
  }) async {
    return await (_db.select(_db.auditLogs)
          ..where((l) => l.targetTable.equals(entityType))
          ..where((l) => l.recordId.equals(entityId))
          ..orderBy([(l) => OrderingTerm(expression: l.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Get void logs for an entity
  Future<List<VoidLog>> getVoidLogsForEntity({
    required String entityType,
    required int entityId,
  }) async {
    return await (_db.select(_db.voidLogs)
          ..where((l) => l.targetTable.equals(entityType))
          ..where((l) => l.recordId.equals(entityId))
          ..orderBy([(l) => OrderingTerm(expression: l.voidedAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Get all audit logs for a date range
  Stream<List<AuditLog>> watchAuditLogs({
    DateTime? fromDate,
    DateTime? toDate,
    String? entityType,
    String? action,
  }) {
    var query = _db.select(_db.auditLogs);

    if (fromDate != null) {
      query = query..where((l) => l.createdAt.isBiggerOrEqualValue(fromDate));
    }
    if (toDate != null) {
      query = query..where((l) => l.createdAt.isSmallerOrEqualValue(toDate));
    }
    if (entityType != null) {
      query = query..where((l) => l.targetTable.equals(entityType));
    }
    if (action != null) {
      query = query..where((l) => l.action.equals(action));
    }

    return (query..orderBy([(l) => OrderingTerm(expression: l.createdAt, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Get all void logs for a date range
  Stream<List<VoidLog>> watchVoidLogs({
    DateTime? fromDate,
    DateTime? toDate,
    String? entityType,
  }) {
    var query = _db.select(_db.voidLogs);

    if (fromDate != null) {
      query = query..where((l) => l.voidedAt.isBiggerOrEqualValue(fromDate));
    }
    if (toDate != null) {
      query = query..where((l) => l.voidedAt.isSmallerOrEqualValue(toDate));
    }
    if (entityType != null) {
      query = query..where((l) => l.targetTable.equals(entityType));
    }

    return (query..orderBy([(l) => OrderingTerm(expression: l.voidedAt, mode: OrderingMode.desc)]))
        .watch();
  }
}
