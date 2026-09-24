import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/inventory/supplier_identity_rules.dart';
import 'package:tapix/core/services/inventory/supplier_product_identity_service.dart';

void main() {
  late AppDatabase db;
  late SupplierProductIdentityService identities;
  late int currencyId;
  late int noor;
  late int amal;
  late int productId;
  late int variantId;

  Matcher failure(String key) => isA<SupplierIdentityException>().having(
    (e) => e.messageKey,
    'messageKey',
    'supplier_identity.$key',
  );

  Future<int> addSupplier(String name, String? code) =>
      db.supplierDao.createSupplier(
        SuppliersCompanion.insert(
          name: name,
          currencyId: currencyId,
          productCode: Value(code),
        ),
      );

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    identities = SupplierProductIdentityService(db);
    noor = await addSupplier('Noor', ' n1 ');
    amal = await addSupplier('Amal', 'A2');
    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Base product',
            sku: const Value('015'),
            currencyId: Value(currencyId),
            costCents: Decimal.fromInt(2500),
            priceCents: Decimal.fromInt(3500),
            stockQuantity: const Value(80),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(2500),
            priceCents: Decimal.fromInt(3500),
            stockQuantity: const Value(80),
          ),
        );
  });
  tearDown(() => db.close());

  test('DAO normalizes letters and digits, checks all suppliers', () async {
    expect((await db.supplierDao.getSupplier(noor))!.productCode, 'N1');
    expect(await db.supplierDao.isProductCodeAvailable(' n1 '), isFalse);
    expect(
      await db.supplierDao.isProductCodeAvailable(
        'n1',
        excludingSupplierId: noor,
      ),
      isTrue,
    );
    await expectLater(
      addSupplier('Other', 'N1'),
      throwsA(failure('code_in_use')),
    );
  });

  test('two optional codes are stored as NULL', () async {
    final a = await addSupplier('Blank 1', '');
    final b = await addSupplier('Blank 2', null);
    expect((await db.supplierDao.getSupplier(a))!.productCode, isNull);
    expect((await db.supplierDao.getSupplier(b))!.productCode, isNull);
  });

  test('invalid code never creates a supplier', () async {
    final count = (await db.select(db.suppliers).get()).length;
    await expectLater(
      addSupplier('Invalid', 'N-1'),
      throwsA(failure('invalid_code')),
    );
    expect((await db.select(db.suppliers).get()).length, count);
  });

  test('inactive supplier retains the prefix', () async {
    final s = (await db.supplierDao.getSupplier(noor))!;
    await db.supplierDao.updateSupplier(s.copyWith(isActive: false));
    await expectLater(
      addSupplier('Replacement', 'n1'),
      throwsA(failure('code_in_use')),
    );
  });

  test('unused code can change, and safe deletion releases it', () async {
    final id = await addSupplier('Unused', 'FREE7');
    final s = (await db.supplierDao.getSupplier(id))!;
    await db.supplierDao.updateSupplier(
      s.copyWith(productCode: const Value('FREE8')),
    );
    await addSupplier('New FREE7', 'FREE7');
    expect(await db.supplierDao.deleteSupplier(id), 1);
    await addSupplier('New FREE8', 'FREE8');
  });

  test('preview has no writes and N -> A -> N never stacks prefixes', () async {
    for (final id in [noor, amal, noor]) {
      final p = await identities.preview(supplierId: id, productId: productId);
      expect(p.sourceSku, id == noor ? 'N1-015' : 'A2-015');
      expect(p.alreadyIssued, isFalse);
    }
    expect(await db.select(db.supplierProductIdentities).get(), isEmpty);
    expect(
      (await (db.select(
        db.products,
      )..where((p) => p.id.equals(productId))).getSingle()).sku,
      '015',
    );
  });

  test(
    'simple product uses the same canonical variant with null or explicit ID',
    () async {
      final first = await identities.ensureIssued(
        supplierId: noor,
        productId: productId,
      );
      final second = await identities.ensureIssued(
        supplierId: noor,
        productId: productId,
        variantId: variantId,
      );
      expect(first.id, second.id);
      expect(first.canonicalVariantId, variantId);
      expect(first.sourceSku, 'N1-015');
    },
  );

  test(
    'one product, two suppliers, repeated issuance stays two identities',
    () async {
      for (final s in [noor, noor, amal, noor, amal]) {
        await identities.ensureIssued(supplierId: s, productId: productId);
      }
      final rows = await identities.getProductIdentities(productId);
      expect(rows.map((r) => r.sourceSku).toList(), ['A2-015', 'N1-015']);
      expect(
        (await db.select(db.products).get())
            .where((p) => p.id == productId)
            .length,
        1,
      );
    },
  );

  test(
    'a later base-SKU edit cannot mutate previously issued source codes',
    () async {
      final original = await identities.ensureIssued(
        supplierId: noor,
        productId: productId,
      );
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(sku: Value('016')));
      final again = await identities.ensureIssued(
        supplierId: noor,
        productId: productId,
      );
      expect(again.id, original.id);
      expect(again.sourceSku, 'N1-015');
      expect(again.baseSkuSnapshot, '015');
    },
  );

  test(
    'issued prefix is locked, but rename and deactivate remain allowed',
    () async {
      await identities.ensureIssued(supplierId: noor, productId: productId);
      expect(await db.supplierDao.isProductCodeLocked(noor), isTrue);
      final s = (await db.supplierDao.getSupplier(noor))!;
      await expectLater(
        db.supplierDao.updateSupplier(
          s.copyWith(productCode: const Value('N2')),
        ),
        throwsA(failure('code_locked')),
      );
      await expectLater(
        db.supplierDao.deleteSupplier(noor),
        throwsA(failure('delete_blocked')),
      );
      await db.supplierDao.updateSupplier(
        s.copyWith(name: 'Noor renamed', isActive: false),
      );
      expect((await identities.resolveSourceSku(' n1-015 '))!.supplierId, noor);
    },
  );

  test('identity operation does not change quantity or cost', () async {
    final before = (await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingle());
    final balances = await db
        .customSelect(
          'SELECT * FROM business_warehouse_stocks ORDER BY warehouse_id,variant_id',
        )
        .get();
    await identities.ensureIssued(supplierId: noor, productId: productId);
    final after = (await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingle());
    expect(after.stockQuantity, before.stockQuantity);
    expect(after.costCents, before.costCents);
    expect(after.costingMethod, before.costingMethod);
    expect(
      (await db
              .customSelect(
                'SELECT * FROM business_warehouse_stocks ORDER BY warehouse_id,variant_id',
              )
              .get())
          .map((r) => r.data)
          .toList(),
      balances.map((r) => r.data).toList(),
    );
  });

  test('outer operation rollback removes its newly issued identity', () async {
    await expectLater(
      db.transaction(() async {
        await identities.ensureIssued(supplierId: noor, productId: productId);
        throw StateError('failure after identity creation');
      }),
      throwsStateError,
    );
    expect(await db.select(db.supplierProductIdentities).get(), isEmpty);
    expect(await db.supplierDao.isProductCodeLocked(noor), isFalse);
  });

  test(
    'a shared manufacturer barcode cannot be used as a supplier source code',
    () async {
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(barcode: Value('N1-015')));
      await expectLater(
        identities.ensureIssued(supplierId: noor, productId: productId),
        throwsA(failure('source_code_collision')),
      );
    },
  );

  test('local client cannot reserve on behalf of its master', () async {
    await db.settingsDao.saveSetting('lan.mode', 'client');
    await expectLater(
      addSupplier('Client local code', 'CL1'),
      throwsA(failure('master_required')),
    );
    await expectLater(
      identities.ensureIssued(supplierId: noor, productId: productId),
      throwsA(failure('master_required')),
    );
    expect(await db.select(db.supplierProductIdentities).get(), isEmpty);
  });

  test('foreign key and database integrity checks', () async {
    await identities.ensureIssued(supplierId: noor, productId: productId);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    final check = await db.customSelect('PRAGMA integrity_check').getSingle();
    expect(check.data.values.single, 'ok');
  });
}
