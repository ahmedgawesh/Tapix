# Story 8.16: supplier-credit-balance-reports

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
I want supplier credit balance reports,
so that I can track supplier credits.

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

### Supplier Credit Balance Data Requirements
- **Credit Balance Definition**: Amount suppliers owe us or credits we have with them (negative balance in supplier_transactions)
- **Balance Calculation**: Sum of all transactions where balance is negative (we are owed money or have credits)
- **Transaction Logic**: 
  - Purchases (positive amount_cents) → decrease credit balance (we owe them)
  - Purchase Returns (negative amount_cents, type 'credit_note') → increase credit balance (they owe us)
  - Supplier Payments (negative amount_cents, type 'payment') → increase credit balance (we overpaid or they owe us)
  - Supplier Refunds (negative amount_cents, type 'payment') → increase credit balance
  - Supplier Discounts (negative amount_cents, type 'discount') → increase credit balance
- **Filter Criteria**: Only show suppliers with negative net balance (debit_balance_cents < 0)
- **SQL Logic**: Use `HAVING debit_balance_cents < 0` to filter suppliers who owe us money
- **Date Range**: User-selectable period for transaction inclusion
- **Real-time Updates**: Balance updates when any transaction changes
- **Supplier Information**: Name, contact details, current credit balance, transaction count

### Field Specifications
- **Money Fields**: Must use INTEGER cents (credit_balance_cents, total_payments_cents, total_refunds_cents)
- **Date Fields**: ISO date strings for consistent formatting and filtering
- **Supplier References**: Link to suppliers table via supplier_id
- **Transaction References**: Link to relevant transaction tables (purchases, payments)
- **Validation**: Required fields, date range validation, business rule validation
- **Permissions**: Role-based access control (Owner, Manager, Cashier, Salesperson)
- **Real-Time Updates**: UI must update automatically on data changes

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Service Dependencies**: Use appropriate services from Core Services Inventory
- **Cross-Feature Integration**: Follow interaction patterns from specification
- **Supplier Module**: Use existing SupplierRepository and supplier data patterns
- **Reporting Module**: Follow established reporting patterns from supplier balance reports (8-14) and supplier debit balance reports (8-15)

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
- **Large Data Handling**: Must handle thousands of supplier records smoothly
- **Real-Time Performance**: <50ms for database updates to reflect in UI
- **Memory Management**: No memory leaks with large datasets

## Acceptance Criteria

1. [ ] Supplier credit balance report shows all suppliers with credit balances
2. [ ] Date range filter correctly filters transactions for balance calculation
3. [ ] Real-time updates when supplier transactions change
4. [ ] Export functionality (PDF/Excel) supports filtered data
5. [ ] Responsive design works on all screen sizes

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

### Report-Specific Acceptance Criteria
- AC-RPT-001: Supplier credit balances calculated from transaction history (payments, refunds, discounts, returns, purchases)
- AC-RPT-002: Credit balance filter shows only suppliers with negative balances (debit_balance_cents < 0) indicating they owe us money
- AC-RPT-003: Report updates in real-time when any supplier transaction changes
- AC-RPT-004: Supports date range filtering for credit balance calculations
- AC-RPT-005: Export to PDF and Excel with proper formatting
- AC-RPT-006: Print functionality works for both A4 and thermal printers

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
- [ ] BL-001: Implement supplier credit balance calculation logic (AC-BL-001)
- [ ] BL-002: Add role-based permission checks (AC-BL-002)
- [ ] BL-003: Configure real-time data synchronization (AC-BL-003)
- [ ] BL-004: Implement money calculations in cents (AC-BL-004)

### FEATURE TASKS
- [ ] Task 1: Supplier Credit Balance Data Layer (AC: BL-001, BL-004)
  - [ ] Subtask 1.1: Create SupplierCreditBalanceRepository with Drift queries
  - [ ] Subtask 1.2: Implement credit balance calculation from transaction history
  - [ ] Subtask 1.3: Add date range filtering for balance calculations
- [ ] Task 2: Supplier Credit Balance Bloc Layer (AC: TECH-002, BL-003)
  - [ ] Subtask 2.1: Create SupplierCreditBalanceBloc extending RealtimeBloc
  - [ ] Subtask 2.2: Implement events for date range filtering
  - [ ] Subtask 2.3: Add real-time stream subscriptions for transaction changes
- [ ] Task 3: Supplier Credit Balance UI Layer (AC: UI-001, UI-002, UI-004)
  - [ ] Subtask 3.1: Create SupplierCreditBalanceScreen with responsive layout
  - [ ] Subtask 3.2: Implement date range picker with localization
  - [ ] Subtask 3.3: Add supplier list with credit balance display
  - [ ] Subtask 3.4: Implement export functionality (PDF/Excel)
