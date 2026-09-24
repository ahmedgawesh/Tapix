#!/usr/bin/env python3
"""Exercise the actual v10095 SQL on SQLite, without Flutter dependencies.

This verifies SQL constraints/migration only, NOT Dart compilation, Flutter
widgets, inventory posting or device integration. Run the Dart tests as well.
"""
from __future__ import annotations
import concurrent.futures
import json
import re
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / 'lib/core/database/migrations/supplier_product_identities.dart'
TEXT = MIGRATION.read_text(encoding='utf-8')
CREATE = re.search(r"const createSupplierProductIdentityTableSql = '''(.*?)''';", TEXT, re.S).group(1)
GUARDS = re.findall(r"'''(.*?)'''", TEXT.split('const supplierProductIdentityGuardStatements', 1)[1], re.S)
OLD = json.loads((ROOT / 'drift_schemas/app_database/drift_schema_v10093.json').read_text(encoding='utf-8'))


def old_database(path=':memory:'):
    db = sqlite3.connect(path, timeout=10, isolation_level=None)
    db.execute('PRAGMA foreign_keys=ON')
    for entry in OLD['fixed_sql']:
        for value in entry['sql']:
            if value['dialect'] == 'sqlite':
                db.execute(value['sql'])
    db.execute('PRAGMA user_version=10093')
    db.execute("INSERT INTO currencies(id,code,name,symbol,exchange_rate) VALUES(1,'USD','US Dollar','$',1)")
    return db


def migrate(db, fail_after=None):
    db.execute('BEGIN IMMEDIATE')
    try:
        if 'product_code' not in [r[1] for r in db.execute('PRAGMA table_info(suppliers)')]:
            db.execute('ALTER TABLE suppliers ADD COLUMN product_code TEXT')
        db.execute(CREATE)
        for n, statement in enumerate(GUARDS):
            db.execute(statement)
            if fail_after == n:
                raise RuntimeError('Injected migration failure')
        db.execute('PRAGMA user_version=10095')
        db.execute('COMMIT')
    except Exception:
        db.execute('ROLLBACK')
        raise


def supplier(db, code=None, name='Supplier', active=1):
    return db.execute('INSERT INTO suppliers(name,currency_id,product_code,is_active) VALUES(?,1,?,?)', (name,code,active)).lastrowid


def product(db, sku='015', variants=False):
    p = db.execute('INSERT INTO products(name,sku,cost_cents,price_cents,currency_id,has_variants,stock_quantity) VALUES(?,?,2500,3500,1,?,80)', ('Product',sku,int(variants))).lastrowid
    v = db.execute('INSERT INTO product_variants(product_id,cost_cents,price_cents,stock_quantity) VALUES(?,2500,3500,80)', (p,)).lastrowid
    return p,v


def issue(db, supplier_id, product_id, variant_id, code='N1', base='015'):
    return db.execute('''INSERT INTO supplier_product_identities(supplier_id,product_id,canonical_variant_id,supplier_code_snapshot,base_sku_snapshot,source_sku)
    VALUES(?,?,?,?,?,?)''',(supplier_id,product_id,variant_id,code,base,code+'-'+base)).lastrowid


def snapshot(db):
    names = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name!='supplier_product_identities' ORDER BY name")]
    result = {}
    for table in names:
        cols = [r[1] for r in db.execute(f'PRAGMA table_info("{table}")') if not(table=='suppliers' and r[1]=='product_code')]
        select = ','.join('"'+c+'"' for c in cols)
        result[table] = db.execute(f'SELECT {select} FROM "{table}" ORDER BY rowid').fetchall()
    return result


