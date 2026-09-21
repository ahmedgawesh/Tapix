import 'package:uuid/uuid.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_tax_policy.dart';
import 'package:tapix/core/services/business/branch_tax_policy_store.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart'
    as legacy;

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late BranchTaxPolicyStore store;
  const original = legacy.AppSettings(
    enableTaxCalculations: false,
    defaultSalesTaxRate: 14.5,
    defaultPurchaseTaxRate: 7.25,
    taxInclusivePricing: true,
    taxRegistrationNumber: '  REG-001  ',
  );
  BranchTaxPolicy changed() => BranchTaxPolicy(
    enabled: true,
    salesRateBps: 2000,
    purchaseRateBps: 1000,
    inclusivePricing: false,
    registrationNumber: 'REG-002',
  );
  Future<List<AppSetting>> policyRows() => (db.select(
    db.appSettings,
  )..where((s) => s.key.like('business.tax%'))).get();
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    store = BranchTaxPolicyStore(db);
  });
  tearDown(() => db.close());

  test('reading never silently adopts device defaults', () async {
    expect(await store.read(), isNull);
    expect(await policyRows(), isEmpty);
  });

  test(
    'explicit adoption preserves effective settings and financial data',
    () async {
      final before = await fixtures.legacySnapshot(db)
        ..remove('app_settings');
      final first = await store.initializeFromLegacy(original);
      expect(first.revision, 1);
      expect(first.policy.toJson(), {
        'enabled': false,
        'salesRateBps': 1450,
        'purchaseRateBps': 725,
        'inclusivePricing': true,
        'registrationNumber': '  REG-001  ',
      });
      final after = await fixtures.legacySnapshot(db)
        ..remove('app_settings');
      expect(after, before);
      final existing = await store.initializeFromLegacy(
        const legacy.AppSettings(),
      );
      expect(existing.policy.toJson(), first.policy.toJson());
      expect(await policyRows(), hasLength(2));
    },
  );

  test(
    'update preserves prior revision and rejects stale preview and writer',
    () async {
      final first = await store.initializeFromLegacy(original);
      final oldRows = await policyRows();
      final second = await store.update(expected: first, policy: changed());
      expect(second.revision, 2);
      expect((await store.read())!.policy.toJson(), changed().toJson());
      final history = oldRows.singleWhere((r) => r.key.endsWith('.revision.1'));
      expect(
        (await (db.select(
          db.appSettings,
        )..where((r) => r.key.equals(history.key))).getSingle()).value,
        history.value,
      );
      await expectLater(store.assertCurrent(first), throwsStateError);
      await expectLater(
        store.update(expected: first, policy: changed()),
        throwsStateError,
      );
      await store.assertCurrent(second);
      expect(await policyRows(), hasLength(3));
    },
  );

  test('unchanged policy does not create a revision', () async {
    final first = await store.initializeFromLegacy(original);
    final next = await store.update(
      expected: first,
      policy: BranchTaxPolicy.fromLegacy(original),
    );
    expect(next.revision, 1);
    expect(await policyRows(), hasLength(2));
  });

  test('concurrent edits cannot silently overwrite each other', () async {
    final first = await store.initializeFromLegacy(original);
    final results = await Future.wait(
      [
        store.update(expected: first, policy: changed()),
        store.update(
          expected: first,
          policy: BranchTaxPolicy.fromLegacy(
            original.copyWith(defaultSalesTaxRate: 5),
          ),
        ),
      ].map((f) => f.then<Object>((v) => v, onError: (Object e) => e)),
    );
    expect(results.whereType<BranchTaxPolicySnapshot>(), hasLength(1));
    expect(results.whereType<StateError>(), hasLength(1));
    expect((await store.read())!.revision, 2);
    expect(await policyRows(), hasLength(3));
  });

  test('failed initial head write rolls back the revision too', () async {
    await db.customStatement("""
      CREATE TRIGGER reject_tax_head BEFORE INSERT ON app_settings
      WHEN NEW.key LIKE 'business.tax%.head'
      BEGIN SELECT RAISE(ABORT, 'injected head failure'); END
    """);
    await expectLater(store.initializeFromLegacy(original), throwsA(anything));
    expect(await policyRows(), isEmpty);
    await db.customStatement('DROP TRIGGER reject_tax_head');
    expect((await store.initializeFromLegacy(original)).revision, 1);
  });

  test(
    'failed head update retains previous policy and no orphan revision',
    () async {
      final first = await store.initializeFromLegacy(original);
      final before = await policyRows();
      await db.customStatement("""
      CREATE TRIGGER reject_tax_update BEFORE UPDATE ON app_settings
      WHEN NEW.key LIKE 'business.tax%.head'
      BEGIN SELECT RAISE(ABORT, 'injected update failure'); END
    """);
      await expectLater(
        store.update(expected: first, policy: changed()),
        throwsA(anything),
      );
      expect(await policyRows(), before);
      await store.assertCurrent(first);
    },
  );

  test(
    'a stale policy check rolls back changes in the posting transaction',
    () async {
      final first = await store.initializeFromLegacy(original);
      await store.update(expected: first, policy: changed());
      await expectLater(
        db.transaction(() async {
          await db
              .into(db.appSettings)
              .insert(
                AppSettingsCompanion.insert(
                  key: 'test.posting.marker',
                  value: 'must roll back',
                ),
              );
          await store.assertCurrent(first);
        }),
        throwsStateError,
      );
      expect(
        await (db.select(
          db.appSettings,
        )..where((r) => r.key.equals('test.posting.marker'))).get(),
        isEmpty,
      );
    },
  );

  test('another database cannot use a preview token', () async {
    final first = await store.initializeFromLegacy(original);
    final other = fixtures.memoryDb();
    try {
      final otherStore = BranchTaxPolicyStore(other);
      await otherStore.initializeFromLegacy(original);
      await expectLater(otherStore.assertCurrent(first), throwsStateError);
      await expectLater(
        otherStore.update(expected: first, policy: changed()),
        throwsStateError,
      );
      expect((await otherStore.read())!.revision, 1);
    } finally {
      await other.close();
    }
  });

  test(
    'corrupt or foreign policy is rejected without resetting settings',
    () async {
      await store.initializeFromLegacy(original);
      final head = (await policyRows()).singleWhere(
        (r) => r.key.endsWith('.head'),
      );
      final bad = jsonDecode(head.value) as Map<String, dynamic>;
      bad['branchId'] = 'foreign-branch';
      await (db.update(db.appSettings)..where((r) => r.id.equals(head.id)))
          .write(AppSettingsCompanion(value: Value(jsonEncode(bad))));
      await expectLater(store.read(), throwsFormatException);
      await expectLater(
        store.initializeFromLegacy(const legacy.AppSettings()),
        throwsFormatException,
      );
      expect(await policyRows(), hasLength(2));
    },
  );

  test('missing history and orphan history are rejected', () async {
    final first = await store.initializeFromLegacy(original);
    final rows = await policyRows();
    final history = rows.singleWhere((r) => r.key.endsWith('.revision.1'));
    await (db.delete(
      db.appSettings,
    )..where((r) => r.id.equals(history.id))).go();
    await expectLater(store.assertCurrent(first), throwsStateError);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(key: history.key, value: history.value),
        );
    await (db.delete(db.appSettings)..where(
          (r) => r.key.equals(
            rows.singleWhere((r) => r.key.endsWith('.head')).key,
          ),
        ))
        .go();
    await expectLater(store.initializeFromLegacy(original), throwsStateError);
  });

  test('inactive local branch refuses policy access', () async {
    final first = await store.initializeFromLegacy(original);
    await (db.update(db.businessBranches)
          ..where((b) => b.id.equals(first.branchId)))
        .write(const BusinessBranchesCompanion(isActive: Value(false)));
    await expectLater(store.read(), throwsStateError);
    await expectLater(
      store.update(expected: first, policy: changed()),
      throwsStateError,
    );
  });

  test('selecting a second warehouse keeps the same branch policy', () async {
    final first = await store.initializeFromLegacy(original);
    final other = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: other,
            organizationId: first.organizationId,
            branchId: first.branchId,
            code: 'TAX-SECOND',
          ),
        );
    final scope = await WarehouseOperationScope.resolve(db, warehouseId: other);
    expect(scope.isPrimary, isFalse);
    expect(scope.branchId, first.branchId);
    await store.assertCurrent(first);
    expect((await store.read())!.policy.toJson(), first.policy.toJson());
    expect(await policyRows(), hasLength(2));
  });

  test(
    'similarly named unrelated settings do not count as policy history',
    () async {
      final branch =
          (await db.select(db.businessContexts).getSingle()).branchId;
      final key = 'business.taxXpolicy.v1.$branch.revision.1';
      await db
          .into(db.appSettings)
          .insert(AppSettingsCompanion.insert(key: key, value: 'unrelated'));
      expect(await store.read(), isNull);
      await store.initializeFromLegacy(original);
      expect(
        (await (db.select(
          db.appSettings,
        )..where((r) => r.key.equals(key))).getSingle()).value,
        'unrelated',
      );
    },
  );

  test('invalid legacy rates cannot leave a partial policy', () async {
    for (final rate in [double.nan, double.infinity, -1.0]) {
      await expectLater(
        store.initializeFromLegacy(
          original.copyWith(defaultSalesTaxRate: rate),
        ),
        throwsArgumentError,
      );
    }
    expect(await policyRows(), isEmpty);
    expect(
      () => BranchTaxPolicy.fromJson({'enabled': true}),
      throwsFormatException,
    );
    expect(
      () => BranchTaxPolicy.fromJson({
        ...changed().toJson(),
        'salesRateBps': 20.5,
      }),
      throwsFormatException,
    );
  });

  test(
    'policy and history survive closing and reopening the database file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tapix-tax-policy-',
      );
      final file = File('${directory.path}/business.db');
      final firstDb = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      var firstClosed = false;
      try {
        final firstStore = BranchTaxPolicyStore(firstDb);
        final first = await firstStore.initializeFromLegacy(original);
        final latest = await firstStore.update(
          expected: first,
          policy: changed(),
        );
        await firstDb.close();
        firstClosed = true;
        final reopened = AppDatabase.connect(
          DatabaseConnection(NativeDatabase(file)),
        );
        try {
          final reloaded = (await BranchTaxPolicyStore(reopened).read())!;
          expect(reloaded.branchId, latest.branchId);
          expect(reloaded.databaseId, latest.databaseId);
          expect(reloaded.revision, 2);
          expect(reloaded.policy.toJson(), changed().toJson());
          expect(
            await reopened.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
        } finally {
          await reopened.close();
        }
      } finally {
        if (!firstClosed) await firstDb.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
