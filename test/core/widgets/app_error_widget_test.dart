import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/widgets/app_error_widget.dart';

void main() {
  testWidgets('fallback builds without Theme, Material or Navigator', (
    tester,
  ) async {
    final details = FlutterErrorDetails(exception: StateError('test'));
    await tester.pumpWidget(
      SizedBox(
        width: 320,
        height: 240,
        child: AppErrorWidget(details: details),
      ),
    );
    final richText = tester.widget<RichText>(find.byType(RichText));
    expect(richText.text.toPlainText(), contains('Something went wrong'));
    expect(find.byType(Text), findsNothing);
    expect(find.byType(Directionality), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
