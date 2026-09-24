import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/inventory/supplier_identity_rules.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int supplierId;

  Matcher failure(String key) => isA<SupplierIdentityException>().having(
    (e) => e.messageKey,
    'messageKey',
    'supplier_identity.$key',
  );

  Future<int> saveInvoice({String number = 'INV1', String status = 'posted'}) =>
      db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: number,
              supplierId: supplierId,
              currencyId: currencyId,
              subtotalCents: Decimal.fromInt(2500),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(2500),
              status: Value(status),
            ),
          );

  Future<void> changeCode(String? value) async {
    final current = (await db.supplierDao.getSupplier(supplierId))!;
    await db.supplierDao.updateSupplier(
      current.copyWith(productCode: Value(value)),
    );
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    supplierId = await db.supplierDao.createSupplier(
      SuppliersCompanion.insert(
        name: 'Noor',
        currencyId: currencyId,
        productCode: const Value('N1'),
      ),
    );
  });
  tearDown(() => db.close());

  test('unused code can change before any saved history', () async {
    expect(await db.supplierDao.isProductCodeLocked(supplierId), isFalse);
    await changeCode('N2');
    expect((await db.supplierDao.getSupplier(supplierId))!.productCode, 'N2');
  });

  test('invoice without source identity locks the code in the DAO', () async {
    await saveInvoice();
    expect(await db.select(db.supplierProductIdentities).get(), isEmpty);
    expect(await db.supplierDao.isProductCodeLocked(supplierId), isTrue);
    await expectLater(changeCode('N2'), throwsA(failure('code_locked')));
    await expectLater(changeCode(null), throwsA(failure('code_locked')));
    expect((await db.supplierDao.getSupplier(supplierId))!.productCode, 'N1');
  });

  test('saved draft also reserves the code permanently', () async {
    final id = await saveInvoice(status: 'draft');
    await (db.delete(db.purchases)..where((p) => p.id.equals(id))).go();
    expect(await db.supplierDao.isProductCodeLocked(supplierId), isTrue);
    await expectLater(changeCode('N2'), throwsA(failure('code_locked')));
  });

  test('cancelled invoice does not release prefix', () async {
    final id = await saveInvoice();
    await (db.update(db.purchases)..where((p) => p.id.equals(id))).write(
      const PurchasesCompanion(status: Value('cancelled')),
    );
    await expectLater(changeCode('N2'), throwsA(failure('code_locked')));
  });

  test('repeated invoices reuse one lock row', () async {
    await saveInvoice(number: 'P1');
    await saveInvoice(number: 'P2');
    expect(await db.select(db.supplierProductCodeLocks).get(), hasLength(1));
  });

  test(
    'old supplier with no prefix may be assigned one even with history',
    () async {
      await changeCode(null);
      await saveInvoice();
      expect(await db.supplierDao.isProductCodeLocked(supplierId), isFalse);
      await changeCode('007');
      expect(
        (await db.supplierDao.getSupplier(supplierId))!.productCode,
        '007',
      );
      expect(await db.supplierDao.isProductCodeLocked(supplierId), isTrue);
      await expectLater(changeCode('008'), throwsA(failure('code_locked')));
    },
  );

  test('same code and other supplier details remain editable', () async {
    await saveInvoice();
    final supplier = (await db.supplierDao.getSupplier(supplierId))!;
    await db.supplierDao.updateSupplier(
      supplier.copyWith(name: 'Noor renamed', productCode: const Value(' n1 ')),
    );
    expect(
      (await db.supplierDao.getSupplier(supplierId))!.name,
      'Noor renamed',
    );
  });

  test('status-only update retains balance and immutable prefix', () async {
    await saveInvoice();
    final before = (await db.supplierDao.getSupplier(supplierId))!;
    await (db.update(db.suppliers)..where((s) => s.id.equals(supplierId)))
        .write(SuppliersCompanion(balanceCents: Value(Decimal.fromInt(555))));
    await db.supplierDao.setSupplierActive(before.id, false);
    final inactive = (await db.supplierDao.getSupplier(supplierId))!;
    expect(inactive.isActive, isFalse);
    expect(inactive.balanceCents, Decimal.fromInt(555));
    expect(inactive.productCode, 'N1');
    expect(
      await db.supplierDao.watchAllSuppliers(isActive: false).first,
      contains(inactive),
    );
    await db.supplierDao.setSupplierActive(supplierId, true);
    final active = (await db.supplierDao.getSupplier(supplierId))!;
    expect(active.isActive, isTrue);
    expect(active.balanceCents, Decimal.fromInt(555));
  });

  test('inactive supplier still owns the unique code', () async {
    await db.supplierDao.setSupplierActive(supplierId, false);
    await expectLater(
      db.supplierDao.createSupplier(
        SuppliersCompanion.insert(
          name: 'Other',
          currencyId: currencyId,
          productCode: const Value('n1'),
        ),
      ),
      throwsA(failure('code_in_use')),
    );
  });

  test('direct writes cannot bypass invoice lock', () async {
    await saveInvoice();
    await expectLater(
      db.customStatement('UPDATE suppliers SET product_code=? WHERE id=?', [
        'N2',
        supplierId,
      ]),
      throwsA(anything),
    );
    expect((await db.supplierDao.getSupplier(supplierId))!.productCode, 'N1');
  });

  test('failed invoice transaction rolls back its new lock too', () async {
    await expectLater(
      db.transaction(() async {
        await saveInvoice();
        throw StateError('Injected posting failure');
      }),
      throwsStateError,
    );
    expect(await db.supplierDao.isProductCodeLocked(supplierId), isFalse);
    await changeCode('N2');
  });

  test(
    'used code survives removed document and blocks supplier deletion',
    () async {
      final id = await saveInvoice(status: 'draft');
      await (db.delete(db.purchases)..where((p) => p.id.equals(id))).go();
      await expectLater(
        db.supplierDao.deleteSupplier(supplierId),
        throwsA(failure('delete_blocked')),
      );
    },
  );

  test('foreign key and integrity checks after reactivation', () async {
    await saveInvoice();
    await db.supplierDao.setSupplierActive(supplierId, false);
    await db.supplierDao.setSupplierActive(supplierId, true);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect(
      (await db.customSelect('PRAGMA integrity_check').getSingle())
          .data
          .values
          .single,
      'ok',
    );
  });
}
