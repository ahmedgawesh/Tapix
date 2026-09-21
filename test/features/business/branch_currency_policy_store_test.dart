import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/currency_service.dart' as money;
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late BranchCurrencyPolicyStore store;
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    store = BranchCurrencyPolicyStore(db);
  });
  tearDown(() => db.close());

  test('bind is explicit and idempotent; refuses a different currency', () async {
    expect(await store.read(), null);
    final salesBefore = (await db.select(db.sales).get())
        .map((s) => s.toJson())
        .toList();
    final purchasesBefore = (await db.select(db.purchases).get())
        .map((s) => s.toJson())
        .toList();
    await store.bind('USD');
    expect((await store.read())!.code, 'USD');
    expect((await store.read())!.digits, 2);
    await store.bind('USD');
    await expectLater(store.bind('EUR'), throwsStateError);
    expect(
      (await db.select(db.sales).get()).map((s) => s.toJson()).toList(),
      salesBefore,
    );
    expect(
      (await db.select(db.purchases).get()).map((s) => s.toJson()).toList(),
      purchasesBefore,
    );
    final count = await db
        .customSelect(
          "SELECT COUNT(*) AS n FROM app_settings WHERE key LIKE 'business.currency.v1.%'",
        )
        .getSingle();
    expect(count.read<int>('n'), 1);
  });

  test(
    'display setting changes only before branch currency is bound',
    () async {
      SharedPreferences.setMockInitialValues({'currency_code': 'USD'});
      final prefs = await SharedPreferences.getInstance();
      final service = money.CurrencyService(
        prefs,
        validateCurrencyChange: store.validateDisplayCode,
      );
      await service.setCurrency('EUR');
      expect(service.getCurrency().code, 'EUR');
      await store.bind('USD');
      await service.setCurrency('USD');
      await expectLater(service.setCurrency('EUR'), throwsStateError);
      expect(service.getCurrency().code, 'USD');
    },
  );

  test('mixed historical accounting refuses binding without writes', () async {
    final other =
        (await db
                .customSelect(
                  "SELECT id FROM currencies WHERE code != 'USD' LIMIT 1",
                )
                .getSingle())
            .read<int>('id');
    await db.customStatement(
      "UPDATE sales SET currency_id = ?, status = 'completed'",
      [other],
    );
    final before = await fixtures.legacySnapshot(db);
    await expectLater(store.bind('USD'), throwsStateError);
    expect(await fixtures.legacySnapshot(db), before);
    expect(await store.read(), null);
  });

  test('posting requires a binding and matching currency', () async {
    final usd = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    await expectLater(
      store.requireCurrency(usd, requireBinding: true),
      throwsStateError,
    );
    await store.bind('USD');
    await store.requireCurrency(usd, requireBinding: true);
    await expectLater(store.requireCurrency(-1), throwsStateError);
  });

  test('corrupt binding cannot silently establish a new currency', () async {
    await store.bind('USD');
    await db.customStatement(
      "UPDATE app_settings SET value = '{}' WHERE key LIKE 'business.currency.v1.%'",
    );
    await expectLater(store.read(), throwsStateError);
    await expectLater(store.bind('USD'), throwsStateError);
  });
}
