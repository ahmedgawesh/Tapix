import '../app_database.dart';

Future<void> installInventoryRevaluationAudit(AppDatabase db) async {
  for (final event in ['UPDATE', 'DELETE']) {
    await db.customStatement(
      '''CREATE TRIGGER IF NOT EXISTS inventory_revaluation_layers_${event.toLowerCase()}
      BEFORE $event ON inventory_revaluation_layers
      BEGIN SELECT RAISE(ABORT, 'FIFO revaluation audit is immutable'); END''',
    );
  }
}
