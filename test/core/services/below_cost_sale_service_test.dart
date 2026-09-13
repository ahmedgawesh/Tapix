import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/below_cost_sale_service.dart';
import 'package:tapix/features/auth/domain/entities/user_entity.dart';

void main() {
  const service = BelowCostSaleService();

  BelowCostCheckResult check(UserRole role, {required bool policyEnabled}) {
    return service.check(
      costCents: Decimal.fromInt(1000),
      sellingPriceCents: Decimal.fromInt(900),
      productName: 'Test product',
      productId: 7,
      lineTempId: 'line-1',
      userRole: role,
      allowOverride: policyEnabled,
    );
  }

  test('global policy is required even for managers and owners', () {
    expect(check(UserRole.manager, policyEnabled: false).canOverride, isFalse);
    expect(check(UserRole.owner, policyEnabled: false).canOverride, isFalse);
  });

  test('enabled policy permits only managers and owners to override', () {
    expect(check(UserRole.manager, policyEnabled: true).canOverride, isTrue);
    expect(check(UserRole.owner, policyEnabled: true).canOverride, isTrue);
    expect(check(UserRole.cashier, policyEnabled: true).canOverride, isFalse);
    expect(
      check(UserRole.salesperson, policyEnabled: true).canOverride,
      isFalse,
    );
  });

  test('warning remains tied to the exact invoice line', () {
    final result = check(UserRole.owner, policyEnabled: true);
    expect(result.lineTempId, 'line-1');
    expect(result.lossCents, Decimal.fromInt(100));
  });
}
