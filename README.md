# TapBix

**TapBix** is an offline-first Point-of-Sale (POS) and double-entry accounting
application for small businesses, built with Flutter.

- **Package ID:** `com.tapix.pos` (registered on Google Play — do not change)
- **Store display name:** TapBix
- **Platforms:** Android, iOS, Windows, Linux, Web

## Features

- Sales & purchases with strict double-entry journal entries
- Inventory management (standard / batch / batch-expiry costing)
- Customers, suppliers, employees, expenses
- Financial reports (trial balance, ledgers, reconciliation & health)
- Subscriptions via RevenueCat (weekly / monthly / yearly / lifetime)
- Localized in Arabic, English, and French
- Encrypted SQLite database (SQLite3MultipleCiphers) with backup/restore

## Development

```bash
flutter pub get
flutter run
```

## Testing & analysis

```bash
flutter analyze --no-pub
flutter test --no-pub
```

## Release builds

```bash
flutter build appbundle --release   # Google Play (requires android/key.properties)
flutter build ipa --release         # App Store
flutter build windows --release     # Windows
```

The Android release build uses R8 minification with keep-rules in
`android/app/proguard-rules.pro`.
