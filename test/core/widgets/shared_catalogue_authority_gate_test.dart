import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/widgets/shared_catalogue_authority_gate.dart';

class _Assets extends AssetLoader {
  const _Assets();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final locale in const [Locale('ar'), Locale('en'), Locale('fr')]) {
    testWidgets(
      'independent branch explanation fits narrow ${locale.languageCode}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
            path: 'assets/translations',
            assetLoader: const _Assets(),
            startLocale: locale,
            child: Builder(
              builder: (context) => MaterialApp(
                locale: context.locale,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: child!,
                ),
                home: SharedCatalogueAuthorityGate(
                  title: 'Catalogue',
                  authorityCheck: () async => false,
                  child: const Text('editable catalogue'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('editable catalogue'), findsNothing);
        expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('coordinator opens the requested editor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SharedCatalogueAuthorityGate(
          title: 'Catalogue',
          authorityCheck: () async => true,
          child: const Text('editable catalogue'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('editable catalogue'), findsOneWidget);
  });
}
