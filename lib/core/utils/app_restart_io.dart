import 'dart:io';

/// Closes the process where platform conventions allow it.
///
/// iOS applications must never terminate themselves. Callers must ask the
/// user to close and reopen the app when this returns false.
Future<bool> closeAppForFreshRestart() async {
  if (Platform.isIOS) return false;
  exit(0);
}
