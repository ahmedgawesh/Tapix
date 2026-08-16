import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/products/data/datasources/variant_local_datasource.dart';
import 'package:tapix/features/products/data/repositories/product_variant_repository_impl.dart';

/// End-to-end regression suite for three linked, audit-grade invariants:
///
///   1. `writeOffAndDeleteVariant` must post a balanced Shrinkage journal
///      entry (Dr 5800 / Cr 1200) for `on_hand × cost_cents` BEFORE removing
///      or deactivating the variant row. This keeps Σ(stock × cost) ≡ 1200
///      Inventory balance after the delete — the invariant relied on by the
///      reconciliation report.
///
///   2. `JournalLocalDatasource.getTotalInventoryValueCents` must include
///      inactive (soft-deleted) variants, because their prior purchase /
///      opening-balance JEs still sit on the 1200 ledger. Excluding them
///      would produce a false-positive reconciliation mismatch whenever a
///      customer soft-deletes a product.
///
///   3. The 4100 / 5700 "return adjustment" accounts must be classified as
///      contra-accounts (4100 = expense, 5700 = revenue) so the P&L in the
///      standard reports engine nets them against COGS / Sales without a
///      code change. This is the IFRS/GAAP presentation used by QuickBooks,
///      Xero, Odoo and SAP B1.
void main() {
  late AppDatabase db;
  late InventoryAdjustmentDao adjDao;
  late JournalEntryService journal;
  late InventoryAdjustmentService service;
  late VariantLocalDatasource variantDs;
  late ProductVariantRepositoryImpl variantRepo;
  late JournalLocalDatasource journalDs;

  late int currencyId;

  Future<({int debitCents, int creditCents})> accountBalance(
    String code,
  ) async {
    final row = await db
        .customSelect(
          '''
      SELECT
        COALESCE(SUM(jel.debit_cents), 0)  AS dr,
        COALESCE(SUM(jel.credit_cents), 0) AS cr
      FROM journal_entry_lines jel
      INNER JOIN journal_entries je ON je.id = jel.journal_entry_id
      INNER JOIN accounts a         ON a.id  = jel.account_id
      WHERE a.account_code = ? AND je.status = 'posted'
      ''',
          variables: [Variable.withString(code)],
        )
        .getSingle();
    return (debitCents: row.read<int>('dr'), creditCents: row.read<int>('cr'));
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    adjDao = InventoryAdjustmentDao(db);
    final accountingRepo = AccountingRepository(db);
    journal = JournalEntryService(accountingRepo);
    service = InventoryAdjustmentService(db: db, dao: adjDao, journal: journal);

    variantDs = VariantLocalDatasourceImpl(
      db.productVariantDao,
      db.productColorDao,
      db.sizeDao,
    );
    variantRepo = ProductVariantRepositoryImpl(variantDs, service);
    journalDs = JournalLocalDatasourceImpl(db.accountingDao);

    // Force DB init (runs migrations + account seeding)
    await db.customSelect('SELECT 1').get();

    // Seed system user for audit columns
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;
  });

  tearDown(() async => db.close());

  group('Account classification (contra-accounts IFRS/GAAP)', () {
    test(
      '4100 Purchase Return Adjustment is seeded as expense (contra-COGS)',
      () async {
        final row = await db
            .customSelect(
              'SELECT account_type FROM accounts WHERE account_code = ?',
              variables: [Variable.withString('4100')],
            )
            .getSingle();
        expect(
          row.read<String>('account_type'),
          equals('expense'),
          reason:
              '4100 must net against COGS in P&L — expense type produces a '
              'negative (contra) figure when the return Dr is on AP.',
        );
      },
    );

    test(
      '5700 Sales Return Adjustment is seeded as revenue (contra-sales)',
      () async {
        final row = await db
            .customSelect(
              'SELECT account_type FROM accounts WHERE account_code = ?',
              variables: [Variable.withString('5700')],
            )
            .getSingle();
        expect(
          row.read<String>('account_type'),
          equals('revenue'),
          reason:
              '5700 must net against 4000 Sales in P&L — revenue type with a '
              'Dr balance produces a negative (contra) figure.',
        );
      },
    );
  });

  group('writeOffAndDeleteVariant — GL stays in sync', () {
    test('stock>0 → posts Shrinkage Dr 5800 / Cr 1200 for qty × cost, then '
        'soft-deletes (inventory_adjustments ref must remain)', () async {
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('WO-001'),
              name: 'WriteOff Product',
              costCents: Decimal.fromInt(2500), // $25.00
              priceCents: Decimal.fromInt(5000),
              currencyId: Value(currencyId),
              stockQuantity: const Value(40),
              hasVariants: const Value(true),
            ),
          );
      final colorId = await db
          .into(db.productColors)
          .insert(
            ProductColorsCompanion.insert(
              name: 'Red',
              hexCode: const Value('#FF0000'),
            ),
          );
      final variantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              colorId: Value(colorId),
              costCents: Decimal.fromInt(2500),
              priceCents: Decimal.fromInt(5000),
              priceAdjustmentCents: Value(Decimal.zero),
              stockQuantity: const Value(40),
            ),
          );

      final before5800 = await accountBalance('5800');
      final before1200 = await accountBalance('1200');

      final result = await variantRepo.writeOffAndDeleteVariant(
        variantId: variantId,
        reason: 'Test write-off on delete',
      );

      // The shrinkage itself creates an `inventory_adjustments` row pointing
      // at this variant, which smartDeleteVariant (correctly) counts as a
      // reference — so the row is SOFT-deleted (is_active=0). This preserves
      // the audit link from the posted JE back to the variant for reports.
      expect(
        result.wasDeleted,
        isFalse,
        reason:
            'the shrinkage row is itself a reference → soft delete to keep '
            'the audit trail reachable from reports.',
      );
      expect(result.referenceCount, greaterThanOrEqualTo(1));

      // Variant row still present but deactivated.
      final row = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.isActive, isFalse);
      expect(
        row.stockQuantity,
        equals(0),
        reason: 'shrinkage must drive on-hand to zero',
      );

      // Journal impact: Dr 5800 += 40×2500 = 100_000, Cr 1200 += 100_000
      final after5800 = await accountBalance('5800');
      final after1200 = await accountBalance('1200');
      expect(after5800.debitCents - before5800.debitCents, equals(40 * 2500));
      expect(after1200.creditCents - before1200.creditCents, equals(40 * 2500));
    });

    test(
      'stock=0 → short-circuits: no JE posted, smart-delete hard-path',
      () async {
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('WO-002'),
                name: 'Zero-stock Product',
                costCents: Decimal.fromInt(1000),
                priceCents: Decimal.fromInt(2000),
                currencyId: Value(currencyId),
                stockQuantity: const Value(0),
                hasVariants: const Value(true),
              ),
            );
        final colorId = await db
            .into(db.productColors)
            .insert(
              ProductColorsCompanion.insert(
                name: 'Blue',
                hexCode: const Value('#0000FF'),
              ),
            );
        final variantId = await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: productId,
                colorId: Value(colorId),
                costCents: Decimal.fromInt(1000),
                priceCents: Decimal.fromInt(2000),
                priceAdjustmentCents: Value(Decimal.zero),
                stockQuantity: const Value(0),
              ),
            );

        final before5800 = await accountBalance('5800');
        final before1200 = await accountBalance('1200');

        final result = await variantRepo.writeOffAndDeleteVariant(
          variantId: variantId,
          reason: 'Zero-stock path',
        );

        expect(result.wasDeleted, isTrue);

        // No journal movement: the write-off branch must be skipped entirely.
        final after5800 = await accountBalance('5800');
        final after1200 = await accountBalance('1200');
        expect(after5800.debitCents, equals(before5800.debitCents));
        expect(after1200.creditCents, equals(before1200.creditCents));
      },
    );
  });

  group('default variant lifecycle', () {
    test(
      'simple product reuses its sole dimensional row as the default',
      () async {
        final colorId = (await (db.select(
          db.productColors,
        )..where((c) => c.name.equals('Purple'))).getSingle()).id;
        final sizeId = await db
            .into(db.sizes)
            .insert(SizesCompanion.insert(name: 'Single-row size'));
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Simple dimensional product',
                sku: const Value('SIMPLE-DIM'),
                barcode: const Value('2057373895281'),
                costCents: Decimal.fromInt(700),
                priceCents: Decimal.fromInt(1200),
                currencyId: Value(currencyId),
                hasVariants: const Value(false),
              ),
            );
        final existingId = await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: productId,
                sku: const Value('SIMPLE-DIM'),
                barcode: const Value('2057373895281'),
                colorId: Value(colorId),
                sizeId: Value(sizeId),
                costCents: Decimal.fromInt(700),
                priceCents: Decimal.fromInt(1200),
              ),
            );

        final ensuredId = await variantRepo.ensureDefaultVariantForProduct(
          productId: productId,
          costCents: Decimal.fromInt(700),
          priceCents: Decimal.fromInt(1200),
          stockQuantity: 0,
        );

        expect(ensuredId, existingId);
        final rows = await (db.select(
          db.productVariants,
        )..where((v) => v.productId.equals(productId))).get();
        expect(rows, hasLength(1));
        expect(rows.single.colorId, colorId);
        expect(rows.single.sizeId, sizeId);
      },
    );

    test(
      'ensureDefaultVariantForProduct reactivates archived anonymous row',
      () async {
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Archived default product',
                costCents: Decimal.fromInt(700),
                priceCents: Decimal.fromInt(1200),
                currencyId: Value(currencyId),
                hasVariants: const Value(false),
              ),
            );
        final archivedId = await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: productId,
                costCents: Decimal.fromInt(700),
                priceCents: Decimal.fromInt(1200),
                priceAdjustmentCents: Value(Decimal.zero),
                isActive: const Value(false),
              ),
            );

        final ensuredId = await variantRepo.ensureDefaultVariantForProduct(
          productId: productId,
          costCents: Decimal.fromInt(700),
          priceCents: Decimal.fromInt(1200),
          stockQuantity: 0,
        );

        expect(ensuredId, equals(archivedId));
        final rows = await (db.select(
          db.productVariants,
        )..where((v) => v.productId.equals(productId))).get();
        expect(rows, hasLength(1));
        expect(rows.single.isActive, isTrue);
        expect(
          (await variantRepo.getDefaultVariantByProduct(productId))?.id,
          equals(archivedId),
        );
      },
    );
  });

  group('getTotalInventoryValueCents — audit-grade reconciliation', () {
    test(
      'sums Σ(stock × cost) across ALL variants (active AND inactive)',
      () async {
        final p1 = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('INV-R1'),
                name: 'Rec Product 1',
                costCents: Decimal.fromInt(1000),
                priceCents: Decimal.fromInt(2000),
                currencyId: Value(currencyId),
                hasVariants: const Value(true),
              ),
            );
        // Two distinct colors so the (product, color, size) unique index is
        // satisfied for both variants.
        final redId = await db
            .into(db.productColors)
            .insert(
              ProductColorsCompanion.insert(
                name: 'RecRed',
                hexCode: const Value('#AA0000'),
              ),
            );
        final greenId = await db
            .into(db.productColors)
            .insert(
              ProductColorsCompanion.insert(
                name: 'RecGreen',
                hexCode: const Value('#00AA00'),
              ),
            );
        // Active variant: 10 × 1000 = 10_000
        await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: p1,
                colorId: Value(redId),
                costCents: Decimal.fromInt(1000),
                priceCents: Decimal.fromInt(2000),
                priceAdjustmentCents: Value(Decimal.zero),
                stockQuantity: const Value(10),
                isActive: const Value(true),
              ),
            );
        // Inactive (soft-deleted) variant: still 5 × 1000 = 5_000 on the GL
        await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: p1,
                colorId: Value(greenId),
                costCents: Decimal.fromInt(1000),
                priceCents: Decimal.fromInt(2000),
                priceAdjustmentCents: Value(Decimal.zero),
                stockQuantity: const Value(5),
                isActive: const Value(false),
              ),
            );

        // Product without any variants: 7 × 500 = 3_500
        await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                sku: const Value<String?>('INV-R2'),
                name: 'Rec Product 2 (no variants)',
                costCents: Decimal.fromInt(500),
                priceCents: Decimal.fromInt(900),
                currencyId: Value(currencyId),
                stockQuantity: const Value(7),
                hasVariants: const Value(false),
              ),
            );

        final total = await journalDs.getTotalInventoryValueCents();
        expect(
          total,
          equals(10 * 1000 + 5 * 1000 + 7 * 500),
          reason:
              'Inactive variants must still count — their opening/purchase JE '
              'is still on the 1200 ledger. Excluding them would fire a false '
              'desync alert whenever a user soft-deletes a product.',
        );
      },
    );
  });
}
