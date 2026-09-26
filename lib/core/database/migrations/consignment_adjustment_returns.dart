import '../app_database.dart';
import 'consignment_return_liability.dart';

Future<void> installConsignmentAdjustmentReturnGuards(AppDatabase db) async {
  await installConsignmentReturnLiabilityGuards(db);
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_adj_event_insert_guard',
  );
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_adj_event_identity_guard',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_adj_events_supplier '
    'ON consignment_adjustment_return_events('
    'supplier_id,currency_id,settlement_status,occurred_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_adj_items_layer '
    'ON sale_return_adjustment_items(consignment_layer_id)',
  );

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_adj_event_insert_guard
    BEFORE INSERT ON consignment_adjustment_return_events
    WHEN NEW.journal_entry_id IS NOT NULL
      OR NEW.settlement_status!='unassigned'
      OR NOT EXISTS(
        SELECT 1
        FROM sale_return_adjustment_items i
        JOIN sale_return_adjustments r ON r.id=i.return_id
        JOIN consignment_inventory_layers l ON l.id=i.consignment_layer_id
        WHERE i.id=NEW.return_item_id
          AND r.id=NEW.return_id
          AND l.id=NEW.layer_id
          AND l.supplier_id=NEW.supplier_id
          AND l.agreement_id=NEW.agreement_id
          AND r.currency_id=NEW.currency_id
          AND r.warehouse_id=l.warehouse_id
          AND i.product_id=l.product_id
          AND i.variant_id=l.variant_id
          AND (
            (NEW.kind='adjustment_return_reversal'
              AND r.status IN ('draft','pending')
              AND NEW.signed_quantity=-i.quantity
              AND NEW.signed_amount_cents<=0
              AND NEW.restores_stock=CASE
                WHEN i.disposition_type='restock' THEN 1 ELSE 0 END
              AND (
                i.disposition_type='restock'
                OR EXISTS(
                  SELECT 1
                  FROM consignment_return_liability_decisions d
                  WHERE d.source_table='sale_return_adjustments'
                    AND d.source_id=r.id
                    AND d.source_item_id=i.id
                    AND d.disposition_type=i.disposition_type
                    AND d.responsibility IN ('supplier','company')
                    AND (
                      d.responsibility='supplier'
                      OR (d.responsibility='company'
                        AND NEW.signed_amount_cents=0)
                    )
                )
              ))
            OR
            (NEW.kind='adjustment_return_void_reaccrual'
              AND r.status='posted'
              AND NEW.signed_quantity=i.quantity
              AND NEW.signed_amount_cents>=0
              AND EXISTS(
                SELECT 1 FROM consignment_adjustment_return_events old
                WHERE old.return_item_id=i.id
                  AND old.kind='adjustment_return_reversal'
                  AND old.signed_quantity=-NEW.signed_quantity
                  AND old.signed_amount_cents=-NEW.signed_amount_cents
                  AND old.restores_stock=NEW.restores_stock
              ))
          )
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment adjustment-return event');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_adj_event_identity_guard
    BEFORE UPDATE OF layer_id,supplier_id,agreement_id,currency_id,kind,
      signed_quantity,signed_amount_cents,restores_stock,return_id,
      return_item_id,request_key,occurred_at,created_at
    ON consignment_adjustment_return_events
    BEGIN
      SELECT RAISE(ABORT,'Consignment adjustment-return event is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_adj_event_journal_guard
    BEFORE UPDATE OF journal_entry_id ON consignment_adjustment_return_events
    WHEN OLD.journal_entry_id IS NOT NULL
      OR NEW.journal_entry_id IS NULL
      OR NOT EXISTS(
        SELECT 1 FROM journal_entries j
        WHERE j.id=NEW.journal_entry_id
          AND j.status='posted'
          AND j.source_table='consignment_adjustment_return_events'
          AND j.source_id=OLD.id
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment adjustment-return journal');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_adj_event_no_delete
    BEFORE DELETE ON consignment_adjustment_return_events
    BEGIN
      SELECT RAISE(ABORT,'Consignment adjustment-return events are immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_adj_return_completion_guard
    BEFORE UPDATE OF status ON sale_return_adjustments
    WHEN NEW.status IN ('posted','voided')
      AND (
        EXISTS(
          SELECT 1 FROM consignment_adjustment_return_events e
          WHERE e.return_id=NEW.id AND e.signed_amount_cents!=0 AND e.journal_entry_id IS NULL
        )
        OR EXISTS(
          SELECT 1 FROM sale_return_adjustment_items i
          WHERE i.return_id=NEW.id AND i.consignment_layer_id IS NOT NULL
            AND NOT EXISTS(
              SELECT 1 FROM consignment_adjustment_return_events e
              WHERE e.return_item_id=i.id
                AND e.kind=CASE WHEN NEW.status='posted'
                  THEN 'adjustment_return_reversal'
                  ELSE 'adjustment_return_void_reaccrual' END
                AND (e.signed_amount_cents=0 OR e.journal_entry_id IS NOT NULL)
            )
        )
      )
    BEGIN
      SELECT RAISE(ABORT,'Consignment adjustment return requires posted journals');
    END
  ''');
}
