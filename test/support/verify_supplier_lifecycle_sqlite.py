#!/usr/bin/env python3
"""Exercise literal v10096 migration/guards against the real v10095 export.

Uses only temporary/in-memory SQLite databases. Does not run Flutter/Dart,
open an application database, or prove correctness of device integration.
"""
from __future__ import annotations
import json
import re
import sqlite3
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = json.loads((ROOT / 'drift_schemas/app_database/drift_schema_v10095.json').read_text())
TEXT = (ROOT / 'lib/core/database/migrations/supplier_product_code_locks.dart').read_text()
CREATE = re.search(r"const createSupplierProductCodeLocksSql = '''(.*?)''';", TEXT, re.S).group(1)
BACKFILL = re.search(r"const backfillSupplierProductCodeLocksSql = '''(.*?)''';", TEXT, re.S).group(1)
GUARDS = re.findall(r"'''(.*?)'''", TEXT.split('const supplierProductCodeLockStatements', 1)[1], re.S)
OLD_TEXT = (ROOT / 'lib/core/database/migrations/supplier_product_identities.dart').read_text()
OLD_GUARDS = re.findall(r"'''(.*?)'''", OLD_TEXT.split('const supplierProductIdentityGuardStatements', 1)[1], re.S)


def old_db(path=':memory:'):
    db = sqlite3.connect(path, isolation_level=None)
    db.execute('PRAGMA foreign_keys=ON')
    for entry in SCHEMA['fixed_sql']:
        for sql in entry['sql']:
            if sql['dialect'] == 'sqlite':
                db.execute(sql['sql'])
    for sql in OLD_GUARDS:
        db.execute(sql)
    db.execute('PRAGMA user_version=10095')
    db.execute("INSERT INTO currencies(id,code,name,symbol,exchange_rate) VALUES(1,'USD','Dollar','$',1)")
    return db


def migrate(db, fail_after=None):
    db.execute('BEGIN IMMEDIATE')
    try:
        db.execute(CREATE)
        for i, sql in enumerate(GUARDS):
            db.execute(sql)
            if fail_after == i:
                raise RuntimeError('Injected migration failure')
        db.execute(BACKFILL)
        db.execute('PRAGMA user_version=10096')
        db.execute('COMMIT')
    except Exception:
        db.execute('ROLLBACK')
        raise


def supplier(db, code, active=1):
    return db.execute('INSERT INTO suppliers(name,currency_id,product_code,is_active) VALUES(?,1,?,?)',
                      ('Supplier '+str(code), code, active)).lastrowid


def purchase(db, sid, number='PO1', status='posted'):
    return db.execute('''INSERT INTO purchases(purchase_number,supplier_id,subtotal_cents,tax_cents,total_cents,currency_id,status)
                         VALUES(?,?,2500,0,2500,1,?)''', (number, sid, status)).lastrowid


def product(db):
    pid = db.execute("INSERT INTO products(name,sku,cost_cents,price_cents,currency_id) VALUES('Test','015',2500,3500,1)").lastrowid
    vid = db.execute('INSERT INTO product_variants(product_id,cost_cents,price_cents) VALUES(?,2500,3500)', (pid,)).lastrowid
    return pid, vid


