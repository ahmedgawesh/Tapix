import '../app_database.dart';

Future<void> removeSaleSourceSelectionGuards(AppDatabase db) async {
  await db.customStatement(
    'DROP TRIGGER IF EXISTS sale_source_selection_insert_guard',
  );
  await db.customStatement(
    'DROP TRIGGER IF EXISTS sale_source_selection_update_guard',
  );
}

Future<void> installSaleSourceSelectionGuards(AppDatabase db) async {
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS idx_sale_items_consignment_layer '
    'ON sale_items(consignment_layer_id) '
    'WHERE consignment_layer_id IS NOT NULL',
  );
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS sale_source_selection_insert_guard
    BEFORE INSERT ON sale_items
    WHEN (NEW.supplier_identity_id IS NOT NULL
            AND NEW.consignment_layer_id IS NOT NULL)
      OR (NEW.consignment_layer_id IS NOT NULL AND NOT EXISTS(
        SELECT 1
        FROM consignment_inventory_layers l
        JOIN sales s ON s.id=NEW.sale_id
        JOIN products p ON p.id=NEW.product_id
        WHERE l.id=NEW.consignment_layer_id
          AND l.warehouse_id=s.warehouse_id
          AND l.product_id=NEW.product_id
          AND (l.variant_id=NEW.variant_id
            OR (NEW.variant_id IS NULL AND p.has_variants=0))
          AND l.status='open'
          AND l.remaining_quantity>=NEW.quantity
      ))
    BEGIN
      SELECT RAISE(ABORT,'stock_sources.source_mismatch');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS sale_source_selection_update_guard
    BEFORE UPDATE OF
      sale_id,product_id,variant_id,quantity,
      supplier_identity_id,consignment_layer_id
    ON sale_items
    WHEN (NEW.supplier_identity_id IS NOT NULL
            AND NEW.consignment_layer_id IS NOT NULL)
      OR (NEW.consignment_layer_id IS NOT NULL AND NOT EXISTS(
        SELECT 1
        FROM consignment_inventory_layers l
        JOIN sales s ON s.id=NEW.sale_id
        JOIN products p ON p.id=NEW.product_id
        WHERE l.id=NEW.consignment_layer_id
          AND l.warehouse_id=s.warehouse_id
          AND l.product_id=NEW.product_id
          AND (l.variant_id=NEW.variant_id
            OR (NEW.variant_id IS NULL AND p.has_variants=0))
          AND l.status='open'
          AND l.remaining_quantity>=NEW.quantity
      ))
      OR (EXISTS(
        SELECT 1 FROM sales s
        WHERE s.id IN (OLD.sale_id,NEW.sale_id)
          AND s.status NOT IN ('draft','pending')
      ) AND (
        NEW.sale_id IS NOT OLD.sale_id
        OR NEW.product_id IS NOT OLD.product_id
        OR NEW.variant_id IS NOT OLD.variant_id
        OR NEW.quantity IS NOT OLD.quantity
        OR NEW.supplier_identity_id IS NOT OLD.supplier_identity_id
        OR NEW.consignment_layer_id IS NOT OLD.consignment_layer_id
      ))
    BEGIN
      SELECT RAISE(ABORT,'stock_sources.source_mismatch');
    END
  ''');
}
