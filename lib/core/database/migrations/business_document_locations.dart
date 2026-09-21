import '../app_database.dart';

/// Closed list, also constrained in the table schema. Never interpolate input
/// supplied by a client into trigger SQL or table names.
const locatedBusinessTables = [
  'sales',
  'purchases',
  'sale_returns',
  'purchase_returns',
  'sale_return_adjustments',
  'purchase_return_adjustments',
  'inventory_adjustments',
  'product_batches',
  'journal_entries',
];

// Resolve accounting side effects through their immutable economic source.
// The aliases below are internal constants, never client SQL identifiers.
String _journalOrigin(String alias) =>
    """(
  SELECT l.organization_id, l.branch_id, l.warehouse_id
  FROM business_document_locations l
  WHERE (l.source_table = $alias.source_table AND l.source_id = $alias.source_id
    AND $alias.source_table IN ('inventory_adjustments', 'purchases', 'purchase_returns',
      'sales', 'sale_returns', 'sale_return_adjustments', 'purchase_return_adjustments'))
    OR ($alias.source_table = 'sale_payments' AND l.source_table = 'sales'
      AND l.source_id = (SELECT sale_id FROM sale_payments WHERE id = $alias.source_id))
    OR ($alias.source_table = 'purchase_payments' AND l.source_table = 'purchases'
      AND l.source_id = (SELECT purchase_id FROM purchase_payments WHERE id = $alias.source_id))
    OR ($alias.source_table = 'customer_reward_redemptions' AND l.source_table = 'sales'
      AND l.source_id = (SELECT sale_id FROM customer_reward_redemptions WHERE id = $alias.source_id))
    OR ($alias.source_table = 'cheque_instruments' AND EXISTS (
      SELECT 1 FROM cheque_instruments q WHERE q.id = $alias.source_id
        AND q.source_table = l.source_table AND q.source_id = l.source_id))
    OR ($alias.source_table = 'commissions' AND EXISTS (
      SELECT 1 FROM commissions event WHERE event.id = $alias.source_id
        AND l.source_table = CASE
          WHEN event.sale_return_id IS NOT NULL THEN 'sale_returns'
          WHEN event.sale_return_adjustment_id IS NOT NULL THEN 'sale_return_adjustments'
          ELSE 'sales' END
        AND l.source_id = COALESCE(event.sale_return_id, event.sale_return_adjustment_id, event.sale_id)))
)""";

// SQLite built-ins work on native and Web without registering a connection-
// specific function. RFC 4122 version/variant bits are set explicitly.
const _uuidSql =
    "(lower(hex(randomblob(4))) || '-' || "
    "lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || "
    "'-' || substr('89ab', 1 + abs(random() % 4), 1) || "
    "substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6))))";

/// Called before older migrations rebuild source tables. Reinstalled after all
/// migrations so legacy repairs retain their existing SQL behavior.
Future<void> removeBusinessDocumentLocationTriggers(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' "
        "AND name GLOB 'business_location_*'",
      )
      .get();
  for (final row in rows) {
    final escaped = row.read<String>('name').replaceAll('"', '""');
    await db.customStatement('DROP TRIGGER "$escaped"');
  }
}

