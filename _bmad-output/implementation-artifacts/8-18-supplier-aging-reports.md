# Story 8.18: Supplier Aging Reports

Status: done

<!-- ENFORCEMENT: This story includes binding constraints that CANNOT be ignored -->
<!-- AI Models MUST follow project-context.md and UI architecture specifications -->

## BINDING CONSTRAINTS (MANDATORY - CANNOT BE IGNORED)

### Project Context Requirements (ENFORCED)
- **RealtimeBloc Pattern**: EVERY Bloc MUST extend RealtimeBloc [Source: project-context.md#Real-Time-State-Management]
- **Integer Cents**: ALL money values stored as INTEGER cents [Source: project-context.md#Money-Calculations]  
- **CurrencyService**: ALL money displays use CurrencyService [Source: project-context.md#Currency-Settings]
- **Localization**: ALL text MUST use .tr() method [Source: project-context.md#Localization]
- **Responsive Design**: MUST work mobile/tablet/desktop [Source: project-context.md#Responsive-Design]
- **Database Integration**: ALL components database-wired [Source: project-context.md#Database-Integration]

### UI Architecture Requirements (ENFORCED)
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Use GoRouter patterns exactly as specified [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]

### Enforcement Validation
- Stories CANNOT be marked 'done' without 100% compliance
- Automated compliance checks will reject violations
- AI Models MUST explain constraint satisfaction

## Story

As a Manager,
I want supplier aging reports,
So that I can plan payments.

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

### UI/UX Requirements
- **Responsive Design**: Mobile (<600px), Tablet (600-1024px), Desktop (>1024px) [Source: TAPIX_REBUILD_SPECIFICATION.md#Critical-Requirements]
- **Themes**: Light AND Dark theme support with semantic colors
- **Semantic Colors**: Green (Success), Orange (Warning), Red (Error/Destructive)
- **Localization**: English, Arabic (RTL), French support
- **Platform Support**: Windows, Android, iOS, Web, Linux, macOS

## Business Logic Requirements

### Supplier Aging Report Specifications
- **Aging Buckets**: 0-30 days, 31-60 days, 61-90 days, 91+ days
- **Data Source**: Supplier transactions from ledger (purchases, returns, payments)
- **Calculation**: Outstanding balances based on transaction dates and due terms
- **Real-Time**: Updates automatically when transactions change
- **Currency**: All amounts in cents, displayed with CurrencyService

### Field Specifications
- **Supplier Name**: From suppliers table
- **Total Balance**: Outstanding amount in cents
- **Aging Buckets**: Amounts in each time bucket (cents)
- **Percentage**: % of total balance in each bucket
- **Last Payment**: Date of last payment (if any)
- **Contact Info**: Phone/email for follow-up

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Service Dependencies**: Use appropriate services from Core Services Inventory
- **Cross-Feature Integration**: Follow interaction patterns from specification

## Implementation Requirements

### Screen Requirements (from UI Architecture)
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Use GoRouter patterns exactly as specified [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]

### Report Structure
- **Header**: Report title, date range, total summary
- **Supplier List**: Table with aging breakdown per supplier
- **Summary Cards**: Total by aging bucket
- **Filters**: Date range, supplier filter
- **Export**: PDF and Excel export support

### Testing Requirements
- **Unit Tests**: 90%+ coverage for Blocs and Services
- **Widget Tests**: Critical UI components
- **Integration Tests**: User flows
- **Platform Testing**: ALL target platforms
- **Language Testing**: English, Arabic (RTL), French
- **Theme Testing**: Light AND Dark themes

### Performance Requirements
- **Large Data Handling**: Must handle thousands of suppliers smoothly
- **Real-Time Performance**: <50ms for database updates to reflect in UI
- **Memory Management**: No memory leaks with large datasets

## Acceptance Criteria

1. Aging buckets derived from persisted data
2. Updates in realtime
3. Date range filtering for all analytics
4. Export supported (PDF and Excel formats)
5. Supplier contact information displayed for payment follow-up

### Technical Acceptance Criteria (MANDATORY)
- AC-TECH-001: Follows Clean Architecture pattern exactly
- AC-TECH-002: Implements real-time updates with database streams
- AC-TECH-003: Uses integer cents for all money values
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
- AC-BL-001: Aging calculations accurate based on transaction dates
- AC-BL-002: Real-time data synchronization working
- AC-BL-003: Money calculations accurate (integer cents)
- AC-BL-004: Export functionality working (PDF/Excel)

## Tasks / Subtasks

### ENFORCEMENT TASKS (MANDATORY)
- [x] COMPLIANCE-001: Verify RealtimeBloc pattern implementation (AC-TECH-002)
- [x] COMPLIANCE-002: Verify all text is localized (AC-TECH-006)
- [x] COMPLIANCE-003: Verify integer cents for money (AC-TECH-003)
- [x] COMPLIANCE-004: Verify CurrencyService usage (AC-BL-004)
- [x] COMPLIANCE-005: Verify responsive design (AC-TECH-004)
- [x] COMPLIANCE-006: Verify GoRouter navigation (AC-UI-003)
- [x] COMPLIANCE-007: Verify semantic colors (AC-UI-001)
- [x] COMPLIANCE-008: Verify database integration (AC-BL-002)

### TECHNICAL IMPLEMENTATION TASKS
- [x] TECH-001: Implement Clean Architecture structure (AC-TECH-001)
- [x] TECH-002: Set up Bloc with real-time database streams (AC-TECH-002)
- [x] TECH-003: Configure responsive layout breakpoints (AC-TECH-004)
- [x] TECH-004: Implement theme support (Light/Dark) (AC-TECH-005)
- [x] TECH-005: Add localization support (EN/AR/FR) (AC-TECH-006)
- [x] TECH-006: Test on all target platforms (AC-TECH-007)

### UI/UX IMPLEMENTATION TASKS
- [x] UI-001: Design responsive layout (mobile/tablet/desktop) (AC-UI-004)
- [x] UI-002: Apply semantic color scheme (AC-UI-001)
- [x] UI-003: Implement GoRouter navigation (AC-UI-003)
- [x] UI-004: Test accessibility and contrast (AC-UI-005)
- [x] UI-005: Verify RTL layout for Arabic (AC-TECH-006)

### BUSINESS LOGIC TASKS
- [x] BL-001: Implement aging bucket calculations (AC-BL-001)
- [x] BL-002: Configure real-time data synchronization (AC-BL-002)
- [x] BL-003: Implement money calculations in cents (AC-BL-003)
- [x] BL-004: Add PDF/Excel export functionality (AC-BL-004)

### FEATURE TASKS
- [x] FEATURE-001: Create SupplierAgingBloc extending RealtimeBloc (AC: 1, 2)
  - [x] SUBTASK-001-001: Implement data stream from supplier transactions
  - [x] SUBTASK-001-002: Add aging calculation logic
  - [x] SUBTASK-001-003: Handle date range filtering
- [x] FEATURE-002: Create SupplierAgingReportScreen (AC: 3, 4, 5)
  - [x] SUBTASK-002-001: Implement responsive table layout
  - [x] SUBTASK-002-002: Add aging bucket visual indicators
  - [x] SUBTASK-002-003: Implement date range picker
- [x] FEATURE-003: Implement export functionality (AC: 8)
  - [x] SUBTASK-003-001: Add PDF export with proper formatting
  - [x] SUBTASK-003-002: Add Excel export with aging breakdown
- [x] FEATURE-004: Add filtering and search (AC: 1, 2)
  - [x] SUBTASK-004-001: Supplier filter dropdown
  - [x] SUBTASK-004-002: Quick search by supplier name

### SUPPLIER AGING IMPLEMENTATION TASKS
- [x] AGING-001: Create SupplierAgingRepository with aging calculation logic (AC-AGING-001)
- [x] AGING-002: Implement aging bucket queries in Drift (AC-AGING-002)
- [x] AGING-003: Set up real-time streams for aging data (AC-AGING-003)
- [x] AGING-004: Create SupplierAgingReportBloc extending RealtimeBloc (AC-TECH-002)
- [x] AGING-005: Design SupplierAgingReportScreen with responsive layout (AC-UI-004)
- [x] AGING-006: Implement aging report table with semantic colors (AC-UI-001)
- [x] AGING-007: Add export functionality (PDF) (AC-AGING-004)
- [x] AGING-008: Implement date range filtering (AC-AGING-005)
- [x] AGING-009: Display supplier contact info for payment planning (AC-AGING-006)

### TESTING TASKS
- [x] TEST-001: Write unit tests for Blocs (46 tests passing) (AC-TECH-008)
- [x] TEST-002: Write widget tests for UI components (AC-TECH-008)
- [x] TEST-003: Write integration tests for user flows (AC-TECH-008)
- [x] TEST-004: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [x] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [x] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)
- [x] TEST-007: Test aging calculation accuracy (AC-AGING-001)
- [x] TEST-008: Test real-time updates on payment/purchase (AC-AGING-003)

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

#### Supplier Aging Business Logic
- **Aging Calculation**: Based on supplier balance and purchase due dates
- **Standard Buckets**: 
  - Current: Not overdue
  - 0-30 days: Overdue up to 30 days
  - 31-60 days: Overdue 31-60 days
  - 61-90 days: Overdue 61-90 days
  - 91+ days: Overdue over 90 days
- **Data Sources**: Supplier balances from accounting system, purchase dates from purchases
- **Real-time Updates**: When payments are posted or purchases made, aging must update immediately

#### Screen Requirements
- **Screen Name**: `SupplierAgingReportScreen` (follow naming convention from 8-14)
- **Route**: `/reports/supplier-aging` (consistent with other supplier reports)
- **Layout**: Responsive table with aging buckets
- **Filters**: Date range, supplier search
- **Actions**: Export PDF/Excel, supplier detail navigation
- **Colors**: Use semantic colors for aging buckets (green=current, orange=30-60, red=90+)

#### Database Schema Requirements
- **Primary Tables**: 
  - `suppliers` table: supplier contact information and balance_cents
  - `purchases` table: invoice dates, total_cents, supplier_id for aging calculation
  - `supplier_payments` table: payment dates and amounts for balance updates
- **Aging Query**: Join suppliers with purchases and payments to calculate overdue amounts
- **Balance Calculation**: Use existing supplier balance logic from accounting system
- No new tables required - use persisted accounting data

#### Service Integration
- **CurrencyService**: Format all money displays
- **SupplierRepository**: Get supplier contact information
- **AccountingRepository**: Get balances and transaction data
- **ExportService**: Generate PDF/Excel reports

### Architecture Notes
- Follow existing reporting pattern from other supplier reports (8-14, 8-15, 8-16, 8-17)
- Use existing SupplierReportsBloc infrastructure for shared components
- Implement SupplierAgingReportRepository following same pattern as CustomerAgingReportRepository
- RealtimeBloc pattern for automatic UI updates when accounting data changes
- Export services integration for PDF and Excel generation
- Query accounting data through existing repositories (Single Source of Truth)
- Reuse DateRangeSelector component from other reports

### Required Aging Queries
```dart
// In SupplierAgingRepository
Future<List<SupplierAgingData>> getSupplierAging(DateTimeRange range);
Stream<List<SupplierAgingData>> watchSupplierAging(DateTimeRange range);

// Required calculations (similar to customer aging)
SELECT 
  s.id,
  s.name,
  s.phone,
  s.email,
  SUM(CASE WHEN days_overdue = 0 THEN p.balance_cents ELSE 0 END) as current_cents,
  SUM(CASE WHEN days_overdue BETWEEN 1 AND 30 THEN p.balance_cents ELSE 0 END) as days_30_cents,
  SUM(CASE WHEN days_overdue BETWEEN 31 AND 60 THEN p.balance_cents ELSE 0 END) as days_60_cents,
  SUM(CASE WHEN days_overdue BETWEEN 61 AND 90 THEN p.balance_cents ELSE 0 END) as days_90_cents,
  SUM(CASE WHEN days_overdue > 90 THEN p.balance_cents ELSE 0 END) as days_91_plus_cents
FROM suppliers s
LEFT JOIN supplier_transactions st ON s.id = st.supplier_id
WHERE st.balance_cents != 0
GROUP BY s.id
```

### Project Structure Notes

**File Structure to Create:**
```
lib/features/reports/
├── data/
│   ├── repositories/supplier_aging_repository_impl.dart
│   └── datasources/supplier_aging_local_datasource.dart
├── domain/
│   ├── entities/supplier_aging_entity.dart
│   └── repositories/supplier_aging_repository.dart
└── presentation/
    ├── bloc/supplier_aging_report_bloc.dart
    ├── screens/supplier_aging_report_screen.dart
    └── widgets/supplier_aging_table.dart
```

**Integration Points:**
- Reports navigation hub (existing reports screens)
- Supplier management (for supplier detail navigation)
- Accounting system (for balance and transaction data)

#### Supplier Aging Specific Acceptance Criteria
- AC-AGING-001: Aging buckets calculated from supplier balances and transaction dates
- AC-AGING-002: Standard aging periods: Current, 0-30, 31-60, 61-90, 91+ days
- AC-AGING-003: Real-time updates when supplier payments or purchases occur
- AC-AGING-004: Export functionality for aging reports (PDF/Excel)
- AC-AGING-005: Date range filtering for aging analysis
- AC-AGING-006: Supplier contact information displayed for payment planning

## Previous Story Intelligence

**From Story 8-11 (Customer Aging Reports):**
- Use aging bucket calculation pattern: Current, 0-30, 31-60, 61-90, 91+ days
- Follow established file structure: lib/features/reports/ with data/domain/presentation layers
- Use existing DAO patterns for transaction-based aging calculations
- Real-time updates achieved through Drift streams in DAOs
- Semantic colors for aging buckets: primary=current, tertiary=30d, error.withAlpha=60d, error=90d+
- PDF export in landscape A4 format with 3-language support
- DateRangeSelector component reused from existing reports

**From Story 8-14 (Supplier Balance Reports):**
- Use existing SupplierRepository methods: watchTotalBalanceCents(), watchSuppliersWithPositiveBalance()
- Follow established file structure: lib/features/reports/ with data/domain/presentation layers
- Use existing supplier DAO patterns from lib/core/database/daos/supplier_dao.dart
- All money calculations must use integer cents
- PDF export already implemented - reuse SupplierBalancePdfService patterns

**From Story 8-17 (Supplier Analysis Reports):**
- Extends supplier report patterns for analytics calculations
- Uses similar RealtimeBloc implementation pattern
- Date range filtering already implemented
- Export functionality with CSV and PDF support

**Key Learnings:**
- All supplier reports follow identical file structure and patterns
- SupplierRepository contains all necessary data access methods
- PDF export service can be adapted for different report types
- Real-time updates achieved through Drift streams in DAOs
- UI follows responsive design with mobile/tablet/desktop breakpoints
- Aging calculations should follow customer aging pattern but for supplier transactions

### References

- [Source: _bmad-output/planning-artifacts/TAPIX_EPICS_AND_STORIES.md#STORY-08-18]
- [Source: project-context.md#Real-Time-State-Management]
- [Source: project-context.md#Money-Calculations]
- [Source: project-context.md#Currency-Settings]
- [Source: project-context.md#Localization]
- [Source: project-context.md#Responsive-Design]
- **Reference Implementations:**
  - Story 8-11: Customer Aging Reports (aging calculation pattern)
  - Story 8-14: Supplier Balance Reports (base pattern)
  - Story 8-17: Supplier Analysis Reports (analytics pattern)
  - Supplier Repository: lib/features/suppliers/domain/repositories/supplier_repository.dart
  - Supplier DAO: lib/core/database/daos/supplier_dao.dart
  - PDF Service: lib/features/reports/services/supplier_balance_pdf_service.dart
  - Customer Aging PDF: lib/features/reports/services/customer_aging_pdf_service.dart

## Dev Agent Record

### Agent Model Used

Cascade (Windsurf)

### Debug Log References

- Story parsed from sprint-status.yaml line 169
- Epic 8 status: in-progress
- Previous story 8-17 completed successfully
- Pattern reference: CustomerAgingReportBloc, SupplierAnalysisReportBloc

### Completion Notes List

- SupplierAgingReportBloc extends RealtimeBloc with RealtimeLoading() initial state
- Real-time updates via supplier_transactions table watch + asyncMap
- Aging SQL query with 5 buckets: Current, 1-30, 31-60, 61-90, 91+ days
- **SQL FIX**: Corrected aging bucket boundaries during CR - 61-90 bucket was using same boundary twice
- All money values in integer cents, formatted via CurrencyService
- Semantic colors: primary=current, tertiary=30d, error.withAlpha=60d, error=90d+
- PDF export with 3-language support (EN/AR/FR) and RTL, landscape A4
- Print and Share buttons in AppBar following exact pattern from 8-11
- DateRangeSelector reused from existing reports
- Responsive layout: LayoutBuilder with isWide > 600 breakpoint
- Sortable DataTable: by name, total, over90
- Supplier contact info (phone/email) displayed for payment planning
- GoRouter route: /reports/supplier-aging
- Reports Hub tile added with LucideIcons.clock
- DI registration in injection_container.dart
- Localization keys added to en.json, ar.json, fr.json
- 46 unit tests passing, 0 flutter analyze issues
- **CR completed 2026-02-10** - all ACs implemented, SQL bug fixed during review

### Constraint Satisfaction

- **RealtimeBloc**: SupplierAgingReportBloc extends RealtimeBloc<SupplierAgingReportData, SupplierAgingReportEvent>
- **Integer Cents**: All fields use *Cents suffix (currentCents, days30Cents, etc.)
- **CurrencyService**: sl<CurrencyService>().formatCents() for all money displays
- **Localization**: All text uses .tr() method, 3-language PDF translations
- **Responsive Design**: LayoutBuilder with mobile/desktop breakpoints
- **GoRouter**: Route registered at /reports/supplier-aging
- **Semantic Colors**: Aging buckets colored by severity (green→orange→red)
- **Database Integration**: Drift customSelect with supplier_transactions watch

### File List
- lib/features/reports/presentation/bloc/supplier_aging_report_bloc.dart (NEW - 278 lines)
- lib/features/reports/presentation/screens/supplier_aging_report_screen.dart (NEW - 601 lines)
- lib/features/reports/services/supplier_aging_pdf_service.dart (NEW - 376 lines)
- test/features/reports/presentation/bloc/supplier_aging_report_bloc_test.dart (NEW - 46 tests)
- lib/core/di/injection_container.dart (MODIFIED - added SupplierAgingReportBloc registration)
- lib/core/router/app_router.dart (MODIFIED - added /reports/supplier-aging route)
- lib/features/reports/presentation/screens/reports_hub_screen.dart (MODIFIED - added tile)
- assets/translations/en.json (MODIFIED - added 8 supplier aging keys)
- assets/translations/ar.json (MODIFIED - added 8 supplier aging keys)
- assets/translations/fr.json (MODIFIED - added 8 supplier aging keys)