def snapshot(db):
    names = [r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name!='supplier_product_code_locks' ORDER BY name")]
    return {n: db.execute('SELECT * FROM "'+n+'" ORDER BY rowid').fetchall() for n in names}


class SupplierLifecycleSqlTests(unittest.TestCase):
    def setUp(self):
        self.db = old_db()
        self.addCleanup(self.db.close)
        self.n = supplier(self.db, 'N1')
        self.a = supplier(self.db, 'A2')
        self.legacy = supplier(self.db, None)
        self.p, self.v = product(self.db)
        migrate(self.db)

    def change(self, sid, code):
        self.db.execute('UPDATE suppliers SET product_code=? WHERE id=?', (code,sid))

    def locks(self):
        return self.db.execute('SELECT supplier_id,product_code FROM supplier_product_code_locks ORDER BY supplier_id').fetchall()

    def test_unused_prefix_can_change(self):
        self.change(self.n,'N2')
        supplier(self.db,'N1')
        self.assertEqual(self.locks(), [])

    def test_saved_invoice_locks_without_identity(self):
        purchase(self.db,self.n)
        self.assertEqual(self.locks(),[(self.n,'N1')])
        self.assertEqual(self.db.execute('SELECT count(*) FROM supplier_product_identities').fetchone()[0],0)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'): self.change(self.n,'N2')

    def test_saved_draft_locks_too(self):
        purchase(self.db,self.n,status='draft')
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'): self.change(self.n,'N2')

    def test_empty_and_null_cannot_clear_used_code(self):
        purchase(self.db,self.n)
        for code in [None, '']:
            with self.subTest(code=code), self.assertRaises(sqlite3.IntegrityError): self.change(self.n,code)
        self.assertEqual(self.locks(),[(self.n,'N1')])

    def test_rename_same_code_allowed(self):
        purchase(self.db,self.n)
        self.db.execute("UPDATE suppliers SET name='Renamed',product_code='N1' WHERE id=?",(self.n,))
        self.assertEqual(self.db.execute('SELECT name FROM suppliers WHERE id=?',(self.n,)).fetchone()[0],'Renamed')

    def test_status_and_balance_updates_do_not_unlock_or_conflict(self):
        purchase(self.db,self.n)
        self.db.execute('UPDATE suppliers SET is_active=0,balance_cents=42 WHERE id=?',(self.n,))
        self.db.execute('UPDATE suppliers SET is_active=1 WHERE id=?',(self.n,))
        self.assertEqual(self.db.execute('SELECT balance_cents,product_code,is_active FROM suppliers WHERE id=?',(self.n,)).fetchone(),(42,'N1',1))
        self.assertEqual(self.locks(),[(self.n,'N1')])

    def test_inactive_code_cannot_be_reused(self):
        self.db.execute('UPDATE suppliers SET is_active=0 WHERE id=?',(self.n,))
        with self.assertRaises(sqlite3.IntegrityError): supplier(self.db,'N1')
        with self.assertRaises(sqlite3.IntegrityError): supplier(self.db,'n1')

    def test_leading_zeroes_retained_on_lock(self):
        sid=supplier(self.db,'007');purchase(self.db,sid)
        self.assertEqual(self.locks(),[(sid,'007')])
        self.assertEqual(self.db.execute('SELECT typeof(product_code) FROM supplier_product_code_locks').fetchone()[0],'text')

    def test_legacy_history_without_code_allows_first_assignment(self):
        purchase(self.db,self.legacy)
        self.assertEqual(self.locks(),[])
        self.change(self.legacy,'OLD8')
        self.assertEqual(self.locks(),[(self.legacy,'OLD8')])
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'): self.change(self.legacy,'OLD9')

    def test_repeated_invoice_does_not_duplicate_lock(self):
        for i in range(10): purchase(self.db,self.n,number=f'P{i}')
        self.assertEqual(self.locks(),[(self.n,'N1')])

    def test_cancel_delete_invoice_does_not_unlock(self):
        pid=purchase(self.db,self.n,status='draft')
        self.db.execute("UPDATE purchases SET status='cancelled' WHERE id=?",(pid,))
        self.db.execute('DELETE FROM purchases WHERE id=?',(pid,))
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'): self.change(self.n,'N2')
        with self.assertRaisesRegex(sqlite3.IntegrityError,'delete_blocked'): self.db.execute('DELETE FROM suppliers WHERE id=?',(self.n,))

    def test_invoice_supplier_change_locks_both_historical_codes(self):
        pid=purchase(self.db,self.n,status='draft')
        self.db.execute('UPDATE purchases SET supplier_id=? WHERE id=?',(self.a,pid))
        self.assertEqual(self.locks(),[(self.n,'N1'),(self.a,'A2')])

    def test_transaction_locks(self):
        self.db.execute("INSERT INTO supplier_transactions(supplier_id,transaction_type,amount_cents,currency_id) VALUES(?,'payment',-100,1)",(self.n,))
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'): self.change(self.n,'N2')

    def test_batch_locks(self):
        self.db.execute("INSERT INTO product_batches(product_id,variant_id,supplier_id,batch_number,received_quantity,remaining_quantity,unit_cost_cents) VALUES(?,?,?,'B1',1,1,2500)",(self.p,self.v,self.n))
        self.assertEqual(self.locks(),[(self.n,'N1')])

    def test_purchase_adjustment_return_locks(self):
        self.db.execute("INSERT INTO purchase_return_adjustments(return_number,supplier_id,currency_id,total_cents) VALUES('R1',?,1,2500)",(self.n,))
        self.assertEqual(self.locks(),[(self.n,'N1')])

    def test_issued_identity_locks_even_without_invoice(self):
        self.db.execute("INSERT INTO supplier_product_identities(supplier_id,product_id,canonical_variant_id,supplier_code_snapshot,base_sku_snapshot,source_sku) VALUES(?,?,?,'N1','015','N1-015')",(self.n,self.p,self.v))
        self.assertEqual(self.locks(),[(self.n,'N1')])

    def test_lock_update_and_delete_rejected(self):
        purchase(self.db,self.n)
        for sql in ["UPDATE supplier_product_code_locks SET product_code='N2'",'DELETE FROM supplier_product_code_locks',"UPDATE supplier_product_code_locks SET locked_at='2099-01-01'"]:
            with self.subTest(sql=sql), self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):self.db.execute(sql)

    def test_direct_sql_replace_cannot_change_owner(self):
        purchase(self.db,self.n)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):
            self.db.execute("INSERT OR REPLACE INTO suppliers(id,name,currency_id,product_code) VALUES(?,'Hijack',1,'N9')",(self.n,))
        with self.assertRaises(sqlite3.IntegrityError):supplier(self.db,'N1')

    def test_direct_sql_cannot_reassign_supplier_id(self):
        purchase(self.db,self.n)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):self.db.execute('UPDATE suppliers SET id=100 WHERE id=?',(self.n,))

    def test_update_or_ignore_does_not_bypass_lock(self):
        purchase(self.db,self.n)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):self.db.execute("UPDATE OR IGNORE suppliers SET product_code='X9' WHERE id=?",(self.n,))

    def test_lock_sidecar_cannot_be_replaced_with_other_code(self):
        purchase(self.db,self.n)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):
            self.db.execute("INSERT OR REPLACE INTO supplier_product_code_locks(supplier_id,product_code) VALUES(?,'N9')",(self.n,))

    def test_lock_sidecar_cannot_replace_timestamp_even_with_same_code(self):
        purchase(self.db,self.n)
        with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):
            self.db.execute("INSERT OR REPLACE INTO supplier_product_code_locks(supplier_id,product_code,locked_at) VALUES(?,'N1','2099-01-01')",(self.n,))

    def test_duplicate_invoice_failure_rolls_back_new_supplier_lock(self):
        purchase(self.db,self.n)
        with self.assertRaises(sqlite3.IntegrityError): purchase(self.db,self.a)
        self.assertEqual(self.locks(),[(self.n,'N1')])

    def test_invoice_transaction_rollback_includes_lock(self):
        self.db.execute('BEGIN IMMEDIATE')
        purchase(self.db,self.n)
        self.assertEqual(self.locks(),[(self.n,'N1')])
        self.db.execute('ROLLBACK')
        self.assertEqual(self.locks(),[])
        self.change(self.n,'N2')

    def test_first_assignment_rollback_restores_null_and_no_lock(self):
        purchase(self.db,self.legacy)
        self.db.execute('BEGIN IMMEDIATE');self.change(self.legacy,'L9');self.db.execute('ROLLBACK')
        self.assertEqual(self.locks(),[])
        self.assertIsNone(self.db.execute('SELECT product_code FROM suppliers WHERE id=?',(self.legacy,)).fetchone()[0])

    def test_lock_does_not_change_inventory_or_financial_data(self):
        before=snapshot(self.db)
        self.db.execute('INSERT INTO supplier_product_code_locks(supplier_id,product_code) VALUES(?,?)',(self.n,'N1'))
        self.assertEqual(snapshot(self.db),before)

    def test_fk_integrity_checks(self):
        purchase(self.db,self.n)
        self.assertEqual(self.db.execute('PRAGMA foreign_key_check').fetchall(),[])
        self.assertEqual(self.db.execute('PRAGMA integrity_check').fetchone()[0],'ok')


