import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart';

void main() {
  group('AppSettings pharmacy feature', () {
    test('is opt-in for existing and new installations', () {
      expect(const AppSettings().enablePharmacyFeatures, isFalse);
      expect(AppSettings.fromMap(const {}).enablePharmacyFeatures, isFalse);
    });

    test('survives copy and JSON persistence', () {
      final enabled = const AppSettings().copyWith(
        enablePharmacyFeatures: true,
      );

      expect(enabled.enablePharmacyFeatures, isTrue);
      expect(
        AppSettings.fromJson(enabled.toJson()).enablePharmacyFeatures,
        isTrue,
      );
    });
  });
}
