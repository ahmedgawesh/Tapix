# Story 3.2: product-crud-variants

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a Manager,
I want to add and edit products with size/color variants,
so that I can manage my inventory details.

## Acceptance Criteria

1. [x] Product form includes all fields from spec (cost, price, tax, etc.)
2. [x] Support for multiple variants (Color/Size combinations)
3. [x] Money inputs handle cents correctly
4. [x] Validation for required fields

## Tasks / Subtasks

- [x] Task 1: Implement product CRUD form (AC: 1, 3, 4)
  - [x] Subtask 1.1: Create comprehensive product form with all required fields
  - [x] Subtask 1.2: Implement money input widgets with cent precision
  - [x] Subtask 1.3: Add form validation for required fields and data types
  - [x] Subtask 1.4: Implement product create and update operations
- [x] Task 2: Implement product variants system (AC: 2)
  - [x] Subtask 2.1: Create variant management UI for colors and sizes
  - [x] Subtask 2.2: Implement variant CRUD operations with stock tracking
  - [x] Subtask 2.3: Add variant-specific pricing and SKU management
  - [x] Subtask 2.4: Implement variant bulk operations and import/export

## Dev Notes

### Project Structure Notes

- **Feature Location**: `lib/features/products/`
- **Bloc Pattern**: Must extend `RealtimeBloc` for real-time updates
- **Database**: Use Drift with `products`, `product_variants`, `product_colors`, `sizes` tables
- **Real-time Updates**: Product form must auto-update when database changes
- **Variants Support**: Full variant management with color/size combinations
- **Navigation Integration**: Small app bar with back arrow for all screen sizes
- **Settings Integration**: Language and currency settings for development testing
- **Theme Integration**: Full dark/light mode support with semantic colors

### Architecture Compliance

**Clean Architecture Structure:**
```
lib/features/products/
├── data/
│   ├── models/
│   │   ├── product_model.dart
│   │   ├── product_variant_model.dart
│   │   ├── product_color_model.dart
│   │   └── size_model.dart
│   ├── repositories/
│   │   ├── product_repository_impl.dart
│   │   └── product_variant_repository_impl.dart
│   └── datasources/
│       ├── product_local_datasource.dart
│       └── variant_local_datasource.dart
├── domain/
│   ├── entities/
│   │   ├── product.dart
│   │   ├── product_variant.dart
│   │   ├── product_color.dart
│   │   └── size.dart
│   ├── repositories/
│   │   ├── product_repository.dart
│   │   └── product_variant_repository.dart
│   └── usecases/
│       ├── create_product_usecase.dart
│       ├── update_product_usecase.dart
│       ├── create_variant_usecase.dart
│       └── update_variant_usecase.dart
├── presentation/
│   ├── bloc/
│   │   ├── product_form_bloc.dart
│   │   ├── product_variants_bloc.dart
│   │   ├── colors_bloc.dart
│   │   └── sizes_bloc.dart
│   ├── screens/
│   │   ├── product_form_screen.dart
│   │   ├── product_variants_screen.dart
│   │   ├── colors_management_screen.dart
│   │   └── sizes_management_screen.dart
│   └── widgets/
│       ├── product_form_widget.dart
│       ├── variant_management_widget.dart
│       ├── variant_tile_widget.dart
│       ├── color_picker_widget.dart
│       ├── size_selector_widget.dart
│       ├── money_input_widget.dart
│       └── app_bar_widget.dart
└── services/
    ├── product_service.dart
    ├── variant_service.dart
    └── money_calculation_service.dart
```

**Additional Features Structure:**
```
lib/features/
├── settings/
│   ├── presentation/
│   │   ├── screens/settings_screen.dart
│   │   ├── widgets/language_selector_widget.dart
│   │   ├── widgets/currency_selector_widget.dart
│   │   └── widgets/theme_toggle_widget.dart
│   ├── domain/
│   │   ├── entities/settings.dart
│   │   └── usecases/update_settings_usecase.dart
│   └── data/
│       └── repositories/settings_repository_impl.dart
└── theme/
    ├── app_theme.dart
    ├── app_colors.dart
    ├── theme_service.dart
    └── widgets/theme_toggle_button.dart
```

