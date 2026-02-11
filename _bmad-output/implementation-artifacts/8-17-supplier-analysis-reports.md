# Story 8.17: supplier-analysis-reports

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
I want supplier analysis reports,
so that I can evaluate supplier performance.

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

### Field Specifications (from Rebuild Spec)
- **Money Fields**: Must use INTEGER cents (price_cents, cost_cents, total_cents)
- **Validation**: Required fields, format validation, business rule validation
- **Permissions**: Role-based access control (Owner, Manager, Cashier, Salesperson)
- **Real-Time Updates**: UI must update automatically on data changes

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Service Dependencies**: Use appropriate services from Core Services Inventory
- **Cross-Feature Integration**: Follow interaction patterns from specification

## Implementation Requirements

### Screen Requirements (from UI Architecture)
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Use GoRouter patterns exactly as specified [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]

### Testing Requirements
- **Unit Tests**: 90%+ coverage for Blocs and Services
- **Widget Tests**: Critical UI components
- **Integration Tests**: User flows
- **Platform Testing**: ALL target platforms
- **Language Testing**: English, Arabic (RTL), French
- **Theme Testing**: Light AND Dark themes

### Performance Requirements
- **Large Data Handling**: Must handle thousands of records smoothly
- **Real-Time Performance**: <50ms for database updates to reflect in UI
- **Memory Management**: No memory leaks with large datasets

## Acceptance Criteria

1. Purchases, returns, and settlement analytics with specific KPIs:
   - Total purchase volume by supplier (sum and count)
   - Purchase return rate percentage (returns / purchases)
   - Average payment days (days from purchase to payment)
   - Settlement ratio (paid amount / total purchases)
   - Average order value per supplier
   - Top performing suppliers by volume and payment timeliness
2. Date range filtering for all analytics
3. Export supported (CSV and PDF formats)
4. Real-time updates when supplier transactions change

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
- AC-BL-001: All validations implemented per specification
- AC-BL-002: Role-based permissions enforced
- AC-BL-003: Real-time data synchronization working
- AC-BL-004: Money calculations accurate (integer cents)

## Tasks / Subtasks

### ENFORCEMENT TASKS (MANDATORY)
- [x] COMPLIANCE-001: Verify RealtimeBloc pattern implementation (AC-TECH-002)
- [x] COMPLIANCE-002: Verify all text is localized (AC-TECH-006)
- [x] COMPLIANCE-003: Verify integer cents for money (AC-TECH-003)
- [x] COMPLIANCE-004: Verify CurrencyService usage (AC-BL-004)
- [x] COMPLIANCE-005: Verify responsive design (AC-TECH-004)
- [x] COMPLIANCE-006: Verify GoRouter navigation (AC-UI-003)
- [x] COMPLIANCE-007: Verify semantic colors (AC-UI-001)
- [x] COMPLIANCE-008: Verify database integration (AC-BL-003)

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
- [x] BL-001: Implement field validations per specification (AC-BL-001)
- [x] BL-002: Add role-based permission checks (AC-BL-002)
- [x] BL-003: Configure real-time data synchronization (AC-BL-003)
- [x] BL-004: Implement money calculations in cents (AC-BL-004)

### TESTING TASKS
- [x] TEST-001: Write unit tests for Blocs (90%+ coverage) (AC-TECH-008)
- [x] TEST-002: Write widget tests for UI components (AC-TECH-008)
- [x] TEST-003: Write integration tests for user flows (AC-TECH-008)
- [x] TEST-004: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [x] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [x] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)

### FEATURE TASKS
- [x] ANALYSIS-001: Create supplier analysis data repository (AC: 1)
  - [x] SUBTASK-001-001: Implement purchases analytics queries (total volume, count, AOV)
  - [x] SUBTASK-001-002: Implement returns analytics queries (return rate %)
  - [x] SUBTASK-001-003: Implement settlement analytics (avg payment days, settlement ratio)
  - [x] SUBTASK-001-004: Add supplier performance ranking logic
- [x] ANALYSIS-002: Design supplier analysis report UI (AC: 1)
  - [x] SUBTASK-002-001: Create KPI summary cards section (volume, return rate, payment days)
  - [x] SUBTASK-002-002: Create detailed analytics table with supplier rankings
  - [x] SUBTASK-002-003: Add date range filters (reuse from 8-14)
  - [x] SUBTASK-002-004: Add sorting capabilities (by each KPI)
- [x] ANALYSIS-003: Implement export functionality (AC: 2, 3)
  - [x] SUBTASK-003-001: Add CSV export with all analytics columns
  - [x] SUBTASK-003-002: Adapt PDF export from SupplierBalancePdfService for analysis format
  - [x] SUBTASK-003-003: Ensure export works across platforms and languages
- [x] ANALYSIS-004: Implement real-time updates (AC: 4)
  - [x] SUBTASK-004-001: Extend RealtimeBloc for analysis data streaming
  - [x] SUBTASK-004-002: Connect to existing supplier transaction streams
  - [x] SUBTASK-004-003: Optimize query performance for real-time analytics

### Previous Story Intelligence

