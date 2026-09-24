import '../app_database.dart';

/// Installs append-only guards for consignment sale allocations and obligation
/// events. Application services still validate business policy; these guards
/// prevent alternate DAO, LAN or restore paths from rewriting posted history.
Future<void> installConsignmentSalesGuards(AppDatabase db) async {
  // These two guards evolve with additive event columns. Recreate them so
  // upgraded databases enforce the same contract as fresh databases.
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_obligation_events_insert_guard',
  );
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_obligation_events_identity_guard',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_sale_allocations_line '
    'ON consignment_sale_allocations(sale_item_id,sequence)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_sale_allocations_layer '
    'ON consignment_sale_allocations(layer_id,status)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_obligations_supplier '
    'ON consignment_obligation_events(supplier_id,currency_id,settlement_status,occurred_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_obligations_source '
    'ON consignment_obligation_events(source_table,source_id,source_item_id)',
  );

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_sale_allocations_insert_guard
    BEFORE INSERT ON consignment_sale_allocations
    WHEN NOT EXISTS(
      SELECT 1
      FROM sale_items si
      JOIN sales s ON s.id=si.sale_id
      JOIN consignment_inventory_layers l ON l.id=NEW.layer_id
      WHERE si.id=NEW.sale_item_id
        AND s.status IN ('draft','pending')
        AND s.warehouse_id=NEW.warehouse_id
        AND l.warehouse_id=NEW.warehouse_id
        AND l.supplier_id=NEW.supplier_id
        AND l.agreement_id=NEW.agreement_id
        AND l.product_id=si.product_id
        AND l.variant_id=si.variant_id
        AND l.status='open'
        AND l.remaining_quantity>=NEW.quantity
        AND si.quantity_scale=NEW.quantity_scale
        AND si.measurement_type=NEW.measurement_type
        AND l.quantity_scale=NEW.quantity_scale
        AND l.measurement_type=NEW.measurement_type
        AND l.settlement_basis=NEW.settlement_basis
        AND l.unit_cost_cents IS NEW.unit_cost_cents
        AND l.supplier_share_bps IS NEW.supplier_share_bps
        AND l.include_line_discount=NEW.include_line_discount
        AND l.include_invoice_discount=NEW.include_invoice_discount
        AND l.include_sales_tax=NEW.include_sales_tax
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment sale allocation');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_sale_allocations_identity_guard
    BEFORE UPDATE OF
      id,sale_item_id,layer_id,warehouse_id,supplier_id,agreement_id,sequence,
      quantity,quantity_scale,measurement_type,settlement_basis,unit_cost_cents,
      supplier_share_bps,include_line_discount,include_invoice_discount,
      include_sales_tax,allocated_subtotal_cents,
      allocated_line_discount_cents,allocated_invoice_discount_cents,
      allocated_tax_cents,settlement_base_cents,obligation_cents,created_at
    ON consignment_sale_allocations
    BEGIN
      SELECT RAISE(ABORT,'Consignment sale allocation is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_sale_allocations_no_delete
    BEFORE DELETE ON consignment_sale_allocations
    BEGIN
      SELECT RAISE(ABORT,'Consignment sale allocation cannot be deleted');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_obligation_events_insert_guard
    BEFORE INSERT ON consignment_obligation_events
    WHEN NEW.journal_entry_id IS NOT NULL
      OR NEW.settlement_status!='unassigned'
      OR NOT EXISTS(
        SELECT 1
        FROM consignment_sale_allocations a
        JOIN sale_items si ON si.id=a.sale_item_id
        JOIN sales s ON s.id=si.sale_id
        WHERE a.id=NEW.allocation_id
          AND a.supplier_id=NEW.supplier_id
          AND a.agreement_id=NEW.agreement_id
          AND s.currency_id=NEW.currency_id
          AND (
            (NEW.kind='sale_accrual'
              AND NEW.restores_stock=1
              AND NEW.source_table='sales'
              AND NEW.source_id=s.id
              AND NEW.source_item_id=si.id
              AND NEW.signed_quantity=a.quantity
              AND NEW.signed_amount_cents=a.obligation_cents
              AND s.status IN ('draft','pending'))
            OR
            (NEW.kind='linked_return_reversal'
              AND NEW.source_table='sale_returns'
              AND NEW.signed_quantity<0
              AND NEW.signed_amount_cents<=0
              AND EXISTS(
                SELECT 1 FROM sale_return_items ri
                JOIN sale_returns r ON r.id=ri.return_id
                WHERE ri.id=NEW.source_item_id
                  AND r.id=NEW.source_id
                  AND ri.sale_item_id=si.id
                  AND r.status IN ('draft','pending')
                  AND NEW.restores_stock=CASE
                    WHEN r.disposition_type IN ('write_off','damaged','scrap')
                    THEN 0 ELSE 1 END
              ))
            OR
            (NEW.kind='return_void_reaccrual'
              AND NEW.source_table='sale_returns'
              AND NEW.signed_quantity>0
              AND NEW.signed_amount_cents>=0
              AND EXISTS(
                SELECT 1 FROM consignment_obligation_events old
                WHERE old.allocation_id=NEW.allocation_id
                  AND old.kind='linked_return_reversal'
                  AND old.source_table=NEW.source_table
                  AND old.source_id=NEW.source_id
                  AND old.source_item_id=NEW.source_item_id
                  AND old.signed_quantity=-NEW.signed_quantity
                  AND old.signed_amount_cents=-NEW.signed_amount_cents
                  AND old.restores_stock=NEW.restores_stock
              ))
            OR
            (NEW.kind IN ('adjustment_return_reversal','adjustment_return_accrual')
              AND NEW.restores_stock=1
              AND ((NEW.signed_quantity<0 AND NEW.signed_amount_cents<=0)
                OR (NEW.signed_quantity>0 AND NEW.signed_amount_cents>=0)))
            OR
            (NEW.kind='sale_void_reversal'
              AND NEW.restores_stock=1
              AND NEW.source_table='sales'
              AND NEW.source_id=s.id
              AND NEW.source_item_id=si.id
              AND NEW.signed_quantity=-(a.quantity-a.reversed_quantity)
              AND NEW.signed_amount_cents=-(a.obligation_cents-a.reversed_obligation_cents)
              AND s.status='completed')
          )
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment obligation event');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_obligation_events_identity_guard
    BEFORE UPDATE OF
      allocation_id,supplier_id,agreement_id,currency_id,kind,signed_quantity,
      signed_amount_cents,restores_stock,source_table,source_id,source_item_id,
      request_key,occurred_at,created_at
    ON consignment_obligation_events
    BEGIN
      SELECT RAISE(ABORT,'Consignment obligation event is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_obligation_events_journal_guard
    BEFORE UPDATE OF journal_entry_id ON consignment_obligation_events
    WHEN OLD.journal_entry_id IS NOT NULL
      OR NEW.journal_entry_id IS NULL
      OR NOT EXISTS(
        SELECT 1 FROM journal_entries j
        WHERE j.id=NEW.journal_entry_id
          AND j.status='posted'
          AND j.source_table='consignment_obligation_events'
          AND j.source_id=OLD.id
      )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment obligation journal');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_obligation_events_no_delete
    BEFORE DELETE ON consignment_obligation_events
    BEGIN
      SELECT RAISE(ABORT,'Consignment obligation events are immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_sale_completion_guard
    BEFORE UPDATE OF status ON sales
    WHEN NEW.status='completed'
      AND (
        EXISTS(
          SELECT 1 FROM consignment_obligation_events e
          WHERE e.source_table='sales' AND e.source_id=NEW.id
            AND e.signed_amount_cents!=0 AND e.journal_entry_id IS NULL
        )
        OR EXISTS(
          SELECT 1 FROM consignment_sale_allocations a
          JOIN sale_items si ON si.id=a.sale_item_id
          WHERE si.sale_id=NEW.id
          GROUP BY a.id
          HAVING NOT EXISTS(
            SELECT 1 FROM consignment_obligation_events e
            WHERE e.allocation_id=a.id AND e.kind='sale_accrual'
          )
        )
      )
    BEGIN
      SELECT RAISE(ABORT,'Consignment sale requires posted accrual journals');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_sale_void_completion_guard
    BEFORE UPDATE OF status ON sales
    WHEN NEW.status='voided'
      AND (
        EXISTS(
          SELECT 1 FROM consignment_obligation_events e
          WHERE e.source_table='sales' AND e.source_id=NEW.id
            AND e.signed_amount_cents!=0 AND e.journal_entry_id IS NULL
        )
        OR EXISTS(
          SELECT 1 FROM consignment_sale_allocations a
          JOIN sale_items si ON si.id=a.sale_item_id
          WHERE si.sale_id=NEW.id
            AND (a.reversed_quantity!=a.quantity
              OR a.reversed_obligation_cents!=a.obligation_cents
              OR a.status!='fully_reversed')
        )
      )
    BEGIN
      SELECT RAISE(ABORT,'Consignment sale void requires complete reversal journals');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_sale_return_completion_guard
    BEFORE UPDATE OF status ON sale_returns
    WHEN NEW.status IN ('posted','voided')
      AND EXISTS(
        SELECT 1 FROM consignment_obligation_events e
        WHERE e.source_table='sale_returns' AND e.source_id=NEW.id
          AND e.signed_amount_cents!=0 AND e.journal_entry_id IS NULL
      )
    BEGIN
      SELECT RAISE(ABORT,'Consignment return requires posted reversal journals');
    END
  ''');
}
