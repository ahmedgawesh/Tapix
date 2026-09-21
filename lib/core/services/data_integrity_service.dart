import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'business/warehouse_stock_scope.dart';

/// Runtime data integrity guard service.
///
/// Provides validation methods that verify accounting invariants before and
/// after critical operations. If an invariant fails, the violation is logged
/// and the operation is prevented (or flagged).
///
/// This service does NOT modify data — it only reads and validates.
class DataIntegrityService {
  final AppDatabase _db;

  DataIntegrityService(this._db);

  // ---------------------------------------------------------------------------
  // INVARIANT 1: Journal entries must always be balanced (debit == credit)
  // ---------------------------------------------------------------------------

  /// Verify that a specific journal entry is balanced.
  /// Returns true if balanced, false if not.
  Future<bool> verifyJournalEntryBalanced(int journalEntryId) async {
    final rows = await _db
        .customSelect(
          'SELECT '
          '  COALESCE(SUM(debit_cents), 0) AS total_debit, '
          '  COALESCE(SUM(credit_cents), 0) AS total_credit '
          'FROM journal_entry_lines '
          'WHERE journal_entry_id = ?',
          variables: [Variable.withInt(journalEntryId)],
        )
        .getSingle();

    final totalDebit = rows.read<int>('total_debit');
    final totalCredit = rows.read<int>('total_credit');

    if (totalDebit != totalCredit) {
      developer.log(
        'INTEGRITY VIOLATION: Journal entry #$journalEntryId is unbalanced! '
        'Debit=$totalDebit Credit=$totalCredit',
        name: 'DATA_INTEGRITY',
      );
      return false;
    }
    return true;
  }

  /// Verify ALL posted journal entries are balanced.
  /// Returns a list of unbalanced journal entry IDs.
  Future<List<int>> findUnbalancedJournalEntries() async {
    final rows = await _db
        .customSelect(
          'SELECT je.id, '
          '  COALESCE(SUM(jel.debit_cents), 0) AS total_debit, '
          '  COALESCE(SUM(jel.credit_cents), 0) AS total_credit '
          'FROM journal_entries je '
          'LEFT JOIN journal_entry_lines jel ON jel.journal_entry_id = je.id '
          'WHERE je.status = ? '
          'GROUP BY je.id '
          'HAVING total_debit != total_credit',
          variables: [Variable.withString('posted')],
        )
        .get();

    final unbalanced = rows.map((r) => r.read<int>('id')).toList();
    if (unbalanced.isNotEmpty) {
      developer.log(
        'INTEGRITY VIOLATION: ${unbalanced.length} unbalanced journal entries found: $unbalanced',
        name: 'DATA_INTEGRITY',
      );
    }
    return unbalanced;
  }

  // ---------------------------------------------------------------------------
  // INVARIANT 2: Stock quantities must never be negative
  // ---------------------------------------------------------------------------

  /// Check for any product variants with negative stock.
  /// Returns list of variant IDs with negative stock.
  Future<List<({int variantId, int productId, int stockQuantity})>>
  findNegativeStockVariants() async {
    final rows = await _db
        .customSelect(
          'SELECT v.id, v.product_id, s.quantity AS stock_quantity '
          'FROM product_variants v JOIN ${WarehouseStockScope.primaryStocks} s ON s.variant_id = v.id '
          'WHERE s.quantity < 0',
        )
        .get();

    final violations = rows
        .map(
          (r) => (
            variantId: r.read<int>('id'),
            productId: r.read<int>('product_id'),
            stockQuantity: r.read<int>('stock_quantity'),
          ),
        )
        .toList();

    if (violations.isNotEmpty) {
      developer.log(
        'INTEGRITY VIOLATION: ${violations.length} variants have negative stock: '
        '${violations.map((v) => 'variant#${v.variantId}=${v.stockQuantity}').join(', ')}',
        name: 'DATA_INTEGRITY',
      );
    }
    return violations;
  }

