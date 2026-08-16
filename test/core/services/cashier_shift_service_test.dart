import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/cashier_shift_service.dart';

void main() {
  late AppDatabase db;
  late CashierShiftService service;
  late int userId;
  late int currencyId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    service = CashierShiftService(db);
    final currency =
        await (db.select(db.currencies)
              ..where((c) => c.isBase.equals(true))
              ..limit(1))
            .getSingle();
    currencyId = currency.id;
    final now = DateTime(2026, 8, 9, 8);
    userId = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'cashier_shift_test',
            passwordHash: 'test',
            role: 'cashier',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  test('only one open shift is allowed per cashier', () async {
    final opened = await service.openShift(
      userId: userId,
      openingCashCents: 10000,
      openedAt: DateTime(2026, 8, 9, 8),
    );

    expect(await service.resolveOpenShiftId(userId), opened.shift.id);
    await expectLater(
      service.openShift(userId: userId, openingCashCents: 0),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'cashier_shift_already_open',
        ),
      ),
    );
  });

  test(
    'summary reconciles sales, both return types, and later payments',
    () async {
      final opened = await service.openShift(
        userId: userId,
        openingCashCents: 10000,
        openedAt: DateTime(2026, 8, 9, 8),
      );
      final shiftId = opened.shift.id;

      final cashSaleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'S-CASH',
              cashierShiftId: Value(shiftId),
              subtotalCents: Decimal.fromInt(15000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(15000),
              paidAmountCents: Value(Decimal.fromInt(12000)),
              currencyId: currencyId,
              paymentMethod: 'cash',
              status: const Value('completed'),
              saleDate: Value(DateTime(2026, 8, 9, 9)),
            ),
          );
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'S-CARD',
              cashierShiftId: Value(shiftId),
              subtotalCents: Decimal.fromInt(5000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(5000),
              paidAmountCents: Value(Decimal.fromInt(5000)),
              currencyId: currencyId,
              paymentMethod: 'card',
              status: const Value('completed'),
              saleDate: Value(DateTime(2026, 8, 9, 10)),
            ),
          );
      final linkedReturnId = await db
          .into(db.saleReturns)
          .insert(
            SaleReturnsCompanion.insert(
              saleId: cashSaleId,
              cashierShiftId: Value(shiftId),
              returnNumber: 'SR-LINKED',
              totalCents: Decimal.fromInt(2000),
              currencyId: currencyId,
              status: const Value('posted'),
              refundMethod: const Value('cash'),
              returnDate: Value(DateTime(2026, 8, 9, 11)),
            ),
          );
      final adjustmentReturnId = await db
          .into(db.saleReturnAdjustments)
          .insert(
            SaleReturnAdjustmentsCompanion.insert(
              returnNumber: 'SAR-ADJ',
              cashierShiftId: Value(shiftId),
              currencyId: currencyId,
              totalCents: Decimal.fromInt(1000),
              status: const Value('posted'),
              refundMethod: const Value('card'),
              returnDate: Value(DateTime(2026, 8, 9, 12)),
            ),
          );
      await db
          .into(db.salePayments)
          .insert(
            SalePaymentsCompanion.insert(
              saleId: cashSaleId,
              cashierShiftId: Value(shiftId),
              amountCents: Decimal.fromInt(3000),
              currencyId: currencyId,
              paymentMethod: 'cash',
              paymentDate: Value(DateTime(2026, 8, 9, 13)),
            ),
          );

      final summary = await service.getSummary(shiftId);
      expect(summary.salesCount, 2);
      expect(summary.linkedReturnsCount, 1);
      expect(summary.adjustmentReturnsCount, 1);
      expect(summary.additionalPaymentsCount, 1);
      expect(summary.grossSalesCents, 20000);
      expect(summary.returnsCents, 3000);
      expect(summary.netSalesCents, 17000);
      expect(summary.additionalPaymentsCents, 3000);
      expect(summary.cashReceivedCents, 15000);
      expect(summary.cashRefundedCents, 2000);
      expect(summary.expectedCashCents, 23000);
      expect(await service.getTransactions(shiftId), hasLength(5));

      // Every printable sales document resolves its own frozen shift. A
      // return must never inherit the original invoice cashier by date.
      expect(
        (await service.getSaleShift(cashSaleId))?.cashierName,
        'cashier_shift_test',
      );
      expect(
        (await service.getSaleReturnShift(linkedReturnId))?.shift.id,
        shiftId,
      );
      expect(
        (await service.getSaleAdjustmentReturnShift(
          adjustmentReturnId,
        ))?.shift.id,
        shiftId,
      );

      final closed = await service.closeShift(
        shiftId: shiftId,
        closedByUserId: userId,
        countedClosingCashCents: 22500,
        closedAt: DateTime(2026, 8, 9, 16),
      );
      expect(closed.varianceCents, -500);
      expect(await service.resolveOpenShiftId(userId), isNull);

      final persisted = (await service.getShift(shiftId))!.shift;
      expect(persisted.status, 'closed');
      expect(persisted.expectedClosingCashCents!.toBigInt().toInt(), 23000);
      expect(persisted.cashVarianceCents!.toBigInt().toInt(), -500);
    },
  );
}
