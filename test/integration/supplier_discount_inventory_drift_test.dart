// ════════════════════════════════════════════════════════════════════════════
// REGRESSION — Supplier discount JE must not credit Inventory (1200).
// ════════════════════════════════════════════════════════════════════════════
//
// Field report (2026-05-17, backup tapix_backup_20260517_182011.db): after
// recording a $9.90 discount from the supplier profile screen, the
// Reconciliation & Health screen flagged:
//
//     Inventory mismatch: GL(journal_lines)=276210, Σ(stock×cost)=277200
//
// Root cause: `JournalEntryService.recordDirectSupplierDiscountJournalEntry`
// posted Dr 2000 / Cr **1200** (Inventory). Crediting Inventory in the GL
// without a matching stock-side movement (no `products.cost_cents`,
// `product_variants.cost_cents`, or `stock_batches.cost_cents` update)
// permanently drove GL inventory below the on-hand carrying value
// Σ(stock × cost).
//
// Fix: route the credit to NEW account `4900 Purchase Discounts Earned`
// (revenue / "other income"). Stock layers are untouched, Σ(stock × cost)
// is unchanged, and the discount is correctly recognised as income —
// IFRS/GAAP-conformant treatment of an unallocated supplier rebate that
// cannot be allocated back to specific PO lines without a full landed-
// cost recalculation engine.
//
// What is pinned here
// -------------------
//  1. After a supplier discount is recorded, the JE has exactly two lines:
//     Dr 2000 Accounts Payable and Cr 4900 Purchase Discounts Earned.
//     Neither line touches Inventory (1200).
//  2. Account 4900 is seeded by the chart-of-accounts seeder, classified
//     as `revenue`, system account.
//  3. The end-to-end invariant: after a supplier discount, the GL
//     Inventory balance equals Σ(stock × cost) — no drift.
//  4. The LedgerRebuildService produces correct accounting when replaying
//     a supplier-discount transaction (so users with the historical bad
//     posting can recover their books).
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/ledger_rebuild_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/suppliers/data/datasources/supplier_local_datasource.dart';
import 'package:tapix/features/suppliers/data/repositories/supplier_repository_impl.dart';
import 'package:tapix/features/suppliers/domain/repositories/supplier_repository.dart';