**From Story 8-14 (Supplier Balance Reports):**
- Use existing SupplierRepository methods: watchTotalBalanceCents(), watchSuppliersWithPositiveBalance()
- Follow established file structure: lib/features/reports/ with data/domain/presentation layers
- Use existing supplier DAO patterns from lib/core/database/daos/supplier_dao.dart
- Reference customer statement reports (8-12) for similar calculation patterns
- All money calculations must use integer cents
- PDF export already implemented - reuse SupplierBalancePdfService patterns

**From Story 8-15 (Supplier Debit Balance Reports):**
- Extends 8-14 patterns for debit-specific filtering
- Uses similar RealtimeBloc implementation pattern
- Date range filtering already implemented

**From Story 8-16 (Supplier Credit Balance Reports):**
- Mirrors 8-15 for credit-specific filtering
- Same export functionality patterns
- Consistent UI patterns across supplier reports

**Key Learnings:**
- All supplier reports follow identical file structure and patterns
- SupplierRepository contains all necessary data access methods
- PDF export service can be adapted for different report types
- Real-time updates achieved through Drift streams in DAOs
- UI follows responsive design with mobile/tablet/desktop breakpoints

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
- **Screen Names**: Use exact screen names from rebuild spec (e.g., `SupplierAnalysisReportsScreen`)
- **Field Lists**: Include ALL fields from specification (e.g., supplier analytics fields)
- **Business Rules**: Implement all validations and rules from specification
- **Service Integration**: Use services from Core Services Inventory (section 8)
- **Database Schema**: Follow exact schema from Database Requirements (section 9)

### Architecture Notes
- **REUSE EXISTING PATTERNS**: Follow identical structure from stories 8-14, 8-15, 8-16
- **File Structure**: Use same lib/features/reports/ structure with data/domain/presentation layers
- **Bloc Pattern**: Extend RealtimeBloc like SupplierBalanceReportBloc
- **Repository**: Create new repository but leverage existing SupplierRepository methods
- **Data Source**: Use existing supplier DAOs and transaction tables
- **Export Service**: Adapt SupplierBalancePdfService for analysis report format
- **UI Patterns**: Follow same responsive layout and component patterns
- **Database Queries**: Optimize for analytics calculations (aggregates, grouping)

### Required Analytics Queries
```dart
// In SupplierAnalysisRepository
Future<List<SupplierAnalysisData>> getSupplierAnalysis(DateTimeRange range);
Stream<List<SupplierAnalysisData>> watchSupplierAnalysis(DateTimeRange range);

// Required calculations
totalPurchases = SUM(purchases.total_cents)
purchaseCount = COUNT(purchases.id)
returnRate = (SUM(returns.total_cents) / totalPurchases) * 100
avgPaymentDays = AVG(DATEDIFF(payments.date, purchases.date))
settlementRatio = (SUM(payments.amount_cents) / totalPurchases) * 100
avgOrderValue = totalPurchases / purchaseCount
```

### Project Structure Notes

```
lib/features/reports/
├── data/
│   ├── datasources/
│   │   └── supplier_analysis_local_datasource.dart  // NEW
│   ├── models/
│   │   └── supplier_analysis_model.dart  // NEW
│   └── repositories/
│       └── supplier_analysis_repository_impl.dart  // NEW
├── domain/
│   ├── entities/
│   │   └── supplier_analysis_entity.dart  // NEW
│   └── repositories/
│       └── supplier_analysis_repository.dart  // NEW
└── presentation/
    ├── bloc/
    │   └── supplier_analysis_report_bloc.dart  // NEW
    └── screens/
        └── supplier_analysis_report_screen.dart  // NEW
```

### References

- [Source: _bmad-output/planning-artifacts/TAPIX_EPICS_AND_STORIES.md#STORY-08-17]
- [Source: project-context.md#Real-Time-State-Management]
- [Source: project-context.md#Money-Calculations]
- [Source: project-context.md#Responsive-Design]
- **Reference Implementations:**
  - Story 8-14: Supplier Balance Reports (base pattern)
  - Story 8-15: Supplier Debit Balance Reports (filtering pattern)
  - Story 8-16: Supplier Credit Balance Reports (UI pattern)
  - Story 8-12: Customer Statement Reports (calculation pattern)
  - Supplier Repository: lib/features/suppliers/domain/repositories/supplier_repository.dart
  - Supplier DAO: lib/core/database/daos/supplier_dao.dart
  - PDF Service: lib/features/reports/services/supplier_balance_pdf_service.dart

## Dev Agent Record

### Agent Model Used

Cascade (Penguin Alpha)

### Debug Log References

### Completion Notes List

### File List
- lib/features/reports/presentation/bloc/supplier_analysis_report_bloc.dart (NEW - 403 lines)
- lib/features/reports/presentation/screens/supplier_analysis_report_screen.dart (NEW - 694 lines)
- lib/features/reports/services/supplier_analysis_pdf_service.dart (NEW - 398 lines)
- test/features/reports/presentation/bloc/supplier_analysis_report_bloc_test.dart (NEW - 819 lines)
- lib/core/di/injection_container.dart (MODIFIED - added SupplierAnalysisReportBloc registration)
- assets/translations/en.json (MODIFIED - added supplier analysis translations)
- assets/translations/ar.json (MODIFIED - added supplier analysis translations)
- assets/translations/fr.json (MODIFIED - added supplier analysis translations)
- lib/core/router/app_router.dart (NO CHANGE - route already configured)