/// Backfills metadata only, then captures every write path (including LAN and
/// direct DAO inserts) in the same SQLite statement as its source document.
/// Public entry points remain primary-only until authorization and licensing
/// are connected; internal scoped documents retain their accounting location.
Future<void> installBusinessDocumentLocations(AppDatabase db) async {
  await db.transaction(() async {
    final context = await db.select(db.businessContexts).get();
    if (context.length != 1 || context.single.id != 1) {
      throw StateError('Cannot assign documents without one business context.');
    }
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS business_locations_by_warehouse
      ON business_document_locations(warehouse_id, source_table, source_id)
    ''');
    // Rebuild triggers during migration only, not on each ordinary connection.
    await removeBusinessDocumentLocationTriggers(db);
    for (final table in locatedBusinessTables) {
      final batch = table == 'product_batches';
      final routed =
          batch ||
          table == 'inventory_adjustments' ||
          table == 'purchases' ||
          table == 'sales' ||
          table == 'sale_return_adjustments' ||
          table == 'purchase_return_adjustments';
      final journal = table == 'journal_entries';
      final destination = routed
          ? 'COALESCE(NEW.warehouse_id, warehouse_id)'
          : journal
          ? "COALESCE((SELECT l.warehouse_id FROM business_document_locations l WHERE l.source_table = 'journal_entries' AND l.source_id = NEW.reversed_entry_id), (SELECT l.warehouse_id FROM ${_journalOrigin('NEW')} l), warehouse_id)"
          : table == 'sale_returns'
          ? "(SELECT l.warehouse_id FROM business_document_locations l WHERE l.source_table = 'sales' AND l.source_id = NEW.sale_id)"
          : table == 'purchase_returns'
          ? "(SELECT l.warehouse_id FROM business_document_locations l WHERE l.source_table = 'purchases' AND l.source_id = NEW.purchase_id)"
          : 'warehouse_id';
      final routeGuard = routed
          ? """
        SELECT CASE WHEN NEW.warehouse_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM business_warehouses w JOIN business_contexts c
            ON c.organization_id = w.organization_id AND c.branch_id = w.branch_id
          JOIN business_branches b ON b.id = w.branch_id AND b.organization_id = w.organization_id
          WHERE c.id = 1 AND w.id = NEW.warehouse_id AND w.is_active = 1 AND b.is_active = 1)
          THEN RAISE(ABORT, 'Invalid inventory warehouse') END;
      """
          : '';
      final journalGuard = journal
          ? """
        SELECT CASE WHEN NEW.source_table = 'inventory_adjustments' AND NOT EXISTS (
          SELECT 1 FROM inventory_adjustments a JOIN business_document_locations l
            ON l.source_table = 'inventory_adjustments' AND l.source_id = a.id
          JOIN business_contexts c ON c.organization_id = l.organization_id AND c.branch_id = l.branch_id
          WHERE c.id = 1 AND a.id = NEW.source_id )
          THEN RAISE(ABORT, 'Inventory journal source or currency mismatch') END;
      """
          : '';
      final batchGuard = batch
          ? """
          SELECT CASE WHEN NEW.warehouse_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM business_warehouses w JOIN business_contexts c
              ON c.organization_id = w.organization_id AND c.branch_id = w.branch_id
            JOIN business_branches b ON b.id = w.branch_id AND b.organization_id = w.organization_id
            WHERE c.id = 1 AND w.id = NEW.warehouse_id AND w.is_active = 1 AND b.is_active = 1)
            THEN RAISE(ABORT, 'Invalid batch warehouse') END;
          SELECT CASE WHEN NEW.purchase_item_id IS NOT NULL AND NEW.warehouse_id IS NOT NULL
            AND NEW.warehouse_id != (SELECT warehouse_id FROM business_contexts WHERE id = 1)
            AND NOT EXISTS (
              SELECT 1 FROM purchase_items pi JOIN business_document_locations l
                ON l.source_table = 'purchases' AND l.source_id = pi.purchase_id
              JOIN business_contexts c ON c.id = 1
              WHERE pi.id = NEW.purchase_item_id AND pi.product_id = NEW.product_id
                AND (pi.variant_id IS NULL OR pi.variant_id = NEW.variant_id)
                AND l.organization_id = c.organization_id AND l.branch_id = c.branch_id
                AND l.warehouse_id = NEW.warehouse_id)
            THEN RAISE(ABORT, 'Purchase source and batch warehouse differ') END;

      """
          : '';

      await db.customStatement('''
        INSERT INTO business_document_locations
          (document_id, source_table, source_id, organization_id, branch_id,
           warehouse_id, origin_database_id)
        SELECT $_uuidSql, '$table', s.id, c.organization_id, c.branch_id,
               c.warehouse_id, c.database_id
        FROM $table s CROSS JOIN business_contexts c
        WHERE c.id = 1 AND NOT EXISTS (
          SELECT 1 FROM business_document_locations l
          WHERE l.source_table = '$table' AND l.source_id = s.id)
      ''');
      await db.customStatement('''
        CREATE TRIGGER business_location_${table}_insert AFTER INSERT ON $table
        BEGIN
          $routeGuard
          $batchGuard
          $journalGuard
          SELECT CASE WHEN (SELECT COUNT(*) FROM business_contexts WHERE id = 1) != 1
            THEN RAISE(ABORT, 'Missing business location') END;
          INSERT INTO business_document_locations
            (document_id, source_table, source_id, organization_id, branch_id,
             warehouse_id, origin_database_id)
          SELECT $_uuidSql, '$table', NEW.id, organization_id, branch_id,
                 $destination, database_id FROM business_contexts WHERE id = 1;
        END
      ''');
      await db.customStatement('''
        CREATE TRIGGER business_location_${table}_delete AFTER DELETE ON $table
        BEGIN
          DELETE FROM business_document_locations
          WHERE source_table = '$table' AND source_id = OLD.id;
        END
      ''');
      await db.customStatement('''
        CREATE TRIGGER business_location_${table}_id BEFORE UPDATE OF id ON $table
        WHEN NEW.id != OLD.id
        BEGIN SELECT RAISE(ABORT, 'Document local identity is immutable'); END
      ''');
      // Polymorphic references have no SQLite FK; enforce existence and reject
      // direct removal while the document still exists. Normal draft deletion
      // runs its AFTER DELETE trigger once the source row is gone.
      await db.customStatement('''
        CREATE TRIGGER business_location_${table}_reference
        BEFORE INSERT ON business_document_locations
        WHEN NEW.source_table = '$table'
          AND NOT EXISTS (SELECT 1 FROM $table WHERE id = NEW.source_id)
        BEGIN SELECT RAISE(ABORT, 'Unknown source document'); END
      ''');
      await db.customStatement('''
        CREATE TRIGGER business_location_${table}_retain
        BEFORE DELETE ON business_document_locations
        WHEN OLD.source_table = '$table'
          AND EXISTS (SELECT 1 FROM $table WHERE id = OLD.source_id)
        BEGIN SELECT RAISE(ABORT, 'Document location is required'); END
      ''');
    }
    await db.customStatement('''
      CREATE TRIGGER business_location_no_replace
      BEFORE INSERT ON business_document_locations
      WHEN EXISTS (SELECT 1 FROM business_document_locations l
        WHERE l.document_id = NEW.document_id
          OR (l.source_table = NEW.source_table AND l.source_id = NEW.source_id))
      BEGIN SELECT RAISE(ABORT, 'Document identity already exists'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_immutable
      BEFORE UPDATE ON business_document_locations
      BEGIN SELECT RAISE(ABORT, 'Document location is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_primary_only
      BEFORE INSERT ON business_document_locations
      WHEN NOT EXISTS (
        SELECT 1 FROM business_contexts c WHERE c.id = 1
          AND c.organization_id = NEW.organization_id AND c.branch_id = NEW.branch_id
          AND c.database_id = NEW.origin_database_id
          AND (c.warehouse_id = NEW.warehouse_id OR (
            NEW.source_table = 'sale_return_adjustments' AND EXISTS (
              SELECT 1 FROM sale_return_adjustments p JOIN business_warehouses w ON w.id = p.warehouse_id
              WHERE p.id = NEW.source_id AND w.id = NEW.warehouse_id
                AND w.organization_id = c.organization_id AND w.branch_id = c.branch_id AND w.is_active = 1)) OR (
            NEW.source_table = 'purchase_return_adjustments' AND EXISTS (
              SELECT 1 FROM purchase_return_adjustments p JOIN business_warehouses w ON w.id = p.warehouse_id
              WHERE p.id = NEW.source_id AND w.id = NEW.warehouse_id
                AND w.organization_id = c.organization_id AND w.branch_id = c.branch_id AND w.is_active = 1)) OR (
            NEW.source_table = 'sales' AND EXISTS (
              SELECT 1 FROM sales p JOIN business_warehouses w ON w.id = p.warehouse_id
              WHERE p.id = NEW.source_id AND w.id = NEW.warehouse_id
                AND w.organization_id = c.organization_id AND w.branch_id = c.branch_id AND w.is_active = 1)) OR (
            NEW.source_table = 'sale_returns' AND EXISTS (
              SELECT 1 FROM sale_returns r JOIN business_document_locations l
                ON l.source_table = 'sales' AND l.source_id = r.sale_id
              WHERE r.id = NEW.source_id AND l.warehouse_id = NEW.warehouse_id
                AND l.organization_id = c.organization_id AND l.branch_id = c.branch_id)) OR (
            NEW.source_table = 'purchases' AND EXISTS (
              SELECT 1 FROM purchases p JOIN business_warehouses w ON w.id = p.warehouse_id
              WHERE p.id = NEW.source_id AND w.id = NEW.warehouse_id
                AND w.organization_id = c.organization_id AND w.branch_id = c.branch_id AND w.is_active = 1)) OR (
            NEW.source_table = 'purchase_returns' AND EXISTS (
              SELECT 1 FROM purchase_returns r JOIN business_document_locations l
                ON l.source_table = 'purchases' AND l.source_id = r.purchase_id
              WHERE r.id = NEW.source_id AND l.warehouse_id = NEW.warehouse_id
                AND l.organization_id = c.organization_id AND l.branch_id = c.branch_id)) OR (
            NEW.source_table = 'product_batches' AND EXISTS (
              SELECT 1 FROM product_batches pb JOIN business_warehouses w ON w.id = pb.warehouse_id
              JOIN business_branches b ON b.id = w.branch_id AND b.organization_id = w.organization_id
              WHERE pb.id = NEW.source_id AND pb.warehouse_id = NEW.warehouse_id
                AND w.organization_id = c.organization_id AND w.branch_id = c.branch_id
                AND w.is_active = 1 AND b.is_active = 1)) OR (
            NEW.source_table = 'inventory_adjustments' AND EXISTS (
              SELECT 1 FROM inventory_adjustments a JOIN business_warehouses w ON w.id = a.warehouse_id
              WHERE a.id = NEW.source_id AND a.warehouse_id = NEW.warehouse_id
                AND w.organization_id = c.organization_id AND w.branch_id = c.branch_id AND w.is_active = 1)) OR (
            NEW.source_table = 'journal_entries' AND EXISTS (
              SELECT 1 FROM journal_entries j JOIN business_document_locations l
                ON l.source_table = 'journal_entries' AND l.source_id = j.reversed_entry_id
              WHERE j.id = NEW.source_id AND l.warehouse_id = NEW.warehouse_id
                AND l.organization_id = c.organization_id AND l.branch_id = c.branch_id)) OR (
            NEW.source_table = 'journal_entries' AND EXISTS (
              SELECT 1 FROM journal_entries j WHERE j.id = NEW.source_id AND EXISTS (
                SELECT 1 FROM ${_journalOrigin('j')} l WHERE l.warehouse_id = NEW.warehouse_id
                  AND l.organization_id = c.organization_id AND l.branch_id = c.branch_id)))))
      BEGIN SELECT RAISE(ABORT, 'Only the primary warehouse is operational'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_sale_adjustment_batch_immutable
      BEFORE UPDATE OF return_batch_id ON sale_return_adjustment_items
      WHEN OLD.return_batch_id IS NOT NULL AND NEW.return_batch_id IS NOT OLD.return_batch_id
      BEGIN SELECT RAISE(ABORT, 'Adjustment return batch is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_journal_reversal_immutable
      BEFORE UPDATE OF reversed_entry_id ON journal_entries
      WHEN NEW.reversed_entry_id IS NOT OLD.reversed_entry_id
      BEGIN SELECT RAISE(ABORT, 'Journal reversal source is immutable'); END
    ''');
    for (final table in [
      'sale_return_adjustments',
      'purchase_return_adjustments',
    ]) {
      await db.customStatement('''
        CREATE TRIGGER business_location_${table}_route_immutable
        BEFORE UPDATE OF warehouse_id ON $table
        WHEN NEW.warehouse_id IS NOT OLD.warehouse_id
        BEGIN SELECT RAISE(ABORT, 'Adjustment return warehouse is immutable'); END
      ''');
    }
    await db.customStatement('''
      CREATE TRIGGER business_location_sale_route_immutable
      BEFORE UPDATE OF warehouse_id ON sales
      WHEN NEW.warehouse_id IS NOT OLD.warehouse_id
      BEGIN SELECT RAISE(ABORT, 'Sale warehouse is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_sale_return_parent_immutable
      BEFORE UPDATE OF sale_id ON sale_returns
      WHEN NEW.sale_id IS NOT OLD.sale_id
      BEGIN SELECT RAISE(ABORT, 'Sale return source is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_purchase_route_immutable
      BEFORE UPDATE OF warehouse_id ON purchases
      WHEN NEW.warehouse_id IS NOT OLD.warehouse_id
      BEGIN SELECT RAISE(ABORT, 'Purchase warehouse is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_purchase_return_parent_immutable
      BEFORE UPDATE OF purchase_id ON purchase_returns
      WHEN NEW.purchase_id IS NOT OLD.purchase_id
      BEGIN SELECT RAISE(ABORT, 'Purchase return source is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_batch_route_immutable
      BEFORE UPDATE OF warehouse_id ON product_batches
      WHEN NEW.warehouse_id IS NOT OLD.warehouse_id
      BEGIN SELECT RAISE(ABORT, 'Batch warehouse is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_adjustment_route_immutable
      BEFORE UPDATE OF warehouse_id ON inventory_adjustments
      WHEN NEW.warehouse_id IS NOT OLD.warehouse_id
      BEGIN SELECT RAISE(ABORT, 'Adjustment warehouse is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_inventory_journal_source_immutable
      BEFORE UPDATE OF source_table, source_id ON journal_entries
      WHEN (OLD.source_table IN ('inventory_adjustments', 'purchases', 'purchase_returns', 'sales', 'sale_returns', 'sale_return_adjustments', 'purchase_return_adjustments', 'sale_payments', 'purchase_payments', 'customer_reward_redemptions', 'cheque_instruments', 'commissions') OR NEW.source_table IN ('inventory_adjustments', 'purchases', 'purchase_returns', 'sales', 'sale_returns', 'sale_return_adjustments', 'purchase_return_adjustments', 'sale_payments', 'purchase_payments', 'customer_reward_redemptions', 'cheque_instruments', 'commissions'))
        AND (NEW.source_table IS NOT OLD.source_table OR NEW.source_id IS NOT OLD.source_id)
      BEGIN SELECT RAISE(ABORT, 'Inventory journal source is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_adjustment_currency_immutable
      BEFORE UPDATE OF currency_id ON inventory_adjustments
      WHEN NEW.currency_id IS NOT OLD.currency_id
      BEGIN SELECT RAISE(ABORT, 'Adjustment currency is immutable'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_adjustment_journal_link
      BEFORE UPDATE OF journal_entry_id ON inventory_adjustments
      WHEN NEW.journal_entry_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM journal_entries j JOIN business_document_locations l
          ON l.source_table = 'journal_entries' AND l.source_id = j.id
        JOIN business_document_locations a
          ON a.source_table = 'inventory_adjustments' AND a.source_id = NEW.id
        WHERE j.id = NEW.journal_entry_id
          AND j.source_table = 'inventory_adjustments' AND j.source_id = NEW.id
          AND l.warehouse_id = a.warehouse_id
          AND l.branch_id = a.branch_id AND l.organization_id = a.organization_id)
      BEGIN SELECT RAISE(ABORT, 'Adjustment journal link mismatch'); END
    ''');
    for (final event in ['INSERT', 'UPDATE']) {
      await db.customStatement('''
        CREATE TRIGGER business_location_inventory_line_${event.toLowerCase()}
        BEFORE $event ON journal_entry_lines
        WHEN EXISTS (
          SELECT 1 FROM journal_entries j JOIN inventory_adjustments a
            ON j.source_table = 'inventory_adjustments' AND j.source_id = a.id
          WHERE j.id = NEW.journal_entry_id AND a.currency_id != NEW.currency_id)
        BEGIN SELECT RAISE(ABORT, 'Inventory journal currency mismatch'); END
      ''');
    }
    await db.customStatement('''
      CREATE TRIGGER business_location_context_replace BEFORE INSERT ON business_contexts
      WHEN EXISTS (SELECT 1 FROM business_contexts c WHERE c.id = NEW.id
        AND (NEW.organization_id != c.organization_id OR NEW.branch_id != c.branch_id
          OR NEW.warehouse_id != c.warehouse_id OR NEW.database_id != c.database_id))
      BEGIN SELECT RAISE(ABORT, 'Cannot replace the owner of business documents'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_context_update BEFORE UPDATE ON business_contexts
      WHEN (NEW.organization_id != OLD.organization_id OR NEW.branch_id != OLD.branch_id
        OR NEW.warehouse_id != OLD.warehouse_id OR NEW.database_id != OLD.database_id)
      BEGIN SELECT RAISE(ABORT, 'Cannot reassign existing business documents'); END
    ''');
    await db.customStatement('''
      CREATE TRIGGER business_location_context_delete BEFORE DELETE ON business_contexts
      WHEN EXISTS (SELECT 1 FROM business_document_locations)
      BEGIN SELECT RAISE(ABORT, 'Cannot remove the owner of business documents'); END
    ''');
  });
}
