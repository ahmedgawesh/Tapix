import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/settings_dao.dart';
import 'package:tapix/features/settings/data/services/app_settings_service.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'independent branch follows shared pharmacy and promotion policy',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_settings_v1': const AppSettings().toJson(),
      });
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      await db.customSelect('SELECT 1').get();
      final settings = SettingsDao(db);
      await settings.saveSetting(
        'lan.branch_sync.coordinator_database_id.v1',
        '99999999-9999-4999-8999-999999999999',
      );
      await settings.saveSetting('pharmacy_features_enabled', '1');
      await settings.saveSetting('promotions_enabled', '1');
      final service = AppSettingsService(
        prefs,
        database: db,
        settingsDao: settings,
      );

      await service.initializeSharedFeaturePolicy();
      expect(service.current.enablePharmacyFeatures, isTrue);
      expect(service.current.enablePromotions, isTrue);

      final disabled = service.stream.firstWhere(
        (value) => !value.enablePharmacyFeatures && !value.enablePromotions,
      );
      await settings.saveSetting('pharmacy_features_enabled', '0');
      await settings.saveSetting('promotions_enabled', '0');
      await disabled.timeout(const Duration(seconds: 2));
      expect(service.current.enablePharmacyFeatures, isFalse);
      expect(service.current.enablePromotions, isFalse);

      service.dispose();
      await db.close();
    },
  );

  test('coordinator keeps its local feature preferences', () async {
    SharedPreferences.setMockInitialValues({
      'app_settings_v1': const AppSettings(
        enablePharmacyFeatures: true,
        enablePromotions: true,
      ).toJson(),
    });
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    final settings = SettingsDao(db);
    final localDatabaseId = await db
        .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
        .map((row) => row.read<String>('database_id'))
        .getSingle();
    await settings.saveSetting(
      'lan.branch_sync.coordinator_database_id.v1',
      localDatabaseId,
    );
    await settings.saveSetting('pharmacy_features_enabled', '0');
    await settings.saveSetting('promotions_enabled', '0');
    final service = AppSettingsService(
      prefs,
      database: db,
      settingsDao: settings,
    );

    await service.initializeSharedFeaturePolicy();
    expect(service.current.enablePharmacyFeatures, isTrue);
    expect(service.current.enablePromotions, isTrue);

    service.dispose();
    await db.close();
  });
}