class SupplierLifecycleMigrationTests(unittest.TestCase):
    def test_existing_invoice_codes_frozen_without_modifying_old_data(self):
        db=old_db();self.addCleanup(db.close)
        n=supplier(db,'N1',active=0);a=supplier(db,'007');none=supplier(db,None);unused=supplier(db,'FREE9')
        purchase(db,n,number='OLD1');purchase(db,a,number='OLD2');purchase(db,none,number='OLD3')
        before=snapshot(db);migrate(db)
        self.assertEqual(snapshot(db),before)
        self.assertEqual(db.execute('SELECT supplier_id,product_code FROM supplier_product_code_locks ORDER BY supplier_id').fetchall(),[(n,'N1'),(a,'007')])
        self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],10096)
        db.execute("UPDATE suppliers SET product_code='FREE8' WHERE id=?",(unused,))

    def test_existing_codes_are_not_invented_or_restored_from_names(self):
        db=old_db();self.addCleanup(db.close)
        s=supplier(db,'CHANGED9');purchase(db,s)
        db.execute("UPDATE suppliers SET product_code='CURRENT9' WHERE id=?",(s,))
        migrate(db)
        self.assertEqual(db.execute('SELECT product_code FROM supplier_product_code_locks').fetchone()[0],'CURRENT9')

    def test_migration_failure_rolls_back_table_triggers_and_version(self):
        db=old_db();self.addCleanup(db.close)
        n=supplier(db,'N1');purchase(db,n);before=snapshot(db)
        with self.assertRaises(RuntimeError):migrate(db,fail_after=3)
        self.assertEqual(snapshot(db),before)
        self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],10095)
        self.assertEqual(db.execute("SELECT name FROM sqlite_master WHERE name='supplier_product_code_locks'").fetchall(),[])
        migrate(db)
        self.assertEqual(db.execute('SELECT product_code FROM supplier_product_code_locks').fetchone()[0],'N1')

    def test_schema_name_collision_fails_instead_of_ignoring(self):
        db=old_db();self.addCleanup(db.close)
        db.execute('CREATE VIEW supplier_product_code_locks AS SELECT 1 AS incompatible')
        with self.assertRaises(sqlite3.DatabaseError):migrate(db)
        self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],10095)

    def test_installation_idempotent(self):
        db=old_db();self.addCleanup(db.close)
        n=supplier(db,'N1');purchase(db,n);migrate(db)
        before=db.execute('SELECT * FROM supplier_product_code_locks').fetchall()
        migrate(db)
        self.assertEqual(db.execute('SELECT * FROM supplier_product_code_locks').fetchall(),before)

    def test_new_connection_keeps_guard_after_document_removed(self):
        with tempfile.TemporaryDirectory() as d:
            path=str(Path(d)/'test.sqlite');db=old_db(path)
            n=supplier(db,'N1');purchase(db,n);migrate(db);db.execute('DELETE FROM purchases');db.close()
            db=sqlite3.connect(path);self.addCleanup(db.close)
            with self.assertRaisesRegex(sqlite3.IntegrityError,'code_locked'):db.execute("UPDATE suppliers SET product_code='N2' WHERE id=?",(n,))

    def test_new_source_transactions_update_existing_locks_under_replace(self):
        db=old_db();self.addCleanup(db.close);n=supplier(db,'N1');migrate(db)
        pid=purchase(db,n)
        db.execute('INSERT OR REPLACE INTO purchases(id,purchase_number,supplier_id,subtotal_cents,tax_cents,total_cents,currency_id) VALUES(?,\'PO1\',?,2500,0,2500,1)',(pid,n))
        self.assertEqual(db.execute('SELECT count(*) FROM supplier_product_code_locks').fetchone()[0],1)

if __name__=='__main__':
    unittest.main(verbosity=2)
