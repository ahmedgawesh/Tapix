import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/payments/checkout_settlement.dart';
import 'package:tapix/core/services/inventory/purchase_supplier_source_service.dart';
import 'package:tapix/core/services/inventory/supplier_identity_rules.dart';
import 'package:tapix/core/services/inventory/supplier_product_identity_service.dart';
import 'package:tapix/core/services/inventory/supplier_purchase_source_policy.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/purchases/domain/entities/purchase_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_form_bloc.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart';

class _Products extends Mock implements ProductRepository {}

class _Variants extends Mock implements ProductVariantRepository {}

class _Purchases extends Mock implements PurchaseRepository {
  int saves = 0;
  int? savedSupplier;
  List<PurchaseItemInput> savedItems = [];
  @override
  Future<int> createPurchase({
    required int supplierId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required List<PurchaseItemInput> items,
    String? paymentMethod,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,
    bool taxInclusiveAtPost = false,
    List<CheckoutPaymentAllocation> initialPayments = const [],
  }) async {
    saves++;
    savedSupplier = supplierId;
    savedItems = List.of(items);
    return 99;
  }
}

class _Previewer implements PurchaseSupplierSourcePreviewer {
  _Previewer(this.callback);
  final Future<SupplierIdentityPreview> Function(int supplierId) callback;
  final List<int> calls = [];
  @override
  Future<SupplierIdentityPreview> preview({
    required int supplierId,
    required int productId,
    int? variantId,
  }) {
    calls.add(supplierId);
    return callback(supplierId);
  }
}

SupplierIdentityPreview _value(int id) => SupplierIdentityPreview(
  supplierId: id,
  productId: 1,
  canonicalVariantId: 10,
  supplierCode: id == 1 ? 'N1' : '007',
  baseSku: '015',
  sourceSku: id == 1 ? 'N1-015' : '007-015',
);

Future<void> _until(
  PurchaseFormBloc bloc,
  bool Function(PurchaseFormState) match,
) async {
  if (match(bloc.state)) return;
  await bloc.stream.firstWhere(match).timeout(const Duration(seconds: 3));
}

