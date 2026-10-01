import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart' hide Size;
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/core/services/feature_gate_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/consignment/data/consignment_reporting_service.dart';
import 'package:tapix/features/consignment/presentation/screens/consignment_hub_screen.dart';

// Models the existing gate's trusted offline state. No store service is supplied
// to consignment: a second online check must not override this decision.
class _TrustedGate extends ChangeNotifier implements FeatureGateService {
  bool granted = true;
  void update(bool value) {
    granted = value;
    notifyListeners();
  }

  @override
  FeatureAccess canAccess(AppFeature feature) => granted
      ? const FeatureAccess.granted()
      : const FeatureAccess.denied(FeatureDenyReason.requiresPro);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session extends SessionService {
  _Session(this.id);
  final int id;
  @override
  Future<int?> getCurrentUserId() async => id;
}

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

  testWidgets(
    'owner actions follow trusted Pro without a separate store check',
    (tester) async {
      await sl.reset();
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      final gate = _TrustedGate();
      addTearDown(() async {
        await sl.reset();
        gate.dispose();
        await db.close();
      });
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final owner = await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              username: 'offline-owner',
              passwordHash: 'unused',
              role: 'owner',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      var remoteClient = false;
      final module = ConsignmentModuleService(
        db,
        _Session(owner),
        PlatformConsignmentEntitlement(featureGate: gate),
        BranchConsignmentPolicyStore(db),
        isRemoteClient: () => remoteClient,
      );
      await module.initialize();
      await module.setEnabled(
        enabled: true,
        reason: 'Owner enabled consignment',
      );
      expect(await module.operationsEnabled(), isTrue);
      remoteClient = true;
      expect(await module.operationsEnabled(), isFalse);
      remoteClient = false;
      // This is the common local-server path for both standalone and branch
      // installations; restoring Pro must also refresh an already open screen.
      gate.update(false);
      sl.registerSingleton<AppDatabase>(db);
      sl.registerSingleton<FeatureGateService>(gate);
      sl.registerSingleton<ConsignmentModuleService>(module);
      sl.registerSingleton<ConsignmentReportingService>(
        ConsignmentReportingService(db, module),
      );
      sl.registerSingleton<CurrencyService>(
        CurrencyService(await SharedPreferences.getInstance()),
      );
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: const Locale('en'),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: const ConsignmentHubScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      void expectActions(bool enabled) {
        for (final key in [
          'new_agreement',
          'new_receipt',
          'new_ownership_conversion',
          'new_custody_movement',
        ]) {
          final action = tester.widget<InkWell>(
            find
                .ancestor(
                  of: find.text('consignment.$key'.tr()),
                  matching: find.byType(InkWell),
                )
                .first,
          );
          expect(action.onTap != null, enabled, reason: key);
        }
      }

      expectActions(false);
      gate.update(true);
      await tester.pumpAndSettle();
      expect(await module.operationsEnabled(), isTrue);
      expectActions(true);
      gate.update(false);
      await tester.pumpAndSettle();
      expectActions(false);
      expect(await module.historicalManagementEnabled(), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
