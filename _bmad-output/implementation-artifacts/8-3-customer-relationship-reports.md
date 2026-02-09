# Story 8.3: Customer Relationship Reports

Status: ready-for-dev

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
I want customer analytics and statements,
so that I can manage receivables and retention.

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
- **PDF**: pdf package for report generation
- **Excel**: excel package for spreadsheet export

### UI/UX Requirements
- **Responsive Design**: Mobile (<600px), Tablet (600-1024px), Desktop (>1024px) [Source: TAPIX_REBUILD_SPECIFICATION.md#Critical-Requirements]
- **Themes**: Light AND Dark theme support with semantic colors
- **Semantic Colors**: Green (Success), Orange (Warning), Red (Error/Destructive)
- **Localization**: English, Arabic (RTL), French support
- **Platform Support**: Windows, Android, iOS, Web, Linux, macOS
- **Overflow Prevention**: MUST use LayoutBuilder for responsive layouts [Source: project-context.md#Overflow-Prevention-Notes]
- **Theme-Aware Colors**: Use Theme.of(context).colorScheme for surfaces and text [Source: project-context.md#Theme-Aware-UI-Rules]

## Business Logic Requirements

### Customer Reports Specifications
- **Customer Statements**: Opening/closing balances with transaction history
- **Customer Aging**: Outstanding balances categorized by aging buckets (0-30, 31-60, 61-90, 90+ days)
- **Payment History**: Chronological list of all customer payments with methods
- **Customer Analytics**: Purchase frequency, average order value, total sales volume
- **Real-Time Data**: All reports must update automatically when transactions change

### Field Specifications (from Rebuild Spec)
- **Money Fields**: Must use INTEGER cents (balance_cents, payment_cents, total_cents)
- **Date Fields**: Use DateTime objects with proper formatting
- **Customer References**: Use customer_id foreign keys with proper joins
- **Validation**: Date range validation, required field validation
- **Permissions**: Role-based access control (Owner, Manager, Cashier, Salesperson)
- **Real-Time Updates**: UI must update automatically on data changes

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Customer Module**: MUST use existing CustomerRepository and LoyaltyRepository from `lib/features/customers/`
- **Accounting Module**: Integrate with journal entries for transaction data
- **Sales Module**: Use sales data for analytics and payment history
- **Export Services**: Use existing PDF and export services
- **Customer Analytics Integration**: Leverage existing customer fields:
  - `total_spent_cents` (INTEGER) - Already tracked in customers table
  - `total_transactions` (INTEGER) - Already tracked in customers table
  - `last_transaction_at` (DateTime) - Already tracked in customers table
  - `segment` (retail/wholesale/premium) - For customer segmentation reports
  - `loyalty_tier_id` - For loyalty-based analytics

## Implementation Requirements

### Screen Requirements (from UI Architecture)
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Use GoRouter patterns exactly as specified [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]
- **Report Screen Layout**: Filter panel + data table + export actions

### Data Layer Requirements
- **Repository Pattern**: MUST extend existing CustomerRepository for report methods
- **Data Sources**: CustomerReportsDataSource using Drift queries
- **Real-Time Queries**: Use Drift watch() methods for live updates
- **Complex Queries**: JOIN operations across customers, sales, payments, and journal tables
- **Loyalty Integration**: Query loyalty_tiers table for tier-based analytics

### Testing Requirements
- **Unit Tests**: 90%+ coverage for Blocs and Services
- **Widget Tests**: Critical UI components (report tables, filters)
- **Integration Tests**: Report generation and export flows
- **Platform Testing**: ALL target platforms
- **Language Testing**: English, Arabic (RTL), French
- **Theme Testing**: Light AND Dark themes

### Localization Requirements
- **Customer Report Keys**: MUST use `customers.reports.*` prefix for all report-related strings
- **Existing Keys**: Leverage existing customer keys from project-context.md:
  - `customers.segment_*`, `customers.segment_*_desc` for segmentation
  - `customers.benefit_*` keys for loyalty benefit displays
  - Follow pattern: `customers.reports.aging`, `customers.reports.statement`, etc.
- **Translation Files**: Add to `assets/translations/en.json`, `ar.json`, `fr.json`
- **Loyalty Tiers**: Use standard tier names (Bronze, Silver, Gold, Premium) for filtering

### Performance Requirements
- **Large Data Handling**: Must handle thousands of customer records smoothly
- **Real-Time Performance**: <50ms for database updates to reflect in UI
- **Export Performance**: PDF/Excel generation within reasonable time limits
- **Memory Management**: No memory leaks with large datasets

## Acceptance Criteria

1. Customer statements show opening balance, transactions, and closing balance
2. Customer aging report categorizes outstanding balances by time periods
3. Payment history displays all customer payments with dates and methods
4. Customer analytics show purchase patterns and metrics
5. All reports update in real-time from Drift database changes
6. PDF and Excel export functionality works correctly
7. Date range filtering applies to all reports
8. Responsive design works on mobile, tablet, and desktop

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
- AC-BL-001: All customer report calculations are accurate
- AC-BL-002: Role-based permissions enforced for sensitive reports
- AC-BL-003: Real-time data synchronization working
- AC-BL-004: Money calculations accurate (integer cents)
- AC-BL-005: Date range filtering works correctly
- AC-BL-006: Export formats match business requirements

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
- [ ] BL-001: Implement customer report calculations (AC-BL-001)
- [ ] BL-002: Add role-based permission checks (AC-BL-002)
- [ ] BL-003: Configure real-time data synchronization (AC-BL-003)
- [ ] BL-004: Implement money calculations in cents (AC-BL-004)
- [ ] BL-005: Implement date range filtering (AC-BL-005)
- [ ] BL-006: Implement PDF/Excel export (AC-BL-006)

### FEATURE TASKS
- [ ] FEATURE-001: Create Customer Reports screen (AC: 1,2,3,4)
  - [ ] SUBTASK-001-001: Implement report filter panel (customer, date range, segment, loyalty tier)
  - [ ] SUBTASK-001-002: Create customer statement report view
  - [ ] SUBTASK-001-003: Create customer aging report view
  - [ ] SUBTASK-001-004: Create payment history report view
  - [ ] SUBTASK-001-005: Create customer analytics dashboard with segmentation
- [ ] FEATURE-002: Implement Customer Reports Bloc (AC: 5)
  - [ ] SUBTASK-002-001: Create CustomerReportsBloc extending RealtimeBloc
  - [ ] SUBTASK-002-002: Implement real-time data streams
  - [ ] SUBTASK-002-003: Add report filtering and state management
- [ ] FEATURE-003: Extend Existing Customer Data Layer (AC: 5)
  - [ ] SUBTASK-003-001: Add report methods to existing CustomerRepository
  - [ ] SUBTASK-003-002: Create CustomerReportsDataSource with Drift queries
  - [ ] SUBTASK-003-003: Implement complex JOIN queries for report data
  - [ ] SUBTASK-003-004: Integrate with existing LoyaltyRepository for tier analytics
- [ ] FEATURE-004: Implement Export Functionality (AC: 6)
  - [ ] SUBTASK-004-001: Extend existing JournalPdfService for customer reports
  - [ ] SUBTASK-004-002: Create Excel export service for reports
  - [ ] SUBTASK-004-003: Add export buttons and UI integration
- [ ] FEATURE-005: Implement Navigation and Routing (AC: 7)
  - [ ] SUBTASK-005-001: Add customer reports routes to app_router.dart
  - [ ] SUBTASK-005-002: Implement navigation from reports hub
  - [ ] SUBTASK-005-003: Add breadcrumb navigation

### TESTING TASKS
- [ ] TEST-001: Write unit tests for CustomerReportsBloc (90%+ coverage) (AC-TECH-008)
- [ ] TEST-002: Write unit tests for CustomerReportsRepository (AC-TECH-008)
- [ ] TEST-003: Write widget tests for report screens (AC-TECH-008)
- [ ] TEST-004: Write integration tests for report generation (AC-TECH-008)
- [ ] TEST-005: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [ ] TEST-006: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [ ] TEST-007: Test both themes (Light/Dark) (AC-TECH-005)
- [ ] TEST-008: Test export functionality (PDF/Excel) (AC-BL-006)

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
- **Screen Names**: Use exact screen names from rebuild spec (e.g., `CustomerReportsScreen`)
- **Database Queries**: Use existing customer, sales, and payment tables with proper JOINs
- **Business Rules**: Implement all aging calculations and balance derivations from specification
- **Service Integration**: Use existing customer and accounting services
- **Export Integration**: Use existing PDF generation services from accounting module

### Architecture Notes
- **Real-time Updates**: Customer reports must automatically refresh when sales/payments are posted
- **Database Schema**: Follow existing customer, sales, and journal entry tables
- **Performance**: Optimize queries for large datasets using proper indexing
- **Testing Standards**: Follow existing test patterns from customer and accounting modules

### Project Structure Notes

**File Structure to Follow:**
```
lib/features/reports/
├── data/
│   ├── datasources/
│   │   └── customer_reports_datasource.dart
│   └── repositories/
│       └── customer_reports_repository_impl.dart
├── domain/
│   ├── entities/
│   │   ├── customer_statement_entity.dart
│   │   ├── customer_aging_entity.dart
│   │   └── customer_analytics_entity.dart
│   └── repositories/
│       └── customer_reports_repository.dart
└── presentation/
    ├── bloc/
    │   └── customer_reports_bloc.dart
    ├── screens/
    │   └── customer_reports_screen.dart
    └── widgets/
        ├── customer_statement_widget.dart
        ├── customer_aging_widget.dart
        └── customer_analytics_widget.dart

# IMPORTANT: Extend existing repositories
- Add report methods to: lib/features/customers/data/repositories/customer_repository.dart
- Use existing: lib/features/customers/data/repositories/loyalty_repository.dart
- Follow patterns from: lib/features/customers/presentation/bloc/customer_loyalty_bloc.dart
```

### Integration Points
- **Customer Module**: MUST extend existing `CustomerRepository` and use `LoyaltyRepository` [Source: project-context.md#Customers-Module]
- **Customer Fields**: Use existing tracked fields:
  - `total_spent_cents`, `total_transactions`, `last_transaction_at` from customers table
  - `segment` for customer segmentation reports
  - `loyalty_tier_id` for loyalty-based analytics
- **Accounting Module**: Use existing journal entry services for transaction data
- **Sales Module**: Use existing sales repositories for sales data
- **Export Services**: Extend existing `JournalPdfService` for PDF generation
- **UI Patterns**: Follow overflow prevention patterns from CustomerHubScreen [Source: project-context.md#Overflow-Prevention-Notes]

### References
- Customer Module: `lib/features/customers/`
- Accounting Module: `lib/features/accounting/`
- Sales Module: `lib/features/sales/`
- Reports Module: `lib/features/reports/`
- Project Context: [Source: project-context.md]

## Dev Agent Record

### Agent Model Used

BMad Scrum Master Agent v1.0 - Story Creation Workflow

### Debug Log References

- Sprint Status: `sprint-status.yaml` line 154 (story 8-3 status: backlog)
- Epics Source: `TAPIX_EPICS_AND_STORIES.md` lines 848-856
- Project Context: `project-context.md` (full context loaded)

### Completion Notes List

- Story 8.3 extracted from EPIC-08 (Reporting) 
- Status updated from backlog to ready-for-dev
- Comprehensive developer guardrails created
- All binding constraints enforced
- Previous story intelligence: Stories 8.1 and 8.2 completed (financial and inventory reports)

### File List

**Story File Created:**
- `/home/ahmed/AhmedF/tapix projects/tapix/_bmad-output/implementation-artifacts/8-3-customer-relationship-reports.md`

**Referenced Files:**
- `project-context.md` - Cross-cutting concerns and patterns
- `TAPIX_EPICS_AND_STORIES.md` - Story requirements and acceptance criteria
- `sprint-status.yaml` - Story tracking and status management
