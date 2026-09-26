import '../app_database.dart';

Future<void> removeWarehouseTransferGuards(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND name GLOB 'warehouse_transfer*'",
      )
      .get();
  for (final row in rows) {
    final name = row.read<String>('name').replaceAll('"', '""');
    await db.customStatement('DROP TRIGGER "$name"');
  }
}

Future<void> installWarehouseTransferGuards(AppDatabase db) async {
  await removeWarehouseTransferGuards(db);

  for (final table in [
    'warehouse_transfers',
    'warehouse_transfer_lines',
    'warehouse_transfer_dispatches',
    'warehouse_transfer_allocations',
    'warehouse_transfer_receipts',
    'warehouse_transfer_receipt_items',
    'warehouse_transfer_recalls',
    'warehouse_transfer_recall_items',
    'warehouse_transfer_events',
  ]) {
    await db.customStatement(
      '''CREATE TRIGGER ${table}_no_delete
      BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Transfer audit cannot be deleted'); END''',
    );
  }

  for (final table in [
    'warehouse_transfer_lines',
    'warehouse_transfer_allocations',
    'warehouse_transfer_receipt_items',
    'warehouse_transfer_recall_items',
    'warehouse_transfer_events',
  ]) {
    await db.customStatement(
      '''CREATE TRIGGER ${table}_no_update
      BEFORE UPDATE ON $table BEGIN SELECT RAISE(ABORT,'Transfer contents are immutable'); END''',
    );
  }

  await db.customStatement('''
    CREATE TRIGGER warehouse_transfers_no_replace
    BEFORE INSERT ON warehouse_transfers
    WHEN EXISTS(SELECT 1 FROM warehouse_transfers WHERE id=NEW.id)
    BEGIN SELECT RAISE(ABORT,'Transfer identity already exists'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfers_creation
    BEFORE INSERT ON warehouse_transfers
    WHEN NEW.status!='draft' OR NEW.sealed!=0 OR NOT EXISTS(
      SELECT 1 FROM business_contexts c WHERE c.id=1
        AND c.database_id=NEW.database_id
        AND c.organization_id=NEW.organization_id
        AND c.branch_id=NEW.branch_id)
      OR EXISTS(SELECT 1 FROM warehouse_transfers WHERE request_key=NEW.request_key)
    BEGIN SELECT RAISE(ABORT,'Invalid transfer creation'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfers_identity
    BEFORE UPDATE OF id,organization_id,branch_id,database_id,
      source_warehouse_id,destination_warehouse_id,currency_id,created_by,
      request_key,request_hash,notes,line_count,created_at
    ON warehouse_transfers
    BEGIN SELECT RAISE(ABORT,'Transfer identity and intent are immutable'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_lines_creation
    BEFORE INSERT ON warehouse_transfer_lines
    WHEN NOT EXISTS(
      SELECT 1 FROM warehouse_transfers t
      JOIN product_variants v ON v.id=NEW.variant_id AND v.product_id=NEW.product_id
      WHERE t.id=NEW.transfer_id AND t.status='draft' AND t.sealed=0)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_lines
        WHERE transfer_id=NEW.transfer_id AND variant_id=NEW.variant_id)
    BEGIN SELECT RAISE(ABORT,'Transfer lines cannot change after sealing'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfers_seal
    BEFORE UPDATE OF sealed ON warehouse_transfers
    WHEN NOT(OLD.sealed=0 AND NEW.sealed=1 AND OLD.status='draft'
      AND NEW.line_count=(SELECT COUNT(*) FROM warehouse_transfer_lines
        WHERE transfer_id=OLD.id))
    BEGIN SELECT RAISE(ABORT,'Transfer lines are incomplete or already sealed'); END
  ''');

  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_dispatches_creation
    BEFORE INSERT ON warehouse_transfer_dispatches
    WHEN NEW.sealed!=0 OR NEW.journal_entry_id IS NOT NULL
      OR NOT EXISTS(
        SELECT 1 FROM warehouse_transfers t JOIN users u ON u.id=NEW.actor_id
        WHERE t.id=NEW.transfer_id AND t.status='draft' AND t.sealed=1
          AND u.is_active=1)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_dispatches
        WHERE transfer_id=NEW.transfer_id OR request_key=NEW.request_key)
    BEGIN SELECT RAISE(ABORT,'Invalid transfer dispatch'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_dispatches_identity
    BEFORE UPDATE OF id,transfer_id,request_key,request_hash,actor_id,
      allocation_count,owned_value_cents,dispatched_at,created_at
    ON warehouse_transfer_dispatches
    BEGIN SELECT RAISE(ABORT,'Transfer dispatch is immutable'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_dispatches_finalize
    BEFORE UPDATE OF journal_entry_id,sealed ON warehouse_transfer_dispatches
    WHEN NOT(
      OLD.sealed=0 AND NEW.sealed=1
      AND NEW.allocation_count=(SELECT COUNT(*) FROM warehouse_transfer_allocations a
        WHERE a.dispatch_id=OLD.id)
      AND NEW.owned_value_cents=COALESCE((SELECT SUM(a.value_cents)
        FROM warehouse_transfer_allocations a
        WHERE a.dispatch_id=OLD.id AND a.owner_type='owned'),0)
      AND NOT EXISTS(
        SELECT 1 FROM warehouse_transfer_lines l
        WHERE l.transfer_id=OLD.transfer_id
          AND l.quantity!=COALESCE((SELECT SUM(a.quantity)
            FROM warehouse_transfer_allocations a
            WHERE a.dispatch_id=OLD.id AND a.line_id=l.id),0)
      )
      AND ((NEW.owned_value_cents=0 AND NEW.journal_entry_id IS NULL)
        OR (NEW.owned_value_cents>0 AND EXISTS(
          SELECT 1 FROM journal_entries j
          JOIN warehouse_transfers t ON t.id=OLD.transfer_id
          WHERE j.id=NEW.journal_entry_id
            AND j.status='posted'
            AND j.entry_type='warehouse_transfer_dispatch'
            AND j.source_table='warehouse_transfer_dispatches'
            AND j.source_id=OLD.id
            AND j.total_debit_cents=NEW.owned_value_cents
            AND j.total_credit_cents=NEW.owned_value_cents
            AND (SELECT COUNT(*) FROM journal_entry_lines l
              WHERE l.journal_entry_id=j.id)=2
            AND EXISTS(
              SELECT 1 FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
              WHERE l.journal_entry_id=j.id AND a.account_code='1210'
                AND l.currency_id=t.currency_id
                AND l.debit_cents=NEW.owned_value_cents AND l.credit_cents=0)
            AND EXISTS(
              SELECT 1 FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
              WHERE l.journal_entry_id=j.id AND a.account_code='1200'
                AND l.currency_id=t.currency_id
                AND l.debit_cents=0 AND l.credit_cents=NEW.owned_value_cents)
        )))
    )
    BEGIN SELECT RAISE(ABORT,'Transfer dispatch is incomplete'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_allocations_creation
    BEFORE INSERT ON warehouse_transfer_allocations
    WHEN NOT EXISTS(
      SELECT 1 FROM warehouse_transfer_dispatches d
      JOIN warehouse_transfer_lines l ON l.id=NEW.line_id
      JOIN warehouse_transfers t ON t.id=l.transfer_id AND t.id=d.transfer_id
      WHERE d.id=NEW.dispatch_id AND d.sealed=0 AND t.status='draft'
        AND l.quantity_scale=NEW.quantity_scale
        AND l.measurement_type=NEW.measurement_type)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_allocations
        WHERE dispatch_id=NEW.dispatch_id AND sequence=NEW.sequence)
      OR (NEW.source_batch_id IS NOT NULL AND NOT EXISTS(
        SELECT 1 FROM product_batches b
        JOIN warehouse_transfer_lines l ON l.id=NEW.line_id
        JOIN warehouse_transfers t ON t.id=l.transfer_id
        WHERE b.id=NEW.source_batch_id AND b.warehouse_id=t.source_warehouse_id
          AND b.product_id=l.product_id AND b.variant_id=l.variant_id))
      OR (NEW.owner_type='consignment' AND NOT EXISTS(
        SELECT 1 FROM consignment_inventory_layers c
        JOIN warehouse_transfer_lines l ON l.id=NEW.line_id
        JOIN warehouse_transfers t ON t.id=l.transfer_id
        WHERE c.id=NEW.source_consignment_layer_id
          AND c.warehouse_id=t.source_warehouse_id
          AND c.product_id=l.product_id AND c.variant_id=l.variant_id
          AND c.supplier_id=NEW.supplier_id AND c.agreement_id=NEW.agreement_id))
    BEGIN SELECT RAISE(ABORT,'Invalid transfer allocation'); END
  ''');

  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_batch_consumption_creation
    BEFORE INSERT ON batch_consumptions
    WHEN NEW.transfer_allocation_id IS NOT NULL AND NOT(
      (NEW.direction='out' AND NEW.consumption_type='warehouse_transfer_dispatch'
        AND EXISTS(
          SELECT 1 FROM warehouse_transfer_allocations a
          WHERE a.id=NEW.transfer_allocation_id
            AND a.source_batch_id=NEW.batch_id AND a.quantity=NEW.quantity)
        AND NOT EXISTS(SELECT 1 FROM batch_consumptions prior
          WHERE prior.transfer_allocation_id=NEW.transfer_allocation_id))
      OR
      (NEW.direction='in' AND NEW.consumption_type='warehouse_transfer_recall'
        AND EXISTS(
          SELECT 1 FROM batch_consumptions original
          WHERE original.transfer_allocation_id=NEW.transfer_allocation_id
            AND original.direction='out'
            AND original.consumption_type='warehouse_transfer_dispatch'
            AND original.batch_id=NEW.batch_id
            AND original.quantity>=NEW.quantity
            AND original.unit_cost_cents=NEW.unit_cost_cents)
        AND NOT EXISTS(SELECT 1 FROM batch_consumptions prior
          WHERE prior.transfer_allocation_id=NEW.transfer_allocation_id
            AND prior.direction='in')))
    BEGIN SELECT RAISE(ABORT,'Invalid transfer batch ledger entry'); END
  ''');

  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_batch_creation
    BEFORE INSERT ON product_batches
    WHEN (NEW.source='warehouse_transfer' OR NEW.origin_batch_id IS NOT NULL
      OR NEW.transfer_allocation_id IS NOT NULL)
      AND NOT EXISTS(
        SELECT 1 FROM warehouse_transfer_allocations a
        JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id AND d.sealed=1
        JOIN warehouse_transfer_lines l ON l.id=a.line_id
        JOIN warehouse_transfers t ON t.id=l.transfer_id
        JOIN product_batches source ON source.id=a.source_batch_id
        WHERE a.id=NEW.transfer_allocation_id
          AND a.source_batch_id=NEW.origin_batch_id
          AND t.status IN ('in_transit','partially_received')
          AND t.destination_warehouse_id=NEW.warehouse_id
          AND l.product_id=NEW.product_id AND l.variant_id=NEW.variant_id
          AND a.unit_cost_cents=NEW.unit_cost_cents
          AND a.manufacturer_lot_number IS NEW.manufacturer_lot_number
          AND a.expiry_date IS NEW.expiry_date
          AND source.purchase_item_id IS NEW.purchase_item_id
          AND source.supplier_id IS NEW.supplier_id
          AND NEW.received_quantity<=a.quantity-COALESCE((
            SELECT SUM(existing.received_quantity) FROM product_batches existing
            WHERE existing.transfer_allocation_id=a.id
          ),0))
    BEGIN SELECT RAISE(ABORT,'Invalid transfer destination batch'); END
  ''');

  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_receipts_creation
    BEFORE INSERT ON warehouse_transfer_receipts
    WHEN NEW.sealed!=0 OR NEW.journal_entry_id IS NOT NULL
      OR NOT EXISTS(
        SELECT 1 FROM warehouse_transfers t
        JOIN warehouse_transfer_dispatches d ON d.transfer_id=t.id AND d.sealed=1
        JOIN users u ON u.id=NEW.actor_id
        WHERE t.id=NEW.transfer_id
          AND t.status IN ('in_transit','partially_received')
          AND u.is_active=1)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_receipts
        WHERE request_key=NEW.request_key)
    BEGIN SELECT RAISE(ABORT,'Invalid transfer receipt'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_receipts_identity
    BEFORE UPDATE OF id,transfer_id,request_key,request_hash,actor_id,item_count,
      accepted_owned_value_cents,variance_owned_value_cents,
      destination_inventory_delta_cents,notes,received_at,created_at
    ON warehouse_transfer_receipts
    BEGIN SELECT RAISE(ABORT,'Transfer receipt is immutable'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_receipt_items_creation
    BEFORE INSERT ON warehouse_transfer_receipt_items
    WHEN NOT EXISTS(
      SELECT 1 FROM warehouse_transfer_receipts r
      JOIN warehouse_transfer_allocations a ON a.id=NEW.allocation_id
      JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id
      WHERE r.id=NEW.receipt_id AND r.sealed=0 AND d.transfer_id=r.transfer_id)
      OR NEW.accepted_quantity+NEW.damaged_quantity+NEW.lost_quantity
        > (SELECT a.quantity-COALESCE((
            SELECT SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity)
            FROM warehouse_transfer_receipt_items i
            JOIN warehouse_transfer_receipts prior ON prior.id=i.receipt_id
            WHERE i.allocation_id=NEW.allocation_id AND prior.sealed=1
          ),0) FROM warehouse_transfer_allocations a WHERE a.id=NEW.allocation_id)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_receipt_items
        WHERE receipt_id=NEW.receipt_id AND allocation_id=NEW.allocation_id)
      OR EXISTS(
        SELECT 1 FROM warehouse_transfer_allocations a
        JOIN warehouse_transfer_lines l ON l.id=a.line_id
        JOIN products p ON p.id=l.product_id
        JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id
        JOIN warehouse_transfers t ON t.id=d.transfer_id
        WHERE a.id=NEW.allocation_id AND (
          (a.owner_type='consignment' AND
            (NEW.accepted_value_cents!=0 OR NEW.variance_value_cents!=0
             OR (NEW.accepted_quantity>0 AND NEW.destination_consignment_layer_id IS NULL)
             OR (NEW.accepted_quantity=0 AND NEW.destination_consignment_layer_id IS NOT NULL)))
          OR
          (a.owner_type='owned' AND NEW.destination_consignment_layer_id IS NOT NULL)
          OR
          (NEW.accepted_quantity=0 AND NEW.destination_batch_id IS NOT NULL)
          OR
          (NEW.accepted_quantity>0
            AND (p.costing_method='fifo' OR p.inventory_tracking_type IN ('batch','batch_expiry'))
            AND NOT EXISTS(
              SELECT 1 FROM product_batches b
              WHERE b.id=NEW.destination_batch_id
                AND b.transfer_allocation_id=a.id
                AND b.warehouse_id=t.destination_warehouse_id
                AND b.product_id=l.product_id AND b.variant_id=l.variant_id
                AND b.received_quantity=NEW.accepted_quantity))
          OR
          (NEW.accepted_quantity>0
            AND p.costing_method!='fifo'
            AND p.inventory_tracking_type NOT IN ('batch','batch_expiry')
            AND NEW.destination_batch_id IS NOT NULL)
          OR
          ((NEW.damaged_quantity>0 OR NEW.lost_quantity>0)
            AND length(trim((SELECT notes FROM warehouse_transfer_receipts
              WHERE id=NEW.receipt_id)))=0)
        ))
    BEGIN SELECT RAISE(ABORT,'Invalid transfer receipt allocation'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_receipts_finalize
    BEFORE UPDATE OF journal_entry_id,sealed ON warehouse_transfer_receipts
    WHEN NOT(
      OLD.sealed=0 AND NEW.sealed=1
      AND NEW.item_count=(SELECT COUNT(*) FROM warehouse_transfer_receipt_items i
        WHERE i.receipt_id=OLD.id)
      AND NEW.accepted_owned_value_cents=COALESCE((SELECT SUM(i.accepted_value_cents)
        FROM warehouse_transfer_receipt_items i WHERE i.receipt_id=OLD.id),0)
      AND NEW.variance_owned_value_cents=COALESCE((SELECT SUM(i.variance_value_cents)
        FROM warehouse_transfer_receipt_items i WHERE i.receipt_id=OLD.id),0)
      AND NEW.destination_inventory_delta_cents=NEW.accepted_owned_value_cents
      AND ((NEW.accepted_owned_value_cents=0 AND NEW.variance_owned_value_cents=0
        AND NEW.destination_inventory_delta_cents=0 AND NEW.journal_entry_id IS NULL)
        OR (NEW.accepted_owned_value_cents+NEW.variance_owned_value_cents>0
          AND EXISTS(
            SELECT 1 FROM journal_entries j
            JOIN warehouse_transfers t ON t.id=OLD.transfer_id
            WHERE j.id=NEW.journal_entry_id
              AND j.status='posted'
              AND j.entry_type='warehouse_transfer_receipt'
              AND j.source_table='warehouse_transfer_receipts'
              AND j.source_id=OLD.id
              AND j.total_debit_cents=NEW.accepted_owned_value_cents+NEW.variance_owned_value_cents
              AND j.total_credit_cents=NEW.accepted_owned_value_cents+NEW.variance_owned_value_cents
              AND (SELECT COUNT(*) FROM journal_entry_lines l
                WHERE l.journal_entry_id=j.id)
                  =1+(CASE WHEN NEW.accepted_owned_value_cents>0 THEN 1 ELSE 0 END)
                    +(CASE WHEN NEW.variance_owned_value_cents>0 THEN 1 ELSE 0 END)
              AND (NEW.accepted_owned_value_cents=0 OR EXISTS(
                SELECT 1 FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
                WHERE l.journal_entry_id=j.id AND a.account_code='1200'
                  AND l.currency_id=t.currency_id
                  AND l.debit_cents=NEW.accepted_owned_value_cents AND l.credit_cents=0))
              AND (NEW.variance_owned_value_cents=0 OR EXISTS(
                SELECT 1 FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
                WHERE l.journal_entry_id=j.id AND a.account_code='5800'
                  AND l.currency_id=t.currency_id
                  AND l.debit_cents=NEW.variance_owned_value_cents AND l.credit_cents=0))
              AND EXISTS(
                SELECT 1 FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
                WHERE l.journal_entry_id=j.id AND a.account_code='1210'
                  AND l.currency_id=t.currency_id AND l.debit_cents=0
                  AND l.credit_cents=NEW.accepted_owned_value_cents+NEW.variance_owned_value_cents)
          )))
    )
    BEGIN SELECT RAISE(ABORT,'Transfer receipt is incomplete'); END
  ''');

  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_recalls_creation
    BEFORE INSERT ON warehouse_transfer_recalls
    WHEN NEW.sealed!=0 OR NEW.journal_entry_id IS NOT NULL
      OR NOT EXISTS(
        SELECT 1 FROM warehouse_transfers t
        JOIN warehouse_transfer_dispatches d ON d.transfer_id=t.id AND d.sealed=1
        JOIN users u ON u.id=NEW.actor_id
        WHERE t.id=NEW.transfer_id
          AND t.status IN ('in_transit','partially_received')
          AND u.is_active=1)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_recalls
        WHERE transfer_id=NEW.transfer_id OR request_key=NEW.request_key)
    BEGIN SELECT RAISE(ABORT,'Invalid transfer recall'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_recalls_identity
    BEFORE UPDATE OF id,transfer_id,request_key,request_hash,actor_id,item_count,
      owned_value_cents,reason,recalled_at,created_at
    ON warehouse_transfer_recalls
    BEGIN SELECT RAISE(ABORT,'Transfer recall is immutable'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_recall_items_creation
    BEFORE INSERT ON warehouse_transfer_recall_items
    WHEN NOT EXISTS(
      SELECT 1 FROM warehouse_transfer_recalls r
      JOIN warehouse_transfer_allocations a ON a.id=NEW.allocation_id
      JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id
      WHERE r.id=NEW.recall_id AND r.sealed=0 AND d.transfer_id=r.transfer_id
        AND NEW.quantity=a.quantity-COALESCE((
          SELECT SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity)
          FROM warehouse_transfer_receipt_items i
          JOIN warehouse_transfer_receipts receipt ON receipt.id=i.receipt_id
          WHERE i.allocation_id=a.id AND receipt.sealed=1),0)
        AND ((a.owner_type='consignment' AND NEW.value_cents=0)
          OR (a.owner_type='owned' AND NEW.value_cents>=0)))
      OR EXISTS(SELECT 1 FROM warehouse_transfer_recall_items
        WHERE allocation_id=NEW.allocation_id)
    BEGIN SELECT RAISE(ABORT,'Invalid transfer recall allocation'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_recalls_finalize
    BEFORE UPDATE OF journal_entry_id,sealed ON warehouse_transfer_recalls
    WHEN NOT(
      OLD.sealed=0 AND NEW.sealed=1
      AND NEW.item_count=(SELECT COUNT(*) FROM warehouse_transfer_recall_items i
        WHERE i.recall_id=OLD.id)
      AND NEW.owned_value_cents=COALESCE((SELECT SUM(i.value_cents)
        FROM warehouse_transfer_recall_items i WHERE i.recall_id=OLD.id),0)
      AND NOT EXISTS(
        SELECT 1 FROM warehouse_transfer_allocations a
        JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id
        WHERE d.transfer_id=OLD.transfer_id
          AND a.quantity!=COALESCE((
            SELECT SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity)
            FROM warehouse_transfer_receipt_items i
            JOIN warehouse_transfer_receipts receipt ON receipt.id=i.receipt_id
            WHERE i.allocation_id=a.id AND receipt.sealed=1),0)
            +COALESCE((SELECT SUM(ri.quantity)
              FROM warehouse_transfer_recall_items ri
              JOIN warehouse_transfer_recalls recall ON recall.id=ri.recall_id
              WHERE ri.allocation_id=a.id
                AND (recall.sealed=1 OR recall.id=OLD.id)),0))
      AND ((NEW.owned_value_cents=0 AND NEW.journal_entry_id IS NULL)
        OR (NEW.owned_value_cents>0 AND EXISTS(
          SELECT 1 FROM journal_entries j
          JOIN warehouse_transfers t ON t.id=OLD.transfer_id
          WHERE j.id=NEW.journal_entry_id
            AND j.status='posted'
            AND j.entry_type='warehouse_transfer_recall'
            AND j.source_table='warehouse_transfer_recalls'
            AND j.source_id=OLD.id
            AND j.total_debit_cents=NEW.owned_value_cents
            AND j.total_credit_cents=NEW.owned_value_cents
            AND (SELECT COUNT(*) FROM journal_entry_lines l
              WHERE l.journal_entry_id=j.id)=2
            AND EXISTS(
              SELECT 1 FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
              WHERE l.journal_entry_id=j.id AND a.account_code='1200'
                AND l.currency_id=t.currency_id
                AND l.debit_cents=NEW.owned_value_cents AND l.credit_cents=0)
            AND EXISTS(
              SELECT 1 FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
              WHERE l.journal_entry_id=j.id AND a.account_code='1210'
                AND l.currency_id=t.currency_id
                AND l.debit_cents=0 AND l.credit_cents=NEW.owned_value_cents)
        )))
    )
    BEGIN SELECT RAISE(ABORT,'Transfer recall is incomplete'); END
  ''');

  // Once a transfer document is sealed, its exact journal is immutable. This
  // prevents a valid link at posting time from being rebound or edited later
  // through raw SQL while keeping ordinary draft journals unaffected.
  const linkedTransferJournal = '''
    EXISTS(SELECT 1 FROM warehouse_transfer_dispatches d
      WHERE d.sealed=1 AND d.journal_entry_id=OLD.id)
    OR EXISTS(SELECT 1 FROM warehouse_transfer_receipts r
      WHERE r.sealed=1 AND r.journal_entry_id=OLD.id)
    OR EXISTS(SELECT 1 FROM warehouse_transfer_recalls r
      WHERE r.sealed=1 AND r.journal_entry_id=OLD.id)
  ''';
  await db.customStatement("""
    CREATE TRIGGER warehouse_transfer_journal_header_update
    BEFORE UPDATE ON journal_entries
    WHEN $linkedTransferJournal
    BEGIN SELECT RAISE(ABORT,'Posted transfer journal is immutable'); END
  """);
  await db.customStatement("""
    CREATE TRIGGER warehouse_transfer_journal_header_delete
    BEFORE DELETE ON journal_entries
    WHEN $linkedTransferJournal
    BEGIN SELECT RAISE(ABORT,'Posted transfer journal cannot be deleted'); END
  """);
  await db.customStatement("""
    CREATE TRIGGER warehouse_transfer_journal_line_insert
    BEFORE INSERT ON journal_entry_lines
    WHEN EXISTS(SELECT 1 FROM warehouse_transfer_dispatches d
        WHERE d.sealed=1 AND d.journal_entry_id=NEW.journal_entry_id)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_receipts r
        WHERE r.sealed=1 AND r.journal_entry_id=NEW.journal_entry_id)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_recalls r
        WHERE r.sealed=1 AND r.journal_entry_id=NEW.journal_entry_id)
    BEGIN SELECT RAISE(ABORT,'Posted transfer journal lines are immutable'); END
  """);
  await db.customStatement("""
    CREATE TRIGGER warehouse_transfer_journal_line_update
    BEFORE UPDATE ON journal_entry_lines
    WHEN EXISTS(SELECT 1 FROM warehouse_transfer_dispatches d
        WHERE d.sealed=1 AND d.journal_entry_id IN (OLD.journal_entry_id,NEW.journal_entry_id))
      OR EXISTS(SELECT 1 FROM warehouse_transfer_receipts r
        WHERE r.sealed=1 AND r.journal_entry_id IN (OLD.journal_entry_id,NEW.journal_entry_id))
      OR EXISTS(SELECT 1 FROM warehouse_transfer_recalls r
        WHERE r.sealed=1 AND r.journal_entry_id IN (OLD.journal_entry_id,NEW.journal_entry_id))
    BEGIN SELECT RAISE(ABORT,'Posted transfer journal lines are immutable'); END
  """);
  await db.customStatement("""
    CREATE TRIGGER warehouse_transfer_journal_line_delete
    BEFORE DELETE ON journal_entry_lines
    WHEN EXISTS(SELECT 1 FROM warehouse_transfer_dispatches d
        WHERE d.sealed=1 AND d.journal_entry_id=OLD.journal_entry_id)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_receipts r
        WHERE r.sealed=1 AND r.journal_entry_id=OLD.journal_entry_id)
      OR EXISTS(SELECT 1 FROM warehouse_transfer_recalls r
        WHERE r.sealed=1 AND r.journal_entry_id=OLD.journal_entry_id)
    BEGIN SELECT RAISE(ABORT,'Posted transfer journal lines cannot be deleted'); END
  """);

  await db.customStatement('''
    CREATE TRIGGER warehouse_transfer_events_creation
    BEFORE INSERT ON warehouse_transfer_events
    WHEN EXISTS(SELECT 1 FROM warehouse_transfer_events
      WHERE request_key=NEW.request_key OR (transfer_id=NEW.transfer_id AND kind=NEW.kind))
      OR NOT EXISTS(
        SELECT 1 FROM warehouse_transfers t JOIN users u ON u.id=NEW.actor_id
        WHERE t.id=NEW.transfer_id AND t.sealed=1 AND u.is_active=1
          AND (
            (NEW.kind='created' AND t.status='draft'
              AND t.request_key=NEW.request_key AND t.request_hash=NEW.request_hash
              AND t.created_by=NEW.actor_id)
            OR (NEW.kind='cancelled' AND t.status='draft' AND length(trim(NEW.reason))>0)
            OR (NEW.kind='dispatched' AND t.status='draft' AND EXISTS(
              SELECT 1 FROM warehouse_transfer_dispatches d
              WHERE d.transfer_id=t.id AND d.sealed=1
                AND d.request_key=NEW.request_key AND d.request_hash=NEW.request_hash
                AND d.actor_id=NEW.actor_id))
            OR (NEW.kind='completed' AND t.status IN ('in_transit','partially_received')
              AND NOT EXISTS(
                SELECT 1 FROM warehouse_transfer_allocations a
                JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id
                WHERE d.transfer_id=t.id AND a.quantity>COALESCE((
                  SELECT SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity)
                  FROM warehouse_transfer_receipt_items i
                  JOIN warehouse_transfer_receipts r ON r.id=i.receipt_id
                  WHERE i.allocation_id=a.id AND r.sealed=1
                ),0)))
          ))
    BEGIN SELECT RAISE(ABORT,'Invalid transfer event'); END
  ''');
  await db.customStatement('''
    CREATE TRIGGER warehouse_transfers_status
    BEFORE UPDATE OF status ON warehouse_transfers
    WHEN NOT(
      (OLD.status='draft' AND NEW.status='cancelled' AND OLD.sealed=1
        AND EXISTS(SELECT 1 FROM warehouse_transfer_events e
          WHERE e.transfer_id=OLD.id AND e.kind='cancelled'))
      OR
      (OLD.status='draft' AND NEW.status='in_transit' AND OLD.sealed=1
        AND EXISTS(SELECT 1 FROM warehouse_transfer_dispatches d
          WHERE d.transfer_id=OLD.id AND d.sealed=1)
        AND EXISTS(SELECT 1 FROM warehouse_transfer_events e
          WHERE e.transfer_id=OLD.id AND e.kind='dispatched'))
      OR
      (OLD.status='in_transit' AND NEW.status='partially_received'
        AND EXISTS(SELECT 1 FROM warehouse_transfer_receipts r
          WHERE r.transfer_id=OLD.id AND r.sealed=1)
        AND EXISTS(
          SELECT 1 FROM warehouse_transfer_allocations a
          JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id
          WHERE d.transfer_id=OLD.id AND a.quantity>COALESCE((
            SELECT SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity)
            FROM warehouse_transfer_receipt_items i
            JOIN warehouse_transfer_receipts r ON r.id=i.receipt_id
            WHERE i.allocation_id=a.id AND r.sealed=1
          ),0)))
      OR
      (OLD.status IN ('in_transit','partially_received') AND NEW.status='cancelled'
        AND EXISTS(SELECT 1 FROM warehouse_transfer_recalls recall
          WHERE recall.transfer_id=OLD.id AND recall.sealed=1))
      OR
      (OLD.status IN ('in_transit','partially_received') AND NEW.status='completed'
        AND EXISTS(SELECT 1 FROM warehouse_transfer_events e
          WHERE e.transfer_id=OLD.id AND e.kind='completed')
        AND NOT EXISTS(
          SELECT 1 FROM warehouse_transfer_allocations a
          JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id
          WHERE d.transfer_id=OLD.id AND a.quantity>COALESCE((
            SELECT SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity)
            FROM warehouse_transfer_receipt_items i
            JOIN warehouse_transfer_receipts r ON r.id=i.receipt_id
            WHERE i.allocation_id=a.id AND r.sealed=1
          ),0)))
    )
    BEGIN SELECT RAISE(ABORT,'Transfer status requires its atomic document'); END
  ''');

  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS warehouse_transfers_source_status ON warehouse_transfers(source_warehouse_id,status,created_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS warehouse_transfers_destination_status ON warehouse_transfers(destination_warehouse_id,status,created_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS warehouse_transfer_allocations_line ON warehouse_transfer_allocations(line_id,sequence)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS warehouse_transfer_receipts_transfer ON warehouse_transfer_receipts(transfer_id,received_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS warehouse_transfer_receipt_items_allocation ON warehouse_transfer_receipt_items(allocation_id)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS warehouse_transfer_recalls_transfer ON warehouse_transfer_recalls(transfer_id,recalled_at)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS warehouse_transfer_recall_items_recall ON warehouse_transfer_recall_items(recall_id)',
  );
}
