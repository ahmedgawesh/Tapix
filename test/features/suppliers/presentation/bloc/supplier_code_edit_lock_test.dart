import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/money/money_input_parser.dart';
import 'package:tapix/core/services/inventory/supplier_identity_rules.dart';
import 'package:tapix/features/suppliers/domain/repositories/supplier_repository.dart';
import 'package:tapix/features/suppliers/presentation/bloc/supplier_form_bloc.dart';
import '../../support/supplier_lifecycle_repository.dart';

class _Parser extends Mock implements MoneyInputParser {}

class _EditRepository extends Fake implements SupplierRepository {
  Supplier saved = sampleSupplier(1, 'N1');
  bool locked = false;

  @override
  Future<Supplier?> getSupplier(int id) async => saved;
  @override
  Future<bool> isProductCodeLocked(int id) async => locked;
  @override
  Future<List<Supplier>> searchSuppliers(
    String query, {
    bool? isActive,
  }) async => [saved];
  @override
  Future<bool> isProductCodeAvailable(
    String? code, {
    int? excludingSupplierId,
  }) async => true;
  @override
  Future<bool> updateSupplier(Supplier supplier) async {
    if (locked && supplier.productCode != saved.productCode) {
      throw const SupplierIdentityException('supplier_identity.code_locked');
    }
    saved = supplier;
    return true;
  }

  @override
  Future<int?> adjustOpeningBalance({
    required int supplierId,
    required int desiredBalanceCents,
    String? description,
  }) async => null;
}

void main() {
  late _EditRepository repository;
  late SupplierFormBloc bloc;

  Future<void> send(SupplierFormEvent event) async {
    final next = bloc.stream.firstWhere((s) => s is SupplierFormReady);
    bloc.add(event);
    await next.timeout(const Duration(seconds: 5));
  }

  Future<SupplierFormState> submit() async {
    final next = bloc.stream.firstWhere(
      (s) =>
          s is SupplierFormSuccess ||
          s is SupplierFormError ||
          (s is SupplierFormReady && !s.isSubmitting),
    );
    bloc.add(const SupplierFormSubmitted());
    return next.timeout(const Duration(seconds: 5));
  }

  setUp(() {
    repository = _EditRepository();
    final parser = _Parser();
    when(() => parser.parseSignedOrZero(any())).thenReturn(0);
    bloc = SupplierFormBloc(repository, moneyParser: parser);
  });
  tearDown(() => bloc.close());

  test(
    'saved history locks field on load while supplier name stays editable',
    () async {
      repository.locked = true;
      await send(const SupplierFormLoadRequested(supplierId: 1));
      expect((bloc.state as SupplierFormReady).productCodeLocked, isTrue);
      await send(const SupplierFormNameChanged('New name'));
      expect(await submit(), isA<SupplierFormSuccess>());
      expect(repository.saved.name, 'New name');
      expect(repository.saved.productCode, 'N1');
      expect(repository.saved.balanceCents, Decimal.zero);
    },
  );

  test(
    'a concurrently saved invoice rejects draft code and restores stored code',
    () async {
      await send(const SupplierFormLoadRequested(supplierId: 1));
      await send(const SupplierFormProductCodeChanged('N2'));
      repository.locked = true;
      final result = (await submit()) as SupplierFormReady;
      expect(result.productCode, 'N1');
      expect(result.productCodeLocked, isTrue);
      expect(result.errors['productCode'], 'supplier_identity.code_locked');
      await send(const SupplierFormNameChanged('Still editable'));
      expect(await submit(), isA<SupplierFormSuccess>());
      expect(repository.saved.productCode, 'N1');
    },
  );

  test('code remains editable before use', () async {
    await send(const SupplierFormLoadRequested(supplierId: 1));
    await send(const SupplierFormProductCodeChanged('007'));
    expect(await submit(), isA<SupplierFormSuccess>());
    expect(repository.saved.productCode, '007');
  });
}
