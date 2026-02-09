# Story 7.5: Journal Entries & General Ledger

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

As a Accountant,
I want the system to generate journal entries,
so that the books are always balanced.

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

### Accounting System Requirements
- **Double-Entry Bookkeeping**: Every transaction MUST have balanced debits and credits
- **Chart of Accounts**: Standard account structure (Assets, Liabilities, Equity, Revenue, Expenses)
- **Journal Entry Structure**: Multiple lines per entry with account, debit/credit, amount, reference
- **Automatic Journal Generation**: Sales, purchases, expenses, payments create journal entries automatically
- **Real-Time Balance Updates**: Account balances update instantly when entries are posted

### Field Specifications (from Rebuild Spec)
- **Money Fields**: Must use INTEGER cents (debit_cents, credit_cents, balance_cents)
- **Date Fields**: ISO 8601 format with timezone support
- **Reference Fields**: Link to source documents (invoices, receipts, etc.)
- **Account Fields**: Account codes following standard chart of accounts
- **Validation**: Required fields, balanced entry validation, business rule validation
- **Real-Time Updates**: UI must update automatically on data changes

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Service Dependencies**: Use appropriate services from Core Services Inventory
- **Cross-Feature Integration**: Journal entries generated from Sales, Purchases, Expenses, Payments
- **Audit Trail**: All entries must be traceable to source transactions
- **CurrencyService**: ALL money displays must use CurrencyService for proper formatting
- **PDF Export**: Journal entries and trial balance must support PDF generation and printing
- **Existing Tables**: Use existing Drift tables (Accounts, JournalEntries, JournalEntryLines) - DO NOT recreate

## Implementation Requirements

### Screen Requirements (from UI Architecture)
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Use GoRouter patterns exactly as specified [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]

### Database Schema Requirements
- **Accounts table**: Already exists with accountCode, accountName, accountType, balanceCents
- **JournalEntries table**: Already exists with entryNumber, entryDate, status, entryType, sourceTable, sourceId
- **JournalEntryLines table**: Already exists with debitCents, creditCents, accountId references
- **AccountingPeriods table**: Already exists for period management
- **DO NOT CREATE NEW TABLES** - Use existing accounting tables in `lib/core/database/tables/accounting.dart`
- **Use existing AccountingDao**: Extend `lib/core/database/daos/accounting_dao.dart` for additional methods
- **MoneyConverter**: Use existing MoneyConverter for integer cents fields

### Testing Requirements
- **Unit Tests**: 90%+ coverage for Blocs and Services
- **Widget Tests**: Critical UI components
- **Integration Tests**: Journal entry creation and balance calculations
- **Platform Testing**: ALL target platforms
- **Language Testing**: English, Arabic (RTL), French
- **Theme Testing**: Light AND Dark themes

### Performance Requirements
- **Large Data Handling**: Must handle thousands of journal entries smoothly
- **Real-Time Performance**: <50ms for database updates to reflect in UI
- **Memory Management**: No memory leaks with large datasets
- **Query Performance**: Optimized queries for balance calculations and reports

## Acceptance Criteria

1. Double-entry structure is enforced
2. Entries persist to Drift and update UI in realtime

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
- AC-BL-001: Double-entry validation enforced (debits = credits)
- AC-BL-002: Account balances update in real-time
- AC-BL-003: Journal entries link to source documents
- AC-BL-004: Money calculations accurate (integer cents)

### Accounting Acceptance Criteria (MANDATORY)
- AC-ACC-001: Chart of accounts structure implemented
- AC-ACC-002: Automatic journal generation for transactions
- AC-ACC-003: Balance sheet equation maintained (Assets = Liabilities + Equity)
- AC-ACC-004: Audit trail preserved for all entries

## Tasks / Subtasks

