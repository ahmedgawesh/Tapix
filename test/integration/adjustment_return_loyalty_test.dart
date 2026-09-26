// ════════════════════════════════════════════════════════════════════════════
// Sale ADJUSTMENT return — loyalty-point deduction + restore-on-void.
//
// Field request (Jul 2026, backup tapix_backup_20260706_005152.db, customer
// "roby"): a credit adjustment return with a selected customer must DEDUCT the
// customer's loyalty points ("طالما انا مختار العميل"), and the void must put
// them back. This pins:
//   1. post deducts base×multiplier points (default settings: ppu=1),
//   2. the deduction is capped at the customer's current balance,
//   3. void restores exactly what was deducted,
//   4. the preview (`previewAdjustmentReturnDeduction`) reports the same
//      points + the per-point value used by the form UI.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/customers/data/repositories/loyalty_repository_impl.dart';

void main() {
  late AppDatabase db;
  late AdjustmentReturnDao adjDao;
  late JournalEntryService journalService;
  late LoyaltyPointsService loyalty;

  late int currencyId;
  late int productId;
  late int variantId;
  late int customerId;

  Future<int> loyaltyBalance() async {
    final c = await (db.select(
      db.customers,
    )..where((x) => x.id.equals(customerId))).getSingle();
    return c.loyaltyPointsBalance;
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accountingRepo = AccountingRepository(db);
    journalService = JournalEntryService(accountingRepo);
    adjDao = AdjustmentReturnDao(db);
    loyalty = LoyaltyPointsService(
      LoyaltyRepositoryImpl(db, journalService),
      journalService,
      db,
    );

    await db.customSelect('SELECT 1').get();

    // Remove seeded tiers so the tier multiplier is a deterministic 1.0
    // (this test pins the base×multiplier math, not tier configuration).
    await db.delete(db.loyaltyTiers).go();

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;

    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value<String?>('LOY-TEST-001'),
            name: 'Loyalty Test Product',
            costCents: Decimal.fromInt(3000),
            priceCents: Decimal.fromInt(5000),
            currencyId: Value(currencyId),
            stockQuantity: const Value(100),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(100),
            costCents: Decimal.fromInt(3000),
            priceCents: Decimal.fromInt(5000),
          ),
        );
    customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'roby',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(135749)),
            loyaltyEnabled: const Value(true),
            loyaltyPointsBalance: const Value(500),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> createCreditReturn({required int totalCents}) {
    return adjDao.createSaleAdjReturn(
      SaleReturnAdjustmentsCompanion.insert(
        returnNumber: 'SAR-LOY-0001',
        customerId: Value(customerId),
        currencyId: currencyId,
        totalCents: Decimal.fromInt(totalCents),
        refundMethod: const Value('credit'),
      ),
      [
        SaleReturnAdjustmentItemsCompanion.insert(
          sourceResolution: const Value('unverified'),
          sourceResolutionReason: const Value('test fixture'),
          returnId: 0,
          productId: productId,
          variantId: Value(variantId),
          quantity: 1,
          unitPriceCents: Decimal.fromInt(totalCents),
          totalCents: Decimal.fromInt(totalCents),
        ),
      ],
    );
  }

  for (final entry in [('JPY', 1), ('KWD', 1000)]) {
    test(
      'adjustment loyalty preview and posting agree for ${entry.$1}',
      () async {
        final currency = await (db.select(
          db.currencies,
        )..where((c) => c.code.equals(entry.$1))).getSingleOrNull();
        final id =
            currency?.id ??
            await db
                .into(db.currencies)
                .insert(
                  CurrenciesCompanion.insert(
                    exchangeRate: Decimal.one,
                    code: entry.$1,
                    name: entry.$1,
                    symbol: entry.$1,
                  ),
                );
        await BranchCurrencyPolicyStore(db).bind(entry.$1);
        currencyId = id;
        await (db.update(db.customers)..where((c) => c.id.equals(customerId)))
            .write(CustomersCompanion(currencyId: Value(id)));
        await (db.update(db.products)..where((p) => p.id.equals(productId)))
            .write(ProductsCompanion(currencyId: Value(id)));
        final preview = await loyalty.previewAdjustmentReturnDeduction(
          customerId: customerId,
          returnTotalCents: 10 * entry.$2,
        );
        expect(preview.pointsToDeduct, 10);
        final returnId = await createCreditReturn(totalCents: 10 * entry.$2);
        await adjDao.postSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
          loyaltyPointsService: loyalty,
        );
        expect(await loyaltyBalance(), 490);
        await adjDao.voidSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
          loyaltyPointsService: loyalty,
        );
        expect(await loyaltyBalance(), 500);
      },
    );
  }

  test(
    'post deducts base points (ppu=1); void restores them exactly',
    () async {
      // $100 return, default ppu=1 → 100 base points, multiplier 1.0.
      final returnId = await createCreditReturn(totalCents: 10000);
      expect(await loyaltyBalance(), equals(500));

      await adjDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        allowOverHistory: true,
        loyaltyPointsService: loyalty,
      );

      expect(
        await loyaltyBalance(),
        equals(400),
        reason: '500 − 100 deducted for the credit adjustment return.',
      );

      // A redeem transaction keyed by the adjustment return id exists.
      final redeemed =
          await (db.select(db.loyaltyPointTransactions)..where(
                (t) =>
                    t.referenceType.equals('sale_return_adjustment') &
                    t.referenceId.equals(returnId),
              ))
              .get();
      expect(redeemed.length, equals(1));
      expect(redeemed.single.points, equals(-100));

      // Void restores exactly.
      await adjDao.voidSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        loyaltyPointsService: loyalty,
      );
      expect(
        await loyaltyBalance(),
        equals(500),
        reason: 'Void re-credits the 100 points deducted on post.',
      );
    },
  );

  test('deduction is capped at the customer current balance', () async {
    // Drain the customer to 30 points; a $100 return would compute 100 but
    // must cap at 30 (never negative).
    await (db.update(db.customers)..where((c) => c.id.equals(customerId)))
        .write(const CustomersCompanion(loyaltyPointsBalance: Value(30)));

    final returnId = await createCreditReturn(totalCents: 10000);
    await adjDao.postSaleAdjReturn(
      returnId,
      journalEntryService: journalService,
      allowOverHistory: true,
      loyaltyPointsService: loyalty,
    );

    expect(
      await loyaltyBalance(),
      equals(0),
      reason: 'Capped deduction: 30 − 30 = 0, never negative.',
    );
  });

  test('preview reports the same points + per-point value', () async {
    // Default settings: pointValueCents = 1.
    final preview = await loyalty.previewAdjustmentReturnDeduction(
      customerId: customerId,
      returnTotalCents: 10000,
    );
    expect(preview.enabled, isTrue);
    expect(preview.pointsToDeduct, equals(100));
    expect(preview.pointValueCents, equals(1));
    expect(preview.totalValueCents, equals(100));
  });

  test('no deduction when loyalty is disabled', () async {
    await db.customStatement('UPDATE loyalty_settings SET is_enabled = 0');
    final returnId = await createCreditReturn(totalCents: 10000);
    await adjDao.postSaleAdjReturn(
      returnId,
      journalEntryService: journalService,
      allowOverHistory: true,
      loyaltyPointsService: loyalty,
    );
    expect(
      await loyaltyBalance(),
      equals(500),
      reason: 'Loyalty disabled → no points deducted.',
    );
  });
}
