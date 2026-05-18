import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../datasources/supplier_local_datasource.dart';

/// Implementation of SupplierRepository
class SupplierRepositoryImpl implements SupplierRepository {
  final SupplierLocalDatasource _datasource;
  final SessionService _sessionService;
  final JournalEntryService _journalService;
  final AppDatabase _db;
  final AuditLogService _auditService;

  SupplierRepositoryImpl(this._datasource, this._sessionService, this._journalService, this._db, this._auditService);

  Future<int?> _currentUserId() => _sessionService.getCurrentUserId();

  @override
  Stream<List<Supplier>> watchAllSuppliers({bool? isActive}) {
    return _datasource.watchAllSuppliers(isActive: isActive);
  }

  @override
  Stream<Supplier?> watchSupplier(int id) {
    return _datasource.watchSupplier(id);
  }

  @override
  Future<Supplier?> getSupplier(int id) {
    return _datasource.getSupplier(id);
  }

  @override
  Future<List<Supplier>> searchSuppliers(String query, {bool? isActive}) {
    return _datasource.searchSuppliers(query, isActive: isActive);
  }

  @override
  Future<int> createSupplier({
    required String name,
    String? email,
    String? phone,
    String? address,
    required int currencyId,
    Decimal? initialBalance,
  }) async {
    final balanceCents = initialBalance ?? Decimal.zero;
    final companion = SuppliersCompanion(
      name: Value(name),
      email: Value(email),
      phone: Value(phone),
      address: Value(address),
      currencyId: Value(currencyId),
      balanceCents: Value(balanceCents),
      openingBalanceCents: Value(balanceCents), // Store opening balance separately
      isActive: const Value(true),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    );

    final balanceInt = balanceCents.toBigInt().toInt();

    // ATOMIC: create supplier + post opening balance journal entry together
    final supplierId = await _db.transaction(() async {
      final id = await _datasource.createSupplier(companion);

      if (balanceInt != 0) {
        final userId = await _currentUserId();
        await _journalService.recordSupplierOpeningBalanceJournalEntry(
          supplierId: id,
          amountCents: balanceInt,
          currencyId: currencyId,
          userId: userId,
        );
      }

      return id;
    });

    return supplierId;
  }

  @override
  Future<bool> updateSupplier(Supplier supplier) {
    return _datasource.updateSupplier(supplier);
  }

  @override
  Future<int> deleteSupplier(int id) {
    return _datasource.deleteSupplier(id);
  }

  @override
  Stream<int> watchSupplierCount({bool? isActive}) {
    return _datasource.watchSupplierCount(isActive: isActive);
  }

  @override
  Stream<int> watchTotalBalanceCents() {
    return _datasource.watchTotalBalanceCents();
  }

  @override
  Stream<List<Supplier>> watchSuppliersWithPositiveBalance() {
    return _datasource.watchSuppliersWithPositiveBalance();
  }

  @override
  Stream<List<Supplier>> watchTopSuppliersByBalance({int limit = 5}) {
    return _datasource.watchTopSuppliersByBalance(limit: limit);
  }

  /// DISABLED: Direct balance updates WITHOUT journal entries are forbidden.
  /// Supplier balance must ONLY change through journal-entry-backed operations:
  ///   - createSupplier() with initialBalance
  ///   - recordTransaction('adjustment') for balance adjustments
  ///   - PurchaseDao for purchase/payment/return operations
  ///
  /// This prevents GL ↔ Suppliers balance mismatch.
  @override
  Future<void> updateSupplierBalance(int supplierId, int newBalanceCents) async {
    throw StateError(
      'Direct supplier balance updates are DISABLED. '
      'Use recordTransaction(transactionType: "adjustment") instead, '
      'which atomically updates both the supplier balance and the General Ledger.',
    );
  }

  @override
  Future<int> recordTransaction({
    required int supplierId,
    required String transactionType,
    required int amountCents,
    required int currencyId,
    String? description,
    int? referenceId,
    String? referenceType,
    String? discountType,
    DateTime? transactionDate,
  }) async {
    final now = DateTime.now();
    final companion = SupplierTransactionsCompanion(
      supplierId: Value(supplierId),
      transactionType: Value(transactionType),
      amountCents: Value(Decimal.fromInt(amountCents)),
      currencyId: Value(currencyId),
      description: Value(description),
      referenceId: Value(referenceId),
      referenceType: Value(referenceType),
      discountType: Value(discountType),
      transactionDate: Value(transactionDate ?? now),
      createdAt: Value(now),
    );
    // ATOMIC: Wrap supplier transaction (which updates balance) and
    // journal entry creation in a single transaction.
    final userId = await _currentUserId();
    final absAmount = amountCents.abs();

    final txId = await _db.transaction(() async {
      final id = await _datasource.createTransaction(companion);

      // Post journal entries for direct party transactions
      if (transactionType == 'payment' && absAmount > 0) {
        await _journalService.recordDirectSupplierPaymentJournalEntry(
          transactionId: id,
          amountCents: absAmount,
          currencyId: currencyId,
          userId: userId,
        );
      } else if (transactionType == 'discount' && absAmount > 0) {
        await _journalService.recordDirectSupplierDiscountJournalEntry(
          transactionId: id,
          amountCents: absAmount,
          currencyId: currencyId,
          userId: userId,
        );
      } else if (transactionType == 'adjustment' && amountCents != 0) {
        // Balance adjustment uses the opening balance equity account.
        // amountCents carries the sign: positive = we owe supplier more,
        // negative = we owe supplier less.
        await _journalService.recordSupplierOpeningBalanceJournalEntry(
          supplierId: supplierId,
          amountCents: amountCents,
          currencyId: currencyId,
          userId: userId,
        );
      }

      return id;
    });

    return txId;
  }