- [ ] Task 4: Integration and Navigation (AC: UI-003, AC-TECH-001)
  - [ ] Subtask 4.1: Add route to app_router.dart for supplier credit balance reports
  - [ ] Subtask 4.2: Integrate with existing reports navigation structure
  - [ ] Subtask 4.3: Add permissions checks for report access

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
- **Screen Names**: Use exact screen names from rebuild spec (e.g., `SupplierCreditBalanceReportsScreen`)
- **Field Lists**: Include ALL fields from specification (supplier name, credit balance, transaction count, etc.)
- **Business Rules**: Implement all validations and rules from specification
- **Service Integration**: Use services from Core Services Inventory (section 8)
- **Database Schema**: Follow exact schema from Database Requirements (section 9)

### Previous Story Intelligence
From story 8-15 (supplier-debit-balance-reports):
- **Successful Patterns**: Established supplier balance calculation patterns using transaction aggregation
- **Repository Pattern**: SupplierDebitBalanceRepository provides watchSupplierDebitBalances() stream
- **UI Pattern**: Responsive supplier list with balance cards and export functionality
- **Testing Approach**: 40 tests passing with comprehensive coverage of balance calculations
- **Key Learning**: Use Drift's SUM() aggregation for efficient balance calculations
- **Integration Points**: Successfully integrated with existing SupplierRepository
- **Credit vs Debit**: Credit balances are the inverse of debit balances (what suppliers owe us vs what we owe suppliers)
- **SQL Pattern**: Use `HAVING debit_balance_cents < 0` for credit balances (vs `HAVING debit_balance_cents > 0` for debit)
- **Display Logic**: Show credit balance as positive amount for better UX (e.g., "Credit: $500" instead of "-$500")

From story 8-14 (supplier-balance-reports):
- **Base Patterns**: Established supplier balance calculation patterns using transaction aggregation
- **Repository Pattern**: SupplierBalanceRepository provides watchSupplierBalances() stream
- **UI Pattern**: Responsive supplier list with balance cards and export functionality
- **Testing Approach**: 34 tests passing with comprehensive coverage of balance calculations
- **Key Learning**: Use Drift's SUM() aggregation for efficient balance calculations

### Supplier Module Integration (CRITICAL)
**From project-context.md Suppliers Module (lines 2476-2872):**
- **Balance Calculation Pattern**: Use supplier_transactions table for all balance changes
- **Repository Methods**: 
  - `SupplierRepository.recordTransaction()` for recording transactions
  - `SupplierRepository.updateSupplierBalance()` for balance updates
- **Transaction Types**: 'purchase', 'purchase_return', 'payment', 'discount', 'credit_note'
- **Credit Balance Formula**: Credit balance = ABS(SUM(amount_cents)) where SUM(amount_cents) < 0 (negative balance indicates supplier owes us money)
- **Real-time Updates**: Balance updates automatically when supplier_transactions table changes

### Currency Service Requirements (MANDATORY)
**From project-context.md Currency Settings (lines 1242-1337):**
- **ALL money displays MUST use CurrencyService** - NO hardcoded symbols
- **Required for**: Supplier credit balances, report totals, all monetary values
- **Implementation**: `currencyService.format(balanceCents)` for every money display
- **Dynamic Updates**: Currency changes reflect immediately across all screens

### Accounting Integrity Requirements (MANDATORY)
**From project-context.md Accounting Integrity (lines 1066-1160):**
- **Single Source of Truth**: SupplierRepository internally uses AccountingRepository for all balance calculations
- **Transaction Flow**: Supplier transactions go through TransactionOrchestrator before recording
- **Immutable Transactions**: Never modify posted transactions, create reversal entries
- **Balance Changes**: Always through journal entries, never direct balance updates
- **Audit Trail**: Every balance change must be tracked in audit logs
- **Note**: For supplier-specific reports, use SupplierRepository API which handles accounting integrity internally

### Architecture Notes
- **Data Layer**: Extend existing supplier balance patterns for credit-specific filtering
- **Bloc Layer**: Follow RealtimeBloc pattern from project-context.md
- **UI Layer**: Use established responsive patterns from supplier balance reports
- **Testing Standards**: Follow comprehensive testing approach from previous supplier reports
- **Export Patterns**: Reuse PDF/Excel export patterns from other reporting screens

