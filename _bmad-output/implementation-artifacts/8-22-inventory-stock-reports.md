# Story 8.22: inventory-stock-reports

Status: done

<!-- ⚠️ IMPORTANT: This story is ALREADY IMPLEMENTED as part of story 8-2 (inventory-reports) -->
<!-- The Stock Valuation tab in inventory_reports_screen.dart covers all acceptance criteria -->

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
I want inventory stock reports,
so that I can monitor current quantities.

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

1. Stock by product/variant
2. Updates in realtime

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

### Feature-Specific Acceptance Criteria
- AC-FEATURE-001: Stock report shows current quantities by product
- AC-FEATURE-002: Stock report shows current quantities by variant (when applicable)
- AC-FEATURE-003: Report updates in real-time when stock changes
- AC-FEATURE-004: Report supports filtering by category
- AC-FEATURE-005: Report supports search by product name/SKU/barcode
- AC-FEATURE-006: Report shows stock value (quantity × cost)
- AC-FEATURE-007: Report supports export (PDF/Excel)

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

### FEATURE IMPLEMENTATION TASKS
- [ ] FEATURE-001: Create stock report data service (AC-FEATURE-001, AC-FEATURE-002)
- [ ] FEATURE-002: Implement stock report screen with real-time updates (AC-FEATURE-003)
- [ ] FEATURE-003: Add category filtering (AC-FEATURE-004)
- [ ] FEATURE-004: Add search functionality (AC-FEATURE-005)
- [ ] FEATURE-005: Calculate and display stock value (AC-FEATURE-006)
- [ ] FEATURE-006: Implement export functionality (AC-FEATURE-007)

### TESTING TASKS
- [ ] TEST-001: Write unit tests for Blocs (90%+ coverage) (AC-TECH-008)
- [ ] TEST-002: Write widget tests for UI components (AC-TECH-008)
- [ ] TEST-003: Write integration tests for user flows (AC-TECH-008)
- [ ] TEST-004: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [ ] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [ ] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)

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

#### Database Schema Requirements
- **product_variants table**: Query stock_quantity field for current stock levels
- **products table**: Join for product names, categories, and hasVariants flag
- **categories table**: Join for category filtering
- **Stock calculation**: SUM(product_variants.stock_quantity) grouped by product/variant

#### Report Structure
- **Product Level**: Show total stock across all variants when hasVariants=true
- **Variant Level**: Show individual variant stock when hasVariants=true or for single variants
- **Stock Value**: Calculate as quantity × cost_cents (from product_variants table)
- **Real-time Updates**: Use Drift streams on product_variants table

#### Screen Components
- **Report Screen**: `InventoryStockReportScreen` in `lib/features/reports/presentation/screens/`
- **Data Table**: Responsive table with product/variant, quantity, and value columns
- **Filters**: Category dropdown, search field for name/SKU/barcode
- **Export**: PDF and Excel export functionality

#### Bloc Implementation
- **Report Bloc**: `InventoryStockReportBloc` extending RealtimeBloc
- **Events**: LoadReport, FilterByCategory, SearchProducts, ExportReport
- **State**: RealtimeLoading, RealtimeSuccess with report data, RealtimeError
- **Stream**: Watch product_variants table for real-time stock changes

#### Service Layer
- **Report Service**: `InventoryReportService` in `lib/features/reports/data/services/`
- **Data Source**: Drift queries with joins and aggregations
- **Export Service**: PDF and Excel generation using existing report infrastructure

### Architecture Notes
- **Clean Architecture**: Data layer (repositories, datasources), Domain layer (entities, use cases), Presentation layer (blocs, screens)
- **Real-time Pattern**: Database changes → Stream → Bloc → UI updates automatically
- **Dependency Injection**: Use get_it for service injection
- **Error Handling**: Proper error states and user-friendly messages

### Project Structure Notes
- **Feature Module**: `lib/features/reports/` following existing report structure
- **File Organization**: Follow existing patterns from other report screens (trial_balance, profit_loss, balance_sheet)
- **Naming Conventions**: Consistent with existing codebase (snake_case for files, PascalCase for classes)

### Integration Points
- **Product Management**: Use existing product and variant entities
- **Category System**: Integrate with existing category filtering
- **Export Infrastructure**: Reuse existing PDF/Excel export services
- **Navigation**: Add to reports navigation structure

## Dev Agent Record

### Agent Model Used
Bob - Scrum Master (BMad Method)

### Debug Log References
- Workflow execution: create-story workflow
- Source artifacts: TAPIX_EPICS_AND_STORIES.md, project-context.md
- Story context: EPIC-08 Reporting, STORY-08-22 Inventory Stock Reports

### Completion Notes List
- Story parsed from user input "cs 8.22"
- Epic 8 context loaded from TAPIX_EPICS_AND_STORIES.md
- Project context constraints extracted from project-context.md
- Technical requirements aligned with TAPIX_REBUILD_SPECIFICATION.md
- Status updated from backlog to ready-for-dev

### File List
- Story file: /home/ahmed/AhmedF/tapix projects/tapix/_bmad-output/implementation-artifacts/8-22-inventory-stock-reports.md
- Sprint status: /home/ahmed/AhmedF/tapix projects/tapix/_bmad-output/implementation-artifacts/sprint-status.yaml
