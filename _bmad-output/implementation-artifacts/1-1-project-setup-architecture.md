# Story 1.1: Project Setup & Architecture

Status: done

## Story

As a Developer,
I want to initialize the Flutter project with Clean Architecture folders and core dependencies
so that the codebase is maintainable and scalable.

## Acceptance Criteria

1. [x] Flutter project created with `flutter create tapix`
2. [x] Folder structure established: `lib/core`, `lib/features`
3. [x] Core dependencies added (flutter_bloc, drift, go_router, etc.) matching `TAPIX_IMPLEMENTATION_CHECKLIST.md`
4. [x] `analysis_options.yaml` configured for strict linting

## Tasks / Subtasks

- [x] Task 1 (AC: 1, 2, 3, 4)
  - [x] Subtask 1.1: Create Flutter project with proper naming
  - [x] Subtask 1.2: Establish Clean Architecture folder structure
  - [x] Subtask 1.3: Configure pubspec.yaml with all required dependencies
  - [x] Subtask 1.4: Setup analysis_options.yaml for strict linting
  - [x] Subtask 1.5: Verify project builds successfully

## Dev Notes

### 🏗️ ARCHITECTURE INTELLIGENCE - CRITICAL REQUIREMENTS

**Clean Architecture Implementation:**
- Follow feature-based folder structure as defined in TAPIX_IMPLEMENTATION_CHECKLIST.md Phase 1
- Each feature must have: data, domain, presentation layers
- Core shared components in `lib/core/`
- Business logic isolated in Bloc pattern

**Core Dependencies (from Implementation Checklist & REBUILD_SPECIFICATION):**
```yaml
dependencies:
  flutter_bloc: ^8.1.4          # State management
  drift: ^2.23.0               # Offline-first database (Chosen over isar for Web WASM support)
  sqlite3_flutter_libs: ^2.3.0  # Native SQLite bindings
  go_router: ^14.0.0           # Navigation
  flex_color_scheme: ^7.3.0    # Modern theming
  easy_localization: ^3.0.7    # Multi-language support
  printing: ^5.11.0           # PDF generation
  pdf: ^3.10.0                 # PDF creation
  share_plus: ^7.2.0           # File sharing
  mobile_scanner: ^4.0.0      # Barcode scanning
  workmanager: ^0.5.2         # Background tasks
  responsive_framework: ^1.1.0 # Responsive design
  fl_chart: ^0.66.0           # Charts
  get_it: ^7.6.0              # Dependency injection
  dio: ^5.4.0                 # HTTP client (Phase 2 prep)
  decimal: ^2.3.0             # Precise money math
  barcode_widget: ^2.0.4      # Barcode generation
  lucide_icons: ^0.0.1        # Modern icons

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.7        # Code generation
  drift_dev: ^2.23.0          # Database codegen
  bloc_test: ^9.1.6           # Bloc testing
```

**Critical Architecture Patterns:**
- **Bloc Pattern**: All state management through flutter_bloc
- **Repository Pattern**: Data access through repositories
- **Service Layer**: Business logic in service classes
- **Dependency Injection**: GetIt for service location

### 📁 PROJECT STRUCTURE NOTES

**Required Folder Structure (from Implementation Checklist):**

```
lib/
├── core/
│   ├── bloc/           # Base Bloc classes
│   ├── database/       # Drift database setup
│   ├── router/         # GoRouter configuration
│   ├── services/       # Shared services
│   ├── theme/          # App theming
│   ├── widgets/        # Reusable widgets
│   ├── utils/          # Utility functions
│   └── localization/   # Translation setup
└── features/
    ├── auth/           # Authentication
    ├── dashboard/      # Main dashboard
    ├── products/       # Product management
    ├── customers/      # Customer management
    ├── suppliers/      # Supplier management
    ├── sales/          # Sales & POS
    ├── purchases/      # Purchase management
    ├── reports/        # Reporting
    ├── settings/       # App settings
    ├── expenses/       # Expense tracking
    ├── employees/      # Employee management
    ├── users/          # User management
    ├── accounting/     # Financial accounting
    ├── notifications/  # Notification system
    └── database/       # Database management
```

