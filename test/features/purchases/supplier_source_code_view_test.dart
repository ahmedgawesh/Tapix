import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/features/purchases/presentation/widgets/supplier_source_code_view.dart';

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
  for (final language in ['ar', 'en', 'fr']) {
    testWidgets('supplier source code and errors are readable in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: Locale(language),
          saveLocale: false,
          child: Builder(
            builder: (ctx) => MaterialApp(
              locale: ctx.locale,
              supportedLocales: ctx.supportedLocales,
              localizationsDelegates: ctx.localizationDelegates,
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      SupplierSourceCodeView(code: '007-015'),
                      SupplierSourceCodeView(
                        errorKey: 'supplier_identity.code_required',
                      ),
                      SupplierSourceCodeView(pending: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('007-015'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('007-015')).textDirection,
        ui.TextDirection.ltr,
      );
      expect(find.text('supplier_purchase.code_label'), findsNothing);
      expect(find.text('supplier_purchase.loading'), findsNothing);
      expect(find.text('supplier_identity.code_required'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
