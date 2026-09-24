import 'dart:async';
import 'package:decimal/decimal.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/suppliers/domain/repositories/supplier_repository.dart';

Supplier sampleSupplier(int id, String code, {bool active = true}) => Supplier(
  id: id,
  name: 'Supplier $code',
  productCode: code,
  defaultSupplyMode: 'standard',
  balanceCents: Decimal.zero,
  openingBalanceCents: Decimal.zero,
  currencyId: 1,
  isActive: active,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

/// All operations remain in memory; no application database is opened.
class SupplierLifecycleRepository extends Fake implements SupplierRepository {
  List<Supplier> rows;
  final StreamController<List<Supplier>> _changes =
      StreamController<List<Supplier>>.broadcast();
  int unsafeEntityUpdates = 0;

  SupplierLifecycleRepository(this.rows);

  @override
  Stream<List<Supplier>> watchAllSuppliers({bool? isActive}) =>
      Stream.multi((out) {
        List<Supplier> filter(List<Supplier> source) => source
            .where((s) => isActive == null || s.isActive == isActive)
            .toList();
        final subscription = _changes.stream.listen(
          (rows) => out.add(filter(rows)),
          onError: out.addError,
          onDone: out.close,
        );
        out.onCancel = subscription.cancel;
        out.add(filter(rows));
      });

  @override
  Future<void> setSupplierActive(int supplierId, bool isActive) async {
    rows = rows
        .map((s) => s.id == supplierId ? s.copyWith(isActive: isActive) : s)
        .toList();
    publish();
  }

  @override
  Future<bool> updateSupplier(Supplier supplier) async {
    unsafeEntityUpdates++;
    throw StateError('Status updates must not replace the full supplier row');
  }

  void publish() => _changes.add(List<Supplier>.of(rows));
  Future<void> close() => _changes.close();
}
