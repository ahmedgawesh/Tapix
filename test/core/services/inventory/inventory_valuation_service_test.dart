import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/settings_dao.dart';
import 'package:tapix/core/services/inventory/inventory_valuation_method.dart';
import 'package:tapix/core/services/inventory/inventory_valuation_service.dart';

/// Phase A regression tests — guard the contract that:
///   * Fresh installs default to WAC.
///   * The service is the single writer; reads come from settings_dao.
///   * The cache stays coherent under setMethod.
///   * `hasPostedTransactions` reflects sales+purchases honestly.
void main() {
  group('InventoryValuationService', () {
    late AppDatabase db;
    late SettingsDao settingsDao;
    late InventoryValuationService service;

    setUp(() async {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
      // Force the schema/migration to run so the seed row is present.
      await db.customSelect('SELECT 1').get();
      settingsDao = SettingsDao(db);
      service = InventoryValuationService(settingsDao);
    });

    tearDown(() async {
      service.dispose();
      await db.close();
    });

    test('fresh install seeds WAC as the default', () async {
      final method = await service.getMethod();
      expect(method, InventoryValuationMethod.wac);
    });

    test('getMethod is cached after first call', () async {
      await service.getMethod();
      // Mutate the underlying row WITHOUT going through the service.
      // The cache should still serve the previous value until invalidated.
      await settingsDao.saveSetting(
        InventoryValuationMethod.settingKey,
        'fifo',
      );
      expect(service.methodOrDefault, InventoryValuationMethod.wac);

      service.invalidateCache();
      final fresh = await service.getMethod();
      expect(fresh, InventoryValuationMethod.fifo);
    });

    test('setMethod persists and updates the cache', () async {
      final previous = await service.setMethod(
        InventoryValuationMethod.fifo,
        reason: 'switching to FIFO for IFRS reporting',
      );
      expect(previous, InventoryValuationMethod.wac);
      expect(service.methodOrDefault, InventoryValuationMethod.fifo);

      // Read back from a fresh service instance to prove it's persisted.
      final fresh = InventoryValuationService(settingsDao);
      expect(await fresh.getMethod(), InventoryValuationMethod.fifo);
    });

    test('setMethod is a no-op when value is unchanged', () async {
      final first = await service.setMethod(InventoryValuationMethod.wac);
      expect(first, InventoryValuationMethod.wac);
      // Second call with the same value must still return the previous value
      // (which is also wac) without raising.
      final second = await service.setMethod(InventoryValuationMethod.wac);
      expect(second, InventoryValuationMethod.wac);
    });

    test('hasPostedTransactions returns false on an empty DB', () async {
      expect(await service.hasPostedTransactions(), isFalse);
    });

    test('watchMethod emits subsequent writes', () async {
      final emitted = <InventoryValuationMethod>[];
      final sub = service.watchMethod().listen(emitted.add);

      // Initial seed
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await service.setMethod(InventoryValuationMethod.fifo);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await service.setMethod(InventoryValuationMethod.wac);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await sub.cancel();

      // We do not assert the exact ordering of the seed event versus the
      // watcher subscription — only that both writes were observed.
      expect(emitted, contains(InventoryValuationMethod.fifo));
      expect(emitted, contains(InventoryValuationMethod.wac));
    });

    test('fromKey is total — falls back to WAC on garbage', () {
      expect(
        InventoryValuationMethod.fromKey(null),
        InventoryValuationMethod.wac,
      );
      expect(
        InventoryValuationMethod.fromKey(''),
        InventoryValuationMethod.wac,
      );
      expect(
        InventoryValuationMethod.fromKey('average'),
        InventoryValuationMethod.wac,
      );
      expect(
        InventoryValuationMethod.fromKey('FIFO'),
        // Case-sensitive on purpose — stored values are always lowercase.
        InventoryValuationMethod.wac,
      );
    });
  });
}
