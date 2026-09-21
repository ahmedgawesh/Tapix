import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_tax_policy.dart';
import 'package:tapix/core/services/business/branch_tax_policy_store.dart';
import 'package:tapix/features/settings/data/services/app_settings_service.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart'
    as model;
import 'package:tapix/features/settings/presentation/bloc/app_settings_bloc.dart';

import '../../business/business_foundation_test.dart' as fixtures;

const _key = 'app_settings_v1';

/// Models the plugin's separate in-memory cache and platform persistence.
class _Preferences extends Fake implements SharedPreferences {
  _Preferences(Map<String, String> initial)
    : disk = Map.of(initial),
      cache = Map.of(initial);
  final Map<String, String> disk;
  final Map<String, String> cache;
  bool fail = false;
  Completer<void>? pause;
  int writes = 0;
  @override
  String? getString(String key) => cache[key];
  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    cache[key] = value;
    await pause?.future;
    if (fail) return false;
    disk[key] = value;
    return true;
  }

  @override
  Future<void> reload() async {
    cache
      ..clear()
      ..addAll(disk);
  }
}

void main() {
  late AppDatabase db;
  late BranchTaxPolicyStore store;
  late AppSettingsService service;
  late _Preferences prefs;
  const initial = model.AppSettings(
    defaultSalesTaxRate: 14.5,
    defaultPurchaseTaxRate: 7.25,
    enableTaxCalculations: false,
    taxInclusivePricing: true,
    taxRegistrationNumber: 'REG-001',
    receiptHeaderText: 'Device header',
  );
  BranchTaxPolicy policy(double rate) =>
      BranchTaxPolicy.fromLegacy(initial.copyWith(defaultSalesTaxRate: rate));

  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    store = BranchTaxPolicyStore(db);
    prefs = _Preferences({_key: initial.toJson()});
    service = AppSettingsService(prefs, taxStore: store);
  });
  tearDown(() async {
    service.dispose();
    await db.close();
  });

  test(
    'startup adopts current effective tax settings without changing documents',
    () async {
      final before = await fixtures.legacySnapshot(db)
        ..remove('app_settings');
      expect(await store.read(), isNull);
      await service.initializeTaxPolicy();
      final adopted = (await store.read())!;
      expect(
        adopted.policy.toJson(),
        BranchTaxPolicy.fromLegacy(initial).toJson(),
      );
      expect(service.current.toMap(), initial.toMap());
      expect(
        await fixtures.legacySnapshot(db)
          ..remove('app_settings'),
        before,
      );
    },
  );

  test(
    'database policy wins over stale preferences while device fields survive',
    () async {
      final first = await store.initializeFromLegacy(initial);
      await store.update(expected: first, policy: policy(20));
      await service.initializeTaxPolicy();
      expect(service.current.defaultSalesTaxRate, 20);
      expect(service.current.defaultPurchaseTaxRate, 7.25);
      expect(service.current.receiptHeaderText, 'Device header');
      expect((await store.read())!.revision, 2);
    },
  );

  test('tax edits persist a revision and unrelated edits do not', () async {
    await service.initializeTaxPolicy();
    await service.patch((s) => s.copyWith(defaultSalesTaxRate: 20));
    expect((await store.read())!.revision, 2);
    expect((await store.read())!.policy.salesRateBps, 2000);
    await service.patch((s) => s.copyWith(receiptHeaderText: 'Updated header'));
    expect((await store.read())!.revision, 2);
    expect(service.current.defaultSalesTaxRate, 20);
    expect(
      model.AppSettings.fromJson(prefs.disk[_key]!).receiptHeaderText,
      'Updated header',
    );
  });

  test('queued patches evaluate against latest committed settings', () async {
    await service.initializeTaxPolicy();
    prefs.pause = Completer<void>();
    final first = service.patch((s) => s.copyWith(defaultSalesTaxRate: 20));
    final second = service.patch((s) => s.copyWith(defaultPurchaseTaxRate: 9));
    prefs.pause!.complete();
    await Future.wait([first, second]);
    expect(service.current.defaultSalesTaxRate, 20);
    expect(service.current.defaultPurchaseTaxRate, 9);
    expect((await store.read())!.revision, 3);
    expect((await store.read())!.policy.purchaseRateBps, 900);
  });

  test(
    'committed taxes are visible while the preference mirror is still pending',
    () async {
      await service.initializeTaxPolicy();
      prefs.pause = Completer<void>();
      final taxVisible = service.stream.firstWhere(
        (s) => s.defaultSalesTaxRate == 20,
      );
      final saving = service.patch(
        (s) => s.copyWith(
          defaultSalesTaxRate: 20,
          receiptHeaderText: 'Pending header',
        ),
      );
      try {
        await taxVisible;
        expect((await store.read())!.policy.salesRateBps, 2000);
        expect(service.current.defaultSalesTaxRate, 20);
        expect(service.current.receiptHeaderText, 'Device header');
      } finally {
        prefs.pause!.complete();
        await saving;
      }
      expect(service.current.receiptHeaderText, 'Pending header');
    },
  );

  test(
    'stale tax editor refreshes current values and cannot overwrite another edit',
    () async {
      await service.initializeTaxPolicy();
      await store.update(expected: (await store.read())!, policy: policy(20));
      await expectLater(
        service.patch((s) => s.copyWith(defaultSalesTaxRate: 10)),
        throwsStateError,
      );
      expect(service.current.defaultSalesTaxRate, 20);
      expect((await store.read())!.revision, 2);
      expect(prefs.writes, 0);
      await service.patch((s) => s.copyWith(defaultSalesTaxRate: 15));
      expect((await store.read())!.revision, 3);
      expect(service.current.defaultSalesTaxRate, 15);
    },
  );

  test(
    'unrelated edit refreshes a newer policy without replacing its tax values',
    () async {
      await service.initializeTaxPolicy();
      await store.update(expected: (await store.read())!, policy: policy(20));
      await service.patch((s) => s.copyWith(receiptHeaderText: 'Other'));
      expect(service.current.defaultSalesTaxRate, 20);
      expect(service.current.receiptHeaderText, 'Other');
      expect((await store.read())!.revision, 2);
    },
  );

  test(
    'database failure does not save requested preferences or poison retries',
    () async {
      await service.initializeTaxPolicy();
      await db.customStatement("""
      CREATE TRIGGER reject_bound_tax_update BEFORE UPDATE ON app_settings
      WHEN NEW.key LIKE 'business.tax%.head'
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END
    """);
      await expectLater(
        service.patch(
          (s) => s.copyWith(
            defaultSalesTaxRate: 20,
            receiptHeaderText: 'Not saved',
          ),
        ),
        throwsA(anything),
      );
      expect(service.current.toMap(), initial.toMap());
      expect(prefs.writes, 0);
      expect((await store.read())!.revision, 1);
      await db.customStatement('DROP TRIGGER reject_bound_tax_update');
      await service.patch((s) => s.copyWith(defaultSalesTaxRate: 20));
      expect((await store.read())!.revision, 2);
    },
  );

  test(
    'preference failure keeps committed SQL tax visible and other fields unchanged',
    () async {
      await service.initializeTaxPolicy();
      prefs.fail = true;
      await expectLater(
        service.patch(
          (s) => s.copyWith(
            defaultSalesTaxRate: 20,
            receiptHeaderText: 'Not saved',
          ),
        ),
        throwsStateError,
      );
      expect((await store.read())!.policy.salesRateBps, 2000);
      expect(service.current.defaultSalesTaxRate, 20);
      expect(service.current.receiptHeaderText, 'Device header');
      expect(
        model.AppSettings.fromJson(prefs.getString(_key)!).receiptHeaderText,
        'Device header',
      );
      final restarted = AppSettingsService(
        _Preferences(prefs.disk),
        taxStore: store,
      );
      await restarted.initializeTaxPolicy();
      expect(restarted.current.defaultSalesTaxRate, 20);
      expect(restarted.current.receiptHeaderText, 'Device header');
      restarted.dispose();
      prefs.fail = false;
      await service.patch((s) => s.copyWith(receiptHeaderText: 'Retry saved'));
      expect(service.current.receiptHeaderText, 'Retry saved');
      expect((await store.read())!.revision, 2);
    },
  );

  test(
    'legacy service publishes only successful saves and recovers cache on failure',
    () async {
      final legacy = AppSettingsService(prefs);
      final emitted = <model.AppSettings>[];
      final subscription = legacy.stream.listen(emitted.add);
      prefs.fail = true;
      await expectLater(
        legacy.patch((s) => s.copyWith(receiptHeaderText: 'Failed')),
        throwsStateError,
      );
      expect(legacy.current.receiptHeaderText, 'Device header');
      expect(
        model.AppSettings.fromJson(prefs.getString(_key)!).receiptHeaderText,
        'Device header',
      );
      expect(emitted, isEmpty);
      prefs.fail = false;
      await legacy.patch((s) => s.copyWith(receiptHeaderText: 'Saved'));
      expect(legacy.current.receiptHeaderText, 'Saved');
      await subscription.cancel();
      legacy.dispose();
    },
  );

  test(
    'save before initialization and corrupt startup cannot adopt defaults',
    () async {
      await expectLater(
        service.patch((s) => s.copyWith(defaultSalesTaxRate: 20)),
        throwsStateError,
      );
      expect(await store.read(), isNull);
      final first = await store.initializeFromLegacy(initial);
      await (db.update(db.appSettings)..where(
            (r) =>
                r.key.equals('business.tax_policy.v1.${first.branchId}.head'),
          ))
          .write(const AppSettingsCompanion(value: Value('invalid JSON')));
      await expectLater(service.initializeTaxPolicy(), throwsFormatException);
      expect(prefs.writes, 0);
    },
  );

  test('bloc shows committed state after failure and allows retry', () async {
    await service.initializeTaxPolicy();
    final bloc = AppSettingsBloc(service);
    prefs.fail = true;
    final failure = bloc.stream.firstWhere(
      (s) => s.errorMessageKey != null && !s.isSaving,
    );
    bloc.add(
      AppSettingsPatched(
        (s) => s.copyWith(defaultSalesTaxRate: 20, receiptHeaderText: 'Failed'),
      ),
    );
    final failed = await failure;
    expect(failed.settings.defaultSalesTaxRate, 20);
    expect(failed.settings.receiptHeaderText, 'Device header');
    expect(failed.errorMessageKey, 'app_settings.save_error');
    prefs.fail = false;
    final success = bloc.stream.firstWhere(
      (s) =>
          !s.isSaving &&
          s.errorMessageKey == null &&
          s.settings.receiptHeaderText == 'Saved',
    );
    bloc.add(AppSettingsPatched((s) => s.copyWith(receiptHeaderText: 'Saved')));
    await success;
    await bloc.close();
  });

  test('rapid bloc patches preserve separate fields', () async {
    await service.initializeTaxPolicy();
    final bloc = AppSettingsBloc(service);
    final finished = bloc.stream.firstWhere(
      (s) =>
          !s.isSaving &&
          s.settings.defaultSalesTaxRate == 20 &&
          s.settings.defaultPurchaseTaxRate == 9,
    );
    bloc.add(AppSettingsPatched((s) => s.copyWith(defaultSalesTaxRate: 20)));
    bloc.add(AppSettingsPatched((s) => s.copyWith(defaultPurchaseTaxRate: 9)));
    await finished;
    expect((await store.read())!.policy.purchaseRateBps, 900);
    await bloc.close();
  });
}
