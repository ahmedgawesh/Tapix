import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/consignment/presentation/widgets/consignment_reason_dialog.dart';

void main() {
  testWidgets(
    'reason dialog can confirm and close repeatedly without a disposed controller',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      String? confirmed;
      final first = showConsignmentReasonDialog(
        key.currentContext!,
        title: 'Void receipt',
        label: 'Reason',
        cancelLabel: 'Cancel',
        confirmLabel: 'Confirm',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '  Wrong receipt  ');
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      confirmed = await first;
      expect(confirmed, 'Wrong receipt');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);

      final second = showConsignmentReasonDialog(
        key.currentContext!,
        title: 'Void receipt',
        label: 'Reason',
        cancelLabel: 'Cancel',
        confirmLabel: 'Confirm',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(await second, isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
