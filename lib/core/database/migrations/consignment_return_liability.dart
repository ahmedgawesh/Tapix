import 'package:drift/drift.dart';

import '../app_database.dart';

/// Adds the immutable operator decision used when supplier-owned goods are
/// returned by a customer but cannot go back to sellable stock.
///
/// This is deliberately an auxiliary SQL table. It can be installed on every
/// open without changing Drift's generated schema, while still giving old
/// databases the same fail-closed contract as new databases.
Future<void> installConsignmentReturnLiabilityGuards(AppDatabase db) async {
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS consignment_return_liability_decisions (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      source_table TEXT NOT NULL,
      source_id INTEGER NOT NULL,
      source_item_id INTEGER NOT NULL,
      disposition_type TEXT NOT NULL,
      responsibility TEXT NOT NULL,
      reason TEXT NOT NULL,
      decided_by INTEGER REFERENCES users(id) ON DELETE RESTRICT,
      decided_at TEXT NOT NULL,
      request_key TEXT NOT NULL UNIQUE,
      CHECK(source_table IN ('sale_returns','sale_return_adjustments')),
      CHECK(disposition_type IN ('damaged','scrap','write_off')),
      CHECK(responsibility IN ('supplier','company','review')),
      CHECK(length(trim(reason)) BETWEEN 1 AND 500),
      UNIQUE(source_table,source_item_id)
    )
  ''');
  await db.customStatement(
    'CREATE INDEX IF NOT EXISTS consignment_return_liability_source '
    'ON consignment_return_liability_decisions(source_table,source_id)',
  );

  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_return_liability_insert_guard
    BEFORE INSERT ON consignment_return_liability_decisions
    WHEN NOT (
      (NEW.source_table='sale_returns' AND EXISTS(
        SELECT 1
        FROM sale_return_items i
        JOIN sale_returns r ON r.id=i.return_id
        JOIN consignment_sale_allocations a ON a.sale_item_id=i.sale_item_id
        WHERE i.id=NEW.source_item_id
          AND r.id=NEW.source_id
          AND r.status IN ('draft','pending')
          AND r.disposition_type=NEW.disposition_type
      ))
      OR
      (NEW.source_table='sale_return_adjustments' AND EXISTS(
        SELECT 1
        FROM sale_return_adjustment_items i
        JOIN sale_return_adjustments r ON r.id=i.return_id
        WHERE i.id=NEW.source_item_id
          AND r.id=NEW.source_id
          AND r.status IN ('draft','pending')
          AND i.consignment_layer_id IS NOT NULL
          AND i.disposition_type=NEW.disposition_type
      ))
    )
    BEGIN
      SELECT RAISE(ABORT,'Invalid consignment return liability decision');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_return_liability_no_update
    BEFORE UPDATE ON consignment_return_liability_decisions
    BEGIN
      SELECT RAISE(ABORT,'Consignment return liability decision is immutable');
    END
  ''');
  await db.customStatement('''
    CREATE TRIGGER IF NOT EXISTS consignment_return_liability_no_delete
    BEFORE DELETE ON consignment_return_liability_decisions
    BEGIN
      SELECT RAISE(ABORT,'Consignment return liability decision is immutable');
    END
  ''');
}

enum ConsignmentReturnLiabilityResponsibility {
  supplier,
  company,
  review;

  static ConsignmentReturnLiabilityResponsibility fromWire(String? value) =>
      switch (value) {
        'supplier' => supplier,
        'company' => company,
        _ => review,
      };
}

class ConsignmentReturnLiabilityException implements Exception {
  const ConsignmentReturnLiabilityException(this.code);

  static const decisionRequired =
      'consignment.return_liability_decision_required';
  static const invalidDecision =
      'consignment.return_liability_decision_invalid';

  final String code;

  @override
  String toString() => code;
}

class ConsignmentReturnLiabilityDecision {
  const ConsignmentReturnLiabilityDecision({
    required this.responsibility,
    required this.reason,
    this.decidedBy,
  });

  final ConsignmentReturnLiabilityResponsibility responsibility;
  final String reason;
  final int? decidedBy;
}

class ConsignmentReturnLiabilityStore {
  ConsignmentReturnLiabilityStore._();

  static Future<void> record(
    DatabaseAccessor<AppDatabase> dao, {
    required String sourceTable,
    required int sourceId,
    required int sourceItemId,
    required String dispositionType,
    required ConsignmentReturnLiabilityDecision decision,
  }) async {
    final db = dao.attachedDatabase;
    await installConsignmentReturnLiabilityGuards(db);
    final reason = decision.reason.trim();
    if (!const {'sale_returns', 'sale_return_adjustments'}.contains(sourceTable) ||
        !const {'damaged', 'scrap', 'write_off'}.contains(dispositionType) ||
        reason.isEmpty ||
        reason.length > 500) {
      throw const ConsignmentReturnLiabilityException(
        ConsignmentReturnLiabilityException.invalidDecision,
      );
    }
    final responsibility = decision.responsibility.name;
    await db.customInsert(
      'INSERT INTO consignment_return_liability_decisions('
      'source_table,source_id,source_item_id,disposition_type,responsibility,'
      'reason,decided_by,decided_at,request_key) VALUES(?,?,?,?,?,?,?,?,?)',
      variables: [
        Variable.withString(sourceTable),
        Variable.withInt(sourceId),
        Variable.withInt(sourceItemId),
        Variable.withString(dispositionType),
        Variable.withString(responsibility),
        Variable.withString(reason),
        decision.decidedBy == null
            ? const Variable<int>(null)
            : Variable.withInt(decision.decidedBy!),
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
        Variable.withString('$sourceTable:$sourceItemId:$responsibility'),
      ],
    );
  }

  static Future<ConsignmentReturnLiabilityResponsibility> requireResolved(
    DatabaseAccessor<AppDatabase> dao, {
    required String sourceTable,
    required int sourceId,
    required int sourceItemId,
  }) async {
    final db = dao.attachedDatabase;
    await installConsignmentReturnLiabilityGuards(db);
    final row = await db.customSelect(
      'SELECT responsibility FROM consignment_return_liability_decisions '
      'WHERE source_table=? AND source_id=? AND source_item_id=? LIMIT 1',
      variables: [
        Variable.withString(sourceTable),
        Variable.withInt(sourceId),
        Variable.withInt(sourceItemId),
      ],
    ).getSingleOrNull();
    final responsibility = ConsignmentReturnLiabilityResponsibility.fromWire(
      row?.readNullable<String>('responsibility'),
    );
    if (responsibility == ConsignmentReturnLiabilityResponsibility.review) {
      throw const ConsignmentReturnLiabilityException(
        ConsignmentReturnLiabilityException.decisionRequired,
      );
    }
    return responsibility;
  }

  static Future<ConsignmentReturnLiabilityResponsibility?> read(
    DatabaseAccessor<AppDatabase> dao, {
    required String sourceTable,
    required int sourceItemId,
  }) async {
    final db = dao.attachedDatabase;
    await installConsignmentReturnLiabilityGuards(db);
    final row = await db.customSelect(
      'SELECT responsibility FROM consignment_return_liability_decisions '
      'WHERE source_table=? AND source_item_id=? LIMIT 1',
      variables: [
        Variable.withString(sourceTable),
        Variable.withInt(sourceItemId),
      ],
    ).getSingleOrNull();
    if (row == null) return null;
    return ConsignmentReturnLiabilityResponsibility.fromWire(
      row.read<String>('responsibility'),
    );
  }
}
