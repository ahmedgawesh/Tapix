import 'package:drift/drift.dart';
import '../database/app_database.dart';

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
    required int userId,
  }) async {
    return await _db.into(_db.auditLogs).insert(
      AuditLogsCompanion.insert(
        targetTable: entityType,
        recordId: entityId,
        action: action,
        changes: {
          'old': oldValue,
          'new': newValue,
          'timestamp': DateTime.now().toIso8601String(),
        },
        userId: Value(userId),
      ),
    );
  }

  /// Log a void action
  Future<int> logVoid({
    required String entityType,
    required int entityId,
    required String reason,
    required int userId,
  }) async {
    // Log to void_logs table
    await _db.into(_db.voidLogs).insert(
      VoidLogsCompanion.insert(
        targetTable: entityType,
        recordId: entityId,
        reason: reason,
        voidedBy: Value(userId),
      ),
    );

    // Also log to audit_logs for complete trail
    return await log(
      entityType: entityType,
      entityId: entityId,
      action: 'void',
      newValue: {'reason': reason},
      userId: userId,
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
    );
  }

  /// Log a price change
  Future<int> logPriceChange({
    required int productId,
    required int oldPriceCents,
    required int newPriceCents,
    required String priceType, // 'selling', 'cost', 'wholesale'
    required int userId,
  }) async {
    return await log(
      entityType: 'product',
      entityId: productId,
      action: 'price_change',
      oldValue: {'${priceType}PriceCents': oldPriceCents},
      newValue: {'${priceType}PriceCents': newPriceCents},
      userId: userId,
    );
  }

  /// Log a stock adjustment
  Future<int> logStockAdjustment({
    required int productId,
    required int oldQuantity,
    required int newQuantity,
    required String reason,
    required int userId,
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
