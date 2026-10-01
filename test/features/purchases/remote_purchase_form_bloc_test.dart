import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/entities/product_variant_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_form_bloc.dart';

class _Purchases extends Mock implements PurchaseRepository {}

class _Products extends Mock implements ProductRepository {}

class _Variants extends Mock implements ProductVariantRepository {}

class _Lan extends Mock implements LanNetworkService {}

Future<void> _until(
  PurchaseFormBloc bloc,
  bool Function(PurchaseFormState) match,
) async {
  if (match(bloc.state)) return;
  await bloc.stream.firstWhere(match).timeout(const Duration(seconds: 3));
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const LanPurchaseRequest(
        idempotencyKey: 'fallback',
        supplierId: 1,
        paymentMethod: 'credit',
        lines: [],
      ),
    );
  });

  late _Purchases purchases;
  late _Products products;
  late _Variants variants;
  late _Lan lan;
  LanPurchaseRequest? submitted;

  final product = Product(
    id: 41,
    name: 'Measured medicine',
    sku: 'MED-41',
    costCents: Decimal.fromInt(325),
    priceCents: Decimal.fromInt(500),
    stockQuantity: 8000,
    minQuantity: 0,
    hasVariants: true,
    isTaxable: false,
    purchaseTaxRateBps: 0,
    salesTaxRateBps: 0,
    isActive: true,
    trackInventory: true,
    measurementType: 'weight',
    inventoryTrackingType: 'batch_expiry',
  );
  final variant = ProductVariant(
    id: 77,
    productId: 41,
    sku: 'MED-41-BLUE',
    barcode: '6220000000041',
    costCents: Decimal.fromInt(325),
    priceCents: Decimal.fromInt(500),
    priceAdjustmentCents: Decimal.zero,
    stockQuantity: 8000,
    isActive: true,
  );

  PurchaseFormState seed({String? lot = ' LOT-REMOTE-7 '}) => PurchaseFormState(
    supplierId: 9,
    supplierName: 'Branch supplier',
    currencyId: 1,
    purchaseDate: DateTime.utc(2026, 10, 1),
    dueDate: DateTime.utc(2026, 11, 1),
    paymentMethod: PurchasePaymentMethod.credit,
    pharmacyFeaturesEnabled: true,
    useSupplierProductCodes: true,
    discountMode: DiscountMode.invoice,
    invoiceDiscountCents: Decimal.fromInt(50),
    items: [
      PurchaseLineItem(
        tempId: 'remote-line-1',
        product: product,
        variant: variant,
        quantity: 1250,
        unitCostCents: Decimal.fromInt(325),
        expiryDate: DateTime.utc(2028, 6, 30),
        manufacturerLotNumber: lot,
        isMedicine: true,
        colorName: 'Blue',
        sizeName: '1.25 kg',
        originalCostCents: 325,
        originalPriceCents: 500,
        newSellPriceCents: Decimal.fromInt(550),
      ),
    ],
  );

  PurchaseFormBloc build() =>
      PurchaseFormBloc(purchases, variants, products, lan: lan);

  setUp(() {
    purchases = _Purchases();
    products = _Products();
    variants = _Variants();
    lan = _Lan();
    submitted = null;
    when(() => lan.snapshot).thenReturn(
      const LanNetworkSnapshot(
        mode: LanMode.client,
        assignedBranchId: 'CAIRO',
        assignedWarehouseId: 'CAIRO-WH',
        assignedDeviceKind: LanDeviceKind.warehouseWorkstation,
      ),
    );
    when(() => lan.submitRemotePurchase(any())).thenAnswer((invocation) async {
      submitted = invocation.positionalArguments.single as LanPurchaseRequest;
      return const LanPurchaseResult(
        purchaseId: 501,
        purchaseNumber: 'PI-REMOTE-501',
        subtotalCents: 406,
        discountCents: 50,
        taxCents: 0,
        totalCents: 356,
        paidAmountCents: 0,
        status: 'draft',
      );
    });
  });

  blocTest<PurchaseFormBloc, PurchaseFormState>(
    'warehouse purchase stays remote, preserves scaled values, and creates a draft only',
    build: build,
    seed: seed,
    act: (bloc) async {
      bloc.add(const PurchaseFormSubmitted());
      await _until(bloc, (state) => state.isSuccess);
    },
    verify: (bloc) {
      final request = submitted;
      expect(request, isNotNull);
      expect(request!.supplierId, 9);
      expect(request.paymentMethod, 'credit');
      expect(request.paidAmountCents, 0);
      expect(request.overallDiscountType, 'fixed');
      expect(request.overallDiscountValue, 50);
      expect(request.expectedPricingFingerprint, isNotEmpty);
      expect(request.lines, hasLength(1));
      final line = request.lines.single;
      expect(line.productId, 41);
      expect(line.variantId, 77);
      expect(line.quantity, 1250);
      expect(line.unitCostCents, 325);
      expect(line.supplierIdentityRequested, isTrue);
      expect(line.manufacturerLotNumber, 'LOT-REMOTE-7');
      expect(line.expiryDate, DateTime.utc(2028, 6, 30));
      expect(line.newSellPriceCents, 550);
      expect(bloc.state.purchaseId, 501);
      expect(bloc.state.purchaseNumber, 'PI-REMOTE-501');
      verify(() => lan.submitRemotePurchase(any())).called(1);
      verifyNever(() => lan.postRemotePurchase(any()));
      verifyNoMoreInteractions(purchases);
      verifyNoMoreInteractions(products);
      verifyNoMoreInteractions(variants);
    },
  );

  blocTest<PurchaseFormBloc, PurchaseFormState>(
    'medicine lot validation blocks the remote request before any write',
    build: build,
    seed: () => seed(lot: '   '),
    act: (bloc) async {
      bloc.add(const PurchaseFormSubmitted());
      await _until(
        bloc,
        (state) => state.error == 'pharmacy.batch.lot_required_submit_blocked',
      );
    },
    verify: (bloc) {
      expect(bloc.state.isSuccess, isFalse);
      verifyNever(() => lan.submitRemotePurchase(any()));
      verifyNever(() => lan.postRemotePurchase(any()));
      verifyNoMoreInteractions(purchases);
      verifyNoMoreInteractions(products);
      verifyNoMoreInteractions(variants);
    },
  );
}