**Feature Structure Template:**
```
features/{feature}/
├── data/
│   ├── datasources/    # Remote/local data sources
│   ├── models/         # Data transfer objects
│   └── repositories/   # Repository implementations
├── domain/
│   ├── entities/       # Business entities
│   ├── repositories/   # Repository interfaces
│   └── usecases/       # Business use cases
└── presentation/
    ├── bloc/          # Feature-specific Bloc
    ├── pages/         # Screen widgets
    └── widgets/       # Feature-specific widgets
```

### 🧪 TESTING REQUIREMENTS

**Test Structure:**
```
test/
├── unit/              # Unit tests
├── widget/            # Widget tests
├── integration/       # Integration tests
└── e2e/              # End-to-end tests
```

**Testing Standards:**
- Unit tests for all business logic
- Widget tests for all screens
- Integration tests for critical flows
- Minimum 80% code coverage

### 🔧 DEVELOPMENT CONFIGURATION

**Analysis Options Requirements:**
- Strict linting rules enabled
- Custom linting rules for Clean Architecture
- Documentation requirements
- Naming conventions enforcement

**Environment Configuration:**
- Development, staging, production environments
- Environment-specific configurations
- API endpoint management
- Feature flags support

### 📱 PLATFORM SUPPORT

**Multi-Platform Requirements:**
- Android (primary target)
- iOS (secondary target)
- Windows (desktop support)
- Web (WASM support critical)
- Linux (desktop support)
- macOS (desktop support)

**Platform-Specific Considerations:**
- Web: Drift WASM + IndexedDB (add sqlite3.wasm and drift_worker.dart.js to web/)
- Desktop: Native file system access
- Mobile: Camera permissions for barcode scanning

**Web WASM Setup:**
```bash
# Add to web/index.html before closing body tag
<script src="sqlite3.wasm"></script>
<script src="drift_worker.dart.js"></script>
```

### 🌐 LOCALIZATION SETUP

**Multi-Language Support:**
- English (primary)
- Arabic (RTL support required)
- French (secondary)

**Localization Structure:**
```
assets/translations/
├── app_en.arb         # English
├── app_ar.arb         # Arabic
└── app_fr.arb         # French
```

**RTL Requirements:**
- Arabic text direction support
- RTL layout testing
- Font family configuration for Arabic

### 🎨 THEME SYSTEM

**Theme Requirements:**
- Light theme support
- Dark theme support
- System theme detection
- Theme persistence
- Custom color schemes

**Theme Structure with Exact Colors:**
```
lib/core/theme/
├── app_theme.dart      # Main theme configuration
├── light_theme.dart    # Light theme colors
│   # Primary: Deep Blue (#1565C0)
│   # Secondary: Teal (#00897B)
│   # Background: White (#FFFFFF)
│   # Surface: Light Gray (#F5F5F5)
│   # Error: Red (#D32F2F)
│   # Success: Green (#388E3C)
│   # Warning: Orange (#F57C00)
├── dark_theme.dart     # Dark theme colors
│   # Primary: Light Blue (#64B5F6)
│   # Secondary: Teal (#4DB6AC)
│   # Background: Dark Gray (#121212)
│   # Surface: Dark Gray (#1E1E1E)
│   # Error: Light Red (#EF5350)
│   # Success: Light Green (#81C784)
│   # Warning: Light Orange (#FFB74D)
└── theme_extensions.dart # Custom theme extensions
```

### 🔐 SECURITY CONSIDERATIONS

**Security Requirements:**
- Secure storage for sensitive data
- Input validation and sanitization
- SQL injection prevention (Drift handles this)
- Authentication token management
- API key protection

### 📊 PERFORMANCE REQUIREMENTS

**Performance Targets:**
- App startup time < 3 seconds
- Screen transitions < 500ms
- Database queries < 100ms
- Memory usage optimization

**Optimization Strategies:**
- Lazy loading for large lists
- Image caching and optimization
- Database indexing
- Efficient state management

### 🔄 REAL-TIME UPDATES