class IdentitySqlTests(unittest.TestCase):
    def setUp(self):
        self.db = old_database()
        migrate(self.db)
        self.addCleanup(self.db.close)
        self.n = supplier(self.db, 'N1', 'Noor')
        self.a = supplier(self.db, 'A2', 'Amal')
        self.p,self.v = product(self.db)

    def test_01_alphanumeric(self):
        sid = supplier(self.db, 'ALN2026')
        self.assertEqual(self.db.execute('SELECT product_code FROM suppliers WHERE id=?',(sid,)).fetchone()[0], 'ALN2026')

    def test_02_numbers_keep_leading_zeroes(self):
        sid = supplier(self.db, '007')
        issue(self.db,sid,self.p,self.v,'007')
        self.assertEqual(self.db.execute('SELECT source_sku FROM supplier_product_identities').fetchone()[0],'007-015')

    def test_03_letters_only_allowed(self):
        supplier(self.db,'NOR')

    def test_04_max_length_allowed(self):
        supplier(self.db,'ABCDEFGHIJ12')

    def test_05_invalid_codes_rejected_by_database(self):
        for code in ['', 'a1',' N1','N1 ','N 1','N-1','N_1','A'*13,'نور','N١','A\x00Z','A\nB','N🙂',b'N1']:
            with self.subTest(code=repr(code)):
                with self.assertRaises(sqlite3.IntegrityError): supplier(self.db,code)

    def test_06_optional_null_allows_many(self):
        supplier(self.db,None); supplier(self.db,None)
        self.assertEqual(self.db.execute('SELECT count(*) FROM suppliers WHERE product_code IS NULL').fetchone()[0],2)

    def test_07_existing_prefix_rejected(self):
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_in_use'):
            supplier(self.db,'N1')

    def test_08_inactive_supplier_keeps_reservation(self):
        self.db.execute('UPDATE suppliers SET is_active=0 WHERE id=?',(self.n,))
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_in_use'): supplier(self.db,'N1')

    def test_09_own_unchanged_code_allowed(self):
        self.db.execute("UPDATE suppliers SET product_code='N1',name='Renamed' WHERE id=?",(self.n,))

    def test_10_unused_prefix_can_change(self):
        self.db.execute("UPDATE suppliers SET product_code='N2' WHERE id=?",(self.n,))
        supplier(self.db,'N1')

    def test_11_unused_prefix_released_by_safe_delete(self):
        sid = supplier(self.db,'FREE7'); self.db.execute('DELETE FROM suppliers WHERE id=?',(sid,))
        supplier(self.db,'FREE7')

    def test_12_update_to_other_supplier_code_rejected(self):
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_in_use'):
            self.db.execute("UPDATE suppliers SET product_code='N1' WHERE id=?",(self.a,))

    def test_13_supplier_insert_replace_cannot_steal_code(self):
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_in_use'):
            self.db.execute("INSERT OR REPLACE INTO suppliers(id,name,currency_id,product_code) VALUES(999,'Thief',1,'N1')")
        self.assertEqual(self.db.execute('SELECT name FROM suppliers WHERE id=?',(self.n,)).fetchone()[0],'Noor')

    def test_14_supplier_update_replace_cannot_steal_code(self):
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_in_use'):
            self.db.execute("UPDATE OR REPLACE suppliers SET product_code='N1' WHERE id=?",(self.a,))
        self.assertEqual(self.db.execute('SELECT count(*) FROM suppliers').fetchone()[0],2)

    def test_15_same_product_two_sources(self):
        issue(self.db,self.n,self.p,self.v)
        issue(self.db,self.a,self.p,self.v,'A2')
        self.assertEqual(self.db.execute('SELECT source_sku FROM supplier_product_identities ORDER BY source_sku').fetchall(),[('A2-015',),('N1-015',)])
        self.assertEqual(self.db.execute('SELECT count(*) FROM products').fetchone()[0],1)

    def test_16_same_pair_cannot_issue_again(self):
        issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'identity_exists'):
            issue(self.db,self.n,self.p,self.v,base='OTHER')

    def test_17_no_null_variant_loophole(self):
        with self.assertRaises(sqlite3.IntegrityError):
            issue(self.db,self.n,self.p,None)

    def test_18_variant_product_mismatch_rejected(self):
        other,_ = product(self.db,'OTHER')
        with self.assertRaisesRegex(sqlite3.IntegrityError,'source_mismatch'):
            issue(self.db,self.n,other,self.v)

    def test_19_supplier_snapshot_mismatch_rejected(self):
        with self.assertRaisesRegex(sqlite3.IntegrityError,'source_mismatch'):
            issue(self.db,self.n,self.p,self.v,'A2')

    def test_20_issued_prefix_cannot_change(self):
        issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):
            self.db.execute("UPDATE suppliers SET product_code='NEW' WHERE id=?",(self.n,))

    def test_21_issued_prefix_cannot_clear(self):
        issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):
            self.db.execute('UPDATE suppliers SET product_code=NULL WHERE id=?',(self.n,))

    def test_22_supplier_rename_does_not_rewrite_identity(self):
        issue(self.db,self.n,self.p,self.v)
        self.db.execute("UPDATE suppliers SET name='New name',is_active=0 WHERE id=?",(self.n,))
        self.assertEqual(self.db.execute('SELECT supplier_id,source_sku FROM supplier_product_identities').fetchone(),(self.n,'N1-015'))

    def test_23_issued_supplier_cannot_delete(self):
        issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'delete_blocked'):
            self.db.execute('DELETE FROM suppliers WHERE id=?',(self.n,))

    def test_24_replace_owner_cannot_clear_issued_code(self):
        issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):
            self.db.execute("INSERT OR REPLACE INTO suppliers(id,name,currency_id) VALUES(?,'Wrong',1)",(self.n,))

    def test_25_identity_no_reassignment(self):
        iid=issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'identity_immutable'):
            self.db.execute('UPDATE supplier_product_identities SET supplier_id=? WHERE id=?',(self.a,iid))

    def test_26_identity_no_delete(self):
        issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'identity_immutable'):
            self.db.execute('DELETE FROM supplier_product_identities')

    def test_27_identity_replace_rejected(self):
        iid=issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'identity_exists'):
            self.db.execute("INSERT OR REPLACE INTO supplier_product_identities(id,supplier_id,product_id,canonical_variant_id,supplier_code_snapshot,base_sku_snapshot,source_sku) VALUES(?,?,?,?, 'A2','015','A2-015')",(iid,self.a,self.p,self.v))

    def test_28_variant_cannot_move_to_another_product(self):
        issue(self.db,self.n,self.p,self.v); other,_=product(self.db,'OTHER')
        with self.assertRaisesRegex(sqlite3.IntegrityError,'identity_immutable'):
            self.db.execute('UPDATE product_variants SET product_id=? WHERE id=?',(other,self.v))

    def test_29_existing_parent_sku_collision(self):
        product(self.db,'N1-015')
        with self.assertRaisesRegex(sqlite3.IntegrityError,'source_code_collision'):
            issue(self.db,self.n,self.p,self.v)

    def test_30_existing_barcode_collision_case_insensitive(self):
        other,_=product(self.db,'OTHER')
        self.db.execute("UPDATE products SET barcode='n1-015' WHERE id=?",(other,))
        with self.assertRaisesRegex(sqlite3.IntegrityError,'source_code_collision'):
            issue(self.db,self.n,self.p,self.v)

    def test_31_future_sku_cannot_steal_identity(self):
        issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'source_code_collision'):
            product(self.db,'n1-015')

    def test_32_future_variant_barcode_cannot_steal_identity(self):
        issue(self.db,self.n,self.p,self.v)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'source_code_collision'):
            self.db.execute("UPDATE product_variants SET barcode='N1-015' WHERE id=?",(self.v,))

    def test_33_case_insensitive_source_lookup(self):
        iid=issue(self.db,self.n,self.p,self.v)
        self.assertEqual(self.db.execute("SELECT id FROM supplier_product_identities WHERE source_sku=? COLLATE NOCASE",('n1-015',)).fetchone()[0],iid)

    def test_34_retired_TR_namespace_is_available_to_supplier_identity(self):
        sid=supplier(self.db,'TR'); base='A'*32
        iid=issue(self.db,sid,self.p,self.v,'TR',base)
        self.assertEqual(
            self.db.execute('SELECT source_sku FROM supplier_product_identities WHERE id=?',(iid,)).fetchone()[0],
            'TR-'+base,
        )

    def test_35_no_inventory_or_financial_side_effect(self):
        before=snapshot(self.db)
        issue(self.db,self.n,self.p,self.v)
        self.assertEqual(snapshot(self.db),before)

    def test_36_issuance_rolls_back_with_outer_operation(self):
        self.db.execute('BEGIN')
        issue(self.db,self.n,self.p,self.v)
        self.db.execute('ROLLBACK')
        self.assertEqual(self.db.execute('SELECT count(*) FROM supplier_product_identities').fetchone()[0],0)
        self.db.execute("UPDATE suppliers SET product_code='N2' WHERE id=?",(self.n,))

    def test_37_idempotent_guard_install(self):
        before=self.db.execute("SELECT name,sql FROM sqlite_master WHERE type IN ('index','trigger') ORDER BY name").fetchall()
        for sql in GUARDS: self.db.execute(sql)
        self.assertEqual(self.db.execute("SELECT name,sql FROM sqlite_master WHERE type IN ('index','trigger') ORDER BY name").fetchall(),before)

    def test_38_integrity_and_foreign_keys(self):
        issue(self.db,self.n,self.p,self.v)
        self.assertEqual(self.db.execute('PRAGMA foreign_key_check').fetchall(),[])
        self.assertEqual(self.db.execute('PRAGMA integrity_check').fetchall(),[('ok',)])

    def test_39_control_characters_in_base_rejected(self):
        for base in ['A\x00B','A B','A\nB','نور','A'*65,'-015']:
            with self.subTest(base=repr(base)):
                with self.assertRaises(sqlite3.IntegrityError): issue(self.db,self.n,self.p,self.v,base=base)

    def test_40_valid_base_characters(self):
        issue(self.db,self.n,self.p,self.v,base='015.BL_S/1-2')


