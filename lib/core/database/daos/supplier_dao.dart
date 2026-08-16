import 'package:drift/drift.dart';
import 'package:decimal/decimal.dart';
import '../app_database.dart';
import '../tables/parties.dart';
import '../../services/balance_service.dart';
import '../../services/document_number_service.dart';

part 'supplier_dao.g.dart';

@DriftAccessor(tables: [Suppliers, SupplierTransactions])
class SupplierDao extends DatabaseAccessor<AppDatabase>
    with _$SupplierDaoMixin {
  SupplierDao(super.db);

  Stream<List<Supplier>> watchAllSuppliers({bool? isActive}) {
    final query = select(suppliers);
    if (isActive != null) {
      query.where((s) => s.isActive.equals(isActive));
    }
    query.orderBy([(s) => OrderingTerm(expression: s.name)]);
    return query.watch();
  }

  Stream<Supplier?> watchSupplier(int id) {
    return (select(
      suppliers,
    )..where((s) => s.id.equals(id))).watchSingleOrNull();
  }

  Future<Supplier?> getSupplier(int id) {
    return (select(suppliers)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  Future<List<Supplier>> searchSuppliers(String query, {bool? isActive}) {
    final q = select(suppliers)
      ..where(
        (s) =>
            s.name.like('%$query%') |
            s.phone.like('%$query%') |
            s.email.like('%$query%'),
      );
    if (isActive != null) {
      q.where((s) => s.isActive.equals(isActive));
    }
    return q.get();
  }

  Future<int> createSupplier(SuppliersCompanion supplier) {
    return into(suppliers).insert(supplier);
  }

  Future<bool> updateSupplier(Supplier supplier) {
    return update(suppliers).replace(supplier);
  }

  Future<int> deleteSupplier(int id) {
    return (delete(suppliers)..where((s) => s.id.equals(id))).go();
  }

  Future<String> _nextTransactionNumber(String prefix) =>
      DocumentNumberService(attachedDatabase).nextSupplierTransaction(prefix);

  /// Transaction types that are managed by PurchaseDao and must NOT be routed
  /// through this method. PurchaseDao updates supplier balance directly, so
  /// routing these here would cause double balance updates.
  static const _purchaseOwnedTypes = {
    'purchase',
    'purchase_void',
    'purchase_return',
    'refund',
    'refund_reversal',
  };

  Future<int> createTransaction(SupplierTransactionsCompanion tx) {
    return transaction(() async {
      // Guard: reject types owned by PurchaseDao to prevent double balance updates
      final type = tx.transactionType.value;
      if (_purchaseOwnedTypes.contains(type)) {
        throw StateError(
          'SupplierDao.createTransaction() must not be used for "$type" transactions. '
          'These are managed by PurchaseDao which updates balance directly.',
        );
      }

      // Auto-generate transaction number if not provided
      var companion = tx;
      if (!tx.transactionNumber.present || tx.transactionNumber.value == null) {
        String prefix;
        switch (type) {
          case 'payment':
            prefix = 'CPS';
            break;
          case 'discount':
            prefix = 'DS';
            break;
          case 'purchase':
            prefix = 'PUR';
            break;
          case 'refund':
            prefix = 'SRFN';
            break;
          case 'payment_reversal':
            prefix = 'SPRV';
            break;
          case 'credit_note':
            prefix = 'SCRN';
            break;
          case 'adjustment':
            prefix = 'SADJ';
            break;
          default:
            prefix = 'STXN';
        }
        final txNumber = await _nextTransactionNumber(prefix);
        companion = companion.copyWith(transactionNumber: Value(txNumber));
      }

      final txId = await into(supplierTransactions).insert(companion);

      final supplierId = tx.supplierId.value;
      final deltaCents = tx.amountCents.value.toBigInt().toInt();

      final affectsBalance =
          type == 'purchase' ||
          type == 'payment' ||
          type == 'payment_reversal' ||
          type == 'discount' ||
          type == 'adjustment' ||
          type == 'credit_note' ||
          type == 'credit_note_reversal';

      if (!affectsBalance) {
        return txId;
      }

      await BalanceService.adjustSupplierBalance(
        this,
        supplierId: supplierId,
        deltaCents: deltaCents,
      );

      return txId;
    });
  }

  /// Only 'payment' and 'discount' transactions may be edited.
  static const _editableTypes = {'payment', 'discount'};

  /// Update a payment or discount transaction amount.
  /// Returns the old transaction for audit purposes.
  /// Adjusts the supplier balance by the delta (newAmount - oldAmount).
  Future<SupplierTransaction> updateTransactionAmount(
    int transactionId, {
    required int newAmountCents,
    String? newDescription,
  }) {
    return transaction(() async {
      final existing = await (select(
        supplierTransactions,
      )..where((t) => t.id.equals(transactionId))).getSingleOrNull();
      if (existing == null) {
        throw StateError('Transaction #$transactionId not found');
      }
      if (!_editableTypes.contains(existing.transactionType)) {
        throw StateError(
          'Only payment and discount transactions can be edited. '
          'Got: "${existing.transactionType}"',
        );
      }

      final oldCents = existing.amountCents.toBigInt().toInt();
      // For payments/discounts the stored amount is negative (reduces balance).
      // The caller passes the absolute new amount; we preserve the sign.
      final signedNewAmount = oldCents < 0
          ? -newAmountCents.abs()
          : newAmountCents.abs();
      final deltaCents = signedNewAmount - oldCents;

      // Update the transaction row
      await (update(
        supplierTransactions,
      )..where((t) => t.id.equals(transactionId))).write(
        SupplierTransactionsCompanion(
          amountCents: Value(Decimal.fromInt(signedNewAmount)),
          description: newDescription != null
              ? Value(newDescription)
              : const Value.absent(),
        ),
      );

      // Adjust supplier balance by the delta
      if (deltaCents != 0) {
        await BalanceService.adjustSupplierBalance(
          this,
          supplierId: existing.supplierId,
          deltaCents: deltaCents,
        );
      }

      return existing;
    });
  }

  Future<SupplierTransaction?> getTransaction(int transactionId) {
    return (select(
      supplierTransactions,
    )..where((t) => t.id.equals(transactionId))).getSingleOrNull();
  }

  Stream<List<SupplierTransaction>> watchSupplierTransactions(int supplierId) {
    return (select(supplierTransactions)
          ..where((t) => t.supplierId.equals(supplierId))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.transactionDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Future<List<SupplierTransaction>> getSupplierTransactions(
    int supplierId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final query = select(supplierTransactions)
      ..where((t) => t.supplierId.equals(supplierId));
    if (startDate != null) {
      query.where((t) => t.transactionDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.transactionDate.isSmallerOrEqualValue(endDate));
    }
    query.orderBy([
      (t) =>
          OrderingTerm(expression: t.transactionDate, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  Stream<int> watchSupplierCount({bool? isActive}) {
    final query = selectOnly(suppliers)..addColumns([suppliers.id.count()]);
    if (isActive != null) {
      query.where(suppliers.isActive.equals(isActive));
    }
    return query
        .map((row) => row.read(suppliers.id.count()) ?? 0)
        .watchSingle();
  }

  Stream<int> watchTotalBalanceCents() {
    final query = selectOnly(suppliers)
      ..addColumns([suppliers.balanceCents.sum()])
      ..where(suppliers.isActive.equals(true));
    return query
        .map((row) => row.read(suppliers.balanceCents.sum()) ?? 0)
        .watchSingle();
  }

  Stream<List<Supplier>> watchSuppliersWithPositiveBalance() {
    return (select(suppliers)
          ..where(
            (s) =>
                s.balanceCents.isBiggerThanValue(0) & s.isActive.equals(true),
          )
          ..orderBy([
            (s) => OrderingTerm(
              expression: s.balanceCents,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Stream<List<Supplier>> watchTopSuppliersByBalance({int limit = 5}) {
    return (select(suppliers)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([
            (s) => OrderingTerm(
              expression: s.balanceCents,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(limit))
        .watch();
  }

  /// INTERNAL — absolute-set writer for `suppliers.balance_cents`.
  ///
  /// **DO NOT CALL THIS FROM PRODUCTION CODE.** It bypasses both
  /// `BalanceService` and `JournalEntryService`, so any caller silently
  /// desynchronises the supplier sub-ledger from the General Ledger and
  /// breaks `AccountingRepository.reconcileBalances()`.
  ///
  /// Production paths (Phase 1.3, May 2026) must go through:
  ///   - `BalanceService.adjustSupplierBalance` for delta mutations
  ///     (already used by `purchase_dao`, `adjustment_return_dao`, etc.)
  ///   - `recalculateBalance` below, for idempotent rebuild from
  ///     `supplier_transactions`
  ///
  /// Retained only for legacy migration / repair scripts that seed a
  /// balance before any transactions exist.
  @Deprecated('Use BalanceService.adjustSupplierBalance or recalculateBalance')
  Future<void> updateSupplierBalance(
    int supplierId,
    int newBalanceCents,
  ) async {
    await (update(suppliers)..where((s) => s.id.equals(supplierId))).write(
      SuppliersCompanion(
        balanceCents: Value(Decimal.fromInt(newBalanceCents)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Recalculate supplier balance from opening balance plus the transaction ledger.
  /// The opening balance is stored on the supplier and is not duplicated as a
  /// supplier transaction, so omitting it would erase it during reconciliation.
  /// Use this for reconciliation or to fix any balance drift.
  Future<int> recalculateBalance(int supplierId) async {
    return transaction(() async {
      final result = await customSelect(
        'SELECT '
        'COALESCE((SELECT opening_balance_cents FROM suppliers WHERE id = ?), 0) + '
        'COALESCE((SELECT SUM(amount_cents) FROM supplier_transactions '
        "WHERE supplier_id = ? AND transaction_type NOT IN ('refund', 'refund_reversal')), 0) "
        'AS derived_balance',
        variables: [Variable.withInt(supplierId), Variable.withInt(supplierId)],
        readsFrom: {suppliers, supplierTransactions},
      ).getSingle();

      final derivedBalance = result.read<int>('derived_balance');

      await (update(suppliers)..where((s) => s.id.equals(supplierId))).write(
        SuppliersCompanion(
          balanceCents: Value(Decimal.fromInt(derivedBalance)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return derivedBalance;
    });
  }

  /// Recalculate balances for ALL suppliers from their transaction ledgers.
  Future<void> recalculateAllBalances() async {
    final allSuppliers = await select(suppliers).get();
    for (final s in allSuppliers) {
      await recalculateBalance(s.id);
    }
  }
}
