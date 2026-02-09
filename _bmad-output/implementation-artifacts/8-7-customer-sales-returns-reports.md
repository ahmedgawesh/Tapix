# Story 8.7: Customer Sales Returns Reports

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
I want sales returns reports by customer,
so that I can monitor return patterns.

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

### Customer Sales Returns Reports Specifications
- **Returns by Customer**: Aggregate return data grouped by customer with date range filtering
- **Return Pattern Analysis**: Track return frequency, reasons, and values per customer
- **Return Trends**: Monitor return patterns over time to identify problematic products or customers
- **Real-Time Data**: All reports must update automatically when sales returns are processed
- **Export Capabilities**: Support PDF and Excel export formats

### Field Specifications (from Rebuild Spec)
- **Money Fields**: Must use INTEGER cents (return_amount_cents, total_returned_cents)
- **Date Fields**: Use DateTime objects with proper formatting for return dates
- **Customer References**: Use customer_id foreign keys with proper joins
- **Product References**: Use variant_id for product-level return analysis
- **Validation**: Date range validation, required field validation
- **Permissions**: Role-based access control (Owner, Manager, Cashier, Salesperson)
- **Real-Time Updates**: UI must update automatically on data changes

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Customer Module**: MUST use existing CustomerRepository from `lib/features/customers/`
- **Sales Module**: Integrate with sales return transactions from `lib/features/sales/`
- **Product Module**: Use product data for return analysis by product/variant
- **Export Services**: Use existing PDF and export services from `lib/features/reports/services/`
- **Reports Module**: Extend existing customer reports infrastructure

### Data Sources Required
- **sale_returns** table: Core return transaction data (CONFIRMED EXISTS in transactions.dart)
- **sale_return_items** table: Individual returned items with quantities and amounts (CONFIRMED EXISTS)
- **customers** table: Customer information for grouping and filtering
- **product_variants** table: Product details for return analysis
- **sales** table: Original sale references for return context

### Dependencies
- **Epic 5 (Sales & POS)**: Tables exist but Epic 5 is still in backlog - this story can proceed as it only reads data
- **Customer Reports Module**: Build upon existing CustomerReportsBloc pattern
- **No New Tables Required**: All necessary tables already exist in database schema

## Implementation Requirements

### Screen Requirements (from UI Architecture)
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Use GoRouter patterns exactly as specified [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]
- **Report Screen Layout**: Filter panel + data table + export actions

### Data Layer Requirements
- **Repository Pattern**: Create CustomerReturnsRepository extending existing reports repository pattern
- **Database Queries**: Optimize queries for large datasets with proper indexing
- **Stream Integration**: Real-time updates using Drift streams
- **Caching Strategy**: Implement smart caching for frequently accessed return data

### Service Layer Requirements
- **Customer Returns Service**: Business logic for return calculations and aggregations
- **Export Service**: PDF and Excel generation using existing report export infrastructure
- **Date Range Service**: Reuse existing ReportDateRange component and logic
- **Currency Formatting**: Use CurrencyService for all money displays

### Testing Requirements
- **Unit Tests**: 90%+ coverage for Blocs and Services
- **Widget Tests**: Critical UI components (data tables, filters, export buttons)
- **Integration Tests**: User flows (filter → view → export)
- **Platform Testing**: ALL target platforms
- **Language Testing**: English, Arabic (RTL), French
- **Theme Testing**: Light AND Dark themes

### Performance Requirements
- **Large Data Handling**: Must handle thousands of return records smoothly
- **Real-Time Performance**: <50ms for database updates to reflect in UI
- **Memory Management**: No memory leaks with large datasets
- **Export Performance**: PDF/Excel generation under 5 seconds for typical datasets

## Acceptance Criteria

1. Returns by customer and date range
2. Export supported

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
- AC-BL-005: Return aggregations accurate by customer
- AC-BL-006: Date range filtering works correctly
- AC-BL-007: Export formats contain correct data

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
- [ ] BL-005: Implement return aggregation logic (AC-BL-005)
- [ ] BL-006: Implement date range filtering (AC-BL-006)
- [ ] BL-007: Implement export functionality (AC-BL-007)

### FEATURE TASKS
- [ ] FEATURE-001: Extend CustomerReportsBloc for Returns (AC: 1, 2)
  - [ ] Add CustomerReturnsData class following CustomerReportsData pattern
  - [ ] Add CustomerReturnsItem data model for individual return entries
  - [ ] Extend existing stream to watch sale_returns and sale_return_items tables
  - [ ] Add return aggregation logic by customer
