import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'business_foundation_test.dart' as fixtures;
import 'package:tapix/core/services/commissions/commission_source_reconciliation_service.dart';

void main() {
  late AppDatabase db;
  late CommissionService service;
  late int currency, employee, sale, firstReturn;
  Future<int> addReturn(int saleId, String number) => db
      .into(db.saleReturns)
      .insert(
        SaleReturnsCompanion.insert(
          saleId: saleId,
          returnNumber: number,
          totalCents: Decimal.zero,
          subtotalCents: Value(Decimal.fromInt(2000)),
          returnDate: Value(DateTime(2026, 9, 20)),
          currencyId: currency,
          status: const Value('posted'),
        ),
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

  Future<ReviewedCommissionReturnLink> legacyLink() async {
    await service.reverseForReturn(
      saleId: sale,
      saleSubtotalCents: 10000,
      totalSaleItemCount: 10,
      returnSubtotalCents: 2000,
      returnedItemCount: 2,
      currencyId: currency,
      returnDate: DateTime(2026, 9, 20),
    );
    final c = (await rows()).singleWhere(
      (c) => c.commissionAmountCents < Decimal.zero,
    );
    return ReviewedCommissionReturnLink(
      commissionId: c.id,
      returnId: firstReturn,
      expectedAmountCents: -100,
    );
  }

  Future<int> apply(List<ReviewedCommissionReturnLink> links) =>
      CommissionSourceReconciliationService(
        db,
      ).applyReviewedLinks(links, reason: 'Reviewed fixture evidence');
  test(
    'link preserves money, audits once, retries and enables precise void',
    () async {
      final link = await legacyLink();
      final before = await rows();
      expect(await apply([link]), 1);
      expect(await apply([link]), 0);
      final after = await rows();
      expect(
        after.map((c) => c.commissionAmountCents).toList(),
        before.map((c) => c.commissionAmountCents).toList(),
      );
      expect(
        after.map((c) => c.status).toList(),
        before.map((c) => c.status).toList(),
      );
      expect(after.last.saleReturnId, firstReturn);
      expect(await db.select(db.auditLogs).get(), hasLength(1));
      await db.saleDao.voidSaleReturn(firstReturn);
      expect(await rows(), hasLength(1));
    },
  );
  test('ambiguous returns are rejected', () async {
    final link = await legacyLink();
    await addReturn(sale, 'R2');
    await expectLater(apply([link]), throwsStateError);
    expect((await rows()).last.saleReturnId, isNull);
  });
  test('changed amount invalidates plan', () async {
    final link = await legacyLink();
    await db.customStatement(
      'UPDATE commissions SET commission_amount_cents=-99 WHERE id=?',
      [link.commissionId],
    );
    await expectLater(apply([link]), throwsStateError);
    expect(await db.select(db.auditLogs).get(), isEmpty);
  });
  test(
    'incorrect allocation is rejected even if supplied amount matches',
    () async {
      final link = await legacyLink();
      await db.customStatement(
        'UPDATE commissions SET commission_amount_cents=-99 WHERE id=?',
        [link.commissionId],
      );
      await expectLater(
        apply([
          ReviewedCommissionReturnLink(
            commissionId: link.commissionId,
            returnId: firstReturn,
            expectedAmountCents: -99,
          ),
        ]),
        throwsStateError,
      );
    },
  );
  test('audit failure rolls back link', () async {
    final link = await legacyLink();
    await db.customStatement(
      "CREATE TRIGGER fail_link_audit BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT,'test'); END",
    );
    await expectLater(apply([link]), throwsA(isA<Exception>()));
    expect((await rows()).last.saleReturnId, isNull);
  });
  test('invalid later link rolls back entire batch', () async {
    final link = await legacyLink();
    await expectLater(
      apply([
        link,
        const ReviewedCommissionReturnLink(
          commissionId: 99999,
          returnId: 99999,
          expectedAmountCents: -100,
        ),
      ]),
      throwsA(anything),
    );
    expect((await rows()).last.saleReturnId, isNull);
    expect(await db.select(db.auditLogs).get(), isEmpty);
  });
  test('duplicate plan entries are rejected', () async {
    final link = await legacyLink();
    await expectLater(apply([link, link]), throwsArgumentError);
    expect((await rows()).last.saleReturnId, isNull);
  });
}
