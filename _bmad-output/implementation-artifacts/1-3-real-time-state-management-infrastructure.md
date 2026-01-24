# Story 1.3: Real-Time State Management Infrastructure

Status: done

> Objective: Establish a reactive state management foundation using Bloc with Drift streams that automatically updates the UI whenever data changes, eliminating manual refresh requirements throughout the entire application.

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a Developer,
I want to set up a base Bloc pattern with database stream subscriptions,
so that the UI updates automatically whenever data changes.

## Acceptance Criteria

1. **RealtimeService implementation** using Drift streams:
   - Stream-based watchers for all critical tables (products, sales, purchases, customers, suppliers)
   - Efficient query filtering to avoid unnecessary emissions
   - Error handling and retry logic for stream failures
   - Stream debouncing for rapid successive changes

2. **Base Bloc class** with stream subscription handling:
   - Abstract base class `RealtimeBloc<T, E>` for all feature blocs
   - Automatic stream subscription on bloc initialization
   - Stream cancellation on bloc disposal
   - Loading and error states built-in
   - Optimistic update support with rollback capability

3. **Test verification** of real-time updates:
   - Unit test demonstrating database change → Bloc state emission
   - Integration test with UI widget automatically updating
   - Performance test: <100ms from database change to UI update
   - Memory leak test: no retained streams after bloc disposal

## Tasks / Subtasks

- [x] **Create RealtimeService**
  - [x] Implement Drift stream watchers for core tables
  - [x] Add stream filtering and transformation utilities
  - [x] Implement error handling and retry mechanisms
  - [x] Add debouncing for high-frequency updates

- [x] **Build Base RealtimeBloc**
  - [x] Create abstract RealtimeBloc<T, E> class
  - [x] Implement automatic stream subscription lifecycle
  - [x] Add loading, success, and error states
  - [x] Support for optimistic updates with rollback

- [x] **Create Example Implementation**
  - [x] Implement ProductsBloc extending RealtimeBloc
  - [x] Add stream subscription for products table changes
  - [x] Handle product CRUD operations with real-time updates

- [x] **Write Comprehensive Tests**
  - [x] Unit test: RealtimeService stream emissions
  - [x] Unit test: Base Bloc subscription management
  - [x] Integration test: Database → Bloc → UI flow
  - [x] Performance test: Update latency measurement
  - [x] Memory test: Stream cleanup verification

- [x] **Add Documentation**
  - [x] Developer guide for creating new realtime blocs
  - [x] Performance optimization recommendations
  - [x] Troubleshooting guide for common issues

## Dev Notes

### Architecture Alignment

This story builds upon the Clean Architecture established in Story 1.1 and the database schema from Story 1.2:

- **Location**: `lib/core/bloc/` for base classes, `lib/features/{feature}/bloc/` for implementations
- **Dependency**: Uses `flutter_bloc` (8.1.4+) and `drift` (2.23.0+) from validated tech stack
- **Pattern**: Repository → Stream → Bloc → UI (reactive flow)
- **Provider Integration**: Replace existing providers (reactiveSalesProvider, paginatedProductsProvider) with Bloc pattern

### Critical Implementation Details

1. **Stream Management**:
   ```dart
   // Base pattern for all features using Drift streams
   class RealtimeBloc<T, E> extends Bloc<E, T> {
     StreamSubscription? _subscription;
     final Repository _repository;
     
     RealtimeBloc(this._repository) : super(InitialState()) {
       // Subscribe to Drift table changes
       _subscription = _repository.watchAll().listen((data) {
         add(DataUpdated(data));
       });
     }
     
     @override
     Future<void> close() {
       _subscription?.cancel();
       return super.close();
     }
   }
   
   // Example Drift repository implementation
   Stream<List<Product>> watchAllProducts() {
     return (select(products)..where((tbl) => tbl.isActive.equals(true)))
         .watch()
         .map((rows) => rows.map(Product.fromRow).toList());
   }
   ```

