import 'package:tapix/features/sales/presentation/bloc/sale_adj_return_form_bloc.dart';
import 'package:tapix/core/services/business/branch_tax_policy.dart';
import 'package:tapix/core/services/business/branch_tax_policy_store.dart';
import 'package:tapix/core/pricing/pricing_preview_fingerprint.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_adj_return_form_bloc.dart';
import 'package:tapix/core/database/migrations/business_warehouse_stock.dart';
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
import 'package:tapix/features/purchases/data/datasources/purchase_local_datasource.dart';
import 'package:tapix/features/purchases/data/repositories/purchase_repository_impl.dart';
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
    final purchaseRepository = PurchaseRepositoryImpl(
      PurchaseLocalDatasourceImpl(db.purchaseDao, adjustmentReturns),
      AuditLogService(db),
      SessionService(),
      journal,
      db,
    );
    gateway = LanMasterBusinessGatewayImpl(
      database: db,
      sales: repository,
      purchases: purchaseRepository,
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
      auditLog: AuditLogService(db),
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

  Future<void> expectPayloadConflict(Future<Object?> Function() action) async {
    await expectLater(
      action(),
      throwsA(
        isA<LanBusinessException>()
            .having(
              (error) => error.code,
              'code',
              'idempotency_payload_conflict',
            )
            .having((error) => error.statusCode, 'statusCode', 409),
      ),
    );
  }

  test(
    'cashier shift retries are idempotent and conflict on changed money',
    () async {
      final initial = await shiftService.getOpenShiftForUser(actorId);
      await shiftService.closeShift(
        shiftId: initial!.shift.id,
        closedByUserId: actorId,
        countedClosingCashCents: 0,
      );

      final opened = await gateway.openOwnShift(
        actor: actor(),
        openingCashCents: 12500,
        notes: 'Morning till',
      );
      final retriedOpen = await gateway.openOwnShift(
        actor: actor(),
        openingCashCents: 12500,
        notes: ' Morning till ',
      );
      expect(retriedOpen.id, opened.id);
      expect(
        () => gateway.openOwnShift(
          actor: actor(),
          openingCashCents: 12600,
          notes: 'Morning till',
        ),
        throwsA(
          isA<LanBusinessException>().having(
            (error) => error.code,
            'code',
            'shift_open_conflict',
          ),
        ),
      );

      final closed = await gateway.closeOwnShift(
        actor: actor(),
        shiftId: opened.id,
        countedCashCents: 12400,
        notes: 'Counted at logout',
      );
      final retriedClose = await gateway.closeOwnShift(
        actor: actor(),
        shiftId: opened.id,
        countedCashCents: 12400,
        notes: ' Counted at logout ',
      );
      expect(retriedClose.id, closed.id);
      expect(retriedClose.status, 'closed');
      expect(
        () => gateway.closeOwnShift(
          actor: actor(),
          shiftId: opened.id,
          countedCashCents: 12300,
          notes: 'Counted at logout',
        ),
        throwsA(
          isA<LanBusinessException>().having(
            (error) => error.code,
            'code',
            'shift_close_conflict',
          ),
        ),
      );
    },
  );

  group('configured currency identity', () {
    test(
      'checkout snapshot reads current master balances and refuses inactive customers',
      () async {
        final id = await db
            .into(db.customers)
            .insert(
              CustomersCompanion.insert(
                name: 'Checkout customer',
                currencyId: currencyId,
                balanceCents: Value(Decimal.fromInt(554101)),
                loyaltyPointsBalance: const Value(7661),
              ),
            );
        final summary = await gateway.fetchCustomerCheckout(id);
        expect(summary.balanceCents, 554101);
        expect(summary.pointsBalance, 7661);
        expect(summary.currencyId, currencyId);
        await (db.update(db.customers)..where((c) => c.id.equals(id))).write(
          CustomersCompanion(
            balanceCents: Value(Decimal.fromInt(-50)),
            loyaltyPointsBalance: const Value(3),
          ),
        );
        expect((await gateway.fetchCustomerCheckout(id)).balanceCents, -50);
        expect((await gateway.fetchCustomerCheckout(id)).pointsBalance, 3);
        await (db.update(db.customers)..where((c) => c.id.equals(id))).write(
          const CustomersCompanion(isActive: Value(false)),
        );
        await expectLater(
          gateway.fetchCustomerCheckout(id),
          throwsA(isA<LanBusinessException>()),
        );
        await expectLater(
          gateway.fetchCustomerCheckout(999999),
          throwsA(isA<LanBusinessException>()),
        );
      },
    );

    test(
      'catalog currency ID code and symbol come from the same stored currency',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('currency_code', 'EUR');
        final stored = await (db.select(
          db.currencies,
        )..where((c) => c.code.equals('EUR'))).getSingle();
        final page = await gateway.fetchCatalog(
          query: '',
          offset: 0,
          limit: 10,
        );
        expect(page.currencyId, stored.id);
        expect(page.currencyCode, stored.code);
        expect(page.currencySymbol, stored.symbol);
      },
    );

    test(
      'LAN shift and catalog preserve configured currency precision',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('currency_code', 'KWD');
        final stored = await (db.select(
          db.currencies,
        )..where((row) => row.code.equals('KWD'))).getSingleOrNull();
        if (stored == null) {
          await db
              .into(db.currencies)
              .insert(
                CurrenciesCompanion.insert(
                  code: 'KWD',
                  name: 'Kuwaiti Dinar',
                  symbol: 'د.ك',
                  exchangeRate: Decimal.fromInt(1),
                ),
              );
        }
        final initial = await shiftService.getOpenShiftForUser(actorId);
        await shiftService.closeShift(
          shiftId: initial!.shift.id,
          closedByUserId: actorId,
          countedClosingCashCents: 0,
        );

        final opened = await gateway.openOwnShift(
          actor: actor(),
          openingCashCents: 1234,
        );
        final catalog = await gateway.fetchCatalog(
          query: '',
          offset: 0,
          limit: 1,
        );

        expect(opened.currencyCode, 'KWD');
        expect(opened.currencyDecimalDigits, 3);
        expect(opened.currencySymbolAfter, isTrue);
        expect(catalog.currencyCode, 'KWD');
        expect(catalog.currencyDecimalDigits, 3);
        expect(catalog.currencySymbolAfter, isTrue);
      },
    );

    for (final missing in [false, true]) {
      test(
        'unavailable configured currency cannot silently post as base: missing=$missing',
        () async {
          final prefs = await SharedPreferences.getInstance();
          if (missing) {
            await prefs.setString('currency_code', 'EGP');
          } else {
            await (db.update(db.currencies)..where((c) => c.code.equals('USD')))
                .write(const CurrenciesCompanion(isActive: Value(false)));
          }
          final error = throwsA(
            isA<LanBusinessException>().having(
              (e) => e.code,
              'code',
              'currency_unavailable',
            ),
          );
          final sales = await db.select(db.sales).get();
          final journals = await db.select(db.journalEntries).get();
          final stock = await db.select(db.businessWarehouseStocks).get();
          await expectLater(
            gateway.fetchCatalog(query: '', offset: 0, limit: 10),
            error,
          );
          await expectLater(
            gateway.createSale(
              actor: actor(),
              request: LanSaleRequest(
                idempotencyKey: 'invalid-master-currency-$missing',
                paymentMethod: 'cash',
                paidAmountCents: 600,
                lines: [
                  LanSaleLineRequest(
                    productId: productId,
                    variantId: variantId,
                    quantity: 500,
                  ),
                ],
              ),
            ),
            error,
          );
          expect(await db.select(db.sales).get(), sales);
          expect(await db.select(db.journalEntries).get(), journals);
          expect(await db.select(db.businessWarehouseStocks).get(), stock);
        },
      );
    }
  });

  test(
    'concurrent sale retry posts one document and one stock movement',
    () async {
      const request = LanSaleRequest(
        idempotencyKey: 'concurrent-identical-sale-001',
        paymentMethod: 'cash',
        paidAmountCents: 600,
        lines: [LanSaleLineRequest(productId: 1, variantId: 1, quantity: 500)],
      );
      final before = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();

      final results = await Future.wait([
        gateway.createSale(actor: actor(), request: request),
        gateway.createSale(actor: actor(), request: request),
      ]);

      expect(results[0].saleId, results[1].saleId);
      final stored =
          await (db.select(db.sales)..where(
                (row) => row.idempotencyKey.equals(request.idempotencyKey),
              ))
              .get();
      expect(stored, hasLength(1));
      final after = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();
      expect(after.stockQuantity, before.stockQuantity - 500);
      final journalLines = await db
          .customSelect(
            'SELECT jl.debit_cents, jl.credit_cents '
            'FROM journal_entry_lines jl '
            'JOIN journal_entries je ON je.id = jl.journal_entry_id '
            "WHERE je.source_table = 'sales' AND je.source_id = ?",
            variables: [Variable.withInt(stored.single.id)],
          )
          .get();
      expect(journalLines, isNotEmpty);
      expect(
        journalLines.fold<int>(
          0,
          (sum, row) => sum + row.read<int>('debit_cents'),
        ),
        journalLines.fold<int>(
          0,
          (sum, row) => sum + row.read<int>('credit_cents'),
        ),
      );
    },
  );

  test('sale void retry returns the same terminal result once', () async {
    final created = await gateway.createSale(
      actor: actor(),
      request: LanSaleRequest(
        idempotencyKey: 'idempotent-sale-void-001',
        paymentMethod: 'cash',
        paidAmountCents: 600,
        lines: [
          LanSaleLineRequest(
            productId: productId,
            variantId: variantId,
            quantity: 500,
          ),
        ],
      ),
    );

    final first = await gateway.voidSale(
      actor: actor(),
      saleId: created.saleId,
    );
    final retried = await gateway.voidSale(
      actor: actor(),
      saleId: created.saleId,
    );

    expect(first.status, 'voided');
    expect(first.duplicate, isFalse);
    expect(retried.status, 'voided');
    expect(retried.duplicate, isTrue);
    final sale = await repository.getSaleById(created.saleId);
    expect(sale?.isVoided, isTrue);
  });

  test(
    'sale void storage failure restores journals and stock atomically',
    () async {
      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'atomic-void-regression',
          paymentMethod: 'cash',
          paidAmountCents: 600,
          lines: [
            LanSaleLineRequest(
              productId: productId,
              variantId: variantId,
              quantity: 500,
            ),
          ],
        ),
      );
      final before = await db.select(db.journalEntries).get();
      expect(before, isNotEmpty);
      await db.customStatement("""CREATE TRIGGER audit_sale_void_failure
      BEFORE UPDATE OF status ON sales WHEN NEW.status = 'voided'
      BEGIN SELECT RAISE(ABORT, 'audit injected sale void failure'); END""");
      await expectLater(
        repository.voidSale(created.saleId, actorUserId: actorId),
        throwsA(anything),
      );
      final after = await db.select(db.journalEntries).get();
      expect(
        after.map((e) => (e.id, e.status, e.isReversed)),
        before.map((e) => (e.id, e.status, e.isReversed)),
      );
      final stock = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).getSingle();
      expect(stock.stockQuantity, 4500);
      await db.customStatement('DROP TRIGGER audit_sale_void_failure');
      await repository.voidSale(created.saleId, actorUserId: actorId);
      final restored = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).getSingle();
      expect(restored.stockQuantity, 5000);
    },
  );

  test(
    'catalog exposes measured stock and never exposes product cost',
    () async {
      await settings.patch(
        (current) => current.copyWith(
          receiptHeaderText: 'Master invoice header',
          receiptFooterText: 'Master invoice footer',
        ),
      );
      await CurrencyService(
        await SharedPreferences.getInstance(),
      ).setCurrency('EGP');
      final egpId = await db
          .into(db.currencies)
          .insert(
            CurrenciesCompanion.insert(
              code: 'EGP',
              name: 'Egyptian Pound',
              symbol: 'E£',
              exchangeRate: Decimal.fromInt(1),
            ),
          );
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(currencyId: Value(egpId)));
      final catalog = await gateway.fetchCatalog(
        query: 'fabric',
        offset: 0,
        limit: 20,
      );

      expect(catalog.products, hasLength(1));
      expect(catalog.currencyId, egpId);
      expect(catalog.currencyCode, 'EGP');
      expect(catalog.currencySymbol, 'E£');
      expect(catalog.receiptHeaderText, 'Master invoice header');
      expect(catalog.receiptFooterText, 'Master invoice footer');
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
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(hasVariants: Value(true)));
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
      await db.customStatement(
        'UPDATE business_warehouse_stocks SET unit_cost_cents = 12500 '
        'WHERE variant_id IN (SELECT id FROM product_variants WHERE product_id = ?) '
        'AND warehouse_id = (SELECT warehouse_id FROM business_contexts WHERE id = 1)',
        [paidProductId],
      );
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
    'sale details expose measured lines, shift, and master receipt messages',
    () async {
      await settings.patch(
        (current) => current.copyWith(
          receiptHeaderText: 'Master reprint header',
          receiptFooterText: 'Master reprint footer',
        ),
      );
      final created = await gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-sale-details-001',
          paymentMethod: 'cash',
          paidAmountCents: 600,
          lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
        ),
      );

      expect(created.receiptHeaderText, 'Master reprint header');
      expect(created.receiptFooterText, 'Master reprint footer');

      final details = await gateway.fetchSaleDetails(saleId: created.saleId);

      expect(details, isNotNull);
      expect(details!.sale.invoiceNumber, created.invoiceNumber);
      expect(details.cashierName, 'Cashier Employee');
      expect(details.cashierShiftNumber, isNotEmpty);
      expect(details.receiptHeaderText, 'Master reprint header');
      expect(details.receiptFooterText, 'Master reprint footer');
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

  for (final kind in [
    'exclusive',
    'inclusive',
    'disabled',
    'exempt',
    'override',
  ]) {
    test('sale LAN preview refresh and explicit resubmit: $kind', () async {
      await settings.patch(
        (s) => s.copyWith(
          defaultSalesTaxRate: 20,
          enableTaxCalculations: kind != 'disabled',
          taxInclusivePricing: kind == 'inclusive',
        ),
      );
      await (db.update(
        db.products,
      )..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          isTaxable: Value(kind != 'exempt'),
          salesTaxRateBps: Value(kind == 'override' ? 1000 : 0),
        ),
      );
      final lan = _TaxCatalogLan(
        LanCatalogPage.fromJson(
          (await gateway.fetchCatalog(
            query: '',
            offset: 0,
            limit: 10,
          )).toJson(),
        ),
      );
      final sent = <LanSaleAdjustmentReturnRequest>[];
      lan.saleSubmit = (request) {
        final transported = LanSaleAdjustmentReturnRequest.fromJson(
          request.toJson(),
        );
        expect(
          transported.expectedPricingFingerprint,
          request.expectedPricingFingerprint,
        );
        sent.add(transported);
        return gateway.createSaleAdjustmentReturn(
          actor: actor(),
          request: transported,
        );
      };
      final journal = JournalEntryService(AccountingRepository(db));
      final form = SaleAdjReturnFormBloc(
        AdjustmentReturnDao(db),
        journal,
        CommissionService(db.employeeDao),
        LoyaltyPointsService(LoyaltyRepositoryImpl(db, journal), journal, db),
        SessionService(),
        lan: lan,
      );
      addTearDown(form.close);
      Future<void> event(
        SaleAdjReturnFormEvent event,
        bool Function(SaleAdjReturnFormState) ready,
      ) async {
        final changed = form.stream.firstWhere(ready);
        form.add(event);
        await changed.timeout(const Duration(seconds: 10));
      }

      await event(
        SaleAdjReturnItemAdded(
          AdjReturnLineItem(
            productId: productId,
            variantId: variantId,
            productName: 'Measured fabric',
            quantity: 1000,
            quantityScale: 1000,
            measurementType: 'length',
            unitPriceCents: 1500,
            discountCents: 200,
          ),
        ),
        (s) => s.items.length == 1,
      );
      await event(
        const SaleAdjReturnUnverifiedSourceSelected(
          0,
          'Acceptance fixture has no documented inventory source.',
        ),
        (s) =>
            s.items.single.sourceResolution ==
            AdjReturnSourceResolution.unverified,
      );
      await event(
        const SaleAdjReturnOverallDiscountChanged(100, false),
        (s) => s.overallDiscountCents == 100,
      );
      await event(
        const SaleAdjReturnReasonChanged(AdjReturnReasonCode.noReceipt),
        (s) => s.reasonCode != null,
      );
      final tax = switch (kind) {
        'inclusive' => 200,
        'disabled' || 'exempt' => 0,
        'override' => 120,
        _ => 240,
      };
      expect(form.state.totalAdjustedTaxCents, tax);
      expect(form.state.totalCents, kind == 'inclusive' ? 1200 : 1200 + tax);
      final store = BranchTaxPolicyStore(db);
      final prior = await store.initializeFromLegacy(settings.current);
      await store.update(
        expected: prior,
        policy: BranchTaxPolicy.fromLegacy(
          settings.current.copyWith(
            defaultSalesTaxRate: 30,
            enableTaxCalculations: true,
            taxInclusivePricing: kind != 'inclusive',
          ),
        ),
      );
      // The master settings cache remains old; posting must read SQL.
      lan.page = LanCatalogPage.fromJson(
        (await gateway.fetchCatalog(query: '', offset: 0, limit: 10)).toJson(),
      );
      Future<List<Object?>> financialState() async => [
        for (final table in [
          'sale_return_adjustments',
          'sale_return_adjustment_items',
          'journal_entries',
          'journal_entry_lines',
          'products',
          'product_variants',
        ])
          (await db.customSelect('SELECT * FROM $table').get())
              .map((r) => r.data)
              .toList(),
      ];
      final before = await financialState();
      await event(
        const SaleAdjReturnSubmitted(),
        (s) => !s.isSubmitting && s.error != null,
      );
      expect(form.state.error, 'returns.pricing_preview_updated');
      expect(form.state.isSuccess, isFalse);
      expect(sent.length, 1);
      expect(await financialState(), before);
      expect(form.state.items.single.discountCents, 200);
      expect(form.state.overallDiscountCents, 100);
      final accepted = form.state.totalCents;
      await event(
        const SaleAdjReturnSubmitted(),
        (s) => !s.isSubmitting && (s.isSuccess || s.error != null),
      );
      expect(form.state.isSuccess, isTrue, reason: form.state.error);
      expect(sent.length, 2);
      final result = await gateway.createSaleAdjustmentReturn(
        actor: actor(),
        request: sent.last,
      );
      expect(result.duplicate, isTrue);
      expect(result.totalCents, accepted);
      expect((await db.select(db.saleReturnAdjustments).get()).length, 1);
      final balance = await db
          .customSelect(
            'SELECT SUM(debit_cents) d, SUM(credit_cents) c '
            'FROM journal_entry_lines',
          )
          .getSingle();
      expect(balance.read<int>('d'), balance.read<int>('c'));
    });
  }

  test(
    'inclusive sale adjustment freezes the rate on the tax-exclusive base',
    () async {
      await settings.patch(
        (s) => s.copyWith(
          defaultSalesTaxRate: 20,
          defaultPurchaseTaxRate: 7,
          taxInclusivePricing: true,
        ),
      );
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(isTaxable: Value(true)));
      final result = await gateway.createSaleAdjustmentReturn(
        actor: actor(),
        request: LanSaleAdjustmentReturnRequest(
          idempotencyKey: 'sale-inclusive-tax-settings',
          refundMethod: 'cash',
          returnDate: DateTime(2026, 9, 21),
          reasonCode: 'noReceipt',
          overallDiscountCents: 100,
          lines: [
            LanSaleAdjustmentReturnLineRequest(
              productId: productId,
              variantId: variantId,
              quantity: 1000,
              unitPriceCents: 1500,
              discountCents: 200,
              sourceResolution: 'unverified',
              sourceResolutionReason:
                  'Acceptance fixture has no documented inventory source.',
            ),
          ],
        ),
      );
      expect(result.totalCents, 1200);
      final line = await (db.select(
        db.saleReturnAdjustmentItems,
      )..where((r) => r.returnId.equals(result.returnId))).getSingle();
      expect(line.taxCents, Decimal.fromInt(200));
      expect(line.taxRateBpsAtPost, 2000);
      expect(
        (await (db.select(
              db.saleReturnAdjustments,
            )..where((r) => r.id.equals(result.returnId))).getSingle())
            .taxInclusiveAtPost,
        isTrue,
      );
    },
  );

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
            sourceResolution: 'unverified',
            sourceResolutionReason:
                'Acceptance fixture has no documented inventory source.',
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
      await expectPayloadConflict(
        () => gateway.createSaleAdjustmentReturn(
          actor: actor(),
          request: LanSaleAdjustmentReturnRequest(
            idempotencyKey: key,
            refundMethod: 'cash',
            returnDate: DateTime(2026, 8, 25),
            reasonCode: 'noReceipt',
            lines: [
              LanSaleAdjustmentReturnLineRequest(
                productId: productId,
                quantity: 1000,
                unitPriceCents: 1200,
                sourceResolution: 'unverified',
                sourceResolutionReason: 'Different retry payload.',
              ),
            ],
          ),
        ),
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
            sourceResolution: 'unverified',
            sourceResolutionReason:
                'Acceptance fixture has no documented inventory source.',
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
      await expectPayloadConflict(
        () => gateway.createSaleReturn(
          actor: actor(),
          request: LanSaleReturnRequest(
            idempotencyKey: request.idempotencyKey,
            saleId: sale.saleId,
            dispositionType: 'restock',
            refundMethod: 'cash',
            lines: [
              LanSaleReturnLineRequest(saleItemId: item.id, quantity: 300),
            ],
          ),
        ),
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
    'remote linked purchase return preserves stock supplier balance and journal',
    () async {
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'LAN return supplier',
              currencyId: currencyId,
            ),
          );
      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'PI-LAN-RETURN-001',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(800),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(800),
              paidAmountCents: Value(Decimal.zero),
              currencyId: currencyId,
              status: const Value('draft'),
              paymentMethod: const Value('credit'),
            ),
          );
      final purchaseItemId = await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1000,
              unitCostCents: Decimal.fromInt(800),
              subtotalCents: Decimal.fromInt(800),
              totalCents: Decimal.fromInt(800),
            ),
          );
      await db.purchaseDao.postPurchase(purchaseId);

      final before = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();
      final returnable = await gateway.fetchReturnablePurchase(
        purchaseId: purchaseId,
      );
      expect(returnable, isNotNull);
      expect(returnable!.lines.single.availableQuantity, 1000);

      const idempotencyKey = 'lan-linked-purchase-return-001';
      final request = LanPurchaseReturnRequest(
        idempotencyKey: idempotencyKey,
        purchaseId: purchaseId,
        dispositionType: 'restock',
        refundMethod: 'credit',
        lines: [
          LanPurchaseReturnLineRequest(
            purchaseItemId: purchaseItemId,
            quantity: 500,
          ),
        ],
      );
      final created = await gateway.createPurchaseReturn(
        actor: actor(),
        request: request,
      );
      final replayed = await gateway.createPurchaseReturn(
        actor: actor(),
        request: request,
      );
      await expectPayloadConflict(
        () => gateway.createPurchaseReturn(
          actor: actor(),
          request: LanPurchaseReturnRequest(
            idempotencyKey: idempotencyKey,
            purchaseId: purchaseId,
            dispositionType: 'restock',
            refundMethod: 'credit',
            lines: [
              LanPurchaseReturnLineRequest(
                purchaseItemId: purchaseItemId,
                quantity: 400,
              ),
            ],
          ),
        ),
      );
      expect(created.duplicate, isFalse);
      expect(replayed.duplicate, isTrue);
      expect(replayed.returnId, created.returnId);
      expect(created.totalCents, 400);

      final details = await gateway.fetchPurchaseReturnDetails(
        returnId: created.returnId,
        adjustment: false,
      );
      expect(details, isNotNull);
      expect(details!.summary.purchaseNumber, 'PI-LAN-RETURN-001');
      expect(details.lines.single.quantity, 500);
      expect(details.lines.single.totalCents, 400);

      final after = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();
      expect(after.stockQuantity, before.stockQuantity - 500);
      final supplier = await (db.select(
        db.suppliers,
      )..where((row) => row.id.equals(supplierId))).getSingle();
      expect(supplier.balanceCents, Decimal.fromInt(400));

      final journalLines = await db
          .customSelect(
            'SELECT jl.debit_cents, jl.credit_cents '
            'FROM journal_entry_lines jl '
            'JOIN journal_entries je ON je.id = jl.journal_entry_id '
            "WHERE je.source_table = 'purchase_returns' AND je.source_id = ?",
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

      await gateway.voidPurchaseReturn(
        actor: actor(),
        returnId: created.returnId,
        adjustment: false,
      );
      await gateway.voidPurchaseReturn(
        actor: actor(),
        returnId: created.returnId,
        adjustment: false,
      );
      final voided = await (db.select(
        db.purchaseReturns,
      )..where((row) => row.id.equals(created.returnId))).getSingle();
      final restored = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();
      final restoredSupplier = await (db.select(
        db.suppliers,
      )..where((row) => row.id.equals(supplierId))).getSingle();
      expect(voided.status, 'voided');
      expect(restored.stockQuantity, before.stockQuantity);
      expect(restoredSupplier.balanceCents, Decimal.fromInt(800));
    },
  );

  for (final scenario in [
    (
      name: 'exclusive default',
      enabled: true,
      inclusive: false,
      taxable: true,
      rate: 0,
      tax: 240,
      total: 1440,
      savedRate: 2000,
    ),
    (
      name: 'inclusive default',
      enabled: true,
      inclusive: true,
      taxable: true,
      rate: 0,
      tax: 200,
      total: 1200,
      savedRate: 2000,
    ),
    (
      name: 'disabled',
      enabled: false,
      inclusive: false,
      taxable: true,
      rate: 1000,
      tax: 0,
      total: 1200,
      savedRate: 0,
    ),
    (
      name: 'exempt',
      enabled: true,
      inclusive: false,
      taxable: false,
      rate: 1000,
      tax: 0,
      total: 1200,
      savedRate: 0,
    ),
    (
      name: 'product override',
      enabled: true,
      inclusive: false,
      taxable: true,
      rate: 1000,
      tax: 120,
      total: 1320,
      savedRate: 1000,
    ),
  ]) {
    test('purchase adjustment uses master tax settings: ${scenario.name}', () async {
      await settings.patch(
        (s) => s.copyWith(
          enableTaxCalculations: scenario.enabled,
          defaultPurchaseTaxRate: 20,
          defaultSalesTaxRate: 30,
          taxInclusivePricing: scenario.inclusive,
        ),
      );
      await (db.update(
        db.products,
      )..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          isTaxable: Value(scenario.taxable),
          purchaseTaxRateBps: Value(scenario.rate),
        ),
      );
      final supplier = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Tax supplier',
              currencyId: currencyId,
            ),
          );
      final purchase = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'TAX-FIXTURE',
              supplierId: supplier,
              subtotalCents: Decimal.fromInt(1500),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(1500),
              currencyId: currencyId,
              status: const Value('posted'),
            ),
          );
      await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchase,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1000,
              quantityScale: const Value(1000),
              measurementType: const Value('length'),
              unitCostCents: Decimal.fromInt(1500),
              subtotalCents: Decimal.fromInt(1500),
              totalCents: Decimal.fromInt(1500),
            ),
          );
      final form = PurchaseAdjReturnFormBloc(
        AdjustmentReturnDao(db),
        JournalEntryService(AccountingRepository(db)),
        settings: settings,
      );
      final ready = form.stream.firstWhere((state) => state.items.length == 1);
      form.add(
        PurchaseAdjReturnItemAdded(
          AdjReturnLineItem(
            productId: productId,
            variantId: variantId,
            productName: 'Measured fabric',
            quantity: 1000,
            quantityScale: 1000,
            measurementType: 'length',
            unitPriceCents: 1500,
            discountCents: 200,
          ),
        ),
      );
      final state = (await ready).copyWith(overallDiscountCents: 100);
      expect(state.totalAdjustedTaxCents, scenario.tax);
      expect(state.totalCents, scenario.total);
      expect(state.taxInclusivePricing, scenario.inclusive);
      await form.close();
      final page = await gateway.fetchCatalog(query: '', offset: 0, limit: 10);
      final transported = LanCatalogPage.fromJson(
        page.toJson(includeManagement: true),
      );
      expect(transported.defaultPurchaseTaxRateBps, 2000);
      final remoteLan = _TaxCatalogLan(transported);
      final remoteForm = PurchaseAdjReturnFormBloc(
        AdjustmentReturnDao(db),
        JournalEntryService(AccountingRepository(db)),
        lan: remoteLan,
      );
      final remoteReady = remoteForm.stream.firstWhere(
        (s) => s.items.length == 1,
      );
      remoteForm.add(
        PurchaseAdjReturnItemAdded(
          AdjReturnLineItem(
            productId: productId,
            variantId: variantId,
            productName: 'Measured fabric',
            quantity: 1000,
            quantityScale: 1000,
            measurementType: 'length',
            unitPriceCents: 1500,
            discountCents: 200,
          ),
        ),
      );
      final remoteState = (await remoteReady).copyWith(
        overallDiscountCents: 100,
      );
      expect(remoteState.totalCents, state.totalCents);
      expect(remoteState.totalAdjustedTaxCents, state.totalAdjustedTaxCents);
      if (scenario.name == 'exclusive default') {
        remoteLan.page = LanCatalogPage.fromJson({
          ...transported.toJson(includeManagement: true),
          'defaultPurchaseTaxRateBps': 3000,
        });
        final selected = remoteForm.stream.firstWhere(
          (s) => s.supplierId == supplier,
        );
        remoteForm.add(PurchaseAdjReturnSupplierSelected(supplier, 'Supplier'));
        await selected;
        final reason = remoteForm.stream.firstWhere(
          (s) => s.reasonCode != null,
        );
        remoteForm.add(
          const PurchaseAdjReturnReasonChanged(AdjReturnReasonCode.noReceipt),
        );
        await reason;
        final updated = remoteForm.stream.firstWhere(
          (s) => !s.isSubmitting && s.error != null,
        );
        remoteForm.add(const PurchaseAdjReturnSubmitted());
        final refreshed = await updated;
        expect(refreshed.error, 'returns.pricing_preview_updated');
        expect(refreshed.isSuccess, isFalse);
        expect(refreshed.items.single.taxRateBps, 3000);
        expect(refreshed.items.single.discountCents, 200);
        expect(refreshed.totalAdjustedTaxCents, 390);
        expect(refreshed.totalCents, 1690);
        expect(remoteLan.requests.length, 1);
        expect(
          remoteLan.requests.single.expectedPricingFingerprint,
          pricingPreviewFingerprint(
            (await remoteReady).pricing,
            taxInclusive: false,
          ),
        );
      }
      await remoteForm.close();
      if (scenario.name == 'product override') {
        final oldJson = page.toJson(includeManagement: true)
          ..remove('defaultPurchaseTaxRateBps')
          ..['enableTaxCalculations'] = false
          ..['taxInclusivePricing'] = true;
        final oldPage = LanCatalogPage.fromJson(oldJson);
        expect(oldPage.defaultPurchaseTaxRateBps, isNull);
        final oldForm = PurchaseAdjReturnFormBloc(
          AdjustmentReturnDao(db),
          JournalEntryService(AccountingRepository(db)),
          lan: _TaxCatalogLan(oldPage),
        );
        final oldReady = oldForm.stream.firstWhere((s) => s.items.length == 1);
        oldForm.add(
          PurchaseAdjReturnItemAdded(
            AdjReturnLineItem(
              productId: productId,
              variantId: variantId,
              productName: 'Measured fabric',
              quantity: 1000,
              quantityScale: 1000,
              measurementType: 'length',
              unitPriceCents: 1500,
              discountCents: 200,
            ),
          ),
        );
        final oldState = (await oldReady).copyWith(overallDiscountCents: 100);
        expect(oldState.taxInclusivePricing, isFalse);
        expect(oldState.totalCents, 1320);
        await oldForm.close();
      }

      final request = LanPurchaseAdjustmentReturnRequest(
        idempotencyKey: 'tax-settings-${scenario.name}',
        expectedPricingFingerprint: pricingPreviewFingerprint(
          remoteState.pricing,
          taxInclusive: remoteState.taxInclusivePricing,
        ),
        supplierId: supplier,
        refundMethod: 'credit',
        returnDate: DateTime(2026, 9, 21),
        reasonCode: 'noReceipt',
        overallDiscountCents: 100,
        lines: [
          LanPurchaseAdjustmentReturnLineRequest(
            productId: productId,
            variantId: variantId,
            quantity: 1000,
            unitPriceCents: 1500,
            discountCents: 200,
          ),
        ],
      );
      Future<List<Object?>> financialState() async => [
        for (final table in [
          'purchase_return_adjustments',
          'purchase_return_adjustment_items',
          'journal_entries',
          'journal_entry_lines',
          'products',
          'product_variants',
          'suppliers',
        ])
          (await db.customSelect('SELECT * FROM $table').get())
              .map((r) => r.data)
              .toList(),
      ];
      final before = await financialState();
      final stale = LanPurchaseAdjustmentReturnRequest.fromJson({
        ...request.toJson(),
        'expectedPricingFingerprint': 'outdated-preview',
      });
      await expectLater(
        gateway.createPurchaseAdjustmentReturn(actor: actor(), request: stale),
        throwsA(
          isA<LanBusinessException>().having(
            (e) => e.code,
            'code',
            'pricing_preview_changed',
          ),
        ),
      );
      expect(await financialState(), before);
      if (scenario.name == 'exclusive default') {
        final store = BranchTaxPolicyStore(db);
        final original = await store.initializeFromLegacy(settings.current);
        final changed = await store.update(
          expected: original,
          policy: BranchTaxPolicy.fromLegacy(
            settings.current.copyWith(defaultPurchaseTaxRate: 30),
          ),
        );
        // SQL policy changed without updating the settings service cache.
        expect(settings.current.defaultPurchaseTaxRate, 20);
        await expectLater(
          gateway.createPurchaseAdjustmentReturn(
            actor: actor(),
            request: request,
          ),
          throwsA(
            isA<LanBusinessException>().having(
              (e) => e.code,
              'code',
              'pricing_preview_changed',
            ),
          ),
        );
        expect(await financialState(), before);
        await store.update(expected: changed, policy: original.policy);
      }
      final transportedRequest = LanPurchaseAdjustmentReturnRequest.fromJson(
        request.toJson(),
      );
      expect(
        transportedRequest.expectedPricingFingerprint,
        request.expectedPricingFingerprint,
      );
      final result = await gateway.createPurchaseAdjustmentReturn(
        actor: actor(),
        request: transportedRequest,
      );
      expect(result.totalCents, scenario.total);
      final header = await (db.select(
        db.purchaseReturnAdjustments,
      )..where((r) => r.id.equals(result.returnId))).getSingle();
      final line = await (db.select(
        db.purchaseReturnAdjustmentItems,
      )..where((r) => r.returnId.equals(result.returnId))).getSingle();
      expect(header.taxCents, Decimal.fromInt(scenario.tax));
      expect(header.taxInclusiveAtPost, scenario.inclusive);
      expect(line.taxRateBpsAtPost, scenario.savedRate);
      expect(line.discountCents, Decimal.fromInt(300));
      final journal = await db
          .customSelect(
            'SELECT SUM(l.debit_cents) d, SUM(l.credit_cents) c FROM journal_entry_lines l '
            'JOIN journal_entries j ON j.id = l.journal_entry_id '
            "WHERE j.source_table = 'purchase_return_adjustments' AND j.source_id = ?",
            variables: [Variable.withInt(result.returnId)],
          )
          .getSingle();
      expect(journal.read<int>('d'), journal.read<int>('c'));
      final vat = await db
          .customSelect(
            'SELECT COALESCE(SUM(l.credit_cents - l.debit_cents), 0) amount '
            'FROM journal_entry_lines l JOIN journal_entries j ON j.id = l.journal_entry_id '
            'JOIN accounts a ON a.id = l.account_id '
            "WHERE j.source_table = 'purchase_return_adjustments' AND j.source_id = ? AND a.account_code = '1300'",
            variables: [Variable.withInt(result.returnId)],
          )
          .getSingle();
      expect(vat.read<int>('amount'), scenario.tax);
      await settings.patch(
        (s) => s.copyWith(
          defaultPurchaseTaxRate: 5,
          taxInclusivePricing: !scenario.inclusive,
          enableTaxCalculations: !scenario.enabled,
        ),
      );
      final replay = await gateway.createPurchaseAdjustmentReturn(
        actor: actor(),
        request: request,
      );
      expect(replay.duplicate, isTrue);
      expect(replay.totalCents, scenario.total);
      expect(
        (await (db.select(
              db.purchaseReturnAdjustmentItems,
            )..where((r) => r.returnId.equals(result.returnId))).getSingle())
            .taxCents,
        line.taxCents,
      );
    });
  }

  test(
    'remote unlinked purchase return preserves stock supplier balance and journal',
    () async {
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'LAN adjustment return supplier',
              currencyId: currencyId,
            ),
          );
      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'PI-LAN-ADJ-HISTORY-001',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(800),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(800),
              paidAmountCents: Value(Decimal.zero),
              currencyId: currencyId,
              status: const Value('draft'),
              paymentMethod: const Value('credit'),
            ),
          );
      await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1000,
              unitCostCents: Decimal.fromInt(800),
              subtotalCents: Decimal.fromInt(800),
              totalCents: Decimal.fromInt(800),
            ),
          );
      await db.purchaseDao.postPurchase(purchaseId);
      final before = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();

      const idempotencyKey = 'lan-unlinked-purchase-return-001';
      final request = LanPurchaseAdjustmentReturnRequest(
        idempotencyKey: idempotencyKey,
        supplierId: supplierId,
        refundMethod: 'credit',
        returnDate: DateTime(2026, 9, 13),
        reasonCode: 'noReceipt',
        notes: 'Network adjustment return',
        lines: [
          LanPurchaseAdjustmentReturnLineRequest(
            productId: productId,
            variantId: variantId,
            quantity: 500,
            unitPriceCents: 800,
          ),
        ],
      );
      final created = await gateway.createPurchaseAdjustmentReturn(
        actor: actor(),
        request: request,
      );
      final replayed = await gateway.createPurchaseAdjustmentReturn(
        actor: actor(),
        request: request,
      );
      await expectPayloadConflict(
        () => gateway.createPurchaseAdjustmentReturn(
          actor: actor(),
          request: LanPurchaseAdjustmentReturnRequest(
            idempotencyKey: idempotencyKey,
            supplierId: supplierId,
            refundMethod: 'credit',
            returnDate: DateTime(2026, 9, 13),
            reasonCode: 'noReceipt',
            notes: 'Network adjustment return',
            lines: [
              LanPurchaseAdjustmentReturnLineRequest(
                productId: productId,
                variantId: variantId,
                quantity: 400,
                unitPriceCents: 800,
              ),
            ],
          ),
        ),
      );
      expect(created.duplicate, isFalse);
      expect(replayed.duplicate, isTrue);
      expect(replayed.returnId, created.returnId);
      expect(created.totalCents, 400);

      final details = await gateway.fetchPurchaseReturnDetails(
        returnId: created.returnId,
        adjustment: true,
      );
      expect(details, isNotNull);
      expect(details!.summary.isAdjustment, isTrue);
      expect(details.lines.single.quantity, 500);
      expect(details.lines.single.totalCents, 400);

      final after = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();
      expect(after.stockQuantity, before.stockQuantity - 500);
      final supplier = await (db.select(
        db.suppliers,
      )..where((row) => row.id.equals(supplierId))).getSingle();
      expect(supplier.balanceCents, Decimal.fromInt(400));

      final journalLines = await db
          .customSelect(
            'SELECT jl.debit_cents, jl.credit_cents '
            'FROM journal_entry_lines jl '
            'JOIN journal_entries je ON je.id = jl.journal_entry_id '
            "WHERE je.source_table = 'purchase_return_adjustments' AND je.source_id = ?",
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

      await gateway.voidPurchaseReturn(
        actor: actor(),
        returnId: created.returnId,
        adjustment: true,
      );
      await gateway.voidPurchaseReturn(
        actor: actor(),
        returnId: created.returnId,
        adjustment: true,
      );
      final voided = await (db.select(
        db.purchaseReturnAdjustments,
      )..where((row) => row.id.equals(created.returnId))).getSingle();
      final restored = await (db.select(
        db.productVariants,
      )..where((row) => row.id.equals(variantId))).getSingle();
      final restoredSupplier = await (db.select(
        db.suppliers,
      )..where((row) => row.id.equals(supplierId))).getSingle();
      expect(voided.status, 'voided');
      expect(restored.stockQuantity, before.stockQuantity);
      expect(restoredSupplier.balanceCents, Decimal.fromInt(800));
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
        isA<LanBusinessException>()
            .having((error) => error.code, 'code', 'sale_below_cost')
            .having(
              (error) => error.details['lineIndex'],
              'offending line index',
              0,
            )
            .having(
              (error) => error.details['productId'],
              'offending product id',
              productId,
            )
            .having(
              (error) => error.details['canOverride'],
              'cashier override',
              isFalse,
            )
            .having(
              (error) => error.details.containsKey('costCents'),
              'cost remains private',
              isFalse,
            ),
      ),
    );
    expect(await db.select(db.sales).get(), isEmpty);
  });

  test('enabled policy requires a privileged actor and audited reason while '
      'keeping revenue and COGS journals correct', () async {
    await settings.patch(
      (current) => current.copyWith(allowBelowCostSales: true),
    );
    final managerId = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'lan-manager',
            passwordHash: 'test-only',
            role: 'manager',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    final manager = LanRemoteUser(
      id: managerId,
      username: 'lan-manager',
      role: 'manager',
      isActive: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      permissions: const ['create_sales', 'process_sales'],
    );

    final requestWithoutReason = LanSaleRequest(
      idempotencyKey: 'lan-below-cost-manager-001',
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
    );
    final request = requestWithoutReason.copyWith(
      belowCostOverrideReason: 'Clear damaged seasonal stock',
    );

    await expectLater(
      gateway.createSale(
        actor: actor(),
        request: LanSaleRequest(
          idempotencyKey: 'lan-below-cost-cashier-001',
          paymentMethod: request.paymentMethod,
          paidAmountCents: request.paidAmountCents,
          belowCostOverrideReason: 'Attempted cashier override',
          lines: request.lines,
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

    await expectLater(
      gateway.createSale(actor: manager, request: requestWithoutReason),
      throwsA(
        isA<LanBusinessException>()
            .having(
              (error) => error.code,
              'code',
              'sale_below_cost_reason_required',
            )
            .having(
              (error) => error.details['productId'],
              'offending product id',
              productId,
            )
            .having(
              (error) => error.details['canOverride'],
              'manager override',
              isTrue,
            )
            .having(
              (error) => error.details.containsKey('costCents'),
              'cost remains permission-protected',
              isFalse,
            ),
      ),
    );

    final created = await gateway.createSale(actor: manager, request: request);
    expect(created.totalCents, 399);

    final audit =
        await (db.select(db.auditLogs)..where(
              (row) =>
                  row.action.equals('below_cost_override') &
                  row.recordId.equals(created.saleId),
            ))
            .getSingle();
    expect(audit.changes['new']['reason'], 'Clear damaged seasonal stock');
    expect(audit.changes['severity'], 'critical');

    final entries =
        await (db.select(db.journalEntries)..where(
              (row) =>
                  row.sourceTable.equals('sales') &
                  row.sourceId.equals(created.saleId),
            ))
            .get();
    expect(
      entries.map((entry) => entry.entryType),
      containsAll(['sale', 'sale_cogs']),
    );
    expect(
      entries.every((entry) => entry.totalDebitCents == entry.totalCreditCents),
      isTrue,
    );
    final cogs = entries.singleWhere((entry) => entry.entryType == 'sale_cogs');
    expect(cogs.totalDebitCents.toBigInt().toInt(), 400);
    expect(cogs.totalCreditCents.toBigInt().toInt(), 400);
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
      await expectPayloadConflict(
        () => gateway.createSale(
          actor: actor(),
          request: LanSaleRequest(
            idempotencyKey: key,
            paymentMethod: 'cash',
            paidAmountCents: 1200,
            lines: [LanSaleLineRequest(productId: productId, quantity: 1000)],
          ),
        ),
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
  group('warehouse-backed catalog and checkout', () {
    setUp(() async {
      final context = await db.select(db.businessContexts).getSingle();
      const remote = '00000000-0000-4000-8000-000000000099';
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: remote,
              organizationId: context.organizationId,
              branchId: context.branchId,
              code: 'REMOTE-CATALOG',
            ),
          );
      await db
          .into(db.businessWarehouseStocks)
          .insert(
            BusinessWarehouseStocksCompanion.insert(
              warehouseId: remote,
              variantId: variantId,
              quantity: const Value(9000),
              unitCostCents: const Value(50),
            ),
          );
      await removeBusinessWarehouseStockTriggers(db);
      await db.customStatement(
        'UPDATE products SET stock_quantity = 0, cost_cents = 99999',
      );
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = 0, cost_cents = 99999',
      );
    });
    test('catalog ignores stale mirrors and remote balances', () async {
      final page = await gateway.fetchCatalog(query: '', offset: 0, limit: 20);
      final product = page.products.singleWhere((p) => p.id == productId);
      expect(product.stockQuantity, 5000);
      expect(product.costCents, 800);
      expect(product.variants.single.stockQuantity, 5000);
      expect(product.variants.single.costCents, 800);
    });
    test(
      'checkout does not reject sufficient primary stock due to a stale zero mirror',
      () async {
        final result = await gateway.createSale(
          actor: actor(),
          request: LanSaleRequest(
            idempotencyKey: 'warehouse-stock-valid',
            paymentMethod: 'cash',
            paidAmountCents: 600,
            lines: [LanSaleLineRequest(productId: productId, quantity: 500)],
          ),
        );
        expect(result.totalCents, 600);
        final context = await db.select(db.businessContexts).getSingle();
        final row =
            await (db.select(db.businessWarehouseStocks)..where(
                  (s) =>
                      s.variantId.equals(variantId) &
                      s.warehouseId.equals(context.warehouseId),
                ))
                .getSingle();
        expect(row.quantity, 4500);
      },
    );
    test('checkout cannot spend remote stock or an inflated mirror', () async {
      await db.customStatement('UPDATE products SET stock_quantity = 99999');
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = 99999',
      );
      await expectLater(
        gateway.createSale(
          actor: actor(),
          request: LanSaleRequest(
            idempotencyKey: 'warehouse-stock-insufficient',
            paymentMethod: 'cash',
            paidAmountCents: 6600,
            lines: [LanSaleLineRequest(productId: productId, quantity: 5500)],
          ),
        ),
        throwsA(
          isA<LanBusinessException>().having(
            (e) => e.code,
            'code',
            'insufficient_stock',
          ),
        ),
      );
      expect(await db.select(db.sales).get(), isEmpty);
    });
  });

  group('server document location boundary', () {
    late Map<String, int> local, foreign;
    late String otherWarehouse;
    Future<int> insert(
      String table,
      Map<String, Object> values,
    ) => db.customInsert(
      'INSERT INTO $table (${values.keys.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
      variables: values.values
          .map(
            (v) => v is int
                ? Variable.withInt(v)
                : Variable.withString(v as String),
          )
          .toList(),
    );
    Future<Map<String, int>> seed(String suffix) async {
      final supplier = await insert('suppliers', {
        'name': 'Supplier $suffix',
        'currency_id': currencyId,
      });
      final docs = <String, int>{};
      for (final side in ['sale', 'purchase']) {
        final sale = side == 'sale';
        final header = await insert('${side}s', {
          sale ? 'invoice_number' : 'purchase_number': '$side-$suffix',
          if (!sale) 'supplier_id': supplier,
          'currency_id': currencyId,
          'status': sale ? 'completed' : 'posted',
          '${side}_date': DateTime.now().toIso8601String(),
          'subtotal_cents': 1200,
          'total_cents': 1200,
          'tax_cents': 0,
          'payment_method': 'cash',
        });
        await insert('${side}_items', {
          '${side}_id': header,
          'product_id': productId,
          'variant_id': variantId,
          'quantity': 1000,
          sale ? 'unit_price_cents' : 'unit_cost_cents': 1200,
          'subtotal_cents': 1200,
          'total_cents': 1200,
          'tax_cents': 0,
        });
        final linked = await insert('${side}_returns', {
          '${side}_id': header,
          'return_number': '$side-linked-$suffix',
          'currency_id': currencyId,
          'status': 'posted',
          'total_cents': 100,
          'reason': 'Scope test',
        });
        final adjustment = await insert('${side}_return_adjustments', {
          'return_number': '$side-adjustment-$suffix',
          if (!sale) 'supplier_id': supplier,
          'currency_id': currencyId,
          'status': 'posted',
          'total_cents': 50,
        });
        docs.addAll({
          '${side}s': header,
          '${side}_returns': linked,
          '${side}_return_adjustments': adjustment,
        });
      }
      return docs;
    }

    Future<void> move(
      String table,
      int id,
      String warehouse,
    ) => db.customUpdate(
      'UPDATE business_document_locations SET warehouse_id = ? WHERE source_table = ? AND source_id = ?',
      variables: [
        Variable.withString(warehouse),
        Variable.withString(table),
        Variable.withInt(id),
      ],
      updates: {db.businessDocumentLocations},
    );
    setUp(() async {
      final scope = await db.select(db.businessContexts).getSingle();
      otherWarehouse = '00000000-0000-4000-8000-000000000077';
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: otherWarehouse,
              organizationId: scope.organizationId,
              branchId: scope.branchId,
              code: 'REMOTE',
            ),
          );
      local = await seed('LOCAL');
      foreign = await seed('FOREIGN');
      await db.customStatement('DROP TRIGGER business_location_immutable');
      for (final doc in foreign.entries) {
        await move(doc.key, doc.value, otherWarehouse);
      }
    });
    test(
      'sales pagination and dashboard use the same local boundary',
      () async {
        final page = await gateway.fetchSales(limit: 1);
        expect(page.sales.map((s) => s.id), [local['sales']]);
        expect(page.stats.totalCount, 1);
        expect(page.stats.totalSalesCents, 1200);
        expect(page.stats.returnsCount, 1);
        expect(page.stats.totalReturnsCents, 100);
        expect(page.stats.todayCount, 1);
        expect(page.productSearchTerms.keys, isNot(contains(foreign['sales'])));
        expect(page.saleIdsWithReturns, isNot(contains(foreign['sales'])));
      },
    );
    test('sale details cannot be retrieved by guessing a foreign id', () async {
      expect(
        await gateway.fetchSaleDetails(saleId: local['sales']!),
        isNotNull,
      );
      expect(await gateway.fetchSaleDetails(saleId: foreign['sales']!), isNull);
    });
    test('returnable sales search filters before pagination', () async {
      final page = await gateway.fetchReturnableSales(
        query: '',
        offset: 0,
        limit: 1,
      );
      expect(page.sales.map((s) => s.saleId), [local['sales']]);
      expect(page.hasMore, isFalse);
      expect(
        (await gateway.fetchReturnableSales(
          query: 'FOREIGN',
          offset: 0,
          limit: 20,
        )).sales,
        isEmpty,
      );
    });
    test('returnable purchases search filters before pagination', () async {
      final page = await gateway.fetchReturnablePurchases(
        query: '',
        offset: 0,
        limit: 1,
      );
      expect(page.purchases.map((p) => p.purchaseId), [local['purchases']]);
      expect(page.hasMore, isFalse);
      expect(
        (await gateway.fetchReturnablePurchases(
          query: 'FOREIGN',
          offset: 0,
          limit: 20,
        )).purchases,
        isEmpty,
      );
    });
    test('returnable detail endpoints enforce location', () async {
      expect(
        await gateway.fetchReturnableSale(saleId: local['sales']!),
        isNotNull,
      );
      expect(
        await gateway.fetchReturnableSale(saleId: foreign['sales']!),
        isNull,
      );
      expect(
        await gateway.fetchReturnablePurchase(purchaseId: local['purchases']!),
        isNotNull,
      );
      expect(
        await gateway.fetchReturnablePurchase(
          purchaseId: foreign['purchases']!,
        ),
        isNull,
      );
    });
    for (final sale in [true, false]) {
      final side = sale ? 'sale' : 'purchase';
      test(
        '$side return lists keep linked and adjustment IDs separate',
        () async {
          if (sale) {
            final page = await gateway.fetchSaleReturns(
              query: '',
              offset: 0,
              limit: 20,
            );
            expect(page.returns.length, 2);
            expect(
              page.returns.where((r) => r.isAdjustment).single.id,
              local['sale_return_adjustments'],
            );
            expect(
              page.returns.where((r) => !r.isAdjustment).single.id,
              local['sale_returns'],
            );
            expect(
              (await gateway.fetchSaleReturns(
                query: 'FOREIGN',
                offset: 0,
                limit: 20,
              )).returns,
              isEmpty,
            );
          } else {
            final page = await gateway.fetchPurchaseReturns(
              query: '',
              offset: 0,
              limit: 20,
            );
            expect(page.returns.length, 2);
            expect(
              page.returns.where((r) => r.isAdjustment).single.id,
              local['purchase_return_adjustments'],
            );
            expect(
              page.returns.where((r) => !r.isAdjustment).single.id,
              local['purchase_returns'],
            );
            expect(
              (await gateway.fetchPurchaseReturns(
                query: 'FOREIGN',
                offset: 0,
                limit: 20,
              )).returns,
              isEmpty,
            );
          }
        },
      );
      for (final adjustment in [false, true]) {
        test(
          '$side detail enforces the correct return table: adjustment=$adjustment',
          () async {
            final table = adjustment
                ? '${side}_return_adjustments'
                : '${side}_returns';
            if (sale) {
              expect(
                await gateway.fetchSaleReturnDetails(
                  returnId: local[table]!,
                  adjustment: adjustment,
                ),
                isNotNull,
              );
              expect(
                await gateway.fetchSaleReturnDetails(
                  returnId: foreign[table]!,
                  adjustment: adjustment,
                ),
                isNull,
              );
            } else {
              expect(
                await gateway.fetchPurchaseReturnDetails(
                  returnId: local[table]!,
                  adjustment: adjustment,
                ),
                isNotNull,
              );
              expect(
                await gateway.fetchPurchaseReturnDetails(
                  returnId: foreign[table]!,
                  adjustment: adjustment,
                ),
                isNull,
              );
            }
          },
        );
      }
    }
    test(
      'return scope is independent of the original invoice location',
      () async {
        await move('sales', local['sales']!, otherWarehouse);
        expect(await gateway.fetchSaleDetails(saleId: local['sales']!), isNull);
        expect(
          await gateway.fetchSaleReturnDetails(
            returnId: local['sale_returns']!,
            adjustment: false,
          ),
          isNotNull,
        );
        final page = await gateway.fetchSales(limit: 20);
        expect(page.sales, isEmpty);
        expect(page.stats.totalSalesCents, 0);
        expect(page.stats.totalReturnsCents, 100);
      },
    );
    test('disabled local warehouse retains readable history', () async {
      final scope = await db.select(db.businessContexts).getSingle();
      await (db.update(db.businessWarehouses)
            ..where((w) => w.id.equals(scope.warehouseId)))
          .write(const BusinessWarehousesCompanion(isActive: Value(false)));
      expect((await gateway.fetchSales(limit: 20)).sales.map((s) => s.id), [
        local['sales'],
      ]);
    });
  });
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

class _TaxCatalogLan extends Fake implements LanNetworkService {
  LanCatalogPage page;
  final requests = <LanPurchaseAdjustmentReturnRequest>[];
  Future<LanSaleReturnResult> Function(LanSaleAdjustmentReturnRequest)?
  saleSubmit;
  @override
  Future<LanSaleReturnResult> submitRemoteSaleAdjustmentReturn(
    LanSaleAdjustmentReturnRequest request,
  ) => saleSubmit!(request);

  _TaxCatalogLan(this.page);
  @override
  Future<LanPurchaseReturnResult> submitRemotePurchaseAdjustmentReturn(
    LanPurchaseAdjustmentReturnRequest request,
  ) async {
    requests.add(request);
    throw const LanBusinessException(
      'pricing_preview_changed',
      'Changed',
      statusCode: 409,
    );
  }

  @override
  LanNetworkSnapshot get snapshot =>
      const LanNetworkSnapshot(mode: LanMode.client);
  @override
  bool get hasRemoteUserSession => true;
  @override
  Future<LanCatalogPage> fetchRemoteCatalog({
    String query = '',
    int offset = 0,
    int limit = 100,
    bool management = false,
  }) async => page;
}
