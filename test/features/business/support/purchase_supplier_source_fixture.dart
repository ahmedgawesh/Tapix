import 'package:tapix/core/database/app_database.dart';

/// Test fixture only. No production data path is opened by this helper.
/// Reconstruct v10096 columns before testing an actual upgrade to v10099.
Future<void> removePurchaseSupplierSourceSchema(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='trigger' "
        "AND name LIKE 'purchase_supplier_source_%'",
      )
      .get();
  for (final row in rows) {
    await db.customStatement('DROP TRIGGER "${row.read<String>('name')}"');
  }
  await db.customStatement(
    'DROP INDEX IF EXISTS idx_purchase_items_supplier_identity',
  );
  await db.customStatement(
    'ALTER TABLE purchase_items DROP COLUMN supplier_identity_id',
  );
  await db.customStatement(
    'ALTER TABLE purchase_items DROP COLUMN supplier_identity_requested',
  );
}
