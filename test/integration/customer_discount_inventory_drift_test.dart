// ════════════════════════════════════════════════════════════════════════════
// DEFENSE-IN-DEPTH — Customer discount JE must never credit Inventory (1200).
// ════════════════════════════════════════════════════════════════════════════
//
// The supplier-discount side (`recordDirectSupplierDiscountJournalEntry`) was
// found posting `Dr 2000 / Cr 1200` instead of `Dr 2000 / Cr 4900`, which
// permanently drove GL Inventory below the on-hand carrying value. The
// symmetric concern on the customer side is whether
// `recordDirectCustomerDiscountJournalEntry` (invoked when the cashier
// records a discount from the customer-profile screen) might ALSO touch
// Inventory by mistake — it must NOT, because granting a price concession to
// a customer is a revenue-side contra (Discounts Given expense), not a
// stock movement.
//
// This test pins:
//   1. The JE posts EXACTLY two lines: Dr 5500 Discounts Given (expense),
//      Cr 1100 Accounts Receivable.
//   2. Inventory (1200) is NEVER referenced — verified end-to-end via the
//      shared `getTotalInventoryValueCents()` SoT.
//   3. After the discount, GL(1200) == Σ(stock × cost) — the same invariant
//      that the supplier-side fix protects, asserted symmetrically here.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/customers/data/datasources/customer_local_datasource.dart';
import 'package:tapix/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:tapix/features/customers/domain/repositories/customer_repository.dart';

void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late CustomerRepositoryImpl customerRepo;
  late int currencyId;
  late int customerId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);

    customerRepo = CustomerRepositoryImpl(
      CustomerLocalDatasourceImpl(db.customerDao),
      AuditLogService(db),
      SessionService(),
      journal,
      db,
    );

    await db.customSelect('SELECT 1').get();

    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;

    customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(
            name: 'Discount Test Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(50000)), // owes us 500.00
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  test(
      'customer discount JE posts Dr 5500 / Cr 1100 — NEVER touches Inventory (1200)',
      () async {
    await customerRepo.recordDiscount(
      customerId: customerId,
      amountCents: 990,
      currencyId: currencyId,
      description: 'Loyalty rebate',
    );

    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.entryType.equals('customer_discount')))
        .get();
    expect(entries, hasLength(1));
    final entryId = entries.single.id;

    final lines = await (db.select(db.journalEntryLines).join([
      innerJoin(
        db.accounts,
        db.accounts.id.equalsExp(db.journalEntryLines.accountId),
      ),
    ])
          ..where(db.journalEntryLines.journalEntryId.equals(entryId)))
        .get();

    final byCode = <String, ({int debit, int credit})>{};
    for (final row in lines) {
      final code = row.readTable(db.accounts).accountCode;
      final jl = row.readTable(db.journalEntryLines);
      byCode[code] = (
        debit: jl.debitCents.toBigInt().toInt(),
        credit: jl.creditCents.toBigInt().toInt(),
      );
    }

    expect(byCode.keys.toSet(), equals({'5500', '1100'}),
        reason: 'JE must touch exactly Discounts Given (5500) and AR (1100) '
            '— no Inventory (1200), no revenue line, no cash');
    expect(byCode['5500']!.debit, equals(990));
    expect(byCode['5500']!.credit, equals(0));
    expect(byCode['1100']!.debit, equals(0));
    expect(byCode['1100']!.credit, equals(990));

    expect(byCode.containsKey('1200'), isFalse,
        reason: 'Inventory (1200) must NEVER appear on a customer-discount JE');
  });

  test(
      'no inventory drift after customer discount: GL(1200) == Σ(stock × cost)',
      () async {
    // Seed a product+variant pair and post a purchase JE so 1200 is
    // non-zero and aligned with the stock-side Σ before we exercise the
    // customer-discount path.
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: const Value('CDRIFT-1'),
            name: 'Customer Drift Product',
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
            currencyId: Value(currencyId),
            stockQuantity: const Value(0),
            hasVariants: const Value(true),
          ),
        );
    final variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
          ),
        );
    // Open a tiny supplier purely so the purchase posting has a counterparty.
    final supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'Aux Supplier',
            currencyId: currencyId,
          ),
        );
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-CDRIFT-1',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(10000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(10000),
            currencyId: currencyId,
            status: const Value('draft'),
            paymentMethod: const Value('credit'),
          ),
        );
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: 10,
            unitCostCents: Decimal.fromInt(1000),
            subtotalCents: Decimal.fromInt(10000),
            totalCents: Decimal.fromInt(10000),
          ),
        );
    await db.purchaseDao.postPurchase(purchaseId);
    await journal.recordPurchaseJournalEntry(
      purchaseId: purchaseId,
      totalCents: 10000,
      paidAmountCents: 0,
      currencyId: currencyId,
    );

    final glPre = await _inventoryGlNetDebit(db);
    final stockPre = await _sumStockTimesCost(db);
    expect(glPre, equals(stockPre),
        reason: 'baseline invariant: GL inventory == Σ(stock × cost)');

    // Apply a $9.90 customer discount — the symmetric scenario.
    await customerRepo.recordDiscount(
      customerId: customerId,
      amountCents: 990,
      currencyId: currencyId,
    );

    final glPost = await _inventoryGlNetDebit(db);
    final stockPost = await _sumStockTimesCost(db);

    expect(glPost, equals(glPre),
        reason: 'GL Inventory must NOT move when a customer discount is '
            'recorded (no stock-side movement happened).');
    expect(stockPost, equals(stockPre),
        reason: 'Σ(stock × cost) must NOT move (no stock-side movement).');
    expect(glPost, equals(stockPost),
        reason: 'invariant must hold after the customer discount (no drift)');
  });
}

Future<int> _inventoryGlNetDebit(AppDatabase db) async {
  final row = await db.customSelect(
    'SELECT COALESCE(SUM(jl.debit_cents - jl.credit_cents), 0) AS net '
    'FROM journal_entry_lines jl '
    'JOIN journal_entries je ON je.id = jl.journal_entry_id '
    'JOIN accounts a ON a.id = jl.account_id '
    "WHERE je.status = 'posted' AND a.account_code = '1200'",
  ).getSingle();
  return row.read<int>('net');
}

Future<int> _sumStockTimesCost(AppDatabase db) async {
  final ds = JournalLocalDatasourceImpl(AccountingDao(db));
  return ds.getTotalInventoryValueCents();
}
