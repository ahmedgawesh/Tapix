import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/inventory/supplier_product_identity_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/products/data/datasources/product_local_datasource.dart';
import 'package:tapix/features/products/data/datasources/variant_local_datasource.dart';
import 'package:tapix/features/products/data/repositories/category_repository_impl.dart';
import 'package:tapix/features/products/data/repositories/product_repository_impl.dart';
import 'package:tapix/features/products/data/repositories/product_variant_repository_impl.dart';
import 'package:tapix/features/products/domain/entities/import_file_data.dart';
import 'package:tapix/features/products/services/export_service.dart';
import 'package:tapix/features/products/services/export_stock_reader.dart';
import 'package:tapix/features/products/services/file_import_service.dart';
import 'package:tapix/features/products/services/import_validation_service.dart';
import 'package:tapix/features/products/services/product_file_metadata.dart';
import 'package:tapix/features/products/services/product_import_service.dart';
import '../../business/business_foundation_test.dart' as fixtures;

class _Session extends Mock implements SessionService {}

class _Harness {
  final AppDatabase db = fixtures.memoryDb();
  late ProductRepositoryImpl products;
  late ProductVariantRepositoryImpl variants;
  late ProductImportService importer;
  late ExportServiceImpl exporter;
  late int supplierId;
  Future<void> init({bool shiftSupplierId = false}) async {
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      "INSERT INTO users (id, username, password_hash, role, is_active, created_at, updated_at) VALUES (0, 'system', 'no-pin', 'owner', 1, 0, 0)",
    );
    final currency = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    if (shiftSupplierId) {
      await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Unrelated',
              currencyId: currency.id,
            ),
          );
    }
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'شركة الأمل',
            productCode: const Value('AM'),
            currencyId: currency.id,
          ),
        );
    final session = _Session();
    when(() => session.getCurrentUserId()).thenAnswer((_) async => 0);
    products = ProductRepositoryImpl(
      ProductLocalDatasourceImpl(db.productDao),
      AuditLogService(db),
      session,
    );
    variants = ProductVariantRepositoryImpl(
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
    final metadata = ProductFileMetadata(db);
    importer = ProductImportService(
      products,
      variants,
      CategoryRepositoryImpl(db),
      metadata: metadata,
    );
    exporter = ExportServiceImpl(
      products,
      variants,
      CategoryRepositoryImpl(db),
      WarehouseExportStockReader(db),
      metadata: metadata,
    );
  }

  Future<void> import(ImportFileData file) async {
    final mapping = ColumnMapping.fromHeaders(file.headers);
    final errors = await ImportValidationService(products, variants: variants)(
      fileData: file,
      columnMapping: mapping,
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.message).join('\n'));
    final result = await importer(fileData: file, columnMapping: mapping);
    expect(
      result.successfulRows,
      file.rows.length,
      reason: result.errors.map((e) => e.message).join('\n'),
    );
  }
}

