import '../app_database.dart';

/// Quantity provenance is deliberately independent of inventory valuation.
Future<void> installInventoryOrigins(AppDatabase db) async {
  await db.customStatement(
    '''CREATE TABLE IF NOT EXISTS inventory_origin_states (
    warehouse_id TEXT NOT NULL REFERENCES business_warehouses(id),
    variant_id INTEGER NOT NULL REFERENCES product_variants(id),
    quantity INTEGER NOT NULL, measurement_type TEXT NOT NULL,
    dirty INTEGER NOT NULL DEFAULT 0 CHECK(dirty IN (0,1)),
    layers TEXT NOT NULL,
    PRIMARY KEY(warehouse_id,variant_id))''',
  );
  await db.customStatement(
    '''CREATE TABLE IF NOT EXISTS inventory_origin_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    warehouse_id TEXT NOT NULL REFERENCES business_warehouses(id),
    variant_id INTEGER NOT NULL REFERENCES product_variants(id),
    product_id INTEGER NOT NULL REFERENCES products(id),
    measurement_type TEXT NOT NULL,
    event_key TEXT NOT NULL,
    claim_key TEXT,
    delta INTEGER NOT NULL CHECK(delta != 0),
    allocations TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(warehouse_id,event_key))''',
  );
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS inventory_origin_claim ON inventory_origin_events(warehouse_id,variant_id,claim_key)',
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS inventory_origin_stock_changed
    AFTER UPDATE OF quantity ON business_warehouse_stocks WHEN OLD.quantity != NEW.quantity
    BEGIN UPDATE inventory_origin_states SET dirty=1
      WHERE warehouse_id=NEW.warehouse_id AND variant_id=NEW.variant_id; END''',
  );
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS inventory_origin_stock_deleted
    AFTER DELETE ON business_warehouse_stocks
    BEGIN UPDATE inventory_origin_states SET dirty=1
      WHERE warehouse_id=OLD.warehouse_id AND variant_id=OLD.variant_id; END''',
  );
  for (final action in ['UPDATE', 'DELETE']) {
    await db.customStatement(
      '''CREATE TRIGGER IF NOT EXISTS inventory_origin_events_no_${action.toLowerCase()}
      BEFORE $action ON inventory_origin_events
      BEGIN SELECT RAISE(ABORT,'Inventory origin history is immutable'); END''',
    );
  }
  await db.customStatement(
    '''CREATE TRIGGER IF NOT EXISTS inventory_origin_events_no_replace
    BEFORE INSERT ON inventory_origin_events WHEN EXISTS(SELECT 1 FROM inventory_origin_events
      WHERE id=NEW.id OR (warehouse_id=NEW.warehouse_id AND event_key=NEW.event_key))
    BEGIN SELECT RAISE(ABORT,'Inventory origin event already exists'); END''',
  );
}
