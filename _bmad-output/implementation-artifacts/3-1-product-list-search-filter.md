# Story 3.1: product-list-search-filter

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a User,
I want to view, search, and filter products,
so that I can quickly find items.

## Acceptance Criteria

1. [x] List displays name, price, stock, and image
2. [x] Search by name, SKU, or barcode
3. [x] Filter by category, supplier, or stock status (low/out)
4. [x] Pagination/Infinite scroll for large datasets

## Tasks / Subtasks

- [x] Task 1: Implement product list UI (AC: 1)
  - [x] Subtask 1.1: Create product list widget with image, name, price, stock display
  - [x] Subtask 1.2: Implement responsive grid/list layout
  - [x] Subtask 1.3: Add loading states and empty state handling
- [x] Task 2: Implement search functionality (AC: 2)
  - [x] Subtask 2.1: Create search input field with real-time filtering
  - [x] Subtask 2.2: Implement search logic for name, SKU, barcode
  - [x] Subtask 2.3: Add search debouncing for performance
- [x] Task 3: Implement filtering system (AC: 3)
  - [x] Subtask 3.1: Create filter UI for category, supplier, stock status
  - [x] Subtask 3.2: Implement filter logic with multiple criteria
  - [x] Subtask 3.3: Add active filter indicators and clear filters
- [x] Task 4: Implement pagination/infinite scroll (AC: 4)
  - [x] Subtask 4.1: Add pagination controls or infinite scroll detection
  - [x] Subtask 4.2: Implement efficient data loading with pagination
  - [x] Subtask 4.3: Add loading indicators for pagination

## Dev Notes

### Project Structure Notes

- **Feature Location**: `lib/features/products/`
- **Bloc Pattern**: Must extend `RealtimeBloc` for real-time updates
- **Database**: Use Drift with `products` table from TAPIX_TECHNICAL_INVENTORY.md
- **Real-time Updates**: Product list must auto-update when database changes

### Architecture Compliance

**Clean Architecture Structure:**
```
lib/features/products/
├── data/
│   ├── models/
│   │   └── product_model.dart
│   ├── repositories/
│   │   └── product_repository.dart
│   └── datasources/
│       └── product_datasource.dart
├── domain/
│   ├── entities/
│   │   └── product.dart
│   └── repositories/
│       └── product_repository_interface.dart
├── presentation/
│   ├── bloc/
│   │   └── products_bloc.dart
│   ├── screens/
│   │   └── product_list_screen.dart
│   └── widgets/
│       ├── product_list_widget.dart
│       ├── product_search_widget.dart
│       └── product_filter_widget.dart
└── services/
    └── product_service.dart
```

**Bloc Requirements:**
- Extend `RealtimeBloc<List<Product>, ProductsEvent>`
- Use `RealtimeService` for database stream subscriptions
- Implement proper loading, success, and error states
- Handle optimistic updates for better UX

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

### Real-time State Management

**Must Use RealtimeBloc Pattern:**
```dart
class ProductsBloc extends RealtimeBloc<List<Product>, ProductsEvent> {
  @override
  Stream<List<Product>> get dataStream => _productService.watchProducts();
  
  // Handle search/filter events
  // Maintain search/filter state
  // Auto-update on database changes
}
```

### UI/UX Requirements

**Responsive Design System:**
- **Mobile (<600px)**: Single column list, bottom sheet filters, full-width search
- **Tablet (600-1200px)**: 2-column grid, side drawer filters, floating search bar
- **Desktop (>1200px)**: 3-4 column grid, persistent filter sidebar, keyboard shortcuts
- **Material 3 Adaptive Containers**: Use `LayoutBuilder` with breakpoint-specific layouts
- **Smooth Layout Transitions**: Animated transitions between breakpoints (300ms ease)

**Material Design Compliance:**
- Use `flex_color_scheme` for theming with semantic colors
- **Semantic Colors**: Green (Success), Orange (Warning), Red (Error)
- Loading skeletons/shimmers during data fetch using `shimmer` package
- Pull-to-refresh with custom `RefreshIndicator` and branding
- **Micro-interactions**: Product card scale animations, filter chip transitions

