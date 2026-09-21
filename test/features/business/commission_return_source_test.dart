import 'dart:io';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late CommissionService service;
  late int currency, employee, sale, firstReturn, secondReturn;
  Future<int> addReturn(int saleId, String number) => db
      .into(db.saleReturns)
      .insert(
        SaleReturnsCompanion.insert(
          saleId: saleId,
          returnNumber: number,
          totalCents: Decimal.zero,
          currencyId: currency,
          status: const Value('posted'),
        ),
      );
  Future<void> reverse(int id) => service.reverseForReturn(
    saleId: sale,
    saleReturnId: id,
    saleSubtotalCents: 10000,
    totalSaleItemCount: 10,
    returnSubtotalCents: 2000,
    returnedItemCount: 2,
    currencyId: currency,
    returnDate: DateTime(2026, 9, 20),
  );
  Future<List<Commission>> rows() => db.select(db.commissions).get();
  setUp(() async {
    db = fixtures.memoryDb();
    currency = (await db.select(db.currencies).get()).first.id;
    employee = await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            name: 'Agent',
            currencyId: currency,
            defaultCommissionRateBps: const Value(500),
          ),
        );
    sale = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'SALE',
            subtotalCents: Decimal.fromInt(10000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(10000),
            currencyId: currency,
            paymentMethod: 'cash',
            employeeId: Value(employee),
          ),
        );
    firstReturn = await addReturn(sale, 'R1');
    secondReturn = await addReturn(sale, 'R2');
    service = CommissionService(db.employeeDao);
    await service.createForSale(
      saleId: sale,
      employeeId: employee,
      subtotalCents: 10000,
      discountCents: 0,
      itemCount: 10,
      currencyId: currency,
      saleDate: DateTime(2026, 9, 1),
    );
  });
  tearDown(() => db.close());

  test(
    'exact return source survives retries without a second deduction',
    () async {
      await reverse(firstReturn);
      await reverse(firstReturn);
      final all = await rows();
      expect(all, hasLength(2));
      final reversal = all.singleWhere((c) => c.saleReturnId != null);
      expect(reversal.saleReturnId, firstReturn);
      expect(reversal.saleId, sale);
      expect(reversal.commissionAmountCents, Decimal.fromInt(-100));
    },
  );

  test(
    'void removes only its deduction while preserving another return',
    () async {
      await reverse(firstReturn);
      await reverse(secondReturn);
      await db.saleDao.voidSaleReturn(firstReturn);
      final all = await rows();
      expect(all, hasLength(2));
      expect(all.any((c) => c.saleReturnId == firstReturn), isFalse);
      expect(
        all
            .singleWhere((c) => c.saleReturnId == secondReturn)
            .commissionAmountCents,
        Decimal.fromInt(-100),
      );
      expect(
        all.fold<int>(
          0,
          (n, c) => n + c.commissionAmountCents.toBigInt().toInt(),
        ),
        400,
      );
    },
  );

  test('failure after commission removal rolls back the whole void', () async {
    await reverse(firstReturn);
    final before = await rows();
    await db.customStatement(
      "CREATE TRIGGER fail_return_void BEFORE UPDATE ON sale_returns WHEN NEW.status = 'voided' BEGIN SELECT RAISE(ABORT,'test failure'); END",
    );
    await expectLater(
      db.saleDao.voidSaleReturn(firstReturn),
      throwsA(isA<Exception>()),
    );
    expect(await rows(), before);
    expect((await db.saleDao.getSaleReturnById(firstReturn))!.status, 'posted');
  });

  test(
    'wrong invoice source is rejected without partial commissions',
    () async {
      final otherSale = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'OTHER',
              subtotalCents: Decimal.zero,
              taxCents: Decimal.zero,
              totalCents: Decimal.zero,
              currencyId: currency,
              paymentMethod: 'cash',
            ),
          );
      final foreignReturn = await addReturn(otherSale, 'WRONG');
      await expectLater(reverse(foreignReturn), throwsA(isA<Exception>()));
      expect(await rows(), hasLength(1));
    },
  );

  test('recorded return identity cannot be removed or reassigned', () async {
    await reverse(firstReturn);
    for (final expression in [
      'sale_return_id = NULL',
      'sale_return_id = $secondReturn',
      'employee_id = employee_id + 1',
    ]) {
      await expectLater(
        db.customStatement(
          'UPDATE commissions SET $expression WHERE sale_return_id = ?',
          [firstReturn],
        ),
        throwsA(isA<Exception>()),
      );
    }
    expect(
      (await rows()).singleWhere((c) => c.saleReturnId != null).saleReturnId,
      firstReturn,
    );
  });

  test('positive or mixed-source reversal is rejected', () async {
    await reverse(firstReturn);
    for (final expression in [
      'commission_amount_cents = 100',
      'sale_return_adjustment_id = 1',
    ]) {
      await expectLater(
        db.customStatement(
          'UPDATE commissions SET $expression WHERE sale_return_id = ?',
          [firstReturn],
        ),
        throwsA(isA<Exception>()),
      );
    }
  });

  test(
    'unresolved legacy reversal blocks void before any financial changes',
    () async {
      await service.reverseForReturn(
        saleId: sale,
        saleSubtotalCents: 10000,
        totalSaleItemCount: 10,
        returnSubtotalCents: 2000,
        returnedItemCount: 2,
        currencyId: currency,
        returnDate: DateTime(2026, 9, 20),
      );
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        db.saleDao.voidSaleReturn(firstReturn),
        throwsStateError,
      );
      expect(await fixtures.legacySnapshot(db), before);
    },
  );

  test(
    '10086 migration preserves amounts and leaves old source unresolved',
    () async {
      await service.reverseForReturn(
        saleId: sale,
        saleSubtotalCents: 10000,
        totalSaleItemCount: 10,
        returnSubtotalCents: 2000,
        returnedItemCount: 2,
        currencyId: currency,
        returnDate: DateTime(2026, 9, 20),
      );
      final before = await rows();
      final temp = await Directory.systemTemp.createTemp(
        'tapix-commission-upgrade-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/legacy.sqlite');
      await db.customStatement('VACUUM INTO ?', [file.path]);
      final legacy = sqlite.sqlite3.open(file.path);
      try {
        for (final name in ['insert', 'update', 'immutable']) {
          legacy.execute('DROP TRIGGER commission_return_source_$name');
        }
        // This fixture emulates the old schema, before dependent journal routes.
        for (final trigger in legacy.select(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name GLOB 'business_location_*'",
        )) {
          legacy.execute('DROP TRIGGER "${trigger['name']}"');
        }
        legacy.execute('DROP INDEX commissions_by_sale_return');
        legacy.execute('ALTER TABLE commissions DROP COLUMN sale_return_id');
        legacy.execute('PRAGMA user_version = 10086');
        legacy.execute(
          'CREATE VIEW commissions_by_sale_return AS SELECT id FROM commissions',
        );
      } finally {
        legacy.close();
      }
      // Force installation to fail after ADD COLUMN: both schema and version
      // must roll back so a subsequent retry upgrades the same file safely.
      final failing = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      try {
        await expectLater(
          failing.customSelect('SELECT 1').get(),
          throwsA(isA<Exception>()),
        );
      } finally {
        await failing.close();
      }
      final verify = sqlite.sqlite3.open(file.path);
      try {
        expect(
          verify.select('PRAGMA user_version').single['user_version'],
          10086,
        );
        expect(
          verify
              .select('PRAGMA table_info(commissions)')
              .any((r) => r['name'] == 'sale_return_id'),
          isFalse,
        );
        verify.execute('DROP VIEW commissions_by_sale_return');
      } finally {
        verify.close();
      }
      final upgraded = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      try {
        expect(await upgraded.select(upgraded.commissions).get(), before);
        expect(upgraded.schemaVersion, 10091);
        expect(
          await upgraded.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        final oldNegative = (await upgraded.select(upgraded.commissions).get())
            .singleWhere((c) => c.commissionAmountCents < Decimal.zero);
        expect(oldNegative.saleReturnId, isNull);
        await expectLater(
          upgraded.saleDao.voidSaleReturn(firstReturn),
          throwsStateError,
        );
      } finally {
        await upgraded.close();
      }
    },
  );
}
