# Story 8.19: Supplier Statement Reports

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
I want supplier statement reports,
So that I can audit supplier accounts.

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
- **PDF**: pdf package for statement generation

### UI/UX Requirements
- **Responsive Design**: Mobile (<600px), Tablet (600-1024px), Desktop (>1024px) [Source: TAPIX_REBUILD_SPECIFICATION.md#Critical-Requirements]
- **Themes**: Light AND Dark theme support with semantic colors
- **Semantic Colors**: Green (Success), Orange (Warning), Red (Error/Destructive)
- **Localization**: English, Arabic (RTL), French support
- **Platform Support**: Windows, Android, iOS, Web, Linux, macOS

## Business Logic Requirements

### Supplier Statement Report Specifications
- **Statement Period**: Opening balance + transaction list within date range
- **Data Source**: Supplier transactions from ledger (purchases, returns, payments, adjustments)
- **Opening Balance**: Calculated from transactions before start date
- **Closing Balance**: Opening balance + net transactions in period
- **Real-Time**: Updates automatically when transactions change
- **Currency**: All amounts in cents, displayed with CurrencyService

### Field Specifications
- **Supplier Information**: Name, address, contact details
- **Statement Period**: Start date and end date
- **Opening Balance**: Brought forward amount in cents
- **Transaction List**: Date, reference, type, description, amount (cents)
- **Running Balance**: Updated balance after each transaction
- **Closing Balance**: Final amount at period end
- **Summary**: Total purchases, total payments, net change

### Transaction Types Included
- **Purchases**: Increase supplier balance (money owed)
- **Purchase Returns**: Decrease supplier balance
- **Payments**: Decrease supplier balance
- **Discounts/Adjustments**: Credit or debit adjustments
- **Refunds**: Credit adjustments to supplier

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Service Dependencies**: Use appropriate services from Core Services Inventory
- **Cross-Feature Integration**: Follow interaction patterns from specification

## Implementation Requirements

### Screen Requirements (from UI Architecture)
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Use GoRouter patterns exactly as specified [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]
- **Screen Name**: `SupplierStatementReportScreen` (follow naming convention from 8-14)
- **Route**: `/reports/supplier-statement` (consistent with other supplier reports)

### Report Structure
- **Header**: Supplier name, address, statement period, contact info
- **Balance Summary**: Opening balance, total transactions, closing balance
- **Transaction List**: Chronological list with running balance
- **Summary Section**: Totals by transaction type
- **Filters**: Supplier selection, date range
- **Export**: PDF export support (Excel optional for future story)

### PDF Export Requirements
- **Multi-language Support**: Headers and labels localized
- **RTL Support**: Proper Arabic layout
- **Professional Format**: Company header, statement details, transaction table
- **Currency Formatting**: Use CurrencyService for proper formatting
- **Page Numbers**: For multi-page statements

### Testing Requirements
- **Unit Tests**: 90%+ coverage for Blocs and Services
- **Widget Tests**: Critical UI components
- **Integration Tests**: User flows
- **Platform Testing**: ALL target platforms
- **Language Testing**: English, Arabic (RTL), French
- **Theme Testing**: Light AND Dark themes

### Performance Requirements
- **Large Data Handling**: Must handle thousands of transactions smoothly
- **Real-Time Performance**: <50ms for database updates to reflect in UI
- **Memory Management**: No memory leaks with large datasets

## Acceptance Criteria

1. Supplier statement shows opening balance and transaction list for selected period
2. PDF export generates professional statement with all transaction details
3. Statement updates in real-time when supplier transactions change
4. Supports all languages with proper RTL for Arabic
5. Works on all screen sizes without overflow

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
- AC-BL-001: Opening balance calculated correctly from historical data
- AC-BL-002: Running balance updates accurately per transaction
- AC-BL-003: All transaction types included in statement
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
- [ ] BL-001: Implement opening balance calculation (AC-BL-001)
- [ ] BL-002: Add running balance computation (AC-BL-002)
- [ ] BL-003: Include all transaction types (AC-BL-003)
- [ ] BL-004: Implement money calculations in cents (AC-BL-004)

### TESTING TASKS
- [ ] TEST-001: Write unit tests for Blocs (90%+ coverage) (AC-TECH-008)
- [ ] TEST-002: Write widget tests for UI components (AC-TECH-008)
- [ ] TEST-003: Write integration tests for user flows (AC-TECH-008)
- [ ] TEST-004: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [ ] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [ ] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)

