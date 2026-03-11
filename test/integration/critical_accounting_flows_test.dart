import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// Integration tests for critical accounting flows against a real in-memory
/// Drift database. These verify end-to-end integrity of:
///   TEST 1: Sale creation → journal entry → stock deduction → customer balance
///   TEST 2: Sale void → journal reversal → stock restoration → customer balance
///   TEST 3: Purchase posting → inventory increase → journal entry → supplier balance
void main() {
  late AppDatabase db;
  late AccountingRepository accountingRepo;
  late JournalEntryService journalService;

  /// Helper: sum all journal entry lines for a given source.
  Future<({int totalDebit, int totalCredit})> journalTotalsForSource(
    String sourceTable,
    int sourceId,
  ) async {
    final rows = await db.customSelect(
      'SELECT jel.debit_cents, jel.credit_cents '
      'FROM journal_entry_lines jel '
      'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
      'WHERE je.source_table = ? AND je.source_id = ? AND je.status = ?',
      variables: [
        Variable.withString(sourceTable),
        Variable.withInt(sourceId),
        Variable.withString('posted'),
      ],
    ).get();

    int totalDebit = 0;
    int totalCredit = 0;
    for (final row in rows) {
      totalDebit += row.read<int>('debit_cents');
      totalCredit += row.read<int>('credit_cents');
    }
    return (totalDebit: totalDebit, totalCredit: totalCredit);
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    accountingRepo = AccountingRepository(db);
    journalService = JournalEntryService(accountingRepo);

    // Force the database to initialize (triggers beforeOpen → seeds accounts)
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  // =========================================================================
  // TEST 1: Sale creation → journal → stock → customer balance
  // =========================================================================
  group('TEST 1: Sale creation end-to-end', () {
    late int currencyId;
    late int productId;
    late int variantId;
    late int customerId;

    setUp(() async {
      // Get the USD currency (seeded by beforeOpen)
      final usd = await (db.select(db.currencies)
            ..where((c) => c.code.equals('USD')))
          .getSingle();
      currencyId = usd.id;

      // Create a product with stock
      productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          sku: const Value<String?>('INTG-PROD-001'),
          name: 'Integration Test Product',
          costCents: Decimal.fromInt(5000), // $50.00
          priceCents: Decimal.fromInt(10000), // $100.00
          currencyId: Value(currencyId),
          stockQuantity: const Value(50),
        ),
      );

      // Create a default variant for the product
      variantId = await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          productId: productId,
          stockQuantity: const Value(50),
          costCents: Decimal.fromInt(5000),
          priceCents: Decimal.fromInt(10000),
        ),
      );

      // Create a customer
      customerId = await db.into(db.customers).insert(
        CustomersCompanion.insert(
          name: 'Test Customer',
          currencyId: currencyId,
          balanceCents: Value(Decimal.zero),
        ),
      );
    });

    test('cash sale: creates journal entry, deducts stock, no customer balance change', () async {
      // Create the sale
      final saleId = await db.into(db.sales).insert(
        SalesCompanion.insert(
          invoiceNumber: 'INV-INT-001',
          customerId: Value(customerId),
          subtotalCents: Decimal.fromInt(10000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(10000),
          paidAmountCents: Value(Decimal.fromInt(10000)),
          currencyId: currencyId,
          paymentMethod: 'cash',
          status: const Value('draft'),
        ),
      );

      // Add sale item
      await db.into(db.saleItems).insert(
        SaleItemsCompanion.insert(
          saleId: saleId,
          productId: productId,
          variantId: Value(variantId),
          quantity: 2,
          unitPriceCents: Decimal.fromInt(5000),
          subtotalCents: Decimal.fromInt(10000),
          totalCents: Decimal.fromInt(10000),
        ),
      );

      // Post the sale via DAO (deducts stock, updates customer)
      await db.saleDao.postSale(saleId);

      // Create journal entry (normally done by repository layer)
      await journalService.recordSaleJournalEntry(
        saleId: saleId,
        totalCents: 10000,
        paidAmountCents: 10000,
        currencyId: currencyId,
        paymentMethod: 'cash',
      );

      // VERIFY: Journal entry is balanced
      final totals = await journalTotalsForSource('sales', saleId);
      expect(totals.totalDebit, equals(totals.totalCredit),
          reason: 'Journal entry must be balanced (debit == credit)');
      expect(totals.totalDebit, equals(10000),
          reason: 'Total debit must equal sale total');

      // VERIFY: Stock deducted
      final variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(48),
          reason: 'Stock should be 50 - 2 = 48');

      // VERIFY: Sale status is completed
      final sale = await db.saleDao.getSaleById(saleId);
      expect(sale!.status, equals('completed'));

      // VERIFY: Customer balance unchanged for cash sale
      final customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();
      expect(customer.balanceCents.toBigInt().toInt(), equals(0),
          reason: 'Cash sale should not affect customer balance');
    });

    test('credit sale: increases customer balance by total amount', () async {
      final saleId = await db.into(db.sales).insert(
        SalesCompanion.insert(
          invoiceNumber: 'INV-INT-002',
          customerId: Value(customerId),
          subtotalCents: Decimal.fromInt(20000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(20000),
          paidAmountCents: Value(Decimal.zero),
          currencyId: currencyId,
          paymentMethod: 'credit',
          status: const Value('draft'),
        ),
      );

      await db.into(db.saleItems).insert(
        SaleItemsCompanion.insert(
          saleId: saleId,
          productId: productId,
          variantId: Value(variantId),
          quantity: 2,
          unitPriceCents: Decimal.fromInt(10000),
          subtotalCents: Decimal.fromInt(20000),
          totalCents: Decimal.fromInt(20000),
        ),
      );

      // Post sale
      await db.saleDao.postSale(saleId);

      // Create journal entry
      await journalService.recordSaleJournalEntry(
        saleId: saleId,
        totalCents: 20000,
        paidAmountCents: 0,
        currencyId: currencyId,
        paymentMethod: 'credit',
      );

      // VERIFY: Journal entry balanced
      final totals = await journalTotalsForSource('sales', saleId);
      expect(totals.totalDebit, equals(totals.totalCredit));
      expect(totals.totalDebit, equals(20000));

      // VERIFY: Stock deducted
      final variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(48));

      // VERIFY: Customer balance increased (credit sale → customer owes us)
      final customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();
      expect(customer.balanceCents.toBigInt().toInt(), equals(20000),
          reason: 'Credit sale should increase customer balance by total');
    });

    test('COGS journal entry: balanced and correct amount', () async {
      final saleId = await db.into(db.sales).insert(
        SalesCompanion.insert(
          invoiceNumber: 'INV-INT-003',
          subtotalCents: Decimal.fromInt(10000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(10000),
          paidAmountCents: Value(Decimal.fromInt(10000)),
          currencyId: currencyId,
          paymentMethod: 'cash',
          status: const Value('draft'),
        ),
      );

      await db.into(db.saleItems).insert(
        SaleItemsCompanion.insert(
          saleId: saleId,
          productId: productId,
          variantId: Value(variantId),
          quantity: 2,
          unitPriceCents: Decimal.fromInt(5000),
          subtotalCents: Decimal.fromInt(10000),
          totalCents: Decimal.fromInt(10000),
        ),
      );

      await db.saleDao.postSale(saleId);

      // Record COGS entry with known cost: 2 units × $50 = $100 (10000 cents)
      // Note: We use a known value here to test journal entry creation.
      // The computeSaleCostCents method is tested separately.
      const knownCostCents = 10000;

      await journalService.recordSaleCOGSJournalEntry(
        saleId: saleId,
        costCents: knownCostCents,
        currencyId: currencyId,
      );

      // VERIFY: COGS journal balanced (entry_type = 'sale_cogs', source_table = 'sales')
      final cogsRows = await db.customSelect(
        'SELECT jel.debit_cents, jel.credit_cents '
        'FROM journal_entry_lines jel '
        'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
        'WHERE je.entry_type = ? AND je.source_id = ? AND je.status = ?',
        variables: [
          Variable.withString('sale_cogs'),
          Variable.withInt(saleId),
          Variable.withString('posted'),
        ],
      ).get();

      int cogsDebit = 0;
      int cogsCredit = 0;
      for (final row in cogsRows) {
        cogsDebit += row.read<int>('debit_cents');
        cogsCredit += row.read<int>('credit_cents');
      }
      expect(cogsDebit, equals(cogsCredit),
          reason: 'COGS journal must be balanced');
      expect(cogsDebit, equals(knownCostCents));
    });
  });

  // =========================================================================
  // TEST 2: Sale void → journal reversal → stock restoration
  // =========================================================================
  group('TEST 2: Sale void end-to-end', () {
    late int currencyId;
    late int productId;
    late int variantId;
    late int customerId;

    setUp(() async {
      final usd = await (db.select(db.currencies)
            ..where((c) => c.code.equals('USD')))
          .getSingle();
      currencyId = usd.id;

      productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          sku: const Value<String?>('VOID-PROD-001'),
          name: 'Void Test Product',
          costCents: Decimal.fromInt(3000),
          priceCents: Decimal.fromInt(8000),
          currencyId: Value(currencyId),
          stockQuantity: const Value(100),
        ),
      );

      variantId = await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          productId: productId,
          stockQuantity: const Value(100),
          costCents: Decimal.fromInt(3000),
          priceCents: Decimal.fromInt(8000),
        ),
      );

      customerId = await db.into(db.customers).insert(
        CustomersCompanion.insert(
          name: 'Void Test Customer',
          currencyId: currencyId,
          balanceCents: Value(Decimal.zero),
        ),
      );
    });

    test('void completed credit sale: restores stock and customer balance', () async {
      // Step 1: Create and post a credit sale
      final saleId = await db.into(db.sales).insert(
        SalesCompanion.insert(
          invoiceNumber: 'INV-VOID-001',
          customerId: Value(customerId),
          subtotalCents: Decimal.fromInt(16000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(16000),
          paidAmountCents: Value(Decimal.zero),
          currencyId: currencyId,
          paymentMethod: 'credit',
          status: const Value('draft'),
        ),
      );

      await db.into(db.saleItems).insert(
        SaleItemsCompanion.insert(
          saleId: saleId,
          productId: productId,
          variantId: Value(variantId),
          quantity: 2,
          unitPriceCents: Decimal.fromInt(8000),
          subtotalCents: Decimal.fromInt(16000),
          totalCents: Decimal.fromInt(16000),
        ),
      );

      // Post the sale (deducts stock, updates customer balance)
      await db.saleDao.postSale(saleId);

      // Verify pre-void state
      final preVoidVariant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(preVoidVariant.stockQuantity, equals(98));

      final preVoidCustomer = await (db.select(db.customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();
      expect(preVoidCustomer.balanceCents.toBigInt().toInt(), equals(16000));

      // Step 2: Void the sale via DAO (restores stock + customer balance)
      // Note: In production, the repository layer voids journal entries first.
      // This test focuses on the DAO-level void which handles stock/balance restoration.
      await db.saleDao.voidSale(saleId);

      // VERIFY: Sale status is voided
      final sale = await db.saleDao.getSaleById(saleId);
      expect(sale!.status, equals('voided'));

      // VERIFY: Stock restored
      final postVoidVariant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(postVoidVariant.stockQuantity, equals(100),
          reason: 'Stock must be restored to original 100');

      // VERIFY: Customer balance restored to 0
      final postVoidCustomer = await (db.select(db.customers)
            ..where((c) => c.id.equals(customerId)))
          .getSingle();
      expect(postVoidCustomer.balanceCents.toBigInt().toInt(), equals(0),
          reason: 'Customer balance must be restored to 0 after void');
    });

    test('void draft sale: no journal reversal needed, no stock change', () async {
      // Create a draft sale (not posted)
      final saleId = await db.into(db.sales).insert(
        SalesCompanion.insert(
          invoiceNumber: 'INV-VOID-002',
          subtotalCents: Decimal.fromInt(5000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(5000),
          currencyId: currencyId,
          paymentMethod: 'cash',
          status: const Value('draft'),
        ),
      );

      await db.into(db.saleItems).insert(
        SaleItemsCompanion.insert(
          saleId: saleId,
          productId: productId,
          variantId: Value(variantId),
          quantity: 1,
          unitPriceCents: Decimal.fromInt(5000),
          subtotalCents: Decimal.fromInt(5000),
          totalCents: Decimal.fromInt(5000),
        ),
      );

      // Stock should be unchanged (draft not posted)
      final preVariant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(preVariant.stockQuantity, equals(100));

      // Void the sale
      await db.saleDao.voidSale(saleId);

      // Stock should still be 100
      final postVariant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(postVariant.stockQuantity, equals(100),
          reason: 'Draft void must not change stock');
    });
  });

  // =========================================================================
  // TEST 3: Purchase posting → inventory increase → journal → supplier balance
  // =========================================================================
  group('TEST 3: Purchase posting end-to-end', () {
    late int currencyId;
    late int productId;
    late int variantId;
    late int supplierId;

    setUp(() async {
      final usd = await (db.select(db.currencies)
            ..where((c) => c.code.equals('USD')))
          .getSingle();
      currencyId = usd.id;

      productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          sku: const Value<String?>('PURCH-PROD-001'),
          name: 'Purchase Test Product',
          costCents: Decimal.fromInt(2000),
          priceCents: Decimal.fromInt(5000),
          currencyId: Value(currencyId),
          stockQuantity: const Value(10),
        ),
      );

      variantId = await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          productId: productId,
          stockQuantity: const Value(10),
          costCents: Decimal.fromInt(2000),
          priceCents: Decimal.fromInt(5000),
        ),
      );

      supplierId = await db.into(db.suppliers).insert(
        SuppliersCompanion.insert(
          name: 'Test Supplier',
          currencyId: currencyId,
          balanceCents: Value(Decimal.zero),
        ),
      );
    });

    test('credit purchase posting: increases stock, creates journal, updates supplier balance', () async {
      // Create a purchase
      final purchaseId = await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          purchaseNumber: 'PO-INT-001',
          supplierId: supplierId,
          subtotalCents: Decimal.fromInt(10000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(10000),
          paidAmountCents: Value(Decimal.zero),
          currencyId: currencyId,
          status: const Value('draft'),
          paymentMethod: const Value('credit'),
        ),
      );

      // Add purchase item: 5 units @ $20 each
      await db.into(db.purchaseItems).insert(
        PurchaseItemsCompanion.insert(
          purchaseId: purchaseId,
          productId: productId,
          variantId: Value(variantId),
          quantity: 5,
          unitCostCents: Decimal.fromInt(2000),
          subtotalCents: Decimal.fromInt(10000),
          totalCents: Decimal.fromInt(10000),
        ),
      );

      // Post the purchase via DAO (increases stock, updates supplier balance)
      await db.purchaseDao.postPurchase(purchaseId);

      // Create journal entry (normally done by repository layer)
      await journalService.recordPurchaseJournalEntry(
        purchaseId: purchaseId,
        totalCents: 10000,
        paidAmountCents: 0,
        currencyId: currencyId,
        paymentMethod: 'credit',
      );

      // VERIFY: Stock increased
      final variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(15),
          reason: 'Stock should be 10 + 5 = 15');

      // VERIFY: Purchase status is posted
      final purchase = await db.purchaseDao.getPurchaseById(purchaseId);
      expect(purchase!.status, equals('posted'));

      // VERIFY: Journal entry is balanced
      final totals = await journalTotalsForSource('purchases', purchaseId);
      expect(totals.totalDebit, equals(totals.totalCredit),
          reason: 'Purchase journal must be balanced');
      expect(totals.totalDebit, equals(10000));

      // VERIFY: Supplier balance increased (we owe supplier)
      final supplier = await (db.select(db.suppliers)
            ..where((s) => s.id.equals(supplierId)))
          .getSingle();
      expect(supplier.balanceCents.toBigInt().toInt(), equals(10000),
          reason: 'Credit purchase should increase supplier balance');
    });

    test('cash purchase posting: no supplier balance change', () async {
      final purchaseId = await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          purchaseNumber: 'PO-INT-002',
          supplierId: supplierId,
          subtotalCents: Decimal.fromInt(6000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(6000),
          paidAmountCents: Value(Decimal.fromInt(6000)),
          currencyId: currencyId,
          status: const Value('draft'),
          paymentMethod: const Value('cash'),
        ),
      );

      await db.into(db.purchaseItems).insert(
        PurchaseItemsCompanion.insert(
          purchaseId: purchaseId,
          productId: productId,
          variantId: Value(variantId),
          quantity: 3,
          unitCostCents: Decimal.fromInt(2000),
          subtotalCents: Decimal.fromInt(6000),
          totalCents: Decimal.fromInt(6000),
        ),
      );

      // Post purchase
      await db.purchaseDao.postPurchase(purchaseId);

      // Create journal entry
      await journalService.recordPurchaseJournalEntry(
        purchaseId: purchaseId,
        totalCents: 6000,
        paidAmountCents: 6000,
        currencyId: currencyId,
        paymentMethod: 'cash',
      );

      // VERIFY: Stock increased
      final variant = await (db.select(db.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingle();
      expect(variant.stockQuantity, equals(13),
          reason: 'Stock should be 10 + 3 = 13');

      // VERIFY: Journal balanced
      final totals = await journalTotalsForSource('purchases', purchaseId);
      expect(totals.totalDebit, equals(totals.totalCredit));
      expect(totals.totalDebit, equals(6000));

      // VERIFY: Supplier balance unchanged for fully paid purchase
      final supplier = await (db.select(db.suppliers)
            ..where((s) => s.id.equals(supplierId)))
          .getSingle();
      expect(supplier.balanceCents.toBigInt().toInt(), equals(0),
          reason: 'Fully paid purchase should not change supplier balance');
    });
  });

  // =========================================================================
  // Accounting invariant: trial balance must always sum to zero
  // =========================================================================
  group('Trial balance invariant', () {
    test('after sale + COGS, trial balance sums to zero', () async {
      final usd = await (db.select(db.currencies)
            ..where((c) => c.code.equals('USD')))
          .getSingle();
      final currencyId = usd.id;

      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          sku: const Value<String?>('TB-PROD-001'),
          name: 'Trial Balance Product',
          costCents: Decimal.fromInt(4000),
          priceCents: Decimal.fromInt(10000),
          currencyId: Value(currencyId),
          stockQuantity: const Value(20),
        ),
      );

      await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          productId: productId,
          stockQuantity: const Value(20),
          costCents: Decimal.fromInt(4000),
          priceCents: Decimal.fromInt(10000),
        ),
      );

      // Record a cash sale journal entry
      final saleId = 999;
      await journalService.recordSaleJournalEntry(
        saleId: saleId,
        totalCents: 10000,
        paidAmountCents: 10000,
        currencyId: currencyId,
        paymentMethod: 'cash',
      );

      // Record COGS
      await journalService.recordSaleCOGSJournalEntry(
        saleId: saleId,
        costCents: 4000,
        currencyId: currencyId,
      );

      // VERIFY: All posted journal entries are balanced (debit == credit per entry)
      final entries = await db.customSelect(
        'SELECT id, total_debit_cents, total_credit_cents '
        'FROM journal_entries WHERE status = ?',
        variables: [Variable.withString('posted')],
      ).get();

      for (final entry in entries) {
        final debit = entry.read<int>('total_debit_cents');
        final credit = entry.read<int>('total_credit_cents');
        expect(debit, equals(credit),
            reason: 'Entry ${entry.read<int>('id')} must be balanced');
      }

      // VERIFY: Net of all posted lines sums to zero
      final netRow = await db.customSelect(
        'SELECT COALESCE(SUM(debit_cents), 0) AS total_d, '
        'COALESCE(SUM(credit_cents), 0) AS total_c '
        'FROM journal_entry_lines jel '
        'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
        'WHERE je.status = ?',
        variables: [Variable.withString('posted')],
      ).getSingle();

      final totalD = netRow.read<int>('total_d');
      final totalC = netRow.read<int>('total_c');
      expect(totalD, equals(totalC),
          reason: 'Trial balance must always sum to zero (total debits == total credits)');
    });
  });
}
