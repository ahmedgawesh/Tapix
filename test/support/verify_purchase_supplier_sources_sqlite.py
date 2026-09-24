#!/usr/bin/env python3
"""Test Stage2 literal SQL on the user's actual v10096 schema; no Flutter/device DB.

Run from any directory with Python 3. No network, app process or data files are opened.
"""
from pathlib import Path
import json,re,sqlite3,unittest
ROOT=Path(__file__).resolve().parents[2]
SCHEMA=json.loads((ROOT/'drift_schemas/app_database/drift_schema_v10096.json').read_text())
def statements(file,marker):
    t=(ROOT/file).read_text().split(marker,1)[1]
    return re.findall(r"'''(.*?)'''",t,re.S)
IDENTITY=statements('lib/core/database/migrations/supplier_product_identities.dart','const supplierProductIdentityGuardStatements')
LOCKS=statements('lib/core/database/migrations/supplier_product_code_locks.dart','const supplierProductCodeLockStatements')
GUARDS=statements('lib/core/database/migrations/purchase_supplier_sources.dart','const purchaseSupplierSourceStatements')
# Match the actual migration literals, not reimplemented DDL.
TEXT=(ROOT/'lib/core/database/app_database.dart').read_text()
columns=re.findall(r"_safeAddColumn\(\s*'purchase_items',\s*'(supplier_identity_\w+)',\s*'([^']+)'\s*,?\s*\)",TEXT)
assert len(columns)==2, columns

def before96():
    d=sqlite3.connect(':memory:',isolation_level=None);d.row_factory=sqlite3.Row
    d.execute('PRAGMA foreign_keys=ON')
    for e in SCHEMA['fixed_sql']:
        for q in e['sql']:
            if q['dialect']=='sqlite':d.execute(q['sql'])
    for q in IDENTITY+LOCKS:d.execute(q)
    d.execute('PRAGMA user_version=10096')
    d.execute("INSERT INTO currencies(id,code,name,symbol,exchange_rate) VALUES(1,'USD','Dollar','$',1)")
    for i,c in [(1,'N1'),(2,'007'),(3,None)]:
        d.execute('INSERT INTO suppliers(id,name,currency_id,product_code) VALUES(?,?,1,?)',(i,'Supplier '+str(i),c))
    for p in [1,2]:
        d.execute('INSERT INTO products(id,name,sku,cost_cents,price_cents,currency_id) VALUES(?,?,?,2500,3500,1)',(p,'Product '+str(p),f'01{p+4}'))
        d.execute('INSERT INTO product_variants(id,product_id,cost_cents,price_cents) VALUES(?,?,2500,3500)',(p,p))
    return d

def migrate(d,fail=False):
    d.execute('BEGIN IMMEDIATE')
    try:
        for c,t in columns:d.execute(f'ALTER TABLE purchase_items ADD COLUMN {c} {t}')
        for idx,q in enumerate(GUARDS):
            d.execute(q)
            if fail and idx==2:raise RuntimeError('Injected migration failure')
        d.execute('PRAGMA user_version=10097');d.execute('COMMIT')
    except Exception:d.execute('ROLLBACK');raise

def header(d,supplier=1,number='P1',status='draft'):
    return d.execute('INSERT INTO purchases(purchase_number,supplier_id,currency_id,subtotal_cents,tax_cents,total_cents,status) VALUES(?,?,1,5000,0,5000,?)',(number,supplier,status)).lastrowid

def identity(d,supplier=1,product=1):
    row=d.execute('SELECT id FROM supplier_product_identities WHERE supplier_id=? AND canonical_variant_id=?',(supplier,product)).fetchone()
    if row:return row[0]
    prefix=d.execute('SELECT product_code FROM suppliers WHERE id=?',(supplier,)).fetchone()[0]
    base=d.execute('SELECT sku FROM products WHERE id=?',(product,)).fetchone()[0]
    return d.execute('INSERT INTO supplier_product_identities(supplier_id,product_id,canonical_variant_id,supplier_code_snapshot,base_sku_snapshot,source_sku) VALUES(?,?,?,?,?,?)',(supplier,product,product,prefix,base,prefix+'-'+base)).lastrowid

def line(d,pid,source=None,requested=0,product=1,variant=1,qty=2,lot=None):
    return d.execute('INSERT INTO purchase_items(purchase_id,product_id,variant_id,quantity,unit_cost_cents,subtotal_cents,total_cents,supplier_identity_requested,supplier_identity_id,manufacturer_lot_number) VALUES(?,?,?,?,2500,5000,5000,?,?,?)',(pid,product,variant,qty,requested,source,lot)).lastrowid

