import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'return_approval_exceptions.dart';

/// Phase 3 — read/write service for `return_reason_codes`.
///
/// System-seeded rows (`is_system = 1`) are protected from delete and from
/// renaming of `code`. Operators may still toggle `isActive` so a code
/// disappears from new-return pickers without breaking historical FKs.
///
/// Side-filtering: pass `'sale'`, `'purchase'`, or `'both'` (default).
/// Codes with `side = 'both'` always match both sides.
class ReturnReasonCodeService {
  final AppDatabase _db;
  ReturnReasonCodeService(this._db);

  /// Returns active reason codes applicable to [side]. Pass `'sale'`,
  /// `'purchase'`, or `null`/`'both'` for all.
  Future<List<ReturnReasonCode>> listActive({String? side}) async {
    final query = _db.select(_db.returnReasonCodes)
      ..where((t) => t.isActive.equals(true));
    if (side != null && side != 'both') {
      query.where((t) => t.side.isIn([side, 'both']));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.isSystem, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.code),
    ]);
    return query.get();
  }

  /// All rows (active + inactive) — for the admin Reason-Codes screen.
  Future<List<ReturnReasonCode>> listAll() {
    return (_db.select(_db.returnReasonCodes)..orderBy([
          (t) => OrderingTerm(expression: t.isSystem, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.code),
        ]))
        .get();
  }

  Future<ReturnReasonCode?> findByCode(String code) {
    return (_db.select(
      _db.returnReasonCodes,
    )..where((t) => t.code.equals(code))).getSingleOrNull();
  }

  Future<ReturnReasonCode?> findById(int id) {
    return (_db.select(
      _db.returnReasonCodes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Create a new operator-defined reason code. System codes are seeded
  /// only by migrations / `_seedReturnReasonCodes` — never via this API.
  Future<int> create({
    required String code,
    required String labelEn,
    required String labelAr,
    String side = 'both',
    String? description,
  }) async {
    final existing = await findByCode(code);
    if (existing != null) {
      // Idempotent rename of the user fields; system protection is not
      // bypassable.
      if (existing.isSystem) {
        throw SystemReasonCodeProtectedException(code);
      }
      await (_db.update(
        _db.returnReasonCodes,
      )..where((t) => t.id.equals(existing.id))).write(
        ReturnReasonCodesCompanion(
          labelEn: Value(labelEn),
          labelAr: Value(labelAr),
          side: Value(side),
          description: Value(description),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return existing.id;
    }
    return _db
        .into(_db.returnReasonCodes)
        .insert(
          ReturnReasonCodesCompanion.insert(
            code: code,
            labelEn: labelEn,
            labelAr: labelAr,
            side: Value(side),
            description: Value(description),
          ),
        );
  }

  /// Toggle `isActive`. System codes may be deactivated (operator choice)
  /// but cannot be deleted.
  Future<void> setActive(int id, bool active) async {
    await (_db.update(
      _db.returnReasonCodes,
    )..where((t) => t.id.equals(id))).write(
      ReturnReasonCodesCompanion(
        isActive: Value(active),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Rename labels. Code-string is immutable to keep historical FK joins
  /// stable; system rows allow label edits but reject code changes.
  Future<void> updateLabels(
    int id, {
    String? labelEn,
    String? labelAr,
    String? description,
  }) async {
    await (_db.update(
      _db.returnReasonCodes,
    )..where((t) => t.id.equals(id))).write(
      ReturnReasonCodesCompanion(
        labelEn: labelEn == null ? const Value.absent() : Value(labelEn),
        labelAr: labelAr == null ? const Value.absent() : Value(labelAr),
        description: description == null
            ? const Value.absent()
            : Value(description),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Hard-delete a non-system row. Throws
  /// [SystemReasonCodeProtectedException] for system rows.
  Future<void> delete(int id) async {
    final row = await findById(id);
    if (row == null) return;
    if (row.isSystem) {
      throw SystemReasonCodeProtectedException(row.code);
    }
    await (_db.delete(
      _db.returnReasonCodes,
    )..where((t) => t.id.equals(id))).go();
  }
}
