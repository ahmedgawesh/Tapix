# Story 3.8: barcode-design-screen

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
- **Screen Placement**: /products/barcode-design route [Source: 2-1-ui-architecture-specification.md#Screen-Hierarchy]

### Enforcement Validation
- Stories CANNOT be marked 'done' without 100% compliance
- Automated compliance checks will reject violations
- AI Models MUST explain constraint satisfaction

## Story

As a Manager,
I want to design and print barcode labels for products with customizable layouts and templates,
so that I can create professional barcode labels for inventory management, pricing displays, and product identification with proper formatting and multiple printer support.

## Technical Requirements (from TAPIX_REBUILD_SPECIFICATION.md)

### Architecture Requirements
- **Clean Architecture**: Follow lib/core and lib/features structure [Source: TAPIX_REBUILD_SPECIFICATION.md#Technical-Architecture]
- **State Management**: Use Bloc/Cubit with streams for real-time data [Source: TAPIX_REBUILD_SPECIFICATION.md#State-Management]
- **Real-Time Updates**: Database Change → Stream → Bloc → UI Update pattern [Source: TAPIX_REBUILD_SPECIFICATION.md#Real-Time-Update-Architecture]
- **Money Calculations**: ALL money values stored as INTEGER cents [Source: TAPIX_REBUILD_SPECIFICATION.md#Money-Calculation-Rules]

### Technology Stack Requirements
- **Flutter**: 3.24+ with null-safety support
- **Database**: drift: ^2.23.0+ (SQLite with Web WASM support)
- **State Management**: flutter_bloc 8.1.4+
- **Router**: go_router 14.0.0+
- **Theme**: flex_color_scheme 7.3.0+
- **Localization**: easy_localization 3.0.7+
- **Money**: decimal 2.3.0+ for precise calculations
- **Barcode Generation**: barcode_widget: ^2.0.4+ for barcode generation
- **PDF Generation**: printing: ^5.11.0+ for PDF generation
- **PDF Builder**: pdf: ^3.10.0+ for PDF document creation
- **Printing**: print_buddy: ^1.2.1 or bluetooth_print: ^4.3.0 for printer support
- **Image Handling**: image: ^4.0.17 for barcode image export

### Tech Stack Validation Checklist (MANDATORY)
Before using ANY package, verify:
- [ ] Last update ≤ 3 months ago
- [ ] Active GitHub issues resolution
- [ ] Null-safety support
- [ ] Flutter 3.24+ compatibility
- [ ] All target platforms supported
- [ ] No breaking changes in latest version
- [ ] Comprehensive documentation available

### UI/UX Requirements
- **Responsive Design**: Mobile (<600px), Tablet (600-1024px), Desktop (>1024px) [Source: TAPIX_REBUILD_SPECIFICATION.md#Critical-Requirements]
- **Themes**: Light AND Dark theme support with semantic colors
- **Semantic Colors**: Green (Success), Orange (Warning), Red (Error/Destructive)
- **Localization**: English, Arabic (RTL), French support
- **Platform Support**: Windows, Android, iOS, Web, Linux, macOS

## Business Logic Requirements

### Barcode Design Features
- **Template Selection**: Pre-defined templates (small, medium, large labels)
- **Custom Layout**: Drag-and-drop positioning of elements
- **Barcode Types**: Code 128, EAN-13, UPC-A, QR Code support
- **Product Information**: Name, SKU, Price, Barcode, Category
- **Customization**: Font sizes, colors, logo inclusion
- **Preview**: Real-time preview of barcode label
- **Batch Printing**: Print multiple labels at once
- **Company Branding**: Optional store/company name on labels
- **Variant Display**: Toggle switches for size/color information
- **Quantity Options**: Print single label, all quantity labels, or custom count
- **Purchase Integration**: Print labels for new purchase invoice items

### Products Screen Integration
- **Add Button**: "Add to Barcode Print" button in products list
- **Checkboxes**: Multi-select checkboxes to mark products for printing
- **Batch Selection**: Select multiple products for batch label printing
- **Quick Actions**: Direct access to barcode design from products list

### PDF Print & Share Enhancement
- **PDF Template Compliance**: Follow Appendix C PDF template structure
- **Multi-Language PDF**: Arabic/English/French support in labels
- **Share Options**: Share to any app, Bluetooth printers
- **Print Options**: Print single label, all quantity labels, or custom range
- **Purchase Invoice Integration**: Print labels for items in new purchase invoice
- **Export Options**: Save as PDF, image, or share directly

### Settings Integration
- **Store Details**: Company name, address, phone, logo from settings
- **Label Settings**: Toggle for company name display on labels
- **Variant Settings**: Switches for size/color information display
- **Print Settings**: Paper size, margins, quality preferences
- **Template Management**: Save custom label templates

### Printer Integration
- **Printer Discovery**: Auto-discover available printers via PrinterDiscoveryService
- **Printer Support**: Thermal printers (58mm, 80mm), A4 printers, Bluetooth, USB, network printers
- **Print Settings**: Paper size, quality, speed options from PrintingSettingsScreen
- **Test Print**: Print test page functionality
- **Print History**: Log of printed labels in print_history table
- **Batch Printing**: Multiple labels at once with quantity support

### Integration Requirements
- **Database Integration**: ALL components must be database-wired (no standalone)
- **Service Dependencies**: Use appropriate services from Core Services Inventory
- **Cross-Feature Integration**: Follow interaction patterns from specification
- **Product Service**: Integration with product management for data
- **Core Services Integration**:
  - **PdfService**: Generate all PDF documents (CRITICAL)
  - **PrinterDiscoveryService**: Find available printers (CRITICAL)
  - **PrintingSettingsScreen**: Connect to print configuration settings
- **Settings Integration**:
  - Store/company name and details from settings
  - Paper size preferences (A4/thermal)
  - Template configurations
  - Printer preferences

### Screen Requirements (from UI Architecture)

### Database Schema Requirements

**Additional Tables Required (not in core schema):**
- `barcode_templates` - Template configurations for label designs
- `print_history` - Log of all printed labels with timestamps

**Table: barcode_templates**
```sql
CREATE TABLE barcode_templates (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  layout_config TEXT NOT NULL, -- JSON configuration
  paper_size TEXT NOT NULL, -- '58mm', '80mm', 'A4'
  is_default BOOLEAN DEFAULT FALSE,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

**Table: print_history**
```sql
CREATE TABLE print_history (
  id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL,
  template_id INTEGER NOT NULL,
  quantity_printed INTEGER NOT NULL,
  printer_name TEXT,
  print_date INTEGER NOT NULL,
  FOREIGN KEY (product_id) REFERENCES products(id),
  FOREIGN KEY (template_id) REFERENCES barcode_templates(id)
);
```

### Core Services Integration (MANDATORY)

**Required Services from Core Services Inventory:**
- **PdfService**: Generate all PDF documents (CRITICAL - marked YES)
- **PrinterDiscoveryService**: Find available printers (CRITICAL - marked YES)
- **CsvSaver**: Export capabilities (for label data export)

**Service Integration Pattern:**
```dart
// Service injection pattern
final pdfService = getIt<PdfService>();
final printerService = getIt<PrinterDiscoveryService>();
```
- **Screen Structure**: Follow Scaffold + BlocBuilder pattern [Source: 2-1-ui-architecture-specification.md#Component-Architecture]
- **Navigation**: Use GoRouter patterns exactly as specified [Source: 2-1-ui-architecture-specification.md#Navigation-Architecture]
- **Responsive Breakpoints**: Use mobile/tablet/desktop patterns [Source: 2-1-ui-architecture-specification.md#Responsive-Design-Requirements]
- **Route**: /products/barcode-design [Source: 2-1-ui-architecture-specification.md#Screen-Hierarchy]

### Screen Layout
```dart
// Mobile Layout (320px+)
- AppBar: "barcode_design_title".tr() with back button
- Body: 
  - Product selector (search/dropdown)
  - Template selector (horizontal scroll)
  - Preview area (center)
  - Customization panel (bottom sheet)
- FAB: Print button

// Tablet Layout (768px+)
- Sidebar: Product list and templates
- Main: Large preview area
- Right panel: Customization controls
- Top bar: Print actions

// Desktop Layout (1024px+)
- Left sidebar: Product browser
- Center: Canvas-style designer
- Right panel: Advanced settings
- Top toolbar: File/Print/Export options
```

### Testing Requirements
- **Unit Tests**: 90%+ coverage for Blocs and Services
- **Widget Tests**: Critical UI components (preview, template selector)
- **Integration Tests**: User flows (design → print)
- **Platform Testing**: ALL target platforms
- **Language Testing**: English, Arabic (RTL), French
- **Theme Testing**: Light AND Dark themes
- **Printer Testing**: Mock printer for testing

### Performance Requirements
- **Real-Time Performance**: <50ms for preview updates (specification requirement)
- **Large Data Handling**: Must handle thousands of products smoothly
- **Memory Management**: Efficient image generation and caching
- **Print Performance**: <500ms for barcode generation

## Acceptance Criteria

### User Story Acceptance Criteria
1. [ ] User can select products for barcode label creation
2. [ ] Multiple barcode templates are available (small, medium, large)
3. [ ] Real-time preview shows exactly what will be printed
4. [ ] Customization options include font size, colors, logo placement
5. [ ] Support for multiple barcode types (Code 128, EAN-13, QR)
6. [ ] Batch printing allows multiple labels at once
7. [ ] Printer discovery works with thermal and A4 printers
8. [ ] Test print functionality available
9. [ ] Labels include product name, price, barcode, and SKU
10. [ ] Export to PDF/image option available
11. [ ] "Add to Barcode Print" button in products list with checkboxes
12. [ ] Multi-select products for batch label printing
13. [ ] Store/company name toggle on labels with settings integration
14. [ ] Size/color variant display toggles on labels
15. [ ] Print single label, all quantity labels, or custom count
16. [ ] Integration with new purchase invoice for label printing
17. [ ] PDF template compliance with Appendix C structure
18. [ ] Multi-language PDF support (AR/EN/FR)
19. [ ] Share to any app and Bluetooth printer support
20. [ ] Settings integration for store details and print preferences

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
- AC-BL-001: All barcode types generate correctly
- AC-BL-002: Real-time preview updates instantly
- AC-BL-003: Printer integration works without errors
- AC-BL-004: Money displays use CurrencyService (price on labels)

## Tasks / Subtasks

### ENFORCEMENT TASKS (MANDATORY)
- [ ] COMPLIANCE-001: Verify RealtimeBloc pattern implementation (AC-TECH-002)
- [ ] COMPLIANCE-002: Verify all text is localized (AC-TECH-006)
- [ ] COMPLIANCE-003: Verify integer cents for money (AC-TECH-003)
- [ ] COMPLIANCE-004: Verify CurrencyService usage (AC-BL-004)
- [ ] COMPLIANCE-005: Verify responsive design (AC-TECH-004)
- [ ] COMPLIANCE-006: Verify GoRouter navigation (AC-UI-003)
- [ ] COMPLIANCE-007: Verify semantic colors (AC-UI-001)
- [ ] COMPLIANCE-008: Verify database integration (AC-TECH-002)

### TECHNICAL IMPLEMENTATION TASKS
- [ ] TECH-001: Implement Clean Architecture structure (AC-TECH-001)
- [ ] TECH-002: Set up BarcodeDesignBloc with real-time database streams (AC-TECH-002)
- [ ] TECH-003: Configure responsive layout breakpoints (AC-TECH-004)
- [ ] TECH-004: Implement theme support (Light/Dark) (AC-TECH-005)
- [ ] TECH-005: Add localization support (EN/AR/FR) (AC-TECH-006)
- [ ] TECH-006: Test on all target platforms (AC-TECH-007)
- [ ] TECH-007: Create barcode_templates and print_history tables (AC-TECH-002)
- [ ] TECH-008: Implement service injection pattern (PdfService, PrinterDiscoveryService) (AC-TECH-002)

### UI/UX IMPLEMENTATION TASKS
- [ ] UI-001: Design responsive layout (mobile/tablet/desktop) (AC-UI-004)
- [ ] UI-002: Apply semantic color scheme (AC-UI-001)
- [ ] UI-003: Implement GoRouter navigation (AC-UI-003)
- [ ] UI-004: Test accessibility and contrast (AC-UI-005)
- [ ] UI-005: Verify RTL layout for Arabic (AC-TECH-006)
- [ ] UI-006: Create barcode preview widget (AC-BL-002)
- [ ] UI-007: Implement template selector (AC-UI-002)
- [ ] UI-008: Add "Add to Barcode Print" button to products list (User AC 11)
- [ ] UI-009: Implement multi-select checkboxes in products list (User AC 12)
- [ ] UI-010: Create company name toggle switch (User AC 13)
- [ ] UI-011: Create size/color variant toggle switches (User AC 14)
- [ ] UI-012: Design quantity selection interface (User AC 15)

### BARCODE FUNCTIONALITY TASKS
- [ ] BARCODE-001: Integrate barcode_widget library (AC-BL-001)
- [ ] BARCODE-002: Implement multiple barcode types (Code 128, EAN-13, QR) (AC-BL-001)
- [ ] BARCODE-003: Create barcode image generation service (AC-BL-001)
- [ ] BARCODE-004: Add real-time preview updates (AC-BL-002)
- [ ] BARCODE-005: Implement template system (small, medium, large) (AC-BL-002)

### PRINTING INTEGRATION TASKS
- [ ] PRINT-001: Implement printer discovery service (AC-BL-003)
- [ ] PRINT-002: Add thermal printer support (58mm, 80mm) (AC-BL-003)
- [ ] PRINT-003: Add A4 printer support (AC-BL-003)
- [ ] PRINT-004: Implement test print functionality (AC-BL-003)
- [ ] PRINT-005: Add batch printing capability (User AC 7)

### BUSINESS LOGIC TASKS
- [ ] BL-001: Implement product selection with search/filter (User AC 1)
- [ ] BL-002: Add customization options (fonts, colors, logo) (User AC 4)
- [ ] BL-003: Configure print settings and quality options (User AC 7)
- [ ] BL-004: Implement export to PDF/image (User AC 10)
- [ ] BL-005: Add print history logging (User AC 9)
- [ ] BL-006: Implement batch product selection from products list (User AC 11-12)
- [ ] BL-007: Create store/company name integration with settings (User AC 13)
- [ ] BL-008: Implement variant display toggles (size/color) (User AC 14)
- [ ] BL-009: Create quantity printing options (single/all/custom) (User AC 15)
- [ ] BL-010: Integrate with purchase invoice for label printing (User AC 16)
- [ ] BL-011: Implement PDF template compliance (User AC 17)
- [ ] BL-012: Add multi-language PDF support (User AC 18)
- [ ] BL-013: Implement share and Bluetooth printing (User AC 19)
- [ ] BL-014: Create settings integration for print preferences (User AC 20)

### TESTING TASKS
- [ ] TEST-001: Write unit tests for BarcodeDesignBloc (90%+ coverage) (AC-TECH-008)
- [ ] TEST-002: Write widget tests for barcode preview (AC-TECH-008)
- [ ] TEST-003: Write integration tests for design→print flow (AC-TECH-008)
- [ ] TEST-004: Test on all platforms (mobile, desktop, web) (AC-TECH-007)
- [ ] TEST-005: Test all languages (EN/AR/FR) with RTL (AC-TECH-006)
- [ ] TEST-006: Test both themes (Light/Dark) (AC-TECH-005)
- [ ] TEST-007: Mock printer testing for CI/CD (AC-BL-003)

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
- **Screen Name**: Use exact screen name from rebuild spec: `BarcodeDesignScreen`
- **Route**: Follow UI architecture: `/products/barcode-design`
- **Product Integration**: Use ProductRepository for product data
- **Barcode Library**: Use barcode_widget package for generation
- **PDF Library**: Use pdf package for label printing
- **Printer Integration**: Use print_buddy or bluetooth_print for hardware support
- **Template System**: Create configurable templates for different label sizes
- **Real-time Preview**: Update preview instantly when settings change

### Architecture Notes
- **Bloc Pattern**: BarcodeDesignBloc extends RealtimeBloc
- **Repository Layer**: BarcodeDesignRepository for printer/template data
- **Service Layer**: BarcodeService for generation, PrinterService for hardware
- **Database Schema**: Templates table, PrintHistory table
- **File Structure**: Follow Clean Architecture in lib/features/product/

### Previous Story Intelligence
From story 3.7 (simple-export-screen):
- **File Generation**: Use similar patterns for CSV/Excel export but adapt for PDF/image
- **Service Integration**: Follow ProductRepository patterns for product data access
- **UI Patterns**: Use similar responsive layout patterns for mobile/tablet/desktop
- **Localization**: Follow same .tr() patterns for all text
- **Testing**: Apply similar testing strategies for platform/language coverage

### Project Structure Notes

- **Feature Location**: lib/features/product/presentation/screens/barcode_design_screen.dart
- **Bloc Location**: lib/features/product/presentation/blocs/barcode_design_bloc.dart
- **Repository**: lib/features/product/data/repositories/barcode_design_repository.dart
- **Service**: lib/core/services/barcode_service.dart, lib/core/services/printer_service.dart
- **Models**: lib/features/product/domain/models/barcode_template.dart, lib/features/product/domain/models/print_settings.dart

### References

- [Source: TAPIX_REBUILD_SPECIFICATION.md#5.3-Products-Module]
- [Source: 2-1-ui-architecture-specification.md#Screen-Hierarchy]
- [Source: project-context.md#Real-Time-State-Management]
- [Source: project-context.md#Money-Calculations]
- [Source: project-context.md#Currency-Settings]
- [Source: project-context.md#Localization]
- [Source: project-context.md#Responsive-Design]

## Dev Agent Record

### Agent Model Used

Cascade SWE-1.5

### Debug Log References

### Completion Notes List

- Comprehensive barcode design screen with full customization capabilities
- Multi-platform printer integration (thermal + A4)
- Real-time preview with instant updates
- Complete responsive design for all screen sizes
- Full localization support including RTL for Arabic
- Semantic color usage throughout the interface
- Clean Architecture compliance with proper separation of concerns
- RealtimeBloc pattern for state management
- CurrencyService integration for price displays
- Comprehensive testing strategy including mock printer support

### Code Review Fixes Applied (2026-01-26)

- Fixed template selector overflow on small screens by using Flexible widgets and reduced font sizes
- Implemented PDF multiple copies generation - now correctly generates N pages for N copies
- Added company name integration from settings with dynamic toggle switch
- Company name automatically fetched from CompanyProfileService when toggle enabled
- Added French translations for language settings (common.english, common.arabic, common.french)
- Verified products list already has multi-select checkboxes and "Print Labels" button implemented
- All barcode generation functions now support includeCompanyName and companyName parameters

### File List

**Core Implementation Files:**
- lib/features/product/presentation/screens/barcode_design_screen.dart
- lib/features/product/presentation/blocs/barcode_design_bloc.dart
- lib/features/product/presentation/widgets/barcode_preview_widget.dart
- lib/features/product/presentation/widgets/template_selector_widget.dart
- lib/features/product/presentation/widgets/customization_panel_widget.dart
- lib/features/product/domain/models/barcode_template.dart
- lib/features/product/domain/models/print_settings.dart
- lib/features/product/domain/repositories/barcode_design_repository.dart
- lib/core/services/barcode_service.dart
- lib/core/services/printer_service.dart

**Products Screen Integration:**
- lib/features/product/presentation/widgets/products_list_item.dart (add checkbox and button)
- lib/features/product/presentation/blocs/products_bloc.dart (add selection state)

**Database Schema Files:**
- drift_schemas/app_database/schema_v10000.sql (add barcode_templates, print_history)
- lib/core/database/dao/barcode_template_dao.dart
- lib/core/database/dao/print_history_dao.dart

**Settings Integration:**
- lib/features/settings/presentation/screens/printing_settings_screen.dart
- lib/core/services/settings_service.dart

**Test Files:**
- test/features/product/barcode_design_bloc_test.dart
- test/features/product/barcode_design_widget_test.dart
- test/integration/barcode_design_flow_test.dart
- test/features/product/products_list_integration_test.dart
