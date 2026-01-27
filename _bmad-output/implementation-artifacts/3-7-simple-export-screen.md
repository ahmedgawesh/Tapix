# Story 3.7: simple-export-screen

Status: in-progress

<!-- ENFORCEMENT: This story includes binding constraints that CANNOT be ignored -->
<!-- AI Models MUST follow project-context.md and UI architecture specifications -->

## BINDING CONSTRAINTS (MANDATORY - CANNOT BE IGNORED)

### Core Requirements (ENFORCED)
- **RealtimeBloc Pattern**: EVERY Bloc MUST extend RealtimeBloc [Source: project-context.md#Real-Time-State-Management]
- **Integer Cents**: ALL money values stored as INTEGER cents [Source: project-context.md#Money-Calculations]  
- **CurrencyService**: ALL money displays use CurrencyService (EXCEPT export - use raw cents) [Source: project-context.md#Currency-Settings]
- **Localization**: ALL text MUST use .tr() method [Source: project-context.md#Localization]
- **Responsive Design**: MUST work mobile/tablet/desktop [Source: project-context.md#Responsive-Design]
- **Database Integration**: ALL components database-wired [Source: project-context.md#Database-Integration]
- **Clean Architecture**: Follow lib/core and lib/features structure [Source: TAPIX_REBUILD_SPECIFICATION.md#Technical-Architecture]
- **Navigation**: Use GoRouter with /products/export route [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]

### Enforcement Validation
- Stories CANNOT be marked 'done' without 100% compliance
- Automated compliance checks will reject violations
- AI Models MUST explain constraint satisfaction

## Story

As a Manager,
I want to export products to CSV/Excel files,
so that I can share my inventory data, create backups, and perform bulk analysis in external tools while maintaining accurate financial data in proper formats.

## Technical Requirements (from TAPIX_REBUILD_SPECIFICATION.md)

### Architecture Requirements
- **Clean Architecture**: Follow lib/core and lib/features structure [Source: TAPIX_REBUILD_SPECIFICATION.md#Technical-Architecture]
- **State Management**: Use Bloc/Cubit with streams for real-time data [Source: TAPIX_REBUILD_SPECIFICATION.md#State-Management]
- **Real-Time Updates**: Database Change → Stream → Bloc → UI Update pattern [Source: TAPIX_REBUILD_SPECIFICATION.md#Real-Time-Update-Architecture]
- **Money Calculations**: ALL money values stored as INTEGER cents [Source: TAPIX_REBUILD_SPECIFICATION.md#Money-Calculation-Rules]

### Technology Stack Requirements
- **Flutter**: 3.24+ with null-safety support
- **Database**: Drift (SQLite) with Web WASM support
- **State Management**: flutter_bloc 8.1.4+
- **Router**: go_router 14.0.0+
- **Theme**: flex_color_scheme 7.3.0+
- **Localization**: easy_localization 3.0.7+
- **Money**: decimal 2.3.0+ for precise calculations
- **File Generation**: spreadsheet: ^3.0.1 (for Excel), csv: ^6.0.0 (for CSV files)
- **File Saver**: file_saver: ^0.2.4 or share_plus: ^7.2.2 for file downloads

### UI/UX Requirements
- **Responsive Design**: Mobile (<600px), Tablet (600-1024px), Desktop (>1024px) [Source: TAPIX_REBUILD_SPECIFICATION.md#Critical-Requirements]
- **Themes**: Light AND Dark theme support with semantic colors
- **Semantic Colors**: Green (Success), Orange (Warning), Red (Error/Destructive)
- **Localization**: English, Arabic (RTL), French support
- **Platform Support**: Windows, Android, iOS, Web, Linux, macOS

## Business Logic Requirements

### Export Functionality Specifications
- **Format Support**: CSV and Excel (.xlsx) export formats
- **Data Fields**: All product fields including variants, prices in cents, stock levels
- **Currency Formatting**: Price fields in cents (integer) for data integrity
- **Date Formatting**: ISO 8601 format for dates (created_at, updated_at)
- **Real-Time Data**: Export current database state (no caching)
- **Large Dataset Support**: Handle thousands of products without memory issues

### Field Specifications (from Rebuild Spec)
- **Product Fields**: name, sku, barcode, description, cost_cents, price_cents, tax_percent, stock_quantity, min_stock, category_id, supplier_id, is_active, created_at, updated_at
- **Money Fields**: Export as INTEGER cents (cost_cents, price_cents) - NOT formatted currency
- **Validation**: Ensure all required fields are included
- **Permissions**: Export available to Owner and Manager roles only

### Integration Requirements
- **Database Integration**: Query products directly from database (no standalone)
- **Service Dependencies**: Create and use CsvSaver service (to be implemented in this story) [Source: TAPIX_REBUILD_SPECIFICATION.md#Core-Services-Inventory]
- **File System Integration**: Save to Downloads folder or share via platform

## Implementation Requirements

### Screen Requirements (from UI Architecture)
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Access from ProductsMainScreen via export button [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]

### Export Screen Features
- **Format Selection**: Toggle between CSV and Excel formats
- **Progress Indicator**: Show export progress for large datasets
- **Preview**: Show first 10 rows as preview before export
- **Field Selection**: Optional field selection (default all fields)
- **Filter Options**: Export filtered results (category, supplier, active status)
- **Share Options**: Save to file, share via email/apps, print

### Testing Requirements
- **Unit Tests**: 90%+ coverage for ExportBloc and ExportService
- **Widget Tests**: Export screen UI components
- **Integration Tests**: Complete export flow
- **Platform Testing**: ALL target platforms
- **Language Testing**: English, Arabic (RTL), French
- **Theme Testing**: Light AND Dark themes

### Performance Requirements
- **Large Data Handling**: Export 10,000+ products smoothly
- **Memory Management**: Stream export to avoid memory overload
- **Export Speed**: <5 seconds for 1,000 products, <30 seconds for 10,000 products
- **Memory Efficiency**: Use streaming approach for datasets >1000 products

## Implementation Structure

### File Structure (Clean Architecture)
**Domain Layer:**
- lib/features/products/domain/entities/export_result.dart
- lib/features/products/domain/entities/export_config.dart
- lib/features/products/domain/usecases/export_products.dart
- lib/features/products/domain/usecases/generate_export_file.dart

**Services Layer:**
- lib/features/products/services/export_service.dart (NEW - CsvSaver implementation)
- lib/features/products/services/csv_export_service.dart
- lib/features/products/services/excel_export_service.dart

**Presentation Layer:**
- lib/features/products/presentation/bloc/export_bloc.dart
- lib/features/products/presentation/bloc/export_event.dart
- lib/features/products/presentation/bloc/export_state.dart
- lib/features/products/presentation/screens/simple_export_screen.dart
- lib/features/products/presentation/widgets/export_format_selector.dart
- lib/features/products/presentation/widgets/export_preview_widget.dart
- lib/features/products/presentation/widgets/export_progress_widget.dart

**Core Infrastructure:**
- lib/core/di/injection_container.dart (add export services registration)
- lib/core/router/app_router.dart (add /products/export route)

**Localization:**
- assets/translations/en.json (add export_products section)
- assets/translations/ar.json (add export_products section with RTL)
- assets/translations/fr.json (add export_products section)

**Tests:**
- test/features/products/services/export_service_test.dart
- test/features/products/presentation/bloc/export_bloc_test.dart

**Configuration:**
- pubspec.yaml (add spreadsheet, file_saver dependencies)

### Dependency Injection Registration
```dart
// In lib/core/di/injection_container.dart
sl.registerLazySingleton<ExportService>(() => ExportServiceImpl(sl()));
sl.registerFactory<ExportBloc>(() => ExportBloc(sl()));
```

### Localization Keys Required
```json
{
  "export_products": {
    "title": "Export Products",
    "format_selection": "Export Format",
    "csv_format": "CSV",
    "excel_format": "Excel",
    "select_fields": "Select Fields",
    "preview": "Preview",
    "export_button": "Export",
    "progress": "Exporting...",
    "success": "Export completed successfully",
    "error": "Export failed"
  }
}
```

## Acceptance Criteria

1. Export products to CSV format with all fields included
2. Export products to Excel format with proper formatting
3. Money values exported as integer cents (not formatted currency)
4. Export respects current filters (category, supplier, active status)
5. Progress indicator shows during export process
6. Exported files are properly saved/shared
7. Export available only to authorized roles (Owner, Manager)
8. Export works on all platforms (mobile, desktop, web)
9. Export supports all languages (EN/AR/FR) with proper column headers
10. Export handles large datasets without memory issues

### Technical Acceptance Criteria (MANDATORY)
- AC-TECH-001: Follows Clean Architecture pattern exactly
- AC-TECH-002: Implements real-time updates with database streams
- AC-TECH-003: Uses integer cents for all money values in export
- AC-TECH-004: Responsive design works on all screen sizes
- AC-TECH-005: Supports Light AND Dark themes
- AC-TECH-006: Fully localized (EN/AR/FR) with RTL support
- AC-TECH-007: Works on ALL target platforms
- AC-TECH-008: Achieves 90%+ test coverage

### UI/UX Acceptance Criteria (MANDATORY)
- AC-UI-001: Uses semantic colors (success/warning/error)
- AC-UI-002: Follows component architecture pattern
- AC-UI-003: Navigation uses GoRouter as specified
- AC-UI-004: No overflow on any screen size
- AC-UI-005: Accessible design with proper contrast

### Business Logic Acceptance Criteria (MANDATORY)
- AC-BL-001: All export fields implemented per specification
- AC-BL-002: Role-based permissions enforced for export
- AC-BL-003: Real-time data exported (no cached data)
- AC-BL-004: Money values accurate as integer cents

## Tasks / Subtasks

### ENFORCEMENT TASKS (MANDATORY)
- [ ] COMPLIANCE-001: Verify RealtimeBloc pattern implementation (AC-TECH-002)
- [ ] COMPLIANCE-002: Verify all text is localized (AC-TECH-006)
- [ ] COMPLIANCE-003: Verify integer cents for money in export (AC-TECH-003)
- [ ] COMPLIANCE-004: Verify CurrencyService not used in export (raw cents) (AC-BL-004)
- [ ] COMPLIANCE-005: Verify responsive design (AC-TECH-004)
- [ ] COMPLIANCE-006: Verify GoRouter navigation (AC-UI-003)
- [ ] COMPLIANCE-007: Verify semantic colors (AC-UI-001)
- [ ] COMPLIANCE-008: Verify database integration (AC-BL-003)

### TECHNICAL IMPLEMENTATION TASKS
- [ ] TECH-001: Implement Clean Architecture structure (AC-TECH-001)
- [ ] TECH-002: Set up ExportBloc with real-time database streams (AC-TECH-002)
- [ ] TECH-003: Configure responsive layout breakpoints (AC-TECH-004)
- [ ] TECH-004: Implement theme support (Light/Dark) (AC-TECH-005)
- [ ] TECH-005: Add localization support (EN/AR/FR) (AC-TECH-006)
- [ ] TECH-006: Test on all target platforms (AC-TECH-007)

### UI/UX IMPLEMENTATION TASKS
- [ ] UI-001: Design responsive export screen (mobile/tablet/desktop) (AC-UI-004)
- [ ] UI-002: Apply semantic color scheme (AC-UI-001)
- [ ] UI-003: Implement GoRouter navigation from ProductsMainScreen (AC-UI-003)
- [ ] UI-004: Test accessibility and contrast (AC-UI-005)
- [ ] UI-005: Verify RTL layout for Arabic (AC-TECH-006)

### BUSINESS LOGIC TASKS
- [ ] BL-001: Implement CSV export with all product fields (AC-BL-001)
- [ ] BL-002: Implement Excel export with proper formatting (AC-BL-001)
- [ ] BL-003: Add role-based permission checks (Owner/Manager only) (AC-BL-002)
- [ ] BL-004: Export money values as integer cents (AC-BL-004)
- [ ] BL-005: Add export progress indicator (AC-BL-003)
- [ ] BL-006: Implement field selection and filtering options (AC-BL-001)

### TESTING TASKS
- [ ] TEST-001: Write unit tests for ExportBloc (90%+ coverage) (AC-TECH-008)
- [ ] TEST-002: Write widget tests for ExportScreen UI (AC-TECH-008)
- [ ] TEST-003: Write integration tests for export flow (AC-TECH-008)
- [ ] TEST-004: Test export on all platforms (mobile, desktop, web) (AC-TECH-007)
- [ ] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [ ] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)
- [ ] TEST-007: Test large dataset export (10,000+ products) (AC-BL-004)

### FEATURE TASKS
- [ ] EXPORT-001: Create ExportService with CSV/Excel support (AC: 1, 2)
  - [ ] Implement CsvSaver as part of ExportService (NEW service)
  - [ ] Use spreadsheet: ^3.0.1 for Excel generation
  - [ ] Use csv: ^6.0.0 for CSV generation
  - [ ] Stream data to avoid memory issues (datasets >1000)
  - [ ] Target: <5s for 1k products, <30s for 10k products
- [ ] EXPORT-002: Create ExportBloc extending RealtimeBloc (AC: 3, 5, 8)
  - [ ] Handle export progress states (loading, progress, success, error)
  - [ ] Manage export format selection (CSV/Excel)
  - [ ] Handle filter parameters (category, supplier, active)
  - [ ] Register in DI container
- [ ] EXPORT-003: Create SimpleExportScreen with responsive design (AC: 4, 6, 7)
  - [ ] Follow Scaffold + BlocBuilder pattern
  - [ ] Format selection toggle (CSV/Excel)
  - [ ] Field selection checkboxes (default all selected)
  - [ ] Filter options (category, supplier, active status)
  - [ ] Preview table (first 10 rows)
  - [ ] Export button with progress indicator
  - [ ] Support RTL for Arabic
- [ ] EXPORT-004: Add navigation from ProductsMainScreen (AC: 9)
  - [ ] Add export FAB or menu item to ProductsMainScreen
  - [ ] Configure GoRouter route: /products/export
  - [ ] Update app_router.dart
- [ ] EXPORT-005: Implement file save/share functionality (AC: 6)
  - [ ] Use file_saver: ^0.2.4 for desktop/mobile downloads
  - [ ] Use share_plus: ^7.2.2 for mobile sharing
  - [ ] Handle platform-specific file dialogs
  - [ ] Save to Downloads folder by default
- [ ] EXPORT-006: Add localization support (AC: 6)
  - [ ] Add export_products keys to en.json, ar.json, fr.json
  - [ ] Ensure all UI text uses .tr() method
  - [ ] Test RTL layout for Arabic

## Dev Notes

### ENFORCEMENT NOTES (MANDATORY)
- **CRITICAL**: AI Models MUST load TAPIX_REBUILD_SPECIFICATION.md and treat as BINDING LAW
- **CRITICAL**: AI Models MUST load UI architecture specification and follow exactly
- **CRITICAL**: Every implementation MUST explain how constraints are satisfied
- **FAILURE TO FOLLOW BINDING CONSTRAINTS IS NOT ACCEPTABLE**

### Specification References (MANDATORY)
- **Primary Specification**: TAPIX_REBUILD_SPECIFICATION.md (1096 lines of detailed requirements)
- **UI Architecture**: 2-1-ui-architecture-specification.md (screen placement and navigation)
- **Enforcement Framework**: 2-2-development-enforcement-framework.md (binding constraints)
- **Project Context**: project-context.md (implementation patterns)

### Detailed Implementation Guidance
- **Screen Name**: Use exact screen name from rebuild spec: `SimpleExportScreen`
- **Service Integration**: Use CsvSaver service from Core Services Inventory (section 8.3)
- **Database Schema**: Follow products table schema from Database Requirements (section 9)
- **Export Fields**: Include ALL product fields from specification (section 5.3)
- **Money Format**: Export as INTEGER cents, NOT formatted currency
- **File Formats**: Support both CSV and Excel (.xlsx) as specified

### Architecture Notes
- **Bloc Pattern**: ExportBloc must extend RealtimeBloc for real-time data
- **Service Layer**: ExportService handles file generation logic
- **Repository Layer**: Use ProductRepository to query current data
- **File Handling**: Use platform-appropriate file save/share methods
- **Memory Management**: Stream export for large datasets

### Project Structure Notes

```
lib/features/products/
├── data/
│   ├── repositories/
│   │   └── product_repository.dart
│   └── services/
│       └── export_service.dart
├── domain/
│   ├── entities/
│   │   └── product.dart
│   └── usecases/
│       └── export_products.dart
└── presentation/
    ├── bloc/
    │   └── export_bloc.dart
    └── screens/
        └── simple_export_screen.dart
```

### Previous Story Intelligence
- **Story 3-6 (Import)**: Established file handling patterns with spreadsheet/csv packages
- **Story 3-5 (Edit Prices)**: Money handling patterns with integer cents
- **Story 3-4 (Bulk Form)**: Large dataset handling patterns
- **Common Patterns**: RealtimeBloc, responsive design, localization

### References

- [Source: TAPIX_REBUILD_SPECIFICATION.md#Products-Module]
- [Source: TAPIX_REBUILD_SPECIFICATION.md#Core-Services-Inventory]
- [Source: project-context.md#Money-Calculations]
- [Source: project-context.md#Real-Time-State-Management]

## Dev Agent Record

### Agent Model Used

Cascade (SWE-1.5)

### Debug Log References

### Completion Notes List

- Refactored ExportBloc to comply with RealtimeBloc pattern
- Wired export flows to database-backed streams via ProductRepository/Drift DAO
- Enforced Owner/Manager access for /products/export (route permissions + UI gating)
- Updated export UI to use RealtimeState<ExportUiData> and SharePlus.instance.share with in-memory XFile (web compatible)
- Updated unit tests for ExportBloc and ExportService; full test suite passing

### File List

- /home/ahmed/AhmedF/tapix projects/tapix/_bmad-output/implementation-artifacts/3-7-simple-export-screen.md
- /home/ahmed/AhmedF/tapix projects/tapix/lib/core/database/daos/product_dao.dart
- /home/ahmed/AhmedF/tapix projects/tapix/lib/core/router/route_permissions.dart
- /home/ahmed/AhmedF/tapix projects/tapix/lib/features/products/data/datasources/product_local_datasource.dart
- /home/ahmed/AhmedF/tapix projects/tapix/lib/features/products/data/repositories/product_repository_impl.dart
- /home/ahmed/AhmedF/tapix projects/tapix/lib/features/products/domain/repositories/product_repository.dart
- /home/ahmed/AhmedF/tapix projects/tapix/lib/features/products/presentation/bloc/export_bloc.dart
- /home/ahmed/AhmedF/tapix projects/tapix/lib/features/products/presentation/bloc/export_event.dart
- /home/ahmed/AhmedF/tapix projects/tapix/lib/features/products/presentation/bloc/export_state.dart
- /home/ahmed/AhmedF/tapix projects/tapix/lib/features/products/presentation/screens/simple_export_screen.dart
- /home/ahmed/AhmedF/tapix projects/tapix/lib/features/products/services/export_service.dart
- /home/ahmed/AhmedF/tapix projects/tapix/test/features/products/presentation/bloc/export_bloc_test.dart
- /home/ahmed/AhmedF/tapix projects/tapix/test/features/products/presentation/screens/simple_export_screen_test.dart
- /home/ahmed/AhmedF/tapix projects/tapix/test/features/products/services/export_service_test.dart
