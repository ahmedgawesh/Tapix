import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';

void main() {
  late AppDatabase db;
  late AdjustmentReturnDao dao;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    dao = AdjustmentReturnDao(db);
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  SaleReturnAdjustmentsCompanion header() =>
      SaleReturnAdjustmentsCompanion.insert(
        returnNumber: 'SRS-GUARD',
        currencyId: 1,
        totalCents: Decimal.fromInt(100),
      );

  SaleReturnAdjustmentItemsCompanion line({
    Value<String?> sourceResolution = const Value.absent(),
    Value<String?> sourceResolutionReason = const Value.absent(),
  }) => SaleReturnAdjustmentItemsCompanion.insert(
    returnId: 0,
    productId: 1,
    quantity: 1,
    unitPriceCents: Decimal.fromInt(100),
    totalCents: Decimal.fromInt(100),
    sourceResolution: sourceResolution,
    sourceResolutionReason: sourceResolutionReason,
  );

  test('DAO rejects a missing settlement-return source decision', () async {
    expect(
      () => dao.createSaleAdjReturn(header(), [line()]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'returns.source_decision_required',
        ),
      ),
    );
  });

  test('DAO rejects unverified source without an audit reason', () async {
    expect(
      () => dao.createSaleAdjReturn(header(), [
        line(sourceResolution: const Value('unverified')),
      ]),
      throwsA(isA<StateError>()),
    );
  });

  test('DAO rejects not-applicable for a tracked inventory product', () async {
    expect(
      () => dao.createSaleAdjReturn(header(), [
        line(sourceResolution: const Value('not_applicable')),
      ]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'returns.source_decision_required',
        ),
      ),
    );
  });
}
