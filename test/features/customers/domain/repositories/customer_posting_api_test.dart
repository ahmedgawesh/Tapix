import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/customers/domain/repositories/customer_repository.dart';

/// Phase 3.5.3 — locks the contract of `CustomerPostingApi`:
///
///   * `recordPayment` always forwards a *negative* `amountCents` to
///     `recordTransaction` (the sign-flip the widgets used to perform
///     inline now lives here, in exactly one place).
///   * `recordDiscount` does the same and additionally tags the entry
///     with the right `transactionType` and `discountType`.
///   * Both helpers reject non-positive inputs at the boundary so a
///     stale form value can never silently post a zero or already-flipped
///     transaction.
void main() {
  late _RecordingCustomerRepository repo;

  setUp(() {
    repo = _RecordingCustomerRepository();
  });

  group('recordPayment', () {
    test('forwards a negated amount and the "payment" type', () async {
      final id = await repo.recordPayment(
        customerId: 7,
        amountCents: 1500,
        currencyId: 1,
        description: 'May rent',
      );
      expect(id, 42);
      expect(repo.lastCall, isNotNull);
      expect(repo.lastCall!['customerId'], 7);
      expect(repo.lastCall!['transactionType'], 'payment');
      expect(repo.lastCall!['amountCents'], -1500);
      expect(repo.lastCall!['currencyId'], 1);
      expect(repo.lastCall!['description'], 'May rent');
    });

    test('rejects zero amount with ArgumentError', () {
      expect(
        () => repo.recordPayment(customerId: 1, amountCents: 0, currencyId: 1),
        throwsArgumentError,
      );
    });

    test('rejects negative amount with ArgumentError', () {
      expect(
        () =>
            repo.recordPayment(customerId: 1, amountCents: -500, currencyId: 1),
        throwsArgumentError,
      );
    });
  });

  group('recordDiscount', () {
    test(
      'forwards a negated amount, "discount" type and discountType tag',
      () async {
        await repo.recordDiscount(
          customerId: 9,
          amountCents: 250,
          currencyId: 1,
          discountType: 'seasonal',
        );
        expect(repo.lastCall!['transactionType'], 'discount');
        expect(repo.lastCall!['amountCents'], -250);
        expect(repo.lastCall!['discountType'], 'seasonal');
      },
    );

    test('defaults discountType to "cash" when omitted', () async {
      await repo.recordDiscount(customerId: 9, amountCents: 100, currencyId: 1);
      expect(repo.lastCall!['discountType'], 'cash');
    });

    test('rejects zero or negative amounts', () {
      expect(
        () => repo.recordDiscount(customerId: 1, amountCents: 0, currencyId: 1),
        throwsArgumentError,
      );
      expect(
        () =>
            repo.recordDiscount(customerId: 1, amountCents: -1, currencyId: 1),
        throwsArgumentError,
      );
    });
  });
}

/// Minimal `CustomerRepository` stub that records the most recent
/// `recordTransaction` call. Every method besides `recordTransaction`
/// throws `UnimplementedError`, so any drift in the extension that
/// touches a different repository method would surface immediately.
class _RecordingCustomerRepository implements CustomerRepository {
  Map<String, Object?>? lastCall;

  @override
  Future<int> recordTransaction({
    required int customerId,
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
      'customerId': customerId,
      'transactionType': transactionType,
      'amountCents': amountCents,
      'currencyId': currencyId,
      'description': description,
      'referenceId': referenceId,
      'referenceType': referenceType,
      'discountType': discountType,
      'transactionDate': transactionDate,
    };
    return 42;
  }

  // ── Unused members (throw so a regression that touches them fails loudly) ──

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Method ${invocation.memberName} not stubbed in test double.',
  );
}
