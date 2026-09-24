import 'dart:async';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/money/money_input_parser.dart';
import 'package:tapix/core/services/inventory/supplier_identity_rules.dart';
import 'package:tapix/features/suppliers/domain/repositories/supplier_repository.dart';
import 'package:tapix/features/suppliers/presentation/bloc/supplier_form_bloc.dart';

class _MoneyParser extends Mock implements MoneyInputParser {}

class _Repository extends Fake implements SupplierRepository {
  int creates = 0;
  String? savedCode;
  bool available = true;
  bool rejectAtCommit = false;
  Completer<void>? gate;

  @override
  Future<List<Supplier>> searchSuppliers(
    String query, {
    bool? isActive,
  }) async => [];

  @override
  Future<bool> isProductCodeAvailable(
    String? code, {
    int? excludingSupplierId,
  }) async => available;

  @override
  Future<int> createSupplier({
    required String name,
    String? email,
    String? phone,
    String? address,
    String? productCode,
    required int currencyId,
    Decimal? initialBalance,
  }) async {
    creates++;
    if (gate != null) await gate!.future;
    if (rejectAtCommit) {
      throw const SupplierIdentityException('supplier_identity.code_in_use');
    }
    savedCode = productCode;
    return creates;
  }
}

void main() {
  late _Repository repository;
  late SupplierFormBloc bloc;

  Future<void> send(
    SupplierFormEvent event,
    bool Function(SupplierFormReady) predicate,
  ) async {
    final ready = bloc.stream.firstWhere(
      (s) => s is SupplierFormReady && predicate(s),
    );
    bloc.add(event);
    await ready.timeout(const Duration(seconds: 5));
  }

  Future<SupplierFormState> submit() async {
    final done = bloc.stream.firstWhere(
      (s) =>
          s is SupplierFormSuccess ||
          s is SupplierFormError ||
          (s is SupplierFormReady && !s.isSubmitting),
    );
    bloc.add(const SupplierFormSubmitted());
    return done.timeout(const Duration(seconds: 5));
  }

  setUp(() async {
    repository = _Repository();
    final parser = _MoneyParser();
    when(() => parser.parseSignedOrZero(any())).thenReturn(0);
    bloc = SupplierFormBloc(repository, moneyParser: parser);
    await send(const SupplierFormLoadRequested(), (_) => true);
    await send(const SupplierFormNameChanged('Noor'), (s) => s.name == 'Noor');
  });
  tearDown(() => bloc.close());

  test(
    'alphanumeric prefix is passed normalized through form -> repository',
    () async {
      await send(
        const SupplierFormProductCodeChanged(' aln2026 '),
        (s) => s.productCode == ' aln2026 ',
      );
      expect(await submit(), isA<SupplierFormSuccess>());
      expect(repository.savedCode, 'ALN2026');
    },
  );

  test('numeric-looking code keeps leading zeroes', () async {
    await send(
      const SupplierFormProductCodeChanged('007'),
      (s) => s.productCode == '007',
    );
    expect(await submit(), isA<SupplierFormSuccess>());
    expect(repository.savedCode, '007');
  });

  test('invalid text is rejected before a create call', () async {
    await send(
      const SupplierFormProductCodeChanged('N-1'),
      (s) => s.productCode == 'N-1',
    );
    final result = (await submit()) as SupplierFormReady;
    expect(result.errors['productCode'], 'supplier_identity.invalid_code');
    expect(repository.creates, 0);
  });

  test('duplicate code is an inline error, not a raw SQL message', () async {
    repository.available = false;
    await send(
      const SupplierFormProductCodeChanged('N1'),
      (s) => s.productCode == 'N1',
    );
    final result = (await submit()) as SupplierFormReady;
    expect(result.errors['productCode'], 'supplier_identity.code_in_use');
    expect(repository.creates, 0);
  });

  test(
    'concurrent DB reservation failure is still handled after the early check',
    () async {
      repository.rejectAtCommit = true;
      await send(
        const SupplierFormProductCodeChanged('N1'),
        (s) => s.productCode == 'N1',
      );
      final result = (await submit()) as SupplierFormReady;
      expect(result.isSubmitting, isFalse);
      expect(result.errors['productCode'], 'supplier_identity.code_in_use');
    },
  );

  test('editing code clears its conflict so the user can retry', () async {
    repository.available = false;
    await send(
      const SupplierFormProductCodeChanged('N1'),
      (s) => s.productCode == 'N1',
    );
    await submit();
    repository.available = true;
    await send(
      const SupplierFormProductCodeChanged('N2'),
      (s) => s.productCode == 'N2',
    );
    expect((bloc.state as SupplierFormReady).errors, isEmpty);
    expect(await submit(), isA<SupplierFormSuccess>());
  });

  test('blank optional code reaches the repository as NULL', () async {
    expect(await submit(), isA<SupplierFormSuccess>());
    expect(repository.savedCode, isNull);
  });

  test('double submit is blocked before the first async check', () async {
    repository.gate = Completer<void>();
    final saving = bloc.stream.firstWhere(
      (s) => s is SupplierFormReady && s.isSubmitting,
    );
    bloc.add(const SupplierFormSubmitted());
    bloc.add(const SupplierFormSubmitted());
    await saving;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repository.creates, 1);
    final done = bloc.stream.firstWhere((s) => s is SupplierFormSuccess);
    repository.gate!.complete();
    await done;
    expect(repository.creates, 1);
  });
}
