import 'package:flutter/material.dart';

/// Collects a mandatory audit reason without owning a controller.
///
/// Keeping the value in the route closure lets Flutter finish the dialog exit
/// animation before every TextField dependency disappears.
Future<String?> showConsignmentReasonDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String cancelLabel,
  required String confirmLabel,
}) {
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        autofocus: true,
        maxLength: 500,
        decoration: InputDecoration(labelText: label),
        onChanged: (input) => value = input,
        onFieldSubmitted: (input) {
          final result = input.trim();
          if (result.isNotEmpty) Navigator.pop(dialogContext, result);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () {
            final result = value.trim();
            if (result.isNotEmpty) Navigator.pop(dialogContext, result);
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