def snap(d):
    return {r[0]:[dict(x) for x in d.execute('SELECT * FROM "'+r[0]+'" ORDER BY rowid')]
        for r in d.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").fetchall()}

class PurchaseSourceSqlTests(unittest.TestCase):
    def setUp(self):
        self.d=before96();self.addCleanup(self.d.close);migrate(self.d)
    def marked(self,supplier=1,number='P1'):
        p=header(self.d,supplier,number);i=identity(self.d,supplier);l=line(self.d,p,i,1);return p,i,l
    def test_legacy_rows_stay_unbound(self):
        p=header(self.d);l=line(self.d,p);r=self.d.execute('SELECT * FROM purchase_items WHERE id=?',(l,)).fetchone()
        self.assertEqual(r['supplier_identity_requested'],0);self.assertIsNone(r['supplier_identity_id'])
    def test_correct_source_is_accepted(self):
        p,i,l=self.marked();self.assertEqual(self.d.execute('SELECT supplier_identity_id FROM purchase_items WHERE id=?',(l,)).fetchone()[0],i)
    def test_implicit_variant_is_supported(self):
        p=header(self.d);i=identity(self.d);line(self.d,p,i,1,variant=None)
    def test_wrong_supplier_is_rejected(self):
        p=header(self.d,2);i=identity(self.d,1)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'source_mismatch'):line(self.d,p,i,1)
    def test_wrong_product_is_rejected(self):
        p=header(self.d);i=identity(self.d)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'source_mismatch'):line(self.d,p,i,1,product=2,variant=2)
    def test_wrong_variant_is_rejected(self):
        p=header(self.d);i=identity(self.d)
        with self.assertRaises(sqlite3.IntegrityError):line(self.d,p,i,1,variant=2)
    def test_requested_source_cannot_be_null(self):
        p=header(self.d)
        with self.assertRaises(sqlite3.IntegrityError):line(self.d,p,None,1)
    def test_id_without_request_is_rejected(self):
        p=header(self.d);i=identity(self.d)
        with self.assertRaises(sqlite3.IntegrityError):line(self.d,p,i,0)
    def test_invalid_request_flag_is_rejected(self):
        p=header(self.d);i=identity(self.d)
        with self.assertRaises(sqlite3.IntegrityError):line(self.d,p,i,2)
    def test_new_source_cannot_be_injected_into_posted_header(self):
        p=header(self.d,status='posted');i=identity(self.d)
        with self.assertRaises(sqlite3.IntegrityError):line(self.d,p,i,1)
    def test_base_sku_and_quantity_are_not_mutated_by_binding(self):
        before=[dict(x) for x in self.d.execute('SELECT * FROM products')];self.marked()
        self.assertEqual([dict(x) for x in self.d.execute('SELECT * FROM products')],before)
    def test_repeated_pair_reuses_one_identity(self):
        ids=[]
        for k in range(8):
            p=header(self.d,number=f'P{k}');ids.append(identity(self.d));line(self.d,p,ids[-1],1)
        self.assertEqual(len(set(ids)),1)
    def test_two_suppliers_keep_distinct_codes_with_zeros(self):
        self.marked();self.marked(2,'P2')
        self.assertEqual({r[0] for r in self.d.execute('SELECT source_sku FROM supplier_product_identities')},{'N1-015','007-015'})
    def test_two_lots_do_not_merge_purchase_lines(self):
        p=header(self.d);i=identity(self.d);line(self.d,p,i,1,lot='A');line(self.d,p,i,1,lot='B')
        self.assertEqual(self.d.execute('SELECT count(*) FROM purchase_items').fetchone()[0],2)
    def test_direct_supplier_reassignment_requires_rebinding_draft(self):
        p,i,l=self.marked()
        with self.assertRaises(sqlite3.IntegrityError):self.d.execute('UPDATE purchases SET supplier_id=2 WHERE id=?',(p,))
    def test_atomic_draft_replacement_changes_source(self):
        p,i,l=self.marked();self.d.execute('BEGIN');self.d.execute('DELETE FROM purchase_items WHERE id=?',(l,));self.d.execute('UPDATE purchases SET supplier_id=2 WHERE id=?',(p,));a=identity(self.d,2);line(self.d,p,a,1);self.d.execute('COMMIT')
        self.assertEqual(self.d.execute('SELECT supplier_identity_id FROM purchase_items').fetchone()[0],a)
    def test_failed_draft_replace_restores_everything(self):
        p,i,l=self.marked();before=snap(self.d);self.d.execute('BEGIN')
        self.d.execute('DELETE FROM purchase_items WHERE id=?',(l,));self.d.execute('UPDATE purchases SET supplier_id=2 WHERE id=?',(p,));identity(self.d,2)
        with self.assertRaises(sqlite3.IntegrityError):line(self.d,p,i,1)
        self.d.execute('ROLLBACK');self.assertEqual(snap(self.d),before)
    def test_failure_after_identity_rolls_back_new_prefix_lock(self):
        before=snap(self.d);self.d.execute('BEGIN');self.marked()
        with self.assertRaises(sqlite3.IntegrityError):line(self.d,1,None,1)
        self.d.execute('ROLLBACK');self.assertEqual(snap(self.d),before)
    def test_supplier_code_stays_locked_after_draft_deleted(self):
        p,i,l=self.marked();self.d.execute('DELETE FROM purchases WHERE id=?',(p,))
        with self.assertRaises(sqlite3.IntegrityError):self.d.execute("UPDATE suppliers SET product_code='NEW' WHERE id=1")
    def test_posted_source_cannot_be_removed(self):
        p,i,l=self.marked();self.d.execute("UPDATE purchases SET status='posted' WHERE id=?",(p,))
        with self.assertRaises(sqlite3.IntegrityError):self.d.execute('UPDATE purchase_items SET supplier_identity_requested=0,supplier_identity_id=NULL WHERE id=?',(l,))
    def test_posted_source_cannot_be_changed(self):
        p,i,l=self.marked();other=identity(self.d,2);self.d.execute("UPDATE purchases SET status='posted' WHERE id=?",(p,))
        with self.assertRaises(sqlite3.IntegrityError):self.d.execute('UPDATE purchase_items SET supplier_identity_id=? WHERE id=?',(other,l))
    def test_posted_lines_cannot_be_deleted(self):
        p,i,l=self.marked();self.d.execute("UPDATE purchases SET status='posted' WHERE id=?",(p,))
        with self.assertRaises(sqlite3.IntegrityError):self.d.execute('DELETE FROM purchase_items WHERE id=?',(l,))
    def test_posted_header_cannot_be_deleted(self):
        p,i,l=self.marked();self.d.execute("UPDATE purchases SET status='posted' WHERE id=?",(p,))
        with self.assertRaises(sqlite3.IntegrityError):self.d.execute('DELETE FROM purchases WHERE id=?',(p,))
    def test_posted_header_cannot_be_reopened(self):
        p,i,l=self.marked();self.d.execute("UPDATE purchases SET status='posted' WHERE id=?",(p,))
        with self.assertRaises(sqlite3.IntegrityError):self.d.execute("UPDATE purchases SET status='draft' WHERE id=?",(p,))
    def test_void_preserves_source(self):
        p,i,l=self.marked();self.d.execute("UPDATE purchases SET status='posted' WHERE id=?",(p,));self.d.execute("UPDATE purchases SET status='voided' WHERE id=?",(p,));self.assertEqual(self.d.execute('SELECT supplier_identity_id FROM purchase_items WHERE id=?',(l,)).fetchone()[0],i)
    def test_posting_cost_snapshot_update_is_allowed(self):
        p,i,l=self.marked();self.d.execute('UPDATE purchase_items SET inventory_value_at_post_cents=5000 WHERE id=?',(l,));self.d.execute("UPDATE purchases SET status='posted' WHERE id=?",(p,));self.d.execute('UPDATE purchase_items SET qty_returned_linked=1 WHERE id=?',(l,))
    def test_replace_cannot_bypass_history_protection(self):
        p,i,l=self.marked();self.d.execute("UPDATE purchases SET status='posted' WHERE id=?",(p,))
        with self.assertRaises(sqlite3.IntegrityError):self.d.execute('INSERT OR REPLACE INTO purchases(id,purchase_number,supplier_id,currency_id,subtotal_cents,tax_cents,total_cents) VALUES(?,?,?,?,0,0,0)',(p,'P1',2,1))
    def test_inactive_supplier_keeps_historical_binding(self):
        p,i,l=self.marked();self.d.execute('UPDATE suppliers SET is_active=0 WHERE id=1');self.assertEqual(self.d.execute('SELECT supplier_identity_id FROM purchase_items WHERE id=?',(l,)).fetchone()[0],i)
    def test_old_unmarked_posted_lines_keep_legacy_behavior(self):
        p=header(self.d,status='posted');line(self.d,p);self.assertEqual(self.d.execute('SELECT count(*) FROM supplier_product_identities').fetchone()[0],0)
    def test_foreign_keys_and_integrity(self):
        self.marked();self.assertEqual(self.d.execute('PRAGMA foreign_key_check').fetchall(),[]);self.assertEqual(self.d.execute('PRAGMA integrity_check').fetchone()[0],'ok')
    def test_migration_preserves_existing_rows_and_leaves_sources_unknown(self):
        d=before96();self.addCleanup(d.close);p=header(d,status='posted');d.execute('INSERT INTO purchase_items(purchase_id,product_id,variant_id,quantity,unit_cost_cents,subtotal_cents,total_cents) VALUES(?,1,1,2,2500,5000,5000)',(p,));before=snap(d);migrate(d);after=snap(d)
        for row in after['purchase_items']:
            self.assertEqual(row.pop('supplier_identity_requested'),0);self.assertIsNone(row.pop('supplier_identity_id'))
        self.assertEqual(after,before)
    def test_failed_migration_rolls_back_columns_and_version_then_retries(self):
        d=before96();self.addCleanup(d.close);before=snap(d)
        with self.assertRaises(RuntimeError):migrate(d,fail=True)
        self.assertEqual(d.execute('PRAGMA user_version').fetchone()[0],10096);self.assertEqual(snap(d),before)
        self.assertNotIn('supplier_identity_id',[r[1] for r in d.execute('PRAGMA table_info(purchase_items)')]);migrate(d);self.assertEqual(d.execute('PRAGMA user_version').fetchone()[0],10097)

if __name__=='__main__':unittest.main(verbosity=2)