class MigrationSqlTests(unittest.TestCase):
    def seed_old(self, db):
        db.execute("INSERT INTO suppliers(id,name,currency_id,balance_cents,opening_balance_cents) VALUES(1,'Existing',1,125000,5000)")
        p,v=product(db)
        db.execute("INSERT INTO purchases(id,purchase_number,supplier_id,subtotal_cents,tax_cents,total_cents,currency_id,status) VALUES(1,'P-OLD',1,125000,0,125000,1,'posted')")
        db.execute('INSERT INTO purchase_items(id,purchase_id,product_id,variant_id,quantity,unit_cost_cents,subtotal_cents,total_cents) VALUES(1,1,?,?,50,2500,125000,125000)',(p,v))
        db.execute("INSERT INTO sales(id,invoice_number,subtotal_cents,tax_cents,total_cents,currency_id,payment_method) VALUES(1,'S-OLD',7000,0,7000,1,'cash')")
        db.execute('INSERT INTO sale_items(sale_id,product_id,variant_id,quantity,unit_price_cents,subtotal_cents,total_cents,cost_cents) VALUES(1,?,?,2,3500,7000,7000,2500)',(p,v))
        db.execute("INSERT INTO sale_return_adjustments(id,return_number,currency_id,total_cents,status) VALUES(1,'R-OLD',1,3500,'posted')")
        db.execute('INSERT INTO sale_return_adjustment_items(return_id,product_id,variant_id,quantity,unit_price_cents,total_cents) VALUES(1,?,?,1,3500,3500)',(p,v))
        db.execute("INSERT INTO journal_entries(entry_number,description,status,total_debit_cents,total_credit_cents) VALUES('JE-OLD','Retained','posted',125000,125000)")

    def test_41_additive_migration_preserves_all_legacy_rows(self):
        db=old_database(); self.addCleanup(db.close); self.seed_old(db); before=snapshot(db)
        migrate(db)
        self.assertEqual(snapshot(db),before)
        self.assertEqual(db.execute('SELECT product_code FROM suppliers').fetchall(),[(None,)])
        self.assertEqual(db.execute('SELECT count(*) FROM supplier_product_identities').fetchone()[0],0)
        self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],10095)
        self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(),[])

    def test_42_failure_rolls_back_and_retry_succeeds(self):
        db=old_database();self.addCleanup(db.close);self.seed_old(db);before=snapshot(db)
        with self.assertRaises(RuntimeError): migrate(db,fail_after=5)
        self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],10093)
        self.assertNotIn('product_code',[r[1] for r in db.execute('PRAGMA table_info(suppliers)')])
        self.assertEqual(db.execute("SELECT name FROM sqlite_master WHERE name='supplier_product_identities'").fetchall(),[])
        self.assertEqual(snapshot(db),before)
        migrate(db)
        self.assertEqual(snapshot(db),before)

    def test_43_file_backup_restore(self):
        with tempfile.TemporaryDirectory() as directory:
            source=old_database(str(Path(directory)/'original.sqlite'));self.seed_old(source)
            backup=sqlite3.connect(str(Path(directory)/'backup.sqlite'),isolation_level=None)
            source.backup(backup)
            before=snapshot(source);migrate(source)
            self.assertEqual(backup.execute('PRAGMA user_version').fetchone()[0],10093)
            self.assertEqual(snapshot(backup),before)
            source.close();backup.close()

    def test_44_two_connections_one_prefix_winner(self):
        with tempfile.TemporaryDirectory() as directory:
            path=str(Path(directory)/'shared.sqlite')
            db=old_database(path);migrate(db);db.close()
            barrier=threading.Barrier(2)
            def contender(name):
                connection=sqlite3.connect(path,timeout=10,isolation_level=None)
                connection.execute('PRAGMA foreign_keys=ON')
                try:
                    barrier.wait(timeout=5)
                    supplier(connection,'N1',name)
                    return 'saved'
                except sqlite3.IntegrityError:
                    return 'conflict'
                finally: connection.close()
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                results=list(pool.map(contender,['first','second']))
            self.assertEqual(sorted(results),['conflict','saved'])
            db=sqlite3.connect(path)
            self.assertEqual(db.execute("SELECT count(*) FROM suppliers WHERE product_code='N1'").fetchone()[0],1)
            db.close()

    def test_45_migration_does_not_rewrite_product_skus(self):
        self.assertNotIn('UPDATE products SET',TEXT)
        self.assertNotIn('UPDATE product_variants SET',TEXT)

    def test_46_all_new_messages_translated(self):
        keys=set(re.findall(r"'supplier_identity\.([a-z_]+)'",TEXT))
        keys.update(re.findall(r"'supplier_identity\.([a-z_]+)'",(ROOT/'lib/core/services/inventory/supplier_identity_rules.dart').read_text()))
        keys.update(re.findall(r"'supplier_identity\.([a-z_]+)'",(ROOT/'lib/core/services/inventory/supplier_product_identity_service.dart').read_text()))
        for lang in ['ar','en','fr']:
            messages=json.loads((ROOT/f'assets/translations/{lang}.json').read_text())['supplier_identity']
            self.assertTrue(keys.issubset(messages), (lang,keys-set(messages)))


if __name__ == '__main__':
    print('SQLite version:', sqlite3.sqlite_version, flush=True)
    print('Scope: actual migration/constraint SQL only; Flutter tests are separate.', flush=True)
    unittest.main(verbosity=2)
