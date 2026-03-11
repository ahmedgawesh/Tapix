import 'package:flutter/material.dart';

/// Shows a styled snackbar informing the user that this action is disabled in demo mode.
void showDemoSnackbar(BuildContext context, [String? action]) {
  final msg = action != null
      ? '🔒 "$action" is disabled in Demo Mode'
      : '🔒 This action is disabled in Demo Mode';

  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.deepOrange.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.all(12),
    ),
  );
}
