# Story 8.13: Customer Analysis Reports

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
I want customer analysis reports,
so that I can understand buying patterns.

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

1. [x] Frequency/value analysis with date range
2. [x] Updates in realtime

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
- [ ] FEATURE-001: Create customer analysis data repository (AC: 1, 2)
  - [ ] SUBTASK-001-001: Implement CustomerAnalysisRepository with Drift queries
  - [ ] SUBTASK-001-002: Add frequency analysis queries (purchase count, avg days between purchases)
  - [ ] SUBTASK-001-003: Add value analysis queries (avg order value, total spent, profitability)
  - [ ] SUBTASK-001-004: Implement date range filtering for analysis
- [ ] FEATURE-002: Create CustomerAnalysisBloc with RealtimeBloc pattern (AC: 2)
  - [ ] SUBTASK-002-001: Extend existing CustomerReportsBloc or create separate CustomerAnalysisBloc
  - [ ] SUBTASK-002-002: Add events for date range changes and refresh
  - [ ] SUBTASK-002-003: Add states for loading, success, and error handling
- [ ] FEATURE-003: Implement Customer Analytics UI (AC: 1, 2)
  - [ ] SUBTASK-003-001: DECISION: Extend existing Analytics tab in CustomerReportsScreen OR create new CustomerAnalysisReportsScreen
  - [ ] SUBTASK-003-002: Create responsive layout with date range picker
  - [ ] SUBTASK-003-003: Display frequency metrics (purchase count, avg frequency)
  - [ ] SUBTASK-003-004: Display value metrics (avg order value, total revenue)
  - [ ] SUBTASK-003-005: Add customer segmentation visualization (RFM segments)
- [ ] FEATURE-004: Implement export functionality (AC: 1)
  - [ ] SUBTASK-004-001: Add PDF export for analysis reports
  - [ ] SUBTASK-004-002: Add Excel export with analysis data
  - [ ] SUBTASK-004-003: Include date range and generation timestamp

### IMPLEMENTATION DECISION REQUIRED
**Note**: CustomerReportsScreen already has an "Analytics" tab (3rd tab). The developer must decide:
1. **Option A**: Enhance the existing Analytics tab with detailed analysis metrics
2. **Option B**: Create a separate CustomerAnalysisReportsScreen for comprehensive analysis

**Recommendation**: Choose Option A to maintain consistency with existing UI pattern, unless the analysis is too complex for a tab view.

### Previous Story Intelligence

**From Customer Reports Implementation (8-8 through 8-12):**
- **Bloc Pattern**: CustomerReportsBloc extends RealtimeBloc with CustomerReportsEvent base class
- **Data Models**: Follow pattern like CustomerStatementItem, CustomerAgingItem with specific analysis fields
- **Screen Structure**: CustomerReportsScreen uses DefaultTabController with 3 tabs (Statement, Aging, Analytics)
- **Export Pattern**: Uses JournalPdfService for PDF generation, share functionality built-in
- **Date Range**: ReportDateRange widget with CustomerReportsDateRangeChanged event
- **Currency**: All amounts stored as cents (amountCents, runningBalanceCents, totalCents)
- **Real-time Updates**: BlocBuilder<RealtimeState<CustomerReportsData>> pattern

**Key Files to Reference:**
- `lib/features/reports/presentation/bloc/customer_reports_bloc.dart` - Bloc implementation pattern
- `lib/features/reports/presentation/screens/customer_reports_screen.dart` - Screen structure
- Uses `sl<CustomerReportsBloc>()` for dependency injection
- Import pattern: `'../../../../core/bloc/realtime_bloc.dart'`

### Git Intelligence Summary

**Recent Customer Reports Commits:**
- Customer reports follow unified bloc pattern with shared CustomerReportsData
- Export functionality uses existing PDF service infrastructure
- All money fields consistently use integer cents
- Real-time updates implemented via Drift streams

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
- **Screen Names**: Use exact screen names from rebuild spec (e.g., `ProductsMainScreen`, `BulkProductFormScreen`)
- **Field Lists**: Include ALL fields from specification (e.g., 12 product fields from section 5.3)
- **Business Rules**: Implement all validations and rules from specification
- **Service Integration**: Use services from Core Services Inventory (section 8)
- **Database Schema**: Follow exact schema from Database Requirements (section 9)

