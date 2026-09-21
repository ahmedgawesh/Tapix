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
import 'package:tapix/features/purchases/presentation/bloc/purchase_adj_return_form_bloc.dart';
import 'package:tapix/features/settings/data/services/app_settings_service.dart';

void main() {
  late AppDatabase db;
  late AppSettingsService settings;
  late PurchaseAdjReturnFormBloc form;
  late int productId;
  late int supplierId;
  int? variantId;

  Future<void> event(
    PurchaseAdjReturnFormEvent e,
    bool Function(PurchaseAdjReturnFormState) ready,
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
      (s) =>
          s.copyWith(enableTaxCalculations: true, defaultPurchaseTaxRate: 20),
    );
    final currency = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(name: 'Supplier', currencyId: currency.id),
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
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PREVIEW-HISTORY',
            taxCents: Decimal.zero,
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(7500),
            totalCents: Decimal.fromInt(7500),
            currencyId: currency.id,
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
            quantity: 5,
            unitCostCents: Decimal.fromInt(1500),
            subtotalCents: Decimal.fromInt(7500),
            totalCents: Decimal.fromInt(7500),
          ),
        );
    form = PurchaseAdjReturnFormBloc(
      AdjustmentReturnDao(db),
      JournalEntryService(AccountingRepository(db)),
      settings: settings,
    );
    await event(
      PurchaseAdjReturnSupplierSelected(supplierId, 'Supplier'),
      (s) => s.supplierId == supplierId,
    );
    await event(
      const PurchaseAdjReturnReasonChanged(AdjReturnReasonCode.noReceipt),
      (s) => s.reasonCode != null,
    );
    await event(
      PurchaseAdjReturnItemAdded(
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
      const PurchaseAdjReturnOverallDiscountChanged(100, false),
      (s) => s.overallDiscountCents == 100,
    );
    expect(form.state.totalAdjustedTaxCents, 240);
  }

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
                defaultPurchaseTaxRate: change == 'policy' ? 30 : 20,
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
              purchaseTaxRateBps: Value(change == 'product' ? 1000 : 0),
            ),
          );
        }
        final before = await financialState();
        await event(
          const PurchaseAdjReturnSubmitted(),
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
          const PurchaseAdjReturnSubmitted(),
          (s) => !s.isSubmitting && (s.isSuccess || s.error != null),
        );
        expect(form.state.isSuccess, isTrue, reason: form.state.error);
        final header = await db
            .select(db.purchaseReturnAdjustments)
            .getSingle();
        expect(header.totalCents, Decimal.fromInt(total));
        expect(header.taxCents, Decimal.fromInt(tax));
        expect(header.taxInclusiveAtPost, change == 'inclusive');
        final line = await db
            .select(db.purchaseReturnAdjustmentItems)
            .getSingle();
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

  test('missing durable policy cannot post using cached tax values', () async {
    await prepare(false);
    await db.customStatement(
      "DELETE FROM app_settings WHERE key LIKE 'business.tax_policy.%'",
    );
    final before = await financialState();
    await event(
      const PurchaseAdjReturnSubmitted(),
      (s) => !s.isSubmitting && s.error != null,
    );
    expect(form.state.isSuccess, isFalse);
    expect(await financialState(), before);
  });
}
