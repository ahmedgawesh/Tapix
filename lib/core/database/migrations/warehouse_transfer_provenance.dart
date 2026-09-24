import '../app_database.dart';

const _transferProvenanceTriggerNames = [
  'transfer_provenance_product_batches_update',
  'transfer_provenance_product_batches_delete',
  'transfer_provenance_product_batches_no_replace',
  'transfer_provenance_batch_consumptions_update',
  'transfer_provenance_batch_consumptions_delete',
  'transfer_provenance_batch_consumptions_no_replace',
];

/// Removes only the guards owned by this migration.
///
/// The names deliberately do not start with `warehouse_transfer`: the Station 3
/// document installer rebuilds every trigger with that prefix, while these
/// guards protect shared inventory-ledger tables and must survive that rebuild.
Future<void> removeWarehouseTransferProvenanceGuards(AppDatabase db) async {
  for (final name in _transferProvenanceTriggerNames) {
    await db.customStatement('DROP TRIGGER IF EXISTS $name');
  }
}

/// Freezes the source identity written by a posted warehouse transfer.
///
/// A destination batch remains operational: quantity, active status, expiry and
/// `updated_at` can still change through the normal stock/expiry services. The
/// fields that prove which dispatch allocation and source lot created it cannot
/// be rebound. Transfer batch-consumption rows are immutable ledger evidence;
/// corrections must be appended as a receipt, recall or another stock movement.
Future<void> installWarehouseTransferProvenanceGuards(AppDatabase db) async {
  await removeWarehouseTransferProvenanceGuards(db);

  await db.customStatement('''
    CREATE TRIGGER transfer_provenance_product_batches_update
    BEFORE UPDATE OF id,warehouse_id,product_id,variant_id,batch_number,
      manufacturer_lot_number,purchase_item_id,supplier_id,origin_batch_id,
      transfer_allocation_id,source,received_date,received_quantity,
      unit_cost_cents,created_at
    ON product_batches
    WHEN OLD.source='warehouse_transfer'
      OR OLD.origin_batch_id IS NOT NULL
      OR OLD.transfer_allocation_id IS NOT NULL
      OR NEW.source='warehouse_transfer'
      OR NEW.origin_batch_id IS NOT NULL
      OR NEW.transfer_allocation_id IS NOT NULL
    BEGIN
      SELECT RAISE(ABORT,'Transfer batch provenance is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER transfer_provenance_product_batches_delete
    BEFORE DELETE ON product_batches
    WHEN OLD.source='warehouse_transfer'
      OR OLD.origin_batch_id IS NOT NULL
      OR OLD.transfer_allocation_id IS NOT NULL
    BEGIN
      SELECT RAISE(ABORT,'Transfer batch provenance cannot be deleted');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER transfer_provenance_product_batches_no_replace
    BEFORE INSERT ON product_batches
    WHEN EXISTS(
      SELECT 1 FROM product_batches prior
      WHERE (prior.id=NEW.id OR prior.batch_number=NEW.batch_number)
        AND (prior.source='warehouse_transfer'
          OR prior.origin_batch_id IS NOT NULL
          OR prior.transfer_allocation_id IS NOT NULL)
    )
    BEGIN
      SELECT RAISE(ABORT,'Transfer batch provenance cannot be replaced');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER transfer_provenance_batch_consumptions_update
    BEFORE UPDATE ON batch_consumptions
    WHEN OLD.transfer_allocation_id IS NOT NULL
      OR NEW.transfer_allocation_id IS NOT NULL
    BEGIN
      SELECT RAISE(ABORT,'Transfer batch ledger is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER transfer_provenance_batch_consumptions_delete
    BEFORE DELETE ON batch_consumptions
    WHEN OLD.transfer_allocation_id IS NOT NULL
    BEGIN
      SELECT RAISE(ABORT,'Transfer batch ledger cannot be deleted');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER transfer_provenance_batch_consumptions_no_replace
    BEFORE INSERT ON batch_consumptions
    WHEN EXISTS(
      SELECT 1 FROM batch_consumptions prior
      WHERE prior.id=NEW.id AND prior.transfer_allocation_id IS NOT NULL
    )
    BEGIN
      SELECT RAISE(ABORT,'Transfer batch ledger cannot be replaced');
    END
  ''');

  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS transfer_provenance_batches_allocation '
    'ON product_batches(transfer_allocation_id) '
    'WHERE transfer_allocation_id IS NOT NULL',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS transfer_provenance_consumptions_allocation '
    'ON batch_consumptions(transfer_allocation_id) '
    'WHERE transfer_allocation_id IS NOT NULL',
  );
}
