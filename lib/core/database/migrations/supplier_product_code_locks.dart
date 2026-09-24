import '../app_database.dart';

/// v10096: used prefixes remain locked even without a source SKU being issued.
/// Existing codes are frozen as they stand; no historical prefix is guessed.
/// Legacy NULL codes may be assigned once, then become locked if history exists.
const createSupplierProductCodeLocksSql = '''
CREATE TABLE IF NOT EXISTS "supplier_product_code_locks" (
  "supplier_id" INTEGER NOT NULL REFERENCES suppliers (id) ON DELETE RESTRICT,
  "product_code" TEXT NOT NULL,
  "locked_at" TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  PRIMARY KEY ("supplier_id")
)''';

const backfillSupplierProductCodeLocksSql = '''
INSERT INTO supplier_product_code_locks(supplier_id, product_code)
SELECT s.id, s.product_code FROM suppliers s
WHERE s.product_code IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id)
  AND (EXISTS (SELECT 1 FROM purchases WHERE supplier_id=s.id)
  OR EXISTS (SELECT 1 FROM supplier_transactions WHERE supplier_id=s.id)
  OR EXISTS (SELECT 1 FROM product_batches WHERE supplier_id=s.id)
  OR EXISTS (SELECT 1 FROM purchase_return_adjustments WHERE supplier_id=s.id)
  OR EXISTS (SELECT 1 FROM supplier_product_identities WHERE supplier_id=s.id))''';

const supplierProductCodeLockStatements = <String>[
  '''CREATE UNIQUE INDEX IF NOT EXISTS idx_supplier_code_lock_code
ON supplier_product_code_locks(product_code COLLATE NOCASE)''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_valid_insert
BEFORE INSERT ON supplier_product_code_locks
WHEN NOT EXISTS (SELECT 1 FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code=NEW.product_code COLLATE BINARY
    AND s.product_code IS NOT NULL)
  OR EXISTS (SELECT 1 FROM supplier_product_code_locks l
    WHERE l.supplier_id=NEW.supplier_id
       OR (l.product_code=NEW.product_code COLLATE NOCASE AND l.supplier_id!=NEW.supplier_id))
BEGIN SELECT RAISE(ABORT, 'supplier_identity.code_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_immutable_update
BEFORE UPDATE ON supplier_product_code_locks
WHEN NEW.supplier_id IS NOT OLD.supplier_id OR NEW.product_code IS NOT OLD.product_code
  OR NEW.locked_at IS NOT OLD.locked_at
BEGIN SELECT RAISE(ABORT, 'supplier_identity.code_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_immutable_delete
BEFORE DELETE ON supplier_product_code_locks
BEGIN SELECT RAISE(ABORT, 'supplier_identity.code_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_supplier_update
BEFORE UPDATE OF id, product_code ON suppliers
WHEN EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=OLD.id)
  AND (NEW.id IS NOT OLD.id OR NEW.product_code IS NOT OLD.product_code)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.code_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_supplier_replace
BEFORE INSERT ON suppliers
WHEN EXISTS (SELECT 1 FROM supplier_product_code_locks l
  WHERE l.supplier_id=NEW.id AND l.product_code IS NOT NEW.product_code)
  OR EXISTS (SELECT 1 FROM supplier_product_code_locks l
    WHERE l.product_code=NEW.product_code COLLATE NOCASE AND l.supplier_id!=NEW.id)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.code_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_supplier_delete
BEFORE DELETE ON suppliers
WHEN EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=OLD.id)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.delete_blocked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_assign_first_code
AFTER UPDATE OF product_code ON suppliers
WHEN NEW.product_code IS NOT NULL
  AND (EXISTS (SELECT 1 FROM purchases WHERE supplier_id=NEW.id)
  OR EXISTS (SELECT 1 FROM supplier_transactions WHERE supplier_id=NEW.id)
  OR EXISTS (SELECT 1 FROM product_batches WHERE supplier_id=NEW.id)
  OR EXISTS (SELECT 1 FROM purchase_return_adjustments WHERE supplier_id=NEW.id)
  OR EXISTS (SELECT 1 FROM supplier_product_identities WHERE supplier_id=NEW.id))
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT NEW.id,NEW.product_code
  WHERE NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=NEW.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_purchases_insert
AFTER INSERT ON purchases
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_purchases_update
AFTER UPDATE OF supplier_id ON purchases
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_supplier_transactions_insert
AFTER INSERT ON supplier_transactions
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_supplier_transactions_update
AFTER UPDATE OF supplier_id ON supplier_transactions
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_product_batches_insert
AFTER INSERT ON product_batches
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_product_batches_update
AFTER UPDATE OF supplier_id ON product_batches
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_purchase_return_adjustments_insert
AFTER INSERT ON purchase_return_adjustments
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_purchase_return_adjustments_update
AFTER UPDATE OF supplier_id ON purchase_return_adjustments
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_supplier_product_identities_insert
AFTER INSERT ON supplier_product_identities
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_code_lock_supplier_product_identities_update
AFTER UPDATE OF supplier_id ON supplier_product_identities
BEGIN
  INSERT INTO supplier_product_code_locks(supplier_id,product_code)
  SELECT s.id,s.product_code FROM suppliers s
  WHERE s.id=NEW.supplier_id AND s.product_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM supplier_product_code_locks l WHERE l.supplier_id=s.id);
END''',
];

Future<void> installSupplierProductCodeLocks(AppDatabase db) async {
  await db.customStatement(createSupplierProductCodeLocksSql);
  for (final sql in supplierProductCodeLockStatements) {
    await db.customStatement(sql);
  }
  await db.customStatement(backfillSupplierProductCodeLocksSql);
}
