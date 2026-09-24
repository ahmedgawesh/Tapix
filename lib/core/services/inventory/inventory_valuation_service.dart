import 'dart:async';

import 'package:drift/drift.dart' show Variable;

import '../../database/daos/settings_dao.dart';
import '../logging_service.dart';
import 'inventory_valuation_method.dart';

/// SINGLE SOURCE OF TRUTH for the business-wide inventory valuation method.
///
/// Style mirrors `CompanyProfileService` and `BarcodePrinterService`:
///   * Reads/writes a single key in `app_settings`.
///   * Caches the parsed enum in memory after first read.
///   * Exposes a [Stream] for BLoC consumers via `SettingsDao.watchSetting`.
///   * No direct DB access from BLoCs; everything goes through this service.
///
/// Audit / lock policy (lightweight in Phase A; expanded in Phase G):
///   * Once any sale or purchase has been *posted*, [setMethod] still
///     succeeds but emits an info log including the prior method and the
///     caller-provided `reason`. A dedicated audit-log row is left for a
///     future phase that has access to the user id.
///   * Callers that should *block* the change (e.g. UI confirmation
///     dialogs) can inspect [hasPostedTransactions] before invoking
///     [setMethod] — it returns `true` once the legacy guard would also
///     have refused a per-product `costing_method` flip.
class InventoryValuationService {
  final SettingsDao _settingsDao;
  static const String _tag = 'InventoryValuationService';

  InventoryValuationMethod? _cached;
  StreamController<InventoryValuationMethod>? _broadcaster;

  InventoryValuationService(this._settingsDao);

  /// Read the current method. Cheap on subsequent calls — the result is
  /// cached in memory and only re-fetched when [setMethod] writes.
  Future<InventoryValuationMethod> getMethod() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw = await _settingsDao.getSetting(
      InventoryValuationMethod.settingKey,
    );
    final method = InventoryValuationMethod.fromKey(raw);
    _cached = method;
    return method;
  }

  /// Synchronous accessor for callers that have already awaited [getMethod]
  /// at least once (e.g. an app-startup warm-up). Returns
  /// [InventoryValuationMethod.defaultMethod] if the cache is cold — never
  /// throws so DAOs that compose under transactions stay safe.
  InventoryValuationMethod get methodOrDefault =>
      _cached ?? InventoryValuationMethod.defaultMethod;

  /// Watch changes to the method. Backed by Drift's reactive query so a
  /// write from any isolate is observed.
  Stream<InventoryValuationMethod> watchMethod() {
    return _settingsDao
        .watchSetting(InventoryValuationMethod.settingKey)
        .map(InventoryValuationMethod.fromKey)
        .map((m) {
          _cached = m;
          return m;
        });
  }

  /// Persist a new method. Returns the previous value so callers (e.g. an
  /// audit-log dispatcher) can record the delta.
  ///
  /// [reason] is appended to the debug log; future phases will write it
  /// into a dedicated `inventory_policy_audit` table.
  Future<InventoryValuationMethod> setMethod(
    InventoryValuationMethod method, {
    String? reason,
  }) async {
    final previous = await getMethod();
    if (previous == method) {
      LoggingService.debug('setMethod: no-op (already $method)', tag: _tag);
      return previous;
    }

    await _settingsDao.saveSetting(
      InventoryValuationMethod.settingKey,
      method.key,
      description:
          'Business-wide inventory valuation method (IAS 2 / ASC 330).',
    );
    _cached = method;
    _broadcaster?.add(method);

    LoggingService.debug(
      'setMethod: $previous → $method'
      '${reason == null ? '' : ' (reason: $reason)'}',
      tag: _tag,
    );
    return previous;
  }

  /// Heuristic check used by the Settings UI to warn the user that flipping
  /// the global method will change how all subsequent COGS is computed.
  /// Returns `true` once any sale or purchase row exists in the DB.
  ///
  /// We deliberately do NOT block the change here — the UI is the right
  /// layer to gate it behind a confirmation dialog with a reason field.
  Future<bool> hasPostedTransactions() async {
    final db = _settingsDao.attachedDatabase;
    final row = await db.customSelect('''
      SELECT
        (SELECT COUNT(*) FROM sales) +
        (SELECT COUNT(*) FROM purchases) AS total
      ''', variables: const <Variable>[]).getSingle();
    return row.read<int>('total') > 0;
  }

  /// Reset the in-memory cache. Used by tests that mutate the underlying
  /// row directly via raw SQL.
  void invalidateCache() {
    _cached = null;
  }

  void dispose() {
    _broadcaster?.close();
    _broadcaster = null;
  }
}
