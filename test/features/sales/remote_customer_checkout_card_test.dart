import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/core/services/lan/lan_business_models.dart';
import 'package:tapix/features/sales/presentation/widgets/remote_customer_checkout_card.dart';

void main() {
  testWidgets(
    'shows master balances, refreshes and never retains another customer snapshot',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final currency = CurrencyService(await SharedPreferences.getInstance());
      var response = Completer<LanCustomerCheckout>();
      Widget card(int customer) => MaterialApp(
        home: Scaffold(
          body: RemoteCustomerCheckoutCard(
            customerId: customer,
            currencyId: 1,
            invoiceTotalCents: 95000,
            paidAmountCents: 0,
            currencyService: currency,
            load: (_) => response.future,
          ),
        ),
      );
      await tester.pumpWidget(card(1));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      response.complete(
        const LanCustomerCheckout(
          customerId: 1,
          currencyId: 1,
          currencyCode: 'USD',
          balanceCents: 554101,
          pointsBalance: 7661,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('7661'), findsOneWidget);
      expect(find.textContaining('6,491.01'), findsOneWidget);
      response = Completer<LanCustomerCheckout>();
      await tester.pumpWidget(card(2));
      await tester.pump();
      expect(find.textContaining('7661'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      response.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('7661'), findsNothing);
      response = Completer<LanCustomerCheckout>();
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      response.complete(
        const LanCustomerCheckout(
          customerId: 2,
          currencyId: 1,
          currencyCode: 'USD',
          balanceCents: -500,
          pointsBalance: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('sales.loyalty_points: 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
