import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/purchases/data/datasources/purchase_local_datasource.dart';
import 'package:tapix/features/purchases/data/repositories/purchase_repository_impl.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';

class _Session extends Fake implements SessionService {
  @override
  Future<int?> getCurrentUserId() async => null;
}

void main() {
  for (final recording in [false, true]) {
    for (final sourceCodes in [false, true]) {
      for (final disposition in ['restock', 'replace', 'write_off']) {
        test(
          'offline purchase $disposition sourceCodes=$sourceCodes recording=$recording lifecycle',
          () async {
            final db = AppDatabase.connect(
              DatabaseConnection(NativeDatabase.memory()),
            );
            addTearDown(db.close);
            await db.seedInitialDataForTest();
            await BranchCurrencyPolicyStore(db).bind('USD');
            final currency = (await (db.select(
              db.currencies,
            )..where((row) => row.code.equals('USD'))).getSingle()).id;
            final supplier = await db
                .into(db.suppliers)
                .insert(
                  SuppliersCompanion.insert(
                    name: 'Synchronized supplier',
                    productCode: const Value('SUP'),
                    currencyId: currency,
                  ),
                );
            final product = await db
                .into(db.products)
                .insert(
                  ProductsCompanion.insert(
                    name: 'Synchronized purchase item',
                    sku: const Value('150'),
                    currencyId: Value(currency),
                    costCents: Decimal.fromInt(500),
                    priceCents: Decimal.fromInt(1000),
                  ),
                );
            final variant = await db
                .into(db.productVariants)
                .insert(
                  ProductVariantsCompanion.insert(
                    productId: product,
                    sku: const Value('150'),
                    costCents: Decimal.fromInt(500),
                    priceCents: Decimal.fromInt(1000),
                  ),
                );
            final journal = JournalEntryService(AccountingRepository(db));
            final repository = PurchaseRepositoryImpl(
              PurchaseLocalDatasourceImpl(
                db.purchaseDao,
                AdjustmentReturnDao(db),
              ),
              AuditLogService(db),
              _Session(),
              journal,
              db,
            );
            final purchaseId = await repository.createPurchase(
              supplierId: supplier,
              currencyId: currency,
              subtotalCents: Decimal.fromInt(2000),
              discountCents: Decimal.zero,
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(2000),
              paidAmountCents: Decimal.zero,
              paymentMethod: 'credit',
              items: [
                PurchaseItemInput(
                  productId: product,
                  variantId: variant,
                  quantity: 2,
                  supplierIdentityRequested: sourceCodes,
                  unitCostCents: Decimal.fromInt(1000),
                  subtotalCents: Decimal.fromInt(2000),
                  discountCents: Decimal.zero,
                  taxCents: Decimal.zero,
                  totalCents: Decimal.fromInt(2000),
                ),
              ],
            );
            if (recording) {
              await OfflineSyncEventStore(db).activateWriterRecording(
                enrollmentId: '41414141-4141-4141-8141-414141414141',
              );
            }

            await repository.postPurchase(purchaseId);
            final purchaseItem = (await repository.getPurchaseItems(
              purchaseId,
            )).single;
            expect(purchaseItem.supplierIdentityId != null, sourceCodes);
            final returnId = await repository.createPurchaseReturn(
              purchaseId: purchaseId,
              currencyId: currency,
              subtotalCents: Decimal.fromInt(1000),
              discountCents: Decimal.zero,
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(1000),
              refundMethod: 'credit',
              dispositionType: disposition,
              reason: disposition == 'write_off'
                  ? 'Vendor approved disposal RMA-12'
                  : null,
              items: [
                PurchaseReturnItemInput(
                  purchaseItemId: purchaseItem.id,
                  quantity: 1,
                  subtotalCents: Decimal.fromInt(1000),
                  discountCents: Decimal.zero,
                  taxCents: Decimal.zero,
                  refundCents: Decimal.fromInt(1000),
                ),
              ],
            );
            expect(
              (await repository.getPurchaseReturnById(
                returnId,
              ))!.dispositionType,
              disposition,
            );
            expect(
              (await (db.select(
                    db.productVariants,
                  )..where((row) => row.id.equals(variant))).getSingle())
                  .stockQuantity,
              1,
            );
            expect(
              (await (db.select(
                    db.suppliers,
                  )..where((row) => row.id.equals(supplier))).getSingle())
                  .balanceCents,
              Decimal.fromInt(1000),
            );
            await repository.voidPurchaseReturn(returnId);
            expect(
              (await (db.select(
                    db.productVariants,
                  )..where((row) => row.id.equals(variant))).getSingle())
                  .stockQuantity,
              2,
            );
            expect(
              (await (db.select(
                    db.suppliers,
                  )..where((row) => row.id.equals(supplier))).getSingle())
                  .balanceCents,
              Decimal.fromInt(2000),
            );
            await repository.voidPurchase(purchaseId);

            final rows = await db
                .customSelect(
                  'SELECT event_type,payload_json FROM sync_outbox_events '
                  'ORDER BY local_sequence',
                )
                .get();
            final journals = await db
                .customSelect(
                  'SELECT journal_entry_id, SUM(debit_cents)-SUM(credit_cents) AS delta FROM journal_entry_lines GROUP BY journal_entry_id',
                )
                .get();
            expect(journals, isNotEmpty);
            expect(
              journals.every((row) => row.read<int>('delta') == 0),
              isTrue,
            );
            if (!recording) {
              expect(rows, isEmpty);
              return;
            }
            expect(rows.map((row) => row.read<String>('event_type')), [
              'purchase.posted.v1',
              'purchase_return.posted.v1',
              'purchase_return.voided.v1',
              'purchase.voided.v1',
            ]);
            final purchasePayload =
                jsonDecode(rows.first.read<String>('payload_json'))
                    as Map<String, dynamic>;
            expect(purchasePayload['contract'], 'purchase.posted');
            expect(purchasePayload['supplierGlobalId'], isNotEmpty);
            expect(purchasePayload['totalMinor'], 2000);
            expect(purchasePayload['inventoryValueMinor'], 2000);
            expect(purchasePayload['items'], hasLength(1));
            expect(
              (purchasePayload['items'] as List)
                      .single['supplierIdentityGlobalId'] !=
                  null,
              sourceCodes,
            );

            final returnPayload =
                jsonDecode(rows[1].read<String>('payload_json'))
                    as Map<String, dynamic>;
            expect(returnPayload['contract'], 'purchase_return.posted');
            expect(returnPayload['sourceDocumentRef']['localId'], returnId);
            expect(returnPayload['originalPurchaseRef']['localId'], purchaseId);
            expect(returnPayload['inventoryValueMinor'], 1000);

            final storedReturn = await (db.select(
              db.purchaseReturns,
            )..where((row) => row.id.equals(returnId))).getSingle();
            expect(storedReturn.voidedAt, isNotNull);
            expect(storedReturn.voidReason, 'User voided purchase return');
          },
        );
      }
    }
  }
}
