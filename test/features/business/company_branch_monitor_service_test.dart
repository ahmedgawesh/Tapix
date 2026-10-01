import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';
import 'package:tapix/features/business/data/company_branch_monitor_service.dart';
import 'package:tapix/features/business/data/synced_location_report_service.dart';

void main() {
  late AppDatabase db;
  late OfflineSyncEventStore events;
  late SyncInboundProjectionService projections;
  late String organizationId;

  const sourceDatabaseId = '11111111-1111-4111-8111-111111111111';
  const sourceBranchId = '22222222-2222-4222-8222-222222222222';
  const warehouseId = '33333333-3333-4333-8333-333333333333';
  const documentId = '44444444-4444-4444-8444-444444444444';

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    organizationId = await db
        .customSelect(
          'SELECT organization_id FROM business_contexts WHERE id=1',
        )
        .map((row) => row.read<String>('organization_id'))
        .getSingle();
    await db.customStatement(
      '''INSERT INTO business_branches(id,organization_id,code,name,is_active)
      VALUES(?,?,?,?,1)''',
      [sourceBranchId, organizationId, 'CAIRO', 'فرع القاهرة'],
    );
    await db.customStatement(
      '''INSERT INTO business_warehouses(
      id,organization_id,branch_id,code,name,is_active)
      VALUES(?,?,?,?,?,1)''',
      [
        warehouseId,
        organizationId,
        sourceBranchId,
        'CAIRO-MAIN',
        'مخزن القاهرة',
      ],
    );
    events = OfflineSyncEventStore(db);
    projections = SyncInboundProjectionService(db, events);
    await events.enrollSource(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
    );
  });

  tearDown(() => db.close());

  test(
    'remote branch purchase is visible with its branch and warehouse',
    () async {
      await projections.apply(
        _event(
          sequence: 1,
          organizationId: organizationId,
          eventType: 'purchase.posted.v1',
          payload: {
            'contract': 'purchase.posted',
            'contractVersion': 1,
            'documentId': documentId,
            'organizationId': organizationId,
            'branchId': sourceBranchId,
            'warehouseId': warehouseId,
            'purchaseNumber': 'PI-CAIRO-0001',
            'purchaseDate': '2026-09-29T10:00:00.000Z',
            'currencyCode': 'USD',
            'supplierGlobalId': '99999999-9999-4999-8999-999999999999',
            'paymentMethod': 'credit',
            'subtotalMinor': 12500,
            'discountMinor': 0,
            'taxMinor': 0,
            'paidMinor': 0,
            'totalMinor': 12500,
            'itemCount': 1,
            'items': [
              {
                'productName': 'Remote product snapshot',
                'quantityScaled': 2500,
                'quantityScale': 1000,
                'measurementType': 'weight',
                'unitCostMinor': 5000,
                'subtotalMinor': 12500,
                'discountMinor': 0,
                'taxMinor': 0,
                'totalMinor': 12500,
              },
            ],
          },
        ),
      );

      final snapshot = await CompanyBranchMonitorService(
        db,
      ).load(now: DateTime.utc(2026, 9, 29, 10, 1));
      expect(snapshot.documents, hasLength(1));
      final document = snapshot.documents.single;
      expect(document.number, 'PI-CAIRO-0001');
      expect(document.branchName, 'فرع القاهرة');
      expect(document.warehouseName, 'مخزن القاهرة');
      expect(document.kind, CompanyDocumentKind.purchase);
      expect(document.totalMinor, 12500);
      expect(document.paymentMethod, 'credit');
      expect(document.lines, hasLength(1));
      expect(document.lines.single.productName, 'Remote product snapshot');
      expect(document.lines.single.quantityScaled, 2500);
      expect(document.isRemote, isTrue);
    },
  );

  test(
    'void event changes the immutable document status without duplication',
    () async {
      await projections.apply(
        _event(
          sequence: 1,
          organizationId: organizationId,
          eventType: 'sale.posted.v1',
          payload: {
            'contract': 'sale.posted',
            'contractVersion': 1,
            'documentId': documentId,
            'organizationId': organizationId,
            'branchId': sourceBranchId,
            'warehouseId': warehouseId,
            'invoiceNumber': 'SI-CAIRO-0001',
            'saleDate': '2026-09-29T10:00:00.000Z',
            'currencyCode': 'USD',
            'totalMinor': 8000,
            'itemCount': 1,
          },
        ),
      );
      await projections.apply(
        _event(
          sequence: 2,
          eventId: '55555555-5555-4555-8555-555555555555',
          organizationId: organizationId,
          eventType: 'sale.voided.v1',
          payload: {
            'contract': 'sale.voided',
            'contractVersion': 1,
            'documentId': documentId,
            'organizationId': organizationId,
            'branchId': sourceBranchId,
            'warehouseId': warehouseId,
            'invoiceNumber': 'SI-CAIRO-0001',
            'voidedAt': '2026-09-29T10:05:00.000Z',
          },
        ),
      );

      final snapshot = await CompanyBranchMonitorService(db).load();
      expect(snapshot.documents, hasLength(1));
      expect(snapshot.documents.single.isVoided, isTrue);
    },
  );
  test(
    'inventory adjustment is projected for the exact remote warehouse',
    () async {
      const productGlobalId = '77777777-7777-4777-8777-777777777777';
      await projections.apply(
        _event(
          sequence: 1,
          organizationId: organizationId,
          eventType: 'inventory_adjustment.posted.v1',
          payload: {
            'contract': 'inventory_adjustment.posted',
            'contractVersion': 1,
            'documentId': '88888888-8888-4888-8888-888888888888',
            'organizationId': organizationId,
            'branchId': sourceBranchId,
            'warehouseId': warehouseId,
            'adjustmentNumber': 'IA-CAIRO-1',
            'adjustmentType': 'opening_balance',
            'productGlobalId': productGlobalId,
            'quantityDeltaScaled': 3000,
            'unitCostMinor': 200,
            'totalValueMinor': 600,
            'currencyCode': 'USD',
            'postedAt': '2026-09-29T10:00:00.000Z',
          },
        ),
      );

      final snapshot = await CompanyBranchMonitorService(db).load();
      expect(snapshot.inventoryMovements, hasLength(1));
      final movement = snapshot.inventoryMovements.single;
      expect(movement.branchId, sourceBranchId);
      expect(movement.warehouseId, warehouseId);
      expect(movement.productGlobalId, productGlobalId);
      expect(movement.quantityScaled, 3000);
      expect(movement.valueMinor, 600);
      expect(movement.reference, 'IA-CAIRO-1');
    },
  );
  test('damaged sale return keeps money but does not restore stock', () async {
    await projections.apply(
      _event(
        sequence: 1,
        organizationId: organizationId,
        eventType: 'sale_return.posted.v1',
        payload: {
          'contract': 'sale_return.posted',
          'contractVersion': 1,
          'documentId': documentId,
          'organizationId': organizationId,
          'branchId': sourceBranchId,
          'warehouseId': warehouseId,
          'returnNumber': 'SR-DAMAGED-1',
          'returnDate': '2026-09-29T10:00:00.000Z',
          'currencyCode': 'USD',
          'restoresSellableStock': false,
          'subtotalMinor': 1000,
          'discountMinor': 0,
          'taxMinor': 0,
          'paidMinor': 0,
          'totalMinor': 1000,
          'itemCount': 1,
          'items': [
            {
              'productGlobalId': '77777777-7777-4777-8777-777777777777',
              'quantityScaled': 1,
              'quantityScale': 1,
              'measurementType': 'piece',
              'tracksInventory': true,
              'subtotalMinor': 1000,
              'discountMinor': 0,
              'taxMinor': 0,
              'refundMinor': 1000,
              'inventoryValueMinor': 400,
            },
          ],
        },
      ),
    );

    final snapshot = await CompanyBranchMonitorService(db).load();
    final line = snapshot.documents.single.lines.single;
    expect(line.totalMinor, 1000);
    expect(line.inventoryQuantityScaled, 0);
    expect(line.inventoryClassificationKnown, isTrue);
  });

  test(
    'company reports merge locally owned legacy purchase and return once',
    () async {
      final currencyId = await db
          .customSelect("SELECT id FROM currencies WHERE code='USD'")
          .map((row) => row.read<int>('id'))
          .getSingle();
      final local = await db
          .customSelect(
            'SELECT database_id,branch_id FROM sync_local_state WHERE id=1',
          )
          .getSingle();
      final localDatabaseId = local.read<String>('database_id');
      final localBranchId = local.read<String>('branch_id');
      final localWarehouseId = await db
          .customSelect(
            '''SELECT id FROM business_warehouses
            WHERE branch_id=? AND location_kind='branch_store' LIMIT 1''',
            variables: [Variable.withString(localBranchId)],
          )
          .map((row) => row.read<String>('id'))
          .getSingle();

      await db.customStatement(
        'INSERT INTO suppliers(name,currency_id) VALUES(?,?)',
        ['شركة الأمل للتوريدات', currencyId],
      );
      final supplierId = await db
          .customSelect(
            "SELECT id FROM suppliers WHERE name='شركة الأمل للتوريدات'",
          )
          .map((row) => row.read<int>('id'))
          .getSingle();
      await db.customStatement(
        '''INSERT INTO products(name,sku,cost_cents,price_cents,currency_id)
        VALUES(?,?,?,?,?)''',
        ['عصير برتقال', 'ORANGE-LOCAL', 1200, 2000, currencyId],
      );
      final productId = await db
          .customSelect("SELECT id FROM products WHERE sku='ORANGE-LOCAL'")
          .map((row) => row.read<int>('id'))
          .getSingle();
      await db.customStatement(
        '''INSERT INTO purchases(purchase_number,supplier_id,subtotal_cents,
        tax_cents,total_cents,currency_id,status,payment_method,purchase_date)
        VALUES(?,?,?,?,?,?,?,?,?)''',
        [
          'PI-LOCAL-ORANGE',
          supplierId,
          12000,
          0,
          12000,
          currencyId,
          'posted',
          'credit',
          '2026-09-30T08:00:00.000Z',
        ],
      );
      final purchaseId = await db
          .customSelect(
            "SELECT id FROM purchases WHERE purchase_number='PI-LOCAL-ORANGE'",
          )
          .map((row) => row.read<int>('id'))
          .getSingle();
      await db.customStatement(
        '''INSERT INTO purchase_items(purchase_id,product_id,quantity,
        quantity_scale,measurement_type,unit_cost_cents,subtotal_cents,
        tax_cents,total_cents,inventory_value_at_post_cents)
        VALUES(?,?,?,?,?,?,?,?,?,?)''',
        [purchaseId, productId, 10, 1, 'piece', 1200, 12000, 0, 12000, 12000],
      );
      final purchaseItemId = await db
          .customSelect(
            'SELECT id FROM purchase_items WHERE purchase_id=?',
            variables: [Variable.withInt(purchaseId)],
          )
          .map((row) => row.read<int>('id'))
          .getSingle();
      await db.customStatement(
        '''INSERT INTO purchase_returns(purchase_id,return_number,
        subtotal_cents,tax_cents,total_cents,currency_id,status,refund_method,
        return_date) VALUES(?,?,?,?,?,?,?,?,?)''',
        [
          purchaseId,
          'PR-LOCAL-ORANGE',
          2400,
          0,
          2400,
          currencyId,
          'posted',
          'credit',
          '2026-09-30T09:00:00.000Z',
        ],
      );
      final returnId = await db
          .customSelect(
            "SELECT id FROM purchase_returns WHERE return_number='PR-LOCAL-ORANGE'",
          )
          .map((row) => row.read<int>('id'))
          .getSingle();
      await db.customStatement(
        '''INSERT INTO purchase_return_items(return_id,purchase_item_id,
        quantity,quantity_scale,measurement_type,subtotal_cents,tax_cents,
        refund_cents,unit_cost_at_post_cents,inventory_value_at_post_cents)
        VALUES(?,?,?,?,?,?,?,?,?,?)''',
        [returnId, purchaseItemId, 2, 1, 'piece', 2400, 0, 2400, 1200, 2400],
      );

      final purchaseLocation = await db
          .customSelect(
            '''SELECT document_id,branch_id,warehouse_id
            FROM business_document_locations
            WHERE source_table='purchases' AND source_id=?''',
            variables: [Variable.withInt(purchaseId)],
          )
          .getSingle();
      expect(purchaseLocation.read<String>('branch_id'), localBranchId);
      expect(purchaseLocation.read<String>('warehouse_id'), localWarehouseId);

      // A modern copy of the same document in the outbox must not duplicate
      // the locally authoritative row in company totals.
      await events.transaction(
        (transaction) => transaction.append(
          eventType: 'purchase.posted.v1',
          aggregateType: 'purchase',
          aggregateId: purchaseLocation.read<String>('document_id'),
          payload: {
            'documentId': purchaseLocation.read<String>('document_id'),
            'organizationId': organizationId,
            'branchId': localBranchId,
            'warehouseId': localWarehouseId,
            'purchaseNumber': 'PI-LOCAL-ORANGE',
            'purchaseDate': '2026-09-30T08:00:00.000Z',
            'currencyCode': 'USD',
            'totalMinor': 12000,
            'itemCount': 0,
          },
          occurredAt: DateTime.utc(2026, 9, 30, 8),
        ),
      );

      final snapshot = await CompanyBranchMonitorService(db).load();
      final localDocuments = snapshot.documents
          .where((document) => document.sourceDatabaseId == localDatabaseId)
          .toList();
      expect(localDocuments, hasLength(2));
      expect(
        localDocuments.map((document) => document.number),
        containsAll(['PI-LOCAL-ORANGE', 'PR-LOCAL-ORANGE']),
      );
      final purchase = localDocuments.singleWhere(
        (document) => document.kind == CompanyDocumentKind.purchase,
      );
      expect(purchase.partyName, 'شركة الأمل للتوريدات');
      expect(purchase.lines.single.productName, 'عصير برتقال');
      expect(purchase.lines.single.quantityScaled, 10);

      final report =
          await SyncedLocationReportService(
            CompanyBranchMonitorService(db),
          ).load(
            reportKey: 'reports.purchases_by_supplier',
            scope: const SyncedReportScope.company(),
            from: DateTime.utc(2026),
            toExclusive: DateTime.utc(2027),
          );
      expect(report.grossDocumentCount, 1);
      expect(report.returnDocumentCount, 1);
      expect(report.grossTotalsByCurrency, {'USD': 12000});
      expect(report.returnTotalsByCurrency, {'USD': 2400});
      expect(report.netTotalsByCurrency, {'USD': 9600});
      expect(report.rows.single.label, 'شركة الأمل للتوريدات');
      expect(report.rows.single.amountMinor, 12000);
      expect(report.rows.single.documentCount, 1);
    },
  );
}