2. **Performance Considerations**:
   - Use `distinct()` operator to avoid duplicate emissions
   - Implement `debounceTime()` for rapid successive changes
   - Cache expensive computations in bloc state
   - Target: <100ms from database change to UI update
   - Memory: <10MB overhead for active streams

3. **Error Handling**:
   - Wrap streams in try-catch with error states
   - Implement exponential backoff for reconnection
   - Log all stream errors for debugging
   - Handle platform-specific stream behavior (Web WASM vs native)

### Previous Story Intelligence

From Story 1.2 (Database Schema):
- Database tables are fully defined with proper relationships
- Drift is configured and working across all platforms
- WASM support is verified for web platform

From Story 1.1 (Project Setup):
- Clean Architecture folder structure is established
- flutter_bloc dependency is already added
- Base project structure supports feature-based organization

### Cross-Platform Considerations

**Web (WASM) Specifics:**
- Streams use OPFS/IndexedDB backend (configured in Story 1.2)
- Higher latency for initial stream setup (~50ms vs ~10ms native)
- Memory constraints: limit concurrent streams to <20

**Native Platforms:**
- Direct SQLite file streams with minimal latency
- Can handle 50+ concurrent streams
- Background processing supported

**Unified Approach:**
- Abstract platform differences in RealtimeService
- Use adaptive debouncing based on platform detection
- Fallback to polling if streams fail on Web

### Testing Requirements

- **Unit Tests**: 90% coverage for RealtimeService and BaseBloc
- **Integration Tests**: Verify end-to-end reactive flow
- **Widget Tests**: Confirm UI updates automatically
- **Performance Tests**: <100ms update latency target

### References

- [Source: TAPIX_REBUILD_SPECIFICATION.md#Real-Time-Updates]
- [Source: TAPIX_TECHNICAL_INVENTORY.md#Database-Tables]
- [Source: TAPIX_TECHNICAL_INVENTORY.md#Providers-Inventory]
- [Source: TAPIX_IMPLEMENTATION_CHECKLIST.md#Phase-2-Core-Infrastructure]
- [Source: 1-2-database-schema-implementation.md#Data-Access-Layer]

## Dev Agent Record

### Agent Model Used

Claude Sonnet 3.5 (November 2024)

### Debug Log References

- RealtimeService implementation logs
- Bloc subscription lifecycle logs
- Performance measurement logs

### Completion Notes List

- RealtimeService handles all core table streams (products, sales, purchases, customers, suppliers, categories, variants)
- RealtimeBloc provides consistent pattern across features with built-in states
- Performance targets met (<100ms update latency verified in tests)
- Money values are stored and retrieved using integer cents semantics
- Comprehensive test coverage achieved with focused suites passing
- Documentation completed for developer onboarding in `docs/realtime-bloc-guide.md`
- Platform-adaptive configuration for Web WASM vs Native
- Optimistic update support with automatic rollback on failure

### File List

- `lib/core/bloc/realtime_bloc.dart` - Base reactive bloc class with states and events
- `lib/core/services/realtime_service.dart` - Stream management service with debouncing and retry
- `lib/features/products/presentation/bloc/products_bloc.dart` - Example implementation
- `test/core/bloc/realtime_bloc_test.dart` - Base bloc tests (21 tests)
- `test/core/services/realtime_service_test.dart` - Service tests (14 tests)
- `test/integration/realtime_updates_test.dart` - End-to-end tests (9 tests)
- `test/features/products/bloc/products_bloc_test.dart` - ProductsBloc tests (14 tests)
- `docs/realtime-bloc-guide.md` - Developer documentation

## Change Log

- 2026-01-24: Story 1.3 implemented - Real-time state management infrastructure complete
- 2026-01-24: Code review completed - All issues fixed (5 HIGH, 2 MEDIUM, 1 LOW)
- 2026-01-24: All implementation files committed to version control
- 2026-01-24: All tests passing (58 total tests across 4 test suites)
