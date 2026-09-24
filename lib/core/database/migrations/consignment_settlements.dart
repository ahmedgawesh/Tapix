import '../app_database.dart';

Future<void> installConsignmentSettlementGuards(AppDatabase db) async {
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_statement_item_insert_guard',
  );
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_obligation_assignment_guard',
  );
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_adjustment_assignment_guard',
  );
  await db.customStatement(
    'DROP TRIGGER IF EXISTS consignment_custody_assignment_guard',
  );
  final hasCustodyEvents =
      (await db
              .customSelect(
                'SELECT EXISTS(SELECT 1 FROM sqlite_master '
                'WHERE type=\'table\' AND name=\'consignment_custody_events\') AS present',
              )
              .getSingle())
          .read<int>('present') ==
      1;
  final custodySourceClause = hasCustodyEvents
      ? '''
          OR
          (NEW.source_ledger='custody_loss' AND EXISTS(
            SELECT 1 FROM consignment_custody_events e
            WHERE e.id=NEW.event_id
              AND e.supplier_id=st.supplier_id
              AND e.agreement_id=st.agreement_id
              AND e.currency_id=st.currency_id
              AND e.signed_quantity=NEW.signed_quantity
              AND e.signed_amount_cents=NEW.signed_amount_cents
              AND e.occurred_at=NEW.occurred_at
              AND e.settlement_status='unassigned'
              AND e.signed_amount_cents!=0
              AND e.journal_entry_id IS NOT NULL
          ))
        '''
      : '';
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_statements_supplier_period '
    'ON consignment_settlement_statements('
    'branch_id,supplier_id,currency_id,period_start,period_end,status)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_statement_items_source '
    'ON consignment_settlement_items(source_ledger,event_id)',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_statement_payments_statement '
    'ON consignment_settlement_payments(statement_id,status,paid_at)',
  );

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_statement_item_insert_guard
    BEFORE INSERT ON consignment_settlement_items
    WHEN NOT EXISTS(
      SELECT 1 FROM consignment_settlement_statements st
      WHERE st.id=NEW.statement_id AND st.status='draft'
        AND NEW.occurred_at BETWEEN st.period_start AND st.period_end
        AND (
          (NEW.source_ledger='sale_obligation' AND EXISTS(
            SELECT 1 FROM consignment_obligation_events e
            WHERE e.id=NEW.event_id
              AND e.supplier_id=st.supplier_id
              AND e.agreement_id=st.agreement_id
              AND e.currency_id=st.currency_id
              AND e.signed_quantity=NEW.signed_quantity
              AND e.signed_amount_cents=NEW.signed_amount_cents
              AND e.occurred_at=NEW.occurred_at
              AND e.settlement_status='unassigned'
              AND (e.signed_amount_cents=0 OR e.journal_entry_id IS NOT NULL)
          ))
          OR
          (NEW.source_ledger='adjustment_return' AND EXISTS(
            SELECT 1 FROM consignment_adjustment_return_events e
            WHERE e.id=NEW.event_id
              AND e.supplier_id=st.supplier_id
              AND e.agreement_id=st.agreement_id
              AND e.currency_id=st.currency_id
              AND e.signed_quantity=NEW.signed_quantity
              AND e.signed_amount_cents=NEW.signed_amount_cents
              AND e.occurred_at=NEW.occurred_at
              AND e.settlement_status='unassigned'
              AND (e.signed_amount_cents=0 OR e.journal_entry_id IS NOT NULL)
          ))
          $custodySourceClause
        )
    ) OR EXISTS(
      SELECT 1 FROM consignment_settlement_items old
      JOIN consignment_settlement_statements active
        ON active.id=old.statement_id
      WHERE old.source_ledger=NEW.source_ledger
        AND old.event_id=NEW.event_id
        AND active.status!='voided'
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment settlement source');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_statement_item_immutable
    BEFORE UPDATE ON consignment_settlement_items
    BEGIN
      SELECT RAISE(ABORT,'Consignment settlement item is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_statement_item_no_delete
    BEFORE DELETE ON consignment_settlement_items
    BEGIN
      SELECT RAISE(ABORT,'Consignment settlement item cannot be deleted');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_obligation_assignment_guard
    BEFORE UPDATE OF settlement_status ON consignment_obligation_events
    WHEN NOT (
      NEW.settlement_status=OLD.settlement_status
      OR (
        OLD.settlement_status='unassigned'
        AND NEW.settlement_status='assigned'
        AND EXISTS(
          SELECT 1 FROM consignment_settlement_items i
          JOIN consignment_settlement_statements st ON st.id=i.statement_id
          WHERE i.source_ledger='sale_obligation' AND i.event_id=OLD.id
            AND st.status!='voided'
        )
      )
      OR (
        OLD.settlement_status='assigned'
        AND NEW.settlement_status='unassigned'
        AND NOT EXISTS(
          SELECT 1 FROM consignment_settlement_items i
          JOIN consignment_settlement_statements st ON st.id=i.statement_id
          WHERE i.source_ledger='sale_obligation' AND i.event_id=OLD.id
            AND st.status!='voided'
        )
      )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment obligation assignment');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_adjustment_assignment_guard
    BEFORE UPDATE OF settlement_status ON consignment_adjustment_return_events
    WHEN NOT (
      NEW.settlement_status=OLD.settlement_status
      OR (
        OLD.settlement_status='unassigned'
        AND NEW.settlement_status='assigned'
        AND EXISTS(
          SELECT 1 FROM consignment_settlement_items i
          JOIN consignment_settlement_statements st ON st.id=i.statement_id
          WHERE i.source_ledger='adjustment_return' AND i.event_id=OLD.id
            AND st.status!='voided'
        )
      )
      OR (
        OLD.settlement_status='assigned'
        AND NEW.settlement_status='unassigned'
        AND NOT EXISTS(
          SELECT 1 FROM consignment_settlement_items i
          JOIN consignment_settlement_statements st ON st.id=i.statement_id
          WHERE i.source_ledger='adjustment_return' AND i.event_id=OLD.id
            AND st.status!='voided'
        )
      )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment adjustment assignment');
    END
  ''');

  if (hasCustodyEvents) {
    await db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS consignment_custody_assignment_guard
      BEFORE UPDATE OF settlement_status ON consignment_custody_events
      WHEN NOT (
        NEW.settlement_status=OLD.settlement_status
        OR (
          OLD.settlement_status='unassigned'
          AND NEW.settlement_status='assigned'
          AND EXISTS(
            SELECT 1 FROM consignment_settlement_items i
            JOIN consignment_settlement_statements st ON st.id=i.statement_id
            WHERE i.source_ledger='custody_loss' AND i.event_id=OLD.id
              AND st.status!='voided'
          )
        )
        OR (
          OLD.settlement_status='assigned'
          AND NEW.settlement_status='unassigned'
          AND NOT EXISTS(
            SELECT 1 FROM consignment_settlement_items i
            JOIN consignment_settlement_statements st ON st.id=i.statement_id
            WHERE i.source_ledger='custody_loss' AND i.event_id=OLD.id
              AND st.status!='voided'
          )
        )
      )
      BEGIN
        SELECT RAISE(ABORT,'Invalid consignment custody assignment');
      END
    ''');
  }

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_statement_identity_guard
    BEFORE UPDATE OF organization_id,branch_id,database_id,supplier_id,
      agreement_id,currency_id,statement_number,period_start,period_end,
      tax_rate_bps,tax_inclusive,obligation_subtotal_cents,tax_cents,
      total_cents,line_count,due_date,request_key,request_hash,created_by,
      created_at
    ON consignment_settlement_statements
    BEGIN
      SELECT RAISE(ABORT,'Consignment settlement identity is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_statement_no_delete
    BEFORE DELETE ON consignment_settlement_statements
    BEGIN
      SELECT RAISE(ABORT,'Consignment settlement cannot be deleted');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_payment_insert_guard
    BEFORE INSERT ON consignment_settlement_payments
    WHEN NOT EXISTS(
      SELECT 1 FROM consignment_settlement_statements st
      JOIN supplier_transactions tx ON tx.id=NEW.supplier_transaction_id
      JOIN journal_entries j ON j.id=NEW.journal_entry_id
      WHERE st.id=NEW.statement_id
        AND st.status IN ('posted','partially_paid')
        AND st.total_cents>0
        AND st.paid_cents+NEW.amount_cents<=st.total_cents
        AND tx.supplier_id=st.supplier_id
        AND tx.currency_id=st.currency_id
        AND tx.transaction_type='consignment_payment'
        AND tx.amount_cents=-NEW.amount_cents
        AND tx.reference_id=st.id
        AND tx.reference_type='consignment_settlement_statement'
        AND j.status='posted'
        AND j.source_table='consignment_settlement_payments'
        AND j.source_id=NEW.id
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment settlement payment');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_statement_transition_guard
    BEFORE UPDATE OF status,paid_cents,journal_entry_id,
      supplier_transaction_id,void_journal_entry_id,
      void_supplier_transaction_id,reviewed_by,reviewed_at,posted_by,posted_at,
      voided_by,voided_at,void_reason
    ON consignment_settlement_statements
    WHEN NOT (
      (
        NEW.status=OLD.status
        AND NEW.paid_cents=OLD.paid_cents
        AND NEW.journal_entry_id IS OLD.journal_entry_id
        AND NEW.supplier_transaction_id IS OLD.supplier_transaction_id
        AND NEW.void_journal_entry_id IS OLD.void_journal_entry_id
        AND NEW.void_supplier_transaction_id IS OLD.void_supplier_transaction_id
        AND NEW.reviewed_by IS OLD.reviewed_by
        AND NEW.reviewed_at IS OLD.reviewed_at
        AND NEW.posted_by IS OLD.posted_by
        AND NEW.posted_at IS OLD.posted_at
        AND NEW.voided_by IS OLD.voided_by
        AND NEW.voided_at IS OLD.voided_at
        AND NEW.void_reason=OLD.void_reason
      )
      OR
      (
        OLD.status='draft' AND NEW.status='reviewed'
        AND NEW.paid_cents=0
        AND NEW.reviewed_by IS NOT NULL AND NEW.reviewed_at IS NOT NULL
        AND NEW.posted_by IS NULL AND NEW.posted_at IS NULL
        AND NEW.journal_entry_id IS NULL
        AND NEW.supplier_transaction_id IS NULL
        AND NEW.voided_by IS NULL AND NEW.voided_at IS NULL
        AND length(NEW.void_reason)=0
      )
      OR
      (
        OLD.status IN ('draft','reviewed') AND NEW.status='voided'
        AND NEW.paid_cents=0
        AND NEW.posted_by IS NULL AND NEW.posted_at IS NULL
        AND NEW.journal_entry_id IS NULL
        AND NEW.supplier_transaction_id IS NULL
        AND NEW.void_journal_entry_id IS NULL
        AND NEW.void_supplier_transaction_id IS NULL
        AND NEW.voided_by IS NOT NULL AND NEW.voided_at IS NOT NULL
        AND length(trim(NEW.void_reason))>0
      )
      OR
      (
        OLD.status='reviewed'
        AND NEW.status=CASE WHEN NEW.total_cents>0 THEN 'posted' ELSE 'paid' END
        AND NEW.paid_cents=0
        AND NEW.reviewed_by IS NOT NULL AND NEW.reviewed_at IS NOT NULL
        AND NEW.posted_by IS NOT NULL AND NEW.posted_at IS NOT NULL
        AND NEW.voided_by IS NULL AND NEW.voided_at IS NULL
        AND length(NEW.void_reason)=0
        AND (
          (NEW.total_cents=0
            AND NEW.supplier_transaction_id IS NULL
            AND NEW.journal_entry_id IS NULL)
          OR
          (NEW.total_cents!=0
            AND EXISTS(
              SELECT 1 FROM supplier_transactions tx
              WHERE tx.id=NEW.supplier_transaction_id
                AND tx.supplier_id=NEW.supplier_id
                AND tx.currency_id=NEW.currency_id
                AND tx.transaction_type='consignment_settlement'
                AND tx.amount_cents=NEW.total_cents
                AND tx.reference_id=NEW.id
                AND tx.reference_type='consignment_settlement_statement'
            )
            AND EXISTS(
              SELECT 1 FROM journal_entries j
              WHERE j.id=NEW.journal_entry_id AND j.status='posted'
                AND j.entry_type='consignment_settlement'
                AND j.source_table='consignment_settlement_statements'
                AND j.source_id=NEW.id
            )
          )
        )
      )
      OR
      (
        OLD.status IN ('posted','partially_paid','paid')
        AND NEW.status IN ('posted','partially_paid','paid')
        AND NEW.total_cents>0
        AND NEW.paid_cents=(
          SELECT COALESCE(SUM(p.amount_cents),0)
          FROM consignment_settlement_payments p
          WHERE p.statement_id=NEW.id AND p.status='posted'
        )
        AND NEW.status=CASE
          WHEN NEW.paid_cents=0 THEN 'posted'
          WHEN NEW.paid_cents=NEW.total_cents THEN 'paid'
          ELSE 'partially_paid' END
        AND NEW.supplier_transaction_id IS OLD.supplier_transaction_id
        AND NEW.journal_entry_id IS OLD.journal_entry_id
        AND NEW.void_supplier_transaction_id IS NULL
        AND NEW.void_journal_entry_id IS NULL
      )
      OR
      (
        OLD.status IN ('posted','partially_paid','paid')
        AND NEW.status='voided' AND NEW.paid_cents=0
        AND NOT EXISTS(
          SELECT 1 FROM consignment_settlement_payments p
          WHERE p.statement_id=NEW.id AND p.status='posted'
        )
        AND NEW.voided_by IS NOT NULL AND NEW.voided_at IS NOT NULL
        AND length(trim(NEW.void_reason))>0
        AND (
          (NEW.total_cents=0
            AND NEW.void_supplier_transaction_id IS NULL
            AND NEW.void_journal_entry_id IS NULL)
          OR
          (NEW.total_cents!=0
            AND EXISTS(
              SELECT 1 FROM supplier_transactions tx
              WHERE tx.id=NEW.void_supplier_transaction_id
                AND tx.supplier_id=NEW.supplier_id
                AND tx.currency_id=NEW.currency_id
                AND tx.transaction_type='consignment_settlement_void'
                AND tx.amount_cents=-NEW.total_cents
                AND tx.reference_id=NEW.id
                AND tx.reference_type='consignment_settlement_statement'
            )
            AND EXISTS(
              SELECT 1 FROM journal_entries j
              WHERE j.id=NEW.void_journal_entry_id AND j.status='posted'
                AND j.entry_type='consignment_settlement_void'
                AND j.source_table='consignment_settlement_statements'
                AND j.source_id=NEW.id
            )
          )
        )
      )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment settlement transition');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_payment_reversal_guard
    BEFORE UPDATE OF status,reversal_supplier_transaction_id,
      reversal_journal_entry_id,reversed_at,reversed_by,reversal_reason
    ON consignment_settlement_payments
    WHEN NOT (
      (
        NEW.status=OLD.status
        AND NEW.reversal_supplier_transaction_id IS OLD.reversal_supplier_transaction_id
        AND NEW.reversal_journal_entry_id IS OLD.reversal_journal_entry_id
        AND NEW.reversed_at IS OLD.reversed_at
        AND NEW.reversed_by IS OLD.reversed_by
        AND NEW.reversal_reason=OLD.reversal_reason
      )
      OR
      (
        OLD.status='posted' AND NEW.status='reversed'
        AND NEW.reversed_at IS NOT NULL AND NEW.reversed_by IS NOT NULL
        AND length(trim(NEW.reversal_reason))>0
        AND EXISTS(
          SELECT 1 FROM supplier_transactions tx
          JOIN consignment_settlement_statements st ON st.id=NEW.statement_id
          WHERE tx.id=NEW.reversal_supplier_transaction_id
            AND tx.supplier_id=st.supplier_id
            AND tx.currency_id=st.currency_id
            AND tx.transaction_type='consignment_payment_reversal'
            AND tx.amount_cents=NEW.amount_cents
            AND tx.reference_id=NEW.id
            AND tx.reference_type='consignment_settlement_payment'
        )
        AND EXISTS(
          SELECT 1 FROM journal_entries j
          WHERE j.id=NEW.reversal_journal_entry_id AND j.status='posted'
            AND j.entry_type='consignment_settlement_payment_reversal'
            AND j.source_table='consignment_settlement_payments'
            AND j.source_id=NEW.id
        )
      )
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment payment reversal');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_payment_identity_guard
    BEFORE UPDATE OF statement_id,amount_cents,payment_method,reference,
      request_key,supplier_transaction_id,journal_entry_id,paid_at,created_by,
      created_at
    ON consignment_settlement_payments
    BEGIN
      SELECT RAISE(ABORT,'Consignment settlement payment is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_payment_no_delete
    BEFORE DELETE ON consignment_settlement_payments
    BEGIN
      SELECT RAISE(ABORT,'Consignment settlement payment cannot be deleted');
    END
  ''');
}
