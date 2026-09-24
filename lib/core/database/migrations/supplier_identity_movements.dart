import '../app_database.dart';

/// v10107 — carries an explicitly verified supplier identity through sales
/// and standalone sale returns. The guards are deliberately additive: null
/// remains valid for legacy/unverified documents and no historical row is
/// attributed automatically.
const supplierIdentityMovementStatements = <String>[
  '''CREATE INDEX IF NOT EXISTS idx_sale_items_supplier_identity
ON sale_items(supplier_identity_id) WHERE supplier_identity_id IS NOT NULL''',
  '''CREATE INDEX IF NOT EXISTS idx_sale_adj_items_supplier_identity
ON sale_return_adjustment_items(supplier_identity_id)
WHERE supplier_identity_id IS NOT NULL''',
  '''CREATE TRIGGER IF NOT EXISTS sale_supplier_identity_insert
BEFORE INSERT ON sale_items
WHEN NEW.supplier_identity_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM supplier_product_identities i
  JOIN products p ON p.id=NEW.product_id
  WHERE i.id=NEW.supplier_identity_id AND i.product_id=NEW.product_id
    AND p.track_inventory=1
    AND (NEW.variant_id=i.canonical_variant_id OR
      (NEW.variant_id IS NULL AND p.has_variants=0)))
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_mismatch'); END''',
  '''CREATE TRIGGER IF NOT EXISTS sale_supplier_identity_update
BEFORE UPDATE OF supplier_identity_id,product_id,variant_id,sale_id ON sale_items
WHEN (NEW.supplier_identity_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM supplier_product_identities i
  JOIN products p ON p.id=NEW.product_id
  WHERE i.id=NEW.supplier_identity_id AND i.product_id=NEW.product_id
    AND p.track_inventory=1
    AND (NEW.variant_id=i.canonical_variant_id OR
      (NEW.variant_id IS NULL AND p.has_variants=0))))
 OR ((OLD.supplier_identity_id IS NOT NULL OR NEW.supplier_identity_id IS NOT NULL)
   AND EXISTS (SELECT 1 FROM sales s WHERE s.id IN (OLD.sale_id,NEW.sale_id)
     AND s.status NOT IN ('draft','pending'))
   AND (NEW.sale_id IS NOT OLD.sale_id OR NEW.product_id IS NOT OLD.product_id
     OR NEW.variant_id IS NOT OLD.variant_id
     OR NEW.supplier_identity_id IS NOT OLD.supplier_identity_id))
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_mismatch'); END''',
  '''CREATE TRIGGER IF NOT EXISTS sale_adj_supplier_identity_insert
BEFORE INSERT ON sale_return_adjustment_items
WHEN (NEW.supplier_identity_id IS NOT NULL AND NEW.consignment_layer_id IS NOT NULL)
 OR (NEW.supplier_identity_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM supplier_product_identities i
  JOIN products p ON p.id=NEW.product_id
  WHERE i.id=NEW.supplier_identity_id AND i.product_id=NEW.product_id
    AND p.track_inventory=1
    AND (NEW.variant_id=i.canonical_variant_id OR
      (NEW.variant_id IS NULL AND p.has_variants=0))))
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_mismatch'); END''',
  '''CREATE TRIGGER IF NOT EXISTS sale_adj_supplier_identity_update
BEFORE UPDATE OF supplier_identity_id,consignment_layer_id,product_id,variant_id,return_id
ON sale_return_adjustment_items
WHEN (NEW.supplier_identity_id IS NOT NULL AND NEW.consignment_layer_id IS NOT NULL)
 OR (NEW.supplier_identity_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM supplier_product_identities i
  JOIN products p ON p.id=NEW.product_id
  WHERE i.id=NEW.supplier_identity_id AND i.product_id=NEW.product_id
    AND p.track_inventory=1
    AND (NEW.variant_id=i.canonical_variant_id OR
      (NEW.variant_id IS NULL AND p.has_variants=0))))
 OR ((OLD.supplier_identity_id IS NOT NULL OR NEW.supplier_identity_id IS NOT NULL)
   AND EXISTS (SELECT 1 FROM sale_return_adjustments r
     WHERE r.id IN (OLD.return_id,NEW.return_id) AND r.status NOT IN ('draft','pending'))
   AND (NEW.return_id IS NOT OLD.return_id OR NEW.product_id IS NOT OLD.product_id
     OR NEW.variant_id IS NOT OLD.variant_id
     OR NEW.consignment_layer_id IS NOT OLD.consignment_layer_id
     OR NEW.supplier_identity_id IS NOT OLD.supplier_identity_id))
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_mismatch'); END''',
];

Future<void> installSupplierIdentityMovementGuards(AppDatabase db) async {
  for (final statement in supplierIdentityMovementStatements) {
    await db.customStatement(statement);
  }
}
