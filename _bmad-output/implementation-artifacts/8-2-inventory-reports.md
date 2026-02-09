# Story 8.2: Inventory Reports

Status: ready-for-dev

<!-- ENFORCEMENT: This story includes binding constraints that CANNOT be ignored -->
<!-- AI Models MUST follow project-context.md and UI architecture specifications -->

## BINDING CONSTRAINTS (MANDATORY - CANNOT BE IGNORED)

### Project Context Requirements (ENFORCED)
- **Bloc Pattern**: Reports use standard Bloc pattern (see AccountingHealthBloc) [Source: project-context.md#Real-Time-State-Management]
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
I want to see stock valuation and low stock alerts,
so that I can reorder in time.

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

1. [ ] Stock valuation report
2. [ ] Low stock report
3. [ ] Product movement history

### Technical Acceptance Criteria (MANDATORY)
- AC-TECH-001: Follows Clean Architecture pattern exactly
- AC-TECH-002: Implements standard Bloc pattern for reports (like AccountingHealthBloc)
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
- [ ] COMPLIANCE-001: Verify Bloc pattern implementation (standard Bloc like AccountingHealthBloc) (AC-TECH-002)
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
- [ ] FEAT-001: Create Inventory Reports screen (AC: 1)
  - [ ] FEAT-001-001: Implement stock valuation report
  - [ ] FEAT-001-002: Implement low stock alerts report
  - [ ] FEAT-001-003: Implement product movement history report
- [ ] FEAT-002: Create Inventory Reports Bloc (AC: 1)
  - [ ] FEAT-002-001: Extend RealtimeBloc for real-time updates
  - [ ] FEAT-002-002: Implement report data streams
  - [ ] FEAT-002-003: Add filtering and date range support
- [ ] FEAT-003: Implement report data services (AC: 1)
  - [ ] FEAT-003-001: Create stock valuation calculations
  - [ ] FEAT-003-002: Implement low stock detection logic
  - [ ] FEAT-003-003: Create product movement tracking
- [ ] FEAT-004: Add export functionality (AC: 1)
  - [ ] FEAT-004-001: PDF export for all reports
  - [ ] FEAT-004-002: Excel export support
  - [ ] FEAT-004-003: Localized export headers
- [ ] FEAT-005: Implement responsive UI components (AC: 1)
  - [ ] FEAT-005-001: Mobile-optimized report tables
  - [ ] FEAT-005-002: Tablet layout adaptations
  - [ ] FEAT-005-003: Desktop split-view design

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
- **Screen Names**: Use exact screen names from rebuild spec (e.g., `InventoryReportsScreen`)
- **Integration**: Place under products feature since inventory reports are about stock, not financial transactions
- **Field Lists**: Include ALL fields from specification for inventory calculations
- **Business Rules**: Implement all validations and rules from specification
- **Service Integration**: Use services from Core Services Inventory (section 8)
- **Database Schema**: Follow exact schema from Database Requirements (section 9)
- **Navigation**: Add inventory reports as a new option in products main screen
- **Bloc Pattern**: Follow AccountingHealthBloc pattern (standard Bloc, not RealtimeBloc for reports)

### Architecture Notes
- **Bloc Pattern**: Use standard Bloc pattern like AccountingHealthBloc (not RealtimeBloc for reports)
- **Report Calculations**: Stock valuation uses variant.costCents * stockQuantity (integer cents)
- **Low Stock Logic**: Configurable threshold per product/variant using existing `reorder_level` field
- **Product Movement**: Track all inventory transactions (sales, purchases, returns, adjustments)
- **Export Services**: Create new InventoryPdfService following JournalPdfService pattern
  - Reference: lib/features/accounting/presentation/services/journal_pdf_service.dart

### Project Structure Notes

**Required Files Structure:**
```
lib/features/products/
├── presentation/
│   ├── bloc/
│   │   ├── product_variants_bloc.dart  # Already exists
│   │   └── inventory_reports_bloc.dart  # New bloc for inventory reports
│   └── screens/
│       ├── variants_screen.dart  # Already exists
│       └── inventory_reports_screen.dart     # New screen for inventory reports
├── data/
│   ├── repositories/
│   │   ├── product_repository.dart  # Already exists
│   │   └── inventory_reports_repository.dart  # New repository
│   └── datasources/
│       └── inventory_reports_local_datasource.dart  # New datasource
└── services/
    ├── export_service.dart  # Already exists
    ├── import_service.dart  # Already exists
    └── inventory_pdf_service.dart  # New service following JournalPdfService pattern
```

### Database Integration Requirements
- **Stock Valuation Query**: JOIN products, product_variants, calculate SUM(stockQuantity * costCents)
- **Low Stock Query**: Filter variants WHERE stockQuantity <= reorder_level (using existing field)
- **Product Movement Query**: Track inventory transactions from sales, purchases, returns
- **Real-time Updates**: All reports must update automatically when inventory changes

### References

- [Source: TAPIX_EPICS_AND_STORIES.md#EPIC-08-Reporting]
- [Source: project-context.md#Product-Variants-System]
- [Source: project-context.md#Real-Time-State-Management]
- [Source: project-context.md#Money-Calculations]

## Dev Agent Record

### Agent Model Used

Bob (Scrum Master) - Create Story Workflow v1.0

### Debug Log References

- Story extracted from sprint-status.yaml line 153
- Epic 8 context loaded from TAPIX_EPICS_AND_STORIES.md
- Project context constraints loaded from project-context.md

### Completion Notes List

- Story 8.2 created with comprehensive developer guardrails
- All binding constraints enforced from project-context.md
- Technical requirements aligned with TAPIX_REBUILD_SPECIFICATION.md
- Implementation structure follows Clean Architecture patterns

### File List

- Primary story: 8-2-inventory-reports.md
- Dependencies: project-context.md, TAPIX_REBUILD_SPECIFICATION.md
- Template source: _bmad/bmm/workflows/4-implementation/create-story/template.md
