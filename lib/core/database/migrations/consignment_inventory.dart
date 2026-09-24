import '../app_database.dart';

Future<void> installConsignmentInventoryGuards(AppDatabase db) async {
  // These guards evolve with the schema. Drop only the two layer guards
  // whose accepted insert shapes changed when warehouse transfers were added.
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_layers_insert_guard',
  );
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_layers_identity_guard',
  );
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS business_stock_supplier_owned_insert_guard
    BEFORE INSERT ON business_warehouse_stocks
    WHEN NEW.supplier_owned_quantity<0
      OR NEW.supplier_owned_quantity>CASE WHEN NEW.quantity>0 THEN NEW.quantity ELSE 0 END
    BEGIN
      SELECT RAISE(ABORT,'Supplier-owned quantity exceeds physical stock');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS business_stock_supplier_owned_update_guard
    BEFORE UPDATE OF quantity,supplier_owned_quantity ON business_warehouse_stocks
    WHEN NEW.supplier_owned_quantity<0
      OR NEW.supplier_owned_quantity>CASE WHEN NEW.quantity>0 THEN NEW.quantity ELSE 0 END
    BEGIN
      SELECT RAISE(ABORT,'Supplier-owned quantity exceeds physical stock');
    END
  ''');

  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_receipts_supplier_status '
    'ON consignment_receipts(branch_id,supplier_id,status,received_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_layers_stock '
    'ON consignment_inventory_layers(warehouse_id,variant_id,status,received_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_layers_supplier '
    'ON consignment_inventory_layers(supplier_id,status,received_at)',
  );

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipts_insert_guard
    BEFORE INSERT ON consignment_receipts
    WHEN NEW.status!='draft'
      OR NOT EXISTS(
        SELECT 1 FROM business_contexts c
        WHERE c.id=1
          AND c.organization_id=NEW.organization_id
          AND c.branch_id=NEW.branch_id
          AND c.database_id=NEW.database_id
      )
      OR NOT EXISTS(
        SELECT 1 FROM business_warehouses w
        WHERE w.id=NEW.warehouse_id
          AND w.organization_id=NEW.organization_id
          AND w.branch_id=NEW.branch_id
          AND w.is_active=1
      )
      OR NOT EXISTS(
        SELECT 1 FROM consignment_agreements a
        WHERE a.id=NEW.agreement_id
          AND a.status='active'
          AND a.organization_id=NEW.organization_id
          AND a.branch_id=NEW.branch_id
          AND a.database_id=NEW.database_id
          AND a.supplier_id=NEW.supplier_id
          AND a.currency_id=NEW.currency_id
          AND a.effective_from<=NEW.received_at
          AND (a.effective_to IS NULL OR a.effective_to>=NEW.received_at)
      )
      OR NOT EXISTS(
        SELECT 1 FROM users u
        WHERE u.id=NEW.created_by
          AND u.is_active=1
          AND u.role IN ('owner','manager')
      )
      OR NOT EXISTS(
        SELECT 1 FROM app_settings s
        WHERE s.key='business.consignment_policy.v1.'||NEW.branch_id||'.head'
          AND json_extract(s.value,'\$.organizationId')=NEW.organization_id
          AND json_extract(s.value,'\$.branchId')=NEW.branch_id
          AND json_extract(s.value,'\$.databaseId')=NEW.database_id
          AND json_extract(s.value,'\$.policy.enabled')=1
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment receipt draft');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipts_identity_guard
    BEFORE UPDATE OF
      id,organization_id,branch_id,database_id,warehouse_id,supplier_id,
      agreement_id,currency_id,receipt_number,request_key,request_hash,
      received_at,notes,line_count,created_by,created_at
    ON consignment_receipts
    BEGIN
      SELECT RAISE(ABORT,'Consignment receipt intent is immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipts_status_guard
    BEFORE UPDATE OF status,posted_by,posted_at,voided_by,voided_at,void_reason
    ON consignment_receipts
    WHEN NOT (
      OLD.status='draft'
      AND NEW.status='posted'
      AND NEW.posted_by IS NOT NULL
      AND NEW.posted_at IS NOT NULL
      AND NEW.voided_by IS NULL
      AND NEW.voided_at IS NULL
      AND length(NEW.void_reason)=0
      AND EXISTS(
        SELECT 1 FROM consignment_receipt_events e
        WHERE e.receipt_id=OLD.id
          AND e.kind='posted'
          AND e.actor_id=NEW.posted_by
      )
      AND NEW.line_count=(SELECT COUNT(*) FROM consignment_receipt_items i WHERE i.receipt_id=OLD.id)
      AND NEW.line_count=(SELECT COUNT(*) FROM consignment_inventory_layers l
        JOIN consignment_receipt_items i ON i.id=l.receipt_item_id
        WHERE i.receipt_id=OLD.id)
      AND NOT EXISTS(
        SELECT 1 FROM consignment_receipt_items i
        LEFT JOIN business_warehouse_stocks s
          ON s.warehouse_id=OLD.warehouse_id AND s.variant_id=i.variant_id
        WHERE i.receipt_id=OLD.id
          AND (
            s.variant_id IS NULL
            OR s.supplier_owned_quantity!=COALESCE((
              SELECT SUM(l.remaining_quantity)
              FROM consignment_inventory_layers l
              WHERE l.warehouse_id=OLD.warehouse_id
                AND l.variant_id=i.variant_id
                AND l.status!='voided'
            ),0)
          )
      )
    ) AND NOT (
      OLD.status='posted'
      AND NEW.status='voided'
      AND NEW.posted_by=OLD.posted_by
      AND NEW.posted_at=OLD.posted_at
      AND NEW.voided_by IS NOT NULL
      AND NEW.voided_at IS NOT NULL
      AND length(trim(NEW.void_reason))>0
      AND EXISTS(
        SELECT 1 FROM consignment_receipt_events e
        WHERE e.receipt_id=OLD.id
          AND e.kind='voided'
          AND e.actor_id=NEW.voided_by
          AND e.reason=NEW.void_reason
      )
      AND NOT EXISTS(
        SELECT 1 FROM consignment_inventory_layers l
        JOIN consignment_receipt_items i ON i.id=l.receipt_item_id
        WHERE i.receipt_id=OLD.id AND l.status!='voided'
      )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment receipt transition');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipts_no_delete
    BEFORE DELETE ON consignment_receipts
    BEGIN
      SELECT RAISE(ABORT,'Consignment receipt audit cannot be deleted');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipt_items_insert_guard
    BEFORE INSERT ON consignment_receipt_items
    WHEN NOT EXISTS(
      SELECT 1
      FROM consignment_receipts r
      JOIN consignment_agreement_items ai
        ON ai.id=NEW.agreement_item_id
        AND ai.agreement_id=r.agreement_id
        AND ai.product_id=NEW.product_id
        AND (ai.variant_id IS NULL OR ai.variant_id=NEW.variant_id)
      JOIN product_variants v
        ON v.id=NEW.variant_id
        AND v.product_id=NEW.product_id
        AND v.is_active=1
      JOIN products p
        ON p.id=NEW.product_id
        AND p.is_active=1
        AND p.track_inventory=1
      WHERE r.id=NEW.receipt_id
        AND r.status='draft'
        AND NEW.settlement_basis=ai.settlement_basis
        AND NEW.unit_cost_cents IS ai.unit_cost_cents
        AND NEW.supplier_share_bps IS ai.supplier_share_bps
        AND NEW.include_line_discount=ai.include_line_discount
        AND NEW.include_invoice_discount=ai.include_invoice_discount
        AND NEW.include_sales_tax=ai.include_sales_tax
        AND NEW.measurement_type=p.measurement_type
        AND NEW.quantity_scale=CASE WHEN p.measurement_type='piece' THEN 1 ELSE 1000 END
        AND (
          p.inventory_tracking_type NOT IN ('batch','batch_expiry')
          OR NEW.manufacturer_lot_number IS NOT NULL
        )
        AND (
          p.inventory_tracking_type!='batch_expiry'
          OR NEW.expiry_date IS NOT NULL
        )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment receipt item');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipt_items_no_update
    BEFORE UPDATE ON consignment_receipt_items
    BEGIN
      SELECT RAISE(ABORT,'Consignment receipt lines are immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipt_items_no_delete
    BEFORE DELETE ON consignment_receipt_items
    BEGIN
      SELECT RAISE(ABORT,'Consignment receipt lines are immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipt_events_insert_guard
    BEFORE INSERT ON consignment_receipt_events
    WHEN NOT EXISTS(
      SELECT 1 FROM consignment_receipts r
      JOIN users u ON u.id=NEW.actor_id
      WHERE r.id=NEW.receipt_id
        AND u.is_active=1
        AND u.role IN ('owner','manager')
        AND (
          (NEW.kind='posted' AND r.status='draft'
            AND r.line_count=(SELECT COUNT(*) FROM consignment_receipt_items i WHERE i.receipt_id=r.id))
          OR
          (NEW.kind='voided' AND r.status='posted' AND length(trim(NEW.reason))>0)
        )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment receipt event');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipt_events_no_change
    BEFORE UPDATE ON consignment_receipt_events
    BEGIN SELECT RAISE(ABORT,'Consignment receipt events are immutable'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_receipt_events_no_delete
    BEFORE DELETE ON consignment_receipt_events
    BEGIN SELECT RAISE(ABORT,'Consignment receipt events are immutable'); END
  ''');

  await db.customStatement('''
    CREATE TRIGGER consignment_layers_insert_guard
    BEFORE INSERT ON consignment_inventory_layers
    WHEN NEW.status!='open'
      OR NEW.remaining_quantity!=NEW.received_quantity
      OR NOT (
        (
          NEW.origin_layer_id IS NULL
          AND NEW.transfer_allocation_id IS NULL
          AND EXISTS(
            SELECT 1 FROM consignment_receipt_items i
            JOIN consignment_receipts r ON r.id=i.receipt_id
            JOIN consignment_receipt_events e
              ON e.receipt_id=r.id AND e.kind='posted'
            WHERE i.id=NEW.receipt_item_id
              AND r.status='draft'
              AND r.warehouse_id=NEW.warehouse_id
              AND r.supplier_id=NEW.supplier_id
              AND r.agreement_id=NEW.agreement_id
              AND i.product_id=NEW.product_id
              AND i.variant_id=NEW.variant_id
              AND i.quantity=NEW.received_quantity
              AND i.quantity_scale=NEW.quantity_scale
              AND i.measurement_type=NEW.measurement_type
              AND i.settlement_basis=NEW.settlement_basis
              AND i.unit_cost_cents IS NEW.unit_cost_cents
              AND i.supplier_share_bps IS NEW.supplier_share_bps
              AND i.include_line_discount=NEW.include_line_discount
              AND i.include_invoice_discount=NEW.include_invoice_discount
              AND i.include_sales_tax=NEW.include_sales_tax
              AND r.received_at=NEW.received_at
          )
        )
        OR
        (
          NEW.origin_layer_id IS NOT NULL
          AND NEW.transfer_allocation_id IS NOT NULL
          AND EXISTS(
            SELECT 1
            FROM warehouse_transfer_allocations a
            JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id AND d.sealed=1
            JOIN warehouse_transfer_lines tl ON tl.id=a.line_id
            JOIN warehouse_transfers t ON t.id=tl.transfer_id
            JOIN consignment_inventory_layers source ON source.id=a.source_consignment_layer_id
            WHERE a.id=NEW.transfer_allocation_id
              AND a.owner_type='consignment'
              AND a.source_consignment_layer_id=NEW.origin_layer_id
              AND t.destination_warehouse_id=NEW.warehouse_id
              AND source.receipt_item_id=NEW.receipt_item_id
              AND source.supplier_id=NEW.supplier_id
              AND source.agreement_id=NEW.agreement_id
              AND source.product_id=NEW.product_id
              AND source.variant_id=NEW.variant_id
              AND source.quantity_scale=NEW.quantity_scale
              AND source.measurement_type=NEW.measurement_type
              AND source.settlement_basis=NEW.settlement_basis
              AND source.unit_cost_cents IS NEW.unit_cost_cents
              AND source.supplier_share_bps IS NEW.supplier_share_bps
              AND source.include_line_discount=NEW.include_line_discount
              AND source.include_invoice_discount=NEW.include_invoice_discount
              AND source.include_sales_tax=NEW.include_sales_tax
              AND NEW.received_quantity<=a.quantity-COALESCE((
                SELECT SUM(existing.received_quantity)
                FROM consignment_inventory_layers existing
                WHERE existing.transfer_allocation_id=a.id
              ),0)
          )
        )
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment inventory layer');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_layers_identity_guard
    BEFORE UPDATE OF
      id,receipt_item_id,origin_layer_id,transfer_allocation_id,
      warehouse_id,supplier_id,agreement_id,product_id,
      variant_id,batch_id,received_quantity,quantity_scale,measurement_type,
      settlement_basis,unit_cost_cents,supplier_share_bps,
      include_line_discount,include_invoice_discount,include_sales_tax,received_at
    ON consignment_inventory_layers
    BEGIN
      SELECT RAISE(ABORT,'Consignment inventory source is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_layers_no_delete
    BEFORE DELETE ON consignment_inventory_layers
    BEGIN
      SELECT RAISE(ABORT,'Consignment inventory audit cannot be deleted');
    END
  ''');
}