**Accessibility Requirements:**
- **Screen Reader Support**: `semantics` labels for all interactive elements
- **Keyboard Navigation**: Full keyboard tab order and shortcuts (Ctrl+K search, Ctrl+F filter)
- **High Contrast**: Support for system high contrast mode
- **Text Scaling**: Support for system font scaling up to 200%
- **Focus Management**: Visible focus indicators and logical tab order
- **Voice Over**: iOS VoiceOver and Android TalkBack compatibility

**Search UI:**
- Search field with clear button and voice search icon (mobile)
- Real-time search with debouncing (300ms) and result highlighting
- Search history with recent searches (persisted locally)
- Keyboard shortcuts (Ctrl+K desktop, Cmd+K macOS)
- Camera barcode scanning integration with `mobile_scanner`
- Fuzzy matching with typo tolerance and phonetic search

**Filter UI:**
- **Mobile**: Bottom sheet with filter chips and clear all option
- **Tablet**: Side drawer with collapsible filter sections
- **Desktop**: Persistent sidebar with advanced filter options
- Filter chips with active state indicators and count badges
- Real-time filter application with smooth list transitions
- Filter persistence across app sessions

**List UI:**
- **Mobile**: Single column with swipe actions (edit/delete)
- **Tablet**: 2-column grid with hover effects
- **Desktop**: 3-4 column grid with keyboard navigation
- Product images with `cached_network_image` and placeholder handling
- Stock status indicators with color-coded badges
- Price formatting with currency symbols and locale support
- Product card hover states with quick action buttons

### Performance Requirements

**Cross-Platform Performance Matrix:**
- **Web WASM**: Virtual scrolling with `flutter_list_view` (1000+ items), pagination fallback
- **Mobile**: Infinite scroll with memory limit (500 items cached), image lazy loading
- **Desktop**: Keyboard shortcuts, hover states, multi-threaded search processing
- **Memory Limits**: Mobile <100MB, Tablet <200MB, Desktop <500MB

**Pagination Strategy:**
- **Mobile**: Infinite scroll with threshold (5 items left), 20 items per page
- **Tablet**: Hybrid pagination (load more button + infinite scroll option)
- **Desktop**: Virtual scrolling with configurable page size (20-50 items)
- **Database**: Efficient queries with LIMIT/OFFSET and indexed fields
- **Memory Management**: Automatic cleanup of off-screen items

**Search Performance:**
- Debounced search input (300ms) with cancellation on rapid changes
- **Database Indexes**: `products(name)`, `products(sku)`, `products(barcode)`
- **Search Algorithm**: Full-text search with ranking and fuzzy matching
- **Caching**: LRU cache for frequent searches (max 100 queries)
- **Background Processing**: Isolates for heavy search operations

**Real-time Performance:**
- **Stream Debouncing**: 50ms native, 100ms web (WASM limitations)
- **Memory Management**: <10MB overhead for active streams
- **Update Latency**: <100ms from DB change to UI update
- **Batch Updates**: Coalesce multiple rapid changes into single UI update
- **Platform Adaptation**: Different stream strategies per platform

### Localization Requirements

**Multi-language Support:**
- Product names in EN/AR/FR with intelligent fallback (EN → AR → FR)
- **RTL Layout**: Full RTL support for Arabic with `Directionality` widgets
- **Dynamic Font Scaling**: Per-language font size optimization
- **Text Overflow**: Ellipsis handling for long product names in all languages
- **Number Formatting**: Locale-specific currency and number formatting

**Typography System:**
- **Arabic**: IBM Plex Sans Arabic with proper RTL kerning
- **Latin**: IBM Plex Sans with optimal line height
- **Font Weights**: 300-700 range with language-specific optimization
- **Text Alignment**: RTL right-align for Arabic, LTR left-align for EN/FR