**Bloc Requirements:**
- Extend `RealtimeBloc<Product, ProductFormEvent>` for product form
- Extend `RealtimeBloc<List<ProductVariant>, VariantsEvent>` for variants
- Use `RealtimeService` for database stream subscriptions
- Implement proper loading, success, and error states
- Handle optimistic updates for better UX
- Maintain form state with validation
- **Theme Bloc**: Extend `RealtimeBloc<ThemeData, ThemeEvent>` for theme switching
- **Settings Bloc**: Extend `RealtimeBloc<Settings, SettingsEvent>` for language/currency

### Database Schema Compliance

**Products Table (from TAPIX_TECHNICAL_INVENTORY.md):**
```dart
class Product {
  final int id;
  final String name;
  final String? nameAr;
  final String? nameFr;
  final String? sku;
  final String? barcode;
  final int? categoryId;
  final int costCents;
  final int priceCents;
  final int? wholesalePriceCents;
  final int quantity;
  final int minQuantity;
  final bool isActive;
  final bool isTaxable;
  final int taxRateBps;
  final String? imagePath;
  final String? description;
  final int? currencyId;
  final int? supplierId;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

**Product Variants Table:**
```dart
class ProductVariant {
  final int id;
  final int productId;
  final int? colorId;
  final int? sizeId;
  final String? sku;
  final String? barcode;
  final int quantity;
  final int priceAdjustmentCents;
  final bool isActive;
}
```

**Product Colors Table:**
```dart
class ProductColor {
  final int id;
  final String name;
  final String? hexCode;
  final bool isActive;
}
```

**Sizes Table:**
```dart
class Size {
  final int id;
  final String name;
  final int sortOrder;
  final bool isActive;
}
```

### Real-time State Management

**Must Use RealtimeBloc Pattern:**
```dart
class ProductFormBloc extends RealtimeBloc<Product, ProductFormEvent> {
  @override
  Stream<Product> get dataStream => _productService.watchProduct(productId);
  
  // Handle form field changes
  // Maintain validation state
  // Auto-save draft functionality
  // Real-time variant updates
}

class ProductVariantsBloc extends RealtimeBloc<List<ProductVariant>, VariantsEvent> {
  @override
  Stream<List<ProductVariant>> get dataStream => _variantService.watchProductVariants(productId);
  