### Customer Analysis Metrics Specification
**Frequency Analysis Metrics:**
- `purchaseCount`: Total number of purchases within date range
- `avgDaysBetweenPurchases`: Average days between consecutive purchases
- `purchaseFrequency`: High/Medium/Low based on industry benchmarks
- `lastPurchaseDate`: Most recent purchase date
- `daysSinceLastPurchase`: Days since last purchase

**Value Analysis Metrics:**
- `avgOrderValueCents`: Average order value in cents
- `totalSpentCents`: Total amount spent within date range
- `largestOrderCents`: Largest single order value
- `profitabilityCents`: Estimated profit (revenue - cost of goods)
- `customerLifetimeValueCents`: Predicted lifetime value

**Segmentation Metrics:**
- `recencyScore`: 1-5 score based on last purchase
- `frequencyScore`: 1-5 score based on purchase frequency
- `monetaryScore`: 1-5 score based on total spending
- `rfmSegment`: RFM segment (Champions, Loyal, At Risk, etc.)

**Data Models to Create:**
```dart
class CustomerAnalysisItem {
  final int customerId;
  final String customerName;
  final String segment;
  final int purchaseCount;
  final double avgDaysBetweenPurchases;
  final int avgOrderValueCents;
  final int totalSpentCents;
  final int profitabilityCents;
  final String rfmSegment;
  final DateTime? lastPurchaseDate;
}
```

### Drift Query Patterns for RFM Analysis
**Recency Query (days since last purchase):**
```sql
SELECT c.id, c.name, 
  julianday('now') - julianday(MAX(s.date)) as days_since_last_purchase
FROM customers c
LEFT JOIN sales s ON c.id = s.customer_id
WHERE s.date BETWEEN :startDate AND :endDate
GROUP BY c.id
```

**Frequency Query (purchase count and avg days between):**
```sql
SELECT c.id, COUNT(s.id) as purchase_count,
  CASE 
    WHEN COUNT(s.id) > 1 THEN 
      (julianday(MIN(s.date)) - julianday(MAX(s.date))) / (COUNT(s.id) - 1)
    ELSE 0 
  END as avg_days_between
FROM customers c
LEFT JOIN sales s ON c.id = s.customer_id
WHERE s.date BETWEEN :startDate AND :endDate
GROUP BY c.id
```

**Monetary Query (total and average values):**
```sql
SELECT c.id, 
  SUM(s.total_cents) as total_spent_cents,
  AVG(s.total_cents) as avg_order_value_cents
FROM customers c
LEFT JOIN sales s ON c.id = s.customer_id
WHERE s.date BETWEEN :startDate AND :endDate
GROUP BY c.id
```

### Architecture Notes
- **Reporting Pattern**: Follow existing customer reports pattern (8-8, 8-9, 8-10, 8-11, 8-12)
- **Data Analysis**: Use customer transaction history for frequency/value calculations
- **Real-time Updates**: Leverage existing customer data streams for live updates
- **Export Integration**: Reuse existing PDF/Excel export infrastructure from other reports

### Project Structure Notes

**Feature Location**: `lib/features/reports/presentation/screens/customer_analysis_reports_screen.dart`
**Bloc Location**: `lib/features/reports/presentation/bloc/customer_analysis_bloc.dart`
**Repository Location**: `lib/features/reports/data/repositories/customer_analysis_repository.dart`

**Alignment with existing reports structure**:
- Follow pattern from `customer_sales_reports_screen.dart` (8-10)
- Reuse export utilities from `customer_statement_reports_screen.dart` (8-12)
- Use similar date range filtering as `customer_aging_reports_screen.dart` (8-11)

### References

- [Source: TAPIX_EPICS_AND_STORIES.md#STORY-08-13]
- [Source: project-context.md#Real-Time-State-Management]
- [Source: project-context.md#Money-Calculations]
- [Source: project-context.md#Responsive-Design]
- [Source: project-context.md#Localization]
- [Source: project-context.md#Customers-Module] - CustomerRepository, CustomerLoyaltyBloc patterns
- [Source: project-context.md#Customer-Analysis-Requirements] - Use existing customer data streams

## Dev Agent Record

### Agent Model Used

Cascade (Penguin Alpha)

### Debug Log References

### Completion Notes List

### File List