  /// Validate that a stock deduction will not cause negative stock.
  /// Returns true if the deduction is safe.
  Future<bool> validateStockDeduction({
    required int variantId,
    required int quantity,
  }) async {
    if (quantity < 0) return false;
    final row = await _db
        .customSelect(
          'SELECT s.quantity AS stock_quantity FROM ${WarehouseStockScope.primaryStocks} s '
          'JOIN business_warehouses w ON w.id = s.warehouse_id '
          'JOIN business_branches b ON b.id = w.branch_id '
          'WHERE s.variant_id = ? AND w.is_active = 1 AND b.is_active = 1',
          variables: [Variable.withInt(variantId)],
        )
        .getSingleOrNull();

    if (row == null) {
      developer.log(
        'INTEGRITY WARNING: Variant #$variantId not found for stock validation',
        name: 'DATA_INTEGRITY',
      );
      return false;
    }

    final currentStock = row.read<int>('stock_quantity');
    if (currentStock - quantity < 0) {
      developer.log(
        'INTEGRITY GUARD: Stock deduction blocked for variant #$variantId. '
        'Current=$currentStock, Requested=$quantity, Would result in ${currentStock - quantity}',
        name: 'DATA_INTEGRITY',
      );
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // INVARIANT 3: Trial balance must sum to zero
  // ---------------------------------------------------------------------------

  /// Verify the trial balance sums to zero (total debits == total credits).
  /// Returns the imbalance amount in cents (0 = balanced).
  Future<int> verifyTrialBalance() async {
    final rows = await _db
        .customSelect(
          'SELECT '
          '  COALESCE(SUM(jel.debit_cents), 0) AS total_debit, '
          '  COALESCE(SUM(jel.credit_cents), 0) AS total_credit '
          'FROM journal_entry_lines jel '
          'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
          'WHERE je.status = ?',
          variables: [Variable.withString('posted')],
        )
        .getSingle();

    final totalDebit = rows.read<int>('total_debit');
    final totalCredit = rows.read<int>('total_credit');
    final imbalance = totalDebit - totalCredit;

    if (imbalance != 0) {
      developer.log(
        'INTEGRITY VIOLATION: Trial balance is unbalanced! '
        'Total Debit=$totalDebit, Total Credit=$totalCredit, Imbalance=$imbalance',
        name: 'DATA_INTEGRITY',
      );
    }
    return imbalance;
  }

  // ---------------------------------------------------------------------------
  // FULL INTEGRITY CHECK
  // ---------------------------------------------------------------------------

  /// Run all integrity checks and return a comprehensive report.
  Future<IntegrityReport> runFullIntegrityCheck() async {
    developer.log('Starting full integrity check...', name: 'DATA_INTEGRITY');

    final unbalancedJournals = await findUnbalancedJournalEntries();
    final negativeStock = await findNegativeStockVariants();
    final trialBalanceImbalance = await verifyTrialBalance();

    final report = IntegrityReport(
      unbalancedJournalEntryIds: unbalancedJournals,
      negativeStockVariants: negativeStock,
      trialBalanceImbalanceCents: trialBalanceImbalance,
      timestamp: DateTime.now(),
    );

    developer.log(
      'Integrity check complete: ${report.isHealthy ? "HEALTHY" : "VIOLATIONS FOUND"}\n$report',
      name: 'DATA_INTEGRITY',
    );

    return report;
  }
}

/// Report from a full integrity check.
class IntegrityReport {
  final List<int> unbalancedJournalEntryIds;
  final List<({int variantId, int productId, int stockQuantity})>
  negativeStockVariants;
  final int trialBalanceImbalanceCents;
  final DateTime timestamp;

  IntegrityReport({
    required this.unbalancedJournalEntryIds,
    required this.negativeStockVariants,
    required this.trialBalanceImbalanceCents,
    required this.timestamp,
  });

  bool get isHealthy =>
      unbalancedJournalEntryIds.isEmpty &&
      negativeStockVariants.isEmpty &&
      trialBalanceImbalanceCents == 0;

  @override
  String toString() {
    final buf = StringBuffer()
      ..writeln('IntegrityReport (${timestamp.toIso8601String()})')
      ..writeln('  Unbalanced journals: ${unbalancedJournalEntryIds.length}')
      ..writeln('  Negative stock variants: ${negativeStockVariants.length}')
      ..writeln('  Trial balance imbalance: $trialBalanceImbalanceCents cents');
    return buf.toString();
  }
}
