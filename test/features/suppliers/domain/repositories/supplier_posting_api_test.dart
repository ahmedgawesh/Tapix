import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/suppliers/domain/repositories/supplier_repository.dart';

/// Phase 3.5.3 — locks the supplier-side equivalent of
/// `customer_posting_api_test.dart`. Same reasoning, different ledger.
void main() {
  late _RecordingSupplierRepository repo;

  setUp(() {
    repo = _RecordingSupplierRepository();
  });

  test('recordPayment forwards a negated amount and "payment" type',
      () async {
    await repo.recordPayment(
      supplierId: 3,
      amountCents: 9999,
      currencyId: 1,
      description: 'Wire to vendor',
    );
    expect(repo.lastCall!['supplierId'], 3);
    expect(repo.lastCall!['transactionType'], 'payment');
    expect(repo.lastCall!['amountCents'], -9999);
    expect(repo.lastCall!['description'], 'Wire to vendor');
  });

  test('recordDiscount forwards "discount" type and discountType tag',
      () async {
    await repo.recordDiscount(
      supplierId: 3,
      amountCents: 50,
      currencyId: 1,
      discountType: 'volume',
    );
    expect(repo.lastCall!['transactionType'], 'discount');
    expect(repo.lastCall!['amountCents'], -50);
    expect(repo.lastCall!['discountType'], 'volume');
  });

  test('recordPayment rejects non-positive amounts', () {
    expect(
      () => repo.recordPayment(supplierId: 1, amountCents: 0, currencyId: 1),
      throwsArgumentError,
    );
    expect(
      () => repo.recordPayment(supplierId: 1, amountCents: -1, currencyId: 1),
      throwsArgumentError,
    );
  });

  test('recordDiscount rejects non-positive amounts', () {
    expect(
      () => repo.recordDiscount(supplierId: 1, amountCents: 0, currencyId: 1),
      throwsArgumentError,
    );
  });
}

class _RecordingSupplierRepository implements SupplierRepository {
  Map<String, Object?>? lastCall;

  @override
  Future<int> recordTransaction({
    required int supplierId,
    required String transactionType,
    required int amountCents,
    required int currencyId,
    String? description,
    int? referenceId,
    String? referenceType,
    String? discountType,
    DateTime? transactionDate,
  }) async {
    lastCall = {
      'supplierId': supplierId,
      'transactionType': transactionType,
      'amountCents': amountCents,
      'currencyId': currencyId,
      'description': description,
      'referenceId': referenceId,
      'referenceType': referenceType,
      'discountType': discountType,
      'transactionDate': transactionDate,
    };
    return 7;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        'Method ${invocation.memberName} not stubbed in test double.',
      );
}
