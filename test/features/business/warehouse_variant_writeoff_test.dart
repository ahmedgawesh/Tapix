import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/database/daos/product_variant_dao.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:tapix/features/products/data/datasources/variant_local_datasource.dart';
import 'package:tapix/features/products/data/repositories/product_variant_repository_impl.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late ProductVariantRepositoryImpl repo;
  late int variant;
  late String other;

  Future<void> seed(String costing) async {
    db = fixtures.memoryDb();
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      "INSERT INTO users (id, username, password_hash, role, is_active, created_at, updated_at) VALUES (0, 'system', 'no-pin', 'owner', 1, 0, 0)",
    );
    final product = await db.customInsert(
      'INSERT INTO products (name, cost_cents, price_cents, costing_method) VALUES (?, 500, 1000, ?)',
      variables: [
        Variable.withString('Writeoff'),
        Variable.withString(costing),
      ],
    );
    repo = ProductVariantRepositoryImpl(
      VariantLocalDatasourceImpl(
        db.productVariantDao,
        db.productColorDao,
        db.sizeDao,
      ),
      InventoryAdjustmentService(
        db: db,
        dao: InventoryAdjustmentDao(db),
        journal: JournalEntryService(AccountingRepository(db)),
      ),
    );
    variant = await repo.createVariant(
      productId: product,
      costCents: Decimal.fromInt(500),
      priceCents: Decimal.fromInt(1000),
      stockQuantity: 3,
    );
    final scope = await BusinessFoundationRepository(db).getScope();
    other = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: other,
            organizationId: scope.organizationId,
            branchId: scope.branchId,
            code: 'OTHER',
          ),
        );
    await db
        .into(db.businessWarehouseStocks)
        .insert(
          BusinessWarehouseStocksCompanion.insert(
            warehouseId: other,
            variantId: variant,
          ),
        );
  }

  Future<Object> snapshot() async => [
    await fixtures.legacySnapshot(db),
    for (final table in [
      'business_warehouse_stocks',
      'business_document_locations',
    ])
      (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
          .map((r) => r.data)
          .toList(),
  ];

  Future<void> remote(int quantity) async {
    await (db.update(db.businessWarehouseStocks)
          ..where((s) => s.warehouseId.equals(other)))
        .write(BusinessWarehouseStocksCompanion(quantity: Value(quantity)));
  }

  for (final costing in ['wac', 'fifo']) {
    group(costing, () {
      setUp(() => seed(costing));
      tearDown(() => db.close());
      for (final quantity in [5, -5]) {
        test(
          'remote stock $quantity rolls back local shrinkage and journal',
          () async {
            await remote(quantity);
            await db.customStatement(
              'UPDATE business_warehouses SET is_active = 0 WHERE id = ?',
              [other],
            );
            final before = await snapshot();
            await expectLater(
              repo.writeOffAndDeleteVariant(
                variantId: variant,
                reason: 'Damaged',
              ),
              throwsA(isA<VariantStockNotZeroException>()),
            );
            expect(await snapshot(), before);
          },
        );
      }
      test(
        'failure at final deactivation rolls back all financial writes',
        () async {
          final before = await snapshot();
          await db.customStatement(
            "CREATE TRIGGER reject_deactivation BEFORE UPDATE OF is_active ON product_variants WHEN NEW.is_active = 0 BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
          );
          await expectLater(
            repo.writeOffAndDeleteVariant(
              variantId: variant,
              reason: 'Damaged',
            ),
            throwsA(anything),
          );
          expect(await snapshot(), before);
        },
      );
      test(
        'successful writeoff settles inventory and retry does not duplicate journal',
        () async {
          final result = await repo.writeOffAndDeleteVariant(
            variantId: variant,
            reason: 'Damaged',
          );
          expect(result.wasDeleted, isFalse);
          final row = await repo.getVariantById(variant);
          expect(row!.stockQuantity, 0);
          expect(row.isActive, isFalse);
          final journal = await db
              .customSelect(
                'SELECT SUM(debit_cents) AS dr, SUM(credit_cents) AS cr FROM journal_entry_lines',
              )
              .getSingle();
          expect(journal.read<int>('dr'), 3000);
          expect(journal.read<int>('cr'), 3000);
          final inventory = await db
              .customSelect(
                "SELECT SUM(l.debit_cents - l.credit_cents) AS balance FROM journal_entry_lines l JOIN accounts a ON a.id = l.account_id WHERE a.account_code = '1200'",
              )
              .getSingle();
          expect(inventory.read<int>('balance'), 0);
          final entries = (await db.select(db.journalEntries).get()).length;
          await repo.writeOffAndDeleteVariant(
            variantId: variant,
            reason: 'Retry',
          );
          expect(await db.select(db.journalEntries).get(), hasLength(entries));
        },
      );
      test('missing variant remains a no-op', () async {
        final before = await snapshot();
        final result = await repo.writeOffAndDeleteVariant(
          variantId: variant + 100,
          reason: 'Missing',
        );
        expect(result.wasDeleted, isFalse);
        expect(result.referenceCount, 0);
        expect(await snapshot(), before);
      });
    });
  }
}