### FEATURE TASKS
- [ ] FEATURE-001: Create SupplierStatementBloc extending RealtimeBloc (AC-TECH-002)
  - [ ] SUBTASK-001.1: Implement data stream from supplier transactions
  - [ ] SUBTASK-001.2: Add supplier selection and date range filtering
  - [ ] SUBTASK-001.3: Calculate opening and closing balances
- [ ] FEATURE-002: Build SupplierStatementScreen with responsive layout (AC-UI-004)
  - [ ] SUBTASK-002.1: Design supplier selection and date filter UI
  - [ ] SUBTASK-002.2: Create transaction list with running balance
  - [ ] SUBTASK-002.3: Add balance summary cards
- [ ] FEATURE-003: Implement PDF export for statements (AC: 1)
  - [ ] SUBTASK-003.1: Create PDF template with company header
  - [ ] SUBTASK-003.2: Add transaction table with proper formatting
  - [ ] SUBTASK-003.3: Support multi-language and RTL layouts
- [ ] FEATURE-004: Add real-time updates for transaction changes (AC-BL-003)
  - [ ] SUBTASK-004.1: Stream database changes to Bloc
  - [ ] SUBTASK-004.2: Update UI automatically on data changes
  - [ ] SUBTASK-004.3: Handle loading and error states

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
- **Screen Names**: Use exact screen names from rebuild spec (e.g., `SupplierStatementReportScreen`)
- **Field Lists**: Include ALL fields from specification (supplier info, balances, transactions)
- **Business Rules**: Implement all calculations and rules from specification
- **Service Integration**: Use services from Core Services Inventory (section 8)
- **Database Schema**: Follow exact schema from Database Requirements (section 9)

#### Database Schema Requirements
- **Primary Tables**: 
  - `suppliers` table: supplier contact information and balance_cents
  - `purchases` table: invoice dates, total_cents, supplier_id for transactions
  - `supplier_payments` table: payment dates and amounts for balance updates
  - `supplier_returns` table: return dates and amounts for credit transactions
  - `supplier_ledger` table: all supplier transactions for statement generation
- **Statement Query**: Join suppliers with ledger to get transaction history
- **Balance Calculation**: Use existing supplier balance logic from accounting system

#### Screen Requirements
- **Screen Name**: `SupplierStatementReportScreen` (follow naming convention from 8-14)
- **Route**: `/reports/supplier-statement` (consistent with other supplier reports)
- **Layout**: Responsive table with transaction list and running balance
- **Filters**: Date range, supplier selection
- **Actions**: Export PDF, supplier detail navigation
- **Colors**: Use semantic colors for balance indicators (green=credit, red=debit)

### Architecture Notes
- Follow RealtimeBloc pattern for all state management
- Use Drift streams for real-time database updates
- Implement Clean Architecture with proper separation of concerns
- All money calculations must use integer cents
- CurrencyService for all money display formatting

### Project Structure Notes
- Align with existing supplier reports pattern (8-14 through 8-18)
- Use similar structure to customer statement reports (8-12)
- Follow established file organization in lib/features/reports/
- Maintain consistency with existing report implementations
- Implementation path: `lib/features/reports/presentation/screens/supplier_statement_report_screen.dart`
- Bloc path: `lib/features/reports/presentation/bloc/supplier_statement_report_bloc.dart`
- Repository path: `lib/features/reports/data/repositories/supplier_statement_repository.dart`

### Previous Story Intelligence
From story 8-18 (supplier aging reports):
- Use similar RealtimeBloc pattern for supplier data streaming
- Follow established PDF export patterns from other reports
- Maintain consistent UI patterns with supplier report family
- Use same filtering and date range selection approach

### References
- Supplier aging reports implementation (8-18) for pattern reference
- Customer statement reports (8-12) for statement structure
- Project context for mandatory implementation patterns
- UI architecture specification for screen structure requirements

## Dev Agent Record

### Agent Model Used
Cascade (Penguin Alpha) - Scrum Master Agent

### Debug Log References
Workflow executed via create-story workflow with comprehensive context analysis

### Completion Notes List
- Story created with binding constraints enforcement
- Technical requirements aligned with TAPIX specifications
- Implementation patterns consistent with existing supplier reports
- All mandatory acceptance criteria included

### File List
- Story file: 8-19-supplier-statement-reports.md
- References: TAPIX_REBUILD_SPECIFICATION.md, project-context.md, UI architecture
- Related implementations: 8-14 through 8-18 supplier reports
