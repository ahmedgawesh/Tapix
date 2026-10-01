import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/sales/presentation/services/sale_customer_account.dart';
import 'package:tapix/features/sales/presentation/widgets/sale_customer_points_summary.dart';

class _Branch extends Fake implements LanNetworkService {
  bool expired = false;
  @override
  LanNetworkSnapshot get snapshot =>
      const LanNetworkSnapshot(mode: LanMode.client);
  @override
  Future<LanCustomerCheckout> fetchRemoteCustomerCheckout(int id) async {
    if (expired) {
      throw const LanBusinessException(
        'authentication_required',
        'Sign in',
        statusCode: 401,
      );
    }
    return LanCustomerCheckout(
      customerId: id,
      currencyId: 1,
      currencyCode: 'USD',
      balanceCents: 2700,
      pointsBalance: 7661,
    );
  }
}

void main() {
  test(
    'receipt balance and loyalty always come from the owning branch',
    () async {
      final branch = _Branch();
      final result = await loadSaleCustomerAccount(
        customerId: 4,
        lan: branch,
        loadLocal: (_) async => throw StateError('Wrong local customer'),
      );
      expect(result!.balanceCents, 2700);
      expect(result.pointsBalance, 7661);
      branch.expired = true;
      await expectLater(
        loadSaleCustomerAccount(
          customerId: 4,
          lan: branch,
          loadLocal: (_) async => throw StateError('Wrong local customer'),
        ),
        throwsA(isA<LanBusinessException>()),
      );
    },
  );
  testWidgets(
    'confirmation shows committed points and retry never invents a zero balance',
    (tester) async {
      var failed = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SaleCustomerPointsSummary(
              load: () async {
                if (failed) throw StateError('offline');
                return 7661;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('checkout_customer_unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining(': 0'), findsNothing);
      failed = false;
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.textContaining('7661'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
