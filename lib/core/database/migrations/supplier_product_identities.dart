import '../app_database.dart';

/// Additive table SQL, also used by the standalone SQLite verification script.
/// Keep aligned with SupplierProductIdentities and verify with Drift tooling.
const createSupplierProductIdentityTableSql = '''
CREATE TABLE IF NOT EXISTS "supplier_product_identities" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "supplier_id" INTEGER NOT NULL REFERENCES suppliers (id) ON DELETE RESTRICT,
  "product_id" INTEGER NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
  "canonical_variant_id" INTEGER NOT NULL REFERENCES product_variants (id) ON DELETE RESTRICT,
  "supplier_code_snapshot" TEXT NOT NULL,
  "base_sku_snapshot" TEXT NOT NULL,
  "source_sku" TEXT NOT NULL,
  "created_at" TEXT NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  UNIQUE ("supplier_id", "canonical_variant_id")
)''';

/// Shared by fresh creation and additive migration 10093 -> 10095.
/// No WHERE is_active=1: inactive suppliers retain their reservations.
/// BEFORE guards also reject INSERT/UPDATE OR REPLACE, whose conflict
/// resolution must never transfer an issued prefix or printed source SKU.
const supplierProductIdentityGuardStatements = <String>[
  '''CREATE UNIQUE INDEX IF NOT EXISTS idx_suppliers_product_code_unique ON suppliers(product_code COLLATE NOCASE)''',
  '''CREATE UNIQUE INDEX IF NOT EXISTS idx_supplier_identity_source_sku ON supplier_product_identities(source_sku COLLATE NOCASE)''',
  '''CREATE INDEX IF NOT EXISTS idx_supplier_identity_product ON supplier_product_identities(product_id, canonical_variant_id)''',
  '''CREATE TRIGGER IF NOT EXISTS suppliers_product_code_valid_insert
BEFORE INSERT ON suppliers
WHEN NEW.product_code IS NOT NULL AND (
  typeof(NEW.product_code) != 'text'
  OR instr(NEW.product_code,char(0))>0
  OR length(NEW.product_code) NOT BETWEEN 1 AND 12
  OR NEW.product_code != upper(trim(NEW.product_code)) COLLATE BINARY
  OR NEW.product_code GLOB '*[^A-Z0-9]*'
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.invalid_code'); END''',
  '''CREATE TRIGGER IF NOT EXISTS suppliers_product_code_unique_insert
BEFORE INSERT ON suppliers
WHEN NEW.product_code IS NOT NULL AND EXISTS (
  SELECT 1 FROM suppliers s
  WHERE s.id != NEW.id
    AND s.product_code = NEW.product_code COLLATE NOCASE
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.code_in_use'); END''',
  '''CREATE TRIGGER IF NOT EXISTS suppliers_product_code_valid_update
BEFORE UPDATE OF product_code ON suppliers
WHEN NEW.product_code IS NOT NULL AND (
  typeof(NEW.product_code) != 'text'
  OR instr(NEW.product_code,char(0))>0
  OR length(NEW.product_code) NOT BETWEEN 1 AND 12
  OR NEW.product_code != upper(trim(NEW.product_code)) COLLATE BINARY
  OR NEW.product_code GLOB '*[^A-Z0-9]*'
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.invalid_code'); END''',
  '''CREATE TRIGGER IF NOT EXISTS suppliers_product_code_unique_update
BEFORE UPDATE OF product_code ON suppliers
WHEN NEW.product_code IS NOT NULL AND EXISTS (
  SELECT 1 FROM suppliers s
  WHERE s.id != NEW.id
    AND s.product_code = NEW.product_code COLLATE NOCASE
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.code_in_use'); END''',
  '''CREATE TRIGGER IF NOT EXISTS suppliers_product_code_locked
BEFORE UPDATE OF product_code ON suppliers
WHEN NEW.product_code IS NOT OLD.product_code AND EXISTS (
  SELECT 1 FROM supplier_product_identities i WHERE i.supplier_id=OLD.id
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.code_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS suppliers_product_code_no_replace_issued
BEFORE INSERT ON suppliers
WHEN EXISTS (
  SELECT 1 FROM supplier_product_identities i WHERE i.supplier_id=NEW.id
) AND NOT EXISTS (
  SELECT 1 FROM suppliers s WHERE s.id=NEW.id
    AND s.product_code IS NEW.product_code
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.code_locked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS suppliers_product_code_no_delete_issued
BEFORE DELETE ON suppliers
WHEN EXISTS (
  SELECT 1 FROM supplier_product_identities i WHERE i.supplier_id=OLD.id
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.delete_blocked'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_identity_no_duplicate
BEFORE INSERT ON supplier_product_identities
WHEN EXISTS (
  SELECT 1 FROM supplier_product_identities i
  WHERE i.id=NEW.id OR i.source_sku=NEW.source_sku COLLATE NOCASE
    OR (i.supplier_id=NEW.supplier_id AND i.canonical_variant_id=NEW.canonical_variant_id)
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.identity_exists'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_identity_valid_source
BEFORE INSERT ON supplier_product_identities
WHEN NOT EXISTS (
  SELECT 1 FROM suppliers s JOIN product_variants v ON v.id=NEW.canonical_variant_id
  WHERE s.id=NEW.supplier_id AND v.product_id=NEW.product_id
    AND s.product_code=NEW.supplier_code_snapshot COLLATE BINARY
    AND s.product_code IS NOT NULL
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_mismatch'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_identity_valid_base_sku
BEFORE INSERT ON supplier_product_identities
WHEN typeof(NEW.base_sku_snapshot) != 'text'
  OR instr(NEW.base_sku_snapshot,char(0))>0
  OR length(NEW.base_sku_snapshot) NOT BETWEEN 1 AND 64
  OR NEW.base_sku_snapshot GLOB '*[^A-Za-z0-9._/-]*'
  OR substr(NEW.base_sku_snapshot,1,1) NOT GLOB '[A-Za-z0-9]'
  OR NEW.source_sku != (NEW.supplier_code_snapshot || '-' || NEW.base_sku_snapshot) COLLATE BINARY
BEGIN SELECT RAISE(ABORT, 'supplier_identity.base_sku_invalid'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_identity_code_namespace
BEFORE INSERT ON supplier_product_identities
WHEN EXISTS (
  SELECT 1 FROM products p WHERE trim(p.sku)=NEW.source_sku COLLATE NOCASE
    OR trim(p.barcode)=NEW.source_sku COLLATE NOCASE
) OR EXISTS (
  SELECT 1 FROM product_variants v WHERE trim(v.sku)=NEW.source_sku COLLATE NOCASE
    OR trim(v.barcode)=NEW.source_sku COLLATE NOCASE
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_code_collision'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_identity_no_reassignment
BEFORE UPDATE ON supplier_product_identities
WHEN NEW.id IS NOT OLD.id OR NEW.supplier_id IS NOT OLD.supplier_id OR NEW.product_id IS NOT OLD.product_id OR NEW.canonical_variant_id IS NOT OLD.canonical_variant_id OR NEW.supplier_code_snapshot IS NOT OLD.supplier_code_snapshot OR NEW.base_sku_snapshot IS NOT OLD.base_sku_snapshot OR NEW.source_sku IS NOT OLD.source_sku OR NEW.created_at IS NOT OLD.created_at
BEGIN SELECT RAISE(ABORT, 'supplier_identity.identity_immutable'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_identity_no_delete
BEFORE DELETE ON supplier_product_identities
WHEN 1
BEGIN SELECT RAISE(ABORT, 'supplier_identity.identity_immutable'); END''',
  '''CREATE TRIGGER IF NOT EXISTS supplier_identity_variant_parent
BEFORE UPDATE OF product_id ON product_variants
WHEN NEW.product_id IS NOT OLD.product_id AND EXISTS (
  SELECT 1 FROM supplier_product_identities i WHERE i.canonical_variant_id=OLD.id
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.identity_immutable'); END''',
  '''CREATE TRIGGER IF NOT EXISTS products_supplier_identity_namespace_insert
BEFORE INSERT ON products
WHEN EXISTS (
  SELECT 1 FROM supplier_product_identities i
  WHERE i.source_sku=trim(NEW.sku) COLLATE NOCASE
    OR i.source_sku=trim(NEW.barcode) COLLATE NOCASE
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_code_collision'); END''',
  '''CREATE TRIGGER IF NOT EXISTS products_supplier_identity_namespace_update
BEFORE UPDATE OF sku, barcode ON products
WHEN EXISTS (
  SELECT 1 FROM supplier_product_identities i
  WHERE i.source_sku=trim(NEW.sku) COLLATE NOCASE
    OR i.source_sku=trim(NEW.barcode) COLLATE NOCASE
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_code_collision'); END''',
  '''CREATE TRIGGER IF NOT EXISTS product_variants_supplier_identity_namespace_insert
BEFORE INSERT ON product_variants
WHEN EXISTS (
  SELECT 1 FROM supplier_product_identities i
  WHERE i.source_sku=trim(NEW.sku) COLLATE NOCASE
    OR i.source_sku=trim(NEW.barcode) COLLATE NOCASE
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_code_collision'); END''',
  '''CREATE TRIGGER IF NOT EXISTS product_variants_supplier_identity_namespace_update
BEFORE UPDATE OF sku, barcode ON product_variants
WHEN EXISTS (
  SELECT 1 FROM supplier_product_identities i
  WHERE i.source_sku=trim(NEW.sku) COLLATE NOCASE
    OR i.source_sku=trim(NEW.barcode) COLLATE NOCASE
)
BEGIN SELECT RAISE(ABORT, 'supplier_identity.source_code_collision'); END''',
];

Future<void> installSupplierProductIdentityGuards(AppDatabase db) async {
  for (final sql in supplierProductIdentityGuardStatements) {
    await db.customStatement(sql);
  }
}
