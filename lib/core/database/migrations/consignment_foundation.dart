import '../app_database.dart';

/// Guards the commercial agreement foundation only. Stock ownership, receipt,
/// consumption and settlement tables are introduced by later migrations.
Future<void> installConsignmentFoundationGuards(AppDatabase db) async {
  await db.customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS consignment_one_active_supplier_currency '
    'ON consignment_agreements(branch_id,supplier_id,currency_id) '
    "WHERE status='active'",
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_agreements_supplier_status '
    'ON consignment_agreements(branch_id,supplier_id,status,effective_from)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_agreement_items_product '
    'ON consignment_agreement_items(agreement_id,product_id,variant_id)',
  );

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_agreements_insert_guard
    BEFORE INSERT ON consignment_agreements
    WHEN NEW.status!='draft'
      OR NEW.revision<1
      OR NOT EXISTS(
        SELECT 1 FROM business_contexts c
        WHERE c.id=1
          AND c.organization_id=NEW.organization_id
          AND c.branch_id=NEW.branch_id
          AND c.database_id=NEW.database_id
      )
      OR NOT EXISTS(
        SELECT 1 FROM suppliers s
        WHERE s.id=NEW.supplier_id
          AND s.currency_id=NEW.currency_id
          AND s.is_active=1
      )
      OR NOT EXISTS(
        SELECT 1 FROM users u
        WHERE u.id=NEW.created_by
          AND u.is_active=1
          AND u.role IN ('owner','manager')
      )
      OR (
        NEW.revision=1
        AND EXISTS(
          SELECT 1 FROM consignment_agreements a
          WHERE a.agreement_key=NEW.agreement_key
        )
      )
      OR (
        NEW.revision>1
        AND NOT EXISTS(
          SELECT 1 FROM consignment_agreements a
          WHERE a.agreement_key=NEW.agreement_key
            AND a.revision=NEW.revision-1
            AND a.supplier_id=NEW.supplier_id
            AND a.currency_id=NEW.currency_id
            AND a.branch_id=NEW.branch_id
            AND a.organization_id=NEW.organization_id
            AND a.database_id=NEW.database_id
            AND a.status IN ('active','superseded','closed')
        )
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment agreement draft');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_agreements_identity_guard
    BEFORE UPDATE OF
      id,agreement_key,revision,organization_id,branch_id,database_id,
      supplier_id,currency_id,agreement_number,created_by,created_at
    ON consignment_agreements
    BEGIN
      SELECT RAISE(ABORT,'Consignment agreement identity is immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_agreements_active_terms_guard
    BEFORE UPDATE OF
      effective_from,effective_to,settlement_frequency,payment_terms_days,
      settlement_tax_rate_bps,settlement_tax_inclusive,notes
    ON consignment_agreements
    WHEN OLD.status!='draft'
    BEGIN
      SELECT RAISE(ABORT,'Activated consignment terms are immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_agreements_status_guard
    BEFORE UPDATE OF status,activated_by,activated_at,ended_by,ended_at
    ON consignment_agreements
    WHEN NOT (
      OLD.status='draft'
      AND NEW.status='active'
      AND OLD.activated_by IS NULL
      AND NEW.activated_by IS NOT NULL
      AND NEW.activated_at IS NOT NULL
      AND NEW.ended_by IS NULL
      AND NEW.ended_at IS NULL
      AND EXISTS(
        SELECT 1 FROM users u
        WHERE u.id=NEW.activated_by
          AND u.is_active=1
          AND u.role IN ('owner','manager')
      )
      AND EXISTS(
        SELECT 1 FROM app_settings s
        WHERE s.key='business.consignment_policy.v1.'||NEW.branch_id||'.head'
          AND json_extract(s.value,'\$.organizationId')=NEW.organization_id
          AND json_extract(s.value,'\$.branchId')=NEW.branch_id
          AND json_extract(s.value,'\$.databaseId')=NEW.database_id
          AND json_extract(s.value,'\$.policy.enabled')=1
      )
      AND EXISTS(
        SELECT 1 FROM consignment_agreement_items i
        WHERE i.agreement_id=OLD.id
      )
      AND NOT EXISTS(
        SELECT 1 FROM consignment_agreements a
        WHERE a.id!=OLD.id
          AND a.branch_id=OLD.branch_id
          AND a.supplier_id=OLD.supplier_id
          AND a.currency_id=OLD.currency_id
          AND a.status='active'
      )
    ) AND NOT (
      OLD.status='active'
      AND NEW.status IN ('superseded','closed')
      AND NEW.activated_by=OLD.activated_by
      AND NEW.activated_at=OLD.activated_at
      AND NEW.ended_by IS NOT NULL
      AND NEW.ended_at IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM users u
        WHERE u.id=NEW.ended_by
          AND u.is_active=1
          AND u.role IN ('owner','manager')
      )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment agreement transition');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_agreements_no_delete
    BEFORE DELETE ON consignment_agreements
    WHEN OLD.status!='draft'
    BEGIN
      SELECT RAISE(ABORT,'Activated consignment agreements cannot be deleted');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_agreement_items_insert_guard
    BEFORE INSERT ON consignment_agreement_items
    WHEN NOT EXISTS(
      SELECT 1 FROM consignment_agreements a
      WHERE a.id=NEW.agreement_id AND a.status='draft'
    )
      OR NOT EXISTS(
        SELECT 1 FROM products p
        WHERE p.id=NEW.product_id AND p.is_active=1
      )
      OR (
        NEW.variant_id IS NOT NULL
        AND NOT EXISTS(
          SELECT 1 FROM product_variants v
          WHERE v.id=NEW.variant_id
            AND v.product_id=NEW.product_id
            AND v.is_active=1
        )
      )
      OR EXISTS(
        SELECT 1 FROM consignment_agreement_items i
        WHERE i.agreement_id=NEW.agreement_id
          AND i.product_id=NEW.product_id
          AND (
            i.variant_id IS NULL
            OR NEW.variant_id IS NULL
            OR i.variant_id=NEW.variant_id
          )
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid or overlapping consignment agreement item');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_agreement_items_update_guard
    BEFORE UPDATE ON consignment_agreement_items
    WHEN NOT EXISTS(
      SELECT 1 FROM consignment_agreements a
      WHERE a.id=OLD.agreement_id AND a.status='draft'
    )
      OR NEW.agreement_id!=OLD.agreement_id
    BEGIN
      SELECT RAISE(ABORT,'Activated consignment agreement items are immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_agreement_items_delete_guard
    BEFORE DELETE ON consignment_agreement_items
    WHEN NOT EXISTS(
      SELECT 1 FROM consignment_agreements a
      WHERE a.id=OLD.agreement_id AND a.status='draft'
    )
    BEGIN
      SELECT RAISE(ABORT,'Activated consignment agreement items are immutable');
    END
  ''');
}
