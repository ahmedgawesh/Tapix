// Single source of truth for the "select all numeric input on focus" UX
// behaviour used across every screen and dialog that accepts monetary or
// quantitative values (prices, costs, taxes, discounts, quantities, amounts,
// salaries, commissions, loyalty points, etc.).
//
// Why this is centralised:
// * Per the project's ACCOUNTING_INTEGRITY_GUIDELINES, repeated UX logic must
//   live behind a single helper instead of being copy-pasted into every form.
// * The helpers below are pure UX glue — they do NOT touch validation,
//   formatting, pricing engines, repositories, BLoCs, or any persisted value.
//
// Two utilities are exposed:
//   1. [selectAllText]  — a tiny function intended for `TextFormField.onTap`
//                         (covers the dominant mobile/POS tap interaction).
//   2. [SelectAllOnFocusNode] — a `FocusNode` subclass that selects-all whenever
//                               focus is gained, also covering Tab/keyboard
//                               navigation on desktop and web.
//
// Both utilities are safe to use with any [TextEditingController] regardless
// of input formatters or keyboard type; they only mutate `controller.selection`
// — never the underlying text.

import 'package:flutter/widgets.dart';

/// Selects all text currently in [controller].
///
/// Designed for use inside `TextFormField.onTap` / `TextField.onTap` so that
/// the user can immediately overwrite a numeric value (e.g. `0.00`, `1500`,
/// `15%`) without having to manually clear the field first.
///
/// Safe to call when the controller is empty — it becomes a no-op.
void selectAllText(TextEditingController controller) {
  final length = controller.text.length;
  if (length == 0) return;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: length,
  );
}

/// A [FocusNode] that automatically selects all text in the supplied
/// [TextEditingController] every time the node gains focus.
///
/// This complements `onTap`-based selection by also covering focus
/// transitions caused by Tab key navigation (common on desktop / web).
///
/// Usage:
/// ```dart
/// late final TextEditingController _priceCtrl;
/// late final SelectAllOnFocusNode _priceFocus;
///
/// @override
/// void initState() {
///   super.initState();
///   _priceCtrl = TextEditingController(text: '0.00');
///   _priceFocus = SelectAllOnFocusNode(_priceCtrl);
/// }
///
/// @override
/// void dispose() {
///   _priceFocus.dispose();
///   _priceCtrl.dispose();
///   super.dispose();
/// }
///
/// // …
/// TextFormField(
///   controller: _priceCtrl,
///   focusNode: _priceFocus,
///   // …
/// )
/// ```
class SelectAllOnFocusNode extends FocusNode {
  SelectAllOnFocusNode(this._controller) {
    addListener(_handleFocusChange);
  }

  final TextEditingController _controller;

  void _handleFocusChange() {
    if (hasFocus) {
      selectAllText(_controller);
    }
  }

  @override
  void dispose() {
    removeListener(_handleFocusChange);
    super.dispose();
  }
}
