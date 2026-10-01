import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/features/business/data/lan_branch_enrollment_service.dart';
import 'package:tapix/features/business/data/lan_branch_provisioning_service.dart';
import 'package:tapix/features/business/presentation/screens/lan_branch_join_screen.dart';

class _Assets extends AssetLoader {
  const _Assets();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Service extends Fake implements LanBranchProvisioningService {
  _Service({this.result});

  final LanBranchProvisioningResult? result;

  @override
  Future<LanBranchProvisioningResult> join(String encodedInvitation) async =>
      result!;
}

String _invitation() => LanBranchConnectionInvitation(
  hosts: const ['192.168.1.20'],
  port: 45820,
  coordinatorFingerprint: List.filled(64, 'a').join(),
  branch: LanBranchInvitation(
    enrollmentId: '66666666-6666-4666-8666-666666666666',
    organizationId: '11111111-1111-4111-8111-111111111111',
    organizationName: 'Tapix Company',
    coordinatorBranchId: '22222222-2222-4222-8222-222222222222',
    branchId: '33333333-3333-4333-8333-333333333333',
    branchName: 'Cairo',
    branchCode: 'CAIRO',
    warehouseId: '44444444-4444-4444-8444-444444444444',
    warehouseName: 'Cairo main',
    warehouseCode: 'CAI-MAIN',
    coordinatorDatabaseId: '55555555-5555-4555-8555-555555555555',
    secret: 'test-one-time-secret',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  ),
).encode();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final language in ['ar', 'en', 'fr']) {
    testWidgets('branch join preview is responsive in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final locale = Locale(language);
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: locale,
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              theme: ThemeData(brightness: Brightness.dark),
              home: LanBranchJoinScreen(service: _Service()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), _invitation());
      await tester.pumpAndSettle();
      expect(find.text('Tapix Company'), findsOneWidget);
      expect(find.textContaining('CAIRO'), findsOneWidget);
      expect(find.textContaining('CAI-MAIN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('committed join explains pending shared-data bootstrap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
        path: 'assets/translations',
        assetLoader: const _Assets(),
        startLocale: const Locale('ar'),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: LanBranchJoinScreen(
              service: _Service(
                result: const LanBranchProvisioningResult(
                  organizationName: 'Tapix Company',
                  branchName: 'Cairo',
                  warehouseName: 'Cairo main',
                  catalogueReady: false,
                  locationsReady: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _invitation());
    await tester.pumpAndSettle();
    final joinButton = find.text('ربط هذا الجهاز بالفرع');
    await tester.ensureVisible(joinButton);
    await tester.pumpAndSettle();
    await tester.tap(joinButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('تم اعتماد هوية الفرع'), findsOneWidget);
    expect(
      find.textContaining('سيعيد النظام المحاولة تلقائيًا'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
