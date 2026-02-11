# Story 8.6: Expense Reports

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
I want expense reports,
so that I can track operational costs over time.

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

### Expense Report Data Requirements
- **Expense Summaries**: Group expenses by category with total amounts
- **Date Range Filtering**: User-selectable period for expense analysis
- **Category Breakdown**: Show expense totals per category with percentages
- **Trend Analysis**: Expense trends over time (optional chart visualization)
- **Real-time Updates**: Report updates when any expense changes
- **Integration**: Use existing ExpenseRepository from Epic 7 (expenses module)

### Field Specifications
- **Money Fields**: Must use INTEGER cents (amount_cents from expenses table)
- **Date Fields**: DateTime objects for expense_date filtering
- **Category References**: Link to expense_categories table via category_id
- **Aggregations**: SUM(amount_cents) GROUP BY category_id
- **Validation**: Required fields, date range validation, business rule validation
- **Permissions**: Role-based access control (Owner, Manager, Cashier, Salesperson)
- **Real-Time Updates**: UI must update automatically on data changes

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Service Dependencies**: Use appropriate services from Core Services Inventory
- **Cross-Feature Integration**: Follow interaction patterns from specification
- **Expense Module**: Use existing ExpenseRepository and expense data patterns from Epic 7
- **Reporting Module**: Follow established reporting patterns from other reports (8-1 through 8-5, 8-7 onwards)

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
- **Large Data Handling**: Must handle thousands of expense records smoothly
- **Real-Time Performance**: <50ms for database updates to reflect in UI
- **Memory Management**: No memory leaks with large datasets

## Acceptance Criteria

1. Expense summaries by category and date range
2. Updates in realtime from Drift

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

### Report Acceptance Criteria (MANDATORY)
- AC-RPT-001: Expense summaries grouped by category with totals
- AC-RPT-002: Date range filtering applied correctly
- AC-RPT-003: Real-time updates when expenses change
- AC-RPT-004: PDF export with multi-language support
- AC-RPT-005: Excel/CSV export with proper formatting
- AC-RPT-006: Print support for A4 and thermal printers

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

### REPORT IMPLEMENTATION TASKS
- [ ] RPT-001: Create expense summary calculation service (AC-RPT-001)
- [ ] RPT-002: Implement category-wise expense aggregation (AC-RPT-002)
- [ ] RPT-003: Set up real-time expense updates (AC-RPT-003)
- [ ] RPT-004: Add date range filtering (AC-RPT-004)
- [ ] RPT-005: Implement PDF export functionality (AC-RPT-005)
- [ ] RPT-006: Implement Excel export functionality (AC-RPT-005)
- [ ] RPT-007: Add print support for A4 and thermal printers (AC-RPT-006)

### FEATURE TASKS
- [ ] FEATURE-001: Create ExpenseReportBloc (AC: AC-BL-003, AC-TECH-002)
  - [ ] Subtask 001.1: Extend RealtimeBloc for real-time updates
  - [ ] Subtask 001.2: Implement expense summaries by category
  - [ ] Subtask 001.3: Add date range filtering for expense periods
- [ ] FEATURE-002: Create ExpenseReportScreen (AC: AC-UI-004, AC-TECH-004)
  - [ ] Subtask 002.1: Design responsive layout following other report patterns
  - [ ] Subtask 002.2: Add date range picker with validation
  - [ ] Subtask 002.3: Display expense list with category summaries
  - [ ] Subtask 002.4: Add category-wise breakdown with percentages
- [ ] FEATURE-003: Implement Expense Summary Service (AC: AC-BL-004, AC-TECH-003)
  - [ ] Subtask 003.1: Create service leveraging existing ExpenseRepository
  - [ ] Subtask 003.2: Query expenses within date range using watchExpensesByDateRange()
  - [ ] Subtask 003.3: Calculate category totals in integer cents (Note: Repository may need extension method for category grouping)
  - [ ] Subtask 003.4: Join with expense_categories for category names
- [ ] FEATURE-004: Add Export Functionality (AC: AC-RPT-005, AC-RPT-006)
  - [ ] Subtask 004.1: Create PDF export following other report patterns
  - [ ] Subtask 004.2: Add Excel export with proper formatting

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
- **Screen Names**: Use exact screen names from rebuild spec (e.g., `ExpenseReportScreen`)
- **Field Lists**: Include ALL fields from specification (e.g., expense fields from section 5.12)
- **Business Rules**: Implement all validations and rules from specification
- **Service Integration**: Use services from Core Services Inventory (section 8)
- **Database Schema**: Follow exact schema from Database Requirements (section 9)

### Architecture Notes
- **RealtimeBloc Pattern**: Must extend RealtimeBloc for expense report data streams
- **Existing Infrastructure**: Use ExpenseRepository from lib/features/expenses/domain/repositories/expense_repository.dart
- **Database Queries**: Leverage existing watchExpensesByDateRange and watchAllCategories methods
- **Money Handling**: All expense amounts stored as integer cents, display via CurrencyService
- **Responsive Layout**: Use LayoutBuilder for mobile/tablet/desktop breakpoints
- **Export Services**: Use PdfService and CsvSaver from Core Services Inventory
- **Report Patterns**: Follow same structure as other reports in lib/features/reports/presentation/screens/

### Project Structure Notes

**Report Feature Integration:**
```
lib/features/reports/
├── presentation/
│   ├── screens/
│   │   └── expense_report_screen.dart  # NEW - Add to existing 24 screens
│   ├── bloc/
│   │   └── expense_report_bloc.dart    # NEW - Add to existing 19 blocs
│   └── widgets/
│       ├── expense_summary_card.dart   # NEW - Add to existing 2 widgets
│       └── expense_category_chart.dart # NEW
├── services/
│   └── expense_pdf_service.dart        # NEW - Follow existing PDF service pattern
```

**Existing Expense Infrastructure to Use:**
```
lib/features/expenses/
├── domain/
│   └── repositories/
│       └── expense_repository.dart     # EXISTING - Use watchExpensesByDateRange()
├── data/
│   └── repositories/
│       └── expense_repository_impl.dart # EXISTING
└── presentation/
    └── bloc/
        └── expenses_bloc.dart           # EXISTING - Reference for patterns
```

### Database Schema References
- **expenses table**: id, date, category_id, amount_cents, description, payment_method
- **expense_categories table**: id, name, description, active
- **Query Pattern**: JOIN with categories, GROUP BY category, SUM(amount_cents)

### Integration Points
- **CurrencyService**: For all money formatting and display
- **PdfService**: For PDF export functionality
- **CsvSaver**: For Excel/CSV export
- **RealtimeService**: For automatic UI updates

### References

- Cite all technical details with source paths and sections, e.g. [Source: docs/<file>.md#Section]

## Dev Agent Record

### Agent Model Used

Claude Sonnet (Anthropic)

### Debug Log References

### Completion Notes List

### File List
