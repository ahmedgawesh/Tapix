// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_form_bloc.dart';

class _Sales extends Mock implements SaleRepository {}

class _Variants extends Mock implements ProductVariantRepository {}

class _Products extends Mock implements ProductRepository {}

class _Audit extends Mock implements AuditLogService {}

class _Lan extends Fake implements LanNetworkService {
  int requests = 0;
  @override
  LanNetworkSnapshot get snapshot =>
      const LanNetworkSnapshot(mode: LanMode.client);
  @override
  Future<LanCustomerCheckout> fetchRemoteCustomerCheckout(int id) async {
    requests++;
    return LanCustomerCheckout(
      customerId: id,
      currencyId: 1,
      currencyCode: 'USD',
      balanceCents: 0,
      pointsBalance: 500,
      redemptionEnabled: true,
      pointValueCents: 2,
      minRedemptionPoints: 20,
      maxRedemptionPercentBps: 5000,
    );
  }
}

void main() {
  test(
    'cashier loads branch policy and redeems without changing taxable invoice',
    () async {
      final lan = _Lan();
      final bloc = SaleFormBloc(
        _Sales(),
        _Variants(),
        _Products(),
        _Audit(),
        lan: lan,
      );
      addTearDown(bloc.close);
      final product = Product(
        id: 1,
        name: 'Taxed item',
        costCents: Decimal.fromInt(100),
        priceCents: Decimal.fromInt(1000),
        stockQuantity: 10,
        minQuantity: 0,
        hasVariants: false,
        isTaxable: true,
        purchaseTaxRateBps: 0,
        salesTaxRateBps: 1000,
        isActive: true,
        trackInventory: false,
      );
      bloc.emit(
        bloc.state.copyWith(
          enableTaxCalculations: true,
          items: [
            SaleLineItem(
              tempId: 'line1',
              product: product,
              quantity: 1,
              unitPriceCents: Decimal.fromInt(1000),
            ),
          ],
        ),
      );
      final loaded = bloc.stream.firstWhere((s) => s.loyaltySettings != null);
      bloc.add(
        const SaleCustomerChanged(customerId: 7, customerName: 'Customer'),
      );
      await loaded;
      expect(lan.requests, 1);
      expect(bloc.state.canOfferLoyaltyRedemption, isTrue);
      final redeemed = bloc.stream.firstWhere(
        (s) => s.loyaltyPointsToRedeem > 0,
      );
      bloc.add(
        const SaleLoyaltyRedemptionChanged(enabled: true, pointsToRedeem: 100),
      );
      await redeemed;
      expect(bloc.state.loyaltyDiscountCents, 200);
      expect(bloc.state.taxCents, Decimal.fromInt(100));
      expect(bloc.state.totalBeforeLoyaltyCents, Decimal.fromInt(1100));
      expect(bloc.state.totalCents, Decimal.fromInt(900));
      final cleared = bloc.stream.firstWhere((s) => s.customerId == null);
      bloc.add(const SaleCustomerChanged());
      await cleared;
      expect(bloc.state.loyaltyPointsToRedeem, 0);
      expect(bloc.state.loyaltyDiscountCents, 0);
    },
  );
  test('wire rejects fractional redemption and preserves replay payload', () {
    const request = LanSaleRequest(
      idempotencyKey: 'loyalty-wire-001',
      paymentMethod: 'cash',
      loyaltyPointsToRedeem: 100,
      loyaltyValueCents: 200,
      lines: [],
    );
    expect(
      LanSaleRequest.fromJson(request.toJson()).copyWith().toJson(),
      request.toJson(),
    );
    expect(
      () => LanSaleRequest.fromJson({
        ...request.toJson(),
        'loyaltyPointsToRedeem': 1.5,
      }),
      throwsA(anything),
    );
  });
}
