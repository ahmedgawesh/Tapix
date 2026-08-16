import 'dart:async';

import '../../../../core/database/daos/settings_dao.dart';
import '../../domain/entities/company_profile.dart';

class CompanyProfileService {
  final SettingsDao _settingsDao;

  static const String keyCompanyProfile = 'company_profile';

  final _controller = StreamController<CompanyProfile>.broadcast();

  CompanyProfileService(this._settingsDao);

  Stream<CompanyProfile> get profileStream => _controller.stream;

  Future<CompanyProfile> getProfile() async {
    final raw = await _settingsDao.getSetting(keyCompanyProfile);
    return CompanyProfile.tryFromJson(raw) ?? CompanyProfile.empty();
  }

  Stream<CompanyProfile> watchProfile() {
    return _settingsDao
        .watchSetting(keyCompanyProfile)
        .map(
          (raw) => CompanyProfile.tryFromJson(raw) ?? CompanyProfile.empty(),
        );
  }

  Future<void> saveProfile(CompanyProfile profile) async {
    await _settingsDao.saveSetting(keyCompanyProfile, profile.toJson());
    _controller.add(profile);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
