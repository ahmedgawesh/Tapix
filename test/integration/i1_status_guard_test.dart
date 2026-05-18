import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase I1 — defense-in-depth status guards on edit/delete-item DAO methods.
///
/// The repository layer (`SaleRepositoryImpl.updateSale`,
/// `PurchaseRepositoryImpl.updatePurchase`) already gates edits to
/// draft/pending documents. These tests prove that even if a future caller
/// bypasses the repository and goes straight to the DAO, the same guard
/// fires — preventing silent corruption of stock movements, batch
/// consumptions and the GL on posted/voided documents.
///
/// Coverage:
///   • SaleDao.updateSaleWithItems
///   • PurchaseDao.updatePurchaseWithItems
///   • PurchaseDao.updatePurchaseItem
///   • PurchaseDao.deletePurchaseItem
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late int currencyId;
  late int customerId;
  late int supplierId;

  Future<int> insertProduct() async {
    final pid = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: const Value('I1-P'),
            name: 'I1 product',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            currencyId: Value(currencyId),
            stockQuantity: const Value(0),
          ),
        );
    return pid;
  }

  Future<int> insertVariant(int productId) =>
      db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              stockQuantity: const Value(0),
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
            ),
          );

  /// Insert a sale row directly with the requested status — bypasses the
  /// post pipeline (which we don't need; we're only testing the guard).
  Future<int> insertSale({required String status}) async {
    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-I1-$status',
            customerId: Value(customerId),
            subtotalCents: Decimal.fromInt(200),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(200),
            paidAmountCents: Value(Decimal.fromInt(200)),
            currencyId: currencyId,
            paymentMethod: 'cash',
            status: Value(status),
          ),
        );
    return saleId;
  }

  Future<int> insertPurchase({required String status}) async {
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-I1-$status',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(200),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(200),
            paidAmountCents: Value(Decimal.zero),
            currencyId: currencyId,
            status: Value(status),
            paymentMethod: const Value('credit'),
          ),
        );
    return purchaseId;
  }

  Future<int> insertPurchaseItem({
    required int purchaseId,
    required int productId,
    int? variantId,
  }) =>
      db.into(db.purchaseItems).insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1,
              unitCostCents: Decimal.fromInt(100),
              subtotalCents: Decimal.fromInt(100),
              totalCents: Decimal.fromInt(100),
            ),
          );

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;

    customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(
            name: 'I1 Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'I1 Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  });

  tearDown(() async => db.close());

  Matcher isI1Violation() => isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('I1 violation'),
      );

  // ──────────────────────────────────────────────────────────────────────────
  // 1. SaleDao.updateSaleWithItems
  // ──────────────────────────────────────────────────────────────────────────
  group('SaleDao.updateSaleWithItems — I1 status guard', () {
    test('throws on a "completed" sale', () async {
      final pid = await insertProduct();
      final saleId = await insertSale(status: 'completed');

      expect(
        () => db.saleDao.updateSaleWithItems(
          saleId,
          const SalesCompanion(),
          [
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: pid,
              quantity: 5,
              unitPriceCents: Decimal.fromInt(200),
              subtotalCents: Decimal.fromInt(1000),
              totalCents: Decimal.fromInt(1000),
            ),
          ],
        ),
        throwsA(isI1Violation()),
      );
    });

    test('throws on a "voided" sale', () async {
      final pid = await insertProduct();
      final saleId = await insertSale(status: 'voided');

      expect(
        () => db.saleDao.updateSaleWithItems(
          saleId,
          const SalesCompanion(),
          [
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: pid,
              quantity: 1,
              unitPriceCents: Decimal.fromInt(200),
              subtotalCents: Decimal.fromInt(200),
              totalCents: Decimal.fromInt(200),
            ),
          ],
        ),
        throwsA(isI1Violation()),
      );
    });

    test('passes on a "draft" sale (happy path)', () async {
      final pid = await insertProduct();
      final saleId = await insertSale(status: 'draft');

      final ok = await db.saleDao.updateSaleWithItems(
        saleId,
        const SalesCompanion(),
        [
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: pid,
            quantity: 2,
            unitPriceCents: Decimal.fromInt(200),
            subtotalCents: Decimal.fromInt(400),
            totalCents: Decimal.fromInt(400),
          ),
        ],
      );
      expect(ok, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. PurchaseDao.updatePurchaseWithItems
  // ──────────────────────────────────────────────────────────────────────────
  group('PurchaseDao.updatePurchaseWithItems — I1 status guard', () {
    test('throws on a "posted" purchase', () async {
      final pid = await insertProduct();
      final purchaseId = await insertPurchase(status: 'posted');

      expect(
        () => db.purchaseDao.updatePurchaseWithItems(
          purchaseId,
          const PurchasesCompanion(),
          [
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: pid,
              quantity: 99,
              unitCostCents: Decimal.fromInt(100),
              subtotalCents: Decimal.fromInt(9900),
              totalCents: Decimal.fromInt(9900),
            ),
          ],
        ),
        throwsA(isI1Violation()),
      );
    });

    test('throws on a "voided" purchase', () async {
      final pid = await insertProduct();
      final purchaseId = await insertPurchase(status: 'voided');

      expect(
        () => db.purchaseDao.updatePurchaseWithItems(
          purchaseId,
          const PurchasesCompanion(),
          [
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: pid,
              quantity: 1,
              unitCostCents: Decimal.fromInt(100),
              subtotalCents: Decimal.fromInt(100),
              totalCents: Decimal.fromInt(100),
            ),
          ],
        ),
        throwsA(isI1Violation()),
      );
    });

    test('passes on a "draft" purchase (happy path)', () async {
      final pid = await insertProduct();
      final purchaseId = await insertPurchase(status: 'draft');

      final ok = await db.purchaseDao.updatePurchaseWithItems(
        purchaseId,
        const PurchasesCompanion(),
        [
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: pid,
            quantity: 3,
            unitCostCents: Decimal.fromInt(100),
            subtotalCents: Decimal.fromInt(300),
            totalCents: Decimal.fromInt(300),
          ),
        ],
      );
      expect(ok, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. PurchaseDao.updatePurchaseItem
  // ──────────────────────────────────────────────────────────────────────────
  group('PurchaseDao.updatePurchaseItem — I1 status guard', () {
    test('throws when parent purchase is "posted"', () async {
      final pid = await insertProduct();
      final vid = await insertVariant(pid);
      final purchaseId = await insertPurchase(status: 'posted');
      final itemId = await insertPurchaseItem(
        purchaseId: purchaseId,
        productId: pid,
        variantId: vid,
      );

      expect(
        () => db.purchaseDao.updatePurchaseItem(
          itemId,
          const PurchaseItemsCompanion(quantity: Value(999)),
        ),
        throwsA(isI1Violation()),
      );
    });

    test('passes when parent purchase is "draft"', () async {
      final pid = await insertProduct();
      final vid = await insertVariant(pid);
      final purchaseId = await insertPurchase(status: 'draft');
      final itemId = await insertPurchaseItem(
        purchaseId: purchaseId,
        productId: pid,
        variantId: vid,
      );

      final ok = await db.purchaseDao.updatePurchaseItem(
        itemId,
        const PurchaseItemsCompanion(quantity: Value(7)),
      );
      expect(ok, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. PurchaseDao.deletePurchaseItem
  // ──────────────────────────────────────────────────────────────────────────
  group('PurchaseDao.deletePurchaseItem — I1 status guard', () {
    test('throws when parent purchase is "posted"', () async {
      final pid = await insertProduct();
      final vid = await insertVariant(pid);
      final purchaseId = await insertPurchase(status: 'posted');
      final itemId = await insertPurchaseItem(
        purchaseId: purchaseId,
        productId: pid,
        variantId: vid,
      );

      expect(
        () => db.purchaseDao.deletePurchaseItem(itemId),
        throwsA(isI1Violation()),
      );
    });

    test('passes when parent purchase is "draft"', () async {
      final pid = await insertProduct();
      final vid = await insertVariant(pid);
      final purchaseId = await insertPurchase(status: 'draft');
      final itemId = await insertPurchaseItem(
        purchaseId: purchaseId,
        productId: pid,
        variantId: vid,
      );

      final rows = await db.purchaseDao.deletePurchaseItem(itemId);
      expect(rows, equals(1));
    });
  });
}