### ENFORCEMENT TASKS (MANDATORY)
- [ ] COMPLIANCE-001: Verify RealtimeBloc pattern implementation (AC-TECH-002)
- [ ] COMPLIANCE-002: Verify all text is localized (AC-TECH-006)
- [ ] COMPLIANCE-003: Verify integer cents for money (AC-TECH-003)
- [ ] COMPLIANCE-004: Verify CurrencyService usage (AC-BL-004)
- [ ] COMPLIANCE-005: Verify responsive design (AC-TECH-004)
- [ ] COMPLIANCE-006: Verify GoRouter navigation (AC-UI-003)
- [ ] COMPLIANCE-007: Verify semantic colors (AC-UI-001)
- [ ] COMPLIANCE-008: Verify database integration (AC-BL-002)

### TECHNICAL IMPLEMENTATION TASKS
- [ ] TECH-001: Implement Clean Architecture structure (AC-TECH-001)
- [ ] TECH-002: Set up Bloc with real-time database streams (AC-TECH-002)
- [ ] TECH-003: Configure responsive layout breakpoints (AC-TECH-004)
- [ ] TECH-004: Implement theme support (Light/Dark) (AC-TECH-005)
- [ ] TECH-005: Add localization support (EN/AR/FR) (AC-TECH-006)
- [ ] TECH-006: Test on all target platforms (AC-TECH-007)

### DATABASE IMPLEMENTATION TASKS
- [ ] DB-001: Create journal_entries table with proper schema (AC-BL-001)
- [ ] DB-002: Create journal_entry_lines table with constraints (AC-BL-001)
- [ ] DB-003: Create accounts table with chart of accounts structure (AC-ACC-001)
- [ ] DB-004: Add foreign key constraints and indexes (AC-BL-002)
- [ ] DB-005: Implement database triggers for balance updates (AC-BL-002)

### BUSINESS LOGIC TASKS
- [ ] BL-001: Implement double-entry validation logic (AC-ACC-002)
- [ ] BL-002: Create journal entry service with balance calculations (AC-BL-002)
- [ ] BL-003: Implement automatic journal generation for sales/purchases (AC-ACC-002)
- [ ] BL-004: Add account balance real-time updates (AC-BL-002)
- [ ] BL-005: Implement audit trail functionality (AC-ACC-004)

### UI/UX IMPLEMENTATION TASKS
- [ ] UI-001: Design responsive layout (mobile/tablet/desktop) (AC-UI-004)
- [ ] UI-002: Apply semantic color scheme (AC-UI-001)
- [ ] UI-003: Implement GoRouter navigation (AC-UI-003)
- [ ] UI-004: Test accessibility and contrast (AC-UI-005)
- [ ] UI-005: Verify RTL layout for Arabic (AC-TECH-006)

### TESTING TASKS
- [ ] TEST-001: Write unit tests for Blocs (90%+ coverage) (AC-TECH-008)
- [ ] TEST-002: Write widget tests for UI components (AC-TECH-008)
- [ ] TEST-003: Write integration tests for journal entry flows (AC-TECH-008)
- [ ] TEST-004: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [ ] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [ ] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)
- [ ] TEST-007: Test double-entry validation edge cases (AC-ACC-002)
- [ ] TEST-008: Test balance calculation accuracy (AC-BL-004)

### FEATURE TASKS
- [ ] TASK-001: Implement Chart of Accounts management (AC-ACC-001)
  - [ ] SUBTASK-001.1: Create accounts CRUD operations (extend existing AccountingDao)
  - [ ] SUBTASK-001.2: Implement account hierarchy (parent-child relationships)
  - [ ] SUBTASK-001.3: Add account type validation (Asset/Liability/Equity/Revenue/Expense)
- [ ] TASK-002: Implement Journal Entry creation and management (AC-ACC-002)
  - [ ] SUBTASK-002.1: Create journal entry form with balanced validation
  - [ ] SUBTASK-002.2: Implement journal entry list with real-time updates
  - [ ] SUBTASK-002.3: Add journal entry detail view with audit trail
