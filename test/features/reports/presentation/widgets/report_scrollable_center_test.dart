import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/widgets/report_scrollable_center.dart';

void main() {
  testWidgets('scrolls instead of overflowing on a compact report viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              height: 100,
              child: ReportScrollableCenter(
                child: SizedBox(width: 280, height: 240),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });
}
