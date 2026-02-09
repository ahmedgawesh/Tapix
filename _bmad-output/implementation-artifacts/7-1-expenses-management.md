# Story 7.1: Expenses Management

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

As a User,
I want to record operational expenses,
So that my profit/loss is accurate.

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
- **Money Fields**: Must use INTEGER cents (amount_cents)
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

1. Expense CRUD with categories
2. Money math uses integer cents only

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
- [ ] FEAT-001: Create expense categories management (AC: 1)
  - [ ] FEAT-001.1: Implement expense categories CRUD
  - [ ] FEAT-001.2: Add category validation and uniqueness
  - [ ] FEAT-001.3: Create category selection UI
- [ ] FEAT-002: Implement expense CRUD operations (AC: 1)
  - [ ] FEAT-002.1: Create expense data model with integer cents
  - [ ] FEAT-002.2: Implement expense repository with Drift
  - [ ] FEAT-002.3: Add expense validation (amount, date, category)
- [ ] FEAT-003: Build expense management UI (AC: 1)
  - [ ] FEAT-003.1: Create expense list screen with real-time updates
  - [ ] FEAT-003.2: Build expense form screen with validation
  - [ ] FEAT-003.3: Add responsive design for all screen sizes
- [ ] FEAT-004: Integrate with accounting system (AC: 2)
  - [ ] FEAT-004.1: Connect expenses to journal entries
  - [ ] FEAT-004.2: Ensure money calculations use integer cents
  - [ ] FEAT-004.3: Add real-time balance updates

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
- **Screen Names**: Use exact screen names from rebuild spec (e.g., `ExpensesScreen`, `ExpenseFormScreen`)
- **Field Lists**: Include ALL fields from specification (amount_cents, date, category, description)
- **Business Rules**: Implement all validations and rules from specification
- **Service Integration**: Use services from Core Services Inventory (section 8)
- **Database Schema**: Follow exact schema from Database Requirements (section 9)

### Architecture Notes
- **RealtimeBloc**: All expense-related Blocs MUST extend RealtimeBloc for automatic database updates
- **Money Handling**: Store all amounts as integer cents, use CurrencyService for display
- **Category Management**: Expenses belong to categories, implement category CRUD first
- **Integration**: Expenses should impact profit/loss calculations and reporting

### Database Schema Requirements
Based on TAPIX_REBUILD_SPECIFICATION.md section 9, the expenses system requires:
- `expense_categories` table: id, name, description, is_active, created_at, updated_at
- `expenses` table: id, category_id, amount_cents, date, description, created_at, updated_at
- Proper foreign key relationships and indexes
- Money fields as INTEGER (cents)

### Project Structure Notes
- Follow Clean Architecture: `lib/features/expenses/` with data/domain/presentation layers
- Repository pattern with Drift implementation
- Bloc pattern extending RealtimeBloc for real-time updates
- Responsive UI components using LayoutBuilder for breakpoints

### Integration Points
- **Accounting**: Expenses must integrate with journal entries system
- **Reporting**: Expense data must be available for financial reports
- **Permissions**: Role-based access (Owner/Manager can manage, Cashier/Salesperson view-only)
- **Localization**: All expense-related strings must be localized

### References
- [Source: TAPIX_REBUILD_SPECIFICATION.md#Critical-Requirements]
- [Source: TAPIX_REBUILD_SPECIFICATION.md#Database-Schema-Requirements]
- [Source: project-context.md#Money-Calculations]
- [Source: project-context.md#Real-Time-State-Management]
- [Source: project-context.md#Responsive-Design]

## Dev Agent Record

### Agent Model Used
Cascade (Penguin Alpha)

### Debug Log References
- Story creation workflow executed per BMad Method
- All binding constraints extracted and enforced
- Epic 7 context analyzed for Finance & Accounting requirements

### Completion Notes List
- Comprehensive story context created with all binding constraints
- Technical requirements aligned with TAPIX_REBUILD_SPECIFICATION.md
- Money calculation rules enforced (integer cents only)
- Real-time updates required via RealtimeBloc pattern
- Responsive design mandatory for all screen sizes
- Full localization support required (EN/AR/FR with RTL)

### File List
- Primary story file: `7-1-expenses-management.md`
- References: TAPIX_REBUILD_SPECIFICATION.md, project-context.md
- Dependencies: UI architecture specification, enforcement framework
