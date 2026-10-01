import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/business/data/company_branch_monitor_service.dart';
import 'package:tapix/features/business/data/synced_location_report_service.dart';

class _Monitor extends CompanyBranchMonitorService {
  _Monitor(super.db, this.snapshot);

  final CompanyBranchMonitorSnapshot snapshot;

  @override
  Future<CompanyBranchMonitorSnapshot> load({DateTime? now}) async => snapshot;
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() => db.close());

  test(
    'remote supplier sales report is warehouse scoped and nets returns',
    () async {
      final at = DateTime.utc(2026, 9, 30, 12);
      CompanyDocumentLineSnapshot line({
        required int total,
        required int cost,
        required int quantity,
      }) => CompanyDocumentLineSnapshot(
        productName: 'Product',
        variantName: 'Variant',
        quantityScaled: quantity,
        quantityScale: 1,
        measurementType: 'piece',
        unitMinor: total ~/ quantity,
        subtotalMinor: total,
        discountMinor: 0,
        taxMinor: 0,
        totalMinor: total,
        supplierNames: const ['Supplier A'],
        inventoryValueMinor: cost,
      );
      CompanyDocumentSnapshot document({
        required String id,
        required String warehouse,
        required CompanyDocumentKind kind,
        required int total,
        required int cost,
        required int quantity,
      }) => CompanyDocumentSnapshot(
        documentId: id,
        sourceDatabaseId: 'remote-db',
        branchId: 'cairo',
        branchName: 'Cairo',
        warehouseId: warehouse,
        warehouseName: warehouse,
        kind: kind,
        number: id,
        documentDate: at,
        currencyCode: 'USD',
        totalMinor: total,
        itemCount: 1,
        isRemote: true,
        isVoided: false,
        occurredAt: at,
        subtotalMinor: total,
        lines: [line(total: total, cost: cost, quantity: quantity)],
      );
      final snapshot = CompanyBranchMonitorSnapshot(
        locations: const [],
        documents: [
          document(
            id: 'sale',
            warehouse: 'floor',
            kind: CompanyDocumentKind.sale,
            total: 8000,
            cost: 3000,
            quantity: 2,
          ),
          document(
            id: 'return',
            warehouse: 'floor',
            kind: CompanyDocumentKind.saleReturn,
            total: 2000,
            cost: 800,
            quantity: 1,
          ),
          document(
            id: 'other',
            warehouse: 'other-warehouse',
            kind: CompanyDocumentKind.sale,
            total: 99000,
            cost: 1000,
            quantity: 1,
          ),
        ],
        generatedAt: at,
      );
      final service = SyncedLocationReportService(_Monitor(db, snapshot));

      final supplier = await service.load(
        reportKey: 'reports.sales_by_supplier',
        branchId: 'cairo',
        warehouseId: 'floor',
        from: DateTime.utc(2026),
        toExclusive: DateTime.utc(2027),
      );
      expect(supplier.documentCount, 2);
      expect(supplier.rows, hasLength(1));
      expect(supplier.rows.single.label, 'Supplier A');
      expect(supplier.rows.single.amountMinor, 6000);
      expect(supplier.rows.single.quantity, 1);

      final profit = await service.load(
        reportKey: 'reports.profit_by_product',
        branchId: 'cairo',
        warehouseId: 'floor',
        from: DateTime.utc(2026),
        toExclusive: DateTime.utc(2027),
      );
      expect(profit.rows.single.amountMinor, 6000);
      expect(profit.rows.single.costMinor, 2200);
      expect(profit.rows.single.profitMinor, 3800);
      expect(profit.profitByCurrency, {'USD': 3800});
    },
  );

  test('voided documents appear only in cancelled report', () async {
    final at = DateTime.utc(2026, 9, 30);
    final voided = CompanyDocumentSnapshot(
      documentId: 'void',
      sourceDatabaseId: 'remote-db',
      branchId: 'cairo',
      branchName: 'Cairo',
      warehouseId: 'floor',
      warehouseName: 'Floor',
      kind: CompanyDocumentKind.sale,
      number: 'SI-VOID',
      documentDate: at,
      currencyCode: 'USD',
      totalMinor: 1000,
      itemCount: 0,
      isRemote: true,
      isVoided: true,
      occurredAt: at,
    );
    final voidedPurchase = CompanyDocumentSnapshot(
      documentId: 'void-purchase',
      sourceDatabaseId: 'remote-db',
      branchId: 'cairo',
      branchName: 'Cairo',
      warehouseId: 'floor',
      warehouseName: 'Floor',
      kind: CompanyDocumentKind.purchase,
      number: 'PI-VOID',
      documentDate: at,
      currencyCode: 'USD',
      totalMinor: 2000,
      itemCount: 0,
      isRemote: true,
      isVoided: true,
      occurredAt: at,
    );
    final service = SyncedLocationReportService(
      _Monitor(
        db,
        CompanyBranchMonitorSnapshot(
          locations: const [],
          documents: [voided, voidedPurchase],
          generatedAt: at,
        ),
      ),
    );

    Future<SyncedLocationReportData> load(String key) => service.load(
      reportKey: key,
      branchId: 'cairo',
      warehouseId: 'floor',
      from: DateTime.utc(2026),
      toExclusive: DateTime.utc(2027),
    );

    expect((await load('reports.all_sales')).rows, isEmpty);
    expect(
      (await load('reports.cancelled_invoices')).rows.single.label,
      'SI-VOID',
    );
    expect(
      (await load('reports.cancelled_purchases')).rows.single.label,
      'PI-VOID',
    );
  });
  test(
    'purchase orders are not confused with posted purchase invoices',
    () async {
      final at = DateTime.utc(2026, 9, 30);
      CompanyDocumentSnapshot purchase(String id, String paymentMethod) =>
          CompanyDocumentSnapshot(
            documentId: id,
            sourceDatabaseId: 'remote-db',
            branchId: 'cairo',
            branchName: 'Cairo',
            warehouseId: 'floor',
            warehouseName: 'Floor',
            kind: CompanyDocumentKind.purchase,
            number: id,
            documentDate: at,
            currencyCode: 'USD',
            totalMinor: 1000,
            itemCount: 0,
            isRemote: true,
            isVoided: false,
            occurredAt: at,
            paymentMethod: paymentMethod,
          );
      final service = SyncedLocationReportService(
        _Monitor(
          db,
          CompanyBranchMonitorSnapshot(
            locations: const [],
            documents: [
              purchase('normal', 'cash'),
              purchase('order', 'purchaseOrder'),
            ],
            generatedAt: at,
          ),
        ),
      );

      final result = await service.load(
        reportKey: 'reports.purchase_orders',
        branchId: 'cairo',
        warehouseId: 'floor',
        from: DateTime.utc(2026),
        toExclusive: DateTime.utc(2027),
      );

      expect(result.documentCount, 1);
      expect(result.rows.single.label, 'order');
    },
  );

  test('supplier sales split money by immutable source quantities', () async {
    final at = DateTime.utc(2026, 9, 30);
    final document = CompanyDocumentSnapshot(
      documentId: 'sale',
      sourceDatabaseId: 'remote-db',
      branchId: 'cairo',
      branchName: 'Cairo',
      warehouseId: 'floor',
      warehouseName: 'Floor',
      kind: CompanyDocumentKind.sale,
      number: 'SI-1',
      documentDate: at,
      currencyCode: 'USD',
      totalMinor: 101,
      itemCount: 1,
      isRemote: true,
      isVoided: false,
      occurredAt: at,
      subtotalMinor: 101,
      lines: const [
        CompanyDocumentLineSnapshot(
          productName: 'Mixed source product',
          variantName: null,
          quantityScaled: 4,
          quantityScale: 1,
          measurementType: 'piece',
          unitMinor: 0,
          subtotalMinor: 101,
          discountMinor: 0,
          taxMinor: 0,
          totalMinor: 101,
          supplierAllocations: [
            CompanySupplierAllocationSnapshot(
              name: 'Supplier A',
              quantityScaled: 1,
              sourceQuality: 'verified',
            ),
            CompanySupplierAllocationSnapshot(
              name: 'Supplier B',
              quantityScaled: 3,
              sourceQuality: 'verified',
            ),
          ],
        ),
      ],
    );
    final service = SyncedLocationReportService(
      _Monitor(
        db,
        CompanyBranchMonitorSnapshot(
          locations: const [],
          documents: [document],
          generatedAt: at,
        ),
      ),
    );

    final result = await service.load(
      reportKey: 'reports.sales_by_supplier',
      branchId: 'cairo',
      warehouseId: 'floor',
      from: DateTime.utc(2026),
      toExclusive: DateTime.utc(2027),
    );

    expect(result.rows.map((row) => row.amountMinor), containsAll([25, 76]));
    expect(result.rows.fold<int>(0, (sum, row) => sum + row.amountMinor), 101);
    expect(result.rows.fold<double>(0, (sum, row) => sum + row.quantity), 4);
  });

  test('commission report uses recorded entries including reversals', () async {
    final at = DateTime.utc(2026, 9, 30);
    CompanyDocumentSnapshot document({
      required String id,
      required CompanyDocumentKind kind,
      required int commissionMinor,
    }) => CompanyDocumentSnapshot(
      documentId: id,
      sourceDatabaseId: 'remote-db',
      branchId: 'cairo',
      branchName: 'Cairo',
      warehouseId: 'floor',
      warehouseName: 'Floor',
      kind: kind,
      number: id,
      documentDate: at,
      currencyCode: 'USD',
      totalMinor: kind == CompanyDocumentKind.sale ? 5000 : 1000,
      itemCount: 0,
      isRemote: true,
      isVoided: false,
      occurredAt: at,
      operatorLabel: 'Mona',
      commissionMinor: commissionMinor,
      commissionDataKnown: true,
    );
    final service = SyncedLocationReportService(
      _Monitor(
        db,
        CompanyBranchMonitorSnapshot(
          locations: const [],
          documents: [
            document(
              id: 'sale',
              kind: CompanyDocumentKind.sale,
              commissionMinor: 123,
            ),
            document(
              id: 'return',
              kind: CompanyDocumentKind.saleReturn,
              commissionMinor: -23,
            ),
          ],
          generatedAt: at,
        ),
      ),
    );

    final result = await service.load(
      reportKey: 'reports.salespeople_commission',
      branchId: 'cairo',
      warehouseId: 'floor',
      from: DateTime.utc(2026),
      toExclusive: DateTime.utc(2027),
    );

    expect(result.rows.single.label, 'Mona');
    expect(result.rows.single.amountMinor, 100);
    expect(result.hasLegacyGaps, isFalse);
  });

  test(
    'inventory balance includes synchronized adjustments before the period',
    () async {
      final movementAt = DateTime.utc(2026, 1, 5);
      final generatedAt = DateTime.utc(2026, 9, 30);
      final service = SyncedLocationReportService(
        _Monitor(
          db,
          CompanyBranchMonitorSnapshot(
            locations: const [],
            documents: const [],
            generatedAt: generatedAt,
            inventoryMovements: [
              CompanyInventoryMovementSnapshot(
                movementId: 'adjustment',
                branchId: 'cairo',
                warehouseId: 'floor',
                productName: 'Opening product',
                quantityScaled: 5000,
                quantityScale: 1000,
                measurementType: 'weight',
                valueMinor: 2500,
                currencyCode: 'USD',
                occurredAt: movementAt,
              ),
            ],
          ),
        ),
      );

      final result = await service.load(
        reportKey: 'reports.inventory_reports',
        branchId: 'cairo',
        warehouseId: 'floor',
        from: DateTime.utc(2026, 9),
        toExclusive: DateTime.utc(2027),
      );

      expect(result.rows.single.label, 'Opening product');
      expect(result.rows.single.quantity, 5);
      expect(result.rows.single.amountMinor, 2500);
      expect(result.generatedAt, movementAt);
    },
  );
  test(
    'location, branch, and company scopes never bleed into each other',
    () async {
      final at = DateTime.utc(2026, 9, 30, 12);
      CompanyDocumentSnapshot purchase({
        required String id,
        required String branch,
        required String warehouse,
        required int total,
      }) => CompanyDocumentSnapshot(
        documentId: id,
        sourceDatabaseId: 'db-$branch',
        branchId: branch,
        branchName: branch,
        warehouseId: warehouse,
        warehouseName: warehouse,
        kind: CompanyDocumentKind.purchase,
        number: 'PI-$id',
        documentDate: at,
        currencyCode: 'USD',
        totalMinor: total,
        itemCount: 1,
        isRemote: true,
        isVoided: false,
        occurredAt: at,
        partyName: 'Supplier A',
        subtotalMinor: total,
        lines: [
          CompanyDocumentLineSnapshot(
            productName: 'Product $id',
            variantName: null,
            quantityScaled: 1,
            quantityScale: 1,
            measurementType: 'piece',
            unitMinor: total,
            subtotalMinor: total,
            discountMinor: 0,
            taxMinor: 0,
            totalMinor: total,
          ),
        ],
      );
      final service = SyncedLocationReportService(
        _Monitor(
          db,
          CompanyBranchMonitorSnapshot(
            locations: const [],
            generatedAt: at,
            documents: [
              purchase(
                id: 'cairo-floor',
                branch: 'cairo',
                warehouse: 'floor',
                total: 1000,
              ),
              purchase(
                id: 'cairo-store',
                branch: 'cairo',
                warehouse: 'store',
                total: 2000,
              ),
              purchase(
                id: 'main-floor',
                branch: 'main',
                warehouse: 'main-floor',
                total: 9000,
              ),
            ],
          ),
        ),
      );

      Future<SyncedLocationReportData> load(SyncedReportScope scope) =>
          service.load(
            reportKey: 'reports.purchases_by_supplier',
            scope: scope,
            from: DateTime.utc(2026),
            toExclusive: DateTime.utc(2027),
          );

      final location = await load(
        const SyncedReportScope.location(
          branchId: 'cairo',
          warehouseId: 'floor',
        ),
      );
      expect(location.documentCount, 1);
      expect(location.totalsByCurrency, {'USD': 1000});
      expect(
        location.rows.single.documents.map((document) => document.documentId),
        ['cairo-floor'],
      );

      final branch = await load(const SyncedReportScope.branch('cairo'));
      expect(branch.documentCount, 2);
      expect(branch.totalsByCurrency, {'USD': 3000});
      expect(
        branch.rows.single.documents.map((document) => document.documentId),
        containsAll(['cairo-floor', 'cairo-store']),
      );

      final company = await load(const SyncedReportScope.company());
      expect(company.documentCount, 3);
      expect(company.totalsByCurrency, {'USD': 12000});
      expect(company.rows.single.documents, hasLength(3));
    },
  );

  test('inventory movement reports include posted return documents', () async {
    final at = DateTime.utc(2026, 9, 30, 12);
    final returned = CompanyDocumentSnapshot(
      documentId: 'return-1',
      sourceDatabaseId: 'remote-db',
      branchId: 'cairo',
      branchName: 'Cairo',
      warehouseId: 'floor',
      warehouseName: 'Floor',
      kind: CompanyDocumentKind.saleReturn,
      number: 'SR-1',
      documentDate: at,
      currencyCode: 'USD',
      totalMinor: 500,
      itemCount: 1,
      isRemote: true,
      isVoided: false,
      occurredAt: at,
      lines: const [
        CompanyDocumentLineSnapshot(
          productName: 'Returned product',
          variantName: null,
          quantityScaled: 1,
          quantityScale: 1,
          measurementType: 'piece',
          unitMinor: 500,
          subtotalMinor: 500,
          discountMinor: 0,
          taxMinor: 0,
          totalMinor: 500,
          inventoryQuantityScaled: 1,
          inventoryClassificationKnown: true,
          inventoryValueMinor: 300,
        ),
      ],
    );
    final service = SyncedLocationReportService(
      _Monitor(
        db,
        CompanyBranchMonitorSnapshot(
          locations: const [],
          documents: [returned],
          generatedAt: at,
        ),
      ),
    );

    final result = await service.load(
      reportKey: 'reports.stock_movement_report',
      branchId: 'cairo',
      warehouseId: 'floor',
      from: DateTime.utc(2026),
      toExclusive: DateTime.utc(2027),
    );

    expect(result.rows.single.label, 'Returned product');
    expect(result.rows.single.quantity, 1);
    expect(result.rows.single.documents.single.documentId, 'return-1');
  });

  test(
    'purchase tax nets linked and adjustment returns by exact location',
    () async {
      final at = DateTime.utc(2026, 10, 1, 10);
      CompanyDocumentSnapshot document({
        required String id,
        required CompanyDocumentKind kind,
        required int tax,
        String branch = 'cairo',
        String warehouse = 'floor',
      }) => CompanyDocumentSnapshot(
        documentId: id,
        sourceDatabaseId: 'db-$branch',
        branchId: branch,
        branchName: branch,
        warehouseId: warehouse,
        warehouseName: warehouse,
        kind: kind,
        number: id,
        documentDate: at,
        currencyCode: 'USD',
        totalMinor: tax * 10,
        subtotalMinor: tax * 9,
        taxMinor: tax,
        itemCount: 1,
        isRemote: true,
        isVoided: false,
        occurredAt: at,
        lines: [
          CompanyDocumentLineSnapshot(
            productName: id,
            variantName: null,
            quantityScaled: 1,
            quantityScale: 1,
            measurementType: 'piece',
            unitMinor: tax * 9,
            subtotalMinor: tax * 9,
            discountMinor: 0,
            taxMinor: tax,
            totalMinor: tax * 10,
          ),
        ],
      );
      final service = SyncedLocationReportService(
        _Monitor(
          db,
          CompanyBranchMonitorSnapshot(
            locations: const [],
            generatedAt: at,
            documents: [
              document(
                id: 'PI-1',
                kind: CompanyDocumentKind.purchase,
                tax: 150,
              ),
              document(
                id: 'PR-1',
                kind: CompanyDocumentKind.purchaseReturn,
                tax: 30,
              ),
              document(
                id: 'PRA-1',
                kind: CompanyDocumentKind.purchaseAdjustmentReturn,
                tax: 20,
              ),
              document(
                id: 'PI-MAIN',
                kind: CompanyDocumentKind.purchase,
                tax: 900,
                branch: 'main',
                warehouse: 'main-floor',
              ),
            ],
          ),
        ),
      );

      final result = await service.load(
        reportKey: 'reports.purchase_tax_report',
        scope: const SyncedReportScope.location(
          branchId: 'cairo',
          warehouseId: 'floor',
        ),
        from: DateTime.utc(2026),
        toExclusive: DateTime.utc(2027),
      );

      expect(result.documentCount, 3);
      expect(result.totalsByCurrency, {'USD': 100});
      expect(result.grossTotalsByCurrency, {'USD': 150});
      expect(result.returnTotalsByCurrency, {'USD': 50});
      expect(result.netTotalsByCurrency, {'USD': 100});
      expect(result.grossDocumentCount, 1);
      expect(result.returnDocumentCount, 2);
      expect(
        result.rows.expand((row) => row.documents).map((item) => item.branchId),
        everyElement('cairo'),
      );
    },
  );

  test('sales tax analysis never includes purchase documents', () async {
    final at = DateTime.utc(2026, 10, 1, 10);
    CompanyDocumentSnapshot document(
      String id,
      CompanyDocumentKind kind,
      int tax,
    ) => CompanyDocumentSnapshot(
      documentId: id,
      sourceDatabaseId: 'remote-db',
      branchId: 'cairo',
      branchName: 'Cairo',
      warehouseId: 'floor',
      warehouseName: 'Floor',
      kind: kind,
      number: id,
      documentDate: at,
      currencyCode: 'USD',
      totalMinor: tax * 10,
      taxMinor: tax,
      itemCount: 1,
      isRemote: true,
      isVoided: false,
      occurredAt: at,
      lines: [
        CompanyDocumentLineSnapshot(
          productName: 'Taxed product',
          variantName: null,
          quantityScaled: 1,
          quantityScale: 1,
          measurementType: 'piece',
          unitMinor: tax * 9,
          subtotalMinor: tax * 9,
          discountMinor: 0,
          taxMinor: tax,
          totalMinor: tax * 10,
        ),
      ],
    );
    final service = SyncedLocationReportService(
      _Monitor(
        db,
        CompanyBranchMonitorSnapshot(
          locations: const [],
          generatedAt: at,
          documents: [
            document('SI-1', CompanyDocumentKind.sale, 100),
            document('SR-1', CompanyDocumentKind.saleReturn, 20),
            document('PI-1', CompanyDocumentKind.purchase, 700),
          ],
        ),
      ),
    );

    final result = await service.load(
      reportKey: 'reports.tax_by_product',
      branchId: 'cairo',
      warehouseId: 'floor',
      from: DateTime.utc(2026),
      toExclusive: DateTime.utc(2027),
    );

    expect(result.documentCount, 2);
    expect(result.totalsByCurrency, {'USD': 80});
    expect(result.netTotalsByCurrency, {'USD': 80});
    expect(
      result.rows.single.documents.map((item) => item.number),
      containsAll(<String>['SI-1', 'SR-1']),
    );
  });

  test(
    'sales invoice lists stay gross while summary exposes returns and net',
    () async {
      final at = DateTime.utc(2026, 10, 1, 10);
      CompanyDocumentSnapshot document(
        String id,
        CompanyDocumentKind kind,
        int total,
      ) => CompanyDocumentSnapshot(
        documentId: id,
        sourceDatabaseId: 'remote-db',
        branchId: 'cairo',
        branchName: 'Cairo',
        warehouseId: 'floor',
        warehouseName: 'Floor',
        kind: kind,
        number: id,
        documentDate: at,
        currencyCode: 'USD',
        totalMinor: total,
        itemCount: 0,
        isRemote: true,
        isVoided: false,
        occurredAt: at,
        paymentMethod: 'cash',
      );
      final service = SyncedLocationReportService(
        _Monitor(
          db,
          CompanyBranchMonitorSnapshot(
            locations: const [],
            generatedAt: at,
            documents: [
              document('SI-1', CompanyDocumentKind.sale, 1000),
              document('SR-1', CompanyDocumentKind.saleReturn, 250),
            ],
          ),
        ),
      );

      final invoices = await service.load(
        reportKey: 'reports.all_sales',
        branchId: 'cairo',
        warehouseId: 'floor',
        from: DateTime.utc(2026),
        toExclusive: DateTime.utc(2027),
      );

      expect(invoices.documentCount, 1);
      expect(invoices.rows.single.documents.single.number, 'SI-1');
      expect(invoices.grossTotalsByCurrency, {'USD': 1000});
      expect(invoices.returnTotalsByCurrency, {'USD': 250});
      expect(invoices.netTotalsByCurrency, {'USD': 750});
    },
  );

  test('ordinary purchase reports exclude purchase orders', () async {
    final at = DateTime.utc(2026, 10, 1, 10);
    CompanyDocumentSnapshot purchase(String id, String paymentMethod) =>
        CompanyDocumentSnapshot(
          documentId: id,
          sourceDatabaseId: 'remote-db',
          branchId: 'cairo',
          branchName: 'Cairo',
          warehouseId: 'floor',
          warehouseName: 'Floor',
          kind: CompanyDocumentKind.purchase,
          number: id,
          documentDate: at,
          currencyCode: 'USD',
          totalMinor: 1000,
          itemCount: 0,
          isRemote: true,
          isVoided: false,
          occurredAt: at,
          paymentMethod: paymentMethod,
          partyName: 'Supplier',
        );
    final service = SyncedLocationReportService(
      _Monitor(
        db,
        CompanyBranchMonitorSnapshot(
          locations: const [],
          generatedAt: at,
          documents: [
            purchase('PI-1', 'cash'),
            purchase('PO-1', 'purchaseOrder'),
          ],
        ),
      ),
    );

    final purchases = await service.load(
      reportKey: 'reports.purchases_by_supplier',
      branchId: 'cairo',
      warehouseId: 'floor',
      from: DateTime.utc(2026),
      toExclusive: DateTime.utc(2027),
    );
    final orders = await service.load(
      reportKey: 'reports.purchase_orders',
      branchId: 'cairo',
      warehouseId: 'floor',
      from: DateTime.utc(2026),
      toExclusive: DateTime.utc(2027),
    );

    expect(purchases.documentCount, 1);
    expect(purchases.grossTotalsByCurrency, {'USD': 1000});
    expect(purchases.rows.single.documents.single.number, 'PI-1');
    expect(orders.documentCount, 1);
    expect(orders.rows.single.documents.single.number, 'PO-1');
  });
}