void main() {
  late _Purchases repo;
  late _Products products;
  late _Variants variants;
  late _Previewer preview;
  final product = Product(
    id: 1,
    name: 'Product',
    sku: '015',
    costCents: Decimal.fromInt(2500),
    priceCents: Decimal.fromInt(3500),
    stockQuantity: 0,
    minQuantity: 0,
    hasVariants: false,
    isTaxable: false,
    isActive: true,
    trackInventory: true,
    purchaseTaxRateBps: 0,
    salesTaxRateBps: 0,
  );
  PurchaseFormState seed({bool enabled = true, bool submitting = false}) =>
      PurchaseFormState(
        supplierId: 1,
        currencyId: 1,
        purchaseDate: DateTime(2026, 9, 23),
        useSupplierProductCodes: enabled,
        isSubmitting: submitting,
        paymentMethod: PurchasePaymentMethod.credit,
        items: [
          PurchaseLineItem(
            tempId: 'L1',
            product: product,
            quantity: 2,
            unitCostCents: Decimal.fromInt(2500),
            originalCostCents: 2500,
            originalPriceCents: 3500,
          ),
        ],
      );
  PurchaseFormBloc build() => PurchaseFormBloc(
    repo,
    variants,
    products,
    supplierSourcePreviewer: preview,
  );
  setUp(() {
    repo = _Purchases();
    products = _Products();
    variants = _Variants();
    preview = _Previewer((id) async => _value(id));
  });

  test('existing settings default off and opt-in survives JSON round-trip', () {
    expect(AppSettings.fromMap({}).enableSupplierProductCodes, isFalse);
    final changed = AppSettings.fromMap(
      {},
    ).copyWith(enableSupplierProductCodes: true);
    expect(
      AppSettings.fromJson(changed.toJson()).enableSupplierProductCodes,
      isTrue,
    );
    expect(SupplierPurchaseSourcePolicy.enabled(false), isFalse);
    expect(
      SupplierPurchaseSourcePolicy.buildAllowsWrites,
      isTrue,
      reason: 'The completed source cycle must remain enabled in releases.',
    );
  });

  blocTest<PurchaseFormBloc, PurchaseFormState>(
    'N -> 007 -> N uses preview service and never concatenates prior SKU',
    build: build,
    seed: seed,
    act: (bloc) async {
      for (final id in [1, 2, 1]) {
        bloc.add(PurchaseSupplierChanged(id));
        await _until(
          bloc,
          (s) =>
              !s.isResolvingSupplierSources &&
              s.supplierSourcePreviews['L1']?.supplierId == id,
        );
      }
    },
    verify: (bloc) {
      expect(preview.calls, [1, 2, 1]);
      expect(bloc.state.supplierSourcePreviews['L1']!.sourceSku, 'N1-015');
      expect(bloc.state.items.single.product.sku, '015');
      expect(repo.saves, 0);
    },
  );

  group('controlled preview completion', () {
    late Completer<SupplierIdentityPreview> oldPreview;
    late Completer<void> oldStarted;
    blocTest<PurchaseFormBloc, PurchaseFormState>(
      'late N response cannot overwrite a newer 007 preview',
      build: () {
        oldPreview = Completer<SupplierIdentityPreview>();
        oldStarted = Completer<void>();
        preview = _Previewer((id) {
          if (id == 1) {
            oldStarted.complete();
            return oldPreview.future;
          }
          return Future.value(_value(id));
        });
        return build();
      },
      seed: seed,
      act: (bloc) async {
        bloc.add(const PurchaseSupplierChanged(1));
        await oldStarted.future;
        bloc.add(const PurchaseSupplierChanged(2));
        await _until(
          bloc,
          (s) => s.supplierSourcePreviews['L1']?.supplierId == 2,
        );
        oldPreview.complete(_value(1));
        await Future<void>.delayed(Duration.zero);
      },
      verify: (bloc) {
        expect(bloc.state.supplierSourcePreviews['L1']!.sourceSku, '007-015');
        expect(bloc.state.supplierId, 2);
      },
    );
  });

  group('submit while preview is pending', () {
    late Completer<SupplierIdentityPreview> pending;
    late Completer<void> started;
    var successes = 0;
    blocTest<PurchaseFormBloc, PurchaseFormState>(
      'late preview does not emit another success or navigate twice',
      build: () {
        pending = Completer<SupplierIdentityPreview>();
        started = Completer<void>();
        successes = 0;
        var calls = 0;
        preview = _Previewer((id) {
          calls++;
          if (calls == 1) {
            started.complete();
            return pending.future;
          }
          return Future.value(_value(id));
        });
        return build();
      },
      seed: seed,
      act: (bloc) async {
        final subscription = bloc.stream.listen((s) {
          if (s.isSuccess) successes++;
        });
        try {
          bloc.add(const PurchaseSupplierChanged(1));
          await started.future;
          bloc.add(const PurchaseFormSubmitted());
          await _until(bloc, (s) => s.isSuccess);
          pending.complete(_value(1));
          await Future<void>.delayed(Duration.zero);
        } finally {
          await subscription.cancel();
        }
      },
      verify: (bloc) {
        expect(successes, 1);
        expect(repo.saves, 1);
        expect(bloc.state.isResolvingSupplierSources, isFalse);
      },
    );
  });

  blocTest<PurchaseFormBloc, PurchaseFormState>(
    'preview error is shown and submit refuses rather than saving unknown source',
    build: () {
      preview = _Previewer(
        (_) async => throw const SupplierIdentityException(
          'supplier_identity.code_required',
        ),
      );
      return build();
    },
    seed: seed,
    act: (bloc) async {
      bloc.add(const PurchaseSupplierChanged(2));
      await _until(
        bloc,
        (s) =>
            s.supplierSourceErrors['L1'] == 'supplier_identity.code_required',
      );
      bloc.add(const PurchaseFormSubmitted());
      await _until(
        bloc,
        (s) => !s.isSubmitting && s.error == 'supplier_identity.code_required',
      );
    },
    verify: (bloc) {
      expect(repo.saves, 0);
      expect(bloc.state.isSuccess, isFalse);
    },
  );

  blocTest<PurchaseFormBloc, PurchaseFormState>(
    'submit carries request flag to the repository for database binding',
    build: build,
    seed: seed,
    act: (bloc) async {
      bloc.add(const PurchaseFormSubmitted());
      await _until(bloc, (s) => s.isSuccess);
    },
    verify: (bloc) {
      expect(repo.saves, 1);
      expect(repo.savedSupplier, 1);
      expect(repo.savedItems.single.supplierIdentityRequested, isTrue);
      expect(repo.savedItems.single.productId, 1);
      expect(preview.calls, [1]);
    },
  );

  blocTest<PurchaseFormBloc, PurchaseFormState>(
    'disabled option preserves old save path without preview or attribution',
    build: build,
    seed: () => seed(enabled: false),
    act: (bloc) async {
      bloc.add(const PurchaseFormSubmitted());
      await _until(bloc, (s) => s.isSuccess);
    },
    verify: (bloc) {
      expect(repo.savedItems.single.supplierIdentityRequested, isFalse);
      expect(preview.calls, isEmpty);
    },
  );

  blocTest<PurchaseFormBloc, PurchaseFormState>(
    'supplier edits and double submit are ignored while a save is running',
    build: build,
    seed: () => seed(submitting: true),
    act: (bloc) {
      bloc.add(const PurchaseSupplierChanged(2));
      bloc.add(const PurchaseFormSubmitted());
    },
    verify: (bloc) {
      expect(bloc.state.supplierId, 1);
      expect(repo.saves, 0);
      expect(preview.calls, isEmpty);
    },
  );

  for (final requested in [false, true]) {
    blocTest<PurchaseFormBloc, PurchaseFormState>(
      'saved draft source request $requested survives opposite global preference',
      build: () {
        final date = DateTime(2026, 9, 23);
        when(() => repo.getPurchaseById(22)).thenAnswer(
          (_) async => PurchaseEntity(
            id: 22,
            purchaseNumber: 'OLD-22',
            supplierId: 1,
            currencyId: 1,
            subtotalCents: Decimal.fromInt(5000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(5000),
            status: 'draft',
            paymentMethod: 'credit',
            purchaseDate: date,
            createdAt: date,
            updatedAt: date,
          ),
        );
        when(() => repo.getPurchaseItems(22)).thenAnswer(
          (_) async => [
            PurchaseItemEntity(
              id: 1,
              purchaseId: 22,
              productId: 1,
              quantity: 2,
              unitCostCents: Decimal.fromInt(2500),
              subtotalCents: Decimal.fromInt(5000),
              totalCents: Decimal.fromInt(5000),
              taxCents: Decimal.zero,
              createdAt: date,
              supplierIdentityRequested: requested,
              supplierIdentityId: requested ? 7 : null,
              supplierSourceSku: requested ? 'N1-015' : null,
            ),
          ],
        );
        when(
          () => products.watchProduct(1),
        ).thenAnswer((_) => Stream.value(product));
        when(
          () => variants.getDefaultVariantByProduct(1),
        ).thenAnswer((_) async => null);
        when(() => variants.getAllColors()).thenAnswer((_) async => []);
        when(() => variants.getAllSizes()).thenAnswer((_) async => []);
        return build();
      },
      act: (bloc) async {
        bloc.add(
          PurchaseFormInitialized(
            purchaseId: 22,
            currencyId: 1,
            useSupplierProductCodes: !requested,
          ),
        );
        await _until(
          bloc,
          (s) =>
              s.items.isNotEmpty &&
              s.purchaseId == 22 &&
              (!requested || s.supplierSourcePreviews.isNotEmpty),
        );
      },
      verify: (bloc) {
        expect(bloc.state.useSupplierProductCodes, requested);
        expect(preview.calls, requested ? [1] : isEmpty);
        expect(repo.saves, 0);
      },
    );
  }
}
