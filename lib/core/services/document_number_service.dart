import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Generates permanent, monotonically increasing business document numbers.
///
/// The sequence is stored independently from the business rows, so deleting a
/// document never makes its number available again. Existing legacy numbers
/// are intentionally left untouched.
class DocumentNumberService {
  DocumentNumberService(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<String> nextSaleInvoice() =>
      _next(prefix: 'SI', table: 'sales', column: 'invoice_number');

  Future<String> nextSaleReturn() =>
      _next(prefix: 'SR', table: 'sale_returns', column: 'return_number');

  Future<String> nextSaleAdjustmentReturn() => _next(
    prefix: 'SRS',
    table: 'sale_return_adjustments',
    column: 'return_number',
  );

  Future<String> nextPurchaseInvoice() =>
      _next(prefix: 'PI', table: 'purchases', column: 'purchase_number');

  Future<String> nextPurchaseReturn() =>
      _next(prefix: 'PR', table: 'purchase_returns', column: 'return_number');

  Future<String> nextPurchaseAdjustmentReturn() => _next(
    prefix: 'PRS',
    table: 'purchase_return_adjustments',
    column: 'return_number',
  );

  Future<String> nextCustomerTransaction(String prefix) => _next(
    prefix: prefix,
    table: 'customer_transactions',
    column: 'transaction_number',
  );

  Future<String> nextSupplierTransaction(String prefix) => _next(
    prefix: prefix,
    table: 'supplier_transactions',
    column: 'transaction_number',
  );

  Future<String> _next({
    required String prefix,
    required String table,
    required String column,
  }) async {
    if (!RegExp(r'^[A-Z]+$').hasMatch(prefix)) {
      throw ArgumentError.value(prefix, 'prefix', 'Must contain A-Z only');
    }

    // Identifiers are never supplied by callers. This allow-list prevents a
    // future accidental dynamic identifier from becoming raw SQL input.
    const targets = <String>{
      'sales.invoice_number',
      'sale_returns.return_number',
      'sale_return_adjustments.return_number',
      'purchases.purchase_number',
      'purchase_returns.return_number',
      'purchase_return_adjustments.return_number',
      'customer_transactions.transaction_number',
      'supplier_transactions.transaction_number',
    };
    if (!targets.contains('$table.$column')) {
      throw ArgumentError('Unsupported document number target: $table.$column');
    }

    final now = _clock();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final displayedPrefix = '$prefix-$year$month';

    // The visible number includes year + month, while the counter key only
    // includes the year. Therefore numbering continues through the months of
    // one year and restarts from 1 automatically on January 1st.
    final sequenceKey = '$prefix-$year';

    return _db.transaction(() async {
      // Reconcile with already-created new-format rows. This also makes
      // imported databases safe if their sequence table was not included.
      final maxRow = await _db
          .customSelect(
            'SELECT COALESCE(MAX(CAST(SUBSTR($column, ?) AS INTEGER)), 0) AS max_no '
            'FROM $table WHERE $column GLOB ?',
            variables: [
              Variable<int>(prefix.length + 9),
              Variable<String>('$prefix-$year[0-1][0-9]-[0-9]*'),
            ],
          )
          .getSingle();
      final maxExisting = maxRow.read<int>('max_no');

      await _db.customStatement(
        'INSERT OR IGNORE INTO document_sequences '
        '(prefix, last_number, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)',
        [sequenceKey, maxExisting],
      );
      await _db.customStatement(
        'UPDATE document_sequences '
        'SET last_number = MAX(last_number, ?) + 1, '
        'updated_at = CURRENT_TIMESTAMP WHERE prefix = ?',
        [maxExisting, sequenceKey],
      );
      final sequence = await _db
          .customSelect(
            'SELECT last_number FROM document_sequences WHERE prefix = ?',
            variables: [Variable<String>(sequenceKey)],
          )
          .getSingle();
      final number = sequence.read<int>('last_number');
      return '$displayedPrefix-${number.toString().padLeft(6, '0')}';
    });
  }
}