  // Handle variant CRUD operations
  // Maintain variant state
  // Bulk operations support
  // Real-time stock updates
}
```

### UI/UX Requirements

**Navigation Requirements:**
- **Small App Bar**: Compact app bar with back arrow for all screen sizes
- **Back Navigation**: Fully functional back arrow on mobile, tablet, and desktop
- **Router Integration**: Use `go_router` for proper navigation stack management
- **Breadcrumb Support**: Clear navigation path indication for deep links
- **Keyboard Shortcuts**: ESC key for back navigation on desktop

**Theme Requirements:**
- **Dark/Light Mode Toggle**: Theme switcher button in app bar for easy testing
- **Semantic Color Usage**: All components must use semantic colors from theme
- **Consistent Styling**: Every UI element follows app theme guidelines
- **Real-time Theme Switching**: Immediate theme change without app restart
- **Theme Persistence**: User's theme choice saved and restored

**Responsive Design System:**
- **Mobile (<600px)**: Single column form, bottom sheet for variants, full-width inputs, compact app bar
- **Tablet (600-1200px)**: Two-column form layout, side panel for variants, optimized input widths, medium app bar
- **Desktop (>1200px)**: Multi-column form with persistent variant panel, keyboard shortcuts, full app bar
- **Material 3 Adaptive Containers**: Use `LayoutBuilder` with breakpoint-specific layouts
- **Smooth Layout Transitions**: Animated form sections (300ms ease)

**Material Design Compliance:**
- Use `flex_color_scheme` for theming with semantic colors
- **Semantic Colors**: Green (Success), Orange (Warning), Red (Error)
- Loading skeletons/shimmers during form submission
- **Micro-interactions**: Form field focus animations, variant tile transitions
- **Progressive Disclosure**: Advanced options in expandable sections

**Settings Integration Requirements:**
- **Language Settings**: Real-time language switching (EN/AR/FR) for testing
- **Currency Settings**: Dynamic currency selection and formatting for testing
- **Settings Screen**: Comprehensive settings screen accessible from app bar
- **Development Testing**: Easy switching between languages and currencies during development
- **Settings Persistence**: User preferences saved and restored across app sessions
- **Real-time Updates**: Immediate UI updates when settings change

**Form UI Requirements:**
- **Smart Defaults**: Auto-populate fields based on category/supplier
- **Field Grouping**: Logical sections (Basic Info, Pricing, Inventory, Variants)
- **Real-time Validation**: Immediate feedback with helpful error messages
- **Auto-save**: Draft saving with restore capability
- **Keyboard Navigation**: Full tab order and shortcuts (Ctrl+S save, Ctrl+N new)

**Money Input Requirements:**
- **Cent Precision**: Always work with integer cents, display as formatted currency
- **Currency Formatting**: Locale-specific formatting with symbol position
- **Input Masking**: Proper decimal input handling and validation
- **Calculation Support**: Auto-calculate margins, tax amounts, and totals
- **Multi-currency**: Support for different currencies with conversion

**Variant Management UI:**
- **Mobile**: Bottom sheet with variant list, add variant FAB
- **Tablet**: Side panel with variant grid, drag-to-reorder
- **Desktop**: Persistent variant table with inline editing
- **Visual Color Picker**: Color selection with hex codes and preview
- **Size Management**: Predefined sizes with custom size support
- **Bulk Operations**: Mass price updates, stock adjustments

**Image Management:**
- **Image Upload**: Camera capture or gallery selection
- **Image Processing**: Auto-resize and compression
- **Preview**: Multiple image support with zoom
- **Storage**: Local storage with cloud sync preparation

### Performance Requirements

**Form Performance:**
- **Debounced Validation**: 300ms delay for field validation
- **Optimistic Updates**: Immediate UI feedback for form changes
- **Memory Management**: <50MB for form with variants
- **Auto-save Throttling**: Save drafts every 30 seconds or on field change

**Variant Performance:**
- **Lazy Loading**: Load variants on demand (20 per page)
- **Efficient Updates**: Batch variant operations
- **Search Performance**: O(log n) variant lookup
- **Real-time Updates**: <100ms from DB change to UI update

**Database Optimization:**
- **Indexes**: `products(sku)`, `products(barcode)`, `product_variants(product_id)`
- **Transactions**: Atomic variant operations
- **Constraints**: Foreign key relationships with cascade delete
- **Migrations**: Versioned schema updates

### Localization Requirements

**Multi-language Support:**
- Product names in EN/AR/FR with intelligent fallback
- **RTL Layout**: Full RTL support for Arabic form fields
- **Dynamic Font Scaling**: Per-language font size optimization
- **Number Formatting**: Locale-specific currency and number formatting

**Typography System:**
- **Arabic**: IBM Plex Sans Arabic with proper RTL kerning
- **Latin**: IBM Plex Sans with optimal line height
- **Font Weights**: 300-700 range with language-specific optimization
- **Text Alignment**: RTL right-align for Arabic, LTR left-align for EN/FR

**Keys to Implement:**
```dart
// app_en.arb
"product_form_title": "Product Form",
"product_form_basicInfo": "Basic Information",
"product_form_name": "Product Name",
"product_form_nameAr": "Arabic Name",
"product_form_nameFr": "French Name",
"product_form_sku": "SKU",
"product_form_barcode": "Barcode",
"product_form_category": "Category",
"product_form_supplier": "Supplier",
"product_form_pricing": "Pricing",
"product_form_cost": "Cost Price",
"product_form_price": "Selling Price",
"product_form_wholesalePrice": "Wholesale Price",
"product_form_tax": "Tax Settings",
"product_form_isTaxable": "Taxable",
"product_form_taxRate": "Tax Rate",
"product_form_inventory": "Inventory",
"product_form_quantity": "Current Stock",
"product_form_minQuantity": "Minimum Stock",
"product_form_variants": "Product Variants",
"product_form_addVariant": "Add Variant",
"product_form_variantColor": "Color",
"product_form_variantSize": "Size",
"product_form_variantSku": "Variant SKU",
"product_form_variantBarcode": "Variant Barcode",
"product_form_variantPrice": "Price Adjustment",
"product_form_save": "Save Product",
"product_form_saveDraft": "Save Draft",
"product_form_cancel": "Cancel",
"product_form_delete": "Delete Product",
"product_form_required": "This field is required",
"product_form_invalidNumber": "Please enter a valid number",
"product_form_imageUpload": "Upload Image",
"product_form_description": "Description"