- [ ] FEATURE-002: Add Returns Tab to CustomerReportsScreen (AC: 4, 5, 6)
  - [ ] Add new tab index for returns in existing TabBar
  - [ ] Implement returns data table following existing pattern
  - [ ] Add export buttons for returns data
  - [ ] Ensure responsive layout with LayoutBuilder
- [ ] FEATURE-003: Implement Returns Data Loading (AC: 1, 3)
  - [ ] Create _loadReturns() method following _loadStatements() pattern
  - [ ] Join sale_returns → customers with proper filtering
  - [ ] Calculate return totals and counts per customer
  - [ ] Apply date range filtering
- [ ] FEATURE-004: Add Export Services Integration (AC: 7)
  - [ ] Extend existing PDF export service for returns data
  - [ ] Add Excel export following existing export patterns
  - [ ] Format returns data with proper currency formatting
- [ ] FEATURE-005: Add Return Details Drill-down (AC: 5, 6)
  - [ ] Show individual return items when customer selected
  - [ ] Display return reasons and disposition types
  - [ ] Link to original sale invoices where applicable

### TESTING TASKS
- [ ] TEST-001: Write unit tests for CustomerReturnsBloc (90%+ coverage) (AC-TECH-008)
- [ ] TEST-002: Write widget tests for CustomerReturnsScreen (AC-TECH-008)
- [ ] TEST-003: Write integration tests for user flows (AC-TECH-008)
- [ ] TEST-004: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [ ] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [ ] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)
- [ ] TEST-007: Test export functionality (AC-BL-007)
- [ ] TEST-008: Test return aggregations accuracy (AC-BL-005)

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
- **Screen Names**: Use exact screen names from rebuild spec (e.g., `CustomerReturnsReportsScreen`)
- **Field Lists**: Include ALL fields from specification (money fields as INTEGER cents)
- **Business Rules**: Implement all validations and rules from specification
- **Service Integration**: Use services from Core Services Inventory (section 8)
- **Database Schema**: Follow exact schema from Database Requirements (section 9)

### Architecture Notes
- **Extend Existing Pattern**: Extend `CustomerReportsBloc` and `CustomerReportsScreen` - DO NOT create new files
- **Follow Established Structure**: Use the same tab-based approach as existing customer reports
- **Reuse Components**: Leverage existing `ReportDateRange`, export services, and data table patterns
- **Real-time Integration**: Follow existing RealtimeBloc implementation with combined streams
- **No New Repository Needed**: Use existing AppDatabase select statements within the bloc

### Project Structure Notes
- **Primary Location**: Extend `lib/features/reports/presentation/bloc/customer_reports_bloc.dart`
- **Screen Location**: Extend `lib/features/reports/presentation/screens/customer_reports_screen.dart`
- **No New Files Required**: This story extends existing customer reports functionality
- **Integration Points**: Connect to existing customer and sales return tables via AppDatabase

### Database Schema Integration
- **Primary Tables**: `sale_returns`, `sale_return_items`, `customers`, `product_variants`
- **Join Patterns**: Customer → Returns → Items → Products for comprehensive analysis
- **Aggregation Queries**: GROUP BY customer_id with SUM of return amounts and COUNT of returns
- **Date Filtering**: Efficient date range queries on return_date columns
- **Index Requirements**: Ensure proper indexing on customer_id and return_date fields

### Export Requirements
- **PDF Format**: Professional report layout with customer summaries and charts
- **Excel Format**: Detailed data with pivot table friendly structure
- **Naming Convention**: `customer_returns_report_YYYY-MM-DD`
- **Content**: Customer name, return count, total returned amount, return frequency

### References
- **Customer Reports Pattern**: [Source: 8-3-customer-relationship-reports.md]
- **Reports Module Structure**: [Source: lib/features/reports/]
- **RealtimeBloc Pattern**: [Source: project-context.md#Real-Time-State-Management]
- **Export Services**: [Source: lib/features/reports/services/]

## Dev Agent Record

### Agent Model Used
Bob (Scrum Master) - BMad Method Workflow Engine

### Debug Log References
- Workflow: create-story
- Template: _bmad/bmm/workflows/4-implementation/create-story/template.md
- Instructions: _bmad/bmm/workflows/4-implementation/create-story/instructions.xml

### Completion Notes List
- Epic 8 status: in-progress
- Story 8.7 created from backlog → ready-for-dev
- Based on existing customer reports patterns
- Integrated with existing reports infrastructure
- Comprehensive developer guardrails provided

### File List
- Story file: 8-7-customer-sales-returns-reports.md
- Sprint status: _bmad-output/implementation-artifacts/sprint-status.yaml (updated)
- References: 8-3-customer-relationship-reports.md (pattern reference)
