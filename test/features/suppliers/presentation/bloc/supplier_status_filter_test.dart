import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/suppliers/presentation/bloc/suppliers_bloc.dart';
import '../../support/supplier_lifecycle_repository.dart';

void main() {
  late SupplierLifecycleRepository repository;
  late SuppliersBloc bloc;
  SuppliersData getData() =>
      (bloc.state as RealtimeSuccess<SuppliersData>).data;

  Future<void> send(SuppliersEvent event) async {
    final next = bloc.stream.firstWhere(
      (s) => s is RealtimeSuccess<SuppliersData>,
    );
    bloc.add(event);
    await next.timeout(const Duration(seconds: 5));
  }

  setUp(() async {
    repository = SupplierLifecycleRepository([
      sampleSupplier(1, 'N1'),
      sampleSupplier(2, '007', active: false),
    ]);
    bloc = SuppliersBloc(repository);
    await bloc.stream
        .firstWhere((s) => s is RealtimeSuccess<SuppliersData>)
        .timeout(const Duration(seconds: 5));
  });
  tearDown(() async {
    await bloc.close();
    await repository.close();
  });

  test('default active view retains inactive count', () {
    expect(getData().suppliers.map((s) => s.id), [1]);
    expect(getData().inactiveCount, 1);
    expect(getData().totalCount, 2);
  });

  test('inactive and all filters expose retained records', () async {
    await send(
      const SuppliersStatusFilterChanged(SupplierStatusFilter.inactive),
    );
    expect(getData().suppliers.map((s) => s.id), [2]);
    await send(const SuppliersStatusFilterChanged(SupplierStatusFilter.all));
    expect(getData().suppliers, hasLength(2));
  });

  test('search and live updates retain selected status', () async {
    await send(
      const SuppliersStatusFilterChanged(SupplierStatusFilter.inactive),
    );
    await send(const SuppliersSearchRequested('007'));
    final update = bloc.stream.firstWhere(
      (s) => s is RealtimeSuccess<SuppliersData>,
    );
    repository.rows.add(sampleSupplier(3, 'A9', active: false));
    repository.publish();
    await update.timeout(const Duration(seconds: 5));
    expect(getData().suppliers.map((s) => s.id), [2]);
    expect(getData().inactiveCount, 2);
    expect(getData().searchQuery, '007');
  });

  test('code search is case-insensitive and survives refresh', () async {
    await send(const SuppliersSearchRequested('n1'));
    expect(getData().suppliers.map((s) => s.id), [1]);
    final refreshed = bloc.stream.firstWhere(
      (s) => s is RealtimeSuccess<SuppliersData>,
    );
    bloc.refresh();
    await refreshed.timeout(const Duration(seconds: 5));
    expect(getData().searchQuery, 'n1');
    expect(getData().statusFilter, SupplierStatusFilter.active);
  });

  test(
    'reactivation moves supplier to active without whole-row replacement',
    () async {
      await send(
        const SuppliersStatusFilterChanged(SupplierStatusFilter.inactive),
      );
      await send(SupplierToggleActiveRequested(repository.rows[1]));
      expect(getData().suppliers, isEmpty);
      expect(getData().inactiveCount, 0);
      await send(
        const SuppliersStatusFilterChanged(SupplierStatusFilter.active),
      );
      expect(getData().suppliers, hasLength(2));
      expect(repository.unsafeEntityUpdates, 0);
      expect(repository.rows[1].productCode, '007');
    },
  );

  test('empty active list still has inactive records accessible', () async {
    await send(SupplierToggleActiveRequested(repository.rows[0]));
    expect(getData().suppliers, isEmpty);
    expect(getData().inactiveCount, 2);
    await send(
      const SuppliersStatusFilterChanged(SupplierStatusFilter.inactive),
    );
    expect(getData().suppliers, hasLength(2));
  });

  test('clearing search preserves inactive filter', () async {
    await send(
      const SuppliersStatusFilterChanged(SupplierStatusFilter.inactive),
    );
    await send(const SuppliersSearchRequested('missing'));
    expect(getData().suppliers, isEmpty);
    await send(const SuppliersSearchRequested(''));
    expect(getData().suppliers.map((s) => s.id), [2]);
    expect(getData().isSearching, isFalse);
    expect(getData().searchQuery, isNull);
  });
}