// app_ar.arb (RTL)
"product_form_title": "نموذج المنتج",
"product_form_basicInfo": "المعلومات الأساسية",
"product_form_name": "اسم المنتج",
"product_form_nameAr": "الاسم بالعربية",
"product_form_nameFr": "الاسم بالفرنسية",
"product_form_sku": "رمز المنتج",
"product_form_barcode": "الباركود",
"product_form_category": "الفئة",
"product_form_supplier": "المورد",
"product_form_pricing": "التسعير",
"product_form_cost": "سعر التكلفة",
"product_form_price": "سعر البيع",
"product_form_wholesalePrice": "سعر الجملة",
"product_form_tax": "إعدادات الضريبة",
"product_form_isTaxable": "خاضع للضريبة",
"product_form_taxRate": "نسبة الضريبة",
"product_form_inventory": "المخزون",
"product_form_quantity": "المخزون الحالي",
"product_form_minQuantity": "الحد الأدنى للمخزون",
"product_form_variants": "متغيرات المنتج",
"product_form_addVariant": "إضافة متغير",
"product_form_variantColor": "اللون",
"product_form_variantSize": "المقاس",
"product_form_variantSku": "رمز المتغير",
"product_form_variantBarcode": "باركود المتغير",
"product_form_variantPrice": "تعديل السعر",
"product_form_save": "حفظ المنتج",
"product_form_saveDraft": "حفظ المسودة",
"product_form_cancel": "إلغاء",
"product_form_delete": "حذف المنتج",
"product_form_required": "هذا الحقل مطلوب",
"product_form_invalidNumber": "يرجى إدخال رقم صحيح",
"product_form_imageUpload": "رفع صورة",
"product_form_description": "الوصف"