### SQL Implementation Example
```sql
-- Credit balance query (adapted from 8-15 with inverted HAVING clause)
SELECT 
  s.id AS supplier_id,
  s.name AS supplier_name,
  s.phone AS phone,
  COALESCE(SUM(CASE WHEN st.amount_cents > 0 THEN st.amount_cents ELSE 0 END), 0) AS total_purchases_cents,
  COALESCE(SUM(CASE WHEN st.amount_cents < 0 AND st.transaction_type = 'credit_note' THEN ABS(st.amount_cents) ELSE 0 END), 0) AS total_returns_cents,
  COALESCE(SUM(CASE WHEN st.amount_cents < 0 AND st.transaction_type = 'payment' THEN ABS(st.amount_cents) ELSE 0 END), 0) AS total_payments_cents,
  COALESCE(SUM(CASE WHEN st.amount_cents < 0 AND st.transaction_type = 'discount' THEN ABS(st.amount_cents) ELSE 0 END), 0) AS total_discounts_cents,
  COALESCE(SUM(st.amount_cents), 0) AS debit_balance_cents,
  COUNT(st.id) AS transaction_count,
  MAX(st.transaction_date) AS last_transaction_at
FROM suppliers s
LEFT JOIN supplier_transactions st 
  ON st.supplier_id = s.id
  AND st.transaction_date >= ?
  AND st.transaction_date <= ?
WHERE s.is_active = 1
GROUP BY s.id
HAVING debit_balance_cents < 0  -- KEY: Negative balance = supplier owes us
ORDER BY debit_balance_cents ASC  -- Show largest credits first
```
Note: Display balance as ABS(debit_balance_cents) for user-friendly positive amounts

### Project Structure Notes

- **Feature Location**: `lib/features/reports/presentation/screens/supplier_credit_balance_reports_screen.dart`
- **Bloc Location**: `lib/features/reports/presentation/bloc/supplier_credit_balance_bloc.dart`
- **Repository Location**: `lib/features/reports/data/repositories/supplier_credit_balance_repository.dart`
- **Integration**: Aligns with existing reports module structure and navigation

### References

- Cite all technical details with source paths and sections, e.g. [Source: docs/<file>.md#Section]

## Dev Agent Record

### Agent Model Used

Cascade (Windsurf)

### Debug Log References

- flutter analyze: 0 issues found
- flutter test: 41/41 tests passing

### Completion Notes List

- Followed exact same patterns as story 8-15 (supplier-debit-balance-reports)
- RealtimeBloc pattern: SupplierCreditBalanceReportBloc extends RealtimeBloc ✅
- Integer cents: All money fields use integer cents ✅
- CurrencyService: All money displays use cs.formatCents() ✅
- Localization: All text uses .tr() method, 3 languages (EN/AR/FR) ✅
- Responsive design: LayoutBuilder with isWide breakpoints ✅
- Date range: Reuses DateRangeSelector with all presets ✅
- PDF: 3-language PDF with company header, table, totals footer ✅
- Print/Share: Print and share buttons in AppBar ✅
- Themes: Uses colorScheme for Light/Dark theme support ✅
- Semantic colors: Green for credit/receivable, Error (red) for purchases, Primary for payments ✅
- GoRouter: Route at /reports/supplier-credit-balance ✅
- DI: Registered in injection_container.dart ✅
- Reports hub: Added tile under Supplier Reports section ✅
- Audit logging: Print and share actions logged ✅
- SQL query: HAVING net_balance_cents < 0 filters only credit suppliers ✅
- Balance calculation: SUM(amount_cents) from supplier_transactions, negative = credit (supplier owes us) ✅
- Display logic: creditBalanceCents = ABS(net_balance_cents) for user-friendly positive amounts ✅

### File List

- `lib/features/reports/presentation/bloc/supplier_credit_balance_report_bloc.dart` (NEW)
- `lib/features/reports/presentation/screens/supplier_credit_balance_report_screen.dart` (NEW)
- `lib/features/reports/services/supplier_credit_balance_pdf_service.dart` (NEW)
- `lib/core/di/injection_container.dart` (MODIFIED - added DI registration + import)
- `lib/core/router/app_router.dart` (MODIFIED - added route + import)
- `lib/features/reports/presentation/screens/reports_hub_screen.dart` (MODIFIED - added report tile)
- `assets/translations/en.json` (MODIFIED - added 5 localization keys)
- `assets/translations/ar.json` (MODIFIED - added 5 localization keys)
- `assets/translations/fr.json` (MODIFIED - added 5 localization keys)
- `test/features/reports/presentation/bloc/supplier_credit_balance_report_bloc_test.dart` (NEW - 41 tests)
