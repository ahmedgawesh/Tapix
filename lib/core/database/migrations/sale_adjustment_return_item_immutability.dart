import '../app_database.dart';

/// Prevents a posted or voided standalone sale return from being rewritten
/// through raw SQL or a repository path that bypasses the posting service.
///
/// The parent remains editable only while it is `draft` or `pending`. Checking
/// both OLD and NEW parents on update also prevents moving a sealed line into
/// an editable document (or the reverse) to evade the guard.
const saleAdjustmentReturnItemImmutabilityStatements = <String>[
  '''CREATE TRIGGER IF NOT EXISTS sale_adj_item_sealed_insert_guard
BEFORE INSERT ON sale_return_adjustment_items
WHEN EXISTS (
  SELECT 1 FROM sale_return_adjustments r
  WHERE r.id=NEW.return_id AND r.status NOT IN ('draft','pending')
)
BEGIN
  SELECT RAISE(ABORT,'sale_return_adjustment.items_immutable');
END''',
  '''CREATE TRIGGER IF NOT EXISTS sale_adj_item_sealed_update_guard
BEFORE UPDATE ON sale_return_adjustment_items
WHEN EXISTS (
  SELECT 1 FROM sale_return_adjustments r
  WHERE r.id IN (OLD.return_id,NEW.return_id)
    AND r.status NOT IN ('draft','pending')
)
BEGIN
  SELECT RAISE(ABORT,'sale_return_adjustment.items_immutable');
END''',
  '''CREATE TRIGGER IF NOT EXISTS sale_adj_item_sealed_delete_guard
BEFORE DELETE ON sale_return_adjustment_items
WHEN EXISTS (
  SELECT 1 FROM sale_return_adjustments r
  WHERE r.id=OLD.return_id AND r.status NOT IN ('draft','pending')
)
BEGIN
  SELECT RAISE(ABORT,'sale_return_adjustment.items_immutable');
END''',
];

Future<void> installSaleAdjustmentReturnItemImmutabilityGuards(
  AppDatabase db,
) async {
  for (final statement in saleAdjustmentReturnItemImmutabilityStatements) {
    await db.customStatement(statement);
  }
}

Future<void> removeSaleAdjustmentReturnItemImmutabilityGuards(
  AppDatabase db,
) async {
  await db.customStatement(
    'DROP TRIGGER IF EXISTS sale_adj_item_sealed_insert_guard',
  );
  await db.customStatement(
    'DROP TRIGGER IF EXISTS sale_adj_item_sealed_update_guard',
  );
  await db.customStatement(
    'DROP TRIGGER IF EXISTS sale_adj_item_sealed_delete_guard',
  );
}
