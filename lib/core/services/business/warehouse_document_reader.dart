import '../../database/app_database.dart';
import 'document_posting_scope.dart';
import 'warehouse_operation_scope.dart';
import 'warehouse_read_scope.dart';

/// Read boundary for document lists and detail views. Authorization remains
/// at the caller; historical reads do not require an active warehouse.
class WarehouseDocumentReader {
  WarehouseDocumentReader(this.db, {this.scope});
  final AppDatabase db;
  final WarehouseOperationScope? scope;

  Future<WarehouseReadScope> _scope() =>
      scope == null ? WarehouseReadScope.resolve(db) : scope!.forReading(db);

  Future<T> snapshot<T>(Future<T> Function(WarehouseReadScope) action) =>
      db.transaction(() async => action(await _scope()));

  Stream<int> get changes => db
      .customSelect(
        'SELECT 1 AS tick',
        readsFrom: {
          db.sales,
          db.saleReturns,
          db.saleReturnAdjustments,
          db.salePayments,
          db.purchases,
          db.purchaseReturns,
          db.purchaseReturnAdjustments,
          db.purchasePayments,
          db.businessDocumentLocations,
          db.businessContexts,
          db.businessWarehouses,
        },
      )
      .watch()
      .map((_) => 1);

  Future<T> readItem<T>(
    InventoryPostingDocument kind,
    int itemId,
    Future<T> Function() action,
    T absent,
  ) => snapshot((selected) async {
    final rows = await db
        .customSelect(
          'SELECT i.id FROM ${kind.items} i JOIN ${selected.documents(kind)} d '
          'ON d.id = i.${kind.parentKey} WHERE i.id = $itemId',
        )
        .get();
    return rows.isEmpty ? absent : action();
  });

  Future<Map<int, List<String>>> searchTerms(
    InventoryPostingDocument kind,
    Map<int, List<String>> rows,
  ) async => Map.fromEntries(
    await filter(rows.entries.toList(), (_) => kind, (r) => r.key),
  );

  Future<Map<String, List<String>>> returnSearchTerms(
    Map<String, List<String>> rows,
  ) async {
    const kinds = {
      'SR': InventoryPostingDocument.saleReturn,
      'SRA': InventoryPostingDocument.saleAdjustment,
      'PR': InventoryPostingDocument.purchaseReturn,
      'PRA': InventoryPostingDocument.purchaseAdjustment,
    };
    final entries = rows.entries.where((r) {
      final parts = r.key.split('-');
      return parts.length == 2 &&
          kinds.containsKey(parts.first) &&
          int.tryParse(parts.last) != null;
    }).toList();
    return Map.fromEntries(
      await filter(
        entries,
        (r) => kinds[r.key.split('-').first]!,
        (r) => int.parse(r.key.split('-').last),
      ),
    );
  }

  Future<Set<int>> ids(InventoryPostingDocument kind, Set<int> rows) async =>
      (await filter(rows.toList(), (_) => kind, (id) => id)).toSet();

  Future<T> read<T>(
    InventoryPostingDocument kind,
    int id,
    Future<T> Function() action,
    T absent,
  ) => db.transaction(() async => await contains(kind, id) ? action() : absent);

  Stream<T> gate<T>(
    InventoryPostingDocument kind,
    int id,
    Stream<T> source,
    T absent,
  ) => source.asyncMap(
    (value) async => await contains(kind, id) ? value : absent,
  );

  Future<bool> contains(InventoryPostingDocument kind, int id) =>
      db.transaction(() async {
        final selected = await _scope();
        final rows = await db
            .customSelect(
              'SELECT id FROM ${selected.documents(kind)} WHERE id = $id',
            )
            .get();
        return rows.isNotEmpty;
      });

  Future<List<T>> filter<T>(
    List<T> rows,
    InventoryPostingDocument Function(T) kindOf,
    int Function(T) idOf,
  ) => db.transaction(() async {
    final selected = await _scope();
    final allowed = <InventoryPostingDocument, Set<int>>{};
    for (final kind in rows.map(kindOf).toSet()) {
      final ids = rows
          .where((r) => kindOf(r) == kind)
          .map(idOf)
          .toSet()
          .toList();
      final found = <int>{};
      // IDs are typed integers, not client SQL. Chunk the query to bound SQL size.
      for (var offset = 0; offset < ids.length; offset += 500) {
        final batch = ids.skip(offset).take(500).join(',');
        final matches = await db
            .customSelect(
              'SELECT id FROM ${selected.documents(kind)} WHERE id IN ($batch)',
            )
            .get();
        found.addAll(matches.map((r) => r.read<int>('id')));
      }
      allowed[kind] = found;
    }
    return rows.where((r) => allowed[kindOf(r)]!.contains(idOf(r))).toList();
  });
}
