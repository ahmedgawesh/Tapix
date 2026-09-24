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
    '10109 to 10110 preserves legacy return and adds source audit',
    () async {
      final schema = await verifier.schemaAt(10109);
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
      ) VALUES(1,'Legacy return item',100,200,1,'piece',1,0,0,0,0,0,1,
        'wac','standard','$now','$now')
    ''');
      schema.rawDatabase.execute('''
      INSERT INTO product_variants(
        id,product_id,cost_cents,price_cents,price_adjustment_cents,
        stock_quantity,is_active,created_at,updated_at
      ) VALUES(1,1,100,200,0,1,1,'$now','$now')
    ''');
      schema.rawDatabase.execute('''
      INSERT INTO sale_return_adjustments(
        id,return_number,currency_id,subtotal_cents,discount_cents,tax_cents,
        total_cents,status,refund_method,approval_status,approval_required,
        return_date,created_at,updated_at
      ) VALUES(1,'SRS-LEGACY',1,200,0,0,200,'draft','cash','not_required',0,
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

      final item = await db.select(db.saleReturnAdjustmentItems).getSingle();
      expect(item.sourceResolution, isNull);
      expect(item.sourceResolutionReason, isNull);
      expect(item.sourceResolvedBy, isNull);
      expect(item.sourceResolvedAt, isNull);
      expect(item.quantity, 1);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
}
