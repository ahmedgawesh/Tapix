import '../app_database.dart';

Future<void> removeBusinessWarehouseStockTriggers(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' "
        "AND name GLOB 'business_stock_*'",
      )
      .get();
  for (final row in rows) {
    final name = row.read<String>('name').replaceAll('"', '""');
    await db.customStatement('DROP TRIGGER "$name"');
  }
}

/// Atomic compatibility bridge during the transition to location-aware posting.
/// Legacy writers and warehouse writers share the same committed primary
/// balance. Secondary warehouses are storage only: no posting API enables them.
Future<void> installBusinessWarehouseStock(AppDatabase db) async {
  await db.transaction(() async {
    final columns = await db
        .customSelect('PRAGMA table_info(product_variants)')
        .get();
    if (columns.any(
      (row) =>
          (row.read<String>('name') == 'sku' ||
              row.read<String>('name') == 'barcode') &&
          row.read<int>('notnull') == 1,
    )) {
      throw StateError(
        'Repair legacy variant nullability before warehouse migration.',
      );
    }
    final contexts = await db.select(db.businessContexts).get();
    if (contexts.length != 1 || contexts.single.id != 1) {
      throw StateError('Warehouse stock requires one business context.');
    }
    final scope = await db.customSelect('''
      SELECT c.id FROM business_contexts c
      JOIN business_organizations o ON o.id = c.organization_id
      JOIN business_branches b ON b.id = c.branch_id AND b.organization_id = o.id
      JOIN business_warehouses w ON w.id = c.warehouse_id
        AND w.branch_id = b.id AND w.organization_id = o.id
      WHERE c.id = 1
    ''').get();
    if (scope.length != 1) {
      throw StateError('Inconsistent warehouse ownership; migration refused.');
    }
    await removeBusinessWarehouseStockTriggers(db);
    await db.customStatement('''
      INSERT INTO business_warehouse_stocks
        (warehouse_id, variant_id, quantity, unit_cost_cents, updated_at)
      SELECT c.warehouse_id, v.id, v.stock_quantity, v.cost_cents, v.updated_at
      FROM product_variants v CROSS JOIN business_contexts c
      WHERE c.id = 1 AND NOT EXISTS (
        SELECT 1 FROM business_warehouse_stocks s
        WHERE s.warehouse_id = c.warehouse_id AND s.variant_id = v.id)
    ''');
    final mismatches = await db.customSelect('''
      SELECT v.id FROM product_variants v
      JOIN business_contexts c ON c.id = 1
      JOIN business_warehouse_stocks s
        ON s.warehouse_id = c.warehouse_id AND s.variant_id = v.id
      WHERE s.quantity != v.stock_quantity OR s.unit_cost_cents != v.cost_cents
      LIMIT 1
    ''').get();
    if (mismatches.isNotEmpty) {
      throw StateError(
        'Conflicting warehouse stock; automatic overwrite refused.',
      );
    }
    final statements = <String>[
      '''CREATE INDEX IF NOT EXISTS business_stock_by_variant
         ON business_warehouse_stocks(variant_id)''',
      '''CREATE TRIGGER business_stock_scope BEFORE INSERT ON business_warehouse_stocks
         WHEN NOT EXISTS (
           SELECT 1 FROM business_warehouses w JOIN business_contexts c
             ON c.organization_id = w.organization_id AND c.branch_id = w.branch_id
           WHERE c.id = 1 AND w.id = NEW.warehouse_id)
         BEGIN SELECT RAISE(ABORT, 'Warehouse outside local branch'); END''',
      '''CREATE TRIGGER business_stock_no_replace BEFORE INSERT ON business_warehouse_stocks
         WHEN EXISTS (SELECT 1 FROM business_warehouse_stocks
           WHERE warehouse_id = NEW.warehouse_id AND variant_id = NEW.variant_id)
         BEGIN SELECT RAISE(ABORT, 'Update warehouse stock instead of replacing it'); END''',
      '''CREATE TRIGGER business_stock_identity BEFORE UPDATE ON business_warehouse_stocks
         WHEN NEW.warehouse_id != OLD.warehouse_id OR NEW.variant_id != OLD.variant_id
         BEGIN SELECT RAISE(ABORT, 'Warehouse stock identity is immutable'); END''',
      '''CREATE TRIGGER business_stock_retain BEFORE DELETE ON business_warehouse_stocks
         WHEN EXISTS (SELECT 1 FROM product_variants WHERE id = OLD.variant_id)
           AND (OLD.quantity != 0 OR EXISTS (SELECT 1 FROM business_contexts
             WHERE warehouse_id = OLD.warehouse_id))
         BEGIN SELECT RAISE(ABORT, 'Warehouse balance is required'); END''',
      '''CREATE TRIGGER business_stock_variant_retain BEFORE DELETE ON product_variants
         WHEN EXISTS (SELECT 1 FROM business_warehouse_stocks s
           WHERE s.variant_id = OLD.id AND s.quantity != 0
             AND s.warehouse_id != (SELECT warehouse_id FROM business_contexts WHERE id = 1))
         BEGIN SELECT RAISE(ABORT, 'Variant has stock in another warehouse'); END''',
      // REPLACE's implicit delete can skip delete triggers when recursive
      // triggers are disabled. Guard insertion too, before cascades can run.
      '''CREATE TRIGGER business_stock_variant_replace BEFORE INSERT ON product_variants
         WHEN EXISTS (SELECT 1 FROM product_variants v
           JOIN business_warehouse_stocks s ON s.variant_id = v.id
           WHERE (v.id = NEW.id OR v.sku = NEW.sku OR v.barcode = NEW.barcode)
             AND s.quantity != 0
             AND s.warehouse_id != (SELECT warehouse_id FROM business_contexts WHERE id = 1))
         BEGIN SELECT RAISE(ABORT, 'Cannot replace variant with remote warehouse stock'); END''',
      '''CREATE TRIGGER business_stock_variant_identity BEFORE UPDATE OF id, product_id ON product_variants
         WHEN NEW.id != OLD.id OR NEW.product_id != OLD.product_id
         BEGIN SELECT RAISE(ABORT, 'Stock variant identity is immutable'); END''',
      '''CREATE TRIGGER business_stock_variant_insert AFTER INSERT ON product_variants
         BEGIN
           SELECT CASE WHEN (SELECT COUNT(*) FROM business_contexts WHERE id = 1) != 1
             THEN RAISE(ABORT, 'Missing stock context') END;
           INSERT INTO business_warehouse_stocks
             (warehouse_id, variant_id, quantity, unit_cost_cents, updated_at)
           SELECT warehouse_id, NEW.id, NEW.stock_quantity, NEW.cost_cents, NEW.updated_at
           FROM business_contexts WHERE id = 1;
         END''',
      '''CREATE TRIGGER business_stock_variant_update AFTER UPDATE OF stock_quantity, cost_cents ON product_variants
         BEGIN
           SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM business_warehouse_stocks s
             JOIN business_contexts c ON c.warehouse_id = s.warehouse_id
             WHERE c.id = 1 AND s.variant_id = NEW.id)
             THEN RAISE(ABORT, 'Missing primary warehouse balance') END;
           UPDATE business_warehouse_stocks
           SET quantity = NEW.stock_quantity, unit_cost_cents = NEW.cost_cents,
               updated_at = NEW.updated_at
           WHERE variant_id = NEW.id
             AND warehouse_id = (SELECT warehouse_id FROM business_contexts WHERE id = 1)
             AND (quantity != NEW.stock_quantity OR unit_cost_cents != NEW.cost_cents);
         END''',
      '''CREATE TRIGGER business_stock_primary_update AFTER UPDATE OF quantity, unit_cost_cents ON business_warehouse_stocks
         WHEN NEW.warehouse_id = (SELECT warehouse_id FROM business_contexts WHERE id = 1)
         BEGIN
           UPDATE product_variants SET stock_quantity = NEW.quantity,
             cost_cents = NEW.unit_cost_cents, updated_at = NEW.updated_at
           WHERE id = NEW.variant_id
             AND (stock_quantity != NEW.quantity OR cost_cents != NEW.unit_cost_cents);
         END''',
      // Context guards allow an empty installation to be repaired explicitly.
      '''CREATE TRIGGER business_stock_context_update BEFORE UPDATE ON business_contexts
         WHEN EXISTS (SELECT 1 FROM business_warehouse_stocks)
           AND (NEW.warehouse_id != OLD.warehouse_id OR NEW.branch_id != OLD.branch_id
             OR NEW.organization_id != OLD.organization_id OR NEW.database_id != OLD.database_id)
         BEGIN SELECT RAISE(ABORT, 'Stock context is immutable'); END''',
      '''CREATE TRIGGER business_stock_context_delete BEFORE DELETE ON business_contexts
         WHEN EXISTS (SELECT 1 FROM business_warehouse_stocks)
         BEGIN SELECT RAISE(ABORT, 'Stock context is required'); END''',
      '''CREATE TRIGGER business_stock_context_replace BEFORE INSERT ON business_contexts
         WHEN EXISTS (SELECT 1 FROM business_contexts WHERE id = NEW.id)
           AND EXISTS (SELECT 1 FROM business_warehouse_stocks)
         BEGIN SELECT RAISE(ABORT, 'Stock context cannot be replaced'); END''',
      '''CREATE TRIGGER business_stock_warehouse_identity BEFORE UPDATE ON business_warehouses
         WHEN EXISTS (SELECT 1 FROM business_warehouse_stocks WHERE warehouse_id = OLD.id)
           AND (NEW.id != OLD.id OR NEW.branch_id != OLD.branch_id OR NEW.organization_id != OLD.organization_id)
         BEGIN SELECT RAISE(ABORT, 'Warehouse ownership is immutable'); END''',
    ];
    for (final statement in statements) {
      await db.customStatement(statement);
    }
  });
}
