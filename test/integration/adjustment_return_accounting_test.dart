import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
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
    final rows = await db
        .customSelect(
          'SELECT jel.account_id, jel.debit_cents, jel.credit_cents '
          'FROM journal_entry_lines jel '
          'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
          'WHERE je.source_table = ? AND je.source_id = ? AND je.status = ?',
          variables: [
            Variable.withString(sourceTable),
            Variable.withInt(sourceId),
            Variable.withString('posted'),
          ],
        )
        .get();

    return rows
        .map(
          (r) => (
            accountId: r.read<int>('account_id'),
            debitCents: r.read<int>('debit_cents'),
            creditCents: r.read<int>('credit_cents'),
          ),
        )
        .toList();
  }

  /// Helper: sum debits and credits.
  ({int totalDebit, int totalCredit}) sumLines(
    List<({int accountId, int debitCents, int creditCents})> lines,
  ) {
    int d = 0, c = 0;
    for (final l in lines) {
      d += l.debitCents;
      c += l.creditCents;
    }
    return (totalDebit: d, totalCredit: c);
  }

  /// Helper: look up account id by code.
  Future<int> accountIdByCode(String code) async {
    final row = await db
        .customSelect(
          'SELECT id FROM accounts WHERE account_code = ?',
          variables: [Variable.withString(code)],
        )
        .getSingle();
    return row.read<int>('id');
  }

  /// Helper: check if reversed journal entries exist for a source.
  Future<int> reversedJournalCount(String sourceTable, int sourceId) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS cnt FROM journal_entries '
          'WHERE source_table = ? AND source_id = ? AND is_reversed = 1',
          variables: [
            Variable.withString(sourceTable),
            Variable.withInt(sourceId),
          ],
        )
        .getSingle();
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
    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;

    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value<String?>('ADJ-PROD-001'),
            name: 'Adj Return Test Product',
            costCents: Decimal.fromInt(3000), // $30.00
            priceCents: Decimal.fromInt(5000), // $50.00
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
            name: 'Adj Test Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(50000)), // owes $500
          ),
        );

    supplierId = await db
        .into(db.suppliers)
        .insert(
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
            sourceResolution: const Value('unverified'),
            sourceResolutionReason: const Value('test fixture'),
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
      final lines = await journalLinesForSource(
        'sale_return_adjustments',
        returnId,
      );
      final totals = sumLines(lines);

      // VERIFY: Balanced
      expect(
        totals.totalDebit,
        equals(totals.totalCredit),
        reason: 'JE must be balanced',
      );

      // VERIFY: 4 lines
      expect(
        lines.length,
        equals(4),
        reason: 'Should have 4 lines (financial + inventory)',
      );

      // VERIFY: Financial side
      final acct5700 = await accountIdByCode('5700');
      final acct1100 = await accountIdByCode('1100');
      final financial5700 = lines
          .where((l) => l.accountId == acct5700)
          .toList();
      final financial1100 = lines
          .where((l) => l.accountId == acct1100)
          .toList();

      expect(
        financial5700.length,
        equals(1),
        reason: 'One line for Sales Return Adj (5700)',
      );
      expect(
        financial5700.first.debitCents,
        equals(10000),
        reason: 'Dr Sales Return Adj = total',
      );
      expect(financial1100.length, equals(1), reason: 'One line for AR (1100)');
      expect(
        financial1100.first.creditCents,
        equals(10000),
        reason: 'Cr AR = total',
      );

      // VERIFY: Inventory side
      final acct1200 = await accountIdByCode('1200');
      final acct5300 = await accountIdByCode('5300');
      final inv1200 = lines.where((l) => l.accountId == acct1200).toList();
      final inv5300 = lines.where((l) => l.accountId == acct5300).toList();

      expect(
        inv1200.length,
        equals(1),
        reason: 'One line for Inventory (1200)',
      );
      expect(
        inv1200.first.debitCents,
        greaterThan(0),
        reason: 'Dr Inventory > 0 (cost-based)',
      );
      expect(inv5300.length, equals(1), reason: 'One line for COGS (5300)');
      expect(inv5300.first.creditCents, greaterThan(0), reason: 'Cr COGS > 0');

      // VERIFY: Inventory cost = qty * unitCostCents
      // unitCostCents was auto-fetched as 3000 (product cost)
      expect(
        inv1200.first.debitCents,
        equals(6000),
        reason: 'Inventory Dr = 2 * 3000',
      );
      expect(
        inv5300.first.creditCents,
        equals(6000),
        reason: 'COGS Cr = 2 * 3000',
      );

      // VERIFY: Stock increased (sale return adds stock back)
      final variant = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).getSingle();
      expect(
        variant.stockQuantity,
        equals(102),
        reason: 'Stock should be 100 + 2 = 102',
      );

      // VERIFY: Customer balance REDUCED by the refund.
      // A CREDIT adjustment sale return now reduces `customers.balance_cents`
      // (the 1100 AR sub-ledger) by the refund total — the customer owes us
      // less. This keeps the AR sub-ledger reconciled 1:1 with the GL 1100
      // credit posted above (Cr AR = 10000). Seed was 50000; after a $100
      // credit return the customer owes 40000.
      final customer = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();
      expect(
        customer.balanceCents.toBigInt().toInt(),
        equals(40000),
        reason:
            'Credit adjustment sale return must reduce customer '
            'balance by the refund (50000 - 10000 = 40000).',
      );

      // VERIFY: A customer_transactions row surfaces the credit return.
      final txns = await (db.select(
        db.customerTransactions,
      )..where((t) => t.customerId.equals(customerId))).get();
      final adjTxn = txns
          .where((t) => t.transactionType == 'adjustment_return')
          .toList();
      expect(
        adjTxn.length,
        equals(1),
        reason: 'One adjustment_return customer transaction expected.',
      );
      expect(
        adjTxn.first.amountCents.toBigInt().toInt(),
        equals(-10000),
        reason: 'Transaction amount = -refund (reduces receivable).',
      );
    });

    test(
      'voidSaleAdjReturn creates reversal and restores stock/balance',
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
              sourceResolution: const Value('unverified'),
              sourceResolutionReason: const Value('test fixture'),
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
        var variant = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variantId))).getSingle();
        expect(variant.stockQuantity, equals(101));

        // Void
        await adjDao.voidSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
        );

        // VERIFY: Original JE is reversed
        final reversedCount = await reversedJournalCount(
          'sale_return_adjustments',
          returnId,
        );
        expect(
          reversedCount,
          greaterThan(0),
          reason: 'Original JE should be reversed',
        );

        // VERIFY: Stock restored
        variant = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variantId))).getSingle();
        expect(
          variant.stockQuantity,
          equals(100),
          reason: 'Stock should return to original 100',
        );

        // VERIFY: Customer balance RESTORED to seed through post + void.
        // The credit post reduced the balance by 5000 (50000 -> 45000); the
        // void writes the exact reversal (+5000), restoring 50000. This pins
        // the post/void symmetry on the AR sub-ledger.
        final customer = await (db.select(
          db.customers,
        )..where((c) => c.id.equals(customerId))).getSingle();
        expect(
          customer.balanceCents.toBigInt().toInt(),
          equals(50000),
          reason:
              'Customer balance must return to the seed value after '
              'post (-5000) then void (+5000) of a credit adjustment return.',
        );

        // VERIFY: reversal customer transaction present.
        final txns = await (db.select(
          db.customerTransactions,
        )..where((t) => t.customerId.equals(customerId))).get();
        expect(
          txns.where((t) => t.transactionType == 'adjustment_return').length,
          equals(1),
          reason: 'Original adjustment_return row remains.',
        );
        expect(
          txns
              .where((t) => t.transactionType == 'adjustment_return_reversal')
              .length,
          equals(1),
          reason: 'Void writes one adjustment_return_reversal row.',
        );
      },
    );
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
        'purchase_return_adjustments',
        returnId,
      );
      final totals = sumLines(lines);

      // VERIFY: Balanced
      expect(
        totals.totalDebit,
        equals(totals.totalCredit),
        reason: 'JE must be balanced',
      );

      // VERIFY: 4 lines
      expect(
        lines.length,
        equals(4),
        reason: 'Should have 4 lines (financial + inventory)',
      );

      // VERIFY: Financial side — Dr AP (2000), Cr PurchaseRetAdj (4100)
      final acct2000 = await accountIdByCode('2000');
      final acct4100 = await accountIdByCode('4100');
      final fin2000 = lines.where((l) => l.accountId == acct2000).toList();
      final fin4100 = lines.where((l) => l.accountId == acct4100).toList();

      expect(fin2000.length, equals(1));
      expect(fin2000.first.debitCents, equals(15000), reason: 'Dr AP = total');
      expect(fin4100.length, equals(1));
      expect(
        fin4100.first.creditCents,
        equals(15000),
        reason: 'Cr Purchase Ret Adj = total',
      );

      // VERIFY: Inventory side — Dr COGS (5300), Cr Inventory (1200)
      final acct5300 = await accountIdByCode('5300');
      final acct1200 = await accountIdByCode('1200');
      final inv5300 = lines.where((l) => l.accountId == acct5300).toList();
      final inv1200 = lines.where((l) => l.accountId == acct1200).toList();

      expect(inv5300.length, equals(1));
      expect(
        inv5300.first.debitCents,
        equals(9000),
        reason: 'Dr COGS = 3 * 3000',
      );
      expect(inv1200.length, equals(1));
      expect(
        inv1200.first.creditCents,
        equals(9000),
        reason: 'Cr Inventory = 3 * 3000',
      );

      // VERIFY: Stock decreased (purchase return sends stock back)
      final variant = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variantId))).getSingle();
      expect(
        variant.stockQuantity,
        equals(97),
        reason: 'Stock should be 100 - 3 = 97',
      );

      // VERIFY: Supplier balance decreased
      final supplier = await (db.select(
        db.suppliers,
      )..where((s) => s.id.equals(supplierId))).getSingle();
      expect(
        supplier.balanceCents.toBigInt().toInt(),
        equals(65000),
        reason: 'Supplier balance: 80000 - 15000 = 65000',
      );
    });

    test(
      'voidPurchaseAdjReturn creates reversal and restores stock/balance',
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
        var variant = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variantId))).getSingle();
        expect(variant.stockQuantity, equals(99));

        // Void
        await adjDao.voidPurchaseAdjReturn(
          returnId,
          journalEntryService: journalService,
        );

        // VERIFY: Original JE reversed
        final reversedCount = await reversedJournalCount(
          'purchase_return_adjustments',
          returnId,
        );
        expect(reversedCount, greaterThan(0));

        // VERIFY: Stock restored
        variant = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variantId))).getSingle();
        expect(
          variant.stockQuantity,
          equals(100),
          reason: 'Stock should return to 100',
        );

        // VERIFY: Supplier balance restored
        final supplier = await (db.select(
          db.suppliers,
        )..where((s) => s.id.equals(supplierId))).getSingle();
        expect(
          supplier.balanceCents.toBigInt().toInt(),
          equals(80000),
          reason: 'Supplier balance should be restored to 80000',
        );
      },
    );
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
      final initialBalance = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();
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
            sourceResolution: const Value('unverified'),
            sourceResolutionReason: const Value('test fixture'),
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
      final lines = await journalLinesForSource(
        'sale_return_adjustments',
        returnId,
      );
      final acct1000 = await accountIdByCode('1000');
      final acct1100 = await accountIdByCode('1100');
      final cashLines = lines.where((l) => l.accountId == acct1000).toList();
      final arLines = lines.where((l) => l.accountId == acct1100).toList();
      expect(
        cashLines.length,
        equals(1),
        reason: 'Cash refund must Cr 1000 Cash',
      );
      expect(
        cashLines.first.creditCents,
        equals(15150),
        reason: 'Cr 1000 Cash = full refund (subtotal+tax)',
      );
      expect(arLines, isEmpty, reason: 'Cash refund must NEVER touch 1100 AR');

      // Sub-ledger side: customers.balance MUST be unchanged.
      final after = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(customerId))).getSingle();
      expect(
        after.balanceCents.toBigInt().toInt(),
        equals(50000),
        reason:
            'Field bug: customer balance dropped by 15150 here. '
            'Fix gates the side-effect on the JE actually touching 1100 '
            '(it never does for adjustment returns), so balance stays put.',
      );

      // No `customer_transactions` row should be inserted either, because
      // recalculateBalance rebuilds balance from SUM(amount_cents) and
      // would silently re-introduce the bug if the row were present.
      final txCount = await db
          .customSelect(
            'SELECT COUNT(*) AS cnt FROM customer_transactions '
            'WHERE customer_id = ? AND reference_type = ?',
            variables: [
              Variable.withInt(customerId),
              Variable.withString('sale_return_adjustment'),
            ],
          )
          .getSingle();
      expect(
        txCount.read<int>('cnt'),
        equals(0),
        reason:
            'No customer_transactions row may be written for '
            'adjustment sale returns — would drift on recalc.',
      );
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
        'purchase_return_adjustments',
        returnId,
      );
      final acct1000 = await accountIdByCode('1000');
      final acct2000 = await accountIdByCode('2000');
      final cashLines = lines.where((l) => l.accountId == acct1000).toList();
      final apLines = lines.where((l) => l.accountId == acct2000).toList();
      expect(
        cashLines.length,
        equals(1),
        reason: 'Cash refund must Dr 1000 Cash',
      );
      expect(apLines, isEmpty, reason: 'Cash refund must NEVER touch 2000 AP');

      // Sub-ledger: suppliers.balance unchanged + no supplier_transactions row.
      final after = await (db.select(
        db.suppliers,
      )..where((s) => s.id.equals(supplierId))).getSingle();
      expect(
        after.balanceCents.toBigInt().toInt(),
        equals(80000),
        reason: 'Cash refund must not move supplier balance.',
      );
      final txCount = await db
          .customSelect(
            'SELECT COUNT(*) AS cnt FROM supplier_transactions '
            'WHERE supplier_id = ? AND reference_type = ?',
            variables: [
              Variable.withInt(supplierId),
              Variable.withString('purchase_return_adjustment'),
            ],
          )
          .getSingle();
      expect(
        txCount.read<int>('cnt'),
        equals(0),
        reason:
            'No supplier_transactions row may be written for cash '
            'adjustment purchase returns — would drift on recalc.',
      );
    });
  });

  // =========================================================================
  // COMMISSION: adjustment sale return attributed to a salesperson must
  // DEDUCT their commission (field report tapix_backup_20260705_235704.db).
  // =========================================================================
  group('Adjustment sale return — salesperson commission deduction', () {
    late CommissionService commissionService;
    late int employeeId;

    Future<List<Commission>> commissionsByAdj(int adjId) {
      return (db.select(
        db.commissions,
      )..where((c) => c.saleReturnAdjustmentId.equals(adjId))).get();
    }

    Future<void> seedEmployee({int rateBps = 100}) async {
      commissionService = CommissionService(db.employeeDao);
      employeeId = await db.employeeDao.createEmployee(
        EmployeesCompanion.insert(
          name: 'bero',
          currencyId: currencyId,
          commissionType: const Value('percentage'),
          defaultCommissionRateBps: Value(rateBps),
        ),
      );
    }

    test(
      'post deducts commission = (subtotal − discount) × rate; void removes it',
      () async {
        await seedData();
        await seedEmployee(rateBps: 100); // 1%

        // Field shape: subtotal 20000, discount 100 → net 19900 × 1% = 199.
        final returnId = await adjDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-COMM-0001',
            customerId: Value(customerId),
            employeeId: Value(employeeId),
            currencyId: currencyId,
            subtotalCents: Value(Decimal.fromInt(20000)),
            discountCents: Value(Decimal.fromInt(100)),
            taxCents: Value(Decimal.fromInt(199)),
            totalCents: Decimal.fromInt(20099),
            refundMethod: const Value('cash'),
            returnDate: Value(DateTime(2026, 6, 30)),
          ),
          [
            SaleReturnAdjustmentItemsCompanion.insert(
              sourceResolution: const Value('unverified'),
              sourceResolutionReason: const Value('test fixture'),
              returnId: 0,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(20000),
              totalCents: Decimal.fromInt(20099),
            ),
          ],
        );

        await adjDao.postSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
          commissionService: commissionService,
        );

        final rows = await commissionsByAdj(returnId);
        expect(
          rows.length,
          equals(1),
          reason:
              'A negative commission row must be created for the '
              'salesperson attributed to the adjustment return.',
        );
        expect(
          rows.single.commissionAmountCents.toBigInt().toInt(),
          equals(-199),
          reason: 'Deduction = (20000 − 100) × 1% = 199, stored negative.',
        );
        expect(rows.single.saleId, equals(null));
        expect(rows.single.period, equals('2026-06'));

        // Void must delete the reversal exactly.
        await adjDao.voidSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
          commissionService: commissionService,
        );
        expect(
          await commissionsByAdj(returnId),
          isEmpty,
          reason: 'Voiding the adjustment return must remove the deduction.',
        );
      },
    );

    test('no commission row when return has no attributed employee', () async {
      await seedData();
      commissionService = CommissionService(db.employeeDao);

      final returnId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-COMM-0002',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(10000),
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            sourceResolution: const Value('unverified'),
            sourceResolutionReason: const Value('test fixture'),
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(10000),
          ),
        ],
      );

      await adjDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        allowOverHistory: true,
        commissionService: commissionService,
      );

      expect(await commissionsByAdj(returnId), isEmpty);
    });
  });

  // =========================================================================
  // BATCH NAMING: an unlinked sale-adjustment return on a batch-tracked
  // (FIFO) product must materialise a batch NAMED AFTER its SAR document, so
  // the Batch Management report identifies it as an *unlinked* return and it
  // can never be confused with a LINKED `SR-…` sale-return document.
  //
  // Field report tapix_backup_20260706_033510.db: SAR-202607-0001/0003
  // created batches numbered `SR-202607-V…`, which the user read as LINKED
  // returns (their linked returns use the `SR-YYYYMM-NNNN` scheme).
  // =========================================================================
  group('Unlinked sale return batch naming (traceable to SAR document)', () {
    late int fifoProductId;
    late int fifoVariantId;

    Future<void> seedFifoProduct() async {
      fifoProductId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('ADJ-FIFO-001'),
              name: 'Batch-tracked Adj Return Product',
              costCents: Decimal.fromInt(3000),
              priceCents: Decimal.fromInt(5000),
              currencyId: Value(currencyId),
              // Batch-tracked so postSaleAdjReturn materialises a batch.
              costingMethod: const Value('fifo'),
              inventoryTrackingType: const Value('batch'),
              // Start at 0 so the FIFO invariant Σ(batch.remaining)==stock holds
              // (the return itself is the only batch/stock movement).
              stockQuantity: const Value(0),
            ),
          );
      fifoVariantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: fifoProductId,
              stockQuantity: const Value(0),
              costCents: Decimal.fromInt(3000),
              priceCents: Decimal.fromInt(5000),
            ),
          );
    }

    test(
      'batch_number is derived from the SAR return number, never SR-',
      () async {
        await seedData();
        await seedFifoProduct();

        const returnNumber = 'SAR-202607-0001';
        final returnId = await adjDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: returnNumber,
            customerId: Value(customerId),
            currencyId: currencyId,
            totalCents: Decimal.fromInt(5000),
            refundMethod: const Value('cash'),
          ),
          [
            SaleReturnAdjustmentItemsCompanion.insert(
              sourceResolution: const Value('unverified'),
              sourceResolutionReason: const Value('test fixture'),
              returnId: 0,
              productId: fifoProductId,
              variantId: Value(fifoVariantId),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(5000),
              totalCents: Decimal.fromInt(5000),
            ),
          ],
        );

        await adjDao.postSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
        );

        final batches = await (db.select(
          db.productBatches,
        )..where((b) => b.productId.equals(fifoProductId))).get();
        expect(
          batches.length,
          equals(1),
          reason: 'One batch must be materialised for the unlinked return.',
        );
        final batch = batches.single;
        expect(batch.source, equals('sale_return'));
        expect(
          batch.batchNumber.startsWith('$returnNumber-'),
          isTrue,
          reason:
              'Batch must be named after its SAR document so it is '
              'traceable in the Batch Management report. Got '
              '"${batch.batchNumber}".',
        );
        expect(
          batch.batchNumber.startsWith('SR-'),
          isFalse,
          reason: 'Must NOT collide with linked SR- return document numbers.',
        );
      },
    );
  });
}
