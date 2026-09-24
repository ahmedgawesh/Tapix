import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/features/consignment/presentation/widgets/consignment_help.dart';

class _GuideAssets extends AssetLoader {
  const _GuideAssets();

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

  for (final language in ['ar', 'en', 'fr']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'receipt explanation and guide on narrow $language $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final strings =
              (jsonDecode(
                        File(
                          'assets/translations/$language.json',
                        ).readAsStringSync(),
                      )
                      as Map<String, dynamic>)['consignment']
                  as Map<String, dynamic>;
          await tester.pumpWidget(
            EasyLocalization(
              supportedLocales: const [
                Locale('ar'),
                Locale('en'),
                Locale('fr'),
              ],
              path: 'assets/translations',
              assetLoader: const _GuideAssets(),
              startLocale: Locale(language),
              saveLocale: false,
              child: Builder(
                builder: (context) => MaterialApp(
                  theme: ThemeData(brightness: brightness),
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.3)),
                    child: child!,
                  ),
                  home: const Scaffold(
                    body: SingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: ConsignmentHelpCard(
                        messageKey: 'consignment.guide_receipt_notice',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(strings['guide_receipt_notice'] as String),
            findsOneWidget,
          );
          await tester.tap(find.byType(TextButton));
          await tester.pumpAndSettle();
          expect(find.byType(ConsignmentGuideDialog), findsOneWidget);
          final last = find.text(strings['guide_existing_body'] as String);
          await tester.ensureVisible(last);
          await tester.pumpAndSettle();
          expect(last.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(
            find.widgetWithText(TextButton, 'common.close'.tr()),
          );
          await tester.pumpAndSettle();
          expect(find.byType(ConsignmentGuideDialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
