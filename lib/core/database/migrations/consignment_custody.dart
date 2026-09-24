import '../app_database.dart';

Future<void> installConsignmentCustodyGuards(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_custody_supplier_status '
    'ON consignment_custody_documents(branch_id,supplier_id,status,occurred_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_custody_layer '
    'ON consignment_custody_items(layer_id,document_id)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_custody_events_settlement '
    'ON consignment_custody_events(supplier_id,agreement_id,settlement_status,occurred_at)',
  );

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_documents_insert_guard
    BEFORE INSERT ON consignment_custody_documents
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
          AND a.organization_id=NEW.organization_id
          AND a.branch_id=NEW.branch_id
          AND a.database_id=NEW.database_id
          AND a.supplier_id=NEW.supplier_id
          AND a.currency_id=NEW.currency_id
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
          AND json_extract(s.value,'$.organizationId')=NEW.organization_id
          AND json_extract(s.value,'$.branchId')=NEW.branch_id
          AND json_extract(s.value,'$.databaseId')=NEW.database_id
          AND json_extract(s.value,'$.policy.enabled')=1
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment custody document');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_documents_identity_guard
    BEFORE UPDATE OF
      organization_id,branch_id,database_id,warehouse_id,supplier_id,
      agreement_id,currency_id,document_number,document_type,responsibility,
      occurred_at,reason,notes,line_count,request_key,request_hash,created_by,
      created_at
    ON consignment_custody_documents
    BEGIN
      SELECT RAISE(ABORT,'Consignment custody document intent is immutable');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_documents_status_guard
    BEFORE UPDATE OF status,posted_by,posted_at,voided_by,voided_at,void_reason
    ON consignment_custody_documents
    WHEN NOT (
      OLD.status='draft'
      AND NEW.status='posted'
      AND NEW.posted_by IS NOT NULL
      AND NEW.posted_at IS NOT NULL
      AND NEW.voided_by IS NULL
      AND NEW.voided_at IS NULL
      AND length(NEW.void_reason)=0
      AND NEW.line_count=(SELECT COUNT(*) FROM consignment_custody_items i WHERE i.document_id=OLD.id)
      AND EXISTS(
        SELECT 1 FROM consignment_custody_events e
        WHERE e.document_id=OLD.id AND e.kind='posted'
          AND e.actor_id=NEW.posted_by
          AND e.signed_quantity=(SELECT SUM(i.quantity) FROM consignment_custody_items i WHERE i.document_id=OLD.id)
          AND e.signed_amount_cents=(SELECT SUM(i.liability_amount_cents) FROM consignment_custody_items i WHERE i.document_id=OLD.id)
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
        SELECT 1 FROM consignment_custody_events e
        WHERE e.document_id=OLD.id AND e.kind='voided'
          AND e.actor_id=NEW.voided_by AND e.reason=NEW.void_reason
      )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment custody transition');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_documents_no_delete
    BEFORE DELETE ON consignment_custody_documents
    BEGIN
      SELECT RAISE(ABORT,'Consignment custody document audit cannot be deleted');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_items_insert_guard
    BEFORE INSERT ON consignment_custody_items
    WHEN NOT EXISTS(
      SELECT 1
      FROM consignment_custody_documents d
      JOIN consignment_inventory_layers l ON l.id=NEW.layer_id
      WHERE d.id=NEW.document_id
        AND d.status='draft'
        AND l.status='open'
        AND l.warehouse_id=d.warehouse_id
        AND l.supplier_id=d.supplier_id
        AND l.agreement_id=d.agreement_id
        AND l.product_id=NEW.product_id
        AND l.variant_id=NEW.variant_id
        AND l.batch_id IS NEW.batch_id
        AND l.quantity_scale=NEW.quantity_scale
        AND NEW.quantity<=l.remaining_quantity
        AND (
          (d.responsibility='company'
            AND d.document_type IN ('loss','damage')
            AND NEW.liability_unit_cents IS NOT NULL
            AND NEW.liability_amount_cents=
              ((NEW.liability_unit_cents*NEW.quantity)+(NEW.quantity_scale/2))/NEW.quantity_scale)
          OR
          (NOT (d.responsibility='company' AND d.document_type IN ('loss','damage'))
            AND NEW.liability_unit_cents IS NULL
            AND NEW.liability_amount_cents=0)
        )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment custody item');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_items_identity_guard
    BEFORE UPDATE OF
      id,document_id,layer_id,product_id,variant_id,batch_id,quantity,
      quantity_scale,liability_unit_cents,liability_amount_cents
    ON consignment_custody_items
    BEGIN
      SELECT RAISE(ABORT,'Consignment custody item intent is immutable');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_items_consumption_guard
    BEFORE UPDATE OF batch_consumption_id ON consignment_custody_items
    WHEN OLD.batch_consumption_id IS NOT NULL
      OR NEW.batch_consumption_id IS NULL
      OR NOT EXISTS(
        SELECT 1 FROM consignment_custody_documents d
        JOIN batch_consumptions b ON b.id=NEW.batch_consumption_id
        WHERE d.id=OLD.document_id
          AND d.status='draft'
          AND b.batch_id=OLD.batch_id
          AND b.direction='out'
          AND b.quantity=OLD.quantity
          AND b.consumption_type='consignment_custody'
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment custody batch link');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_items_no_delete
    BEFORE DELETE ON consignment_custody_items
    BEGIN
      SELECT RAISE(ABORT,'Consignment custody items are immutable');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_events_insert_guard
    BEFORE INSERT ON consignment_custody_events
    WHEN NOT EXISTS(
      SELECT 1 FROM consignment_custody_documents d
      JOIN users u ON u.id=NEW.actor_id
      WHERE d.id=NEW.document_id
        AND d.supplier_id=NEW.supplier_id
        AND d.agreement_id=NEW.agreement_id
        AND d.currency_id=NEW.currency_id
        AND u.is_active=1
        AND u.role IN ('owner','manager')
        AND (
          (NEW.kind='posted' AND d.status='draft'
            AND NEW.signed_quantity=(SELECT SUM(i.quantity) FROM consignment_custody_items i WHERE i.document_id=d.id)
            AND NEW.signed_amount_cents=(SELECT SUM(i.liability_amount_cents) FROM consignment_custody_items i WHERE i.document_id=d.id))
          OR
          (NEW.kind='voided' AND d.status='posted'
            AND length(trim(NEW.reason))>0
            AND NEW.signed_quantity=-(SELECT e.signed_quantity FROM consignment_custody_events e WHERE e.document_id=d.id AND e.kind='posted')
            AND NEW.signed_amount_cents=-(SELECT e.signed_amount_cents FROM consignment_custody_events e WHERE e.document_id=d.id AND e.kind='posted'))
        )
        AND (
          (NEW.signed_amount_cents=0 AND NEW.journal_entry_id IS NULL AND NEW.settlement_status='not_applicable')
          OR
          (NEW.signed_amount_cents!=0 AND NEW.journal_entry_id IS NOT NULL AND NEW.settlement_status='unassigned')
        )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment custody event');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_events_identity_guard
    BEFORE UPDATE OF
      document_id,kind,supplier_id,agreement_id,currency_id,signed_quantity,
      signed_amount_cents,request_key,request_hash,journal_entry_id,actor_id,
      reason,occurred_at,created_at
    ON consignment_custody_events
    BEGIN
      SELECT RAISE(ABORT,'Consignment custody events are immutable');
    END
  ''');

  await db.customStatement(r'''
    CREATE TRIGGER IF NOT EXISTS consignment_custody_events_no_delete
    BEFORE DELETE ON consignment_custody_events
    BEGIN
      SELECT RAISE(ABORT,'Consignment custody events are immutable');
    END
  ''');
}
