import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

import '../../generated_migrations/consignment_schema/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test(
    '10106 to 10109 preserves sales and adjustment returns as unverified',
    () async {
      final schema = await verifier.schemaAt(10106);
      addTearDown(schema.close);
      const now = '2026-09-24T00:00:00.000Z';
      schema.rawDatabase.execute('''
        INSERT INTO currencies(
          id,code,name,symbol,exchange_rate,is_base,is_active,created_at,updated_at
        ) VALUES(1,'USD','US Dollar','USD',100,1,1,'$now','$now')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO products(
          id,name,cost_cents,price_cents,track_inventory,measurement_type,
          stock_quantity,min_quantity,has_variants,is_taxable,
          purchase_tax_rate_bps,sales_tax_rate_bps,is_active,costing_method,
          inventory_tracking_type,created_at,updated_at
        ) VALUES(1,'Legacy item',100,200,1,'piece',1,0,0,0,0,0,1,
          'wac','standard','$now','$now')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO product_variants(
          id,product_id,cost_cents,price_cents,price_adjustment_cents,
          stock_quantity,is_active,created_at,updated_at
        ) VALUES(1,1,100,200,0,1,1,'$now','$now')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO sales(
          id,invoice_number,subtotal_cents,tax_cents,discount_cents,total_cents,
          paid_amount_cents,currency_id,payment_method,status,sale_date,
          created_at,updated_at
        ) VALUES(1,'S-LEGACY',200,0,0,200,200,1,'cash','completed',
          '$now','$now','$now')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO sale_items(
          id,sale_id,product_id,variant_id,quantity,quantity_scale,
          measurement_type,unit_price_cents,subtotal_cents,discount_cents,
          tax_cents,total_cents,qty_returned_linked,qty_returned_adjustment,
          created_at
        ) VALUES(1,1,1,1,1,1,'piece',200,200,0,0,200,0,0,'$now')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO sale_return_adjustments(
          id,return_number,currency_id,subtotal_cents,discount_cents,tax_cents,
          total_cents,status,refund_method,approval_status,approval_required,
          return_date,created_at,updated_at
        ) VALUES(1,'SAR-LEGACY',1,200,0,0,200,'posted','cash','not_required',0,
          '$now','$now','$now')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO sale_return_adjustment_items(
          id,return_id,product_id,variant_id,quantity,quantity_scale,
          measurement_type,unit_price_cents,unit_cost_cents,discount_cents,
          tax_cents,total_cents,disposition_type,created_at
        ) VALUES(1,1,1,1,1,1,'piece',200,100,0,0,200,'restock','$now')
      ''');

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10115);
      addTearDown(db.close);

      final saleLine = await db.select(db.saleItems).getSingle();
      final returnLine = await db
          .select(db.saleReturnAdjustmentItems)
          .getSingle();
      expect(saleLine.supplierIdentityId, isNull);
      expect(returnLine.supplierIdentityId, isNull);
      expect(saleLine.quantity, 1);
      expect(returnLine.quantity, 1);

      final guards = await db.customSelect('''
        SELECT name FROM sqlite_master
        WHERE type='trigger' AND name LIKE '%supplier_identity_%'
      ''').get();
      expect(
        guards.map((row) => row.read<String>('name')),
        containsAll(<String>{
          'sale_supplier_identity_insert',
          'sale_supplier_identity_update',
          'sale_adj_supplier_identity_insert',
          'sale_adj_supplier_identity_update',
        }),
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
}
