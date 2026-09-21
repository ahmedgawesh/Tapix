import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/business/branch_tax_policy.dart';
import 'package:tapix/core/services/business/branch_tax_policy_store.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_adj_return_form_bloc.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_adj_return_form_bloc.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';
import 'package:tapix/features/customers/data/repositories/loyalty_repository_impl.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/settings/data/services/app_settings_service.dart';

void main() {
  late AppDatabase db;
  late AppSettingsService settings;
  late SaleAdjReturnFormBloc form;
  late int productId;
  late int customerId;
  int? variantId;

  Future<void> event(
    SaleAdjReturnFormEvent e,
    bool Function(SaleAdjReturnFormState) ready,
  ) async {
    final changed = form.stream.firstWhere(ready);
    form.add(e);
    await changed.timeout(const Duration(seconds: 10));
  }

  Future<void> prepare(bool variant) async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    settings = AppSettingsService(
      await SharedPreferences.getInstance(),
      taxStore: BranchTaxPolicyStore(db),
    );
    await settings.initializeTaxPolicy();
    await settings.patch(
      (s) => s.copyWith(enableTaxCalculations: true, defaultSalesTaxRate: 20),
    );
    final currency = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(name: 'Customer', currencyId: currency.id),
        );
    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Product',
            priceCents: Decimal.fromInt(2000),
            costCents: Decimal.fromInt(1500),
            currencyId: Value(currency.id),
            stockQuantity: const Value(10),
            isTaxable: const Value(true),
            hasVariants: Value(variant),
          ),
        );
    // Ordinary products also own a strict default inventory variant.
    final inventoryVariant = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            priceCents: Decimal.fromInt(2000),
            costCents: Decimal.fromInt(1500),
            stockQuantity: const Value(10),
          ),
        );
    variantId = variant ? inventoryVariant : null;
    final purchase = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'PREVIEW-HISTORY',
            paymentMethod: 'cash',
            paidAmountCents: Value(Decimal.fromInt(7500)),
            taxCents: Decimal.zero,
            customerId: Value(customerId),
            subtotalCents: Decimal.fromInt(7500),
            totalCents: Decimal.fromInt(7500),
            currencyId: currency.id,
            status: const Value('completed'),
          ),
        );
    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            saleId: purchase,
            productId: productId,
            variantId: Value(variantId),
            quantity: 5,
            unitPriceCents: Decimal.fromInt(1500),
            subtotalCents: Decimal.fromInt(7500),
            totalCents: Decimal.fromInt(7500),
          ),
        );
    final journal = JournalEntryService(AccountingRepository(db));
    form = SaleAdjReturnFormBloc(
      AdjustmentReturnDao(db),
      journal,
      CommissionService(db.employeeDao),
      LoyaltyPointsService(LoyaltyRepositoryImpl(db, journal), journal, db),
      SessionService(),
      settings: settings,
    );
    await event(
      SaleAdjReturnCustomerSelected(customerId, 'Customer'),
      (s) => s.customerId == customerId,
    );
    await event(
      const SaleAdjReturnReasonChanged(AdjReturnReasonCode.noReceipt),
      (s) => s.reasonCode != null,
    );
    await event(
      SaleAdjReturnItemAdded(
        AdjReturnLineItem(
          productId: productId,
          variantId: variantId,
          productName: 'Product',
          quantity: 1,
          unitPriceCents: 1500,
          discountCents: 200,
        ),
      ),
      (s) => s.items.length == 1,
    );
    await event(
      const SaleAdjReturnOverallDiscountChanged(100, false),
      (s) => s.overallDiscountCents == 100,
    );
    expect(form.state.totalAdjustedTaxCents, 240);
  }

  Future<List<Object?>> financialState() async => [
    for (final table in [
      'sale_return_adjustments',
      'sale_return_adjustment_items',
      'journal_entries',
      'journal_entry_lines',
      'products',
      'product_variants',
      'customers',
    ])
      (await db.customSelect('SELECT * FROM $table').get())
          .map((r) => r.data)
          .toList(),
  ];

  tearDown(() async {
    await form.close();
    settings.dispose();
    await db.close();
  });

  for (final variant in [false, true]) {
    for (final change in [
      'policy',
      'inclusive',
      'disabled',
      'exempt',
      'product',
    ]) {
      test('local preview requires review: variant=$variant $change', () async {
        await prepare(variant);
        if (change == 'policy' ||
            change == 'inclusive' ||
            change == 'disabled') {
          // Update SQL without updating the in-memory settings cache.
          final store = BranchTaxPolicyStore(db);
          await store.update(
            expected: (await store.read())!,
            policy: BranchTaxPolicy.fromLegacy(
              settings.current.copyWith(
                defaultSalesTaxRate: change == 'policy' ? 30 : 20,
                enableTaxCalculations: change != 'disabled',
                taxInclusivePricing: change == 'inclusive',
              ),
            ),
          );
        } else {
          await (db.update(
            db.products,
          )..where((p) => p.id.equals(productId))).write(
            ProductsCompanion(
              isTaxable: Value(change != 'exempt'),
              salesTaxRateBps: Value(change == 'product' ? 1000 : 0),
            ),
          );
        }
        final before = await financialState();
        await event(
          const SaleAdjReturnSubmitted(),
          (s) => !s.isSubmitting && s.error != null,
        );
        expect(form.state.error, 'returns.pricing_preview_updated');
        expect(form.state.isSuccess, isFalse);
        expect(await financialState(), before);
        expect(form.state.items.single.discountCents, 200);
        expect(form.state.overallDiscountCents, 100);
        final tax = {
          'policy': 360,
          'inclusive': 200,
          'exempt': 0,
          'disabled': 0,
          'product': 120,
        }[change]!;
        expect(form.state.totalAdjustedTaxCents, tax);
        final total = change == 'inclusive' ? 1200 : 1200 + tax;
        expect(form.state.totalCents, total);
        await event(
          const SaleAdjReturnSubmitted(),
          (s) => !s.isSubmitting && (s.isSuccess || s.error != null),
        );
        expect(form.state.isSuccess, isTrue, reason: form.state.error);
        final header = await db.select(db.saleReturnAdjustments).getSingle();
        expect(header.totalCents, Decimal.fromInt(total));
        expect(header.taxCents, Decimal.fromInt(tax));
        expect(header.taxInclusiveAtPost, change == 'inclusive');
        final line = await db.select(db.saleReturnAdjustmentItems).getSingle();
        expect(line.discountCents, Decimal.fromInt(300));
        expect(line.taxCents, Decimal.fromInt(tax));
        final journal = await db
            .customSelect(
              'SELECT SUM(debit_cents) d, '
              'SUM(credit_cents) c FROM journal_entry_lines',
            )
            .getSingle();
        expect(journal.read<int>('d'), journal.read<int>('c'));
      });
    }
  }

  test(
    'concurrent additions preserve lines and notes while reading tax rules',
    () async {
      await prepare(false);
      final item = form.state.items.single;
      final complete = form.stream.firstWhere((s) => s.items.length == 3);
      form.add(SaleAdjReturnItemAdded(item));
      form.add(SaleAdjReturnItemAdded(item));
      form.add(const SaleAdjReturnNotesChanged('Keep these notes'));
      await complete.timeout(const Duration(seconds: 10));
      expect(form.state.items.length, 3);
      expect(form.state.notes, 'Keep these notes');
    },
  );

  test('missing durable policy cannot post using cached tax values', () async {
    await prepare(false);
    await db.customStatement(
      "DELETE FROM app_settings WHERE key LIKE 'business.tax_policy.%'",
    );
    final before = await financialState();
    await event(
      const SaleAdjReturnSubmitted(),
      (s) => !s.isSubmitting && s.error != null,
    );
    expect(form.state.isSuccess, isFalse);
    expect(await financialState(), before);
  });
}
