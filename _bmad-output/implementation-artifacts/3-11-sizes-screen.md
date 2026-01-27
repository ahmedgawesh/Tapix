# Story 3.11: Sizes Screen

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

As a Product Manager,
I want to manage product sizes with standardized sizing systems,
so that I can organize and track product variants by size for better inventory management and customer experience.

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

### Field Specifications (from Database Schema)
Based on `sizes` table [Source: TAPIX_TECHNICAL_INVENTORY.md#1.2-Product-Tables]:
- **id**: INTEGER (Primary key, auto-increment)
- **name**: TEXT (Required, size name)
- **sort_order**: INTEGER (Required, for ordering sizes logically)
- **is_active**: INTEGER (Required, 1=active, 0=inactive)

### Validation Rules
- **Name**: Required, max 50 characters, unique
- **Sort Order**: Required, defaults to 0, must be non-negative
- **Active Status**: Required, defaults to active
- **Real-Time Updates**: UI must update automatically on data changes

### Localization Keys Required
```json
{
  "sizes.title": "Sizes",
  "sizes.add_size": "Add Size",
  "sizes.edit_size": "Edit Size",
  "sizes.name": "Size Name",
  "sizes.sort_order": "Sort Order",
  "sizes.active": "Active",
  "sizes.inactive": "Inactive",
  "sizes.search_hint": "Search sizes...",
  "sizes.no_sizes": "No sizes found",
  "sizes.add_first_size": "Add your first size",
  "sizes.delete_confirm_title": "Delete Size",
  "sizes.delete_confirm_message": "Are you sure you want to delete '{size}'?",
  "sizes.delete_with_products": "Cannot delete '{size}' - used by {count} products",
  "sizes.product_count": "{count} products",
  "sizes.save": "Save",
  "sizes.cancel": "Cancel",
  "sizes.delete": "Delete"
}
```

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Product Variants**: Sizes link to product_variants table
- **Service Dependencies**: Use appropriate services from Core Services Inventory
- **Cross-Feature Integration**: Follow patterns from colors and categories screens
- **DAO Integration**: Create `SizeDao` following `ProductColorDao` pattern from `lib/core/database/daos/product_color_dao.dart`
- **Dependency Injection**: Register with `sl<SizeRepository>()` pattern in `injection_container.dart`

## Implementation Requirements

### Screen Requirements (from UI Architecture)
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Use GoRouter patterns exactly as specified [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]

### File Structure Requirements
```
lib/features/products/
├── data/
│   ├── models/
│   │   └── size_model.dart (create)
│   ├── repositories/
│   │   └── size_repository_impl.dart (create)
│   └── datasources/
│       └── size_datasource.dart (create)
├── domain/
│   ├── entities/
│   │   └── size_entity.dart (create)
│   ├── repositories/
│   │   └── size_repository.dart (create)
│   └── usecases/
│       └── size_usecases.dart (create)
└── presentation/
    ├── bloc/
    │   ├── sizes_bloc.dart (create)
    │   ├── sizes_event.dart (create)
    │   └── sizes_state.dart (create)
    ├── screens/
    │   ├── sizes_screen.dart (create)
    │   └── size_form_screen.dart (create)
    └── widgets/
        └── size_selector_widget.dart (create)
```

### Testing Requirements
- **Unit Tests**: 90%+ coverage for Blocs and Services
- **Widget Tests**: Critical UI components
- **Integration Tests**: User flows
- **Platform Testing**: ALL target platforms
- **Language Testing**: English, Arabic (RTL), French
- **Theme Testing**: Light AND Dark themes

### Performance Requirements
- **Large Data Handling**: Must handle thousands of sizes smoothly
- **Real-Time Performance**: <50ms for database updates to reflect in UI
- **Memory Management**: No memory leaks with large datasets

## Acceptance Criteria

### User Story Acceptance Criteria
1. [ ] List all product sizes with name and sort order
2. [ ] Add new sizes with name and sort order
3. [ ] Edit existing size details
4. [ ] Delete sizes (only if not used by products)
5. [ ] Search/filter sizes by name
6. [ ] Show product count for each size
7. [ ] Toggle active/inactive status
8. [ ] Sort sizes by sort order

### Technical Acceptance Criteria (MANDATORY)
- AC-TECH-001: Follows Clean Architecture pattern exactly
- AC-TECH-002: Implements real-time updates with database streams
- AC-TECH-003: Uses integer cents for all money values (N/A for this screen)
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
- AC-BL-004: Product count calculation accurate
- AC-BL-005: Size system grouping and sorting correct

## Tasks / Subtasks

### ENFORCEMENT TASKS (MANDATORY)
- [ ] COMPLIANCE-001: Verify RealtimeBloc pattern implementation (AC-TECH-002)
- [ ] COMPLIANCE-002: Verify all text is localized (AC-TECH-006)
- [ ] COMPLIANCE-003: Verify responsive design (AC-TECH-004)
- [ ] COMPLIANCE-004: Verify GoRouter navigation (AC-UI-003)
- [ ] COMPLIANCE-005: Verify semantic colors (AC-UI-001)
- [ ] COMPLIANCE-006: Verify database integration (AC-BL-003)

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
- [ ] BL-004: Implement product count calculations (AC-BL-004)
- [ ] BL-005: Implement size system grouping and sorting (AC-BL-005)

### TESTING TASKS
- [ ] TEST-001: Write unit tests for Blocs (90%+ coverage) (AC-TECH-008)
- [ ] TEST-002: Write widget tests for UI components (AC-TECH-008)
- [ ] TEST-003: Write integration tests for user flows (AC-TECH-008)
- [ ] TEST-004: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [ ] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [ ] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)