  @override
  Future<int?> adjustOpeningBalance({
    required int supplierId,
    required int desiredBalanceCents,
    String? description,
  }) async {
    // Mirror of CustomerRepositoryImpl.adjustOpeningBalance — wrap the
    // read + post in a single DB transaction to eliminate the TOCTOU race
    // window between reading the current balance and posting the
    // adjustment.
    return _db.transaction(() async {
      final existing = await _datasource.getSupplier(supplierId);
      if (existing == null) {
        throw StateError('Supplier $supplierId not found');
      }
      final currentCents = existing.balanceCents.toBigInt().toInt();
      final deltaCents = desiredBalanceCents - currentCents;
      if (deltaCents == 0) return null;

      return await recordTransaction(
        supplierId: supplierId,
        transactionType: 'adjustment',
        amountCents: deltaCents,
        currencyId: existing.currencyId,
        description: description,
      );
    });
  }

  @override
  Future<SupplierTransaction?> getTransaction(int transactionId) {
    return _datasource.getTransaction(transactionId);
  }

  @override
  Future<SupplierTransaction> updateTransaction({
    required int transactionId,
    required int newAmountCents,
    String? newDescription,
  }) async {
    // 1. Fetch existing transaction to validate and get date
    final existing = await _datasource.getTransaction(transactionId);
    if (existing == null) {
      throw StateError('Transaction #$transactionId not found');
    }

    // 2. Check accounting period is open for the transaction date
    final txDate = existing.transactionDate;
    final periodRows = await _db.customSelect(
      '''SELECT id, is_closed FROM accounting_periods
         WHERE start_date <= ? AND end_date >= ?
         ORDER BY start_date DESC LIMIT 1''',
      variables: [
        Variable.withDateTime(txDate),
        Variable.withDateTime(txDate),
      ],
      readsFrom: {_db.accountingPeriods},
    ).get();
    if (periodRows.isNotEmpty && periodRows.first.read<bool>('is_closed')) {
      throw StateError(
        'Cannot edit transaction: the accounting period containing this '
        'transaction has been closed.',
      );
    }

    final userId = await _currentUserId();
    final oldAmountCents = existing.amountCents.toBigInt().toInt().abs();
    final absNewAmount = newAmountCents.abs();

    // 3. ATOMIC: update transaction + void old journal + create new journal
    final oldTx = await _db.transaction(() async {
      final old = await _datasource.updateTransactionAmount(
        transactionId,
        newAmountCents: absNewAmount,
        newDescription: newDescription,
      );

      // Void old journal entries for this transaction
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'supplier_transactions',
        sourceId: transactionId,
        reason: 'Transaction amount edited from $oldAmountCents to $absNewAmount cents',
        userId: userId,
      );

      // Create new journal entries with updated amount
      if (existing.transactionType == 'payment' && absNewAmount > 0) {
        await _journalService.recordDirectSupplierPaymentJournalEntry(
          transactionId: transactionId,
          amountCents: absNewAmount,
          currencyId: existing.currencyId,
          userId: userId,
        );
      } else if (existing.transactionType == 'discount' && absNewAmount > 0) {
        await _journalService.recordDirectSupplierDiscountJournalEntry(
          transactionId: transactionId,
          amountCents: absNewAmount,
          currencyId: existing.currencyId,
          userId: userId,
        );
      }

      return old;
    });

    // 4. Audit log
    await _auditService.log(
      entityType: 'supplier_transaction',
      entityId: transactionId,
      action: 'edit_transaction',
      oldValue: {
        'amountCents': oldAmountCents,
        'type': existing.transactionType,
        'supplierId': existing.supplierId,
      },
      newValue: {
        'amountCents': absNewAmount,
        'description': newDescription,
      },
      userId: userId,
    );

    return oldTx;
  }

  @override
  Stream<List<SupplierTransaction>> watchSupplierTransactions(int supplierId) {
    return _datasource.watchSupplierTransactions(supplierId);
  }

  @override
  Future<List<SupplierTransaction>> getSupplierTransactions(
    int supplierId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _datasource.getSupplierTransactions(
      supplierId,
      startDate: startDate,
      endDate: endDate,
    );
  }
}