**Keys to Implement:**
```dart
// app_en.arb
"products_list_title": "Products",
"products_search_hint": "Search products...",
"products_search_voice": "Voice Search",
"products_filter_category": "Category",
"products_filter_supplier": "Supplier",
"products_filter_stockStatus": "Stock Status",
"products_out_of_stock": "Out of Stock",
"products_low_stock": "Low Stock",
"products_no_results": "No products found",
"products_loading": "Loading products...",
"products_search_placeholder": "Try searching for product names, SKUs, or barcodes",
"products_filter_active": "{count} active filters",
"products_clear_all_filters": "Clear All Filters"

// app_ar.arb (RTL)
"products_list_title": "المنتجات",
"products_search_hint": "البحث في المنتجات...",
"products_search_voice": "البحث بالصوت",
"products_filter_category": "الفئة",
"products_filter_supplier": "المورد",
"products_filter_stockStatus": "حالة المخزون",
"products_out_of_stock": "نفد المخزون",
"products_low_stock": "مخزون منخفض",
"products_no_results": "لم يتم العثور على منتجات",
"products_loading": "جاري تحميل المنتجات...",
"products_search_placeholder": "جرب البحث عن أسماء المنتجات أو رموز المنتجات أو الباركود",
"products_filter_active": "{count} فلاتر نشطة",
"products_clear_all_filters": "مسح جميع الفلاتر"

// app_fr.arb
"products_list_title": "Produits",
"products_search_hint": "Rechercher des produits...",
"products_search_voice": "Recherche Vocale",
"products_filter_category": "Catégorie",
"products_filter_supplier": "Fournisseur",
"products_filter_stockStatus": "État du Stock",
"products_out_of_stock": "Rupture de Stock",
"products_low_stock": "Stock Faible",
"products_no_results": "Aucun produit trouvé",
"products_loading": "Chargement des produits...",
"products_search_placeholder": "Essayez de rechercher des noms de produits, SKU ou codes-barres",
"products_filter_active": "{count} filtres actifs",
"products_clear_all_filters": "Effacer Tous les Filtres"
```

### Testing Requirements

**Unit Tests:**
- ProductsBloc event handling with platform-specific logic
- Search algorithm with fuzzy matching and ranking
- Filter combinations with complex criteria
- Pagination logic with different strategies per platform
- Responsive breakpoint calculations
- Accessibility helper functions

**Widget Tests:**
- Product list widget rendering across all breakpoints
- Search input functionality with voice and barcode
- Filter UI interactions on mobile/tablet/desktop
- Loading states and skeleton animations
- Keyboard navigation and focus management
- Screen reader semantics

**Integration Tests:**
- Real-time updates simulation with stream debouncing
- Search performance with large datasets (1000+ items)
- Filter performance with complex combinations
- Pagination with database limits and virtual scrolling
- Cross-platform performance benchmarks
- Accessibility compliance verification

**Performance Tests:**
- Memory usage under load (mobile/tablet/desktop)
- Search response time with debouncing
- Scroll performance with large lists
- Real-time update latency measurement
- Web WASM performance optimization

**Accessibility Tests:**
- Screen reader compatibility (VoiceOver/TalkBack)
- Keyboard navigation completeness
- High contrast mode support
- Text scaling up to 200%
- Focus management and visual indicators

### File Structure Requirements

**Create these files:**
```
lib/features/products/
├── data/
│   ├── models/product_model.dart
│   ├── repositories/product_repository_impl.dart
│   └── datasources/product_local_datasource.dart
├── domain/
│   ├── entities/product.dart
│   ├── repositories/product_repository.dart
│   └── usecases/
│       ├── get_products_usecase.dart
│       ├── search_products_usecase.dart
│       └── filter_products_usecase.dart
├── presentation/
│   ├── bloc/
│   │   ├── products_bloc.dart
│   │   ├── products_event.dart
│   │   └── products_state.dart
│   ├── screens/
│   │   └── product_list_screen.dart
│   └── widgets/
│       ├── product_list_widget.dart
│       ├── product_tile_widget.dart
│       ├── product_search_widget.dart
│       └── product_filter_widget.dart
└── services/
    └── product_service.dart
```

### Dependencies