**Real-Time Requirements:**
- Drift reactive streams for database changes
- Bloc state management for UI updates
- Automatic UI refresh on data changes
- No manual refresh needed

**Implementation Pattern:**
```dart
// Example reactive stream setup
Stream<List<Product>> get watchAllProducts => 
    (select(products)..orderBy([(t) => t.name]))
    .watch();
```

### 📋 REFERENCES

**Source Documents:**
- [Source: TAPIX_IMPLEMENTATION_CHECKLIST.md#Phase 1] - Complete dependency list and folder structure
- [Source: TAPIX_TECHNICAL_INVENTORY.md#Section 1] - Database schema reference
- [Source: TAPIX_REBUILD_SPECIFICATION.md#Architecture] - Clean Architecture requirements
- [Source: TAPIX_EPICS_AND_STORIES.md#EPIC-01] - Epic context and business requirements

**Technical Standards:**
- Flutter 3.24+ required (aligned with REBUILD_SPECIFICATION)
- Dart 3.5+ required
- Null safety enforced
- Strong typing required

## Dev Agent Record

### Agent Model Used
Cascade (SWE-1.5)

### Debug Log References

- `flutter pub get`
- `flutter analyze`
- `flutter test`

### Completion Notes List

- Initialized work on existing `tapix` Flutter app, verified naming and structure align with story requirements, and marked sprint/story status as in-progress.
- Created Clean Architecture folder skeleton under `lib/core` and `lib/features` with `.gitkeep` placeholders to enforce repo tracking.
- Updated `pubspec.yaml` with required phase-1 dependencies (flutter_bloc, drift, go_router, etc.) plus tooling packages, then tightened `analysis_options.yaml` with strict analyzer language settings.
- Ran `flutter pub get`, `flutter analyze`, and `flutter test` to confirm dependency graph, linting, and baseline tests remain green (validating Subtask 1.5).
- **CODE REVIEW FIXES APPLIED:** Created missing .gitkeep files in all Clean Architecture folders, fixed analysis_options.yaml with strict linting rules, noted dependency version discrepancies in story specs (sqlite3_flutter_libs, lucide_icons).

### File List

- `pubspec.yaml` – Added required production + dev dependencies per Implementation Checklist.
- `analysis_options.yaml` – Enabled strict analyzer language settings.
- `lib/core/{bloc,database,router,services,theme,widgets,utils,localization}/.gitkeep` – Ensures Clean Architecture core scaffolding exists in VCS.
- `lib/features/{auth,dashboard,products,customers,suppliers,sales,purchases,reports,settings,expenses,employees,users,accounting,notifications,database}/(data|domain|presentation)/**/.gitkeep` – Feature-layer skeleton directories tracked for all Phase 1 areas.
- `web/`, `test/`, `README.md`, `assets/` – Unchanged but validated during verification commands.

### Change Log

- `2026-01-23`: Completed Story 1.1 setup—added Clean Architecture folder skeleton, configured dependencies + strict linting, and validated with `flutter pub get`, `flutter analyze`, `flutter test`.

---

## 🎯 CRITICAL SUCCESS FACTORS

1. **Architecture Compliance**: Must follow Clean Architecture principles exactly
2. **Dependency Management**: All required dependencies must be correctly configured
3. **Multi-Platform Support**: Project must build and run on all target platforms
4. **Code Quality**: Strict linting rules must be enforced
5. **Testability**: Structure must support comprehensive testing

## 🚨 COMMON PITFALLS TO AVOID

1. **Incorrect Folder Structure**: Follow the exact structure from Implementation Checklist
2. **Missing Dependencies**: Ensure all dependencies from checklist are included
3. **Platform-Specific Issues**: Test on all platforms, especially Web WASM
4. **Linting Configuration**: Don't skip strict linting setup
5. **Documentation**: Maintain clear documentation for architecture decisions

## 📚 NEXT STEPS AFTER COMPLETION

1. Run `flutter pub get` to install dependencies
2. Verify project builds on all target platforms
3. Run initial tests to ensure setup is correct
4. Proceed to Story 1-2: Database Schema Implementation
