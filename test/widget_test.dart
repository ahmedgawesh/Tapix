import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/di/injection_container.dart' as di;
import 'package:tapix/core/services/localization_service.dart';
import 'package:tapix/generated/codegen_loader.g.dart';
import 'package:tapix/main.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await di.init();
  });

  tearDownAll(() {
    GetIt.instance.reset();
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    final localizationService = di.sl<LocalizationService>();
    final startLocale = localizationService.getLocale();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: LocalizationService.supportedLocales,
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: startLocale,
        saveLocale: false,
        assetLoader: const CodegenLoader(),
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify basic UI elements are present
    expect(find.text('Tapix'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    
    // Check for theme buttons
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);

    // Check for language buttons
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('AR'), findsOneWidget);
    expect(find.text('FR'), findsOneWidget);
  });
}