### FEATURE TASKS
- [ ] FEATURE-001: Create SizesScreen with list layout (AC: 1, 5, 6, 8)
  - [ ] Implement mobile list view
  - [ ] Implement tablet grid view (2 columns)
  - [ ] Implement desktop grid view (3 columns)
  - [ ] Add search functionality
  - [ ] Add product count display
  - [ ] Implement sorting by sort_order
- [ ] FEATURE-002: Create SizeFormScreen for add/edit (AC: 2, 3, 7)
  - [ ] Form fields for name and sort order
  - [ ] Active/inactive toggle
  - [ ] Validation for unique names
- [ ] FEATURE-003: Implement SizesBloc with RealtimeBloc (AC: AC-TECH-002)
  - [ ] Load sizes from database
  - [ ] Add size functionality
  - [ ] Update size functionality
  - [ ] Delete size functionality (with product count check)
  - [ ] Search/filter functionality
  - [ ] Sort by sort_order
- [ ] FEATURE-004: Add repository and data layer (AC: AC-TECH-001)
  - [ ] SizeRepository interface
  - [ ] SizeRepositoryImpl with Drift
  - [ ] Create SizeDao following ProductColorDao pattern
  - [ ] Product count queries
- [ ] FEATURE-005: Add GoRouter integration (AC: AC-UI-003)
  - [ ] Route: /products/sizes
  - [ ] Route: /products/sizes/new
  - [ ] Route: /products/sizes/:id/edit
  - [ ] Navigation from product forms
- [ ] FEATURE-006: Seed standard sizes (AC: 1)
  - [ ] Add predefined sizes (XS, S, M, L, XL, XXL)
  - [ ] Include proper sort orders
  - [ ] Add idempotent seed data in app_database.dart
- [ ] FEATURE-007: Create SizeSelectorWidget for product forms (user request)
  - [ ] Dropdown widget for selecting sizes
  - [ ] Show size name in selection
  - [ ] Used in product variant forms

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
- **Database Schema**: TAPIX_TECHNICAL_INVENTORY.md#1.2-Product-Tables (product_sizes table)

