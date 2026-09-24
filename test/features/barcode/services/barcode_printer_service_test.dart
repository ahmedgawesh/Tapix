import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:tapix/features/barcode/services/barcode_printer_service.dart';
import 'package:tapix/core/database/daos/settings_dao.dart';

// Generate Mocks
@GenerateNiceMocks([MockSpec<SettingsDao>()])
import 'barcode_printer_service_test.mocks.dart';

void main() {
  late BarcodePrinterService service;
  late MockSettingsDao mockSettingsDao;

  setUp(() {
    mockSettingsDao = MockSettingsDao();
    service = BarcodePrinterService(settingsDao: mockSettingsDao);
  });

  group('BarcodePrinterService', () {
    test('saveSettings stores label dimensions', () async {
      // Arrange
      when(mockSettingsDao.saveSetting(any, any)).thenAnswer((_) async {});

      // Act
      await service.saveSettings(
        widthMm: 58.0,
        heightMm: 40.0,
        includeName: true,
        includePrice: true,
      );

      // Assert
      verify(
        mockSettingsDao.saveSetting('barcode_label_width', '58.0'),
      ).called(1);
      verify(
        mockSettingsDao.saveSetting('barcode_label_height', '40.0'),
      ).called(1);
      verify(
        mockSettingsDao.saveSetting('barcode_include_name', 'true'),
      ).called(1);
      verify(
        mockSettingsDao.saveSetting('barcode_include_price', 'true'),
      ).called(1);
    });

    test('getSettings retrieves stored configuration', () async {
      // Arrange
      when(
        mockSettingsDao.getSetting('barcode_label_width'),
      ).thenAnswer((_) async => '50.0');
      when(
        mockSettingsDao.getSetting('barcode_label_height'),
      ).thenAnswer((_) async => '30.0');
      when(
        mockSettingsDao.getSetting('barcode_include_name'),
      ).thenAnswer((_) async => 'true');
      when(
        mockSettingsDao.getSetting('barcode_include_price'),
      ).thenAnswer((_) async => 'false');

      // Act
      final config = await service.getSettings();

      // Assert
      expect(config.widthMm, 50.0);
      expect(config.heightMm, 30.0);
      expect(config.includeName, true);
      expect(config.includePrice, false);
    });

    test('getSettings returns defaults when no settings stored', () async {
      // Arrange
      when(mockSettingsDao.getSetting(any)).thenAnswer((_) async => null);

      // Act
      final config = await service.getSettings();

      // Assert
      expect(config.widthMm, 50.0); // default
      expect(config.heightMm, 30.0); // default
      expect(config.includeName, false);
      expect(config.includePrice, false);
    });

    // Note: PDF generation tests are skipped as they require Flutter's painting
    // framework and are better tested via integration tests or manual verification.
  });
}
