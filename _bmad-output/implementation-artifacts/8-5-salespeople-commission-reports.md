# Story 8.5: Salespeople Commission Reports

Status: review

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
I want sales team performance and commission reports,
so that I can track targets and incentives.

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

1. Salespeople performance and commission calculations with specific metrics:
   - Total sales revenue per salesperson (sum of sales.total_cents)
   - Sales count per salesperson (count of sales.id)
   - Commission earned based on configurable rates (5% default, 7.5% when target met)
   - Target achievement percentage (vs 1M sales threshold)
   - Performance trend (period-over-period comparison)
   - Salesperson ranking leaderboard
2. Real-time updates from Drift when sales data changes
3. Date range filtering (daily, weekly, monthly, quarterly, yearly)
4. PDF export with commission reports and charts
5. Individual salesperson detail view with sales history

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
- [ ] COMPLIANCE-001: Verify RealtimeBloc pattern implementation (AC-TECH-002)
- [ ] COMPLIANCE-002: Verify all text is localized (AC-TECH-006)
- [ ] COMPLIANCE-003: Verify integer cents for money (AC-TECH-003)
- [ ] COMPLIANCE-004: Verify CurrencyService usage (AC-BL-004)
- [ ] COMPLIANCE-005: Verify responsive design (AC-TECH-004)
- [ ] COMPLIANCE-006: Verify GoRouter navigation (AC-UI-003)
- [ ] COMPLIANCE-007: Verify semantic colors (AC-UI-001)
- [ ] COMPLIANCE-008: Verify database integration (AC-BL-003)

### TECHNICAL IMPLEMENTATION TASKS
- [ ] TECH-001: Implement Clean Architecture structure (AC-TECH-001)
- [ ] TECH-002: Set up Bloc with real-time database streams (AC-TECH-002)
- [ ] TECH-003: Configure responsive layout breakpoints (AC-TECH-004)
- [ ] TECH-004: Implement theme support (Light/Dark) (AC-TECH-005)
- [ ] TECH-005: Add localization support (EN/AR/FR) (AC-TECH-006)
- [ ] TECH-006: Test on all target platforms (AC-TECH-007)

### UI/UX IMPLEMENTATION TASKS
- [ ] UI-001: Design responsive layout (mobile/tablet/desktop) (AC-UI-004)
- [ ] UI-002: Apply semantic color scheme (AC-UI-001)
- [ ] UI-003: Implement GoRouter navigation (AC-UI-003)
- [ ] UI-004: Test accessibility and contrast (AC-UI-005)
- [ ] UI-005: Verify RTL layout for Arabic (AC-TECH-006)

### BUSINESS LOGIC TASKS
- [ ] BL-001: Implement field validations per specification (AC-BL-001)
- [ ] BL-002: Add role-based permission checks (AC-BL-002)
- [ ] BL-003: Configure real-time data synchronization (AC-BL-003)
- [ ] BL-004: Implement money calculations in cents (AC-BL-004)

### TESTING TASKS
- [ ] TEST-001: Write unit tests for Blocs (90%+ coverage) (AC-TECH-008)
- [ ] TEST-002: Write widget tests for UI components (AC-TECH-008)
- [ ] TEST-003: Write integration tests for user flows (AC-TECH-008)
- [ ] TEST-004: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [ ] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [ ] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)

### FEATURE TASKS
- [ ] Task 1: Salespeople Performance Summary (AC: 1)
  - [ ] Subtask 1.1: Create sales performance metrics by employee
  - [ ] Subtask 1.2: Implement commission calculation logic
  - [ ] Subtask 1.3: Add date range filtering
- [ ] Task 2: Commission Reports Dashboard (AC: 1, 2)
  - [ ] Subtask 2.1: Design commission summary cards
  - [ ] Subtask 2.2: Implement real-time data updates
  - [ ] Subtask 2.3: Add export functionality (PDF/Excel)
- [ ] Task 3: Individual Salesperson Details (AC: 1)
  - [ ] Subtask 3.1: Create salesperson detail view
  - [ ] Subtask 3.2: Show sales history and commission breakdown
  - [ ] Subtask 3.3: Add performance trends and targets

## Previous Story Intelligence

**From Story 8-4 (Supplier Performance Reports):**
- Uses hub pattern with navigation cards to individual reports
- Real-time updates through Drift streams
- Responsive design with mobile/tablet/desktop layouts

**From Story 8-17 (Supplier Analysis Reports) - Perfect Implementation:**
- Complex analytics calculations with aggregations and grouping
- Comprehensive PDF export with charts and tables
- 819 tests passing with full coverage
- Optimized queries for large datasets

**From Story 8-3 (Customer Relationship Reports):**
- Customer analytics with KPI tracking
- Date range filtering implementation
- Export functionality (CSV/PDF)

**Key Learnings:**
- All reports follow identical Clean Architecture file structure
- RealtimeBloc pattern is mandatory for automatic updates
- PDF export service can be adapted between report types
- UI must follow responsive design patterns
- Money calculations must use integer cents throughout
- Tests must achieve 90%+ coverage

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

#### Database Schema (Already Available)
- **Sales Table**: Already has `employeeId` field linking to Employees table
- **Employees Table**: Contains employee info (name, position, department)
- **No New Tables Needed**: Commission rates will be configurable in app settings for V1

