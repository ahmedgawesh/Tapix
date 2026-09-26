import 'package:drift/drift.dart';

import '../app_database.dart';

class ConsignmentOwnershipConversionEconomics {
  const ConsignmentOwnershipConversionEconomics({
    required this.conversionId,
    required this.inventoryValueCents,
    required this.supplierCreditNetCents,
    required this.supplierCreditTaxCents,
    required this.supplierCreditTotalCents,
    required this.varianceCents,
  });

  final int conversionId;
  final int inventoryValueCents;
  final int supplierCreditNetCents;
  final int supplierCreditTaxCents;
  final int supplierCreditTotalCents;
  final int varianceCents;
}

/// Persists the financial terms that are separate from the physical ownership
/// conversion. The inventory carrying value can differ from the supplier's
/// credit-note net amount; tax and the resulting variance are therefore frozen
/// independently instead of being inferred later.
Future<void> installConsignmentOwnershipConversionEconomics(
  AppDatabase db,
) async {
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS consignment_ownership_conversion_economics (
      conversion_id INTEGER PRIMARY KEY
        REFERENCES consignment_ownership_conversions(id) ON DELETE RESTRICT,
      inventory_value_cents INTEGER NOT NULL,
      supplier_credit_net_cents INTEGER NOT NULL,
      supplier_credit_tax_cents INTEGER NOT NULL,
      supplier_credit_total_cents INTEGER NOT NULL,
      variance_cents INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      CHECK(inventory_value_cents>0 AND inventory_value_cents<=9007199254740991),
      CHECK(supplier_credit_net_cents>=0 AND supplier_credit_net_cents<=9007199254740991),
      CHECK(supplier_credit_tax_cents>=0 AND supplier_credit_tax_cents<=9007199254740991),
      CHECK(supplier_credit_total_cents>0 AND supplier_credit_total_cents<=9007199254740991),
      CHECK(supplier_credit_total_cents=supplier_credit_net_cents+supplier_credit_tax_cents),
      CHECK(variance_cents=supplier_credit_net_cents-inventory_value_cents)
    )
  ''');

  // A previous app start may already have installed the strict INSERT guard
  // before a later startup discovered a legacy posted row with no economics.
  // Drop all guards before the idempotent backfill so reopening an existing
  // customer database can repair that missing additive row safely.
  for (final name in const [
    'consignment_conversion_economics_insert_guard',
    'consignment_conversion_economics_immutable',
    'consignment_conversion_economics_no_delete',
    'consignment_conversion_economics_completion_guard',
  ]) {
    await db.customStatement('DROP TRIGGER IF EXISTS $name');
  }

  // Reconstruct only economics that the previous implementation already
  // proved: its immutable supplier transaction always equalled the carrying
  // value and recorded no separate tax. This preserves existing customers'
  // posted and voided conversions without guessing from product prices.
  await db.customStatement('''
    INSERT OR IGNORE INTO consignment_ownership_conversion_economics(
      conversion_id,inventory_value_cents,supplier_credit_net_cents,
      supplier_credit_tax_cents,supplier_credit_total_cents,variance_cents,
      created_at
    )
    SELECT c.id,c.inventory_value_cents,c.inventory_value_cents,0,
           c.inventory_value_cents,0,COALESCE(c.created_at,CURRENT_TIMESTAMP)
    FROM consignment_ownership_conversions c
    JOIN supplier_transactions st ON st.id=c.supplier_transaction_id
    WHERE c.status IN ('posted','voided')
      AND st.reference_type='consignment_ownership_conversion'
      AND st.reference_id=c.id
      AND st.amount_cents=-c.inventory_value_cents
  ''');

  await db.customStatement('''
    CREATE TRIGGER consignment_conversion_economics_insert_guard
    BEFORE INSERT ON consignment_ownership_conversion_economics
    WHEN NOT EXISTS(
      SELECT 1 FROM consignment_ownership_conversions c
      WHERE c.id=NEW.conversion_id
        AND c.status='posting'
        AND c.inventory_value_cents=NEW.inventory_value_cents
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid ownership conversion economics');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER consignment_conversion_economics_immutable
    BEFORE UPDATE ON consignment_ownership_conversion_economics
    BEGIN
      SELECT RAISE(ABORT,'Ownership conversion economics are immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER consignment_conversion_economics_no_delete
    BEFORE DELETE ON consignment_ownership_conversion_economics
    BEGIN
      SELECT RAISE(ABORT,'Ownership conversion economics are immutable');
    END
  ''');

  // The conversion can become posted/voided only when its journal and supplier
  // sub-ledger reproduce the exact frozen economics, account by account.
  await db.customStatement('''
    CREATE TRIGGER consignment_conversion_economics_completion_guard
    BEFORE UPDATE OF status ON consignment_ownership_conversions
    WHEN (
      NEW.status='posted' AND NOT EXISTS(
        SELECT 1
        FROM consignment_ownership_conversion_economics e
        JOIN supplier_transactions st ON st.id=NEW.supplier_transaction_id
        JOIN journal_entries j ON j.id=NEW.journal_entry_id
        WHERE e.conversion_id=NEW.id
          AND e.inventory_value_cents=NEW.inventory_value_cents
          AND st.supplier_id=NEW.supplier_id
          AND st.currency_id=NEW.currency_id
          AND st.reference_type='consignment_ownership_conversion'
          AND st.reference_id=NEW.id
          AND st.amount_cents=-e.supplier_credit_total_cents
          AND j.status='posted'
          AND j.entry_type='consignment_ownership_conversion'
          AND j.source_table='consignment_ownership_conversions'
          AND j.source_id=NEW.id
          AND (SELECT COALESCE(SUM(l.debit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='2000')
              =e.supplier_credit_total_cents
          AND (SELECT COALESCE(SUM(l.credit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='1200')
              =e.inventory_value_cents
          AND (SELECT COALESCE(SUM(l.credit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='1300')
              =e.supplier_credit_tax_cents
          AND (SELECT COALESCE(SUM(l.credit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='4900')
              =CASE WHEN e.variance_cents>0 THEN e.variance_cents ELSE 0 END
          AND (SELECT COALESCE(SUM(l.debit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='5900')
              =CASE WHEN e.variance_cents<0 THEN -e.variance_cents ELSE 0 END
      )
    ) OR (
      NEW.status='voided' AND NOT EXISTS(
        SELECT 1
        FROM consignment_ownership_conversion_economics e
        JOIN supplier_transactions st
          ON st.id=NEW.reversal_supplier_transaction_id
        JOIN journal_entries j ON j.id=NEW.reversal_journal_entry_id
        WHERE e.conversion_id=NEW.id
          AND st.supplier_id=NEW.supplier_id
          AND st.currency_id=NEW.currency_id
          AND st.reference_type='consignment_ownership_conversion_void'
          AND st.reference_id=NEW.id
          AND st.amount_cents=e.supplier_credit_total_cents
          AND j.status='posted'
          AND j.entry_type='consignment_ownership_conversion_void'
          AND j.source_table='consignment_ownership_conversions'
          AND j.source_id=NEW.id
          AND (SELECT COALESCE(SUM(l.credit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='2000')
              =e.supplier_credit_total_cents
          AND (SELECT COALESCE(SUM(l.debit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='1200')
              =e.inventory_value_cents
          AND (SELECT COALESCE(SUM(l.debit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='1300')
              =e.supplier_credit_tax_cents
          AND (SELECT COALESCE(SUM(l.debit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='4900')
              =CASE WHEN e.variance_cents>0 THEN e.variance_cents ELSE 0 END
          AND (SELECT COALESCE(SUM(l.credit_cents),0)
               FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id
               WHERE l.journal_entry_id=j.id AND a.account_code='5900')
              =CASE WHEN e.variance_cents<0 THEN -e.variance_cents ELSE 0 END
      )
    )
    BEGIN
      SELECT RAISE(ABORT,'Ownership conversion accounting does not match evidence');
    END
  ''');
}

class ConsignmentOwnershipConversionEconomicsStore {
  ConsignmentOwnershipConversionEconomicsStore._();

  static Future<void> record(
    DatabaseAccessor<AppDatabase> dao, {
    required int conversionId,
    required int inventoryValueCents,
    required int supplierCreditNetCents,
    required int supplierCreditTaxCents,
  }) async {
    final db = dao.attachedDatabase;
    final total = supplierCreditNetCents + supplierCreditTaxCents;
    if (inventoryValueCents <= 0 ||
        supplierCreditNetCents < 0 ||
        supplierCreditTaxCents < 0 ||
        total <= 0) {
      throw StateError('consignment.conversion_credit_invalid');
    }
    await db.customStatement(
      'INSERT INTO consignment_ownership_conversion_economics('
      'conversion_id,inventory_value_cents,supplier_credit_net_cents,'
      'supplier_credit_tax_cents,supplier_credit_total_cents,variance_cents,'
      'created_at) VALUES(?,?,?,?,?,?,?)',
      [
        conversionId,
        inventoryValueCents,
        supplierCreditNetCents,
        supplierCreditTaxCents,
        total,
        supplierCreditNetCents - inventoryValueCents,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  static Future<ConsignmentOwnershipConversionEconomics> require(
    DatabaseAccessor<AppDatabase> dao,
    int conversionId,
  ) async {
    final row = await dao
        .customSelect(
          'SELECT conversion_id,inventory_value_cents,supplier_credit_net_cents,'
          'supplier_credit_tax_cents,supplier_credit_total_cents,variance_cents '
          'FROM consignment_ownership_conversion_economics '
          'WHERE conversion_id=?',
          variables: [Variable.withInt(conversionId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError('consignment.conversion_economics_missing');
    }
    return ConsignmentOwnershipConversionEconomics(
      conversionId: row.read<int>('conversion_id'),
      inventoryValueCents: row.read<int>('inventory_value_cents'),
      supplierCreditNetCents: row.read<int>('supplier_credit_net_cents'),
      supplierCreditTaxCents: row.read<int>('supplier_credit_tax_cents'),
      supplierCreditTotalCents: row.read<int>('supplier_credit_total_cents'),
      varianceCents: row.read<int>('variance_cents'),
    );
  }
}
