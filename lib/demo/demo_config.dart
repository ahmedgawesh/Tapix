/// Global demo mode configuration.
///
/// When DEMO_MODE is passed via --dart-define, this is true.
/// All write operations check this flag before persisting data.
class DemoConfig {
  DemoConfig._();

  /// Whether the app is running in demo mode.
  /// Set via --dart-define=DEMO_MODE=true at build time.
  static const bool isDemo = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  /// Allowed domains for the demo build (domain lock).
  static const List<String> allowedDomains = [
    'tapixsolutions.com',
    'www.tapixsolutions.com',
    'localhost',           // local development
    '127.0.0.1',           // local development
  ];

  /// Demo user credentials (auto-login).
  static const String demoUsername = 'demo_manager';
  static const String demoDisplayName = 'Demo Manager';
}
