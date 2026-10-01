import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/services/lan/lan_models.dart';
import 'package:tapix/core/services/online/online_branch_sync_service.dart';
import 'package:tapix/core/services/online/online_setup_code.dart';
import 'package:tapix/core/services/online/online_sync_controller.dart';
import 'package:tapix/core/services/online/online_sync_gateway.dart';
import 'package:tapix/features/business/presentation/screens/online_sync_settings_screen.dart';
import 'package:uuid/uuid.dart';

class Assets extends AssetLoader {
  const Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class Service extends Fake implements OnlineBranchSyncService {
  bool allowed = true;
  OnlineConnectionSummary? connection;
  int connections = 0;
  String? received;
  final request = OnlineSetupCode(
    type: 'request',
    organizationId: const Uuid().v4(),
    databaseId: const Uuid().v4(),
    branchId: const Uuid().v4(),
    name: 'فرع الاختبار',
  );
  @override
  Future<void> authorizeConfiguration() async {
    if (!allowed) throw const OnlineSyncException('owner_required');
  }

  @override
  Future<OnlineConnectionSummary?> inspectConnection() async => connection;
  @override
  Future<OnlineSetupCode> bindingRequest() async => request;
  @override
  Future<OnlineWriterSession> connectCode(String code) async {
    connections++;
    received = code;
    connection = OnlineConnectionSummary(
      endpoint: Uri.parse('https://example.test'),
      name: request.name,
      role: 'writer',
      enabled: true,
    );
    return OnlineWriterSession(
      organizationId: request.organizationId,
      databaseId: request.databaseId,
      branchId: request.branchId,
      relayId: const Uuid().v4(),
      deviceName: request.name,
      role: 'writer',
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    connection = OnlineConnectionSummary(
      endpoint: connection!.endpoint,
      name: connection!.name,
      role: connection!.role,
      enabled: enabled,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  Future<void> mount(
    WidgetTester tester,
    String language,
    Service service,
    OnlineSyncController controller,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
        path: 'assets/translations',
        assetLoader: const Assets(),
        startLocale: Locale(language),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: OnlineSyncSettingsScreen(
              service: service,
              controller: controller,
              pilotEnabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  OnlineSyncController controller(Service service) => OnlineSyncController(
    inspect: service.inspectConnection,
    synchronize: () async =>
        const LanBranchSyncRunResult(uploaded: 1, downloaded: 0),
    canRun: () => true,
  );
  for (final language in ['ar', 'en', 'fr']) {
    for (final width in [360.0, 1200.0]) {
      testWidgets(
        'pilot settings fits $language width=$width and shows saved branch',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final service = Service()
            ..connection = OnlineConnectionSummary(
              endpoint: Uri.parse('https://example.test'),
              name: 'فرع الاختبار',
              role: 'owner',
              enabled: true,
            );
          final sync = controller(service);
          await mount(tester, language, service, sync);
          expect(find.text('فرع الاختبار'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          sync.dispose();
        },
      );
    }
  }
  testWidgets(
    'single code is reviewed, connected and cleared; pause retains binding',
    (tester) async {
      final service = Service(), sync = controller(Service());
      // Bind this controller to the same fake service as the screen.
      sync.dispose();
      final actual = controller(service);
      await mount(tester, 'en', service, actual);
      final code = OnlineSetupCode(
        type: 'invitation',
        organizationId: service.request.organizationId,
        databaseId: service.request.databaseId,
        branchId: service.request.branchId,
        name: service.request.name,
        endpoint: Uri.parse('https://example.test'),
        secret: List.filled(43, 'a').join(),
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      ).encode();
      final input = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      await tester.enterText(find.byType(TextField), code);
      await tester.ensureVisible(find.text('Connect and save'));
      await tester.tap(find.text('Connect and save'));
      await tester.pumpAndSettle();
      expect(service.connections, 0);
      expect(find.textContaining('https://example.test'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Connect and save').last,
      );
      await tester.pumpAndSettle();
      expect(service.received, code);
      expect(service.connections, 1);
      expect(input.text, isEmpty);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(service.connection!.enabled, false);
      expect(service.connections, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      actual.dispose();
    },
  );
  testWidgets('non-owner sees permission explanation and no setup controls', (
    tester,
  ) async {
    final service = Service()..allowed = false;
    final sync = controller(service);
    await mount(tester, 'en', service, sync);
    expect(
      find.textContaining('Sign in with the active owner'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(service.connections, 0);
    await tester.pumpWidget(const SizedBox());
    sync.dispose();
  });
}