ImportFileData _file(List<String> headers, List<List<String>> rows) =>
    ImportFileData(
      fileName: 'products.csv',
      fileType: ImportFileType.csv,
      headers: headers,
      rows: rows,
      totalRows: rows.length,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final excel in [false, true]) {
    test(
      '${excel ? 'XLSX' : 'CSV'} round trip preserves catalog identities, policies and opening ledger',
      () async {
        final source = _Harness();
        final target = _Harness();
        addTearDown(source.db.close);
        addTearDown(target.db.close);
        await source.init();
        await target.init(shiftSupplierId: true);
        await source.import(
          _file(
            [
              'product_id',
              'name',
              'sku',
              'barcode',
              'price_cents',
              'cost_cents',
              'stock_quantity',
              'has_variants',
              'color',
              'size',
              'measurement_type',
              'track_inventory',
              'purchase_tax_rate_bps',
              'sales_tax_rate_bps',
              'supplier_code',
              'is_taxable',
              'wholesale_price_cents',
            ],
            [
              [
                'a',
                'نفس الاسم',
                '00150',
                '0000123456789',
                '15000',
                '10000',
                '2',
                'false',
                '',
                '',
                'piece',
                'true',
                '1400',
                '100',
                'AM',
                'true',
                '12000',
              ],
              [
                'b',
                'نفس الاسم',
                '00151',
                '0000123456790',
                '12000',
                '5000',
                '1',
                'false',
                'أزرق',
                'M',
                'piece',
                'true',
                '1400',
                '100',
                'AM',
                'true',
                '9000',
              ],
              [
                'c',
                'قماش',
                'ROLL-01',
                '0000123456791',
                '1000',
                '500',
                '1500',
                'false',
                '',
                '',
                'length',
                'true',
                '0',
                '0',
                'AM',
                'false',
                '800',
              ],
              [
                'd',
                'قميص',
                'SHIRT-S',
                '0000123456792',
                '2000',
                '700',
                '3',
                'true',
                'أحمر',
                'S',
                'piece',
                'true',
                '500',
                '1000',
                'AM',
                'true',
                '1800',
              ],
              [
                'd',
                'قميص',
                'SHIRT-L',
                '0000123456793',
                '2500',
                '900',
                '4',
                'true',
                'أحمر',
                'L',
                'piece',
                'true',
                '500',
                '1000',
                'AM',
                'true',
                '2200',
              ],
              [
                'e',
                'خدمة',
                'SERVICE',
                '0000123456794',
                '9000',
                '0',
                '0',
                'false',
                '',
                '',
                'piece',
                'false',
                '0',
                '0',
                '',
                'false',
                '',
              ],
            ],
          ),
        );
        for (final product
            in await source.db.select(source.db.products).get()) {
          if (product.supplierId == null) continue;
          for (final v in await source.variants.getVariantsByProduct(
            product.id,
          )) {
            await SupplierProductIdentityService(source.db).ensureIssued(
              supplierId: source.supplierId,
              productId: product.id,
              variantId: v.id,
            );
          }
        }
        final bytes = excel
            ? await source.exporter.exportToExcel()
            : utf8.encode(await source.exporter.exportToCSV());
        final parsed = await FileImportService()(
          bytes: bytes,
          fileName: excel ? 'catalog.xlsx' : 'catalog.csv',
        );
        expect(parsed.rows.length, 6);
        await target.import(parsed);
        final products = await target.db.select(target.db.products).get();
        expect(products.length, 5);
        expect(products.where((p) => p.name == 'نفس الاسم').length, 2);
        expect(
          products.singleWhere((p) => p.sku == '00151').hasVariants,
          false,
        );
        expect(
          products.singleWhere((p) => p.sku == '00150').barcode,
          '0000123456789',
        );
        expect(
          products.singleWhere((p) => p.sku == '00150').purchaseTaxRateBps,
          1400,
        );
        expect(
          products.singleWhere((p) => p.sku == '00150').salesTaxRateBps,
          100,
        );
        expect(
          products.singleWhere((p) => p.sku == '00150').supplierId,
          target.supplierId,
        );
        expect(
          products.singleWhere((p) => p.sku == 'ROLL-01').measurementType,
          'length',
        );
        expect(
          products.singleWhere((p) => p.sku == 'SERVICE').trackInventory,
          false,
        );
        final identities = await target.db
            .select(target.db.supplierProductIdentities)
            .get();
        expect(identities.length, 5);
        expect(
          identities.map((i) => i.baseSkuSnapshot),
          containsAll(['00150', '00151', 'ROLL-01', 'SHIRT-S', 'SHIRT-L']),
        );
        final stock = await target.db
            .select(target.db.businessWarehouseStocks)
            .get();
        expect(
          stock.map((s) => s.quantity),
          unorderedEquals([2, 1, 1500, 3, 4, 0]),
        );
        expect(
          (await target.db.select(target.db.inventoryAdjustments).get()).length,
          5,
        );
        final journal = await target.db
            .customSelect(
              'SELECT SUM(debit_cents) AS dr, SUM(credit_cents) AS cr FROM journal_entry_lines',
            )
            .getSingle();
        expect(
          journal.read<int>('dr'),
          31450,
        ); // 20000 + 5000 + 750 + 2100 + 3600
        expect(journal.read<int>('cr'), 31450);
        // Re-import into the same company refuses duplicates, without stock/journal changes.
        final retry = await target.importer(
          fileData: parsed,
          columnMapping: ColumnMapping.fromHeaders(parsed.headers),
        );
        expect(retry.successfulRows, 0);
        expect(await target.db.select(target.db.products).get(), hasLength(5));
        expect(
          await target.db.select(target.db.inventoryAdjustments).get(),
          hasLength(5),
        );
        expect(
          await target.db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  }

  test(
    'exported consignment is explicit and cannot become owned opening stock',
    () async {
      final source = _Harness();
      final target = _Harness();
      addTearDown(source.db.close);
      addTearDown(target.db.close);
      await source.init();
      await target.init();
      await source.import(
        _file(
          ['name', 'sku', 'price', 'cost', 'stock_quantity'],
          [
            ['Owned and consigned', 'MIX', '10', '5', '2'],
          ],
        ),
      );
      await source.db.customStatement(
        'UPDATE business_warehouse_stocks SET supplier_owned_quantity=1',
      );
      final file = await FileImportService()(
        bytes: utf8.encode(await source.exporter.exportToCSV()),
        fileName: 'mixed.csv',
      );
      expect(file.rows.single[file.headers.indexOf('stock_quantity')], '2');
      expect(
        file.rows.single[file.headers.indexOf('supplier_owned_quantity')],
        '1',
      );
      final result = await target.importer(
        fileData: file,
        columnMapping: ColumnMapping.fromHeaders(file.headers),
      );
      expect(result.successfulRows, 0);
      expect(await target.db.select(target.db.products).get(), isEmpty);
      expect(await target.db.select(target.db.journalEntries).get(), isEmpty);
    },
  );

  test(
    'cannot skip a stock policy column to reinterpret measured or consigned stock',
    () {
      final file = _file(
        [
          'name',
          'price',
          'stock_quantity',
          'measurement_type',
          'supplier_owned_quantity',
        ],
        [
          ['Product', '1', '1500', 'weight', '100'],
        ],
      );
      expect(
        () => ProductImportService.parseRow(
          file.rows.single,
          0,
          const ColumnMapping({'name': 0, 'price': 1, 'stock_quantity': 2}),
          file.headers,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'missing supplier rolls back a valid preceding product and its opening journal',
    () async {
      final h = _Harness();
      addTearDown(h.db.close);
      await h.init();
      final file = _file(
        ['name', 'sku', 'price', 'cost', 'stock_quantity', 'supplier_code'],
        [
          ['Valid', 'GOOD', '10', '5', '2', 'AM'],
          ['Missing', 'BAD', '10', '5', '2', 'UNKNOWN'],
        ],
      );
      final result = await h.importer(
        fileData: file,
        columnMapping: ColumnMapping.fromHeaders(file.headers),
      );
      expect(result.successfulRows, 0);
      expect(await h.db.select(h.db.products).get(), isEmpty);
      expect(await h.db.select(h.db.journalEntries).get(), isEmpty);
      expect(await h.db.select(h.db.inventoryAdjustments).get(), isEmpty);
    },
  );

  test(
    'inactive variant, batch policy and simple descriptive dimensions survive zero-stock round trip',
    () async {
      final source = _Harness();
      final target = _Harness();
      addTearDown(source.db.close);
      addTearDown(target.db.close);
      await source.init();
      await target.init();
      await source.import(
        _file(
          [
            'name',
            'sku',
            'price',
            'has_variants',
            'color',
            'is_active',
            'variant_is_active',
            'inventory_tracking_type',
          ],
          [
            [
              'Archived',
              'ARCH',
              '10',
              'false',
              'Blue',
              'false',
              'false',
              'batch_expiry',
            ],
          ],
        ),
      );
      expect(
        (await FileImportService()(
          bytes: utf8.encode(await source.exporter.exportToCSV()),
          fileName: 'active.csv',
        )).rows,
        isEmpty,
      );
      final file = await FileImportService()(
        bytes: utf8.encode(
          await source.exporter.exportToCSV(activeOnly: false),
        ),
        fileName: 'all.csv',
      );
      await target.import(file);
      final p = await target.db.select(target.db.products).getSingle();
      final v = await target.db.select(target.db.productVariants).getSingle();
      expect(p.isActive, false);
      expect(p.hasVariants, false);
      expect(v.isActive, false);
      expect(v.colorId, isNotNull);
      expect(p.inventoryTrackingType, 'batch_expiry');
      expect(p.costingMethod, 'fifo');
      expect(await target.db.select(target.db.journalEntries).get(), isEmpty);
    },
  );

  test('export refuses a LAN client local cache', () async {
    final h = _Harness();
    addTearDown(h.db.close);
    await h.init();
    await h.db.settingsDao.saveSetting('lan.mode', 'client');
    await expectLater(h.exporter.exportToCSV(), throwsStateError);
    await expectLater(h.exporter.exportToExcel(), throwsStateError);
  });

  test(
    'mapping never substitutes wholesale price or supplier name for required fields',
    () {
      final map = ColumnMapping.fromHeaders(const [
        'Supplier Name',
        'Wholesale Price (Cents)',
        'Cost (Cents)',
      ]);
      expect(map.getColumnIndex('name'), isNull);
      expect(map.getColumnIndex('price'), isNull);
      expect(map.getColumnIndex('wholesale_price'), 1);
      expect(map.getColumnIndex('cost'), 2);
    },
  );

  for (final invalid in [
    {'supplier_owned_quantity': '1'},
    {'inventory_tracking_type': 'batch_expiry'},
    {'track_inventory': 'false'},
    {'sales_tax_rate_bps': '10001'},
    {'is_active': 'maybe'},
    {'price_cents': '10.5'},
    {'stock_quantity': '-1'},
  ]) {
    test(
      'rejects unsafe row $invalid atomically including valid preceding row',
      () async {
        final h = _Harness();
        addTearDown(h.db.close);
        await h.init();
        final values = {
          'name': 'Invalid',
          'sku': 'BAD',
          'price_cents': '100',
          'stock_quantity': '1',
          ...invalid,
        };
        final valid = {
          ...values,
          'name': 'Valid',
          'sku': 'GOOD',
          'supplier_owned_quantity': '0',
          'inventory_tracking_type': 'standard',
          'track_inventory': 'true',
          'sales_tax_rate_bps': '0',
          'is_active': 'true',
          'price_cents': '100',
          'stock_quantity': '1',
        };
        final file = _file(values.keys.toList(), [
          values.keys.map((k) => valid[k]!).toList(),
          values.values.toList(),
        ]);
        final result = await h.importer(
          fileData: file,
          columnMapping: ColumnMapping.fromHeaders(file.headers),
        );
        expect(result.successfulRows, 0);
        expect(await h.db.select(h.db.products).get(), isEmpty);
        expect(await h.db.select(h.db.journalEntries).get(), isEmpty);
      },
    );
  }
}
