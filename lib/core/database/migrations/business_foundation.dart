import 'package:uuid/uuid.dart';

import '../app_database.dart';

/// Bootstrap the single-branch identity without rewriting a customer's stock,
/// cost, money, historical document identifiers, or subscription settings.
Future<void> initializeBusinessFoundation(AppDatabase db) async {
  await db.transaction(() async {
    // Use projections limited to the original foundation columns. During an
    // upgrade Drift's generated table shape is the newest one, while the
    // physical warehouse table can still be from 10118 or earlier and lacks
    // location_kind. Selecting/inserting through the typed current table at
    // that point makes an otherwise valid legacy database impossible to open.
    final contexts = await db
        .customSelect('SELECT id FROM business_contexts ORDER BY id')
        .get();
    if (contexts.isNotEmpty) {
      if (contexts.length != 1 || contexts.single.read<int>('id') != 1) {
        throw StateError(
          'Invalid business context; refusing to reassign data.',
        );
      }
      return;
    }
    Future<bool> hasRows(String table) async =>
        (await db.customSelect('SELECT 1 FROM $table LIMIT 1').get())
            .isNotEmpty;
    if (await hasRows('business_organizations') ||
        await hasRows('business_branches') ||
        await hasRows('business_warehouses')) {
      throw StateError(
        'Incomplete business identity; refusing to create a second owner.',
      );
    }
    const uuid = Uuid();
    final organizationId = uuid.v4();
    final branchId = uuid.v4();
    final warehouseId = uuid.v4();
    await db.customStatement(
      'INSERT INTO business_organizations(id) VALUES(?)',
      [organizationId],
    );
    await db.customStatement(
      'INSERT INTO business_branches(id,organization_id,code) '
      'VALUES(?,?,?)',
      [branchId, organizationId, 'MAIN'],
    );
    final warehouseColumns = await db
        .customSelect('PRAGMA table_info(business_warehouses)')
        .get();
    final hasLocationKind = warehouseColumns.any(
      (row) => row.read<String>('name') == 'location_kind',
    );
    if (hasLocationKind) {
      await db.customStatement(
        'INSERT INTO business_warehouses('
        'id,organization_id,branch_id,code,location_kind) '
        'VALUES(?,?,?,?,?)',
        [warehouseId, organizationId, branchId, 'MAIN', 'branch_store'],
      );
    } else {
      await db.customStatement(
        'INSERT INTO business_warehouses('
        'id,organization_id,branch_id,code) VALUES(?,?,?,?)',
        [warehouseId, organizationId, branchId, 'MAIN'],
      );
    }
    await db.customStatement(
      'INSERT INTO business_contexts('
      'id,organization_id,branch_id,warehouse_id,database_id) '
      'VALUES(?,?,?,?,?)',
      [1, organizationId, branchId, warehouseId, uuid.v4()],
    );
  });
}

/// Ensures every branch has exactly one semantic sales-floor stock location.
/// Existing branches are backfilled without moving or copying any quantity.
Future<void> ensureBusinessWarehouseLocationKinds(AppDatabase db) async {
  await db.customStatement('''
    UPDATE business_warehouses
    SET location_kind = 'branch_store'
    WHERE id = (
      SELECT candidate.id
      FROM business_warehouses candidate
      WHERE candidate.organization_id = business_warehouses.organization_id
        AND candidate.branch_id = business_warehouses.branch_id
      ORDER BY
        CASE WHEN candidate.id = (
          SELECT warehouse_id FROM business_contexts WHERE id = 1
        ) THEN 0 ELSE 1 END,
        candidate.created_at,
        candidate.code
      LIMIT 1
    )
    AND NOT EXISTS (
      SELECT 1
      FROM business_warehouses existing
      WHERE existing.organization_id = business_warehouses.organization_id
        AND existing.branch_id = business_warehouses.branch_id
        AND existing.location_kind = 'branch_store'
    )
  ''');
}
