// ═══════════════════════════════════════════════════════════════════════════
// Phase 15.2 regression — Purchase adjustment return uses GROSS supplier
// reference (`last_purchase_price_cents ?? cost_cents`), NOT the customer
// sell price (`price_cents`).
//
// Field report (2026-05-18, backup `tapix_backup_20260518_061018.db`): on
// `PurchaseAdjReturnFormScreen`, variants surfaced at $150 (variant SELL
// price) and no-variant products surfaced at their SELL price too. The user
// expected the supplier-reference cost (the gross unit cost the user typed
// on the most recent purchase line), which is the same convention enforced
// by `purchase_form_screen.dart` after Phase 15.1.
//
// These tests pin the resolver inside `UnifiedReturnService.searchProducts`,
// which is the entry point shared with the in-screen `_PickerRow` (both now
// fall through `lastPurchasePriceCents ?? costCents` for purchase side).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';
import 'package:tapix/core/services/unified_return_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/customers/data/repositories/loyalty_repository_impl.dart';

void main() {
  late AppDatabase db;
  late UnifiedReturnService service;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accountingRepo = AccountingRepository(db);
    final journalService = JournalEntryService(accountingRepo);
    final adjDao = AdjustmentReturnDao(db);
    service = UnifiedReturnService(
      db,
      db.purchaseDao,
      db.saleDao,
      adjDao,
      journalService,
      CommissionService(db.employeeDao),
      LoyaltyPointsService(
        LoyaltyRepositoryImpl(db, journalService),
        journalService,
        db,
      ),
    );
    // Force DB init (triggers beforeOpen → seeds accounts + USD currency).
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Future<int> getCurrencyId() async {
    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    return usd.id;
  }

  Future<int> createNoVariantProduct({
    required String name,
    required int priceCents,
    required int costCents,
    int? lastPurchasePriceCents,
  }) async {
    final currencyId = await getCurrencyId();
    return db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: name,
            priceCents: Decimal.fromInt(priceCents),
            costCents: Decimal.fromInt(costCents),
            currencyId: Value(currencyId),
            stockQuantity: const Value(10),
            lastPurchasePriceCents: lastPurchasePriceCents == null
                ? const Value.absent()
                : Value(Decimal.fromInt(lastPurchasePriceCents)),
          ),
        );
  }

  Future<int> createVariantProduct({
    required String name,
    String? barcode,
  }) async {
    final currencyId = await getCurrencyId();
    return db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: name,
            priceCents: Decimal.fromInt(0),
            costCents: Decimal.fromInt(0),
            currencyId: Value(currencyId),
            hasVariants: const Value(true),
            barcode: Value(barcode),
          ),
        );
  }

  Future<int> createVariant(
    int productId, {
    required int priceCents,
    required int costCents,
    int? lastPurchasePriceCents,
    String? barcode,
    bool isActive = true,
    int? sizeId,
  }) async {
    return db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            priceCents: Decimal.fromInt(priceCents),
            costCents: Decimal.fromInt(costCents),
            stockQuantity: const Value(5),
            barcode: Value(barcode),
            isActive: Value(isActive),
            sizeId: Value(sizeId),
            lastPurchasePriceCents: lastPurchasePriceCents == null
                ? const Value.absent()
                : Value(Decimal.fromInt(lastPurchasePriceCents)),
          ),
        );
  }

  // ─── Tests ───────────────────────────────────────────────────────────────

  group('searchProducts — purchase side surfaces GROSS supplier reference', () {
    test('no-variant: lastPurchasePriceCents wins over costCents', () async {
      await createNoVariantProduct(
        name: 'p2 without v',
        priceCents: 19900, // customer SELL price — must NOT leak through
        costCents: 9900, // IAS-2 NET cost (post discount)
        lastPurchasePriceCents: 10000, // GROSS supplier ref
      );

      final results = await service.searchProducts(
        'p2',
        side: ReturnSide.purchase,
      );

      expect(results, hasLength(1));
      // Phase 15.2: must show the GROSS supplier reference, never sell.
      expect(results.single.lastPriceCents, 10000);
    });

    test(
      'no-variant: falls back to costCents when lastPurchasePriceCents is NULL',
      () async {
        await createNoVariantProduct(
          name: 'legacy product',
          priceCents: 19900,
          costCents: 9900,
          lastPurchasePriceCents: null, // pre-migration-10055 row
        );

        final results = await service.searchProducts(
          'legacy',
          side: ReturnSide.purchase,
        );

        expect(results, hasLength(1));
        expect(results.single.lastPriceCents, 9900);
      },
    );

    test(
      'variant: lastPurchasePriceCents wins over variant costCents',
      () async {
        final productId = await createVariantProduct(name: 'p1 with v');
        await createVariant(
          productId,
          priceCents: 15000, // variant SELL price — must NOT leak through
          costCents: 9900,
          lastPurchasePriceCents: 10000,
        );

        final results = await service.searchProducts(
          'p1',
          side: ReturnSide.purchase,
        );

        expect(results, hasLength(1));
        expect(results.single.lastPriceCents, 10000);
      },
    );

    test(
      'variant: falls back to costCents when lastPurchasePriceCents is NULL',
      () async {
        final productId = await createVariantProduct(name: 'p1 with v legacy');
        await createVariant(
          productId,
          priceCents: 15000,
          costCents: 9900,
          lastPurchasePriceCents: null,
        );

        final results = await service.searchProducts(
          'p1',
          side: ReturnSide.purchase,
        );

        expect(results, hasLength(1));
        expect(results.single.lastPriceCents, 9900);
      },
    );

    test(
      'variant + no-variant yield IDENTICAL supplier reference for same GROSS',
      () async {
        // This is the symmetry the field report demanded: when both products
        // are sourced from the supplier at the same GROSS unit cost, the
        // adjustment-return picker must NOT surface $150 for one and $99 for
        // the other.
        await createNoVariantProduct(
          name: 'p2 without v',
          priceCents: 19900,
          costCents: 9800,
          lastPurchasePriceCents: 9900,
        );
        final pid = await createVariantProduct(name: 'p1 with v');
        await createVariant(
          pid,
          priceCents: 15000,
          costCents: 9800,
          lastPurchasePriceCents: 9900,
        );

        final results = await service.searchProducts(
          '',
          side: ReturnSide.purchase,
        );

        final byName = {for (final r in results) r.productName: r};
        expect(byName['p2 without v']?.lastPriceCents, 9900);
        expect(byName['p1 with v']?.lastPriceCents, 9900);
        expect(
          byName['p2 without v']?.lastPriceCents,
          equals(byName['p1 with v']?.lastPriceCents),
        );
      },
    );
  });

  group('searchProducts — sale side keeps customer sell price', () {
    test(
      'no-variant: returns price_cents (NOT cost or last_purchase_price)',
      () async {
        await createNoVariantProduct(
          name: 'p2 without v',
          priceCents: 19900,
          costCents: 9900,
          lastPurchasePriceCents: 10000,
        );

        final results = await service.searchProducts(
          'p2',
          side: ReturnSide.sale,
        );

        expect(results, hasLength(1));
        // Sale-side semantics untouched by Phase 15.2.
        expect(results.single.lastPriceCents, 19900);
      },
    );

    test(
      'variant: returns variant price_cents (NOT cost or last_purchase_price)',
      () async {
        final pid = await createVariantProduct(name: 'p1 with v');
        await createVariant(
          pid,
          priceCents: 15000,
          costCents: 9900,
          lastPurchasePriceCents: 10000,
        );

        final results = await service.searchProducts(
          'p1',
          side: ReturnSide.sale,
        );

        expect(results, hasLength(1));
        expect(results.single.lastPriceCents, 15000);
      },
    );
  });

  group('searchProducts — variant parent barcode', () {
    test('returns every active child for explicit return selection', () async {
      final productId = await createVariantProduct(
        name: 'parent barcode product',
        barcode: 'PARENT-900',
      );
      final firstSizeId = await db
          .into(db.sizes)
          .insert(SizesCompanion.insert(name: 'First'));
      final secondSizeId = await db
          .into(db.sizes)
          .insert(SizesCompanion.insert(name: 'Second'));
      final inactiveSizeId = await db
          .into(db.sizes)
          .insert(SizesCompanion.insert(name: 'Inactive'));
      final firstId = await createVariant(
        productId,
        priceCents: 1000,
        costCents: 600,
        barcode: 'CHILD-901',
        sizeId: firstSizeId,
      );
      final secondId = await createVariant(
        productId,
        priceCents: 1200,
        costCents: 700,
        barcode: 'CHILD-902',
        sizeId: secondSizeId,
      );
      await createVariant(
        productId,
        priceCents: 1400,
        costCents: 800,
        barcode: 'CHILD-903',
        isActive: false,
        sizeId: inactiveSizeId,
      );

      final results = await service.searchProducts(
        'PARENT-900',
        side: ReturnSide.sale,
      );

      expect(
        results.map((r) => r.variantId),
        unorderedEquals([firstId, secondId]),
      );
      expect(results.every((r) => r.variantId != null), isTrue);
    });
  });
}
