import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../datasources/supplier_local_datasource.dart';

/// Implementation of SupplierRepository
class SupplierRepositoryImpl implements SupplierRepository {
  final SupplierLocalDatasource _datasource;
  final AuditLogService _auditService;
  final SessionService _sessionService;

  SupplierRepositoryImpl(this._datasource, this._auditService, this._sessionService);

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
  }) {
    final companion = SuppliersCompanion(
      name: Value(name),
      email: Value(email),
      phone: Value(phone),
      address: Value(address),
      currencyId: Value(currencyId),
      balanceCents: Value(initialBalance ?? Decimal.zero),
      isActive: const Value(true),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    );
    return _datasource.createSupplier(companion);
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

  @override
  Future<void> updateSupplierBalance(int supplierId, int newBalanceCents) async {
    final existing = await _datasource.getSupplier(supplierId);
    final oldBalance = existing?.balanceCents.toBigInt().toInt();

    await _datasource.updateSupplierBalance(supplierId, newBalanceCents);

    await _auditService.log(
      entityType: 'supplier',
      entityId: supplierId,
      action: 'balance_change',
      oldValue: oldBalance == null ? null : {'balanceCents': oldBalance},
      newValue: {
        'balanceCents': newBalanceCents,
        'changeCents': oldBalance == null ? null : (newBalanceCents - oldBalance),
        'reason': 'supplier_balance_update',
      },
      userId: await _currentUserId(),
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
  }) {
    final companion = SupplierTransactionsCompanion(
      supplierId: Value(supplierId),
      transactionType: Value(transactionType),
      amountCents: Value(Decimal.fromInt(amountCents)),
      currencyId: Value(currencyId),
      description: Value(description),
      referenceId: Value(referenceId),
      referenceType: Value(referenceType),
      discountType: Value(discountType),
      transactionDate: Value(DateTime.now()),
      createdAt: Value(DateTime.now()),
    );
    return _datasource.createTransaction(companion);
  }

  @override
  Future<SupplierTransaction?> getTransaction(int transactionId) {
    return _datasource.getTransaction(transactionId);
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