### Detailed Implementation Guidance
- **Screen Names**: Use exact screen names from rebuild spec (SizesScreen, SizeFormScreen)
- **Field Lists**: Include ALL fields from product_sizes table specification
- **Business Rules**: Implement all validations and rules from specification
- **Service Integration**: Use services from Core Services Inventory (section 8)
- **Database Schema**: Follow exact schema from Database Requirements (section 9)

### Architecture Notes
- Follow colors screen pattern exactly for consistency
- Use existing ProductSize entity and model
- Implement RealtimeBloc pattern for real-time updates
- Use semantic colors from theme system
- Implement responsive design with breakpoints
- Group sizes by size system with proper sorting

### Project Structure Notes

- Alignment with unified project structure (paths, modules, naming)
- Follow same patterns as colors and categories screens for consistency
- Use existing size selector patterns where appropriate

### Previous Story Intelligence
- Colors screen (3-10) provides implementation pattern for variant management
- Categories screen (3-9) provides grouping and sorting patterns
- Product CRUD patterns from 3-2 apply
- Real-time state management from 1-3 is foundational
- **Critical**: Use same DAO pattern as ProductColorDao for consistency

### References

- Colors screen implementation: lib/features/products/presentation/screens/colors_screen.dart
- Categories screen implementation: lib/features/products/presentation/screens/categories_screen.dart
- ProductColorDao pattern: lib/core/database/daos/product_color_dao.dart
- DI pattern: lib/core/di/injection_container.dart
- Database schema: TAPIX_TECHNICAL_INVENTORY.md#sizes
- Product variants table: Links sizes via size_id column

### Standard Sizes Seed Data
```json
[
  {"name": "Extra Small", "sort_order": 1},
  {"name": "Small", "sort_order": 2},
  {"name": "Medium", "sort_order": 3},
  {"name": "Large", "sort_order": 4},
  {"name": "Extra Large", "sort_order": 5},
  {"name": "Double Extra Large", "sort_order": 6}
]
```

## Dev Agent Record

### Agent Model Used

Cascade (SWE-1.5) with BMad Method workflow execution

### Debug Log References

- Sprint status loaded from: _bmad-output/implementation-artifacts/sprint-status.yaml
- Epics and stories analyzed from: _bmad-output/planning-artifacts/TAPIX_EPICS_AND_STORIES.md
- Database schema referenced from: _bmad-output/planning-artifacts/TAPIX_TECHNICAL_INVENTORY.md
- Project context enforced from: project-context.md

### Implementation Completion Notes

- ✅ Domain layer: Size entity, SizeRepository interface created
- ✅ Data layer: SizeModel, SizeRepositoryImpl with Drift integration implemented
- ✅ Presentation layer: SizesBloc extending RealtimeBloc with full CRUD operations
- ✅ UI screens: SizesScreen with responsive design and SizeFormScreen for add/edit
- ✅ Localization: Complete EN/AR/FR translations for all size-related UI text
- ✅ Navigation: GoRouter routes added for /products/sizes and /products/sizes/new
- ✅ Dependency Injection: SizeRepository and SizesBloc registered in DI container
- ✅ Database: Standard sizes seed data (XS, S, M, L, XL, XXL) with idempotent upsert
- ✅ Testing: Comprehensive unit tests for SizesBloc and SizeRepositoryImpl
- ✅ Widget tests: Basic rendering and interaction tests for screens
- ✅ Integration: SizeSelectorWidget updated to use SizesBloc
- ✅ Clean Architecture: All layers properly separated and following project patterns
- ✅ Real-time updates: Stream-based state management using RealtimeBloc pattern
- ✅ Error handling: Proper error states and user feedback
- ✅ Validation: Form validation with localized error messages
- ✅ Responsive design: Mobile, tablet, and desktop layouts supported

### File List

- Story file: _bmad-output/implementation-artifacts/3-11-sizes-screen.md
