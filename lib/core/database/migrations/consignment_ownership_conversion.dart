import '../app_database.dart';

/// Database-side invariants for the exceptional existing-stock ownership
/// conversion. Application validation improves messages; these triggers are
/// the final barrier against partial, cross-branch or unaudited writes.
Future<void> installConsignmentOwnershipConversionGuards(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_conversion_supplier_status '
    'ON consignment_ownership_conversions(branch_id,supplier_id,status,converted_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_conversion_item_source '
    'ON consignment_ownership_conversion_items(variant_id,supplier_identity_id,source_batch_id)',
  );

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_conversion_insert_guard
    BEFORE INSERT ON consignment_ownership_conversions
    WHEN NEW.status!='posting'
      OR NOT EXISTS(
        SELECT 1 FROM business_contexts c
        WHERE c.id=1 AND c.organization_id=NEW.organization_id
          AND c.branch_id=NEW.branch_id AND c.database_id=NEW.database_id
      )
      OR NOT EXISTS(
        SELECT 1 FROM business_warehouses w
        WHERE w.id=NEW.warehouse_id AND w.organization_id=NEW.organization_id
          AND w.branch_id=NEW.branch_id AND w.is_active=1
      )
      OR NOT EXISTS(
        SELECT 1 FROM consignment_agreements a
        WHERE a.id=NEW.agreement_id AND a.organization_id=NEW.organization_id
          AND a.branch_id=NEW.branch_id AND a.database_id=NEW.database_id
          AND a.supplier_id=NEW.supplier_id AND a.currency_id=NEW.currency_id
      )
      OR NOT EXISTS(
        SELECT 1 FROM consignment_receipts r
        WHERE r.id=NEW.receipt_id AND r.status='posted'
          AND r.warehouse_id=NEW.warehouse_id AND r.supplier_id=NEW.supplier_id
          AND r.agreement_id=NEW.agreement_id AND r.currency_id=NEW.currency_id
      )
      OR NOT EXISTS(
        SELECT 1 FROM users u WHERE u.id=NEW.created_by
          AND u.is_active=1 AND u.role IN ('owner','manager')
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment ownership conversion');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_conversion_identity_guard
    BEFORE UPDATE OF organization_id,branch_id,database_id,warehouse_id,
      supplier_id,agreement_id,currency_id,receipt_id,conversion_number,
      evidence_reference,converted_at,notes,line_count,inventory_value_cents,
      request_key,request_hash,created_by,created_at
    ON consignment_ownership_conversions
    BEGIN
      SELECT RAISE(ABORT,'Consignment ownership conversion intent is immutable');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_conversion_status_guard
    BEFORE UPDATE OF status,journal_entry_id,supplier_transaction_id,
      void_request_key,void_request_hash,voided_by,voided_at,void_reason,
      reversal_journal_entry_id,reversal_supplier_transaction_id
    ON consignment_ownership_conversions
    WHEN NOT (
      OLD.status='posting' AND NEW.status='posted'
      AND NEW.journal_entry_id IS NOT NULL
      AND NEW.supplier_transaction_id IS NOT NULL
      AND NEW.void_request_key IS NULL AND NEW.void_request_hash IS NULL
      AND NEW.voided_by IS NULL AND NEW.voided_at IS NULL
      AND length(NEW.void_reason)=0
      AND NEW.reversal_journal_entry_id IS NULL
      AND NEW.reversal_supplier_transaction_id IS NULL
      AND NEW.line_count=(SELECT COUNT(*) FROM consignment_ownership_conversion_items i WHERE i.conversion_id=OLD.id)
      AND NEW.inventory_value_cents=(SELECT SUM(i.inventory_amount_cents) FROM consignment_ownership_conversion_items i WHERE i.conversion_id=OLD.id)
    ) AND NOT (
      OLD.status='posted' AND NEW.status='voided'
      AND NEW.journal_entry_id=OLD.journal_entry_id
      AND NEW.supplier_transaction_id=OLD.supplier_transaction_id
      AND length(NEW.void_request_key)=36 AND length(NEW.void_request_hash)=64
      AND NEW.voided_by IS NOT NULL AND NEW.voided_at IS NOT NULL
      AND length(trim(NEW.void_reason))>0
      AND NEW.reversal_journal_entry_id IS NOT NULL
      AND NEW.reversal_supplier_transaction_id IS NOT NULL
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment ownership conversion transition');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_conversion_no_delete
    BEFORE DELETE ON consignment_ownership_conversions
    BEGIN
      SELECT RAISE(ABORT,'Consignment ownership conversion audit cannot be deleted');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_conversion_items_insert_guard
    BEFORE INSERT ON consignment_ownership_conversion_items
    WHEN NOT EXISTS(
      SELECT 1 FROM consignment_ownership_conversions c
      JOIN consignment_receipt_items ri ON ri.id=NEW.receipt_item_id
      JOIN consignment_receipts r ON r.id=ri.receipt_id
      WHERE c.id=NEW.conversion_id AND c.status='posting'
        AND r.id=c.receipt_id AND r.status='posted'
        AND ri.product_id=NEW.product_id AND ri.variant_id=NEW.variant_id
        AND ri.quantity=NEW.quantity AND ri.quantity_scale=NEW.quantity_scale
        AND ri.measurement_type=NEW.measurement_type
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment ownership conversion item');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_conversion_items_immutable
    BEFORE UPDATE ON consignment_ownership_conversion_items
    BEGIN
      SELECT RAISE(ABORT,'Consignment ownership conversion items are immutable');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_conversion_items_no_delete
    BEFORE DELETE ON consignment_ownership_conversion_items
    BEGIN
      SELECT RAISE(ABORT,'Consignment ownership conversion items are immutable');
    END
  ''');
}
