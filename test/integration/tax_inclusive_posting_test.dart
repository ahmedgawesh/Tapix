import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/money/money.dart';
import 'package:tapix/core/pricing/invoice_pricing_engine.dart';
import 'package:tapix/core/pricing/line_item_pricing_engine.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late int currencyId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    journal = JournalEntryService(AccountingRepository(db));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
  });

  tearDown(() => db.close());

  InvoicePricingResult inclusive115() {
    return InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: [
          LineItemPricingInput(
            unitPrice: Money.fromCents(11500),
            quantity: 1,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: true,
      ),
    );
  }

  Future<Map<String, ({int debit, int credit})>> postedLines(
    String sourceTable,
    int sourceId,
  ) async {
    final rows = await db
        .customSelect(
          '''
      SELECT a.account_code, jel.debit_cents, jel.credit_cents
      FROM journal_entry_lines jel
      INNER JOIN journal_entries je ON je.id = jel.journal_entry_id
      INNER JOIN accounts a ON a.id = jel.account_id
      WHERE je.source_table = ? AND je.source_id = ? AND je.status = 'posted'
      ''',
          variables: [
            Variable.withString(sourceTable),
            Variable.withInt(sourceId),
          ],
          readsFrom: {db.journalEntries, db.journalEntryLines, db.accounts},
        )
        .get();

    return {
      for (final row in rows)
        row.read<String>('account_code'): (
          debit: row.read<int>('debit_cents'),
          credit: row.read<int>('credit_cents'),
        ),
    };
  }

  test('inclusive sale posts 115 total as 100 revenue plus 15 VAT', () async {
    final pricing = inclusive115();
    expect(pricing.total.cents, 11500);
    expect(pricing.tax.cents, 1500);

    await journal.recordSaleJournalEntry(
      saleId: 91001,
      totalCents: pricing.total.cents,
      paidAmountCents: pricing.total.cents,
      currencyId: currencyId,
      taxCents: pricing.tax.cents,
      paymentMethod: 'cash',
    );

    final lines = await postedLines('sales', 91001);
    expect(lines['1000'], (debit: 11500, credit: 0));
    expect(lines['4000'], (debit: 0, credit: 10000));
    expect(lines['2100'], (debit: 0, credit: 1500));
  });

  test(
    'inclusive purchase posts 115 total as 100 inventory plus 15 VAT',
    () async {
      final pricing = inclusive115();
      expect(pricing.total.cents, 11500);
      expect(pricing.tax.cents, 1500);

      await journal.recordPurchaseJournalEntry(
        purchaseId: 92001,
        totalCents: pricing.total.cents,
        paidAmountCents: pricing.total.cents,
        currencyId: currencyId,
        taxCents: pricing.tax.cents,
        paymentMethod: 'cash',
      );

      final lines = await postedLines('purchases', 92001);
      expect(lines['1200'], (debit: 10000, credit: 0));
      expect(lines['1300'], (debit: 1500, credit: 0));
      expect(lines['1000'], (debit: 0, credit: 11500));
    },
  );
}
