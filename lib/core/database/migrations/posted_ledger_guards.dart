import '../app_database.dart';

/// Database-boundary protection for the general ledger.
///
/// Journal headers and lines remain editable while the header is `draft`.
/// Posting freezes both tables. A posted entry can only acquire the
/// `is_reversed` marker after a posted reversal entry points back to it; the
/// original remains posted so the original and reversal continue to cancel in
/// ledger reports.
///
/// Keep [removePostedLedgerGuards] available for a future repair migration
/// which deliberately rewrites historical journals before reinstalling these
/// guards in the same transaction.
Future<void> removePostedLedgerGuards(AppDatabase db) async {
  for (final name in _postedLedgerTriggerNames) {
    await db.customStatement('DROP TRIGGER IF EXISTS $name');
  }
}

Future<void> installPostedLedgerGuards(AppDatabase db) async {
  await removePostedLedgerGuards(db);

  // A journal is assembled as draft -> lines -> posted. Direct creation of a
  // posted/voided header would otherwise leave an interval in which no lines
  // exist and would bypass the posting validation below.
  await db.customStatement('''
    CREATE TRIGGER posted_ledger_header_insert_guard
    BEFORE INSERT ON journal_entries
    WHEN NEW.status != 'draft'
    BEGIN
      SELECT RAISE(ABORT, 'accounting.journal_must_start_as_draft');
    END
  ''');

  // The only supported terminal transition is draft -> posted. SQLite table
  // definitions predate strict enum checks, so reject unknown states here too.
  await db.customStatement('''
    CREATE TRIGGER posted_ledger_status_transition_guard
    BEFORE UPDATE OF status ON journal_entries
    WHEN OLD.status = 'draft' AND NEW.status NOT IN ('draft', 'posted')
    BEGIN
      SELECT RAISE(ABORT, 'accounting.invalid_journal_status_transition');
    END
  ''');

  // Validate the persisted lines at the database boundary. Repository checks
  // remain useful for friendly errors, while this guard covers raw SQL, future
  // DAOs and network writers.
  await db.customStatement('''
    CREATE TRIGGER posted_ledger_post_guard
    BEFORE UPDATE OF status ON journal_entries
    WHEN OLD.status = 'draft' AND NEW.status = 'posted' AND (
      NEW.posted_at IS NULL
      OR NEW.total_debit_cents <= 0
      OR NEW.total_debit_cents != NEW.total_credit_cents
      OR (SELECT COUNT(*) FROM journal_entry_lines l
            WHERE l.journal_entry_id = OLD.id) < 2
      OR COALESCE((SELECT SUM(l.debit_cents) FROM journal_entry_lines l
            WHERE l.journal_entry_id = OLD.id), 0) != NEW.total_debit_cents
      OR COALESCE((SELECT SUM(l.credit_cents) FROM journal_entry_lines l
            WHERE l.journal_entry_id = OLD.id), 0) != NEW.total_credit_cents
      OR EXISTS(
        SELECT 1 FROM journal_entry_lines l
        WHERE l.journal_entry_id = OLD.id
          AND (l.debit_cents < 0 OR l.credit_cents < 0
            OR (l.debit_cents = 0 AND l.credit_cents = 0)
            OR (l.debit_cents > 0 AND l.credit_cents > 0))
      )
      OR (SELECT COUNT(DISTINCT l.currency_id) FROM journal_entry_lines l
            WHERE l.journal_entry_id = OLD.id) != 1
    )
    BEGIN
      SELECT RAISE(ABORT, 'accounting.invalid_journal_post');
    END
  ''');

  // Once posted, every header field is immutable. The sole exception is the
  // canonical false -> true reversal marker, and only after its posted reversal
  // header exists. updated_at may change in that same operation only.
  await db.customStatement('''
    CREATE TRIGGER posted_ledger_header_update_guard
    BEFORE UPDATE ON journal_entries
    WHEN OLD.status != 'draft' AND NOT (
      OLD.status = 'posted'
      AND OLD.is_reversed = 0
      AND NEW.is_reversed = 1
      AND NEW.id IS OLD.id
      AND NEW.entry_number IS OLD.entry_number
      AND NEW.description IS OLD.description
      AND NEW.entry_date IS OLD.entry_date
      AND NEW.accounting_period_id IS OLD.accounting_period_id
      AND NEW.status IS OLD.status
      AND NEW.entry_type IS OLD.entry_type
      AND NEW.source_table IS OLD.source_table
      AND NEW.source_id IS OLD.source_id
      AND NEW.reversed_entry_id IS OLD.reversed_entry_id
      AND NEW.total_debit_cents IS OLD.total_debit_cents
      AND NEW.total_credit_cents IS OLD.total_credit_cents
      AND NEW.created_by IS OLD.created_by
      AND NEW.posted_by IS OLD.posted_by
      AND NEW.posted_at IS OLD.posted_at
      AND NEW.created_at IS OLD.created_at
      AND EXISTS(
        SELECT 1 FROM journal_entries reversal
        WHERE reversal.reversed_entry_id = OLD.id
          AND reversal.status = 'posted'
          AND reversal.entry_type = 'reversal'
          AND reversal.id != OLD.id
      )
    )
    BEGIN
      SELECT RAISE(ABORT, 'accounting.posted_journal_immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER posted_ledger_header_delete_guard
    BEFORE DELETE ON journal_entries
    WHEN OLD.status != 'draft'
    BEGIN
      SELECT RAISE(ABORT, 'accounting.posted_journal_immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER posted_ledger_line_insert_guard
    BEFORE INSERT ON journal_entry_lines
    WHEN NOT EXISTS(
      SELECT 1 FROM journal_entries j
      WHERE j.id = NEW.journal_entry_id AND j.status = 'draft'
    )
    BEGIN
      SELECT RAISE(ABORT, 'accounting.posted_journal_lines_immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER posted_ledger_line_update_guard
    BEFORE UPDATE ON journal_entry_lines
    WHEN NOT EXISTS(
      SELECT 1 FROM journal_entries j
      WHERE j.id = OLD.journal_entry_id AND j.status = 'draft'
    ) OR NOT EXISTS(
      SELECT 1 FROM journal_entries j
      WHERE j.id = NEW.journal_entry_id AND j.status = 'draft'
    )
    BEGIN
      SELECT RAISE(ABORT, 'accounting.posted_journal_lines_immutable');
    END
  ''');

  await db.customStatement('''
    CREATE TRIGGER posted_ledger_line_delete_guard
    BEFORE DELETE ON journal_entry_lines
    WHEN NOT EXISTS(
      SELECT 1 FROM journal_entries j
      WHERE j.id = OLD.journal_entry_id AND j.status = 'draft'
    )
    BEGIN
      SELECT RAISE(ABORT, 'accounting.posted_journal_lines_immutable');
    END
  ''');
}

const _postedLedgerTriggerNames = <String>[
  'posted_ledger_header_insert_guard',
  'posted_ledger_status_transition_guard',
  'posted_ledger_post_guard',
  'posted_ledger_header_update_guard',
  'posted_ledger_header_delete_guard',
  'posted_ledger_line_insert_guard',
  'posted_ledger_line_update_guard',
  'posted_ledger_line_delete_guard',
];
