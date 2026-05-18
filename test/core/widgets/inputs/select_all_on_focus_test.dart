// Regression tests for the select-all-on-focus UX helper.
// Pins the contract that every numeric/monetary input across the app relies on.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/widgets/inputs/select_all_on_focus.dart';

void main() {
  group('selectAllText', () {
    test('selects the full range of a populated controller', () {
      final ctrl = TextEditingController(text: '1500.00');
      selectAllText(ctrl);
      expect(ctrl.selection.start, 0);
      expect(ctrl.selection.end, '1500.00'.length);
      expect(ctrl.selection.isCollapsed, isFalse);
      ctrl.dispose();
    });

    test('is a no-op on an empty controller', () {
      final ctrl = TextEditingController();
      // Should not throw; selection stays at default (-1, -1).
      selectAllText(ctrl);
      expect(ctrl.text, isEmpty);
      ctrl.dispose();
    });

    test('does not mutate the underlying text', () {
      final ctrl = TextEditingController(text: '99.50');
      selectAllText(ctrl);
      expect(ctrl.text, '99.50');
      ctrl.dispose();
    });
  });

  group('SelectAllOnFocusNode', () {
    testWidgets('selects all on focus gain', (tester) async {
      final ctrl = TextEditingController(text: '42.00');
      final focus = SelectAllOnFocusNode(ctrl);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(controller: ctrl, focusNode: focus),
        ),
      ));

      focus.requestFocus();
      await tester.pump();

      expect(focus.hasFocus, isTrue);
      expect(ctrl.selection.start, 0);
      expect(ctrl.selection.end, '42.00'.length);

      focus.dispose();
      ctrl.dispose();
    });

    testWidgets('does not throw when controller is empty', (tester) async {
      final ctrl = TextEditingController();
      final focus = SelectAllOnFocusNode(ctrl);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextField(controller: ctrl, focusNode: focus),
        ),
      ));

      focus.requestFocus();
      await tester.pump();

      expect(focus.hasFocus, isTrue);
      focus.dispose();
      ctrl.dispose();
    });

    testWidgets('re-selects on every focus gain', (tester) async {
      final ctrl = TextEditingController(text: '7.00');
      final focus = SelectAllOnFocusNode(ctrl);
      final otherFocus = FocusNode();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(controller: ctrl, focusNode: focus),
              TextField(focusNode: otherFocus),
            ],
          ),
        ),
      ));

      focus.requestFocus();
      await tester.pump();
      expect(ctrl.selection.end, '7.00'.length);

      // Collapse selection (simulate user clicking somewhere inside the text).
      ctrl.selection = const TextSelection.collapsed(offset: 2);
      otherFocus.requestFocus();
      await tester.pump();

      focus.requestFocus();
      await tester.pump();
      expect(ctrl.selection.start, 0);
      expect(ctrl.selection.end, '7.00'.length);

      focus.dispose();
      otherFocus.dispose();
      ctrl.dispose();
    });
  });
}