- [ ] TASK-003: Implement automatic journal generation (AC-ACC-002)
  - [ ] SUBTASK-003.1: Generate journal entries from sales transactions (hook into SaleFormBloc)
  - [ ] SUBTASK-003.2: Generate journal entries from purchase transactions (hook into PurchaseFormBloc)
  - [ ] SUBTASK-003.3: Generate journal entries from expense transactions (extend ExpenseFormBloc)
  - [ ] SUBTASK-003.4: Generate journal entries from payment transactions
- [ ] TASK-004: Implement General Ledger reporting (AC-BL-002)
  - [ ] SUBTASK-004.1: Create general ledger list with date filtering
  - [ ] SUBTASK-004.2: Implement account balance calculations
  - [ ] SUBTASK-004.3: Add trial balance generation
- [ ] TASK-005: Implement PDF Export and Printing (CRITICAL)
  - [ ] SUBTASK-005.1: Create JournalPdfService following existing PDF service pattern
  - [ ] SUBTASK-005.2: Support thermal printer (58mm/80mm) and A4 formats
  - [ ] SUBTASK-005.3: Multi-language PDF support (EN/AR/FR) with RTL for Arabic
  - [ ] SUBTASK-005.4: Add sharing capability for journal entries and reports

## Dev Notes

### ENFORCEMENT NOTES (MANDATORY)
- **CRITICAL**: AI Models MUST load TAPIX_REBUILD_SPECIFICATION.md and treat as BINDING LAW
- **CRITICAL**: AI Models MUST load UI architecture specification and follow exactly
- **CRITICAL**: Every implementation MUST explain how constraints are satisfied
- **FAILURE TO FOLLOW BINDING CONSTRAINTS IS NOT ACCEPTABLE**

### Accounting System Design
- **Double-Entry Principle**: Every financial transaction must affect at least two accounts
- **Debit/Credit Rules**: Assets and Expenses increase with debits, Liabilities, Equity, and Revenue increase with credits
- **Chart of Accounts**: Standard 5-digit account codes (10000-Assets, 20000-Liabilities, 30000-Equity, 40000-Revenue, 50000-Expenses)
- **Balance Sheet Equation**: Assets = Liabilities + Equity must always balance
- **Trial Balance**: Sum of all debits must equal sum of all credits

### Database Schema Details
**IMPORTANT**: Tables already exist in `lib/core/database/tables/accounting.dart` - DO NOT recreate!

**Existing Tables Structure:**
- **Accounts**: Uses MoneyConverter for balanceCents, has accountCode (unique), accountType enum
- **JournalEntries**: Has entryNumber (unique), status (draft/posted/voided), entryType enum, sourceTable/sourceId for auto-generation
- **JournalEntryLines**: Uses MoneyConverter for debitCents/creditCents, proper FK constraints
- **AccountingPeriods**: For period management with closed/open status

**Key Implementation Points:**
- Use existing MoneyConverter for all money fields (integer cents)
- Follow existing enum patterns: AccountTypeEnum, JournalEntryTypeEnum, JournalEntryStatusEnum
- Use existing sourceTable/sourceId pattern for automatic journal generation
- Extend existing AccountingDao - do not create new DAO

### Service Integration Points
- **SalesService**: Generate journal entries for sales transactions (use existing SalePdfService pattern)
- **PurchaseService**: Generate journal entries for purchase transactions (use existing PurchasePdfService pattern)
- **ExpenseService**: Generate journal entries for expense transactions (already exists in lib/features/expenses)
- **PaymentService**: Generate journal entries for customer/supplier payments
- **JournalService**: Core service for journal entry management and balance calculations
- **CurrencyService**: MUST use for all money formatting (see lib/core/services/currency_service.dart)
- **PdfService**: Create JournalPdfService following existing pattern (sale_pdf_service.dart, purchase_pdf_service.dart)