**Required Packages:**
- `flutter_bloc: ^9.1.1` - State management with RealtimeBloc extension
- `drift: ^2.23.0` - Database ORM with real-time streams
- `flex_color_scheme: ^8.0.0` - Material 3 theming with semantic colors
- `easy_localization: ^3.0.7` - Multi-language support with RTL
- `cached_network_image: ^3.3.1` - Optimized image loading and caching
- `shimmer: ^3.0.0` - Loading skeleton animations
- `mobile_scanner: ^7.1.4` - Barcode scanning integration
- `responsive_framework: ^1.1.0` - Responsive design utilities
- `flutter_list_view: ^1.0.0` - Virtual scrolling for large datasets (Web)
- `voice_search_package: ^1.0.0` - Voice search integration (Mobile)
- `flutter_keyboard_visibility: ^6.0.0` - Keyboard management
- `accessibility_package: ^1.0.0` - Accessibility utilities

**Platform-Specific Dependencies:**
- **Web**: `flutter_list_view` for virtual scrolling performance
- **Mobile**: `mobile_scanner` for camera barcode scanning
- **Desktop**: `window_manager` for keyboard shortcuts

**Implementation Order:**
1. **Foundation**: Set up responsive framework and accessibility
2. **Data Layer**: Models, repository, datasource with indexing
3. **Domain Layer**: Entities and use cases with search logic
4. **State Management**: RealtimeBloc with platform-specific optimizations
5. **UI Components**: Responsive widgets with micro-interactions
6. **Real-time Integration**: Stream subscriptions with debouncing
7. **Search System**: Advanced search with voice and barcode
8. **Filter System**: Responsive filter UI with persistence
9. **Performance**: Virtual scrolling and caching strategies
10. **Localization**: Multi-language support with RTL optimization
11. **Accessibility**: Screen reader and keyboard navigation
12. **Testing**: Comprehensive unit, widget, and integration tests

### Advanced Features

**Caching Strategy:**
- **Image Cache**: `cached_network_image` with 30-day expiration and memory limit
- **Search Cache**: LRU cache for frequent searches with 100 query limit
- **Filter Cache**: Persistent filter state across app sessions
- **Offline Support**: Cached product data for offline browsing

**Analytics Integration:**
- **Search Analytics**: Track search queries, results count, and user selections
- **Filter Analytics**: Monitor filter usage and combinations
- **Performance Monitoring**: Track load times, memory usage, and errors
- **User Behavior**: Product view patterns and interaction metrics

**Beautiful Micro-interactions:**
- **Product Cards**: Scale animation on hover (0.95x to 1.0x in 150ms)
- **Filter Chips**: Smooth color transitions when activated/deactivated
- **Search Input**: Focus animation with subtle glow effect
- **Loading Skeletons**: Shimmer effect with wave animation
- **Pull-to-Refresh**: Custom branded animation with logo
- **List Transitions**: Staggered fade-in animations for new items

**Error Handling:**
- **Network Errors**: Graceful fallback with cached data
- **Search Errors**: User-friendly error messages with suggestions
- **Performance Errors**: Automatic fallback to simpler UI
- **Accessibility Errors**: Fallback text alternatives

## Dev Agent Record

### Agent Model Used

Cascade (SWE-1.5)

### Debug Log References

### Completion Notes List

- Implemented all 4 acceptance criteria successfully
- Added barcode search functionality with dialog input (AC2)
- Implemented stock status filtering (out of stock, low stock) (AC3)
- Added category filter UI with bottom sheet (AC3)
- Implemented infinite scroll pagination with 50 items per page (AC4)
- Enhanced ProductDao with filtering and pagination methods
- Created comprehensive unit tests for ProductsBloc
- Created widget tests for ProductTileWidget
- All tests passing with proper coverage of core functionality

### File List

**Presentation Layer:**
- lib/features/products/presentation/screens/product_list_screen.dart
- lib/features/products/presentation/widgets/product_search_widget.dart
- lib/features/products/presentation/widgets/product_filter_widget.dart
- lib/features/products/presentation/widgets/product_tile_widget.dart
- lib/features/products/presentation/bloc/products_bloc.dart

**Data Layer:**
- lib/features/products/data/repositories/product_repository.dart
- lib/core/database/daos/product_dao.dart

**Domain Layer:**
- lib/features/products/domain/entities/product_entity.dart

**Core Infrastructure:**
- lib/core/di/injection_container.dart
- lib/core/router/app_router.dart

**Tests:**
- test/features/products/presentation/bloc/products_bloc_test.dart
- test/features/products/presentation/widgets/product_tile_widget_test.dart
