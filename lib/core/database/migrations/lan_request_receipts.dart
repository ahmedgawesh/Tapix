import '../app_database.dart';

/// Installs the durable LAN request ledger without changing Drift's generated
/// schema. The ledger is intentionally polymorphic: the operation identifies the
/// document table while the document ID identifies the completed document.
Future<void> installLanRequestReceiptLedger(AppDatabase db) async {
  const createLedger = '''
    CREATE TABLE IF NOT EXISTS lan_request_receipts (
      operation TEXT NOT NULL CHECK (operation IN (
        'sale',
        'sale_return',
        'sale_adjustment_return',
        'purchase',
        'purchase_return',
        'purchase_adjustment_return'
      )),
      idempotency_key TEXT NOT NULL,
      request_hash TEXT,
      state TEXT NOT NULL CHECK (state IN ('pending', 'completed', 'legacy')),
      document_id INTEGER,
      document_number TEXT,
      total_cents INTEGER,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      completed_at TEXT,
      PRIMARY KEY (operation, idempotency_key),
      CHECK (
        (state = 'pending' AND request_hash IS NOT NULL
          AND length(request_hash) = 64 AND document_id IS NULL
          AND document_number IS NULL AND total_cents IS NULL
          AND completed_at IS NULL)
        OR
        (state = 'completed' AND request_hash IS NOT NULL
          AND length(request_hash) = 64 AND document_id IS NOT NULL
          AND document_number IS NOT NULL AND total_cents IS NOT NULL
          AND completed_at IS NOT NULL)
        OR
        (state = 'legacy' AND request_hash IS NULL
          AND document_id IS NOT NULL AND document_number IS NOT NULL
          AND total_cents IS NOT NULL AND completed_at IS NOT NULL)
      )
    )
  ''';
  await db.customStatement(createLedger);

  // Older ledgers predate remote purchase invoices. SQLite cannot alter a
  // CHECK constraint in place, so preserve every append-only receipt while
  // replacing only the table definition.
  final definition = await db.customSelect('''SELECT sql FROM sqlite_master
           WHERE type='table' AND name='lan_request_receipts' ''').getSingle();
  if (!definition.read<String>('sql').contains("'purchase',")) {
    await db.transaction(() async {
      await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_lan_request_receipts_no_delete',
      );
      await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_lan_request_receipts_complete_once',
      );
      await db.customStatement(
        'ALTER TABLE lan_request_receipts '
        'RENAME TO lan_request_receipts_before_purchase',
      );
      await db.customStatement(createLedger);
      await db.customStatement('''
        INSERT INTO lan_request_receipts (
          operation, idempotency_key, request_hash, state, document_id,
          document_number, total_cents, created_at, completed_at
        )
        SELECT operation, idempotency_key, request_hash, state, document_id,
               document_number, total_cents, created_at, completed_at
        FROM lan_request_receipts_before_purchase
      ''');
      await db.customStatement(
        'DROP TABLE lan_request_receipts_before_purchase',
      );
    });
  }
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS trg_lan_request_receipts_no_delete
    BEFORE DELETE ON lan_request_receipts
    BEGIN
      SELECT RAISE(ABORT, 'LAN request receipts are append-only');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS trg_lan_request_receipts_complete_once
    BEFORE UPDATE ON lan_request_receipts
    WHEN OLD.state <> 'pending'
      OR NEW.operation IS NOT OLD.operation
      OR NEW.idempotency_key IS NOT OLD.idempotency_key
      OR NEW.request_hash IS NOT OLD.request_hash
      OR NEW.created_at IS NOT OLD.created_at
      OR NEW.state <> 'completed'
      OR NEW.document_id IS NULL
      OR NEW.completed_at IS NULL
    BEGIN
      SELECT RAISE(ABORT, 'LAN request receipt can only be completed once');
    END
  ''');
}
