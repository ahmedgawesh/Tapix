import '../app_database.dart';

/// Old reversal rows remain unassigned: a sale/date match is not proof of the
/// return identity. No financial amounts or statuses are rewritten.
Future<void> installCommissionReturnSource(AppDatabase db) async {
  await db.customStatement('''CREATE INDEX IF NOT EXISTS
    commissions_by_sale_return ON commissions(sale_return_id)''');
  for (final event in ['INSERT', 'UPDATE']) {
    await db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS commission_return_source_${event.toLowerCase()}
      BEFORE $event ON commissions
      WHEN NEW.sale_return_id IS NOT NULL AND (
        NEW.sale_id IS NULL OR NEW.sale_return_adjustment_id IS NOT NULL
        OR NEW.commission_amount_cents >= 0
        OR NOT EXISTS (SELECT 1 FROM sale_returns r
          WHERE r.id = NEW.sale_return_id AND r.sale_id = NEW.sale_id
            AND r.status = 'posted')
      )
      BEGIN SELECT RAISE(ABORT, 'Invalid linked-return commission source'); END
    ''');
  }
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS commission_return_source_immutable
    BEFORE UPDATE ON commissions
    WHEN OLD.sale_return_id IS NOT NULL AND (
      NEW.sale_return_id IS NOT OLD.sale_return_id
      OR NEW.sale_id IS NOT OLD.sale_id
      OR NEW.employee_id IS NOT OLD.employee_id)
    BEGIN SELECT RAISE(ABORT, 'Linked-return commission identity is immutable'); END
  ''');
}