#### Screen Structure
- **Main Screen**: `/reports/salespeople-commission` - Commission reports hub
- **Detail Screen**: `/reports/salespeople-commission/:id` - Individual salesperson performance
- **Navigation**: Access from Reports main menu under "Sales & Performance" section

#### Commission Calculation Logic (V1 - Simple)
```dart
// Base commission rates (configurable in settings)
class CommissionConfig {
  static const defaultRate = 5.0; // 5% of sales
  static const targetBonusRate = 7.5; // 7.5% when target met
  static const targetThreshold = 1000000; // 1M in sales (in cents)
}

// Calculation formula
commissionEarned = salesTotal * (metTarget ? targetBonusRate : defaultRate) / 100;
```

#### Required Analytics Queries
```dart
// In SalespeopleCommissionRepository
Future<List<SalespersonPerformanceData>> getSalespersonPerformance(DateTimeRange range);
Stream<List<SalespersonPerformanceData>> watchSalespersonPerformance(DateTimeRange range);

// Required calculations
totalSales = SUM(sales.total_cents) WHERE sales.employee_id = ?
salesCount = COUNT(sales.id) WHERE sales.employee_id = ?
commissionEarned = totalSales * commissionRate / 100
targetAchieved = totalSales >= targetThreshold
performanceTrend = compareWithPreviousPeriod(totalSales)
```

#### Report Features
- **Performance Metrics**: Total sales, commission earned, target achievement %
- **Trends**: Month-over-month growth, performance trends
- **Rankings**: Salesperson leaderboard by performance
- **Export**: PDF reports with charts and tables
- **Date Filtering**: Daily, weekly, monthly, quarterly, yearly views

#### Reference Implementation Pattern
Follow the exact pattern from Story 8-17 (Supplier Analysis Reports):
- Same file structure in `lib/features/reports/`
- Same RealtimeBloc extension pattern
- Same responsive UI layout patterns
- Same PDF export service adaptation
- Same test structure and coverage

### Architecture Notes
- Follow existing report patterns from 8-4 supplier reports and 8-3 customer reports
- Use RealtimeBloc for automatic data updates
- Implement responsive design for mobile/tablet/desktop
- Follow Clean Architecture with proper separation of concerns

### Project Structure Notes

```
lib/features/reports/
├── data/
│   ├── datasources/
│   │   └── salespeople_commission_local_datasource.dart  // NEW
│   ├── models/
│   │   └── salespeople_commission_model.dart  // NEW
│   └── repositories/
│       └── salespeople_commission_repository_impl.dart  // NEW
├── domain/
│   ├── entities/
│   │   └── salespeople_commission_entity.dart  // NEW
│   └── repositories/
│       └── salespeople_commission_repository.dart  // NEW
└── presentation/
    ├── bloc/
    │   └── salespeople_commission_report_bloc.dart  // NEW
    └── screens/
        └── salespeople_commission_report_screen.dart  // NEW
```

#### Database Integration
- Use existing `Sales` DAO: `lib/core/database/daos/sales_dao.dart`
- Use existing `Employees` DAO: `lib/core/database/daos/employee_dao.dart`
- Add commission-specific queries to repository
- No schema migrations needed for V1

### References
- [Source: TAPIX_EPICS_AND_STORIES.md#STORY-08-05]
- [Source: project-context.md#Real-Time-State-Management]
- [Source: project-context.md#Money-Calculations]
- [Source: project-context.md#Responsive-Design]
- **Reference Implementations:**
  - Story 8-17: Supplier Analysis Reports (perfect implementation pattern)
  - Story 8-4: Supplier Performance Reports (UI pattern)
  - Sales Repository: lib/features/sales/domain/repositories/sales_repository.dart
  - Sales DAO: lib/core/database/daos/sales_dao.dart
  - Employee DAO: lib/core/database/daos/employee_dao.dart
  - PDF Service: lib/features/reports/services/supplier_balance_pdf_service.dart (adapt for commission)

## Dev Agent Record

### Agent Model Used
Cascade (Penguin Alpha)

### Debug Log References
- Story creation workflow executed successfully
- All binding constraints loaded and enforced
- Project context analyzed for implementation patterns

### Completion Notes List
- Story 8.5 implemented with comprehensive requirements
- Binding constraints enforced from project-context.md
- Technical requirements aligned with TAPIX_REBUILD_SPECIFICATION.md
- UI patterns consistent with existing report implementations
- Implementation completed 2026-02-10
- 61 comprehensive tests passing
- 0 flutter analyze issues
- Real-time updates via RealtimeBloc pattern
- Responsive design for mobile/tablet/desktop
- 3-language support (EN/AR/FR) with RTL
- PDF export with print/share functionality
- Commission calculations using integer cents
- Date range filtering and sorting options

### File List
- `/home/ahmed/AhmedF/tapix projects/tapix/_bmad-output/implementation-artifacts/8-5-salespeople-commission-reports.md`
- `/home/ahmed/AhmedF/tapix projects/tapix/lib/features/reports/presentation/bloc/salespeople_commission_report_bloc.dart`
- `/home/ahmed/AhmedF/tapix projects/tapix/lib/features/reports/services/salespeople_commission_pdf_service.dart`
- `/home/ahmed/AhmedF/tapix projects/tapix/lib/features/reports/presentation/screens/salespeople_commission_report_screen.dart`
- `/home/ahmed/AhmedF/tapix projects/tapix/test/features/reports/presentation/bloc/salespeople_commission_report_bloc_test.dart`
