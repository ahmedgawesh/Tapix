import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/business_document_type.dart';

/// Read-only ownership API. SQLite assigns locations atomically on insertion;
/// callers cannot move a document by supplying a different warehouse ID.
class BusinessDocumentRepository {
  BusinessDocumentRepository(this._db);
  final AppDatabase _db;

  Future<BusinessDocumentLocation> getLocation(
    BusinessDocumentType type,
    int sourceId,
  ) async {
    if (sourceId <= 0) throw ArgumentError.value(sourceId, 'sourceId');
    final row =
        await (_db.select(_db.businessDocumentLocations)..where(
              (l) =>
                  l.sourceTable.equals(type.sourceTable) &
                  l.sourceId.equals(sourceId),
            ))
            .getSingleOrNull();
    if (row == null) throw StateError('Document location was not found.');
    return row;
  }

  /// Source tables are explicit dependencies because inserts/deletes update
  /// location metadata through SQLite triggers, outside Drift's write tracking.
  Stream<List<BusinessDocumentLocation>> watchLocations(
    BusinessDocumentType type,
  ) {
    return _db
        .customSelect(
          'SELECT * FROM business_document_locations WHERE source_table = ? ORDER BY source_id',
          variables: [Variable.withString(type.sourceTable)],
          readsFrom: {_db.businessDocumentLocations, _sourceTable(type)},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows) _db.businessDocumentLocations.map(row.data),
          ],
        );
  }

  TableInfo<Table, dynamic> _sourceTable(BusinessDocumentType type) =>
      switch (type) {
        BusinessDocumentType.sale => _db.sales,
        BusinessDocumentType.purchase => _db.purchases,
        BusinessDocumentType.saleReturn => _db.saleReturns,
        BusinessDocumentType.purchaseReturn => _db.purchaseReturns,
        BusinessDocumentType.saleReturnAdjustment => _db.saleReturnAdjustments,
        BusinessDocumentType.purchaseReturnAdjustment =>
          _db.purchaseReturnAdjustments,
        BusinessDocumentType.inventoryAdjustment => _db.inventoryAdjustments,
        BusinessDocumentType.productBatch => _db.productBatches,
        BusinessDocumentType.journalEntry => _db.journalEntries,
      };
}