// app_fr.arb
"product_form_title": "Formulaire de Produit",
"product_form_basicInfo": "Informations de Base",
"product_form_name": "Nom du Produit",
"product_form_nameAr": "Nom en Arabe",
"product_form_nameFr": "Nom en Français",
"product_form_sku": "SKU",
"product_form_barcode": "Code-barres",
"product_form_category": "Catégorie",
"product_form_supplier": "Fournisseur",
"product_form_pricing": "Tarification",
"product_form_cost": "Prix de Coût",
"product_form_price": "Prix de Vente",
"product_form_wholesalePrice": "Prix de Gros",
"product_form_tax": "Paramètres Fiscaux",
"product_form_isTaxable": "Taxable",
"product_form_taxRate": "Taux de Taxe",
"product_form_inventory": "Inventaire",
"product_form_quantity": "Stock Actuel",
"product_form_minQuantity": "Stock Minimum",
"product_form_variants": "Variantes de Produit",
"product_form_addVariant": "Ajouter une Variante",
"product_form_variantColor": "Couleur",
"product_form_variantSize": "Taille",
"product_form_variantSku": "SKU de Variante",
"product_form_variantBarcode": "Code-barres de Variante",
"product_form_variantPrice": "Ajustement de Prix",
"product_form_save": "Sauvegarder le Produit",
"product_form_saveDraft": "Sauvegarder le Brouillon",
"product_form_cancel": "Annuler",
"product_form_delete": "Supprimer le Produit",
"product_form_required": "Ce champ est obligatoire",
"product_form_invalidNumber": "Veuillez entrer un nombre valide",
"product_form_imageUpload": "Télécharger une Image",
"product_form_description": "Description"
```

### Testing Requirements

**Unit Tests:**
- ProductFormBloc event handling with validation
- ProductVariantsBloc CRUD operations
- Money calculation service with cent precision
- Form validation logic with complex rules
- Variant management business logic
- Auto-save functionality

**Widget Tests:**
- Product form rendering across all breakpoints
- Money input widget with currency formatting
- Variant management UI interactions
- Form validation error display
- Image upload and preview functionality
- Color picker and size selector widgets

**Integration Tests:**
- Complete product creation workflow
- Product update with variants
- Real-time updates during form editing
- Multi-user concurrent editing scenarios
- Image upload with processing
- Bulk variant operations

**Performance Tests:**
- Form loading time with large variant counts
- Memory usage during form editing
- Auto-save performance under rapid changes
- Database transaction performance
- Image processing performance

**Accessibility Tests:**
- Screen reader compatibility for complex forms
- Keyboard navigation for all form elements
- High contrast mode support
- Text scaling up to 200%
- Focus management and visual indicators
- Voice control support for form commands

### File Structure Requirements

**Create these files:**
```
lib/features/products/
├── data/
│   ├── models/
│   │   ├── product_model.dart
│   │   ├── product_variant_model.dart
│   │   ├── product_color_model.dart
│   │   └── size_model.dart
│   ├── repositories/
│   │   ├── product_repository_impl.dart
│   │   └── product_variant_repository_impl.dart
│   └── datasources/
│       ├── product_local_datasource.dart
│       └── variant_local_datasource.dart
├── domain/
│   ├── entities/
│   │   ├── product.dart
│   │   ├── product_variant.dart
│   │   ├── product_color.dart
│   │   └── size.dart
│   ├── repositories/
│   │   ├── product_repository.dart
│   │   └── product_variant_repository.dart
│   └── usecases/
│       ├── create_product_usecase.dart
│       ├── update_product_usecase.dart
│       ├── create_variant_usecase.dart
│       ├── update_variant_usecase.dart
│       └── delete_variant_usecase.dart
├── presentation/
│   ├── bloc/
│   │   ├── product_form_bloc.dart
│   │   ├── product_form_event.dart
│   │   ├── product_form_state.dart
│   │   ├── product_variants_bloc.dart
│   │   ├── product_variants_event.dart
│   │   ├── product_variants_state.dart
│   │   ├── colors_bloc.dart
│   │   └── sizes_bloc.dart
│   ├── screens/
│   │   ├── product_form_screen.dart
│   │   ├── product_variants_screen.dart
│   │   ├── colors_management_screen.dart
│   │   └── sizes_management_screen.dart
│   └── widgets/
│       ├── product_form_widget.dart
│       ├── variant_management_widget.dart
│       ├── variant_tile_widget.dart
│       ├── color_picker_widget.dart
│       ├── size_selector_widget.dart
│       ├── money_input_widget.dart
│       ├── image_upload_widget.dart
│       ├── form_section_widget.dart
│       └── app_bar_widget.dart
└── services/
    ├── product_service.dart
    ├── variant_service.dart
    ├── color_service.dart
    ├── size_service.dart
    └── money_calculation_service.dart

lib/features/settings/
├── data/
│   ├── models/settings_model.dart
│   └── repositories/settings_repository_impl.dart
├── domain/
│   ├── entities/settings.dart
│   ├── repositories/settings_repository.dart
│   └── usecases/update_settings_usecase.dart
├── presentation/
│   ├── bloc/
│   │   ├── settings_bloc.dart
│   │   ├── settings_event.dart
│   │   └── settings_state.dart
│   ├── screens/
│   │   └── settings_screen.dart
│   └── widgets/
│       ├── language_selector_widget.dart
│       ├── currency_selector_widget.dart
│       └── theme_toggle_widget.dart
└── services/
    └── settings_service.dart

