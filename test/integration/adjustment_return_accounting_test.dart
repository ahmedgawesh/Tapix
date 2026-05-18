import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// Integration tests for adjustment return accounting flows.
///
///   TEST 1: postSaleAdjReturn → 4-line journal entry (Dr SalesRetAdj 5700,
///           Cr AR 1100, Dr Inventory 1200, Cr COGS 5300)
///   TEST 2: voidSaleAdjReturn → reversal journal entry
///   TEST 3: postPurchaseAdjReturn → 4-line journal entry (Dr AP 2000,
///           Cr PurchaseRetAdj 4100, Dr COGS 5300, Cr Inventory 1200)
///   TEST 4: voidPurchaseAdjReturn → reversal journal entry
void main() {
  late AppDatabase db;
  late AdjustmentReturnDao adjDao;
  late AccountingRepository accountingRepo;
  late JournalEntryService journalService;

  /// Helper: fetch all posted journal entry lines for a source.
  Future<List<({int accountId, int debitCents, int creditCents})>>
      journalLinesForSource(String sourceTable, int sourceId) async {
    final rows = await db.customSelect(
      'SELECT jel.account_id, jel.debit_cents, jel.credit_cents '
      'FROM journal_entry_lines jel '
      'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
      'WHERE je.source_table = ? AND je.source_id = ? AND je.status = ?',
      variables: [
        Variable.withString(sourceTable),
        Variable.withInt(sourceId),
        Variable.withString('posted'),
      ],
    ).get();

    return rows
        .map((r) => (
              accountId: r.read<int>('account_id'),
              debitCents: r.read<int>('debit_cents'),
              creditCents: r.read<int>('credit_cents'),
            ))
        .toList();
  }

  /// Helper: sum debits and credits.
  ({int totalDebit, int totalCredit}) sumLines(
      List<({int accountId, int debitCents, int creditCents})> lines) {
    int d = 0, c = 0;
    for (final l in lines) {
      d += l.debitCents;
      c += l.creditCents;
    }
    return (totalDebit: d, totalCredit: c);
  }

  /// Helper: look up account id by code.
  Future<int> accountIdByCode(String code) async {
    final row = await db.customSelect(
      'SELECT id FROM accounts WHERE account_code = ?',
      variables: [Variable.withString(code)],
    ).getSingle();
    return row.read<int>('id');
  }

  /// Helper: check if reversed journal entries exist for a source.
  Future<int> reversedJournalCount(String sourceTable, int sourceId) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS cnt FROM journal_entries '
      'WHERE source_table = ? AND source_id = ? AND is_reversed = 1',
      variables: [
        Variable.withString(sourceTable),
        Variable.withInt(sourceId),
      ],
    ).getSingle();
    return row.read<int>('cnt');
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    accountingRepo = AccountingRepository(db);
    journalService = JournalEntryService(accountingRepo);
    adjDao = AdjustmentReturnDao(db);

    // Force DB init (seeds accounts)
    await db.customSelect('SELECT 1').get();

    // Seed a system user so FK constraints on created_by/posted_by pass
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, is_active, created_at, updated_at) '
      'VALUES (0, \'system\', \'no-pin\', \'owner\', 1, $now, $now)',
    );
  });

  tearDown(() async {
    await db.close();
  });

  // =========================================================================
  // COMMON SETUP
  // =========================================================================
  late int currencyId;
  late int productId;
  late int variantId;
  late int customerId;
  late int supplierId;

  Future<void> seedData() async {
    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;

    productId = await db.into(db.products).insert(
      ProductsCompanion.insert(
        sku: const Value<String?>('ADJ-PROD-001'),
        name: 'Adj Return Test Product',
        costCents: Decimal.fromInt(3000), // $30.00
        priceCents: Decimal.fromInt(5000), // $50.00
        currencyId: Value(currencyId),
        stockQuantity: const Value(100),
      ),
    );

    variantId = await db.into(db.productVariants).insert(
      ProductVariantsCompanion.insert(
        productId: productId,
        stockQuantity: const Value(100),
        costCents: Decimal.fromInt(3000),
        priceCents: Decimal.fromInt(5000),
      ),
    );

    customerId = await db.into(db.customers).insert(
      CustomersCompanion.insert(
        name: 'Adj Test Customer',
        currencyId: currencyId,
        balanceCents: Value(Decimal.fromInt(50000)), // owes $500
      ),
    );

    supplierId = await db.into(db.suppliers).insert(
      SuppliersCompanion.insert(
        name: 'Adj Test Supplier',
        currencyId: currencyId,
        balanceCents: Value(Decimal.fromInt(80000)), // we owe $800
      ),
    );
  }

  // =========================================================================
  // TEST 1: Sale Adjustment Return — 4-line JE
  // =========================================================================
  group('Sale Adjustment Return Journal Entries', () {
    test('postSaleAdjReturn creates 4-line balanced JE', () async {
      await seedData();

      // Create the adjustment return
      final returnId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-TEST-0001',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(10000), // $100
          refundMethod: const Value('credit'),
          notes: const Value('Test sale adj return'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(10000),
          ),
        ],
      );

      // Post — this should create journal entries.
      // allowOverHistory: true bypasses the new (Phase 0) per-party qty cap;
      // these tests intentionally don't seed an upstream sale, so the cap
      // would refuse them. The cap itself is covered by
      // adjustment_return_quantity_cap_test.dart.
      await adjDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        allowOverHistory: true,
      );

      // Fetch journal lines
      final lines =
          await journalLinesForSource('sale_return_adjustments', returnId);
      final totals = sumLines(lines);

      // VERIFY: Balanced
      expect(totals.totalDebit, equals(totals.totalCredit),
          reason: 'JE must be balanced');

      // VERIFY: 4 lines
      expect(lines.length, equals(4),
          reason: 'Should have 4 lines (financial + inventory)');

      // VERIFY: Financial side
      final acct5700 = await accountIdByCode('5700');
      final acct1100 = await accountIdByCode('1100');
      final financial5700 =
          lines.where((l) => l.accountId == acct5700).toList();
      final financial1100 =
          lines.where((l) => l.accountId == acct1100).toList();

      expect(financial5700.length, equals(1),
          reason: 'One line for Sales Return Adj (5700)');
      expect(financial5700.first.debitCents, equals(10000),
          reason: 'Dr Sales Return Adj = total');
      expect(financial1100.length, equals(1),
          reason: 'One line for AR (1100)');
      expect(financial1100.first.creditCents, equals(10000),
          reason: 'Cr AR = total');

      // VERIFY: Inventory side
      final acct1200 = await accountIdByCode('1200');
      final acct5300 = await accountIdByCode('5300');
      final inv1200 = lines.where((l) => l.accountId == acct1200).toList();
      final inv5300 = lines.where((l) => l.accountId == acct5300).toList();

      expect(inv1200.length, equals(1),
          reason: 'One line for Inventory (1200)');
      expect(inv1200.first.debitCents, greaterThan(0),
          reason: 'Dr Inventory > 0 (cost-based)');
      expect(inv5300.length, equals(1),
          reason: 'One line for COGS (5300)');
      expect(inv5300.first.creditCents, greaterThan(0),
          reason: 'Cr COGS > 0');

      // VERIFY: Inventory cost = qty * unitCostCents
      // unitCostCents was auto-fetched as 3000 (product cost)
      expect(inv1200.first.debitCents, equals(6000),
          reason: 'Inventory Dr = 2 * 3000');
      expect(inv5300.first.creditCents, equals(6000),
          reason: 'COGS Cr = 2 * 3000');

      // VERIFY: Stock increased (sale return adds stock back)
      final variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(102),
          reason: 'Stock should be 100 + 2 = 102');

      // VERIFY: Customer balance UNCHANGED.
      // An adjustment sale return NEVER touches `customers.balance_cents`
      // (the 1100 AR sub-ledger). The unified policy routes the credit
      // settlement to 2400 Customer Credit Liability (sub-ledger lives in
      // `customer_credit_notes`), and cash/bank refunds settle to 1000/1010
      // — none of which is the AR sub-ledger. The legacy fallback in this
      // test environment still credits 1100 in the GL (a known divergence
      // from production where ReturnPostingService is wired and routes to
      // 2400), but the customer-side sub-ledger must remain pristine. This
      // assertion guards against regression of the AR-vs-customer-balance
      // mismatch that produced AR delta = +15150 in the field.
      final customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();
      expect(customer.balanceCents.toBigInt().toInt(), equals(50000),
          reason: 'Customer balance MUST be unchanged on adjustment '
              'sale return — see comment above.');
    });

    test('voidSaleAdjReturn creates reversal and restores stock/balance',
        () async {
      await seedData();

      final returnId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-TEST-0002',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(5000),
          refundMethod: const Value('credit'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(5000),
          ),
        ],
      );

      // Post
      await adjDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        allowOverHistory: true,
      );

      // Verify stock after post
      var variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(101));

      // Void
      await adjDao.voidSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
      );

      // VERIFY: Original JE is reversed
      final reversedCount =
          await reversedJournalCount('sale_return_adjustments', returnId);
      expect(reversedCount, greaterThan(0),
          reason: 'Original JE should be reversed');

      // VERIFY: Stock restored
      variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(100),
          reason: 'Stock should return to original 100');

      // VERIFY: Customer balance UNCHANGED through post + void.
      // postSaleAdjReturn does not touch the AR sub-ledger, so neither
      // does the void (no-op symmetry). 50000 is the seed value.
      final customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();
      expect(customer.balanceCents.toBigInt().toInt(), equals(50000),
          reason: 'Customer balance must remain at the seed value across '
              'post and void of an adjustment sale return.');
    });
  });

  // =========================================================================
  // TEST 3: Purchase Adjustment Return — 4-line JE
  // =========================================================================
  group('Purchase Adjustment Return Journal Entries', () {
    test('postPurchaseAdjReturn creates 4-line balanced JE', () async {
      await seedData();

      final returnId = await adjDao.createPurchaseAdjReturn(
        PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: 'PAR-TEST-0001',
          supplierId: supplierId,
          currencyId: currencyId,
          totalCents: Decimal.fromInt(15000), // $150
          notes: const Value('Test purchase adj return'),
        ),
        [
          PurchaseReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 3,
            unitPriceCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(15000),
          ),
        ],
      );

      // Post
      await adjDao.postPurchaseAdjReturn(
        returnId,
        journalEntryService: journalService,
        allowOverHistory: true,
      );

      // Fetch journal lines
      final lines = await journalLinesForSource(
          'purchase_return_adjustments', returnId);
      final totals = sumLines(lines);

      // VERIFY: Balanced
      expect(totals.totalDebit, equals(totals.totalCredit),
          reason: 'JE must be balanced');

      // VERIFY: 4 lines
      expect(lines.length, equals(4),
          reason: 'Should have 4 lines (financial + inventory)');

      // VERIFY: Financial side — Dr AP (2000), Cr PurchaseRetAdj (4100)
      final acct2000 = await accountIdByCode('2000');
      final acct4100 = await accountIdByCode('4100');
      final fin2000 = lines.where((l) => l.accountId == acct2000).toList();
      final fin4100 = lines.where((l) => l.accountId == acct4100).toList();

      expect(fin2000.length, equals(1));
      expect(fin2000.first.debitCents, equals(15000),
          reason: 'Dr AP = total');
      expect(fin4100.length, equals(1));
      expect(fin4100.first.creditCents, equals(15000),
          reason: 'Cr Purchase Ret Adj = total');

      // VERIFY: Inventory side — Dr COGS (5300), Cr Inventory (1200)
      final acct5300 = await accountIdByCode('5300');
      final acct1200 = await accountIdByCode('1200');
      final inv5300 = lines.where((l) => l.accountId == acct5300).toList();
      final inv1200 = lines.where((l) => l.accountId == acct1200).toList();

      expect(inv5300.length, equals(1));
      expect(inv5300.first.debitCents, equals(9000),
          reason: 'Dr COGS = 3 * 3000');
      expect(inv1200.length, equals(1));
      expect(inv1200.first.creditCents, equals(9000),
          reason: 'Cr Inventory = 3 * 3000');

      // VERIFY: Stock decreased (purchase return sends stock back)
      final variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(97),
          reason: 'Stock should be 100 - 3 = 97');

      // VERIFY: Supplier balance decreased
      final supplier = await (db.select(db.suppliers)
            ..where((s) => s.id.equals(supplierId)))
          .getSingle();
      expect(supplier.balanceCents.toBigInt().toInt(), equals(65000),
          reason: 'Supplier balance: 80000 - 15000 = 65000');
    });

    test('voidPurchaseAdjReturn creates reversal and restores stock/balance',
        () async {
      await seedData();

      final returnId = await adjDao.createPurchaseAdjReturn(
        PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: 'PAR-TEST-0002',
          supplierId: supplierId,
          currencyId: currencyId,
          totalCents: Decimal.fromInt(5000),
        ),
        [
          PurchaseReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(5000),
          ),
        ],
      );

      await adjDao.postPurchaseAdjReturn(
        returnId,
        journalEntryService: journalService,
        allowOverHistory: true,
      );

      // Verify stock after post
      var variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(99));

      // Void
      await adjDao.voidPurchaseAdjReturn(
        returnId,
        journalEntryService: journalService,
      );

      // VERIFY: Original JE reversed
      final reversedCount =
          await reversedJournalCount('purchase_return_adjustments', returnId);
      expect(reversedCount, greaterThan(0));

      // VERIFY: Stock restored
      variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(100),
          reason: 'Stock should return to 100');

      // VERIFY: Supplier balance restored
      final supplier = await (db.select(db.suppliers)
            ..where((s) => s.id.equals(supplierId)))
          .getSingle();
      expect(supplier.balanceCents.toBigInt().toInt(), equals(80000),
          reason: 'Supplier balance should be restored to 80000');
    });
  });

  // =========================================================================
  // REGRESSION: Field-bug reproduction
  //
  //   Field scenario (DB tapix_backup_20260513_014004.db):
  //   AR  GL = 44997, Σ customers.balance = 29847, delta = +15150.
  //
  //   Root cause:
  //     adjustment_return_dao.postSaleAdjReturn unconditionally decremented
  //     `customers.balance_cents` by `refundCents`, but the JE settlement
  //     leg routes to 1000 Cash (cash refund) / 1010 Bank / 2400 Customer
  //     Credit Liability — never to 1100 AR. The customer sub-ledger
  //     (= 1100 AR) therefore drifted from the GL by exactly the refund
  //     amount on every cash/bank/credit-via-2400 adjustment return.
  //
  //   This test reproduces the cash-refund variant (the one observed in
  //   the field) and asserts the customer balance does NOT change. With
  //   the buggy code restored, the assertion fails with delta = -15150.
  // =========================================================================
  group('Regression: field-bug AR sub-ledger drift on cash adj return', () {
    test('cash refund on adjustment sale return leaves customers.balance '
        'untouched (was: -refund_amount)', () async {
      await seedData();

      // Customer enters with $500 owing — same shape as the field DB.
      final initialBalance = await (db.select(db.customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();
      expect(initialBalance.balanceCents.toBigInt().toInt(), equals(50000));

      // 1 unit @ 15150 cents (matches the field SAR-202605-0001 total).
      final returnId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-REGRESSION-FIELD-0001',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(15150),
          refundMethod: const Value('cash'), // ← the field-bug variant
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(15000),
            taxCents: Value(Decimal.fromInt(150)),
            totalCents: Decimal.fromInt(15150),
          ),
        ],
      );

      await adjDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        allowOverHistory: true,
      );

      // GL side: settlement leg credits 1000 Cash (NOT 1100 AR).
      final lines =
          await journalLinesForSource('sale_return_adjustments', returnId);
      final acct1000 = await accountIdByCode('1000');
      final acct1100 = await accountIdByCode('1100');
      final cashLines = lines.where((l) => l.accountId == acct1000).toList();
      final arLines = lines.where((l) => l.accountId == acct1100).toList();
      expect(cashLines.length, equals(1),
          reason: 'Cash refund must Cr 1000 Cash');
      expect(cashLines.first.creditCents, equals(15150),
          reason: 'Cr 1000 Cash = full refund (subtotal+tax)');
      expect(arLines, isEmpty,
          reason: 'Cash refund must NEVER touch 1100 AR');

      // Sub-ledger side: customers.balance MUST be unchanged.
      final after = await (db.select(db.customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();
      expect(after.balanceCents.toBigInt().toInt(), equals(50000),
          reason: 'Field bug: customer balance dropped by 15150 here. '
              'Fix gates the side-effect on the JE actually touching 1100 '
              '(it never does for adjustment returns), so balance stays put.');

      // No `customer_transactions` row should be inserted either, because
      // recalculateBalance rebuilds balance from SUM(amount_cents) and
      // would silently re-introduce the bug if the row were present.
      final txCount = await db.customSelect(
        'SELECT COUNT(*) AS cnt FROM customer_transactions '
        'WHERE customer_id = ? AND reference_type = ?',
        variables: [
          Variable.withInt(customerId),
          Variable.withString('sale_return_adjustment'),
        ],
      ).getSingle();
      expect(txCount.read<int>('cnt'), equals(0),
          reason: 'No customer_transactions row may be written for '
              'adjustment sale returns — would drift on recalc.');
    });

    test('cash refund on adjustment purchase return leaves '
        'suppliers.balance untouched', () async {
      await seedData();

      final returnId = await adjDao.createPurchaseAdjReturn(
        PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: 'PAR-REGRESSION-FIELD-0001',
          supplierId: supplierId,
          currencyId: currencyId,
          totalCents: Decimal.fromInt(10000),
          refundMethod: const Value('cash'),
        ),
        [
          PurchaseReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(10000),
          ),
        ],
      );

      await adjDao.postPurchaseAdjReturn(
        returnId,
        journalEntryService: journalService,
        allowOverHistory: true,
      );

      // GL: settlement leg debits 1000 Cash (NOT 2000 AP).
      final lines = await journalLinesForSource(
          'purchase_return_adjustments', returnId);
      final acct1000 = await accountIdByCode('1000');
      final acct2000 = await accountIdByCode('2000');
      final cashLines = lines.where((l) => l.accountId == acct1000).toList();
      final apLines = lines.where((l) => l.accountId == acct2000).toList();
      expect(cashLines.length, equals(1),
          reason: 'Cash refund must Dr 1000 Cash');
      expect(apLines, isEmpty,
          reason: 'Cash refund must NEVER touch 2000 AP');

      // Sub-ledger: suppliers.balance unchanged + no supplier_transactions row.
      final after = await (db.select(db.suppliers)
            ..where((s) => s.id.equals(supplierId)))
          .getSingle();
      expect(after.balanceCents.toBigInt().toInt(), equals(80000),
          reason: 'Cash refund must not move supplier balance.');
      final txCount = await db.customSelect(
        'SELECT COUNT(*) AS cnt FROM supplier_transactions '
        'WHERE supplier_id = ? AND reference_type = ?',
        variables: [
          Variable.withInt(supplierId),
          Variable.withString('purchase_return_adjustment'),
        ],
      ).getSingle();
      expect(txCount.read<int>('cnt'), equals(0),
          reason: 'No supplier_transactions row may be written for cash '
              'adjustment purchase returns — would drift on recalc.');
    });
  });
}