### Architecture Notes
- **JournalService**: Central service for all journal entry operations (create new)
- **AccountRepository**: Repository pattern for account data access (create new)
- **JournalRepository**: Repository pattern for journal entry data access (create new)
- **RealtimeBloc**: All Blocs must extend RealtimeBloc for real-time updates
- **Database Streams**: Use Drift streams for real-time balance updates
- **Existing Pattern**: Follow ExpenseFormBloc pattern for form handling
- **Currency Integration**: Use CurrencyService for all money displays (see expense implementation)
- **PDF Pattern**: Follow SalePdfService pattern for PDF generation

### Project Structure Notes
```
lib/features/accounting/
├── data/
│   ├── datasources/
│   │   ├── account_local_datasource.dart
│   │   └── journal_local_datasource.dart
│   └── repositories/
│       ├── account_repository_impl.dart
│       └── journal_repository_impl.dart
├── domain/
│   ├── entities/
│   │   ├── account_entity.dart
│   │   ├── journal_entry_entity.dart
│   │   └── journal_line_entity.dart
│   ├── repositories/
│   │   ├── account_repository_interface.dart
│   │   └── journal_repository_interface.dart
│   └── services/
│       └── journal_service.dart
└── presentation/
    ├── bloc/
    │   ├── accounts_bloc.dart
    │   ├── journal_entries_bloc.dart
    │   └── journal_entry_form_bloc.dart
    ├── screens/
    │   ├── journal_entries_list_screen.dart
    │   ├── journal_entry_form_screen.dart
    │   └── journal_entry_detail_screen.dart
    └── widgets/
        ├── journal_entry_card.dart
        └── account_selector.dart
```

### References
- [Source: TAPIX_REBUILD_SPECIFICATION.md#Technical-Architecture]
- [Source: TAPIX_REBUILD_SPECIFICATION.md#Database-Schema-Requirements]
- [Source: project-context.md#Real-Time-State-Management]
- [Source: project-context.md#Money-Calculations]
- [Source: 2-1-ui-architecture-specification.md#Component-Architecture]

### Existing Implementation References (CRITICAL)
- **Database Tables**: `lib/core/database/tables/accounting.dart` (Accounts, JournalEntries, JournalEntryLines)
- **Database DAO**: `lib/core/database/daos/accounting_dao.dart` (extend existing methods)
- **Money Converter**: `lib/core/database/converters/money_converter.dart` (use for all money fields)
- **Currency Service**: `lib/core/services/currency_service.dart` (MUST use for displays)
- **RealtimeBloc**: `lib/core/bloc/realtime_bloc.dart` (all Blocs must extend)
- **Expense Pattern**: `lib/features/expenses/presentation/bloc/expense_form_bloc.dart` (follow form pattern)
- **PDF Pattern**: `lib/features/sales/presentation/services/sale_pdf_service.dart` (follow for PDF generation)

## Dev Agent Record

### Agent Model Used
Cascade (Penguin Alpha) - Advanced AI coding assistant

### Debug Log References
- Workflow executed: create-story workflow v6.0.0-alpha.23
- Story context loaded from: TAPIX_EPICS_AND_STORIES.md
- Project constraints loaded from: project-context.md
- Technical specifications loaded from: TAPIX_REBUILD_SPECIFICATION.md

### Completion Notes List
- Story 7.5 created with comprehensive accounting system requirements
- Double-entry bookkeeping principles enforced
- Real-time balance updates specified
- Integration points defined for all transaction types
- Database schema designed with proper constraints
- UI/UX requirements aligned with project standards

### File List
- Primary story file: 7-5-journal-entries-general-ledger.md
- Source epics: TAPIX_EPICS_AND_STORIES.md
- Project context: project-context.md
- Technical spec: TAPIX_REBUILD_SPECIFICATION.md
- Sprint status: sprint-status.yaml (to be updated)