SyncEventEnvelope _event({
  required int sequence,
  required String organizationId,
  required String eventType,
  required Map<String, Object?> payload,
  String eventId = '66666666-6666-4666-8666-666666666666',
}) {
  final draft = SyncEventEnvelope(
    eventId: eventId,
    sourceDatabaseId: '11111111-1111-4111-8111-111111111111',
    organizationId: organizationId,
    branchId: '22222222-2222-4222-8222-222222222222',
    sequence: sequence,
    eventType: eventType,
    aggregateType: eventType.startsWith('purchase') ? 'purchase' : 'sale',
    aggregateId: '44444444-4444-4444-8444-444444444444',
    contractVersion: 1,
    payload: payload,
    occurredAt: DateTime.utc(2026, 9, 29, 10, sequence),
    eventHash: '',
  );
  return SyncEventEnvelope(
    eventId: draft.eventId,
    sourceDatabaseId: draft.sourceDatabaseId,
    organizationId: draft.organizationId,
    branchId: draft.branchId,
    sequence: draft.sequence,
    eventType: draft.eventType,
    aggregateType: draft.aggregateType,
    aggregateId: draft.aggregateId,
    contractVersion: draft.contractVersion,
    payload: draft.payload,
    occurredAt: draft.occurredAt,
    eventHash: OfflineSyncTransaction.eventHashFor(draft),
  );
}
