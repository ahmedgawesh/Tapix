import 'package:drift/drift.dart';
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
    '10118 upgrade marks one branch sales location and keeps extra warehouses separate',
    () async {
      final schema = await verifier.schemaAt(10118);
      addTearDown(schema.close);
      const organization = '11111111-1111-4111-8111-111111111111';
      const mainBranch = '22222222-2222-4222-8222-222222222222';
      const cairoBranch = '33333333-3333-4333-8333-333333333333';
      const mainLocation = '44444444-4444-4444-8444-444444444444';
      const mainReserve = '55555555-5555-4555-8555-555555555555';
      const cairoLocation = '66666666-6666-4666-8666-666666666666';
      const cairoReserve = '77777777-7777-4777-8777-777777777777';
      const database = '88888888-8888-4888-8888-888888888888';

      schema.rawDatabase.execute('''
        INSERT INTO business_organizations(id,name)
        VALUES('$organization','Migration organization')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO business_branches(id,organization_id,code,name,created_at)
        VALUES
          ('$mainBranch','$organization','MAIN','Main branch',
            '2026-09-01T00:00:00.000Z'),
          ('$cairoBranch','$organization','CAIRO','Cairo branch',
            '2026-09-02T00:00:00.000Z')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO business_warehouses(
          id,organization_id,branch_id,code,name,created_at
        ) VALUES
          ('$mainReserve','$organization','$mainBranch','MAIN-RESERVE',
            'Main reserve','2026-09-01T00:00:00.000Z'),
          ('$mainLocation','$organization','$mainBranch','MAIN',
            'Main sales floor','2026-09-02T00:00:00.000Z'),
          ('$cairoLocation','$organization','$cairoBranch','CAIRO',
            'Cairo sales floor','2026-09-03T00:00:00.000Z'),
          ('$cairoReserve','$organization','$cairoBranch','CAIRO-RESERVE',
            'Cairo reserve','2026-09-04T00:00:00.000Z')
      ''');
      schema.rawDatabase.execute('''
        INSERT INTO business_contexts(
          id,organization_id,branch_id,warehouse_id,database_id
        ) VALUES(
          1,'$organization','$mainBranch','$mainLocation','$database'
        )
      ''');

      final db = AppDatabase.connect(schema.newConnection());
      await verifier.migrateAndValidate(db, 10119);
      addTearDown(db.close);

      final rows = await db.customSelect(
        '''SELECT id,location_kind FROM business_warehouses
            ORDER BY id''',
      ).get();
      final kinds = {
        for (final row in rows)
          row.read<String>('id'): row.read<String>('location_kind'),
      };
      expect(kinds[mainLocation], 'branch_store');
      expect(kinds[mainReserve], 'warehouse');
      expect(kinds[cairoLocation], 'branch_store');
      expect(kinds[cairoReserve], 'warehouse');

      await expectLater(
        db
            .into(db.businessWarehouses)
            .insert(
              BusinessWarehousesCompanion.insert(
                id: '99999999-9999-4999-8999-999999999999',
                organizationId: organization,
                branchId: cairoBranch,
                code: 'CAIRO-SECOND-STORE',
                locationKind: const Value('branch_store'),
              ),
            ),
        throwsA(anything),
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
}
