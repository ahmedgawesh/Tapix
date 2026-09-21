import 'dart:convert';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../currency_service.dart' as money;
import 'local_branch_scope.dart';

/// A branch's accounting currency, independent of a device's display setting.
/// Binding is explicit during authorized add-on setup; old databases and
/// single-branch installations are never silently converted or rebound.
class BranchCurrencyPolicyStore {
  BranchCurrencyPolicyStore(this._db);
  final AppDatabase _db;
  String _key(String branch) => 'business.currency.v1.$branch';

  Future<({int id, String code, int digits})?> read() =>
      _db.transaction(() async {
        final local = await LocalBranchScope.read(_db);
        final row = await (_db.select(
          _db.appSettings,
        )..where((s) => s.key.equals(_key(local.branchId)))).getSingleOrNull();
        if (row == null) return null;
        final value = jsonDecode(row.value);
        if (value is! Map ||
            value['version'] != 1 ||
            value['organizationId'] != local.organizationId ||
            value['branchId'] != local.branchId ||
            value['databaseId'] != local.databaseId ||
            value['currencyId'] is! int ||
            value['code'] is! String ||
            value['digits'] is! int) {
          throw StateError('Invalid branch currency binding');
        }
        final currency = await (_db.select(
          _db.currencies,
        )..where((c) => c.id.equals(value['currencyId'] as int))).getSingle();
        final configured = money.Currency.allCurrencies
            .where((c) => c.code == currency.code)
            .toList();
        if (currency.code != value['code'] ||
            configured.length != 1 ||
            configured.single.decimalDigits != value['digits']) {
          throw StateError('Branch currency identity or precision changed');
        }
        return (
          id: currency.id,
          code: currency.code,
          digits: value['digits'] as int,
        );
      });

  Future<void> bind(String code) => _db.transaction(() async {
    final current = await read();
    if (current != null) {
      if (current.code != code) {
        throw StateError('Branch accounting currency is already bound');
      }
      return;
    }
    final local = await LocalBranchScope.read(_db);
    final currency = await (_db.select(
      _db.currencies,
    )..where((c) => c.code.equals(code) & c.isActive.equals(true))).getSingle();
    final configured = money.Currency.allCurrencies.singleWhere(
      (c) => c.code == code,
    );
    // Mixed historical currencies require explicit reconciliation, not a label
    // change. Unposted drafts do not establish accounting history.
    final conflict = await _db
        .customSelect(
          '''
      SELECT currency_id FROM (
        SELECT currency_id FROM sales WHERE status = 'completed'
        UNION ALL SELECT currency_id FROM purchases WHERE status = 'posted'
        UNION ALL SELECT currency_id FROM sale_returns WHERE status = 'posted'
        UNION ALL SELECT currency_id FROM purchase_returns WHERE status = 'posted'
        UNION ALL SELECT currency_id FROM sale_return_adjustments WHERE status = 'posted'
        UNION ALL SELECT currency_id FROM purchase_return_adjustments WHERE status = 'posted'
        UNION ALL SELECT currency_id FROM inventory_adjustments
        UNION ALL SELECT l.currency_id FROM journal_entry_lines l
          JOIN journal_entries j ON j.id = l.journal_entry_id WHERE j.status = 'posted'
      ) WHERE currency_id != ? LIMIT 1
    ''',
          variables: [Variable.withInt(currency.id)],
        )
        .getSingleOrNull();
    if (conflict != null) {
      throw StateError(
        'Reconcile historical currencies before enabling warehouses',
      );
    }
    await _db
        .into(_db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: _key(local.branchId),
            value: jsonEncode({
              'version': 1,
              'organizationId': local.organizationId,
              'branchId': local.branchId,
              'databaseId': local.databaseId,
              'currencyId': currency.id,
              'code': currency.code,
              'digits': configured.decimalDigits,
            }),
          ),
        );
  });

  Future<void> validateDisplayCode(String code) async {
    final current = await read();
    if (current != null && current.code != code) {
      throw StateError(
        'Changing display currency cannot convert branch accounting data',
      );
    }
  }

  Future<void> validateDefinitionChange(String code, int? digits) async {
    final current = await read();
    if (current != null &&
        current.code == code &&
        (digits == null || digits != current.digits)) {
      throw StateError(
        'Bound accounting currency cannot be removed or rescaled',
      );
    }
  }

  Future<void> requireCurrency(int id, {bool requireBinding = false}) async {
    final current = await read();
    if ((requireBinding && current == null) ||
        (current != null && current.id != id)) {
      throw StateError(
        'Document must use the bound branch accounting currency',
      );
    }
  }
}
