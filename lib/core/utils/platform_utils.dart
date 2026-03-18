import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Platform utilities that safely handle web vs native platform detection.
/// 
/// Use this instead of `dart:io` Platform directly to avoid crashes on web.
class PlatformUtils {
  PlatformUtils._();

  /// Returns true if running on Linux (native, not web)
  static bool get isLinux {
    if (kIsWeb) return false;
    return io.Platform.isLinux;
  }

  /// Returns true if running on Android (native, not web)
  static bool get isAndroid {
    if (kIsWeb) return false;
    return io.Platform.isAndroid;
  }

  /// Returns true if running on iOS (native, not web)
  static bool get isIOS {
    if (kIsWeb) return false;
    return io.Platform.isIOS;
  }

  /// Returns true if running on macOS (native, not web)
  static bool get isMacOS {
    if (kIsWeb) return false;
    return io.Platform.isMacOS;
  }

  /// Returns true if running on Windows (native, not web)
  static bool get isWindows {
    if (kIsWeb) return false;
    return io.Platform.isWindows;
  }

  /// Returns true if running on a desktop platform (Linux, macOS, Windows)
  static bool get isDesktop {
    if (kIsWeb) return false;
    return io.Platform.isLinux || io.Platform.isMacOS || io.Platform.isWindows;
  }

  /// Returns true if running on a mobile platform (Android, iOS)
  static bool get isMobile {
    if (kIsWeb) return false;
    return io.Platform.isAndroid || io.Platform.isIOS;
  }

  /// Returns true if running on web
  static bool get isWeb => kIsWeb;
}