void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late SupplierRepositoryImpl supplierRepo;
  late int currencyId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);

    supplierRepo = SupplierRepositoryImpl(
      SupplierLocalDatasourceImpl(db.supplierDao),
      SessionService(),
      journal,
      db,
      AuditLogService(db),
    );

    // Force schema init + default-account seed.
    await db.customSelect('SELECT 1').get();

    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;

    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'Discount Test Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(100000)), // we owe 1000.00
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  test('account 4900 Purchase Discounts Earned is seeded as revenue', () async {
    final acct = await (db.select(db.accounts)
          ..where((a) => a.accountCode.equals('4900')))
        .getSingleOrNull();
    expect(acct, isNotNull,
        reason: '4900 must be seeded by _seedDefaultAccounts');
    expect(acct!.accountName, 'Purchase Discounts Earned');
    expect(acct.accountType, 'revenue');
    expect(acct.isSystemAccount, isTrue);
  });

  test(
      'supplier discount JE posts Dr 2000 / Cr 4900 — NEVER touches Inventory (1200)',
      () async {
    await supplierRepo.recordDiscount(
      supplierId: supplierId,
      amountCents: 990, // matches the field-report drift exactly
      currencyId: currencyId,
      description: 'Seasonal rebate',
    );

    // Find the supplier_discount JE.
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.entryType.equals('supplier_discount')))
        .get();
    expect(entries, hasLength(1),
        reason: 'recordDiscount must produce exactly one JE');
    final entryId = entries.single.id;

    // Pull lines + account codes.
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

    expect(byCode.keys.toSet(), equals({'2000', '4900'}),
        reason: 'JE must touch exactly AP (2000) and Purchase Discounts '
            'Earned (4900) — no Inventory (1200)');
    expect(byCode['2000']!.debit, equals(990));
    expect(byCode['2000']!.credit, equals(0));
    expect(byCode['4900']!.debit, equals(0));
    expect(byCode['4900']!.credit, equals(990));

    // Guard rail: assert 1200 was NEVER credited, even cross-line.
    expect(byCode.containsKey('1200'), isFalse,
        reason: 'Inventory (1200) must NEVER appear on a supplier-discount JE');
  });

  test(
      'no inventory drift after supplier discount: GL(1200) == Σ(stock × cost)',
      () async {
    // Seed a product+variant pair (StockService requires a variantId).
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: const Value('DRIFT-1'),
            name: 'Drift Test Product',
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

    // Post a purchase so GL Inventory is non-zero AND aligned with stock.
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-DRIFT-1',
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
    // PurchaseDao.postPurchase only mutates stock layers; the JE is the
    // repository's responsibility in production. Drive the production JE
    // helper directly so the GL Inventory balance matches Σ(stock × cost).
    await journal.recordPurchaseJournalEntry(
      purchaseId: purchaseId,
      totalCents: 10000,
      paidAmountCents: 0, // credit purchase
      currencyId: currencyId,
    );

    // Snapshot pre-discount.
    final glPre = await _inventoryGlNetDebit(db);
    final stockPre = await _sumStockTimesCost(db);
    // Diagnostic dump on mismatch — surfaces Decimal/int storage drift
    // (Drift sometimes serialises Decimal-typed columns as TEXT, which
    // breaks naive `CAST(... AS INTEGER) * CAST(... AS INTEGER)` SQL).
    if (glPre != stockPre) {
      final vRows = await db.customSelect(
        'SELECT id, stock_quantity, cost_cents, '
        'typeof(stock_quantity) AS sq_type, typeof(cost_cents) AS cc_type '
        'FROM product_variants',
      ).get();
      // ignore: avoid_print
      print('product_variants snapshot: '
          '${vRows.map((r) => r.data).toList()}');
    }
    expect(glPre, equals(stockPre),
        reason: 'baseline invariant: GL inventory == Σ(stock × cost)');

    // Apply a $9.90 supplier discount — the exact scenario from the field
    // backup that produced the 990-cent drift in the buggy build.
    await supplierRepo.recordDiscount(
      supplierId: supplierId,
      amountCents: 990,
      currencyId: currencyId,
      description: 'Field-report regression',
    );

    // Post-discount invariant: GL Inventory unchanged, Σ(stock × cost)
    // unchanged, both equal. The discount lives on 4900, not 1200.
    final glPost = await _inventoryGlNetDebit(db);
    final stockPost = await _sumStockTimesCost(db);

    expect(glPost, equals(glPre),
        reason: 'GL Inventory must NOT move when a supplier discount is '
            'recorded (no stock-side movement happened).');
    expect(stockPost, equals(stockPre),
        reason: 'Σ(stock × cost) must NOT move (no stock-side movement).');
    expect(glPost, equals(stockPost),
        reason: 'invariant must hold after the discount (no drift)');
  });

  test('LedgerRebuildService produces correct accounting on rebuild',
      () async {
    // First record the discount via the production path.
    await supplierRepo.recordDiscount(
      supplierId: supplierId,
      amountCents: 990,
      currencyId: currencyId,
    );

    final accounting = AccountingRepository(db);
    final rebuild = LedgerRebuildService(
      db: db,
      accountingRepo: accounting,
      journalService: journal,
    );

    final report = await rebuild.rebuild(confirmationToken: true);
    expect(report.errors, isEmpty,
        reason: 'rebuild must complete without errors');

    // After rebuild, the supplier_discount JE has the same shape:
    // Dr 2000 / Cr 4900 — proving the rebuild path also avoids 1200.
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.entryType.equals('supplier_discount')))
        .get();
    expect(entries, hasLength(1));

    final lines = await (db.select(db.journalEntryLines).join([
      innerJoin(
        db.accounts,
        db.accounts.id.equalsExp(db.journalEntryLines.accountId),
      ),
    ])
          ..where(
              db.journalEntryLines.journalEntryId.equals(entries.single.id)))
        .get();

    final codes = lines
        .map((r) => r.readTable(db.accounts).accountCode)
        .toSet();
    expect(codes, equals({'2000', '4900'}),
        reason: 'rebuilt JE must use the new accounts');
    expect(codes.contains('1200'), isFalse);
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
  // Delegate to the SAME production SoT that ReconciliationHealthService
  // uses to compute Σ(stock × cost). Sharing the helper guarantees the
  // test pins the actual user-visible invariant rather than a reasonable-
  // looking duplicate.
  final ds = JournalLocalDatasourceImpl(AccountingDao(db));
  return ds.getTotalInventoryValueCents();
}