lib/core/theme/
├── app_theme.dart
├── app_colors.dart
├── theme_service.dart
├── widgets/
│   └── theme_toggle_button.dart
└── bloc/
    ├── theme_bloc.dart
    ├── theme_event.dart
    └── theme_state.dart

lib/core/navigation/
├── app_router.dart
├── navigation_service.dart
└── widgets/
    └── small_app_bar_widget.dart
```

### Dependencies

**Required Packages:**
- `flutter_bloc: ^9.1.1` - State management with RealtimeBloc extension
- `drift: ^2.23.0` - Database ORM with real-time streams
- `flex_color_scheme: ^8.0.0` - Material 3 theming with semantic colors
- `easy_localization: ^3.0.7` - Multi-language support with RTL
- `cached_network_image: ^3.3.1` - Optimized image loading and caching
- `image_picker: ^1.0.7` - Camera and gallery image selection
- `image: ^4.1.3` - Image processing and manipulation
- `responsive_framework: ^1.1.0` - Responsive design utilities
- `flutter_keyboard_visibility: ^6.0.0` - Keyboard management
- `accessibility_package: ^1.0.0` - Accessibility utilities
- `form_builder: ^9.3.0` - Advanced form building utilities
- `currency_picker: ^2.0.20` - Currency selection and formatting
- `go_router: ^14.6.2` - Declarative routing with navigation stack management
- `shared_preferences: ^2.3.3` - Settings persistence
- `theme_provider: ^0.6.0` - Theme management and persistence

**Platform-Specific Dependencies:**
- **Mobile**: `image_picker` for camera access
- **Desktop**: `window_manager` for keyboard shortcuts
- **Web**: `image_picker_for_web` for web image upload

### Implementation Order

1. **Foundation**: Set up responsive framework, accessibility, and navigation
2. **Theme System**: Implement dark/light mode with semantic colors and persistence
3. **Settings System**: Create language and currency settings with real-time switching
4. **Data Layer**: Models, repository, datasource with variant support
5. **Domain Layer**: Entities and use cases with form validation
6. **State Management**: RealtimeBloc with form state management
7. **Navigation Integration**: Small app bar with back navigation and routing
8. **UI Components**: Responsive form widgets with validation
9. **Money System**: Cent-precise money inputs with currency formatting
10. **Variant System**: Color/size management with CRUD operations
11. **Image System**: Upload, processing, and preview functionality
12. **Real-time Integration**: Stream subscriptions with auto-save
13. **Localization**: Multi-language support with RTL optimization
14. **Accessibility**: Screen reader and keyboard navigation
15. **Testing**: Comprehensive unit, widget, and integration tests

### Advanced Features

**Auto-save and Draft Management:**
- **Draft Persistence**: Save form state every 30 seconds
- **Restore Functionality**: Recover unsaved forms on app restart
- **Conflict Resolution**: Handle concurrent editing scenarios
- **Version History**: Track form changes with undo/redo

**Bulk Operations:**
- **Mass Price Updates**: Apply percentage or fixed amount changes
- **Stock Adjustments**: Bulk quantity updates across variants
- **Import/Export**: CSV import/export for products and variants
- **Template System**: Product templates for similar items

**Advanced Validation:**
- **Business Rules**: Custom validation based on product type
- **Cross-field Validation**: Dependent field validation
- **Async Validation**: Server-side validation for uniqueness
- **Real-time Feedback**: Progressive validation with helpful messages

**Image Management:**
- **Multiple Images**: Support for product gallery
- **Image Processing**: Auto-resize, compression, and optimization
- **Cloud Storage**: Preparation for cloud image sync
- **Image Variants**: Different sizes for different contexts

## Dev Agent Record

### Agent Model Used

Cascade (SWE-1.5)

### Debug Log References

### Completion Notes List

- Created comprehensive product CRUD form with all required fields
- Implemented full variant management system with colors and sizes
- Added cent-precise money input widgets with currency formatting
- Created responsive design system for mobile/tablet/desktop
- Implemented real-time state management with RealtimeBloc
- Added comprehensive form validation with helpful error messages
- Created multi-language support with RTL optimization
- Added accessibility features for screen readers and keyboard navigation
- Implemented auto-save functionality with draft management
- Created comprehensive testing strategy for all components
- **Added small app bar with back navigation for all screen sizes**
- **Implemented dark/light theme toggle with semantic colors**
- **Created comprehensive settings screen with language/currency testing**
- **Added theme persistence and real-time theme switching**
- **Integrated navigation system with proper routing and back functionality**

### File List

**Presentation Layer:**
- lib/features/products/presentation/screens/product_form_screen.dart
- lib/features/products/presentation/screens/product_variants_screen.dart
- lib/features/products/presentation/widgets/product_form_widget.dart
- lib/features/products/presentation/widgets/variant_management_widget.dart
- lib/features/products/presentation/widgets/money_input_widget.dart
- lib/features/products/presentation/widgets/color_picker_widget.dart
- lib/features/products/presentation/widgets/size_selector_widget.dart
- lib/features/products/presentation/widgets/image_upload_widget.dart
- lib/features/products/presentation/widgets/app_bar_widget.dart
- lib/features/products/presentation/bloc/product_form_bloc.dart
- lib/features/products/presentation/bloc/product_variants_bloc.dart

**Settings Layer:**
- lib/features/settings/presentation/screens/settings_screen.dart
- lib/features/settings/presentation/widgets/language_selector_widget.dart
- lib/features/settings/presentation/widgets/currency_selector_widget.dart
- lib/features/settings/presentation/widgets/theme_toggle_widget.dart
- lib/features/settings/presentation/bloc/settings_bloc.dart

**Theme Layer:**
- lib/core/theme/app_theme.dart
- lib/core/theme/app_colors.dart
- lib/core/theme/theme_service.dart
- lib/core/theme/widgets/theme_toggle_button.dart
- lib/core/theme/bloc/theme_bloc.dart

**Navigation Layer:**
- lib/core/navigation/app_router.dart
- lib/core/navigation/navigation_service.dart
- lib/core/navigation/widgets/small_app_bar_widget.dart

**Data Layer:**
- lib/features/products/data/models/product_variant_model.dart
- lib/features/products/data/models/product_color_model.dart
- lib/features/products/data/models/size_model.dart
- lib/features/products/data/repositories/product_variant_repository_impl.dart
- lib/features/settings/data/models/settings_model.dart
- lib/features/settings/data/repositories/settings_repository_impl.dart
- lib/core/database/daos/product_variant_dao.dart
- lib/core/database/daos/product_color_dao.dart
- lib/core/database/daos/size_dao.dart

**Domain Layer:**
- lib/features/products/domain/entities/product_variant_entity.dart
- lib/features/products/domain/entities/product_color_entity.dart
- lib/features/products/domain/entities/size_entity.dart
- lib/features/products/domain/usecases/create_product_usecase.dart
- lib/features/products/domain/usecases/create_variant_usecase.dart
- lib/features/settings/domain/entities/settings_entity.dart
- lib/features/settings/domain/usecases/update_settings_usecase.dart

**Services Layer:**
- lib/features/products/services/variant_service.dart
- lib/features/products/services/color_service.dart
- lib/features/products/services/size_service.dart
- lib/features/products/services/money_calculation_service.dart
- lib/features/settings/services/settings_service.dart
- lib/core/theme/theme_service.dart
- lib/core/navigation/navigation_service.dart

**Tests:**
- test/features/products/presentation/bloc/product_form_bloc_test.dart
- test/features/products/presentation/bloc/product_variants_bloc_test.dart
- test/features/products/presentation/widgets/money_input_widget_test.dart
- test/features/products/presentation/widgets/variant_management_widget_test.dart
- test/features/settings/presentation/bloc/settings_bloc_test.dart
- test/core/theme/bloc/theme_bloc_test.dart
