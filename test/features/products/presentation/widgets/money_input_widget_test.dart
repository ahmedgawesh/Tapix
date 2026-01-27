import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/products/presentation/widgets/money_input_widget.dart';
import 'package:tapix/core/services/currency_service.dart';

class MockCurrencyService extends Mock implements CurrencyService {}

void main() {
  group('MoneyInputWidget', () {
    late MockCurrencyService currencyService;

    setUp(() {
      currencyService = MockCurrencyService();
      when(() => currencyService.currencySymbol).thenReturn('\$');
      when(() => currencyService.format(any())).thenAnswer((invocation) {
        final cents = invocation.positionalArguments[0] as int;
        return '\$${(cents / 100).toStringAsFixed(2)}';
      });
    });

    Widget createWidget(Widget child) {
      return MaterialApp(
        home: Scaffold(
          body: RepositoryProvider<CurrencyService>.value(
            value: currencyService,
            child: child,
          ),
        ),
      );
    }

    testWidgets('renders with initial value', (tester) async {
      final value = Decimal.fromInt(1000); // $10.00
      
      await tester.pumpWidget(createWidget(
        MoneyInputWidget(
          value: value,
          onChanged: (_) {},
          label: 'Price',
        ),
      ));

      expect(find.text('10.00'), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
    });

    testWidgets('updates value on input', (tester) async {
      Decimal? changedValue;
      
      await tester.pumpWidget(createWidget(
        MoneyInputWidget(
          value: Decimal.zero,
          onChanged: (val) => changedValue = val,
          label: 'Price',
        ),
      ));

      await tester.enterText(find.byType(TextField), '15.50');
      await tester.pump();

      // Trigger focus loss to update
      await tester.tap(find.byType(Scaffold));
      await tester.pump();

      expect(changedValue, equals(Decimal.fromInt(1550)));
    });

    testWidgets('displays error text', (tester) async {
      await tester.pumpWidget(createWidget(
        MoneyInputWidget(
          value: Decimal.zero,
          onChanged: (_) {},
          errorText: 'Invalid amount',
        ),
      ));

      expect(find.text('Invalid amount'), findsOneWidget);
    });
  });
}
