import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/money/money.dart';
import 'package:tapix/core/promotions/promotion_engine.dart';
import 'package:tapix/core/promotions/promotion_repository.dart';
import 'package:tapix/core/services/audit_log_service.dart';

void main() {
  late AppDatabase db;
  late PromotionRepository repository;

  setUp(() {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    repository = PromotionRepository(db, AuditLogService(db));
  });

  tearDown(() => db.close());

  test(
    'creates a normalized fixed bundle atomically and loads its rule',
    () async {
      final id = await repository.create(
        const PromotionDraft(
          code: ' bundle-3 ',
          name: 'Three for 100',
          type: PromotionType.fixedBundle,
          rewardType: PromotionRewardType.fixedBundlePrice,
          priceMode: 'wholesale',
          minimumQuantity: 3,
          fixedPriceCents: 10000,
        ),
      );

      final header = await (db.select(
        db.promotions,
      )..where((row) => row.id.equals(id))).getSingle();
      final conditions = await db.select(db.promotionConditions).get();
      final scopes = await db.select(db.promotionScopes).get();
      final rewards = await db.select(db.promotionRewards).get();
      final rule = await repository.loadRule(id);

      expect(header.code, 'BUNDLE-3');
      expect(header.status, 'draft');
      expect(header.priceMode, 'wholesale');
      expect(conditions.single.minimumQuantity, 3);
      expect(scopes.single.targetType, 'all');
      expect(rewards.single.fixedPriceCents?.toBigInt().toInt(), 10000);
      expect(rule?.validate(), isEmpty);
      expect(rule?.fixedBundlePrice?.cents, 10000);
      expect(rule?.priceMode, 'wholesale');
      expect(
        (await db.select(db.auditLogs).get()).map((row) => row.action),
        contains('create'),
      );
    },
  );

  test('duplicate code rolls back without adding children', () async {
    const draft = PromotionDraft(
      code: 'SAVE10',
      name: 'Save ten',
      type: PromotionType.simple,
      rewardType: PromotionRewardType.percentageOff,
      percentBps: 1000,
    );
    await repository.create(draft);

    await expectLater(repository.create(draft), throwsStateError);

    expect(await db.select(db.promotions).get(), hasLength(1));
    expect(await db.select(db.promotionRewards).get(), hasLength(1));
    expect(await db.select(db.promotionScopes).get(), hasLength(1));
  });

  test(
    'persists a variant scope without broadening it to the product',
    () async {
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Variable product',
              costCents: Decimal.fromInt(500),
              priceCents: Decimal.fromInt(1000),
              hasVariants: const Value(true),
            ),
          );
      final variantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              sku: const Value('VAR-RED-S'),
              costCents: Decimal.fromInt(500),
              priceCents: Decimal.fromInt(1000),
              stockQuantity: const Value(4),
            ),
          );

      final promotionId = await repository.create(
        PromotionDraft(
          code: 'VARIANT10',
          name: 'Selected variant only',
          type: PromotionType.simple,
          rewardType: PromotionRewardType.percentageOff,
          variantIds: [variantId],
          percentBps: 1000,
        ),
      );

      final scopes = await (db.select(
        db.promotionScopes,
      )..where((row) => row.promotionId.equals(promotionId))).get();
      final rule = await repository.loadRule(promotionId);

      expect(scopes, hasLength(1));
      expect(scopes.single.targetType, 'variant');
      expect(scopes.single.variantId, variantId);
      expect(scopes.single.productId, isNull);
      expect(rule?.qualifierScopes.single.type, PromotionScopeType.variant);
      expect(rule?.qualifierScopes.single.targetId, variantId);
    },
  );

  test('persists each composed bundle component with its own scale', () async {
    final pieceId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Piece product',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
          ),
        );
    final lengthId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Length product',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            measurementType: const Value('length'),
          ),
        );

    final promotionId = await repository.create(
      PromotionDraft(
        code: 'MIXED-BUNDLE',
        name: 'Piece and metre',
        type: PromotionType.quantity,
        rewardType: PromotionRewardType.percentageOff,
        productIds: [pieceId, lengthId],
        requireEachSelectedItem: true,
        minimumQuantity: 2,
        percentBps: 1000,
      ),
    );
    final scopes =
        await (db.select(db.promotionScopes)
              ..where((row) => row.promotionId.equals(promotionId))
              ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
            .get();
    final rule = await repository.loadRule(promotionId);

    expect(scopes.map((row) => row.requiredQuantity), [1, 1000]);
    expect(scopes.map((row) => row.quantityScale), [1, 1000]);
    expect(
      rule?.qualifierScopes.every((scope) => scope.isRequiredComponent),
      isTrue,
    );
    expect(rule?.validate(), isEmpty);

    await repository.setActive(promotionId, true);
    final activeRule = await repository.loadRule(promotionId);
    final incomplete = PromotionEngine.evaluate(
      cart: PromotionCart(
        currencyId: 1,
        evaluatedAt: DateTime(2026, 9, 1, 12),
        lines: [
          PromotionCartLine(
            lineId: 'piece-only',
            productId: pieceId,
            quantity: 1,
            unitPrice: Money.fromCents(200),
          ),
        ],
      ),
      promotions: [activeRule!],
    );
    expect(
      incomplete.applications,
      isEmpty,
      reason: 'A composed offer must never apply before every item is present',
    );
  });

  test(
    'revision increments version, archives old row, and audits history',
    () async {
      final sourceId = await repository.create(
        const PromotionDraft(
          code: 'VERSIONED',
          name: 'Original',
          type: PromotionType.simple,
          rewardType: PromotionRewardType.percentageOff,
          percentBps: 500,
        ),
      );

      final revisedId = await repository.revise(
        sourceId,
        const PromotionDraft(
          code: 'VERSIONED',
          name: 'Revised',
          type: PromotionType.simple,
          rewardType: PromotionRewardType.percentageOff,
          percentBps: 1000,
          priority: 7,
          maxApplicationsPerTransaction: 2,
        ),
      );

      final source = await (db.select(
        db.promotions,
      )..where((row) => row.id.equals(sourceId))).getSingle();
      final revised = await (db.select(
        db.promotions,
      )..where((row) => row.id.equals(revisedId))).getSingle();
      expect(source.status, 'archived');
      expect(revised.version, 2);
      expect(revised.code, 'VERSIONED-V2');
      expect(revised.priority, 7);
      expect(revised.maxApplicationsPerTransaction, 2);
      expect(
        (await db.select(db.auditLogs).get()).map((row) => row.action),
        containsAll(['create', 'archive', 'revise']),
      );

      final copyId = await repository.duplicate(revisedId);
      final copy = await (db.select(
        db.promotions,
      )..where((row) => row.id.equals(copyId))).getSingle();
      expect(copy.status, 'draft');
      expect(copy.code, startsWith('VERSIONED-V2-COPY'));
    },
  );

  test('activation is validated and archive cannot be reactivated', () async {
    final id = await repository.create(
      const PromotionDraft(
        code: 'BUY2GET1',
        name: 'Buy two get one',
        type: PromotionType.buyXGetY,
        rewardType: PromotionRewardType.freeQuantity,
        minimumQuantity: 2,
        rewardQuantity: 1,
      ),
    );

    await repository.setActive(id, true);
    expect(
      (await (db.select(
        db.promotions,
      )..where((p) => p.id.equals(id))).getSingle()).status,
      'active',
    );

    await repository.archive(id);
    expect(
      (await db.select(db.auditLogs).get()).map((row) => row.action),
      containsAll(['create', 'activate', 'archive']),
    );
    await expectLater(repository.setActive(id, true), throwsStateError);
  });

  test('invalid definition never starts a transaction', () async {
    await expectLater(
      repository.create(
        const PromotionDraft(
          code: 'BAD',
          name: 'Invalid',
          type: PromotionType.fixedBundle,
          rewardType: PromotionRewardType.fixedBundlePrice,
          minimumQuantity: 0,
          fixedPriceCents: 100,
        ),
      ),
      throwsArgumentError,
    );
    expect(await db.select(db.promotions).get(), isEmpty);
    expect(await db.select(db.promotionRewards).get(), isEmpty);
  });

  test('permanently deletes an unused promotion and its definition', () async {
    final promotionId = await repository.create(
      const PromotionDraft(
        code: 'UNUSED-DELETE',
        name: 'Unused promotion',
        type: PromotionType.simple,
        rewardType: PromotionRewardType.percentageOff,
        percentBps: 500,
      ),
    );

    await repository.deleteUnused(promotionId);

    expect(
      await (db.select(
        db.promotions,
      )..where((row) => row.id.equals(promotionId))).getSingleOrNull(),
      isNull,
    );
    expect(
      await (db.select(
        db.promotionScopes,
      )..where((row) => row.promotionId.equals(promotionId))).get(),
      isEmpty,
    );
    expect(
      (await db.select(db.auditLogs).get()).map((row) => row.action),
      contains('delete'),
    );
  });

  test('refuses to delete a promotion referenced by an invoice', () async {
    final promotionId = await repository.create(
      const PromotionDraft(
        code: 'USED-DELETE',
        name: 'Used promotion',
        type: PromotionType.simple,
        rewardType: PromotionRewardType.percentageOff,
        percentBps: 500,
      ),
    );
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.isBase.equals(true))).getSingle();
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'USED-PROMOTION-1',
            subtotalCents: Decimal.fromInt(1000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(900),
            discountCents: Value(Decimal.fromInt(100)),
            currencyId: currency.id,
            paymentMethod: 'cash',
          ),
        );
    await db
        .into(db.salePromotionApplications)
        .insert(
          SalePromotionApplicationsCompanion.insert(
            saleId: saleId,
            promotionId: promotionId,
            promotionCode: 'USED-DELETE',
            promotionName: 'Used promotion',
            promotionVersion: 1,
            promotionType: 'simple',
            concurrencyMode: 'best_price',
            discountCents: Decimal.fromInt(100),
            promotionEngineVersion: 'test',
            calculationSnapshotJson: '{}',
          ),
        );

    await expectLater(
      repository.deleteUnused(promotionId),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'promotion_used',
        ),
      ),
    );
    expect(
      await (db.select(
        db.promotions,
      )..where((row) => row.id.equals(promotionId))).getSingleOrNull(),
      isNotNull,
    );
  });

  test(
    'usage report attributes only promoted lines and nets returned quantity',
    () async {
      final promotionId = await repository.create(
        const PromotionDraft(
          code: 'REPORT10',
          name: 'Report offer',
          type: PromotionType.simple,
          rewardType: PromotionRewardType.percentageOff,
          percentBps: 1000,
        ),
      );
      final currency = await (db.select(
        db.currencies,
      )..where((row) => row.isBase.equals(true))).getSingle();
      final promotedProductId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Promoted line',
              costCents: Decimal.fromInt(600),
              priceCents: Decimal.fromInt(1000),
            ),
          );
      final unrelatedProductId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Unrelated expensive line',
              costCents: Decimal.fromInt(9000),
              priceCents: Decimal.fromInt(10000),
            ),
          );
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'PROMO-REPORT-1',
              subtotalCents: Decimal.fromInt(12000),
              discountCents: Value(Decimal.fromInt(200)),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(11800),
              currencyId: currency.id,
              paymentMethod: 'cash',
              saleDate: Value(DateTime(2026, 9, 1, 10)),
            ),
          );
      final promotedSaleItemId = await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: promotedProductId,
              quantity: 2,
              unitPriceCents: Decimal.fromInt(1000),
              subtotalCents: Decimal.fromInt(2000),
              discountCents: Value(Decimal.fromInt(200)),
              taxCents: Value(Decimal.zero),
              totalCents: Decimal.fromInt(1800),
              costCents: Value(Decimal.fromInt(600)),
              inventoryValueAtPostCents: Value(Decimal.fromInt(1200)),
              qtyReturnedLinked: const Value(1),
            ),
          );
      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: unrelatedProductId,
              quantity: 1,
              unitPriceCents: Decimal.fromInt(10000),
              subtotalCents: Decimal.fromInt(10000),
              totalCents: Decimal.fromInt(10000),
              costCents: Value(Decimal.fromInt(9000)),
              inventoryValueAtPostCents: Value(Decimal.fromInt(9000)),
            ),
          );
      final applicationId = await db
          .into(db.salePromotionApplications)
          .insert(
            SalePromotionApplicationsCompanion.insert(
              saleId: saleId,
              promotionId: promotionId,
              promotionCode: 'REPORT10',
              promotionName: 'Report offer',
              promotionVersion: 1,
              promotionType: 'simple',
              concurrencyMode: 'best_price',
              applicationCount: const Value(1),
              discountCents: Decimal.fromInt(200),
              promotionEngineVersion: 'test',
              calculationSnapshotJson: '{}',
            ),
          );
      await db
          .into(db.saleItemPromotionAllocations)
          .insert(
            SaleItemPromotionAllocationsCompanion.insert(
              applicationId: applicationId,
              saleItemId: promotedSaleItemId,
              discountCents: Decimal.fromInt(200),
              appliedQuantity: 2,
              originalUnitPriceCents: Decimal.fromInt(1000),
              rewardType: 'percentage_off',
            ),
          );

      final rows = await repository.loadUsageReport(
        from: DateTime(2026, 9, 1),
        toExclusive: DateTime(2026, 9, 2),
      );
      final row = rows.single;
      expect(row.transactionCount, 1);
      expect(row.applicationCount, 1);
      expect(row.grossSalesCents, 2000);
      expect(row.returnedGrossSalesCents, 1000);
      expect(row.netDiscountCents, 100);
      expect(row.netCostCents, 600);
      expect(row.netSalesCents, 900);
      expect(row.grossProfitCents, 300);

      final invoices = await repository.loadUsageInvoices(
        promotionId: promotionId,
        currencyId: currency.id,
        from: DateTime(2026, 9, 1),
        toExclusive: DateTime(2026, 9, 2),
      );
      expect(invoices.single.invoiceNumber, 'PROMO-REPORT-1');
      expect(invoices.single.netSalesCents, 900);
      expect(invoices.single.grossProfitCents, 300);
    },
  );
}
