import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/database/daos/pharmacy_dao.dart';
import 'package:tapix/core/promotions/promotion_repository.dart';
import 'package:tapix/core/promotions/promotion_return_policy.dart';
import 'package:tapix/core/promotions/promotion_engine.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/cashier_shift_service.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'package:tapix/core/services/currency_service.dart' show CurrencyService;
import 'package:tapix/core/services/feature_gate_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/domain/models/trial_balance.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/customers/data/repositories/loyalty_repository_impl.dart';
import 'package:tapix/features/sales/data/datasources/sale_local_datasource.dart';
import 'package:tapix/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:tapix/features/sales/data/services/lan_master_business_gateway.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';
import 'package:tapix/features/settings/data/services/app_settings_service.dart';

void main() {
  late AppDatabase db;
  late AppSettingsService settings;
  late LanMasterBusinessGatewayImpl gateway;
  late SaleRepositoryImpl repository;
  late CashierShiftService shiftService;
  late int productId;
  late int variantId;
  late int actorId;
  late int employeeId;
  late int currencyId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = AppSettingsService(prefs);
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();

    final accounting = AccountingRepository(db);
    final journal = JournalEntryService(accounting);
    shiftService = CashierShiftService(db);
    final adjustmentReturns = AdjustmentReturnDao(db);
    final commissions = CommissionService(db.employeeDao);
    final loyaltyRepository = LoyaltyRepositoryImpl(db, journal);
    final loyaltyPoints = LoyaltyPointsService(loyaltyRepository, journal, db);
    repository = SaleRepositoryImpl(
      SaleLocalDatasourceImpl(db.saleDao, adjustmentReturns),
      db.saleDao,
      journal,
      AuditLogService(db),
      SessionService(),
      loyaltyRepository,
      commissions,
      loyaltyPoints,
      cashierShiftService: shiftService,
    );
    gateway = LanMasterBusinessGatewayImpl(
      database: db,
      sales: repository,
      settings: settings,
      shifts: shiftService,
      currencyService: CurrencyService(prefs),
      adjustmentReturns: adjustmentReturns,
      journalEntries: journal,
      commissions: commissions,
      loyaltyPoints: loyaltyPoints,
      pharmacy: PharmacyDao(db),
      promotions: PromotionRepository(db, AuditLogService(db)),
      featureGate: _ProFeatureGate(),
    );

    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.isBase.equals(true))).getSingle();
    currencyId = currency.id;
    actorId = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'lan-cashier',
            passwordHash: 'test-only',
            role: 'cashier',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    employeeId = await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: 'Cashier Employee',
            userId: Value(actorId),
            currencyId: currency.id,
          ),
        );
    await (db.update(db.users)..where((row) => row.id.equals(actorId))).write(
      UsersCompanion(employeeId: Value(employeeId)),
    );
    await shiftService.openShift(userId: actorId, openingCashCents: 0);

    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value('LAN-LENGTH-1'),
            name: 'Measured fabric',
            costCents: Decimal.fromInt(800),
            priceCents: Decimal.fromInt(1200),
            wholesalePriceCents: Value(Decimal.fromInt(1000)),
            currencyId: Value(currency.id),
            stockQuantity: const Value(5000),
            measurementType: const Value('length'),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(5000),
            costCents: Decimal.fromInt(800),
            priceCents: Decimal.fromInt(1200),
          ),
        );
  });

  tearDown(() async {
    settings.dispose();
    await db.close();
  });

  LanRemoteUser actor() => LanRemoteUser(
    id: actorId,
    username: 'lan-cashier',
    role: 'cashier',
    employeeId: employeeId,
    employeeName: 'Cashier Employee',
    isActive: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    permissions: const ['create_sales', 'process_sales'],
  );

  test(
    'catalog exposes measured stock and never exposes product cost',
    () async {
      await CurrencyService(
        await SharedPreferences.getInstance(),
      ).setCurrency('EGP');
      final catalog = await gateway.fetchCatalog(
        query: 'fabric',
        offset: 0,
        limit: 20,
      );

      expect(catalog.products, hasLength(1));
      expect(catalog.currencyCode, 'EGP');
      expect(catalog.currencySymbol, 'E£');
      final product = catalog.products.single;
      expect(product.measurementType, 'length');
      expect(product.quantityScale, 1000);
      expect(product.stockQuantity, 5000);
      expect(product.toJson(), isNot(contains('costCents')));
    },
  );

  test(
    'remote split cheque settlement is posted atomically on the master',
    () async {
      await settings.patch(
        (current) => current.copyWith(allowPartialPayments: true),
      );
      final currency = await (db.select(
        db.currencies,
      )..where((row) => row.isBase.equals(true))).getSingle();
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'LAN cheque customer',
              currencyId: currency.id,
            ),
          );
      final request = LanSaleRequest(
        idempotencyKey: 'lan-split-cheque-sale-001',
        customerId: customerId,
        paymentMethod: 'mixed',
        paidAmountCents: 300,
        lines: [
          LanSaleLineRequest(
            productId: productId,
            variantId: variantId,
            quantity: 1000,
          ),
        ],
        payments: [
          LanCheckoutPaymentRequest(
            method: 'cheque',
            amountCents: 400,
            reference: 'LAN-CHK-400',
            bankName: 'LAN Bank',
            issueDate: DateTime(2026, 9, 7),
            dueDate: DateTime(2026, 10, 7),
          ),
          const LanCheckoutPaymentRequest(method: 'cash', amountCents: 300),
        ],
      );

      final transported = LanSaleRequest.fromJson(request.toJson());
      expect(transported.payments, hasLength(2));
      expect(transported.payments.first.reference, 'LAN-CHK-400');
      expect(transported.payments.first.dueDate, DateTime(2026, 10, 7));

      final created = await gateway.createSale(
        actor: actor(),
        request: transported,
      );
      final sale = await (db.select(
        db.sales,
      )..where((row) => row.id.equals(created.saleId))).getSingle();
      final customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();
      final payments = await (db.select(
        db.salePayments,
      )..where((row) => row.saleId.equals(created.saleId))).get();
      final cheques =
          await (db.select(db.chequeInstruments)..where(
                (row) =>
                    row.sourceTable.equals('sale') &
                    row.sourceId.equals(created.saleId),
              ))
              .get();

      expect(sale.totalCents, Decimal.fromInt(1200));
      expect(sale.paidAmountCents, Decimal.fromInt(300));
      expect(customer.balanceCents, Decimal.fromInt(900));
      expect(payments.map((payment) => payment.paymentMethod), ['cash']);
      expect(cheques, hasLength(1));
      expect(cheques.single.amountCents, Decimal.fromInt(400));
      expect(cheques.single.chequeNumber, 'LAN-CHK-400');
      expect(cheques.single.bankName, 'LAN Bank');
      expect(cheques.single.settlementPaymentId, isNull);
    },
  );

  test('catalog carries composed bundle products to remote cashiers', () async {
    await settings.patch((current) => current.copyWith(enablePromotions: true));
    final pieceProductId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value('LAN-PIECE-1'),
            name: 'Piece item',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            stockQuantity: const Value(10),
          ),
        );
    final promotions = PromotionRepository(db, AuditLogService(db));
    final promotionId = await promotions.create(
      PromotionDraft(
        code: 'LAN-COMPOSED',
        name: 'Remote composed bundle',
        type: PromotionType.quantity,
        rewardType: PromotionRewardType.percentageOff,
        productIds: [productId, pieceProductId],
        requireEachSelectedItem: true,
        minimumQuantity: 2,
        percentBps: 1000,
      ),
    );
    await promotions.setActive(promotionId, true);

    final catalog = await gateway.fetchCatalog(
      query: 'no-normal-product-match',
      offset: 0,
      limit: 20,
    );
    final transportedRule = PromotionRule.fromTransportMap(
      catalog.promotionRules.single,
    );

    expect(catalog.products, isEmpty);
    expect(
      catalog.promotionProducts.map((product) => product.id),
      containsAll([productId, pieceProductId]),
    );
    expect(
      transportedRule.qualifierScopes.map((scope) => scope.requiredQuantity),
      containsAll([1000, 1]),
    );
    expect(
      catalog.promotionProducts.every(
        (product) => !product.toJson().containsKey('costCents'),
      ),
      isTrue,
    );
  });

  test(
    'master re-evaluates retail promotion and persists exact snapshot',
    () async {
      await settings.patch(
        (current) => current.copyWith(enablePromotions: true),
      );
      final promotions = PromotionRepository(db, AuditLogService(db));
      final promotionId = await promotions.create(
        PromotionDraft(
          code: 'LAN10',
          name: 'LAN retail ten',
          type: PromotionType.simple,
          rewardType: PromotionRewardType.percentageOff,
          variantIds: [variantId],
          percentBps: 1000,
        ),
      );
      await promotions.setActive(promotionId, true);

      final catalog = await gateway.fetchCatalog(
        query: 'fabric',
        offset: 0,
        limit: 20,
      );
      expect(catalog.enablePromotions, isTrue);
      expect(catalog.promotionRules, hasLength(1));

      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-promoted-retail-sale-001',
          paymentMethod: 'cash',
          paidAmountCents: 540,
          lines: [
            LanSaleLineRequest(
              productId: productId,
              variantId: variantId,
              quantity: 500,
              priceTier: 'retail',
            ),
          ],
        ),
      );

      expect(created.totalCents, 540);
      final sale = await (db.select(
        db.sales,
      )..where((row) => row.id.equals(created.saleId))).getSingle();
      final item = await (db.select(
        db.saleItems,
      )..where((row) => row.saleId.equals(created.saleId))).getSingle();
      final application = await db
          .select(db.salePromotionApplications)
          .getSingle();
      final allocation = await db
          .select(db.saleItemPromotionAllocations)
          .getSingle();
      expect(sale.discountCents.toBigInt().toInt(), 60);
      expect(item.discountCents.toBigInt().toInt(), 60);
      expect(application.promotionId, promotionId);
      expect(application.discountCents.toBigInt().toInt(), 60);
      expect(allocation.saleItemId, item.id);
      expect(allocation.discountCents.toBigInt().toInt(), 60);
      expect(allocation.appliedQuantity, 500);
      expect(allocation.quantityScale, 1000);

      final snapshots = await promotions.loadSaleApplications(created.saleId);
      expect(snapshots, hasLength(1));
      expect(snapshots.single.name, 'LAN retail ten');
      expect(snapshots.single.discountCents, 60);
      expect(snapshots.single.allocations, hasLength(1));
      expect(snapshots.single.allocations.single.saleItemId, item.id);

      final details = await gateway.fetchSaleDetails(saleId: created.saleId);
      expect(details?.promotionApplications, hasLength(1));
      final transported = LanSaleDetails.fromJson(details!.toJson());
      expect(transported.promotionApplications.single.discountCents, 60);
      expect(
        transported.promotionApplications.single.allocations.single.saleItemId,
        item.id,
      );

      final returnable = await gateway.fetchReturnableSale(
        saleId: created.saleId,
      );
      expect(returnable?.promotionApplications, hasLength(1));
      final transportedReturnable = LanReturnableSaleDetails.fromJson(
        returnable!.toJson(),
      );
      expect(
        transportedReturnable.promotionApplications.single.name,
        'LAN retail ten',
      );
      expect(
        transportedReturnable
            .promotionApplications
            .single
            .allocations
            .single
            .saleItemId,
        item.id,
      );

      final performance = await promotions.loadPerformance(promotionId);
      expect(performance, hasLength(1));
      expect(performance.single.transactionCount, 1);
      expect(performance.single.applicationCount, 1);
      expect(performance.single.discountCents, 60);
      expect(performance.single.netSalesCents, 540);
      expect(performance.single.revenueCents, 540);
      expect(performance.single.costCents, 400);
      expect(performance.single.grossProfitCents, 140);

      // The return must consume the frozen sale-line discount even after the
      // live campaign is no longer active.
      await promotions.archive(promotionId);

      final returned = await gateway.createSaleReturn(
        actor: actor(),
        request: LanSaleReturnRequest(
          idempotencyKey: 'lan-promoted-return-001',
          saleId: created.saleId,
          dispositionType: 'restock',
          refundMethod: 'cash',
          lines: [LanSaleReturnLineRequest(saleItemId: item.id, quantity: 200)],
        ),
      );
      expect(returned.totalCents, 216);
      final returnItem = await (db.select(
        db.saleReturnItems,
      )..where((row) => row.returnId.equals(returned.returnId))).getSingle();
      expect(returnItem.subtotalCents.toBigInt().toInt(), 240);
      expect(returnItem.discountCents.toBigInt().toInt(), 24);
      expect(returnItem.refundCents.toBigInt().toInt(), 216);
      final returnDetails = await gateway.fetchSaleReturnDetails(
        returnId: returned.returnId,
        adjustment: false,
      );
      expect(returnDetails?.promotionApplications, hasLength(1));
      final transportedReturn = LanSaleReturnDetails.fromJson(
        returnDetails!.toJson(),
      );
      expect(
        transportedReturn.promotionApplications.single.name,
        'LAN retail ten',
      );
      expect(
        transportedReturn
            .promotionApplications
            .single
            .allocations
            .single
            .saleItemId,
        item.id,
      );

      final siblingColorId = await db
          .into(db.productColors)
          .insert(
            ProductColorsCompanion.insert(
              name: 'Sibling blue',
              hexCode: const Value('#0000FF'),
            ),
          );
      final siblingVariantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              sku: const Value('LAN-LENGTH-SIBLING'),
              colorId: Value(siblingColorId),
              stockQuantity: const Value(1000),
              costCents: Decimal.fromInt(800),
              priceCents: Decimal.fromInt(1200),
            ),
          );
      final siblingSale = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-sibling-variant-not-promoted-001',
          paymentMethod: 'cash',
          paidAmountCents: 600,
          lines: [
            LanSaleLineRequest(
              productId: productId,
              variantId: siblingVariantId,
              quantity: 500,
              priceTier: 'retail',
            ),
          ],
        ),
      );
      expect(siblingSale.totalCents, 600);

      final wholesale = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-non-promoted-wholesale-sale-001',
          paymentMethod: 'cash',
          paidAmountCents: 500,
          lines: [
            LanSaleLineRequest(
              productId: productId,
              variantId: variantId,
              quantity: 500,
              priceTier: 'wholesale',
            ),
          ],
        ),
      );
      expect(wholesale.totalCents, 500);
    },
  );

  test(
    'profitable free gift posts, returns, and voids without inventory drift',
    () async {
      await settings.patch(
        (current) => current.copyWith(enablePromotions: true),
      );
      final currency = await (db.select(
        db.currencies,
      )..where((row) => row.isBase.equals(true))).getSingle();
      final paidProductId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value('LAN-BOGO-PAID'),
              name: 'Paid promotion item',
              costCents: Decimal.fromInt(12000),
              priceCents: Decimal.fromInt(15000),
              currencyId: Value(currency.id),
              stockQuantity: const Value(10),
            ),
          );
      final giftProductId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value('LAN-BOGO-GIFT'),
              name: 'Gift promotion item',
              costCents: Decimal.fromInt(3000),
              priceCents: Decimal.fromInt(3000),
              currencyId: Value(currency.id),
              stockQuantity: const Value(10),
            ),
          );
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: paidProductId,
              stockQuantity: const Value(10),
              costCents: Decimal.fromInt(12000),
              priceCents: Decimal.fromInt(15000),
            ),
          );
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: giftProductId,
              stockQuantity: const Value(10),
              costCents: Decimal.fromInt(3000),
              priceCents: Decimal.fromInt(3000),
            ),
          );
      final promotions = PromotionRepository(db, AuditLogService(db));
      final promotionId = await promotions.create(
        PromotionDraft(
          code: 'LAN-BUY1-GET1',
          name: 'Profitable free gift',
          type: PromotionType.buyXGetY,
          rewardType: PromotionRewardType.freeQuantity,
          productIds: [paidProductId, giftProductId],
          minimumQuantity: 1,
          rewardQuantity: 1,
        ),
      );
      await promotions.setActive(promotionId, true);

      final accounting = AccountingRepository(db);
      final inventory = JournalLocalDatasourceImpl(db.accountingDao);
      Future<int> inventoryGap() async {
        final trialBalance = await accounting.getTrialBalance();
        final inventoryAccount = await accounting.getAccountByCode('1200');
        final matches = inventoryAccount == null
            ? const <TrialBalanceItem>[]
            : trialBalance.items
                  .where((item) => item.accountId == inventoryAccount.id)
                  .toList(growable: false);
        final glValue = matches.isEmpty
            ? 0
            : matches.single.naturalBalanceCents;
        return glValue - await inventory.getTotalInventoryValueCents();
      }

      final initialGap = await inventoryGap();
      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-profitable-free-gift-001',
          paymentMethod: 'cash',
          paidAmountCents: 15000,
          lines: [
            LanSaleLineRequest(productId: paidProductId, quantity: 1),
            LanSaleLineRequest(productId: giftProductId, quantity: 1),
          ],
        ),
      );

      expect(created.subtotalCents, 18000);
      expect(created.discountCents, 3000);
      expect(created.totalCents, 15000);
      expect(await inventoryGap(), initialGap);
      final soldItems = await (db.select(
        db.saleItems,
      )..where((row) => row.saleId.equals(created.saleId))).get();
      final soldByProduct = {
        for (final item in soldItems) item.productId: item,
      };
      expect(
        soldByProduct[paidProductId]!.discountCents.toBigInt().toInt(),
        2500,
      );
      expect(
        soldByProduct[giftProductId]!.discountCents.toBigInt().toInt(),
        500,
      );

      await expectLater(
        repository.createSaleReturn(
          saleId: created.saleId,
          currencyId: 1,
          subtotalCents: Decimal.zero,
          discountCents: Decimal.zero,
          taxCents: Decimal.zero,
          totalCents: Decimal.zero,
          dispositionType: 'restock',
          refundMethod: 'cash',
          idempotencyKey: 'local-profitable-free-gift-partial-return-001',
          actorUserId: actorId,
          items: [
            SaleReturnItemInput(
              saleItemId: soldByProduct[paidProductId]!.id,
              quantity: 1,
              subtotalCents: Decimal.zero,
              discountCents: Decimal.zero,
              taxCents: Decimal.zero,
              refundCents: Decimal.zero,
            ),
          ],
        ),
        throwsA(isA<PromotionBundleReturnException>()),
      );

      await expectLater(
        gateway.createSaleReturn(
          actor: actor(),
          request: LanSaleReturnRequest(
            idempotencyKey: 'lan-profitable-free-gift-partial-return-001',
            saleId: created.saleId,
            dispositionType: 'restock',
            refundMethod: 'cash',
            lines: [
              LanSaleReturnLineRequest(
                saleItemId: soldByProduct[paidProductId]!.id,
                quantity: 1,
              ),
            ],
          ),
        ),
        throwsA(
          isA<LanBusinessException>().having(
            (error) => error.code,
            'code',
            'promotion_bundle_return_required',
          ),
        ),
      );
      expect(
        await (db.select(
          db.saleReturns,
        )..where((row) => row.saleId.equals(created.saleId))).get(),
        isEmpty,
      );

      final returned = await gateway.createSaleReturn(
        actor: actor(),
        request: LanSaleReturnRequest(
          idempotencyKey: 'lan-profitable-free-gift-return-001',
          saleId: created.saleId,
          dispositionType: 'restock',
          refundMethod: 'cash',
          lines: soldItems
              .map(
                (item) =>
                    LanSaleReturnLineRequest(saleItemId: item.id, quantity: 1),
              )
              .toList(growable: false),
        ),
      );
      expect(returned.totalCents, 15000);
      expect(await inventoryGap(), initialGap);

      final voidable = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-profitable-free-gift-void-001',
          paymentMethod: 'cash',
          paidAmountCents: 15000,
          lines: [
            LanSaleLineRequest(productId: paidProductId, quantity: 1),
            LanSaleLineRequest(productId: giftProductId, quantity: 1),
          ],
        ),
      );
      expect(await inventoryGap(), initialGap);
      await gateway.voidSale(actor: actor(), saleId: voidable.saleId);
      expect(await inventoryGap(), initialGap);

      // Raising the paid item's recorded cost makes the exact same bundle
      // loss-making; the narrow exemption must disappear and the master must
      // retain the normal below-cost rejection.
      await (db.update(db.products)
            ..where((row) => row.id.equals(paidProductId)))
          .write(ProductsCompanion(costCents: Value(Decimal.fromInt(12500))));
      await expectLater(
        gateway.createSale(
          actor: actor(),
          request: LanSaleRequest(
            idempotencyKey: 'lan-unprofitable-free-gift-001',
            paymentMethod: 'cash',
            paidAmountCents: 15000,
            lines: [
              LanSaleLineRequest(productId: paidProductId, quantity: 1),
              LanSaleLineRequest(productId: giftProductId, quantity: 1),
            ],
          ),
        ),
        throwsA(
          isA<LanBusinessException>().having(
            (error) => error.code,
            'code',
            'sale_below_cost',
          ),
        ),
      );
    },
  );

  test(
    'pharmacy catalog searches active ingredients and returns exact alternatives',
    () async {
      await settings.patch(
        (current) => current.copyWith(enablePharmacyFeatures: true),
      );
      final pharmacy = PharmacyDao(db);
      final ingredient = await pharmacy.saveActiveIngredient(
        canonicalName: 'Ibuprofen',
        nameAr: 'إيبوبروفين',
      );
      final currency = await (db.select(
        db.currencies,
      )..where((row) => row.isBase.equals(true))).getSingle();
      final alternativeId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value('LAN-MED-ALT'),
              name: 'Equivalent medicine',
              costCents: Decimal.fromInt(700),
              priceCents: Decimal.fromInt(1100),
              currencyId: Value(currency.id),
              stockQuantity: const Value(3000),
              measurementType: const Value('length'),
            ),
          );
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: alternativeId,
              stockQuantity: const Value(3000),
              costCents: Decimal.fromInt(700),
              priceCents: Decimal.fromInt(1100),
            ),
          );
      final sourceFormula = MedicineProfileDraft(
        productId: productId,
        dosageForm: 'suspension',
        administrationRoute: 'oral',
        ingredients: [
          MedicineIngredientDraft(
            ingredientId: ingredient.id,
            value: '100',
            unit: 'mg',
            basisValue: '5',
            basisUnit: 'ml',
          ),
        ],
      );
      await pharmacy.saveMedicineProfile(sourceFormula);
      await pharmacy.saveMedicineProfile(
        MedicineProfileDraft(
          productId: alternativeId,
          dosageForm: 'suspension',
          administrationRoute: 'oral',
          ingredients: [
            MedicineIngredientDraft(
              ingredientId: ingredient.id,
              value: '20',
              unit: 'mg',
              basisValue: '1',
              basisUnit: 'ml',
            ),
          ],
        ),
      );

      final catalog = await gateway.fetchCatalog(
        query: 'ibuprofen',
        offset: 0,
        limit: 20,
      );
      expect(catalog.enablePharmacyFeatures, isTrue);
      expect(catalog.products.map((value) => value.id).toSet(), {
        productId,
        alternativeId,
      });
      expect(catalog.products.every((value) => value.medicine != null), isTrue);
      expect(
        catalog.products.every(
          (value) => !value.toJson().containsKey('costCents'),
        ),
        isTrue,
      );

      final alternatives = await gateway.fetchMedicineAlternatives(
        productId: productId,
      );
      expect(alternatives.alternatives.map((value) => value.id), [
        alternativeId,
      ]);
      expect(
        alternatives
            .alternatives
            .single
            .medicine
            ?.ingredients
            .single
            .strengthValueMicros,
        20000000,
      );
      expect(
        alternatives.alternatives.single.toJson(),
        isNot(contains('costCents')),
      );
    },
  );

  test('returnable invoice search matches a product name', () async {
    final created = await gateway.createSale(
      actor: actor(),
      request: LanSaleRequest(
        idempotencyKey: 'lan-search-sale-product-001',
        paymentMethod: 'cash',
        paidAmountCents: 600,
        lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
      ),
    );

    final page = await gateway.fetchReturnableSales(
      query: 'fabric',
      offset: 0,
      limit: 20,
    );

    expect(page.sales.map((value) => value.saleId), contains(created.saleId));
  });

  test(
    'sale details expose complete measured lines and cashier shift',
    () async {
      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-sale-details-001',
          paymentMethod: 'cash',
          paidAmountCents: 600,
          lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
        ),
      );

      final details = await gateway.fetchSaleDetails(saleId: created.saleId);

      expect(details, isNotNull);
      expect(details!.sale.invoiceNumber, created.invoiceNumber);
      expect(details.cashierName, 'Cashier Employee');
      expect(details.cashierShiftNumber, isNotEmpty);
      expect(details.lines, hasLength(1));
      expect(details.lines.single.productName, 'Measured fabric');
      expect(details.lines.single.quantity, 500);
      expect(details.lines.single.quantityScale, 1000);
      expect(details.lines.single.measurementType, 'length');
      expect(details.toJson().toString(), isNot(contains('costCents')));
    },
  );

  test('remote void reverses a sale and records the remote actor', () async {
    final created = await gateway.createSale(
      actor: actor(),
      request: LanSaleRequest(
        idempotencyKey: 'lan-sale-void-001',
        paymentMethod: 'cash',
        paidAmountCents: 600,
        lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
      ),
    );

    final result = await gateway.voidSale(
      actor: actor(),
      saleId: created.saleId,
    );

    expect(result.status, 'voided');
    final stored = await (db.select(
      db.sales,
    )..where((row) => row.id.equals(created.saleId))).getSingle();
    expect(stored.status, 'voided');
  });

  test('master PIN policy blocks remote void and returns', () async {
    await settings.patch(
      (current) => current.copyWith(requirePinForVoidRefund: true),
    );

    await expectLater(
      gateway.voidSale(actor: actor(), saleId: 999),
      throwsA(
        isA<LanBusinessException>().having(
          (error) => error.code,
          'code',
          'remote_pin_required',
        ),
      ),
    );
    await expectLater(
      gateway.createSaleAdjustmentReturn(
        actor: actor(),
        request: LanSaleAdjustmentReturnRequest(
          idempotencyKey: 'pin-protected-return-001',
          refundMethod: 'cash',
          returnDate: DateTime(2026, 8, 28),
          reasonCode: 'noReceipt',
          lines: [
            LanSaleAdjustmentReturnLineRequest(
              productId: productId,
              quantity: 500,
              unitPriceCents: 1200,
            ),
          ],
        ),
      ),
      throwsA(
        isA<LanBusinessException>().having(
          (error) => error.code,
          'code',
          'remote_pin_required',
        ),
      ),
    );
  });

  test(
    'remote adjustment return posts once and is present in the returns page',
    () async {
      const key = 'lan-adjustment-return-safe-retry-001';
      final request = LanSaleAdjustmentReturnRequest(
        idempotencyKey: key,
        refundMethod: 'cash',
        returnDate: DateTime(2026, 8, 25),
        reasonCode: 'noReceipt',
        lines: [
          LanSaleAdjustmentReturnLineRequest(
            productId: productId,
            quantity: 500,
            unitPriceCents: 1200,
          ),
        ],
      );

      final created = await gateway.createSaleAdjustmentReturn(
        actor: actor(),
        request: request,
      );
      final replayed = await gateway.createSaleAdjustmentReturn(
        actor: actor(),
        request: request,
      );

      expect(created.duplicate, isFalse);
      expect(replayed.duplicate, isTrue);
      expect(replayed.returnId, created.returnId);
      expect(created.totalCents, 600);

      final product = await (db.select(
        db.products,
      )..where((row) => row.id.equals(productId))).getSingle();
      expect(product.stockQuantity, 5500);

      final page = await gateway.fetchSaleReturns(
        query: created.returnNumber,
        offset: 0,
        limit: 20,
      );
      expect(page.returns, hasLength(1));
      expect(page.returns.single.isAdjustment, isTrue);
      expect(page.returns.single.returnNumber, created.returnNumber);
      final details = await gateway.fetchSaleReturnDetails(
        returnId: created.returnId,
        adjustment: true,
      );
      expect(details, isNotNull);
      expect(details!.summary.isAdjustment, isTrue);
      expect(details.lines.single.productName, 'Measured fabric');
      expect(details.lines.single.quantity, 500);
      expect(details.lines.single.totalCents, 600);

      final stored = await (db.select(
        db.saleReturnAdjustments,
      )..where((row) => row.idempotencyKey.equals(key))).get();
      expect(stored, hasLength(1));
      expect(stored.single.cashierShiftId, isNotNull);
    },
  );

  test('remote adjustment return preserves split cheque lifecycle', () async {
    final customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Return split customer',
            currencyId: currencyId,
          ),
        );
    await gateway.createSale(
      actor: actor(),
      request: LanSaleRequest(
        idempotencyKey: 'lan-adjustment-return-split-source-sale-001',
        customerId: customerId,
        paymentMethod: 'cash',
        paidAmountCents: 600,
        lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
      ),
    );
    final created = await gateway.createSaleAdjustmentReturn(
      actor: actor(),
      request: LanSaleAdjustmentReturnRequest(
        idempotencyKey: 'lan-adjustment-return-split-cheque-001',
        customerId: customerId,
        refundMethod: 'cheque',
        dueDate: DateTime(2026, 9, 25),
        returnDate: DateTime(2026, 8, 25),
        reasonCode: 'noReceipt',
        payments: [
          LanCheckoutPaymentRequest(
            method: 'cheque',
            amountCents: 300,
            reference: 'LAN-ADJ-CHK-300',
            dueDate: DateTime(2026, 9, 25),
          ),
          const LanCheckoutPaymentRequest(method: 'cash', amountCents: 200),
        ],
        lines: [
          LanSaleAdjustmentReturnLineRequest(
            productId: productId,
            quantity: 500,
            unitPriceCents: 1200,
          ),
        ],
      ),
    );

    final header = await (db.select(
      db.saleReturnAdjustments,
    )..where((row) => row.id.equals(created.returnId))).getSingle();
    expect(header.totalCents, Decimal.fromInt(600));
    expect(header.refundMethod, 'mixed');
    expect(header.dueDate, isNull);
    final cheque =
        await (db.select(db.chequeInstruments)..where(
              (row) =>
                  row.sourceTable.equals('sale_return_adjustment') &
                  row.sourceId.equals(created.returnId),
            ))
            .getSingle();
    expect(cheque.amountCents, Decimal.fromInt(300));
    expect(cheque.chequeNumber, 'LAN-ADJ-CHK-300');
    expect(cheque.status, 'issued');
    expect(cheque.settlementPaymentId, isNull);
    final customer = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    expect(customer.balanceCents, Decimal.fromInt(-400));
  });

  test(
    'returnable sales use both return counters and never expose cost',
    () async {
      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-returnable-measured-001',
          paymentMethod: 'cash',
          paidAmountCents: 600,
          lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
        ),
      );
      final item = await (db.select(
        db.saleItems,
      )..where((row) => row.saleId.equals(created.saleId))).getSingle();

      // The fixture product id is generated, so correct the test request if
      // seed ordering ever changes before it reaches production data.
      expect(item.productId, productId);
      await (db.update(
        db.saleItems,
      )..where((row) => row.id.equals(item.id))).write(
        const SaleItemsCompanion(
          qtyReturnedLinked: Value(200),
          qtyReturnedAdjustment: Value(100),
        ),
      );

      final page = await gateway.fetchReturnableSales(
        query: created.invoiceNumber,
        offset: 0,
        limit: 20,
      );
      expect(page.sales.single.saleId, created.saleId);
      final details = await gateway.fetchReturnableSale(saleId: created.saleId);
      expect(details, isNotNull);
      final line = details!.lines.single;
      expect(line.originalQuantity, 500);
      expect(line.returnedQuantity, 300);
      expect(line.availableQuantity, 200);
      expect(line.quantityScale, 1000);
      expect(line.measurementType, 'length');
      expect(line.toJson(), isNot(contains('costCents')));

      await (db.update(
        db.saleItems,
      )..where((row) => row.id.equals(item.id))).write(
        const SaleItemsCompanion(
          qtyReturnedLinked: Value(300),
          qtyReturnedAdjustment: Value(200),
        ),
      );
      expect(
        (await gateway.fetchReturnableSales(
          query: created.invoiceNumber,
          offset: 0,
          limit: 20,
        )).sales,
        isEmpty,
      );
      expect(await gateway.fetchReturnableSale(saleId: created.saleId), isNull);
    },
  );

  test(
    'a retried measured LAN return posts stock and accounting exactly once',
    () async {
      final sale = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-return-source-sale-001',
          paymentMethod: 'cash',
          paidAmountCents: 600,
          lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
        ),
      );
      final item = await (db.select(
        db.saleItems,
      )..where((row) => row.saleId.equals(sale.saleId))).getSingle();

      final request = LanSaleReturnRequest(
        idempotencyKey: 'lan-measured-return-safe-retry-001',
        saleId: sale.saleId,
        dispositionType: 'restock',
        refundMethod: 'cash',
        lines: [LanSaleReturnLineRequest(saleItemId: item.id, quantity: 200)],
      );

      final created = await gateway.createSaleReturn(
        actor: actor(),
        request: request,
      );
      final replayed = await gateway.createSaleReturn(
        actor: actor(),
        request: request,
      );

      expect(created.returnId, replayed.returnId);
      expect(created.duplicate, isFalse);
      expect(replayed.duplicate, isTrue);
      expect(created.totalCents, 240);
      final details = await gateway.fetchSaleReturnDetails(
        returnId: created.returnId,
        adjustment: false,
      );
      expect(details, isNotNull);
      expect(details!.summary.saleId, sale.saleId);
      expect(details.lines.single.saleItemId, item.id);
      expect(details.lines.single.quantity, 200);
      expect(details.lines.single.totalCents, 240);

      final postedItem = await (db.select(
        db.saleItems,
      )..where((row) => row.id.equals(item.id))).getSingle();
      expect(postedItem.qtyReturnedLinked, 200);
      expect(postedItem.qtyReturnedAdjustment, 0);

      final product = await (db.select(
        db.products,
      )..where((row) => row.id.equals(productId))).getSingle();
      expect(product.stockQuantity, 4700);

      final returnRows =
          await (db.select(db.saleReturns)..where(
                (row) => row.idempotencyKey.equals(request.idempotencyKey),
              ))
              .get();
      expect(returnRows, hasLength(1));
      expect(returnRows.single.cashierShiftId, isNotNull);

      final journalLines = await db
          .customSelect(
            'SELECT jl.debit_cents, jl.credit_cents '
            'FROM journal_entry_lines jl '
            'JOIN journal_entries je ON je.id = jl.journal_entry_id '
            "WHERE je.source_table = 'sale_returns' AND je.source_id = ?",
            variables: [Variable.withInt(created.returnId)],
          )
          .get();
      expect(journalLines, isNotEmpty);
      final debits = journalLines.fold<int>(
        0,
        (sum, row) => sum + row.read<int>('debit_cents'),
      );
      final credits = journalLines.fold<int>(
        0,
        (sum, row) => sum + row.read<int>('credit_cents'),
      );
      expect(debits, credits);
    },
  );

  test(
    'cashier shift and selected salesperson remain independent at wholesale',
    () async {
      final currency = await (db.select(
        db.currencies,
      )..where((row) => row.isBase.equals(true))).getSingle();
      final sellerId = await db
          .into(db.employees)
          .insert(
            EmployeesCompanion.insert(
              name: 'Independent Seller',
              currencyId: currency.id,
            ),
          );

      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-wholesale-seller-001',
          salespersonId: sellerId,
          paymentMethod: 'cash',
          paidAmountCents: 500,
          lines: [
            LanSaleLineRequest(
              productId: productId,
              quantity: 500,
              priceTier: 'wholesale',
            ),
          ],
        ),
      );

      final sale = await (db.select(
        db.sales,
      )..where((row) => row.id.equals(created.saleId))).getSingle();
      final item = await (db.select(
        db.saleItems,
      )..where((row) => row.saleId.equals(created.saleId))).getSingle();
      final shift = await shiftService.getOpenShiftForUser(actorId);

      expect(created.totalCents, 500);
      expect(sale.employeeId, sellerId);
      expect(item.employeeId, sellerId);
      expect(sale.cashierShiftId, shift!.shift.id);
      expect(sale.employeeId, isNot(employeeId));
    },
  );

  test(
    'three cashiers can own three simultaneous shifts on one master',
    () async {
      final currency = await (db.select(
        db.currencies,
      )..where((row) => row.isBase.equals(true))).getSingle();
      for (var index = 2; index <= 3; index++) {
        final userId = await db
            .into(db.users)
            .insert(
              UsersCompanion.insert(
                username: 'lan-cashier-$index',
                passwordHash: 'test-only',
                role: 'cashier',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
        final linkedEmployeeId = await db
            .into(db.employees)
            .insert(
              EmployeesCompanion.insert(
                name: 'Cashier Employee $index',
                userId: Value(userId),
                currencyId: currency.id,
              ),
            );
        await (db.update(db.users)..where((row) => row.id.equals(userId)))
            .write(UsersCompanion(employeeId: Value(linkedEmployeeId)));
        await shiftService.openShift(userId: userId, openingCashCents: 0);
      }

      final open = await shiftService.getOpenShifts();
      expect(open, hasLength(3));
      expect(
        open.map((value) => value.cashierName).toSet(),
        containsAll({
          'Cashier Employee',
          'Cashier Employee 2',
          'Cashier Employee 3',
        }),
      );
      await expectLater(
        shiftService.openShift(userId: actorId, openingCashCents: 0),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'a measured line discount is posted to the sale and item exactly',
    () async {
      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-measured-discount-001',
          paymentMethod: 'cash',
          paidAmountCents: 540,
          lines: [
            LanSaleLineRequest(
              productId: productId,
              quantity: 500,
              discountType: 'percentage',
              discountValue: 1000,
            ),
          ],
        ),
      );

      final sale = await (db.select(
        db.sales,
      )..where((row) => row.id.equals(created.saleId))).getSingle();
      final item = await (db.select(
        db.saleItems,
      )..where((row) => row.saleId.equals(created.saleId))).getSingle();

      expect(created.subtotalCents, 600);
      expect(created.discountCents, 60);
      expect(created.totalCents, 540);
      expect(sale.discountCents.toBigInt().toInt(), 60);
      expect(item.discountCents.toBigInt().toInt(), 60);
    },
  );

  test(
    'the master allows a measured item discount exactly down to cost',
    () async {
      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-discount-at-cost-001',
          paymentMethod: 'cash',
          paidAmountCents: 400,
          lines: [
            LanSaleLineRequest(
              productId: productId,
              quantity: 500,
              discountType: 'fixed',
              discountValue: 200,
            ),
          ],
        ),
      );

      expect(created.subtotalCents, 600);
      expect(created.discountCents, 200);
      expect(created.totalCents, 400);
    },
  );

  test('the master rejects a measured item discount below cost', () async {
    await expectLater(
      gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-discount-below-cost-001',
          paymentMethod: 'cash',
          paidAmountCents: 399,
          lines: [
            LanSaleLineRequest(
              productId: productId,
              quantity: 500,
              discountType: 'fixed',
              discountValue: 201,
            ),
          ],
        ),
      ),
      throwsA(
        isA<LanBusinessException>().having(
          (error) => error.code,
          'code',
          'sale_below_cost',
        ),
      ),
    );
    expect(await db.select(db.sales).get(), isEmpty);
  });

  test('the master uses variant cost for the below-cost guard', () async {
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.isBase.equals(true))).getSingle();
    final variantProductId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value('LAN-VARIANT-COST-1'),
            name: 'Variant measured fabric',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(1200),
            currencyId: Value(currency.id),
            stockQuantity: const Value(5000),
            measurementType: const Value('length'),
            hasVariants: const Value(true),
          ),
        );
    final variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: variantProductId,
            sku: const Value('LAN-VARIANT-COST-1-BLUE'),
            stockQuantity: const Value(5000),
            costCents: Decimal.fromInt(900),
            priceCents: Decimal.fromInt(1200),
          ),
        );

    await expectLater(
      gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-variant-below-cost-001',
          paymentMethod: 'cash',
          paidAmountCents: 449,
          lines: [
            LanSaleLineRequest(
              productId: variantProductId,
              variantId: variantId,
              quantity: 500,
              discountType: 'fixed',
              discountValue: 151,
            ),
          ],
        ),
      ),
      throwsA(
        isA<LanBusinessException>().having(
          (error) => error.code,
          'code',
          'sale_below_cost',
        ),
      ),
    );
    expect(await db.select(db.sales).get(), isEmpty);
  });

  test(
    'the master rejects a line discount above its configured limit',
    () async {
      await settings.patch(
        (current) => current.copyWith(maxDiscountPercent: 5),
      );

      await expectLater(
        gateway.createSale(
          actor: actor(),
          request: LanSaleRequest(
            idempotencyKey: 'lan-discount-limit-001',
            paymentMethod: 'cash',
            paidAmountCents: 540,
            lines: [
              LanSaleLineRequest(
                productId: productId,
                quantity: 500,
                discountType: 'percentage',
                discountValue: 1000,
              ),
            ],
          ),
        ),
        throwsA(
          isA<LanBusinessException>().having(
            (error) => error.code,
            'code',
            'discount_exceeds_max',
          ),
        ),
      );
      expect(await db.select(db.sales).get(), isEmpty);
    },
  );

  test(
    'customer overpayment from the original screen becomes master credit',
    () async {
      final currency = await (db.select(
        db.currencies,
      )..where((row) => row.isBase.equals(true))).getSingle();
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'LAN credit customer',
              currencyId: currency.id,
              balanceCents: Value(Decimal.zero),
            ),
          );

      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-customer-overpayment-001',
          customerId: customerId,
          paymentMethod: 'cash',
          paidAmountCents: 700,
          lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
        ),
      );

      final sale = await (db.select(
        db.sales,
      )..where((row) => row.id.equals(created.saleId))).getSingle();
      final customer = await (db.select(
        db.customers,
      )..where((row) => row.id.equals(customerId))).getSingle();

      expect(created.totalCents, 600);
      expect(created.paidAmountCents, 700);
      expect(sale.paidAmountCents.toBigInt().toInt(), 700);
      expect(customer.balanceCents.toBigInt().toInt(), -100);
    },
  );

  test(
    'a retried half-meter sale posts stock and journals exactly once',
    () async {
      const key = 'lan-real-sale-idempotency-001';
      final request = LanSaleRequest(
        idempotencyKey: key,
        paymentMethod: 'cash',
        paidAmountCents: 600,
        lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
      );

      final created = await gateway.createSale(
        actor: actor(),
        request: request,
      );
      final stockAfterFirst = await (db.select(
        db.products,
      )..where((row) => row.id.equals(productId))).getSingle();
      final journalCountAfterFirst =
          (await db.select(db.journalEntries).get()).length;

      final replayed = await gateway.createSale(
        actor: actor(),
        request: request,
      );
      final stockAfterReplay = await (db.select(
        db.products,
      )..where((row) => row.id.equals(productId))).getSingle();
      final journalCountAfterReplay =
          (await db.select(db.journalEntries).get()).length;
      final keyedSales = await (db.select(
        db.sales,
      )..where((row) => row.idempotencyKey.equals(key))).get();

      expect(created.totalCents, 600);
      expect(stockAfterFirst.stockQuantity, 4500);
      expect(replayed.saleId, created.saleId);
      expect(replayed.duplicate, isTrue);
      expect(stockAfterReplay.stockQuantity, 4500);
      expect(keyedSales, hasLength(1));
      expect(keyedSales.single.employeeId, isNull);
      expect(keyedSales.single.cashierShiftId, isNotNull);
      expect(journalCountAfterReplay, journalCountAfterFirst);
      expect(journalCountAfterFirst, greaterThan(0));
    },
  );
}

class _ProFeatureGate extends ChangeNotifier implements FeatureGateService {
  @override
  bool get isInitialized => true;

  @override
  bool get isPro => true;

  @override
  FeatureAccess canAccess(AppFeature feature) => const FeatureAccess.granted();

  @override
  bool isEnabled(AppFeature feature, {required bool settingEnabled}) =>
      settingEnabled;

  @override
  Future<void> refresh() async {}
}
