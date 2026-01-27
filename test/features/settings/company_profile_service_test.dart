import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/settings_dao.dart';
import 'package:tapix/features/settings/data/services/company_profile_service.dart';
import 'package:tapix/features/settings/domain/entities/company_profile.dart';

void main() {
  group('CompanyProfileService', () {
    late AppDatabase database;
    late SettingsDao settingsDao;
    late CompanyProfileService service;

    setUp(() {
      database = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
      settingsDao = SettingsDao(database);
      service = CompanyProfileService(settingsDao);
    });

    tearDown(() async {
      await service.dispose();
      await database.close();
    });

    test('returns empty profile when not set', () async {
      final profile = await service.getProfile();
      expect(profile, isA<CompanyProfile>());
      expect(profile.name, equals(''));
    });

    test('saves and loads profile', () async {
      const profile = CompanyProfile(
        name: 'Tapix Store',
        address: 'Main street',
        phone: '+213000000',
        email: 'store@example.com',
        taxNumber: 'TAX-123',
        website: 'https://example.com',
        logoBase64: 'aGVsbG8=',
      );

      await service.saveProfile(profile);

      final loaded = await service.getProfile();
      expect(loaded.name, equals(profile.name));
      expect(loaded.address, equals(profile.address));
      expect(loaded.phone, equals(profile.phone));
      expect(loaded.email, equals(profile.email));
      expect(loaded.taxNumber, equals(profile.taxNumber));
      expect(loaded.website, equals(profile.website));
      expect(loaded.logoBase64, equals(profile.logoBase64));
    });
  });
}
