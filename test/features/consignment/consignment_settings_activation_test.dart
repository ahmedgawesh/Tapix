import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/settings/presentation/widgets/consignment_settings_section.dart';

class _Assets extends AssetLoader {
  const _Assets();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Session extends SessionService {
  _Session(this.id);

  final int id;

  @override
  Future<int?> getCurrentUserId() async => id;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('activation dialog closes before settings subtree is rebuilt', (
    tester,
  ) async {
    await sl.reset();
    addTearDown(sl.reset);
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);
    final owner = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'consignment-settings-owner',
            passwordHash: 'unused',
            role: 'owner',
            createdAt: DateTime.utc(2026, 9, 24),
            updatedAt: DateTime.utc(2026, 9, 24),
          ),
        );
    final module = ConsignmentModuleService(
      db,
      _Session(owner),
      const GrantedConsignmentEntitlement(),
      BranchConsignmentPolicyStore(db),
      isRemoteClient: () => false,
    );
    await module.initialize();
    sl.registerSingleton<ConsignmentModuleService>(module);

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
            home: const Scaffold(
              body: SingleChildScrollView(child: ConsignmentSettingsSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('consignment-module-switch')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('consignment-change-reason-field')),
      'اعتماد المالك',
    );
    await tester.tap(
      find.byKey(const ValueKey('consignment-change-confirm-button')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      (await BranchConsignmentPolicyStore(db).read())!.policy.enabled,
      true,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('consignment-module-switch')),
          )
          .value,
      true,
    );
  });
}
