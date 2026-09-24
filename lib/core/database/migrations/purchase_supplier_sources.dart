import '../app_database.dart';

/// v10097. These guards add receipt identity only, not a second stock ledger.
/// Keep historical/unmarked lines unmarked: never backfill from primary supplier.
const purchaseSupplierSourceStatements = <String>[
  '''CREATE INDEX IF NOT EXISTS idx_purchase_items_supplier_identity
ON purchase_items(supplier_identity_id) WHERE supplier_identity_id IS NOT NULL''',
  '''CREATE TRIGGER IF NOT EXISTS purchase_supplier_source_insert
BEFORE INSERT ON purchase_items
WHEN (NEW.supplier_identity_requested NOT IN (0,1))
 OR (NEW.supplier_identity_requested=0 AND NEW.supplier_identity_id IS NOT NULL)
 OR (NEW.supplier_identity_requested=1 AND
   (NEW.supplier_identity_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM supplier_product_identities i
    JOIN purchases p ON p.id=NEW.purchase_id
    JOIN products pr ON pr.id=NEW.product_id
    JOIN product_variants v ON v.id=i.canonical_variant_id
    WHERE i.id=NEW.supplier_identity_id AND i.supplier_id=p.supplier_id
      AND i.product_id=NEW.product_id AND v.product_id=NEW.product_id
      AND pr.track_inventory=1 AND p.status IN ('draft','pending')
      AND (NEW.variant_id=i.canonical_variant_id OR
        (NEW.variant_id IS NULL AND pr.has_variants=0)))))
 OR EXISTS (SELECT 1 FROM purchase_items old JOIN purchases p ON p.id=old.purchase_id
    WHERE old.id=NEW.id AND old.supplier_identity_id IS NOT NULL
      AND p.status NOT IN ('draft','pending'))
BEGIN SELECT RAISE(ABORT, 'supplier_purchase.source_mismatch'); END''',
  '''CREATE TRIGGER IF NOT EXISTS purchase_supplier_source_update
BEFORE UPDATE OF supplier_identity_requested, supplier_identity_id, product_id, variant_id, purchase_id, id
ON purchase_items
WHEN (NEW.supplier_identity_requested NOT IN (0,1))
 OR (NEW.supplier_identity_requested=0 AND NEW.supplier_identity_id IS NOT NULL)
 OR (NEW.supplier_identity_requested=1 AND
   (NEW.supplier_identity_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM supplier_product_identities i
    JOIN purchases p ON p.id=NEW.purchase_id
    JOIN products pr ON pr.id=NEW.product_id
    JOIN product_variants v ON v.id=i.canonical_variant_id
    WHERE i.id=NEW.supplier_identity_id AND i.supplier_id=p.supplier_id
      AND i.product_id=NEW.product_id AND v.product_id=NEW.product_id
      AND (NEW.variant_id=i.canonical_variant_id OR
        (NEW.variant_id IS NULL AND pr.has_variants=0)))))
 OR ((OLD.supplier_identity_id IS NOT NULL OR NEW.supplier_identity_id IS NOT NULL)
   AND EXISTS (SELECT 1 FROM purchases p WHERE p.id IN (OLD.purchase_id,NEW.purchase_id)
     AND p.status NOT IN ('draft','pending'))
   AND (NEW.id IS NOT OLD.id OR NEW.purchase_id IS NOT OLD.purchase_id
    OR NEW.product_id IS NOT OLD.product_id OR NEW.variant_id IS NOT OLD.variant_id
    OR NEW.supplier_identity_id IS NOT OLD.supplier_identity_id
    OR NEW.supplier_identity_requested IS NOT OLD.supplier_identity_requested))
BEGIN SELECT RAISE(ABORT, 'supplier_purchase.source_mismatch'); END''',
  '''CREATE TRIGGER IF NOT EXISTS purchase_supplier_source_delete
BEFORE DELETE ON purchase_items
WHEN OLD.supplier_identity_id IS NOT NULL AND EXISTS (
 SELECT 1 FROM purchases p WHERE p.id=OLD.purchase_id AND p.status NOT IN ('draft','pending'))
BEGIN SELECT RAISE(ABORT, 'supplier_purchase.history_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS purchase_supplier_source_supplier_update
BEFORE UPDATE OF supplier_id, id ON purchases
WHEN (NEW.supplier_id IS NOT OLD.supplier_id OR NEW.id IS NOT OLD.id)
 AND EXISTS (SELECT 1 FROM purchase_items pi WHERE pi.purchase_id=OLD.id
  AND pi.supplier_identity_id IS NOT NULL)
BEGIN SELECT RAISE(ABORT, 'supplier_purchase.source_mismatch'); END''',
  '''CREATE TRIGGER IF NOT EXISTS purchase_supplier_source_header_delete
BEFORE DELETE ON purchases
WHEN OLD.status NOT IN ('draft','pending') AND EXISTS (
 SELECT 1 FROM purchase_items pi WHERE pi.purchase_id=OLD.id AND pi.supplier_identity_id IS NOT NULL)
BEGIN SELECT RAISE(ABORT, 'supplier_purchase.history_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS purchase_supplier_source_header_replace
BEFORE INSERT ON purchases
WHEN EXISTS (SELECT 1 FROM purchases p JOIN purchase_items pi ON pi.purchase_id=p.id
 WHERE (p.id=NEW.id OR p.purchase_number=NEW.purchase_number)
   AND pi.supplier_identity_id IS NOT NULL)
BEGIN SELECT RAISE(ABORT, 'supplier_purchase.history_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS purchase_supplier_source_reopen
BEFORE UPDATE OF status ON purchases
WHEN OLD.status IN ('posted','voided') AND NEW.status NOT IN ('posted','voided')
 AND EXISTS (SELECT 1 FROM purchase_items pi WHERE pi.purchase_id=OLD.id
   AND pi.supplier_identity_id IS NOT NULL)
BEGIN SELECT RAISE(ABORT, 'supplier_purchase.history_locked'); END''',
];

Future<void> installPurchaseSupplierSourceGuards(AppDatabase db) async {
  for (final statement in purchaseSupplierSourceStatements) {
    await db.customStatement(statement);
  }
}
