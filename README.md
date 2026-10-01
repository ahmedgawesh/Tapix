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

Current documentation: [index](docs/index.md), [branch/warehouse roadmap](docs/business/REMAINING_ROADMAP_AR.md), and [setup guide](docs/business/BRANCH_WAREHOUSE_CUSTOMER_GUIDE_AR.md).
The local branch rollout has been exercised on three physical devices. The
[station 7 readiness review](docs/business/STATION_7_ENTRY_REVIEW_AR.md) records
its automated verification and the distinction between starting cloud development
and approving an online production release.

### Repository layout

| Path | Contents |
| --- | --- |
| `lib/core/` | Database, accounting, pricing, network, and synchronization services |
| `lib/features/` | Feature repositories, application logic, and Flutter screens |
| `test/` | Unit, widget, integration, and schema migration tests |
| `drift_schemas/` | Versioned database schema snapshots for migration verification |
| `assets/translations/` | Arabic, English, and French translations |
| `docs/` | Current contracts, guides, dated verification, and roadmap |
| `tool/` | Development utilities, including synthetic acceptance data generation |
| `legal/`, `marketing/` | Historical legal and publication material requiring release review |

Device databases, backups, signing material, and build output stay outside Git.
The `_bmad` directories and root `MOC` documents are historical development/design
material; they do not override the current roadmap.

```bash
flutter pub get --enforce-lockfile
flutter run
```

## Testing & analysis

```bash
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub tool/generate_comprehensive_acceptance_database_test.dart
```

CI uses Flutter **3.47.2** and the committed dependency lockfile. The synthetic
acceptance test uses a temporary database and refuses to overwrite existing
files. To retain a generated dataset, set `TAPIX_ACCEPTANCE_DB_PATH` to a new
path under the ignored `backups/` directory before running that test.

## Release builds

```bash
flutter build appbundle --release   # Google Play (requires android/key.properties)
flutter build ipa --release         # App Store
flutter build windows --release     # Windows
```

The Android release build uses R8 minification with keep-rules in
`android/app/proguard-rules.pro`.
